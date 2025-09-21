local fs  = require("filesystem")
local ser = require("serialization")
local util= require("telehub.util")

local M = {}
M.DIR  = "/etc/telehub"
M.PATH = M.DIR.."/config.lua"

M.DEFAULT = {
  REDSTONE_SIDE = "back",
  TRANSPOSER_TELEPOSER_SIDE = "north",
  TRANSPOSER_STORAGE_SIDE = "east",
  LEVEL_ON = 15,
  PULSE_SEC = 0.35,
  MIN_RANGE = 0.40,
  MAX_RANGE = 1.70,
  SCAN_RADIUS = 4.0,
  TICK_SEC = 0.08,
  RES_W = nil,
  RES_H = nil,
  RES_SCALE = 0.5,
  COOLDOWN_MS = 800,
  BTN_COLOR_BG = 0xFFFF00,
  BTN_COLOR_FG = 0x000000,
  DEST_NAME = "Destination",
  BTN_LABEL = "Teleport",
  ACCESS_POLICY = "owner_plus_allow",
  OWNER = nil,
  ALLOW = {},
  DENY  = {},
  UPDATE = {
    AUTO = "apply", -- "off"|"check"|"apply"
    REPO = "https://raw.githubusercontent.com/KingoRodriguo/OpenComputer-Telehub/main",
    MANIFEST = "manifest.lua",
    TIMEOUT = 15,
    KEEP_MANIFEST = false,  -- <-- nouvelle option
  },
}

local function merge(dst, src)
  for k,v in pairs(src or {}) do
    if type(v)=="table" and type(dst[k])=="table" then merge(dst[k], v) else dst[k] = v end
  end
  return dst
end

function M.load()
  local cfg = util.deepcopy(M.DEFAULT)
  if not fs.exists(M.DIR) then fs.makeDirectory(M.DIR) end
  if fs.exists(M.PATH) then
    local ok, t = pcall(dofile, M.PATH)
    if ok and type(t)=="table" then merge(cfg, t) else M.save(cfg) end
  else
    M.save(cfg)
  end
  return cfg
end

function M.save(cfg)
  local tosave = util.deepcopy(cfg)
  local sides = require("sides")
  if type(tosave.REDSTONE_SIDE)=="number" then
    for k,v in pairs(sides) do if type(v)=="number" and v==tosave.REDSTONE_SIDE then tosave.REDSTONE_SIDE=k; break end end
  end
  local f = assert(io.open(M.PATH, "w"))
  f:write("return "..ser.serialize(tosave))
  f:close()
end

return M