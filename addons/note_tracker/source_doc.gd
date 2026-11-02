@tool
extends RefCounted
# Reads an open script from the editor so changes use native undo.
# Reads other scripts from disk.

var path: String
var lines: PackedStringArray
var _code_edit: CodeEdit
var _crlf := false

static func open_buffers() -> Dictionary:
  # get_open_scripts() skips non-script tabs (text files) while
  # get_open_script_editors() does not, so the two only line up when sizes match.
  var result := {}
  var se := EditorInterface.get_script_editor()
  var scripts := se.get_open_scripts()
  var editors := se.get_open_script_editors()
  if scripts.size() != editors.size():
    return result
  for i in scripts.size():
    var ce := editors[i].get_base_editor() as CodeEdit
    if ce and not scripts[i].resource_path.is_empty():
      result[scripts[i].resource_path] = ce
  return result

static func load_doc(file_path: String, buffers := {}) -> RefCounted:
  var doc = load("res://addons/note_tracker/source_doc.gd").new()
  doc.path = file_path
  if buffers.is_empty():
    buffers = open_buffers()
  if buffers.has(file_path):
    doc._code_edit = buffers[file_path]
    doc.lines = doc._code_edit.text.split("\n")
    return doc
  if not FileAccess.file_exists(file_path):
    return null
  var text := FileAccess.get_file_as_string(file_path)
  doc._crlf = text.contains("\r\n")
  doc.lines = text.replace("\r\n", "\n").split("\n")
  return doc

func begin() -> void:
  if _code_edit:
    _code_edit.begin_complex_operation()

func set_line(i: int, text: String) -> void:
  lines[i] = text
  if _code_edit:
    _code_edit.set_line(i, text)

func remove_line(i: int) -> void:
  lines.remove_at(i)
  if _code_edit:
    _code_edit.remove_line_at(i, false)

func insert_line(i: int, text: String) -> void:
  if _code_edit:
    if i < _code_edit.get_line_count():
      _code_edit.insert_line_at(i, text)
    else:
      var last := _code_edit.get_line_count() - 1
      _code_edit.insert_text("\n" + text, last, _code_edit.get_line(last).length())
  lines.insert(i, text)

func commit() -> bool:
  if _code_edit:
    _code_edit.end_complex_operation()
    return true
  var text := "\n".join(lines)
  if _crlf:
    text = text.replace("\n", "\r\n")
  var f := FileAccess.open(path, FileAccess.WRITE)
  if f == null:
    push_error("Note Tracker: cannot write %s" % path)
    return false
  f.store_string(text)
  f.close()
  # Keep any cached Script resource in sync so the editor doesn't hold stale source.
  if ResourceLoader.has_cached(path):
    var script := load(path) as Script
    if script:
      script.source_code = "\n".join(lines)
  EditorInterface.get_resource_filesystem().update_file(path)
  return true

# Index of `line_text` nearest to `hint`, or -1.
func find_line(line_text: String, hint: int) -> int:
  if hint >= 0 and hint < lines.size() and lines[hint] == line_text:
    return hint
  var best := -1
  for i in lines.size():
    if lines[i] == line_text and (best < 0 or absi(i - hint) < absi(best - hint)):
      best = i
  return best
