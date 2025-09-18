local comp = require("component")

local ent = comp.os_entdetector or comp.os_entitydetector or comp.entity_detector
assert(ent, "Entity Detector not found (OpenSecurity)")

local M = {}

function M.scanPlayers(radius)
  local ok, list = pcall(ent.scanPlayers, radius)
  if ok and type(list)=="table" then return list end
  local ok2, list2 = pcall(ent.scanEntities, radius)
  if ok2 and type(list2)=="table" then
    local out = {}
    for _,e in ipairs(list2) do if e.isPlayer==nil or e.isPlayer==true then out[#out+1]=e end end
    return out
  end
  return {}
end

function M.nearest(radius)
  local list = M.scanPlayers(radius)
  local best, dmin
  dmin = 1e9
  for _,e in ipairs(list) do
    local r = tonumber(e.range or e.distance or e.dist or 9e9) or 9e9
    if r < dmin then best, dmin = e, r end
  end
  if not best then return nil end
  return (best.name or best.player or best.username or "?"), dmin
end

return M