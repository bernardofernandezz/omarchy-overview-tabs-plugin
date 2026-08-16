# Task View for Omarchy

Task View is a native fullscreen window overview for Omarchy, inspired by
Windows Task View, macOS Mission Control, and GNOME Activities.

Press `Super+Tab` to see every open window, move through the overview with the
keyboard or mouse, and jump directly to the window you want—even when it is on
another workspace.

Task View runs as an Omarchy Shell overlay inside the existing Quickshell
process. It does not start another shell, daemon, launcher, or background
service.

## Features

- Windows from all workspaces in one fullscreen overview
- Real single-frame window previews
- App names, icons, titles, workspace badges, and monitor badges
- Responsive grid for small and large window counts
- Spatial arrow-key navigation
- `Tab`, `Shift+Tab`, `Enter`, and `Escape` support
- Mouse hover, click, wheel scrolling, and backdrop dismissal
- Workspace filter strip
- Type-to-search by app name, app ID, or window title
- Initial selection on the currently focused window
- Native Omarchy colors, typography, spacing, borders, and animations
- Graceful icon-and-title fallback when a preview is unavailable
- No polling, persisted screenshots, or extra runtime dependencies

## Requirements

- Omarchy 4 with the Quattro plugin runtime
- Quickshell with `Quickshell.Wayland` and `Quickshell.Hyprland`
- Hyprland foreign-toplevel support
- `hyprland-toplevel-export-v1` for window previews

The plugin was developed and tested with:

- Omarchy `4.0.0-1`
- Quickshell `0.3.0.r20.g28771c7`
- Hyprland `0.56.2`

No additional packages are required.

## Installation

### Install from a Git repository

Use Omarchy's native plugin installer:

```bash
omarchy plugin add <repository-url> --enable
```

For example, after this project is published on GitHub:

```bash
omarchy plugin add https://github.com/<owner>/<repository> --enable
```

Confirm that the plugin is installed and enabled:

```bash
omarchy plugin list --json | jq '.[] | select(.id == "local.task-view")'
```

### Install from a local clone

The directory must be a Git repository because the Omarchy installer clones
the plugin source:

```bash
git clone <repository-url> ~/src/omarchy-task-view
omarchy plugin add "file://$HOME/src/omarchy-task-view" --enable
```

Plugin files are installed under:

```text
~/.config/omarchy/plugins/local.task-view/
```

Do not run this repository as a standalone Quickshell configuration.

## Configure the Super+Tab shortcut

Omarchy currently assigns `Super+Tab` to the next-workspace action. Task View
includes `task-view.lua`, which replaces only that binding and leaves the
existing `Alt+Tab` behavior unchanged.

Open:

```text
~/.config/hypr/bindings.lua
```

Add the following line **before** the file's final `return` statement:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/local.task-view/task-view.lua")
```

The end of the file should follow this order:

```lua
-- Your existing configuration and personal bindings

dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/local.task-view/task-view.lua")

return config
```

Reload Hyprland and check the configuration:

```bash
hyprctl reload
hyprctl configerrors
```

`hyprctl configerrors` should return no output. `Super+Tab` can now open and
close Task View.

## Usage

| Input | Action |
| --- | --- |
| `Super+Tab` | Open or close Task View |
| `←` `→` `↑` `↓` | Move spatially through the window grid |
| `Tab` | Select the next window |
| `Shift+Tab` | Select the previous window |
| `Enter` | Activate the selected window |
| `Escape` | Close without changing the active window |
| Type text | Filter by app name, app ID, or title |
| `Backspace` | Edit the current search |
| Mouse hover | Move the selection |
| Mouse click | Activate a window |
| Mouse wheel | Scroll a large grid |
| Backdrop click | Close without changing the active window |

The overlay can also be controlled directly:

```bash
omarchy-shell shell summon local.task-view '{}'
omarchy-shell shell hide local.task-view
omarchy-shell shell toggle local.task-view '{}'
```

## Configuration

### Show all workspaces

Task View shows windows from every workspace by default.

To open it once with only the focused workspace visible:

```bash
omarchy-shell shell summon local.task-view '{"allWorkspaces":false}'
```

### Make current-workspace mode the default

Edit the existing Task View entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "local.task-view",
  "allWorkspaces": false
}
```

Do not replace the complete `plugins` array or the rest of `shell.json`; add
the setting to the entry created by `omarchy plugin enable`.

