@tool
extends VBoxContainer
# Shows notes by tag and lets you edit, complete, and restore them.

const GitHubIssues = preload("res://addons/note_tracker/github_issues.gd")
const Scanner = preload("res://addons/note_tracker/scanner.gd")
const NoteActions = preload("res://addons/note_tracker/note_actions.gd")
const TAGS: PackedStringArray = ["todo", "hack", "note", "info"]
const TAG_COLORS := {
  todo = Color("ffb454"),
  hack = Color("f55151"),
  note = Color("6cb6ff"),
  info = Color("7ee787"),
}

enum { COL_DONE, COL_TAG, COL_TEXT, COL_LOCATION }

var actions := NoteActions.new()
var notes: Array = []
var filter := ""

var github := GitHubIssues.new()
var _issue_dialog: ConfirmationDialog
var _issue_title: LineEdit
var _issue_preview: Label
var _archive_issue: CheckBox
var _reference_issue: CheckBox
var _issue_note: Dictionary = {}
var _request_archive := false
var _request_reference := false
var _status: AcceptDialog
var _token_dialog: AcceptDialog
var _token_input: LineEdit

var _filter_bar: HBoxContainer
var _dropdown: OptionButton
var _tree: Tree
var _done_tree: Tree
var _done_label: Label
var _rescan_timer: Timer


func _ready() -> void:
  name = "Notes"
  size_flags_vertical = SIZE_EXPAND_FILL

  add_child(github)
  github.finished.connect(_on_issue_finished)
  _setup_github_dialogs()
  ProjectSettings.settings_changed.connect(queue_rescan)

  var toolbar := HBoxContainer.new()
  add_child(toolbar)
  _filter_bar = HBoxContainer.new()
  _filter_bar.size_flags_horizontal = SIZE_EXPAND_FILL
  toolbar.add_child(_filter_bar)

  var refresh := Button.new()
  refresh.flat = true
  refresh.icon = _icon("Reload")
  refresh.tooltip_text = "Rescan project"
  refresh.pressed.connect(rescan)
  toolbar.add_child(refresh)
  var credentials := Button.new()
  credentials.text = "GitHub"
  credentials.tooltip_text = "Set or clear the GitHub token for this editor session only"
  credentials.pressed.connect(func():
    _token_input.clear()
    _token_input.placeholder_text = "Token already set; enter a replacement" if not github.token.is_empty() else "Fine-grained personal access token"
    _token_dialog.popup_centered(Vector2i(460, 160))
  )
  toolbar.add_child(credentials)

  var split := VSplitContainer.new()
  split.size_flags_vertical = SIZE_EXPAND_FILL
  add_child(split)

  _tree = _make_tree(["", "Tag", "Note", "Location"])
  _tree.set_column_expand(COL_DONE, false)
  _tree.set_column_custom_minimum_width(COL_DONE, 28)
  _tree.button_clicked.connect(_on_issue_button_clicked)
  _tree.item_edited.connect(_on_item_edited)
  _tree.item_activated.connect(_on_item_activated)
  split.add_child(_tree)

  var done_box := VBoxContainer.new()
  split.add_child(done_box)

  var done_header := HBoxContainer.new()
  done_box.add_child(done_header)
  _done_label = Label.new()
  _done_label.size_flags_horizontal = SIZE_EXPAND_FILL
  done_header.add_child(_done_label)

  var clear := Button.new()
  clear.text = "Clear"
  clear.flat = true
  clear.tooltip_text = "Forget recently done notes (they can no longer be restored)"
  clear.pressed.connect(func(): actions.clear_done(); _refresh_done())
  done_header.add_child(clear)
  _done_tree = _make_tree(["", "Tag", "Note", "Location", "Done"])
  _done_tree.set_column_expand(0, false)
  _done_tree.set_column_custom_minimum_width(0, 28)
  _done_tree.custom_minimum_size.y = 90
  _done_tree.button_clicked.connect(_on_done_button_clicked)
  _done_tree.item_activated.connect(_on_done_activated)
  done_box.add_child(_done_tree)

  _rescan_timer = Timer.new()
  _rescan_timer.one_shot = true
  _rescan_timer.wait_time = 0.3
  _rescan_timer.timeout.connect(rescan)
  add_child(_rescan_timer)

  rescan()

