-- /home/setup.lua
-- Installe/Met à jour telehub-node depuis un repo GitHub (raw).
-- Usage :
--   setup --repo https://raw.githubusercontent.com/<owner>/<repo>/main --manifest manifest.lua --auto apply

local component = require("component")
local fs        = require("filesystem")
local computer  = require("computer")

local internet = component.internet  -- nécessite Internet Card

-- ——— parse args ————————————————————————————————————————————————————
local args = {...}
local function getArg(flag, def)
  for i=1,#args do
    if args[i] == flag and args[i+1] then return args[i+1] end
    local v = args[i]:match("^"..flag.."=(.+)$")
    if v then return v end
  end
  return def
end

local REPO     = getArg("--repo",     "https://raw.githubusercontent.com/KingoRodriguo/OpenComputer-Telehub/main")
local MANIFEST = getArg("--manifest", "manifest.lua")
local AUTO     = getArg("--auto",     "check")  -- off|check|apply

-- ——— util ————————————————————————————————————————————————————————
local function log(msg)
  io.write("[LOG] ", msg, "\n")
end

local function ensureDirForFile(path)
  local dir = fs.path(path)
  if dir and not fs.exists(dir) then
    log("Creating directory: "..dir)
    assert(fs.makeDirectory(dir))
  end
end

local function http_get(url, timeout)
  local deadline = (computer.uptime() + (timeout or 20))

  -- 1) Priorité au module 'internet' (meilleure prise en charge HTTPS/TLS/SNI)
  local ok_lib, inet = pcall(require, "internet")
  if ok_lib and inet and type(inet.request) == "function" then
    -- L’API renvoie un itérateur (request handle)
    local it, reason = inet.request(url, nil, {["User-Agent"]="telehub"})
    if not it then return nil, reason or "request_failed" end

    -- Si disponible, essayons de lire le status/headers
    local status, respHeaders
    if type(it.response) == "function" then
      status, respHeaders = it:response()  -- peut être nil tant que pas connecté
    end

    local data = ""
    for chunk in it do
      if chunk then data = data .. chunk end
      if timeout and computer.uptime() > deadline then
        return nil, "timeout"
      end
      if not status and type(it.response) == "function" then
        status, respHeaders = it:response()
      end
    end

    -- Si on a pu lire un status HTTP, vérifions-le
    if status and (status < 200 or status >= 300) then
      return nil, "http_status_"..tostring(status)
    end
    if #data == 0 then
      -- On tente un fallback bas niveau si le corps est vide
    else
      return data
    end
  end

  -- 2) Fallback composant bas niveau (moins fiable en HTTPS selon env)
  local ok_comp, comp = pcall(require, "component")
  if ok_comp and comp and comp.internet and type(comp.internet.request) == "function" then
    local handle, reason = comp.internet.request(url, nil, {["User-Agent"]="telehub"})
    if not handle then return nil, reason or "request_failed" end
    local data = ""
    for chunk in handle do
      if chunk then data = data .. chunk end
      if timeout and computer.uptime() > deadline then
        return nil, "timeout"
      end
    end
    if #data > 0 then return data end
  end

  return nil, "empty_response"
end

local function writeFile(path, content)
  ensureDirForFile(path)
  log("Writing file: "..path)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

