# Note Tracker

Note Tracker is a Godot 4.7 editor addon that collects tagged comments from GDScript files in one **Notes** dock.

![Note Tracker dock showing tagged notes](screenshots/Screenshot%202026-11-02%20125543.png)

## Installation

1. Copy `addons/note_tracker` into your Godot project.
2. In **Project > Project Settings > Plugins**, enable **Note Tracker**.

## Usage

Add `@todo`, `@hack`, `@note`, or `@info` to a GDScript comment:

```gdscript
# @todo Add a pause menu
move_player() # @note Keep this in sync with the animation
```

Open the **Notes** dock to see your comments. Select a tag to filter the list, or use the refresh button to scan again. Double-click a note to edit its text, or double-click its location to open the script.

Check a note to remove its comment from the source file. Click the restore icon in **Recently done** to put it back.

## Features

- Finds tagged comments across GDScript files, including inline comments.
- Filters notes by tag and shows their file and line number.
- Edits notes and marks them done from the dock.
- Restores recently completed notes, even after restarting the editor.

## Future features

- Create a GitHub issue from a note.
- Configure which tags appear in the dock.
