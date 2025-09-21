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

-- Fonction pour dessiner dynamiquement les options
local function drawOptions(options, w)
    local startY = 5
    local drawn = {}
    for i,opt in ipairs(options) do
        local y = startY + (i-1)*2
        gpu.set(3, y, opt.label or "-")
        if opt.type == "pill" then
            drawn[i] = drawPill(w-10, y, opt.text, opt.bg, opt.fg)
        elseif opt.type == "btn" then
            drawn[i] = drawBtn(w-10, y, opt.width or 10, 1, opt.bg, opt.fg, opt.text)
        elseif opt.type == "text" then
            gpu.set(22, y, tostring(opt.value or "-"))
        end
        opt._y = y -- sauvegarde la position pour les interactions
    end
    return drawn
end

function M.run(cfg, saveFn)
    local t = util.deepcopy(cfg)
    local w,h = gpu.getResolution()
    local running = true

    -- Table des options dynamiques
    local options = {
        {label="[owner_name]", type="pill", text="Edit", bg=0x88FF88, fg=0x000000, value=t.OWNER},
        {label="Destination name :", type="pill", text="Edit", bg=0x88FF88, fg=0x000000, value=t.DEST_NAME},
        {label="[policy_state]", type="pill", text="Allowed", bg=0x55AAFF, fg=0x000000, value=t.ACCESS_POLICY},
        {label="allow_list", type="btn", text="Add", bg=0x555555, fg=0xFFFFFF},
        {label="deny_list", type="btn", text="Add", bg=0x555555, fg=0xFFFFFF},
        {label="Redstone side :", type="pill", text="cycle", bg=0x555555, fg=0xFFFFFF, value=t.REDSTONE_SIDE},
    }

    while running do
        term.clear()
        -- Titre
        local title = "Configuration"
        gpu.set(util.centerX(gpu, title), 2, title)
        gpu.fill(2,3,w-2,1,"─")

        -- Dessiner options
        drawOptions(options, w)

        -- Bas : Cancel / Save
        local rCancel = drawBtn(2, h-1, 10,1, 0x88FF88,0x000000, "Cancel")
        local rSave   = drawBtn(w-11,h-1, 10,1, 0x88FF88,0x000000, "Save")

        -- Version
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

            -- Boucle sur les options pour gérer l'interaction
            for i,opt in ipairs(options) do
                if pointIn(opt, x, ty) then
                    if opt.label=="[owner_name]" then
                        local v = prompt("Owner", t.OWNER); t.OWNER = (v=="" and nil or v)
                    elseif opt.label=="Destination name :" then
                        t.DEST_NAME = prompt("Destination name", t.DEST_NAME)
                    elseif opt.label=="[policy_state]" then
                        t.ACCESS_POLICY = "owner_plus_allow"
                    elseif opt.label=="Redstone side :" then
                        local order={"bottom","top","north","south","west","east"}
                        local cur = util.sideName(util.sideId(t.REDSTONE_SIDE))
                        local idx=1; for i,n in ipairs(order) do if n==cur then idx=i end end
                        idx = idx % #order + 1; t.REDSTONE_SIDE = order[idx]
                    elseif opt.label=="allow_list" then
                        local v = prompt("Add to ALLOW")
                        if v~="" then
                            local ex=false; for _,n in ipairs(t.ALLOW) do if n==v then ex=true end end
                            if not ex then table.insert(t.ALLOW, v) end
                        end
                    elseif opt.label=="deny_list" then
                        local v = prompt("Add to DENY")
                        if v~="" then
                            local ex=false; for _,n in ipairs(t.DENY) do if n==v then ex=true end end
                            if not ex then table.insert(t.DENY, v) end
                        end
                    end
                end
            end

            if pointIn(rCancel,x,ty) then return nil
            elseif pointIn(rSave,x,ty) then
                saveFn(t); return util.deepcopy(t)
            end
        end
    end
end

return M
