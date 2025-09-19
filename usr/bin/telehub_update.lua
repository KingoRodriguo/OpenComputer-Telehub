-- /usr/bin/telehub_update.lua
-- MAJ manuelle : vérifie le manifest, compare la version, remplace les fichiers.
-- Usage:
--   telehub_update --repo https://raw.githubusercontent.com/KingoRodriguo/OpenComputer-Telehub/main --manifest telehub_manifest.lua
--   telehub_update --repo ... --manifest ... --force   (installe même si version identique)

local fs        = require("filesystem")
local computer  = require("computer")

-- ---------- args ----------
local args = {...}
local function getArg(flag, def)
  for i=1,#args do
    if args[i]==flag and args[i+1] then return args[i+1] end
    local v = args[i]:match("^"..flag.."=(.+)$"); if v then return v end
  end
  return def
end

local REPO     = getArg("--repo",     "https://raw.githubusercontent.com/KingoRodriguo/OpenComputer-Telehub/main")
local MANIFEST = getArg("--manifest", "telehub_manifest.lua")
local FORCE    = getArg("--force",    nil) ~= nil

-- ---------- log ----------
local function ts() return string.format("[%06.2f]", computer.uptime()) end
local function log(msg) io.write(ts()," ",msg,"\n"); io.flush() end

-- ---------- utils ----------
local function ensureDirForFile(path)
  local dir = fs.path(path)
  if dir and not fs.exists(dir) then assert(fs.makeDirectory(dir)) end
end

local function http_get(url, timeout)
  local deadline = computer.uptime() + (timeout or 25)

  -- priorité au module 'internet' (HTTPS/TLS OK)
  local ok_lib, inet = pcall(require, "internet")
  if ok_lib and inet and type(inet.request)=="function" then
    local it, reason = inet.request(url, nil, {["User-Agent"]="telehub-update"})
    if not it then return nil, reason or "request_failed" end
    local status
    if type(it.response)=="function" then status = (it:response()) end
    local data = ""
    for chunk in it do
      if chunk then data = data .. chunk end
      if computer.uptime() > deadline then return nil, "timeout" end
      if not status and type(it.response)=="function" then status = (it:response()) end
    end
    if status and (status < 200 or status >= 300) then return nil, "http_status_"..tostring(status) end
    if #data > 0 then return data end
  end

  -- fallback composant (si dispo)
  local ok_comp, comp = pcall(require, "component")
  if ok_comp and comp and comp.internet and type(comp.internet.request)=="function" then
    local h, reason = comp.internet.request(url, nil, {["User-Agent"]="telehub-update"})
    if not h then return nil, reason or "request_failed" end
    local data = ""
    for chunk in h do
      if chunk then data = data .. chunk end
      if computer.uptime() > deadline then return nil, "timeout" end
    end
    if #data > 0 then return data end
  end

  return nil, "empty_response"
end

local function readFile(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local function writeFile(path, content)
  ensureDirForFile(path)
  local f = assert(io.open(path, "w"))
  f:write(content); f:close()
end

-- ---------- version ----------
local VERSION_PATH = "/etc/telehub/version"
local function getLocalVersion()
  local f = io.open(VERSION_PATH, "r")
  if not f then return nil end
  local v = f:read("*l"); f:close(); return v
end
local function setLocalVersion(v)
  writeFile(VERSION_PATH, tostring(v or "0.0.0"))
end
local function parseVer(v)
  local a,b,c = tostring(v or "0.0.0"):match("^(%d+)%.(%d+)%.?(%d*)$")
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end
local function cmpVer(a,b)
  local a1,a2,a3 = parseVer(a); local b1,b2,b3 = parseVer(b)
  if a1~=b1 then return a1<b1 and -1 or 1 end
  if a2~=b2 then return a2<b2 and -1 or 1 end
  if a3~=b3 then return a3<b3 and -1 or 1 end
  return 0
end

-- ---------- manifest ----------
local function fetchManifest(repo, manifest)
  local url = repo .. "/" .. manifest
  log("Fetching manifest: "..url)
  local body, err = http_get(url, 25)
  assert(body, "manifest http error: "..tostring(err))
  -- garde une copie debug si besoin
  writeFile("/home/_telehub_manifest.cached.lua", body)

  local tmp = "/home/_telehub_manifest.lua"
  writeFile(tmp, body)
  local ok, t = pcall(dofile, tmp)
  pcall(fs.remove, tmp)

  assert(ok, "manifest syntax error: "..tostring(t))
  assert(type(t)=="table", "manifest must return a table")
  assert(type(t.files)=="table", "manifest.files must be a table")
  local n=0; for _ in pairs(t.files) do n=n+1 end
  log("Manifest ok. version="..tostring(t.version).." files="..n)
  return t
end

-- ---------- installer (remplace) ----------
local function replaceFile(dstPath, data)
  ensureDirForFile(dstPath)
  -- supprime l'ancien fichier si présent
  if fs.exists(dstPath) then
    log("Removing old: "..dstPath)
    pcall(fs.remove, dstPath)
  end
  -- écrit le nouveau
  local tmp = dstPath..".new"
  writeFile(tmp, data)
  assert(fs.rename(tmp, dstPath), "rename_failed")
  -- vérif simple
  local got = readFile(dstPath) or ""
  assert(#got == #data, "verify_size_mismatch")
end

local function downloadAndReplaceAll(repo, files)
  for src, dst in pairs(files) do
    local url = repo .. "/" .. src
    log("Download "..url)
    local data, err = http_get(url, 30)
    assert(data and #data>0, "download_failed: "..tostring(err))
    log("Install -> "..dst)
    replaceFile(dst, data)
  end
end

-- ---------- main ----------
io.write("[*] telehub manual updater\n")
assert(REPO and REPO:match("^https?://"), "--repo must be a valid raw GitHub URL")

local man = fetchManifest(REPO, MANIFEST)
local cur = getLocalVersion() or "0.0.0"
log("Current version: "..cur.." | Remote: "..tostring(man.version or "?"))

if (not FORCE) and man.version and (cmpVer(cur, man.version) >= 0) then
  log("Already up-to-date. Use --force to reinstall.")
  return
end

downloadAndReplaceAll(REPO, man.files)
if man.version then setLocalVersion(man.version) end
log("Update complete.")
io.write("[✓] Done. You can now run: telehub_node.lua\n")
