@tool
extends Node

signal finished(note: Dictionary, reference: Dictionary, message: String)

const PREFIX := "addons/note-tracker/"
const STORE := "res://.godot/note_tracker/issues.json"
var token := ""
var busy := false
var references: Dictionary = {}
var _request: HTTPRequest
var _note: Dictionary = {}
var _key := ""
var _repository := ""


static func setup_settings() -> void:
  var defaults := {"enable_github": false, "github_repository": "", "should_auto_archive": true, "add_issue_reference": true}
  for key in defaults:
    var setting: String = PREFIX + key
    if not ProjectSettings.has_setting(setting):
      ProjectSettings.set_setting(setting, defaults[key])
    ProjectSettings.set_initial_value(setting, defaults[key])
    ProjectSettings.set_as_basic(setting, true)
    var info := {"name": setting, "type": typeof(defaults[key])}
    if key == "github_repository":
      info.hint = PROPERTY_HINT_PLACEHOLDER_TEXT
      info.hint_string = "owner/repository"
    ProjectSettings.add_property_info(info)

  # Never store the legacy plaintext credential setting.
  if ProjectSettings.has_setting(PREFIX + "github_api_key"):
    ProjectSettings.set_setting(PREFIX + "github_api_key", null)
    ProjectSettings.save()


static func setting(key: String, fallback: Variant) -> Variant:
  return ProjectSettings.get_setting(PREFIX + key, fallback)


static func note_key(note: Dictionary) -> String:
  return (str(note.path) + "\n" + str(note.line_text)).sha256_text()


static func issue_title(text: String) -> String:
  var normalized := " ".join(text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false))
  if normalized.is_empty():
    normalized = "Code note"
  return normalized if normalized.length() <= 80 else normalized.left(79) + "…"


static func issue_body(note: Dictionary) -> String:
  return "%s\n\n---\nFile: `%s`\nLine: %d\nTag: %s\n" % [note.text, str(note.path).trim_prefix("res://"), int(note.line) + 1, note.tag]


func _ready() -> void:
  var data = JSON.parse_string(FileAccess.get_file_as_string(STORE)) if FileAccess.file_exists(STORE) else null
  if data is Dictionary:
    references = data
  _request = HTTPRequest.new()
  _request.timeout = 30.0
  _request.max_redirects = 0 # Never forward Authorization to a redirect target.
  _request.body_size_limit = 1024 * 1024
  add_child(_request)
  _request.request_completed.connect(_completed)


func _exit_tree() -> void:
  token = ""
  if is_instance_valid(_request):
    _request.cancel_request()


func save() -> bool:
  if DirAccess.make_dir_recursive_absolute(STORE.get_base_dir()) != OK:
    return false
  
  var file := FileAccess.open(STORE, FileAccess.WRITE)
  if file == null:
    return false
  file.store_string(JSON.stringify(references))
  file.close()
  return true


func create_issue(note: Dictionary, title: String) -> String:
  if busy:
    return "An issue request is already running."
  if not setting("enable_github", false):
    return "Enable GitHub in Project Settings > Addons > Note-tracker."
  
  _repository = str(setting("github_repository", "")).strip_edges()
  if RegEx.create_from_string("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$").search(_repository) == null:
    return "Set the repository to owner/repository in Project Settings."
  if token.is_empty() or token.contains("\n") or token.contains("\r"):
    return "Enter a valid session token using the GitHub button in the Notes toolbar."
  if title.strip_edges().is_empty() or title.length() > 80:
    return "Enter a title between 1 and 80 characters."
  
  _key = note_key(note)
  if references.has(_key):
    return "This note already has an issue or an unresolved request."
  _note = note.duplicate(true)
  references[_key] = {"state": "unknown", "repository": _repository}
  
  if not save():
    references.erase(_key)
    return "Cannot save issue tracking data; no request was sent."
  
  busy = true
  var headers := PackedStringArray(["Authorization: Bearer " + token, "Accept: application/vnd.github+json", "Content-Type: application/json", "User-Agent: Godot-Note-Tracker", "X-GitHub-Api-Version: 2022-11-28"])
  var error := _request.request("https://api.github.com/repos/" + _repository + "/issues", headers, HTTPClient.METHOD_POST, JSON.stringify({"title": title.strip_edges(), "body": issue_body(note)}))
  
  if error != OK:
    busy = false
    references.erase(_key)
    save()
    return "Could not start the GitHub request. No issue was created."
  return ""


func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
  busy = false
  var parser := JSON.new()
  var parsed := parser.parse(body.get_string_from_utf8()) if not body.is_empty() else ERR_PARSE_ERROR
  var data = parser.data if parsed == OK else null
  
  if result == HTTPRequest.RESULT_SUCCESS and code == 201 and data is Dictionary:
    var url := str(data.get("html_url", ""))
    var number := int(data.get("number", 0))
    if number > 0 and url == "https://github.com/%s/issues/%d" % [_repository, number]:
      var reference := {"provider": "github", "repository": _repository, "number": number, "url": url, "state": "created"}
      references[_key] = reference
      var saved := save()
      finished.emit(_note, reference, "" if saved else "Issue created, but its local reference could not be saved. Copy the URL before closing.")
      return
  
  # A transport failure, unexpected success, or server error may have created an issue.
  if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code < 400:
    finished.emit(_note, {}, "Result uncertain. Check GitHub before retrying; the issue may already exist.")
    return
  references.erase(_key)
  save()

  var message := "GitHub rejected the request (HTTP %d)." % code
  match code:
    401: message += " Check whether your token has expired."
    403: message += " Check Issues write permission, organization approval, and rate limits."
    404: message += " Check the repository name and token repository access."
    410: message += " Issues may be disabled for this repository."
    422: message += " GitHub could not accept the issue."
  # Never display raw response bodies or headers: they can contain credentials.
  finished.emit(_note, {}, message)
