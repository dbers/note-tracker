# Note Tracker

Note Tracker is a Godot 4.6+ editor addon that collects tagged comments from GDScript files in one **Notes** dock.

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

## GitHub integration

In **Project > Project Settings > Addons > Note-tracker**, configure:

- **Enable GitHub**: show issue actions on note rows.
- **GitHub Repository**: target repository in `owner/repository` format.
- **Should Auto Archive**: default for removing the comment after creating an issue.
- **Add Issue Reference**: default for appending the issue URL when keeping a comment active.

Click **GitHub** in the Notes toolbar to enter your token. It is masked and kept **only in memory for this plugin session**, never in project settings, editor settings, or files. Enter it again after restarting the editor or reloading the plugin. Use **Clear stored token** to forget it immediately. Other editor plugins run in the same process; this does not isolate the token from malicious plugins or memory inspection.

Click the **+** beside a note to preview its issue and edit the title (maximum 80 characters). The body contains the full note, repository-relative filename, and one-based line number. Choose whether to archive the comment or keep it and append an issue URL. An archived comment retains its issue link in **Recently done**, and can still be restored.

Linked rows open their existing issue. Local references and pending requests are stored in `.godot/note_tracker/issues.json` (no token). Do not delete this cache while a request is unresolved. If a request times out, check the repository before resetting it through the row action; GitHub may have created the issue already. Identical comment lines in the same file share a local reference; editing a comment manually changes its identity.

The old `github_api_key` project setting is removed on plugin activation. If you previously saved a real token there, revoke it and generate a replacement; removing the current setting cannot erase Git history or backups. Non-secret settings are registered with defaults and saved through the normal Project Settings workflow.

### Generate the Api Key
1. Open [GitHub → Fine-grained tokens](https://github.com/settings/personal-access-tokens) and click Generate new token.
2. Give it a name, such as `Godot Issue Creator`, and choose an expiration.
3. Set Resource owner to the account or organization that owns the repository.
4. Under Repository access, select Only select repositories, then choose your repository.
5. Under Repository permissions, set Issues → Read and write. Leave other optional permissions unset. GitHub automatically includes required metadata access.
6. Generate the token and paste it into the Notes toolbar’s session token dialog. Organization repositories may require administrator approval. [Token setup documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

## License

MIT. See [LICENSE.md](LICENSE.md).
