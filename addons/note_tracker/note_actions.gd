@tool
extends RefCounted
# Edits and restores notes in source files.
# Keeps recently done notes in res://.godot across editor restarts.

const SourceDoc = preload("res://addons/note_tracker/source_doc.gd")
const STORE_PATH := "res://.godot/note_tracker/done.json"
const MAX_DONE := 50

var done: Array = []


func _init() -> void:
  if FileAccess.file_exists(STORE_PATH):
    var data = JSON.parse_string(FileAccess.get_file_as_string(STORE_PATH))
    if data is Array:
      done = data

func save() -> void:
  DirAccess.make_dir_recursive_absolute(STORE_PATH.get_base_dir())
  var f := FileAccess.open(STORE_PATH, FileAccess.WRITE)
  if f:
    f.store_string(JSON.stringify(done, "\t"))

func clear_done() -> void:
  done.clear()
  save()


# Replace the note's text, keeping its `# @tag` prefix.
func edit_text(note: Dictionary, new_text: String) -> bool:
  new_text = new_text.strip_edges()
  if new_text.is_empty() or new_text == note.text:
    return false
  var doc = _open_at(note)
  if doc == null:
    return false
  var i: int = doc.find_line(note.line_text, note.line)
  doc.begin()
  doc.set_line(i, note.line_text.substr(0, note.text_col) + new_text)
  return doc.commit()


# Remove the comment from source and remember it for restore.
func complete(note: Dictionary) -> bool:
  var doc = _open_at(note)
  if doc == null:
    return false
  var i: int = doc.find_line(note.line_text, note.line)
  var code_part: String = note.line_text.substr(0, note.hash_col).rstrip(" \t")
  var entry := {
    path = note.path,
    line = i,
    tag = note.tag,
    text = note.text,
    line_text = note.line_text,
    whole_line = code_part.strip_edges().is_empty(),
    stripped = code_part,
    before = doc.lines[i - 1] if i > 0 else "",
    after = doc.lines[i + 1] if i + 1 < doc.lines.size() else "",
    time = int(Time.get_unix_time_from_system()),
  }

  if note.has("issue_reference"):
    entry.issue_reference = note.issue_reference
  doc.begin()
  if entry.whole_line:
    doc.remove_line(i)
  else:
    doc.set_line(i, code_part)
  if not doc.commit():
    return false
  done.push_front(entry)
  done.resize(mini(done.size(), MAX_DONE))
  save()
  return true


# Put a completed comment back using nearby lines as anchors.
func restore(entry: Dictionary) -> bool:
  var doc = SourceDoc.load_doc(entry.path)
  if doc == null:
    push_warning("Note Tracker: %s no longer exists." % entry.path)
    return false
  var line := int(entry.line)
  doc.begin()
  if entry.whole_line:
    doc.insert_line(_insert_index(doc.lines, entry, line), entry.line_text)
  else:
    var i: int = doc.find_line(entry.stripped, line)
    if i < 0:
      doc.commit()
      push_warning("Note Tracker: the code line for \"%s\" has changed; can't restore." % entry.text)
      return false
    doc.set_line(i, entry.line_text)
  if not doc.commit():
    return false
  done.erase(entry)
  save()
  return true


func _open_at(note: Dictionary):
  var doc = SourceDoc.load_doc(note.path)
  if doc == null or doc.find_line(note.line_text, note.line) < 0:
    push_warning("Note Tracker: \"%s\" changed since the last scan; rescanning." % note.text)
    return null
  return doc


func _insert_index(lines: PackedStringArray, entry: Dictionary, hint: int) -> int:
  # Don't insert after a file's trailing newline.
  var limit := lines.size() - 1 if lines.size() > 0 and lines[-1].is_empty() else lines.size()
  var best := clampi(hint, 0, limit)
  var best_score := 0
  for i in limit + 1:
    var score := 0
    if i > 0 and lines[i - 1] == entry.before:
      score += 1
    if i < lines.size() and lines[i] == entry.after:
      score += 1
    if score > best_score or (score == best_score and score > 0 and absi(i - hint) < absi(best - hint)):
      best = i
      best_score = score
  return best
