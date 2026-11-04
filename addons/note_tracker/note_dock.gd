@tool
extends VBoxContainer
# Shows notes by tag and lets you edit, complete, and restore them.

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

var _filter_bar: HBoxContainer
var _dropdown: OptionButton
var _tree: Tree
var _done_tree: Tree
var _done_label: Label
var _rescan_timer: Timer


func _ready() -> void:
  name = "Notes"
  size_flags_vertical = SIZE_EXPAND_FILL

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

  var split := VSplitContainer.new()
  split.size_flags_vertical = SIZE_EXPAND_FILL
  add_child(split)

  _tree = _make_tree(["", "Tag", "Note", "Location"])
  _tree.set_column_expand(COL_DONE, false)
  _tree.set_column_custom_minimum_width(COL_DONE, 28)
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
