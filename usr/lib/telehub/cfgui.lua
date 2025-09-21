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

-- Dessine une ligne composée de plusieurs éléments
local function drawLine(line, y)
    local x = 3
    local drawn = {}
    for i, el in ipairs(line) do
        local r
        if el.type=="text" then
            gpu.set(x,y,tostring(el.value or ""))
            r={x1=x,y1=y,x2=x+W(el.value or "")-1,y2=y,element=el}
            x = r.x2 + 2
        elseif el.type=="pill" then
            r = drawPill(x,y,el.text or "", el.bg or 0x555555, el.fg or 0xFFFFFF)
            r.element = el
            x = r.x2 + 2
        elseif el.type=="btn" then
            local w = el.width or 10
            r = drawBtn(x,y,w,1, el.bg or 0x555555, el.fg or 0xFFFFFF, el.text or "")
            r.element = el
            x = r.x2 + 2
        end
        drawn[#drawn+1] = r
    end
    return drawn
end

function M.run(cfg, saveFn)
    local t = util.deepcopy(cfg)
    local w,h = gpu.getResolution()

    -- Définir l'interface par lignes
    local lines = {
        -- Ligne 1 : Owner
        {
            {type="text", value="[owner_name test]"},
            {type="pill", text="Edit", value=t.OWNER, bg=0x88FF88, fg=0x000000},
        },
        -- Ligne 2 : Destination
        {
            {type="text", value="Destination name :"},
            {type="pill", text="Edit", value=t.DEST_NAME, bg=0x88FF88, fg=0x000000},
        },
        -- Ligne 3 : Policy
        {
            {type="text", value="[policy_state]"},
            {type="pill", text="Allowed", bg=0x55AAFF, fg=0x000000},
            {type="pill", text="Deny", bg=0xCC4444, fg=0x000000},
            {type="pill", text="Open", bg=0x88FF88, fg=0x000000},
        },
        -- Ligne 4 : Allow list
        {
            {type="text", value="allow_list"},
            {type="btn", text="Add", bg=0x555555, fg=0xFFFFFF},
            {type="btn", text="Del", bg=0x555555, fg=0xFFFFFF},
            {type="text", value=listToStr(t.ALLOW)},
        },
        -- Ligne 5 : Deny list
        {
            {type="text", value="deny_list"},
            {type="btn", text="Add", bg=0x555555, fg=0xFFFFFF},
            {type="btn", text="Del", bg=0x555555, fg=0xFFFFFF},
            {type="text", value=listToStr(t.DENY)},
        },
        -- Ligne 6 : Redstone side
        {
            {type="text", value="Redstone side :"},
            {type="text", value=t.REDSTONE_SIDE},
            {type="pill", text="cycle", value=t.REDSTONE_SIDE, bg=0x555555, fg=0xFFFFFF},
        },
        -- Ligne 7 : Teleposer side
        {
            {type="text", value="Teleposer side :"},
            {type="text", value=t.TRANSPOSER_TELEPOSER_SIDE},
            {type="pill", text="cycle", value=t.REDSTONE_SIDE, bg=0x555555, fg=0xFFFFFF},
        },
        -- Ligne 8 : Storage side
        {
            {type="text", value="Storage side :"},
            {type="text", value=t.TRANSPOSER_STORAGE_SIDE},
            {type="pill", text="cycle", value=t.REDSTONE_SIDE, bg=0x555555, fg=0xFFFFFF},
        },

        -- Ligne 9 : test
        {type="text", value="Test line"},
        {type="pill", text="cycle", value=t.REDSTONE_SIDE, bg=0x555555, fg=0xFFFFFF},
    }

    while true do
        term.clear()
        local title = "Configuration"
        gpu.set(util.centerX(gpu, title),2,title)
        gpu.fill(2,3,w-2,1,"─")

        local drawnElements = {}
        for i,line in ipairs(lines) do
            local y = 5 + (i-1)*2
            local drawn = drawLine(line, y)
            for _,d in ipairs(drawn) do
                drawnElements[#drawnElements+1] = d
            end
        end

        -- Bas : Cancel / Save
        local rCancel = drawBtn(2,h-1,10,1,0x88FF88,0x000000,"Cancel")
        local rSave   = drawBtn(w-11,h-1,10,1,0x88FF88,0x000000,"Save")

        -- Version
        local v = upd.getLocalVersion() or "0.0.0"
        local vstr = "v"..v
        gpu.set(w-W(vstr),h,vstr)

        local ev = {event.pull()}
        if ev[1]=="interrupted" then return nil end
        if ev[1]=="key_down" then
            local _,_,_,code,ch = table.unpack(ev)
            if code==0x10 or ch==81 or ch==113 then return nil end
        elseif ev[1]=="touch" then
            local _,_,x,ty = table.unpack(ev)

            for _,d in ipairs(drawnElements) do
                local el = d.element
                if pointIn(d,x,ty) then
                    if el.type=="pill" then
                        if el.text=="Edit" then
                            el.value = prompt(el.text, el.value)
                            -- Mettre à jour la valeur dans la table t
                            if el == lines[1][2] then t.OWNER = el.value
                            elseif el == lines[2][2] then t.DEST_NAME = el.value
                            elseif el == lines[6][2] then
                                local order={"bottom","top","north","south","west","east"}
                                local cur = util.sideName(util.sideId(t.REDSTONE_SIDE))
                                local idx=1; for i,n in ipairs(order) do if n==cur then idx=i end end
                                idx = idx % #order + 1; t.REDSTONE_SIDE = order[idx]
                                el.value = t.REDSTONE_SIDE
                            end
                        else
                            t.ACCESS_POLICY = el.text
                        end
                    elseif el.type=="btn" then
                        if el.text=="Add" then
                            if lines[4][2]==el then
                                local v = prompt("Add to ALLOW")
                                if v~="" then local ex=false; for _,n in ipairs(t.ALLOW) do if n==v then ex=true end end; if not ex then table.insert(t.ALLOW,v) end end
                            elseif lines[5][2]==el then
                                local v = prompt("Add to DENY")
                                if v~="" then local ex=false; for _,n in ipairs(t.DENY) do if n==v then ex=true end end; if not ex then table.insert(t.DENY,v) end end
                            end
                        elseif el.text=="Del" then
                            if lines[4][3]==el then
                                local v = prompt("Remove from ALLOW")
                                if v~="" then for i=#t.ALLOW,1,-1 do if t.ALLOW[i]==v then table.remove(t.ALLOW,i) end end end
                            elseif lines[5][3]==el then
                                local v = prompt("Remove from DENY")
                                if v~="" then for i=#t.DENY,1,-1 do if t.DENY[i]==v then table.remove(t.DENY,i) end end end
                            end
                        end
                    end
                end
            end

            if pointIn(rCancel,x,ty) then return nil
            elseif pointIn(rSave,x,ty) then saveFn(t); return util.deepcopy(t)
            end
        end
    end
end

return M