# Debounced rescan, for noisy editor signals.
func queue_rescan() -> void:
  if is_node_ready():
    _rescan_timer.start()

func rescan() -> void:
  notes = Scanner.scan_project(TAGS)
  _rebuild_filters()
  _refresh_notes()
  _refresh_done()

func _rebuild_filters() -> void:
  for child in _filter_bar.get_children():
    child.queue_free()

  var counts := {}
  for note in notes:
    counts[note.tag] = counts.get(note.tag, 0) + 1

  var tags := PackedStringArray()
  for tag in TAGS:
    tag = tag.strip_edges().trim_prefix("@").to_lower()
    if not tag.is_empty() and tag not in tags:
      tags.append(tag)

  if filter not in tags:
    filter = ""

  _dropdown = OptionButton.new()
  _dropdown.item_selected.connect(_on_filter_item_selected)
  _dropdown.add_item("Show All")
  for tag in tags:
    _dropdown.add_item(tag)
    
  _dropdown.select(0 if filter.is_empty() else tags.find(filter) + 1)
  _filter_bar.add_child(_dropdown)


func _on_filter_item_selected(index: int) -> void:
  if index == 0:
    filter = ""
  else:
    var selected_text = _dropdown.get_item_text(index)
    filter = selected_text
  _refresh_notes()
  
func _refresh_notes() -> void:
  _tree.clear()
  var root := _tree.create_item()
  for note in notes:
    if not filter.is_empty() and note.tag != filter:
      continue

    var item := _tree.create_item(root)
    item.set_metadata(0, note)
    item.set_cell_mode(COL_DONE, TreeItem.CELL_MODE_CHECK)
    item.set_editable(COL_DONE, true)
    item.set_tooltip_text(COL_DONE, "Mark done (removes the comment)")

    _fill_common(item, note, note.line)
    item.set_editable(COL_TEXT, true)
    item.set_tooltip_text(COL_TEXT, note.text)
    var reference: Dictionary = github.references.get(GitHubIssues.note_key(note), {})
    if not reference.is_empty():
      item.add_button(COL_LOCATION, _icon("ExternalLink"), 1, github.busy, "Open linked issue" if reference.has("url") else "Request uncertain: check GitHub before retrying")
    elif GitHubIssues.setting("enable_github", false):
      item.add_button(COL_LOCATION, _icon("Add"), 0, github.busy, "Create GitHub issue")

func _refresh_done() -> void:
  _done_tree.clear()
  _done_label.text = "Recently done (%d)" % actions.done.size()

  var root := _done_tree.create_item()
  var now := int(Time.get_unix_time_from_system())
  for action in actions.done:
    var item := _done_tree.create_item(root)
    item.set_metadata(0, action)
    item.add_button(0, _icon("UndoRedo"), 0, false, "Restore this comment")
    _fill_common(item, action, int(action.line))

    var reference: Dictionary = action.get("issue_reference", {})
    if reference.has("url"):
      item.add_button(COL_LOCATION, _icon("ExternalLink"), 1, false, reference.url)
    item.set_text(4, _ago(now - int(action.time)))
    for col in range(0, 5):
      item.set_custom_color(col, get_theme_color("font_disabled_color", "Editor"))

func _fill_common(item: TreeItem, comment: Dictionary, line: int) -> void:
  item.set_text(COL_TAG, comment.tag)
  item.set_custom_color(COL_TAG, TAG_COLORS.get(comment.tag, get_theme_color("font_color", "Editor")))
  item.set_text(COL_TEXT, comment.text)
  item.set_text(COL_LOCATION, "%s:%d" % [comment.path.trim_prefix("res://"), line + 1])
  item.set_tooltip_text(COL_LOCATION, "Double-click to open")


