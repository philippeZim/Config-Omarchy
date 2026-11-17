-- Managed by Omarchy_Setup. Loads every other *.lua file in this directory,
-- in sorted order, after Omarchy's defaults and the stock user files.
local dir = os.getenv("HOME") .. "/.config/hypr/setup"
local handle = io.popen("find '" .. dir .. "' -maxdepth 1 -type f -name '*.lua' ! -name init.lua | sort")
if handle then
  for path in handle:lines() do
    dofile(path)
  end
  handle:close()
end
