-- Super+Tab integration for the Task View overlay.
-- Load this file from ~/.config/hypr/bindings.lua after Omarchy's defaults.

hl.unbind("SUPER + TAB")
o.bind(
  "SUPER + TAB",
  "Task View",
  "omarchy-shell shell toggle local.task-view '{}'"
)
