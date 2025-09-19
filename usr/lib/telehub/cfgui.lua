local comp   = require("component")
local term   = require("term")
local event  = require("event")
local unicode= require("unicode")
local util   = require("telehub.util")
local sides  = require("sides")
local upd    = require("telehub.update")

local gpu = comp.gpu
local M = {}

local function W(s) return unicode.len(s or "") end
local function pointIn(r,x,y) return r and x>=r.x1 and x<=r.x2 and y>=r.y1 and y<=r.y2 end

local function drawBtn(x,y,w,h,bg,fg,label)
  local fg0,bg0 = gpu.getForeground(), gpu.getBackground()
  local hasColor = (gpu.getDepth and gpu.getDepth() or 1) >= 4
  if hasColor then gpu.setBackground(bg or 0x333333); gpu.setForeground(fg or 0xFFFFFF) end
  gpu.fill(x,y,w,h," ")
  if label then gpu.set(x+math.floor((w-W(label))/2), y+math.floor(h/2), label) end
  if hasColor then gpu.setBackground(bg0); gpu.setForeground(fg0) end
  return {x1=x,y1=y,x2=x+w-1,y2=y+h-1}
end

local function drawPill(x,y,text,bg,fg)
  local w = W(text) + 2
  return drawBtn(x,y,w,1,bg,fg," "..text.." ")
end

local function prompt(label, def)
  local _,h = gpu.getResolution()
  gpu.fill(1,h,80,1," ")
  term.setCursor(1,h)
  term.write(label .. (def and (" ["..tostring(def).."]") or "") .. ": ")
  local s = term.read() or ""
  s = s:gsub("[\r\n]","")
  if s=="" and def~=nil then s=tostring(def) end
  return s
end

local function listToStr(t)
  local b = {}
  for i,v in ipairs(t or {}) do b[#b+1]=tostring(v) end
  return table.concat(b,", ")
end

function M.run(cfg, saveFn)
  local t = util.deepcopy(cfg)
  local w,h = gpu.getResolution()
  local running = true
  while running do
    term.clear()
    -- Titre
    local title = "Configuration"
    gpu.set(util.centerX(gpu, title), 2, title)
    gpu.fill(2,3,w-2,1,"─")

    local y = 5
    -- Owner
    gpu.set(3,y, "[owner_name]")
    gpu.set(22,y, t.OWNER or "-")
    local rOwn = drawPill(w-10,y,"Edit",0x88FF88,0x000000); y=y+2

    -- Destination
    gpu.set(3,y, "Destination name :")
    gpu.set(22,y, t.DEST_NAME or "-")
    local rDst = drawPill(w-10,y,"Edit",0x88FF88,0x000000); y=y+2

    -- Policy
    gpu.set(3,y, "[policy_state]")
    local rAllow = drawPill(22,y,"Allowed",0x55AAFF,0x000000)
    local rDeny  = drawPill(22+W(" Allowed ")+2,y,"Deny",0xCC4444,0x000000)
    local rOpen  = drawPill(w-10,y,"Open",0x88FF88,0x000000); y=y+2

    -- Allow list
    gpu.set(3,y, "allow_list")
    gpu.set(22,y, listToStr(t.ALLOW))
    local rAAdd = drawPill(w-16,y,"Add",0x555555,0xFFFFFF)
    local rADel = drawPill(w-8, y,"Del",0x555555,0xFFFFFF); y=y+2

    -- Deny list
    gpu.set(3,y, "deny_list")
    gpu.set(22,y, listToStr(t.DENY))
    local rDAdd = drawPill(w-16,y,"Add",0x555555,0xFFFFFF)
    local rDDel = drawPill(w-8, y,"Del",0x555555,0xFFFFFF); y=y+2

    -- Teleposer side
    gpu.set(3,y, "Teleposer side :")
    local rSide = drawPill(w-10,y,"cycle",0x555555,0xFFFFFF)
    gpu.set(22,y, tostring(t.OUT_SIDE)); y=y+3

    -- Bas : Cancel / Save
    local rCancel = drawBtn(2,   h-1, 10,1, 0x88FF88,0x000000, "Cancel")
    local rSave   = drawBtn(w-11,h-1, 10,1, 0x88FF88,0x000000, "Save")

    -- Version en bas-droite
    local v = upd.getLocalVersion() or "0.0.0"
    local vstr = "v"..v
    gpu.set(w - W(vstr), h, vstr)

    local ev = {event.pull()}
    if ev[1]=="interrupted" then return nil end
    if ev[1]=="key_down" then
      local _,_,_,code,ch = table.unpack(ev)
      if code==0x10 or ch==81 or ch==113 then return nil end
    elseif ev[1]=="touch" then
      local _,_,x,ty = table.unpack(ev)
      if pointIn(rOwn,x,ty) then
        local v = prompt("Owner", t.OWNER); t.OWNER = (v=="" and nil or v)
      elseif pointIn(rDst,x,ty) then
        t.DEST_NAME = prompt("Destination name", t.DEST_NAME)
      elseif pointIn(rAllow,x,ty) then
        t.ACCESS_POLICY = "owner_plus_allow"
      elseif pointIn(rDeny,x,ty) then
        t.ACCESS_POLICY = "deny"  -- indicatif visuel uniquement; l’accès réel dépend déjà de DENY/ALLOW/OWNER
      elseif pointIn(rOpen,x,ty) then
        t.ACCESS_POLICY = "open"
      elseif pointIn(rAAdd,x,ty) then
        local v = prompt("Add to ALLOW")
        if v~="" then
          local ex=false; for _,n in ipairs(t.ALLOW) do if n==v then ex=true end end
          if not ex then table.insert(t.ALLOW, v) end
        end
      elseif pointIn(rADel,x,ty) then
        local v = prompt("Remove from ALLOW")
        if v~="" then for i=#t.ALLOW,1,-1 do if t.ALLOW[i]==v then table.remove(t.ALLOW,i) end end end
      elseif pointIn(rDAdd,x,ty) then
        local v = prompt("Add to DENY")
        if v~="" then
          local ex=false; for _,n in ipairs(t.DENY) do if n==v then ex=true end end
          if not ex then table.insert(t.DENY, v) end
        end
      elseif pointIn(rDDel,x,ty) then
        local v = prompt("Remove from DENY")
        if v~="" then for i=#t.DENY,1,-1 do if t.DENY[i]==v then table.remove(t.DENY,i) end end end
      elseif pointIn(rSide,x,ty) then
        local order={"bottom","top","north","south","west","east"}
        local cur = util.sideName(util.sideId(t.OUT_SIDE))
        local idx=1; for i,n in ipairs(order) do if n==cur then idx=i end end
        idx = idx % #order + 1; t.OUT_SIDE = order[idx]
      elseif pointIn(rCancel,x,ty) then
        return nil
      elseif pointIn(rSave,x,ty) then
        saveFn(t); return util.deepcopy(t)
      end
    end
  end
end

return M
