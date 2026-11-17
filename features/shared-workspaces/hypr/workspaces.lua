-- One shared set of workspaces instead of Omarchy's ten per monitor
-- (default/hypr/monitor-workspaces.lua).
--
-- With an external monitor plugged in, workspace 1 lives on the laptop panel
-- and every other workspace on the external monitor. With the laptop alone,
-- all of them are on the laptop. The bar widget in
-- ~/.config/omarchy/plugins/setup.workspaces shows the same row on every bar.

local M = o.workspaces

local function internal(monitor)
  return monitor.name:match("^eDP") or monitor.name:match("^LVDS") or monitor.name:match("^DSI")
end

-- The laptop panel and the first external monitor. `gone` names a monitor
-- Hyprland still lists while it reports its removal.
local function screens(gone)
  local laptop, external = nil, nil

  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror and monitor.name ~= gone then
      if internal(monitor) then
        laptop = laptop or monitor
      elseif not external or monitor.id < external.id then
        external = monitor
      end
    end
  end

  return laptop, external
end

-- The monitor a workspace belongs on.
local function home(id, gone)
  local laptop, external = screens(gone)
  if id == 1 then
    return laptop or external
  end
  return external or laptop
end

local function regular(workspace)
  return workspace and not workspace.special and workspace.id > 0
end

local function send_home(id, gone)
  local workspace = hl.get_workspace(id)
  local monitor = home(id, gone)
  if workspace and monitor and workspace.monitor and workspace.monitor.name ~= monitor.name then
    hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = monitor.name }))
  end
end

-- Show a workspace on the monitor it belongs on, creating it there if needed.
local function show(id, gone)
  send_home(id, gone)

  local monitor = home(id, gone)
  if not hl.get_workspace(id) and monitor and not monitor.focused then
    hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
  end
  hl.dispatch(hl.dsp.focus({ workspace = tostring(id) }))
end

-- Put every workspace on the monitor it belongs on, and every monitor on a
-- workspace of its own.
local function arrange(gone)
  local laptop, external = screens(gone)
  if not laptop and not external then
    return
  end

  local focused_window = hl.get_active_window()
  local focused_workspace = hl.get_active_workspace()

  -- Workspaces left over from Omarchy's per-monitor blocks (11 and up) take a
  -- free number in the shared set.
  for _, workspace in ipairs(hl.get_workspaces()) do
    if regular(workspace) and workspace.id > 10 then
      for id = 2, 10 do
        if not hl.get_workspace(id) then
          hl.dispatch(hl.dsp.workspace.change_id({ workspace = tostring(workspace.id), id = id }))
          break
        end
      end
    end
  end

  if laptop and external then
    local ids = {}
    for _, workspace in ipairs(hl.get_workspaces()) do
      if regular(workspace) then
        ids[#ids + 1] = workspace.id
      end
    end
    table.sort(ids)

    for _, id in ipairs(ids) do
      local workspace = hl.get_workspace(id)
      local on = workspace and workspace.monitor and workspace.monitor.name
      -- Only the laptop and the first external are managed; a third monitor
      -- keeps whatever it shows.
      if (id == 1 and on ~= laptop.name) or (id ~= 1 and on == laptop.name) then
        send_home(id, gone)
      end
    end

    -- Moving a visible workspace away leaves Hyprland to fill the gap with
    -- whatever it finds.
    laptop, external = screens(gone)
    if laptop and regular(laptop.active_workspace) and laptop.active_workspace.id ~= 1 then
      show(1, gone)
    end
    if external and regular(external.active_workspace) and external.active_workspace.id == 1 then
      show(2, gone)
    end
  end

  if focused_window and hl.get_window("address:" .. focused_window.address) then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. focused_window.address }))
  elseif regular(focused_workspace) and hl.get_workspace(focused_workspace.id) then
    hl.dispatch(hl.dsp.focus({ workspace = tostring(focused_workspace.id) }))
  end
end

-- Register the expression a bind stands for, so the keybindings menu and the
-- bar can run it with `hyprctl dispatch`.
local function action(fn, expression)
  o.bind_expressions[fn] = expression
  return fn
end

-- Omarchy's own handlers call these through the module table, so replacing
-- them here switches the per-monitor behaviour off.
function M.reconcile() end

function M.workspace_id(_, slot)
  return slot
end

function M.focus(id)
  return action(function()
    show(id)
  end, "o.workspaces.focus(" .. id .. ")")
end

function M.move_window(id, follow)
  return action(function()
    local window = hl.get_active_window()
    if not window then
      return
    end

    hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = false, window = "address:" .. window.address }))
    send_home(id)
    if follow ~= false then
      show(id)
    end
  end, "o.workspaces.move_window(" .. id .. (follow == false and ", false" or "") .. ")")
end

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  o.rebind("SUPER + " .. key, "Switch to workspace " .. workspace, M.focus(workspace))
  o.rebind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, M.move_window(workspace))
  o.rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, M.move_window(workspace, false))
end

-- Workspaces are pinned to their monitor, so moving one across makes no sense.
for _, key in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
end

hl.on("hyprland.start", function() arrange() end)
hl.on("config.reloaded", function() arrange() end)
hl.on("monitor.added", function() arrange() end)

-- Hyprland reports the removal from inside the monitor's teardown, so wait
-- until that has returned (as Omarchy's own handler does).
hl.on("monitor.removed", function(monitor)
  local name = monitor and monitor.name
  hl.timer(function() arrange(name) end, { type = "oneshot", timeout = 1 })
end)
