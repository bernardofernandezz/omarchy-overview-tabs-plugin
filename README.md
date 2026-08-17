# Task View for Omarchy

Task View is a native fullscreen Mission Control for Omarchy, inspired by
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
- Reliable app names and icons, including Omarchy Chromium web apps and
  generic Quickshell containers
- App titles, active-state indicators, workspace badges, and monitor badges
- Height-aware responsive grid with centered incomplete rows and vertical
  scrolling only after cards reach a usable minimum size
- Spatial arrow-key navigation
- `Tab`, `Shift+Tab`, `Enter`, and `Escape` support
- Workspace and recent-focus views, plus a compact 1–9 workspace minimap
- Animated Workspaces/Recent control and keyed grid transitions when search,
  workspace, or monitor filters reorganize the overview
- Keyboard workspace filtering with `Ctrl+Left`, `Ctrl+Right`, and `Ctrl+1…9`
- Move the selected window with `Shift+1…9` and undo moves with `Ctrl+Z`
- Close a selected window with `Ctrl+W` or the card's close button
- Hold `Space` for a larger quick peek without starting another capture stream
- Optional `h`, `j`, `k`, `l` navigation
- Monitor filtering and address-safe monitor moves on Hyprland's Lua dispatcher
- Mouse hover, click, wheel scrolling, and backdrop dismissal
- Theme-aware workspace tabs with window counts, active state, and urgency
- Ranked fuzzy type-to-search by app name, title, app ID, workspace, or monitor
- Initial selection on the currently focused window
- Native Omarchy colors, typography, spacing, borders, and animations
- Graceful icon-and-title fallback when a preview is unavailable
- Pointer-motion gating that prevents selection churn when cards move under a
  stationary cursor
- In-place preview refresh on every opening: visible cards re-capture while
  the retained texture stays on screen, so previews never go stale and never
  flash
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
| `Ctrl+←` / `Ctrl+→` | Cycle through workspace filters |
| `Ctrl+1` … `Ctrl+9` | Show that numbered workspace |
| `Ctrl+A` | Return to all windows |
| `Ctrl+R` | Toggle workspace and recent-focus ordering |
| `Alt+←` / `Alt+→` | Cycle monitor filters when multiple monitors exist |
| `Shift+1` … `Shift+9` | Move the selected window to that workspace |
| `Ctrl+Shift+←` / `Ctrl+Shift+→` | Move the selected window to the adjacent monitor |
| `Ctrl+Z` | Undo the most recent workspace/monitor move |
| `Ctrl+W` | Close the selected window |
| Hold `Space` | Enlarge the selected preview temporarily |
| `Enter` | Activate the selected window |
| `Escape` | Close without changing the active window |
| Type text | Filter by app name, app ID, or title |
| `Backspace` | Edit the current search |
| Mouse hover | Move the selection |
| Mouse click | Activate a window |
| Mouse wheel | Scroll a large grid |
| Backdrop click | Close without changing the active window |

When `vimNavigation` is enabled, `h`, `j`, `k`, and `l` mirror the arrow keys
while the search query is empty. It is disabled by default so typing always
starts a search predictably.

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

### Enable Vim navigation

Add `vimNavigation` to the existing plugin entry in
`~/.config/omarchy/shell.json`:

```json
{
  "id": "local.task-view",
  "vimNavigation": true
}
```

It can also be enabled for one invocation:

```bash
omarchy-shell shell summon local.task-view '{"vimNavigation":true}'
```

## How it works

### Window discovery

Task View reads the reactive `Hyprland.toplevels`, `Hyprland.workspaces`, and
`Hyprland.monitors` models exposed by Quickshell. Opening, closing, moving, or
renaming a window updates the overview without timer-based polling. Opening
the overlay does not force-refresh these models, avoiding a full delegate and
preview rebuild on every `Super+Tab` press.