-- ——— manifest ————————————————————————————————————————————————————
local function fetchManifest()
  local url = REPO .. "/" .. MANIFEST
  log("Fetching manifest: " .. url)

  local body, err = http_get(url, 20)
  assert(body, "manifest http error: " .. tostring(err))

  -- Debug: tête du contenu (utile pour voir si c’est du HTML/404)
  local head = (body:sub(1,120):gsub("%s"," "))
  log("Manifest head: " .. head)
  log("Manifest bytes: " .. tostring(#body))

  -- Sanitize: retire BOM UTF-8 + normalise CRLF
  if body:sub(1,3) == string.char(0xEF,0xBB,0xBF) then
    log("Stripping UTF-8 BOM")
    body = body:sub(4)
  end
  body = body:gsub("\r\n", "\n")

  -- Petit check heuristique
  if not body:match("^%s*return%s*%{") then
    log("Warning: manifest does not start with 'return {' (may still be valid)")
  end

  local tmp = "/home/_telehub_manifest.lua" -- OpenOS-safe
  writeFile(tmp, body)

  -- Utilise loadfile pour récupérer l’erreur exacte (au lieu de dofile direct)
  local lf, lerr = loadfile(tmp)
  if not lf then
    -- Sauvegarde une copie debug
    local dbg = "/home/_telehub_manifest.debug.lua"
    writeFile(dbg, body)
    error("manifest loadfile error: " .. tostring(lerr) .. " (debug copy: " .. dbg .. ")")
  end

  log("Executing manifest chunk")
  local ok, t = pcall(lf)
  fs.remove(tmp)

  if not ok then
    local dbg = "/home/_telehub_manifest.debug.lua"
    writeFile(dbg, body)
    error("manifest runtime error: " .. tostring(t) .. " (debug copy: " .. dbg .. ")")
  end

  assert(type(t) == "table", "manifest must return a table")
  assert(type(t.files) == "table", "manifest.files must be a table")

  local count = 0; for _ in pairs(t.files) do count = count + 1 end
  log("Manifest loaded: version=" .. tostring(t.version) .. " files=" .. count)
  return t
end


-- ——— téléchargement des fichiers listés ————————————————————————
local function downloadTo(path, url)
  log("Downloading "..url.." -> "..path)
  local data, err = http_get(url, 30)
  assert(data, "download failed: "..tostring(err))
  local tmp = path .. ".new"
  writeFile(tmp, data)
  if fs.exists(path) then
    log("Backup old file: "..path..".bak")
    pcall(fs.remove, path..".bak")
    pcall(fs.rename, path, path..".bak")
  end
  assert(fs.rename(tmp, path), "rename failed")
  log("Installed "..path)
end

-- ——— config ——————————————————————————————————————————————————————
local function loadConfig(path)
  if fs.exists(path) then
    log("Loading config: "..path)
    local ok, t = pcall(dofile, path)
    if ok and type(t) == "table" then return t end
    log("Config corrupted, recreating")
  end
  return {}
end

local function saveConfig(path, cfgTable)
  local ser = require("serialization")
  log("Saving config: "..path)
  writeFile(path, "return "..ser.serialize(cfgTable))
end

local function ensureConfig()
  local cfgDir = "/etc/telehub"
  local cfgPath = cfgDir.."/config.lua"
  if not fs.exists(cfgDir) then
    log("Creating config dir: "..cfgDir)
    fs.makeDirectory(cfgDir)
  end

  local cfg = loadConfig(cfgPath)
  cfg.UPDATE = cfg.UPDATE or {}
  cfg.UPDATE.AUTO     = AUTO
  cfg.UPDATE.REPO     = REPO
  cfg.UPDATE.MANIFEST = MANIFEST
  cfg.UPDATE.TIMEOUT  = cfg.UPDATE.TIMEOUT or 15

  saveConfig(cfgPath, cfg)
  log("Config updated with REPO="..REPO.." AUTO="..AUTO.." MANIFEST="..MANIFEST)
end

local function writeVersion(v)
  local vp = "/etc/telehub/version"
  writeFile(vp, tostring(v or "0.0.0"))
  log("Version set: "..tostring(v))
end

-- ——— main ————————————————————————————————————————————————————————
io.write("[*] telehub-node setup starting\n")
assert(REPO and REPO:match("^https?://"), "--repo must be a valid raw GitHub URL")

local man = fetchManifest()

local count = 0; for _ in pairs(man.files) do count = count + 1 end
log("Installing "..tostring(count).." files")

for src, dst in pairs(man.files) do
  local url = REPO .. "/" .. src
  downloadTo(dst, url)
end

ensureConfig()
writeVersion(man.version or "0.0.0")

io.write("[✓] Setup completed successfully.\n")
io.write("    Entry point: /usr/bin/telehub_node.lua\n")
io.write("    Run with: telehub_node.lua\n")
