@tool
extends EditorPlugin

const NoteDock = preload("res://addons/note_tracker/note_dock.gd")

var _dock: EditorDock
var _panel: NoteDock

func _enter_tree() -> void:
  _panel = NoteDock.new()
  _dock = EditorDock.new()
  _dock.title = "Notes"
  _dock.layout_key = "NoteTracker"
  _dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
  _dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
  _dock.add_child(_panel)
  add_dock(_dock)

  resource_saved.connect(_handle_resource_saved)
  EditorInterface.get_resource_filesystem().filesystem_changed.connect(_panel.queue_rescan)

func _exit_tree() -> void:
  EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_panel.queue_rescan)
  remove_dock(_dock)
  _dock.queue_free()

func _handle_resource_saved(resource: Resource) -> void:
  if resource is Script:
    _panel.queue_rescan()

