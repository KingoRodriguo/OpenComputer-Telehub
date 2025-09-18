local comp  = require("component")
local sides = require("sides")
local util  = require("telehub.util")

local rs = assert(comp.redstone, "Missing Redstone Card T1")

local M = { lastPulse = 0 }

local function sideId(x)
  if type(x)=="number" then return x end
  if type(x)=="string" then return sides[x] or sides.back end
  return sides.back
end

function M.pulse(cfg)
  local now = util.nowMs()
  if now - M.lastPulse < (cfg.COOLDOWN_MS or 800) then return end
  rs.setOutput(sideId(cfg.OUT_SIDE), cfg.LEVEL_ON or 15)
  os.sleep(cfg.PULSE_SEC or 0.3)
  rs.setOutput(sideId(cfg.OUT_SIDE), 0)
  M.lastPulse = util.nowMs()
end

function M.level(cfg, on)
  rs.setOutput(sideId(cfg.OUT_SIDE), on and (cfg.LEVEL_ON or 15) or 0)
end

function M.off(cfg)
  rs.setOutput(sideId(cfg.OUT_SIDE), 0)
end

return M