Desktop metadata is resolved from the live `DesktopEntries` model. The resolver
scores the app ID, initial class, desktop-entry ID, `StartupWMClass`, executable,
Steam application ID, and—when applicable—the domain embedded in Chromium,
Chrome, Brave, and Edge web-app classes.
Window titles are used only as a low-priority display hint for generic
containers such as Quickshell, never as window identity. Icons use Omarchy's
shared application library with the standard application icon as a fallback.

### Theme integration

The overlay consumes the active Omarchy `Color`, `Style`, and `Border` tokens
for its backdrop, typography, spacing, state fills, focus border, urgency, and
accent. It follows theme changes without maintaining a second palette or
hard-coded dark theme.

### Window activation

When a window is selected, Task View:

1. Closes the overlay and releases exclusive keyboard focus.
2. Activates the target workspace when necessary.
3. Requests activation through the Wayland toplevel handle.
4. Falls back to native Hyprland IPC by immutable window address if needed.

Window titles are never used as identifiers.

### Window management

Close requests use the Wayland toplevel handle when available. Workspace moves
use Hyprland's exact `address:0x…` selector, with the current Lua dispatcher and
a legacy dispatcher fallback. Monitor moves are shown only when the installed
Hyprland Lua dispatcher can target a specific window safely. The undo stack is
in memory, bounded to 16 moves, and intentionally never attempts to restore a
closed application.

### Multi-monitor behavior

The overview opens on the currently focused monitor and includes windows from
all monitors. Cards from another monitor display a monitor badge. On setups
with multiple monitors, the top strip adds display filters ordered by Hyprland's
reported `x`/`y` topology; `Ctrl+Shift+Left/Right` moves the selected window to
the adjacent display without following it.

### Plugin structure

```text
local.task-view/
├── manifest.json          Plugin metadata and overlay entry point
├── Overview.qml           Lifecycle, window model, layout, input, and focus
├── WindowCard.qml         Preview, metadata, badges, and pointer interaction
├── WindowActions.qml      Exact-address close/move dispatch and bounded undo
├── ViewModeSwitch.qml     Animated Workspaces/Recent segmented control
├── WorkspaceTab.qml       Theme-aware workspace filter tab
├── PreviewScheduler.qml   Deduplicated, paced one-frame capture queue
├── TaskViewModel.js       Grid sizing, navigation, and app recognition
├── task-view.lua          Optional Super+Tab integration
├── tests/
│   ├── model.test.mjs     Grid, navigation, fuzzy search, and recognition tests
│   └── tst_previewscheduler.qml  Capture queue tests
├── README.md
└── LICENSE
```

## Previews, performance, and privacy

- Cards capture one frame with `live: false` through a paced queue. The selected
  card and cards already visible in the viewport are prioritized.
- Captures begin only after the overlay becomes interactive.
- Every opening requests a fresh frame for each card. `ScreencopyView`'s
  `captureFrame()` refreshes the image in place: the retained texture stays on
  screen until the compositor delivers the replacement, so previews never show
  stale content and never flash.
- Cards are keyed by immutable Hyprland address through `ScriptModel`, so model
  changes update existing delegates instead of destroying and recreating every
  preview surface.
- The latest static frame stays in memory while its card and toplevel exist and
  bridges each refresh, so a slow or temporarily unavailable capture degrades to
  the previous frame instead of fallback content.
- No frames are captured while Task View is closed. Reopening re-captures the
  visible cards; a new capture context is created only for a new source or
  after a failed source is retried on a later session.
- Preview aspect ratios are preserved.
- `ScreencopyView.constraintSize` performs the native aspect-fit calculation,
  avoiding geometry changes while a frame is arriving.
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

The result includes window count, selected index, grid columns, monitor,
opening latency, preview queue length, and capture states. It does not expose
window titles or captured content.

## Development and validation

Changes under `~/.config/omarchy/plugins/` hot-reload automatically. Force a
rescan only when necessary:

