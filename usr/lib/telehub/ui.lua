local comp   = require("component")
local term   = require("term")
local unicode= require("unicode")
local util   = require("telehub.util")
local upd    = require("telehub.update")

local gpu = comp.gpu
local M = {}

local function textW(s) return unicode.len(s or "") end

function M.init(cfg)
  local maxW, maxH = gpu.maxResolution()
  local w = cfg.RES_W or math.max(28, math.floor(maxW * (cfg.RES_SCALE or 0.6)))
  local h = cfg.RES_H or math.max(16, math.floor(maxH * (cfg.RES_SCALE or 0.6)))
  gpu.setResolution(math.min(w, maxW), math.min(h, maxH))
  term.clear()
end

-- Dessine un bouton plein (1 ligne) ou bloc (3 lignes) centré/placé
local function drawBtn(x, y, w, h, bg, fg, label)
  local fg0, bg0 = gpu.getForeground(), gpu.getBackground()
  local hasColor = (gpu.getDepth and gpu.getDepth() or 1) >= 4
  if hasColor then gpu.setBackground(bg or 0x333333); gpu.setForeground(fg or 0xFFFFFF) end
  gpu.fill(x, y, w, h, " ")
  if label then
    local lx = x + math.floor((w - textW(label))/2)
    local ly = y + math.floor(h/2)
    gpu.set(lx, ly, label)
  end
  if hasColor then gpu.setBackground(bg0); gpu.setForeground(fg0) end
  return {x1=x, y1=y, x2=x+w-1, y2=y+h-1}
end

function M.draw(state, cfg)
  local w, h = gpu.getResolution()
  term.clear()

  -- Header
  local dest = "["..(cfg.DEST_NAME or "Destination").."]"
  local headerY = 2
  gpu.set(util.centerX(gpu, dest), headerY, dest)
  gpu.fill(3, headerY+1, w-4, 1, "─")

  -- Owner line
  local owner = "Owner : "..(cfg.OWNER or "-")
  gpu.set(util.centerX(gpu, owner), headerY+3, owner)

  -- TELEPORT button (vert = allowed/owner; rouge = denied)
  local label = (cfg.BTN_LABEL or "TELEPORT"):upper()
  local btnW  = math.max(18, textW(label) + 6)
  local btnH  = 3
  local bx    = math.floor((w - btnW)/2) + 1
  local by    = math.floor(h/2)

  local allowed = state.allowed and state.present
  local bg = allowed and 0x88FF88 or 0xCC4444
  local fg = 0x000000
  local teleRect = drawBtn(bx, by, btnW, btnH, bg, fg, label)

  -- Bottom bar: Configuration centered
  local cfgLabel = "Configuration"
  local cfgW  = textW(cfgLabel) + 4
  local cfgH  = 1
  local cfgX  = math.floor((w - cfgW)/2) + 1
  local cfgY  = h - 1
  local cfgRect = drawBtn(cfgX, cfgY, cfgW, cfgH, 0x55AA55, 0x000000, cfgLabel)

  -- Version en bas-droite
  local v = upd.getLocalVersion() or "0.0.0"
  local vstr = "v"..v
  gpu.set(w - textW(vstr), h, vstr)

  -- Aide en bas-gauche
  gpu.set(2, h, "Q to quit")

  -- Retourne les zones cliquables
  local rects = {
    tele   = teleRect,
    config = cfgRect,
    -- (optionnel) on peut garder un champ 'allowed' pour la logique de clic
    _allowed = allowed
  }
  return rects
end

return M
