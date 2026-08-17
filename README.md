# Task View for Omarchy

Task View is a native, keyboard-first **Mission Control** for Omarchy. It is a
fullscreen overview of every open window — from all workspaces and monitors —
with live window previews, fuzzy search, and direct window actions, inspired by
Windows Task View, macOS Mission Control, and GNOME Activities.

It runs as an Omarchy Shell overlay inside the existing Quickshell process. No
extra shell, daemon, or background service is started.

## Features

- Windows from all workspaces and monitors in one fullscreen overview
- Real single-frame window previews, refreshed on every opening without flashing
- Workspace and Recent views with a compact 1–9 workspace minimap
- Spatial arrow-key navigation, optional `h`/`j`/`k`/`l` Vim keys, `Tab`,
  `Shift+Tab`, `Enter`, and `Escape`
- Ranked fuzzy type-to-search by app name, title, app ID, workspace, or monitor
- Move a window to a workspace (`Shift+1…9`), close it (`Ctrl+W`), or undo moves
  (`Ctrl+Z`)
- Monitor filtering and moves with `Alt+←/→` and `Ctrl+Shift+←/→`
- Hold `Space` for a larger quick peek of the selected window
- Theme-aware tabs and cards using native Omarchy colors, typography, and
  animations
- No polling, persisted screenshots, or extra runtime dependencies

## Requirements

- Omarchy 4 with the Quattro plugin runtime
- Quickshell with `Quickshell.Wayland` and `Quickshell.Hyprland`
- Hyprland with foreign-toplevel support and `hyprland-toplevel-export-v1` for
  window previews

Developed and tested with Omarchy `4.0.0-1`, Quickshell `0.3.0.r20.g28771c7`,
and Hyprland `0.56.2`. No additional packages are required.

## Installation

### Install from GitHub

```bash
omarchy plugin add https://github.com/bernardofernandezz/omarchy-overview-tabs-plugin --enable
```

Confirm that the plugin is installed and enabled:

```bash
omarchy plugin list --json | jq '.[] | select(.id == "local.task-view")'
```

Plugin files are installed under `~/.config/omarchy/plugins/local.task-view/`.

### Install from a local clone

The directory must be a Git repository because the Omarchy installer clones the
plugin source:

```bash
git clone https://github.com/bernardofernandezz/omarchy-overview-tabs-plugin ~/src/omarchy-task-view
omarchy plugin add "file://$HOME/src/omarchy-task-view" --enable
```

Do not run this repository as a standalone Quickshell configuration.

## Set up the Super+Tab shortcut

Omarchy currently assigns `Super+Tab` to the next-workspace action. Task View
includes `task-view.lua`, which replaces only that binding and leaves `Alt+Tab`
unchanged.

Open `~/.config/hypr/bindings.lua` and add the following line **before** the
file's final `return config`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/local.task-view/task-view.lua")
```

Then reload and check the configuration:

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
| `Tab` / `Shift+Tab` | Select the next / previous window |
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
| Mouse hover / click / wheel | Select, activate, or scroll the grid |
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

Options are set per plugin entry in `~/.config/omarchy/shell.json`, which the
shell reloads automatically:

```json
{
  "id": "local.task-view",
  "allWorkspaces": false,
  "vimNavigation": true
}
```

- `allWorkspaces` — show every workspace by default instead of only the focused
  one (`true` by default).
- `vimNavigation` — enable `h`/`j`/`k`/`l` navigation (`false` by default).

Both options can also be passed for a single invocation:

```bash
omarchy-shell shell summon local.task-view '{"allWorkspaces":false,"vimNavigation":true}'
```

## Uninstall

Remove the `dofile(...)` line from `~/.config/hypr/bindings.lua` and reload
Hyprland, then remove the plugin:

```bash
hyprctl reload
omarchy plugin remove local.task-view
```

Omarchy's default `Super+Tab` workspace binding returns after the next Hyprland
reload.

## Troubleshooting

- **The plugin is not listed** — rescan and check:

  ```bash
  omarchy-shell shell rescanPlugins
  omarchy plugin list --json | jq '.[] | select(.id == "local.task-view")'
  ```

  If it is installed but disabled: `omarchy plugin enable local.task-view`.

- **The overlay does not open** — test without the keybinding with
  `omarchy-shell shell summon local.task-view '{}'`, then inspect shell logs with
  `qs log -p "$OMARCHY_PATH/shell" --tail 100`.

- **Cards show icons instead of previews** — preview capture is optional and
  failure is non-fatal; selection and activation keep working.

## Development and validation

Changes under `~/.config/omarchy/plugins/` hot-reload automatically. Run the
project checks from the repository root:

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
and dynamically provided Omarchy singletons; syntax and manifest failures still
return a non-zero exit status.

## License

Task View is available under the MIT License. See [LICENSE](LICENSE).
