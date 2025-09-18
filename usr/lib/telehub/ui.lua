local comp  = require("component")
local term  = require("term")
local unicode= require("unicode")
local util  = require("telehub.util")

local gpu = comp.gpu

local M = {}

function M.init(cfg)
  local maxW, maxH = gpu.maxResolution()
  local w = cfg.RES_W or math.max(20, math.floor(maxW * (cfg.RES_SCALE or 0.5)))
  local h = cfg.RES_H or math.max(10, math.floor(maxH * (cfg.RES_SCALE or 0.5)))
  gpu.setResolution(math.min(w, maxW), math.min(h, maxH))
  term.clear()
end

function M.draw(state, cfg)
  local w,h = gpu.getResolution()
  term.clear()

  local y = math.floor(h/2) - 6
  local title = cfg.DEST_NAME or "Destination"
  gpu.set(util.centerX(gpu, title), y, title)

  local who  = "Player: "..(state.who or "-")
  local dist = "Distance: "..(state.dist and string.format("%.2f", state.dist) or "-")
  local acc  = "Access: "..(state.present and (state.allowed and "ALLOWED" or "DENIED") or "-")
  gpu.set(util.centerX(gpu, who),  y+2, who)
  gpu.set(util.centerX(gpu, dist), y+3, dist)
  gpu.set(util.centerX(gpu, acc),  y+4, acc)

  local rects = {}
  if state.present and state.allowed then
    local label = cfg.BTN_LABEL or "Teleport"
    local pad = 4
    local btnW = unicode.len(label) + pad
    local bx = util.centerX(gpu, string.rep(" ", btnW))
    local by = y + 7

    local fg0,bg0 = gpu.getForeground(), gpu.getBackground()
    local hasColor = (gpu.getDepth and gpu.getDepth() or 1) >= 4
    if hasColor then gpu.setBackground(cfg.BTN_COLOR_BG or 0xFFFF00); gpu.setForeground(cfg.BTN_COLOR_FG or 0x000000) end
    gpu.fill(bx, by, btnW, 3, " ")
    gpu.set(bx + math.floor((btnW - unicode.len(label))/2), by+1, label)
    if hasColor then gpu.setBackground(bg0); gpu.setForeground(fg0) end

    rects.tele = {x1=bx, y1=by, x2=bx+btnW-1, y2=by+2}
  end

  local leftLabel  = "[ OPEN ]"
  local rightLabel = "[ CONFIG ]"
  local leftW  = unicode.len(leftLabel)
  local rightW = unicode.len(rightLabel)
  local lx = 2
  local rx = w - rightW - 1

  local fg0,bg0 = gpu.getForeground(), gpu.getBackground()
  local hasColor = (gpu.getDepth and gpu.getDepth() or 1) >= 4

  if hasColor then
    if cfg.ACCESS_POLICY == "open" then gpu.setBackground(0x44CC44); gpu.setForeground(0x000000) else gpu.setBackground(0x333333); gpu.setForeground(0xFFFFFF) end
  end
  gpu.fill(lx, h-1, leftW, 1, " "); gpu.set(lx, h-1, leftLabel)
  if hasColor then gpu.setBackground(bg0); gpu.setForeground(fg0) end

  if hasColor then gpu.setBackground(0x333333); gpu.setForeground(0xFFFFFF) end
  gpu.fill(rx, h-1, rightW, 1, " "); gpu.set(rx, h-1, rightLabel)
  if hasColor then gpu.setBackground(bg0); gpu.setForeground(fg0) end

  rects.open   = {x1=lx, y1=h-1, x2=lx+leftW-1,  y2=h-1}
  rects.config = {x1=rx, y1=h-1, x2=rx+rightW-1, y2=h-1}

  gpu.set(util.centerX(gpu, "Tap the button to teleport"), h-3, "Tap the button to teleport")
  gpu.set(util.centerX(gpu, "Quit: Ctrl+C or Q"),           h-2, "Quit: Ctrl+C or Q")

  return rects
end

return M