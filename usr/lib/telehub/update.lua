-- /usr/lib/telehub/update.lua
-- Module de mise à jour (utilisé par telehub_node.lua)

local comp      = require("component")
local fs        = require("filesystem")
local ser       = require("serialization")
local computer  = require("computer")

local internet = comp.internet  -- nécessite une Internet Card

local M = {}
M.VERSION_PATH = "/etc/telehub/version"

-- ——— util ————————————————————————————————————————————————————————

local function ensureDirForFile(path)
  local dir = fs.path(path)
  if dir and not fs.exists(dir) then
    fs.makeDirectory(dir)
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

-- ——— version ——————————————————————————————————————————————————————

function M.getLocalVersion()
  if fs.exists(M.VERSION_PATH) then
    local f = io.open(M.VERSION_PATH, "r")
    if f then local v = f:read("*l"); f:close(); return v end
  end
  return nil
end

function M.setLocalVersion(v)
  ensureDirForFile(M.VERSION_PATH)
  local f = assert(io.open(M.VERSION_PATH, "w"))
  f:write(tostring(v or "0.0.0"))
  f:close()
end

local function parseVer(v)
  local a,b,c = tostring(v or "0.0.0"):match("^(%d+)%.(%d+)%.?(%d*)$")
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

function M.cmpVersion(a,b)
  local a1,a2,a3 = parseVer(a)
  local b1,b2,b3 = parseVer(b)
  if a1 ~= b1 then return a1 < b1 and -1 or 1 end
  if a2 ~= b2 then return a2 < b2 and -1 or 1 end
  if a3 ~= b3 then return a3 < b3 and -1 or 1 end
  return 0
end

-- ——— manifest ————————————————————————————————————————————————————

function M.fetchManifest(cfg)
  local repo = cfg.UPDATE and cfg.UPDATE.REPO
  local manifest = (cfg.UPDATE and cfg.UPDATE.MANIFEST) or "telehub_manifest.lua"
  if not repo then return nil, "no_repo" end

  local url = repo .. "/" .. manifest
  local body, err = http_get(url, cfg.UPDATE and cfg.UPDATE.TIMEOUT or 15)
  if not body then return nil, err end

  local tmp = "/home/_telehub_manifest.lua"  -- OpenOS-safe
  ensureDirForFile(tmp)
  local f = assert(io.open(tmp, "w")); f:write(body); f:close()
  local ok, t = pcall(dofile, tmp)

  -- Supprimer ou garder selon config
  if not (cfg.UPDATE and cfg.UPDATE.KEEP_MANIFEST) then
    pcall(fs.remove, tmp)
  end

  if not ok then return nil, "manifest_syntax: " .. tostring(t) end
  if type(t) ~= "table" then return nil, "manifest_not_table" end
  if type(t.files) ~= "table" then return nil, "manifest_missing_files" end
  return t
end

-- ——— téléchargement & application ————————————————————————————————

local function downloadTo(path, url, timeout)
  local data, err = http_get(url, timeout)
  if not data then return false, err end
  ensureDirForFile(path)
  local tmp = path .. ".new"
  local f = assert(io.open(tmp, "w")); f:write(data); f:close()
  if fs.exists(path) then
    pcall(fs.remove, path..".bak")
    pcall(fs.rename, path, path..".bak")
  end
  pcall(fs.rename, tmp, path)
  return true
end

function M.apply(cfg, manifest)
  if not manifest or type(manifest.files) ~= "table" then return false, "no_files" end
  local repo = cfg.UPDATE and cfg.UPDATE.REPO
  if not repo then return false, "no_repo" end

  local changed = false
  local timeout = cfg.UPDATE and cfg.UPDATE.TIMEOUT or 15

  for src, dst in pairs(manifest.files) do
    local url = repo .. "/" .. src
    local ok, err = downloadTo(dst, url, timeout)
    if not ok then return false, "download_failed: "..tostring(src).." ("..tostring(err)..")" end
    changed = true
  end

  if manifest.version then M.setLocalVersion(manifest.version) end
  return changed
end

-- ——— workflow d’auto-update ————————————————————————————————

function M.checkAndMaybeApply(cfg)
  local man, err = M.fetchManifest(cfg)
  if not man then return false, err end

  local cur = M.getLocalVersion() or "0.0.0"
  local newer = (M.cmpVersion(cur, man.version or "0.0.0") < 0)
  local mode = (cfg.UPDATE and cfg.UPDATE.AUTO) or "off"

  if newer and mode == "apply" then
    local ok, aerr = M.apply(cfg, man)
    if not ok then return false, aerr end
    return true
  end
  return false
end

return M