func _on_item_edited() -> void:
  var item := _tree.get_edited()
  var note: Dictionary = item.get_metadata(0)
  match _tree.get_edited_column():
    COL_DONE:
      if item.is_checked(COL_DONE):
        actions.complete(note)
    COL_TEXT:
      actions.edit_text(note, item.get_text(COL_TEXT))

  # rebuilding the tree inside its own edit signal is unsafe.
  rescan.call_deferred()


func _on_item_activated() -> void:
  var item := _tree.get_selected()
  if item == null:
    return
  if _tree.get_column_at_position(_tree.get_local_mouse_position()) == COL_TEXT:
    _tree.edit_selected(true)
  else:
    _jump(item.get_metadata(0))


func _on_done_button_clicked(item: TreeItem, _column: int, _id: int, _mouse: int) -> void:
  if _id == 1:
    _open_issue(item.get_metadata(0).get("issue_reference", {}))
    return
  actions.restore(item.get_metadata(0))
  rescan.call_deferred()


func _on_done_activated() -> void:
  var item := _done_tree.get_selected()
  if item:
    _jump(item.get_metadata(0))


func _jump(n: Dictionary) -> void:
  var script := load(n.path) as Script
  if script:
    EditorInterface.set_main_screen_editor("Script")
    EditorInterface.edit_script(script, int(n.line) + 1, int(n.get("hash_col", 0)))


func _make_tree(titles: Array) -> Tree:
  var tree := Tree.new()
  tree.size_flags_vertical = SIZE_EXPAND_FILL
  tree.hide_root = true
  tree.select_mode = Tree.SELECT_ROW
  tree.columns = titles.size()
  tree.column_titles_visible = true

  for col in titles.size():
    tree.set_column_title(col, titles[col])
    tree.set_column_expand(col, col == COL_TEXT)
    tree.set_column_clip_content(col, true)

  tree.set_column_custom_minimum_width(COL_TAG, 60)
  tree.set_column_custom_minimum_width(COL_LOCATION, 160)
  return tree


func _icon(icon_name: String) -> Texture2D:
  return EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")


static func _ago(seconds: int) -> String:
  if seconds < 60:
    return "just now"
  if seconds < 3600:
    return "%dm ago" % (seconds / 60)
  if seconds < 86400:
    return "%dh ago" % (seconds / 3600)
  return "%dd ago" % (seconds / 86400)


func _setup_github_dialogs() -> void:
  _status = AcceptDialog.new()
  _status.title = "GitHub issue"
  add_child(_status)

  _token_dialog = AcceptDialog.new()
  _token_dialog.title = "GitHub token — session only"
  var token_box := VBoxContainer.new()

  _token_dialog.add_child(token_box)
  var help := Label.new()
  help.text = "Stored in memory only. Use Issues: read and write for your repository."
  token_box.add_child(help)
  _token_input = LineEdit.new()
  _token_input.secret = true
  _token_input.context_menu_enabled = false
  token_box.add_child(_token_input)
  _token_dialog.confirmed.connect(func():
    if not _token_input.text.strip_edges().is_empty():
      github.token = _token_input.text.strip_edges()
    _token_input.clear()
  )
  _token_dialog.canceled.connect(func(): _token_input.clear())
  _token_dialog.add_button("Clear stored token", true, "clear")
  _token_dialog.custom_action.connect(func(_action: StringName):
    github.token = ""
    _token_input.clear()
    _token_dialog.hide()
  )
  add_child(_token_dialog)

  _issue_dialog = ConfirmationDialog.new()
  _issue_dialog.title = "Create GitHub issue"
  _issue_dialog.ok_button_text = "Create issue"

  var box := VBoxContainer.new()
  _issue_dialog.add_child(box)
  _issue_title = LineEdit.new()
  _issue_title.max_length = 80
  box.add_child(_issue_title)
  _issue_preview = Label.new()
  _issue_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  _issue_preview.custom_minimum_size = Vector2(480, 100)
  box.add_child(_issue_preview)
  _archive_issue = CheckBox.new()
  _archive_issue.text = "Archive comment after issue creation"
  box.add_child(_archive_issue)
  _reference_issue = CheckBox.new()
  _reference_issue.text = "Add issue URL to comment (when keeping it active)"
  box.add_child(_reference_issue)
  _issue_dialog.confirmed.connect(_create_issue)
  add_child(_issue_dialog)


