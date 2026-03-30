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

- Your note is saved to `~/Library/Application Support/Scratchpad/note.md` — plain markdown, readable anywhere.
- Supports `# headings`, `## subheadings`, `**bold**`, `*italic*`, `` `code` ``, `- lists`, `> blockquotes`, and `---` dividers.
- Type `[]` then space to create an interactive checkbox. Click to toggle.
- Hover over the `?` in the bottom corner for a quick reference of all shortcuts.
- Follows your system light/dark mode automatically.
