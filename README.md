# Scratchpad

A native macOS menu bar note app. One infinite note, always one click away.

## Usage

Click the pencil icon in your menu bar. Type. Click anywhere else to dismiss. Your note is saved automatically.

## Build

Requires Xcode Command Line Tools. If you don't have them:

```bash
xcode-select --install
```

Then build:

```bash
./build.sh
```

This produces `Scratchpad.app` in the current directory.

## Install

Drag `Scratchpad.app` to `/Applications`, then add it to **System Settings → General → Login Items** so it starts with your Mac.

## Notes

- Your note is saved to `~/Library/Application Support/Scratchpad/note.json`. Existing `note.md` files are migrated automatically on first launch.
- Content is structured as **blocks** — each paragraph, heading, or list item is a discrete unit.
- **Enter** creates a new block below (list and todo blocks carry their type; headings revert to text).
- **Backspace** on an empty block deletes it and focuses the previous one.
- Hover the `+` area at the bottom to reveal block type options: Text, H1, H2, H3, List, Todo, Quote, Divider.
- Within any block, `**bold**`, `*italic*`, and `` `code` `` inline formatting still works.
- Click a checkbox to toggle it. Checked items get strikethrough.
- Follows your system light/dark mode automatically.