```bash
omarchy-shell shell rescanPlugins
```

Run the project checks from the repository root:

```bash
node tests/model.test.mjs
QT_QPA_PLATFORM=minimal QT_QPA_PLATFORMTHEME= GDK_BACKEND= \
  DISPLAY= WAYLAND_DISPLAY= /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import .
omarchy plugin validate "$PWD"
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" -I "$PWD" \
  Overview.qml WindowCard.qml WindowActions.qml ViewModeSwitch.qml \
  WorkspaceTab.qml PreviewScheduler.qml
luac -p task-view.lua
```

The stock Qt linter may warn about Quickshell's synthetic `qs.*` import root
and dynamically provided Omarchy singletons. These tooling warnings also occur
with first-party overlays; syntax and manifest failures return a non-zero exit
status.

## Feasibility and roadmap

The table reflects Omarchy 4.0, Quickshell 0.3, and Hyprland 0.56 as installed
on the development system.

| Feature | Status | Current approach / limit |
| --- | --- | --- |
| All-window overview | SUPPORTED | Reactive Hyprland toplevel model and Wayland single-frame previews |
| Workspace navigation/minimap | SUPPORTED | Reactive workspace model plus known numeric workspaces 1–9 |
| Independent workspace lanes | PARTIALLY SUPPORTED | Model and ordering exist; lane rendering is deferred |
| Keyboard-first navigation | SUPPORTED | Spatial arrows, wrapped Tab, optional Vim keys, immediate focus grab |
| Fuzzy search | SUPPORTED | Fast metadata-only scoring; application contents are not exposed |
| Recent windows | PARTIALLY SUPPORTED | In-memory recency plus `focusHistoryID`, no persistence |
| Move to workspace | SUPPORTED | Exact-address native dispatcher; keyboard shipping now |
| Workspace drag and drop | REQUIRES WORKAROUND | Possible in QML, but compositor/model races need dedicated testing |
| Close window | SUPPORTED | Wayland close request with exact-address Hyprland fallback |
| Quick peek | SUPPORTED | Enlarges the retained frame; creates no live capture stream |
| Multi-monitor filters/moves | PARTIALLY SUPPORTED | Topology-aware model; only one physical monitor was available for validation |
| Group by application | SUPPORTED | Reliable app identity exists; grouped presentation is deferred |
| Window action menu | PARTIALLY SUPPORTED | Safe direct actions ship; float/pin/fullscreen menu is deferred |
| Command mode | REQUIRES WORKAROUND | A small deterministic grammar is viable but not part of the stable core |
| Undo | PARTIALLY SUPPORTED | Workspace/monitor moves only; close is never undoable |
| Media/capture indicators | NOT CURRENTLY FEASIBLE | No reliable PipeWire/portal stream-to-toplevel mapping |
| Project/context detection | REQUIRES WORKAROUND | Would depend on title, process tree, and `/proc` heuristics |
| Session persistence | PARTIALLY SUPPORTED | Apps/layout can be approximated; internal application state cannot |
| Window-rules generator | PARTIALLY SUPPORTED | Technically possible, but safe user-config ownership needs separate design |

## Current limitations

- Windows-style `Alt+Tab` hold/release mode is not implemented; the existing
  Omarchy `Alt+Tab` bindings remain untouched.
- Previews are single frames rather than persistent live streams.
- Focus history is session-local, complemented by Hyprland's
  `focusHistoryID`; it is not persisted across shell restarts.
- Workspace view orders and filters windows by workspace but does not yet
  render independent vertical workspace lanes.
- Application-group, command-palette, and full window-action-menu views are
  deferred; the stable direct shortcuts ship first.
- Audio, microphone, camera, and screencast indicators are unavailable because
  current window metadata does not provide a reliable per-toplevel mapping.
- Project detection, session restoration, and automatic window-rule generation
  require process/configuration heuristics and are intentionally not part of
  the stable core.

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
