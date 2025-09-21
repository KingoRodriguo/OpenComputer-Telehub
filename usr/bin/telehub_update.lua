local fs       = require("filesystem")
local computer = require("computer")
local shell_ok, shell = pcall(require, "shell")

-- ---------- args ----------
local args = {...}
local function getOpt(flag, def)
    for i=1,#args do
        local a = args[i]
        if a==flag and args[i+1] and not tostring(args[i+1]):match("^%-%-") then return args[i+1] end
        local v = a:match("^"..flag.."=(.+)$")
        if v then return v end
    end
    return def
end
local function hasFlag(flag)
    for i=1,#args do if args[i]==flag then return true end end
    return false
end

local REPO     = getOpt("--repo", "https://raw.githubusercontent.com/KingoRodriguo/OpenComputer-Telehub/main")
local MANIFEST = getOpt("--manifest", "manifest.lua")
local FORCE    = hasFlag("--force")
local DEV      = hasFlag("--dev")

-- ---------- logs ----------
local function ts() return string.format("[%06.2f]", computer.uptime()) end
local function log(msg) io.write(ts()," ",msg,"\n"); io.flush() end

-- ---------- normalize REPO ----------
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
REPO = trim(REPO or "")
REPO = REPO:gsub("/+$",""):gsub("/main$",""):gsub("/dev$","")
REPO = REPO .. (DEV and "/dev" or "/main")
log("Using repo: "..REPO)
log("Using manifest: "..MANIFEST.."  (force="..tostring(FORCE)..", dev="..tostring(DEV)..")")

-- ---------- utils ----------
local function ensureDirForFile(path)
    local dir = fs.path(path)
    if dir and not fs.exists(dir) then assert(fs.makeDirectory(dir)) end
end

local function readFile(path)
    local f = io.open(path,"r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, content)
    ensureDirForFile(path)
    local f = assert(io.open(path,"w"))
    f:write(content)
    f:close()
end

-- ---------- HTTP get ----------
local function http_get(url, timeout)
    timeout = timeout or 25
    log("HTTP GET "..url)
    local ok, inet = pcall(require,"internet")
    if ok and inet and inet.request then
        local req = inet.request(url, nil, {["User-Agent"]="telehub-update"})
        if req then
            local data = ""
            for chunk in req do
                if chunk then data = data .. chunk end
                if computer.uptime() > timeout then return nil,"timeout" end
            end
            if #data>0 then return data end
        end
    end
    -- fallback wget
    if shell_ok and shell and shell.execute then
        local tmp = "/home/_http_tmp_"..tostring(math.random(1,1e9))
        local ok = shell.execute(string.format("wget %q %q", url, tmp))
        if ok then
            local data = readFile(tmp) or ""
            pcall(fs.remove,tmp)
            if #data>0 then return data end
        end
    end
    return nil,"http_failed"
end

-- ---------- version ----------
local VERSION_PATH = "/etc/telehub/version"
local function getLocalVersion()
    local v = readFile(VERSION_PATH)
    return v and v:match("%S+") or nil
end
local function setLocalVersion(v)
    writeFile(VERSION_PATH, tostring(v or "0.0.0"))
end

local function parseVer(v)
    local a,b,c = tostring(v or "0.0.0"):match("^(%d+)%.(%d+)%.?(%d*)$")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end
local function cmpVer(a,b)
    local a1,a2,a3=parseVer(a); local b1,b2,b3=parseVer(b)
    if a1~=b1 then return a1<b1 and -1 or 1 end
    if a2~=b2 then return a2<b2 and -1 or 1 end
    if a3~=b3 then return a3<b3 and -1 or 1 end
    return 0
end

-- ---------- manifest ----------
local function fetchManifest(repo, manifest)
    local url = repo .. "/" .. manifest
    log("Fetching manifest: "..url)
    local body, err = http_get(url,25)
    assert(body, "manifest http error: "..tostring(err))
    writeFile("/home/_telehub_manifest.cached.lua", body)
    local tmp = "/home/_telehub_manifest.lua"
    writeFile(tmp, body)
    local ok,t = pcall(dofile,tmp)
    pcall(fs.remove,tmp)
    assert(ok,"manifest syntax error: "..tostring(t))
    assert(type(t)=="table","manifest must return a table")
    assert(type(t.files)=="table","manifest.files must be a table")
    local n=0; for _ in pairs(t.files) do n=n+1 end
    log("Manifest ok. version="..tostring(t.version).." files="..n)
    return t
end

-- ---------- remplacement atomique ----------
local function replaceFile(dstPath,data)
    ensureDirForFile(dstPath)
    local tmp = dstPath..".new"
    writeFile(tmp,data)                       -- écrire le nouveau
    if fs.exists(dstPath) then                -- supprimer l’ancien seulement après
        assert(fs.remove(dstPath),"remove_failed: "..dstPath)
    end
    assert(fs.rename(tmp,dstPath),"rename_failed: "..dstPath)
    local got = readFile(dstPath) or ""
    assert(#got==#data,"verify_size_mismatch: "..dstPath)
end

local function downloadAndReplaceAll(repo, files)
    for src,dst in pairs(files) do
        local url = repo .. "/" .. src
        log("Download "..url)
        local data, err = http_get(url,30)
        assert(data and #data>0, "download_failed: "..tostring(err).." ("..url..")")
        log("Install -> "..dst)
        replaceFile(dst,data)
    end
end

-- ---------- main ----------
io.write("[*] telehub manual updater\n")
assert(REPO:match("^https?://"), "--repo must be a valid URL")
local man = fetchManifest(REPO,MANIFEST)
local cur = getLocalVersion() or "0.0.0"
log("Current version: "..cur.." | Remote: "..tostring(man.version or "?"))

if not FORCE and man.version and cmpVer(cur,man.version)>=0 then
    log("Already up-to-date. Use --force to reinstall.")
    return
end

downloadAndReplaceAll(REPO,man.files)
if man.version then setLocalVersion(man.version) end
log("Update complete.")
io.write("[✓] Done. You can now run: telehub_node.lua\n")
