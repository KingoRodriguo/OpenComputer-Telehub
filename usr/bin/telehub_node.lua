local gpu = require("component").gpu
local term = require("term")
local event = require("event")

local util    = require("telehub.util")
local cfgmod  = require("telehub.config")
local detect  = require("telehub.detector")
local access  = require("telehub.access")
local redio   = require("telehub.redio")
local ui      = require("telehub.ui")
local cfgui   = require("telehub.cfgui")

local cfg = cfgmod.load()
local origW, origH = gpu.getResolution()
local rects = {}

local state = {present=false, who=nil, dist=nil, allowed=false}

local function redraw()
  rects = ui.draw(state, cfg)
end

local function cleanup()
  pcall(function() redio.off(cfg) end)
  pcall(function() gpu.setResolution(origW, origH) end)
  pcall(function() term.clear() end)
end

local function nearest()
  local who, dist = detect.nearest(cfg.SCAN_RADIUS)
  return who, dist
end

local function isPresent(dist)
  return dist and dist >= cfg.MIN_RANGE and dist <= cfg.MAX_RANGE
end

local function main()
  ui.init(cfg)
  redraw()
  while true do
    local ev = { event.pull(cfg.TICK_SEC or 0.08) }
    if ev[1] == "interrupted" then break end
    if ev[1] == "key_down" then
      local _,_,_,code,ch = table.unpack(ev)
      if code == 0x10 or ch == 81 or ch == 113 then break end -- Q
    end

    if ev[1] == "touch" then
      local _,_,x,y = table.unpack(ev)
      if rects.open and x>=rects.open.x1 and x<=rects.open.x2 and y>=rects.open.y1 and y<=rects.open.y2 then
        cfg.ACCESS_POLICY = "open"
        cfgmod.save(cfg)
        redraw()
      elseif rects.config and x>=rects.config.x1 and x<=rects.config.x2 and y>=rects.config.y1 and y<=rects.config.y2 then
        local newCfg = cfgui.run(cfg, cfgmod.save)
        if newCfg then
          cfg = newCfg
          ui.init(cfg)
        end
        redraw()
      elseif rects.tele and x>=rects.tele.x1 and x<=rects.tele.x2 and y>=rects.tele.y1 and y<=rects.tele.y2 then
        local _, d2 = nearest()
        if isPresent(d2) and state.allowed then
          redio.pulse(cfg)
        end
      end
    end

    local who, dist = nearest()
    local present = isPresent(dist)
    local allowed = present and access.allowedFor(who, cfg) or false

    if present ~= state.present or who ~= state.who or (dist or 0) ~= (state.dist or -1) or allowed ~= state.allowed then
      state.present, state.who, state.dist, state.allowed = present, who, dist, allowed
      redraw()
    end
  end
end

local ok, err = xpcall(main, function(e)
  if debug and debug.traceback then return debug.traceback(e, 2) end
  return tostring(e)
end)
cleanup()
if not ok then io.stderr:write(err.."\n") end