local unicode = require("unicode")
local computer = require("computer")
local sides = require("sides")

local M = {}

function M.nowMs() return math.floor(computer.uptime()*1000) end

function M.centerX(gpu, text)
  local w,_ = gpu.getResolution()
  return math.floor((w - unicode.len(text or ""))/2) + 1
end

function M.sideId(x)
  if type(x) == "number" then return x end
  if type(x) == "string" then return sides[x] or sides.back end
  return sides.back
end

function M.sideName(id)
  for k,v in pairs(sides) do if type(v)=="number" and v==id then return k end end
  return id
end

function M.deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k,v in pairs(t) do r[k] = M.deepcopy(v) end
  return r
end

function M.inList(t, v)
  for _,x in ipairs(t or {}) do if x == v then return true end end
  return false
end

return M