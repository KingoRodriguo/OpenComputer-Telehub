local comp  = require("component")
local term  = require("term")
local event = require("event")
local unicode= require("unicode")
local util  = require("telehub.util")
local sides = require("sides")

local updater = require("telehub.update")
local computer = require("computer")

local gpu = comp.gpu

local M = {}

local function pointIn(r,x,y) return r and x>=r.x1 and x<=r.x2 and y>=r.y1 and y<=r.y2 end

local function drawBtn(x,y,text,bg,fg)
  local w = unicode.len(text)
  local fg0,bg0 = gpu.getForeground(), gpu.getBackground()
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.fill(x,y,w,1," ")
  gpu.set(x,y,text)
  if bg then gpu.setBackground(bg0) end
  if fg then gpu.setForeground(fg0) end
  return {x1=x,y1=y,x2=x+w-1,y2=y}
end

local function listToStr(t)
  local buf={} for i,v in ipairs(t or {}) do buf[#buf+1]=tostring(v) end
  return table.concat(buf, ", ")
end

local function prompt(label, def)
  local w,h = gpu.getResolution()
  gpu.fill(1,h,w,1," ")
  term.setCursor(1,h)
  term.write(label .. (def and (" ["..tostring(def).."]") or "") .. ": ")
  local s = term.read() or ""
  s = s:gsub("[\r\n]", "")
  if s=="" and def~=nil then s=tostring(def) end
  return s
end

function M.run(cfg, saveFn)
  local tmp = util.deepcopy(cfg)
  local running = true
  while running do
    term.clear()
    local w,h = gpu.getResolution()
    local y = 3
    gpu.set(util.centerX(gpu, "Configuration"), 1, "Configuration")

    gpu.set(2,y,      "Destination: "..(tmp.DEST_NAME or "-"))
    local rDest=drawBtn(w-12,y,"[ Edit ]",0x666666,0xFFFFFF); y=y+2
    gpu.set(2,y,      "Owner: "..(tmp.OWNER or "-"))
    local rOwn =drawBtn(w-12,y,"[ Edit ]",0x666666,0xFFFFFF); y=y+2
    gpu.set(2,y,      "Policy:")
    local rP1 =drawBtn(12,y,"[ OPEN ]", tmp.ACCESS_POLICY=="open" and 0x44CC44 or 0x333333,0x000000)
    local rP2 =drawBtn(22,y,"[ OWNER+ALLOW ]", tmp.ACCESS_POLICY=="owner_plus_allow" and 0x4488FF or 0x333333,0x000000); y=y+2

    gpu.set(2,y,      "Allow: "..listToStr(tmp.ALLOW))
    local rA1 =drawBtn(w-20,y,"[ Add ]",0x333333,0xFFFFFF)
    local rA2 =drawBtn(w-10,y,"[ Del ]",0x333333,0xFFFFFF); y=y+2

    gpu.set(2,y,      "Deny : "..listToStr(tmp.DENY))
    local rD1 =drawBtn(w-20,y,"[ Add ]",0x333333,0xFFFFFF)
    local rD2 =drawBtn(w-10,y,"[ Del ]",0x333333,0xFFFFFF); y=y+2

    gpu.set(2,y,      "Side : "..tostring(tmp.OUT_SIDE))
    local rS  =drawBtn(w-14,y,"[ Cycle ]",0x333333,0xFFFFFF); y=y+2

    local rSave=drawBtn(w-10,h-1,"[ Save ]",0x55AA55,0x000000)
    local rBack=drawBtn(2,    h-1,"[ Back ]",0xAA5555,0x000000)

    local localVer = updater.getLocalVersion() or "0.0.0"
    local auto = (tmp.UPDATE and tmp.UPDATE.AUTO) or "off"
    gpu.set(2,y, "Update: version "..localVer.."  Auto="..auto)
    local rToggle = drawBtn(w-24,y,"[ Auto Toggle ]",0x333333,0xFFFFFF)
    local rCheck  = drawBtn(w-12,y,"[ Check ]",0x666666,0xFFFFFF); y=y+2

    -- ces deux lignes existent peut-être déjà, garde-les :
    local rNow    = drawBtn(2,   y,"[ Update Now ]",0x55AA55,0x000000)

    -- AJOUT : bouton qui force vérification + application si newer
    local rForce  = drawBtn(20,  y,"[ Check & Update ]",0x55AAFF,0x000000); y=y+2


    local ev = { event.pull() }
    if ev[1] == "interrupted" then running=false
    elseif ev[1] == "key_down" then local _,_,_,code,ch = table.unpack(ev); if code==0x10 or ch==81 or ch==113 then running=false end
    elseif ev[1] == "touch" then local _,_,x,y = table.unpack(ev)
      if pointIn(rDest,x,y) then tmp.DEST_NAME = prompt("Destination", tmp.DEST_NAME)
      elseif pointIn(rOwn,x,y) then local v = prompt("Owner", tmp.OWNER); tmp.OWNER = (v=="" and nil or v)
      elseif pointIn(rP1,x,y)  then tmp.ACCESS_POLICY = "open"
      elseif pointIn(rP2,x,y)  then tmp.ACCESS_POLICY = "owner_plus_allow"
      elseif pointIn(rA1,x,y)  then local v = prompt("Add to ALLOW"); if v~="" then local ex=false for _,n in ipairs(tmp.ALLOW) do if n==v then ex=true end end if not ex then table.insert(tmp.ALLOW, v) end end
      elseif pointIn(rA2,x,y)  then local v = prompt("Remove from ALLOW"); if v~="" then for i=#tmp.ALLOW,1,-1 do if tmp.ALLOW[i]==v then table.remove(tmp.ALLOW,i) end end end
      elseif pointIn(rD1,x,y)  then local v = prompt("Add to DENY"); if v~="" then local ex=false for _,n in ipairs(tmp.DENY) do if n==v then ex=true end end if not ex then table.insert(tmp.DENY, v) end end
      elseif pointIn(rD2,x,y)  then local v = prompt("Remove from DENY"); if v~="" then for i=#tmp.DENY,1,-1 do if tmp.DENY[i]==v then table.remove(tmp.DENY,i) end end end
      elseif pointIn(rS,x,y)   then local order={"bottom","top","north","south","west","east"}; local cur=util.sideName(util.sideId(tmp.OUT_SIDE)); local idx=1 for i,n in ipairs(order) do if n==cur then idx=i end end idx=idx%#order+1; tmp.OUT_SIDE=order[idx]
      elseif pointIn(rSave,x,y) then saveFn(tmp); return util.deepcopy(tmp)
      elseif pointIn(rBack,x,y) then return
      elseif pointIn(rCheck,x,y) then
        local man, err = updater.fetchManifest(tmp)
        local msg = man and ("Latest="..(man.version or "?")) or ("Check failed: "..tostring(err))
        gpu.set(2,h-2,msg)

      elseif pointIn(rNow,x,y) then
        local man = updater.fetchManifest(tmp)
        if man then
          updater.apply(tmp, man)
          localVer = updater.getLocalVersion() or man.version or localVer
          gpu.set(2,h-2,"Applied "..tostring(localVer)..". Reopen to take effect.")
        else
          gpu.set(2,h-2,"Update failed")
        end

      elseif pointIn(rForce,x,y) then
        local man, err = updater.fetchManifest(tmp)
        if not man then
          gpu.set(2,h-2,"Check failed: "..tostring(err))
        else
          local cur = localVer or "0.0.0"
          local newer = (updater.cmpVersion(cur, man.version or "0.0.0") < 0)
          if newer then
            gpu.set(2,h-2,"Updating to "..tostring(man.version).."...")
            local ok, aerr = updater.apply(tmp, man)
            if ok then
              gpu.set(2,h-2,"Update applied. Rebooting...")
              os.sleep(0.6)
              computer.shutdown(true) -- redémarre pour charger le nouveau code
            else
              gpu.set(2,h-2,"Update failed: "..tostring(aerr))
            end
          else
            gpu.set(2,h-2,"Already up to date ("..tostring(cur)..")")
          end
        end

      end
    end
  end
end

return M