func _show_github_message(message: String) -> void:
  _status.dialog_text = message
  _status.popup_centered(Vector2i(520, 180))


func _open_issue(reference: Dictionary) -> void:
  var url := str(reference.get("url", ""))
  if url.begins_with("https://github.com/"):
    OS.shell_open(url)


func _on_issue_button_clicked(item: TreeItem, _column: int, _id: int, _mouse: int) -> void:
  if github.busy:
    return

  var note: Dictionary = item.get_metadata(0)
  var key := GitHubIssues.note_key(note)
  var reference: Dictionary = github.references.get(key, {})
  if reference.has("url"):
    _open_issue(reference)
    return
  if not reference.is_empty():
    var recovery := ConfirmationDialog.new()
    recovery.title = "Check GitHub before retrying"
    recovery.dialog_text = "The previous request may have created an issue. Check the repository first.\nOnly reset this request if you have confirmed no issue exists."
    recovery.ok_button_text = "Reset request"
    recovery.add_button("Open repository", true, "open")
    recovery.custom_action.connect(func(_action: StringName): OS.shell_open("https://github.com/" + str(reference.repository) + "/issues"))
    recovery.confirmed.connect(func():
      github.references.erase(key)
      github.save()
      rescan.call_deferred()
      recovery.queue_free()
    )
    recovery.canceled.connect(recovery.queue_free)
    add_child(recovery)
    recovery.popup_centered()
    return

  _issue_note = note.duplicate(true)
  _issue_title.text = GitHubIssues.issue_title(note.text)
  _issue_preview.text = "Repository: %s\n\n%s" % [GitHubIssues.setting("github_repository", ""), GitHubIssues.issue_body(note)]
  _archive_issue.button_pressed = GitHubIssues.setting("should_auto_archive", true)
  _reference_issue.button_pressed = GitHubIssues.setting("add_issue_reference", true)
  _issue_dialog.popup_centered(Vector2i(540, 300))


func _create_issue() -> void:
  _request_archive = _archive_issue.button_pressed
  _request_reference = _reference_issue.button_pressed

  # Do not send a stale comment after the user has edited the file.
  if actions._open_at(_issue_note) == null:
    _show_github_message("The comment changed. Rescan and try again.")
    rescan.call_deferred()
    return
  var error := github.create_issue(_issue_note, _issue_title.text)
  if not error.is_empty():
    _show_github_message(error)
  _refresh_notes.call_deferred()


func _on_issue_finished(note: Dictionary, reference: Dictionary, message: String) -> void:
  if reference.is_empty():
    _show_github_message(message)
    rescan.call_deferred()
    return
  var result_message := "Created " + str(reference.url)

  # If saving the link failed, leave source intact so the user can recover.
  if not message.is_empty():
    result_message += "\n" + message
  elif _request_archive:
    note.issue_reference = reference
    if not actions.complete(note):
      result_message += "\nCould not archive the changed comment. It has been kept active."
  elif _request_reference:
    var new_text := "%s [GitHub #%d](%s)" % [note.text, reference.number, reference.url]
    # Save the future identity before editing, so rescans keep the link.
    var updated := note.duplicate(true)
    updated.line_text = str(note.line_text).substr(0, int(note.text_col)) + new_text
    var new_key := GitHubIssues.note_key(updated)
    github.references[new_key] = reference
    if not github.save():
      github.references.erase(new_key)
      result_message += "\nCould not save the reference; comment kept unchanged."
    elif not actions.edit_text(note, new_text):
      github.references.erase(new_key)
      github.save()
      result_message += "\nCould not update the changed comment. The issue link is retained locally."
  _show_github_message(result_message)
  rescan.call_deferred()