The shell watches this file and reloads changes automatically.

## How it works

### Window discovery

Task View reads the reactive `Hyprland.toplevels`, `Hyprland.workspaces`, and
`Hyprland.monitors` models exposed by Quickshell. Opening, closing, moving, or
renaming a window updates the overview without timer-based polling.

Desktop metadata comes from `DesktopEntries.heuristicLookup()`. Icons use the
shared Omarchy application library with the standard application icon as a
fallback.

### Window activation

When a window is selected, Task View:

1. Closes the overlay and releases exclusive keyboard focus.
2. Activates the target workspace when necessary.
3. Requests activation through the Wayland toplevel handle.
4. Falls back to native Hyprland IPC by immutable window address if needed.

Window titles are never used as identifiers.

### Multi-monitor behavior

The overview opens on the currently focused monitor and includes windows from
all monitors. Cards from another monitor display a monitor badge.

### Plugin structure

```text
local.task-view/
├── manifest.json          Plugin metadata and overlay entry point
├── Overview.qml           Lifecycle, window model, layout, input, and focus
├── WindowCard.qml         Preview, metadata, badges, and pointer interaction
├── TaskViewModel.js       Grid sizing and navigation algorithms
├── task-view.lua          Optional Super+Tab integration
├── tests/
│   └── model.test.mjs     Deterministic model tests
├── README.md
└── LICENSE
```

## Previews, performance, and privacy

- Each visible card captures one frame with `live: false`.
- Captures begin only after the overlay becomes interactive.
- Closing Task View clears every capture source immediately.
- Preview aspect ratios are preserved.
- The cursor is not included in previews.
- Preview content remains in memory and is never written to disk.
- There is no `hyprctl clients` render loop or process spawned per card.
- `keepLoaded` avoids recompiling the plugin on every invocation.
- Large grids keep a usable minimum card size and scroll vertically.

On the development system, the overlay layer became visible in approximately
32–34 ms across five measured openings with seven windows.

## Troubleshooting

### The plugin is not listed

```bash
omarchy-shell shell rescanPlugins
omarchy plugin list --json | jq '.[] | select(.id == "local.task-view")'
```

If it is installed but disabled:

```bash
omarchy plugin enable local.task-view
```

### Super+Tab still changes workspaces

Ensure the `dofile(...)` line is placed before `return config` in
`~/.config/hypr/bindings.lua`, then run:

```bash
hyprctl reload
hyprctl configerrors
```

### The overlay does not open

Test the plugin without the keybinding:

```bash
omarchy-shell shell summon local.task-view '{}'
```

Inspect recent shell logs:

```bash
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

### Cards show icons instead of previews

Preview capture is optional and failure is non-fatal. Window selection and
activation continue to work when a client or compositor does not permit
capture.

### Inspect the current non-sensitive state

```bash
omarchy-shell shell call local.task-view debugState '' | jq
```

The result includes window count, selected index, grid columns, monitor, and
preview readiness. It does not expose window titles or captured content.

## Development and validation

Changes under `~/.config/omarchy/plugins/` hot-reload automatically. Force a
rescan only when necessary:

```bash
omarchy-shell shell rescanPlugins
```

Run the project checks from the repository root:

```bash
node tests/model.test.mjs
omarchy plugin validate "$PWD"
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Overview.qml WindowCard.qml
luac -p task-view.lua
```

The stock Qt linter may warn about Quickshell's synthetic `qs.*` import root
and dynamically provided Omarchy singletons. These tooling warnings also occur
with first-party overlays; syntax and manifest failures return a non-zero exit
status.

## Current limitations

- `Ctrl+W` window closing is intentionally not implemented to avoid accidental
  destructive actions.
- Windows-style `Alt+Tab` hold/release mode is not implemented; the existing
  Omarchy `Alt+Tab` bindings remain untouched.
- Previews are single frames rather than persistent live streams.
- Advanced persisted focus-history tracking is not included.

## Uninstall

First remove the `dofile(...)` line from `~/.config/hypr/bindings.lua` and
reload Hyprland:

```bash
hyprctl reload
```

Then remove the plugin:

```bash
omarchy plugin remove local.task-view
```

Omarchy's default `Super+Tab` workspace binding returns after the next
Hyprland reload.

## License

Task View is available under the MIT License. See [LICENSE](LICENSE).
# omarchy-overview-tabs-plugin
