@tool
extends RefCounted
# Finds comments tagged with # @<tag>.

const SourceDoc = preload("res://addons/note_tracker/source_doc.gd")
const EXTENSIONS: PackedStringArray = ["gd"]

static func build_regex(tags: PackedStringArray) -> RegEx:
  var names := PackedStringArray()
  for t in tags:
    var clean := t.strip_edges().trim_prefix("@").to_lower()
    if clean.is_valid_ascii_identifier():
      names.append(clean)
  if names.is_empty():
    return null
  return RegEx.create_from_string("(?i)^#+\\s*@(%s)\\b:?\\s*(.*?)\\s*$" % "|".join(names))

# Returns notes with their file, line, tag, and comment text.
static func scan_project(tags: PackedStringArray) -> Array:
  var regex := build_regex(tags)
  var notes := []
  if regex == null:
    return notes
  var buffers := SourceDoc.open_buffers()
  for file_path in _collect_files("res://"):
    var doc = SourceDoc.load_doc(file_path, buffers)
    if doc == null:
      continue
    for i in doc.lines.size():
      var note := parse_line(doc.lines[i], regex)
      if not note.is_empty():
        note.path = file_path
        note.line = i
        notes.append(note)
  return notes

static func parse_line(line: String, regex: RegEx) -> Dictionary:
  var hash_col := comment_start(line)
  if hash_col < 0:
    return {}
  var m := regex.search(line.substr(hash_col))
  if m == null:
    return {}
  return {
    tag = m.get_string(1).to_lower(),
    text = m.get_string(2),
    line_text = line,
    hash_col = hash_col,
    text_col = hash_col + m.get_start(2),
  }

# Column of the first `#` that isn't inside a string literal, or -1.
static func comment_start(line: String) -> int:
  var quote := ""
  var i := 0
  while i < line.length():
    var c := line[i]
    if quote.is_empty():
      if c == "#":
        return i
      if c == "\"" or c == "'":
        quote = c
    elif c == "\\":
      i += 1
    elif c == quote:
      quote = ""
    i += 1
  return -1

static func _collect_files(dir_path: String) -> PackedStringArray:
  var files := PackedStringArray()
  if FileAccess.file_exists(dir_path.path_join(".gdignore")):
    return files
  for f in DirAccess.get_files_at(dir_path):
    if f.get_extension() in EXTENSIONS:
      files.append(dir_path.path_join(f))
  for d in DirAccess.get_directories_at(dir_path):
    if not d.begins_with("."):
      files.append_array(_collect_files(dir_path.path_join(d)))
  return files
