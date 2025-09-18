local comp      = require("component")
local fs        = require("filesystem")
local ser       = require("serialization")
local util      = require("telehub.util")
local computer  = require("computer")

local internet = comp.internet

local M = {}
M.VERSION_PATH = "/etc/telehub/version"

local function ensureDir(path)
  local dir = fs.path(path) or "/"
  if not fs.exists(dir) then fs.makeDirectory(dir) end
end

local function http_get(url, timeout)
  if not internet then return nil, "no_internet_card" end
  local handle, reason = internet.request(url, nil, { ["User-Agent"] = "telehub" })
  if not handle then return nil, reason end
  local data = ""
  local deadline = computer.uptime() + (timeout or 15)
  for chunk in handle do
    if chunk then data = data .. chunk end
    if timeout and computer.uptime() > deadline then return nil, "timeout" end
  end
  return data
end

function M.getLocalVersion()
  if fs.exists(M.VERSION_PATH) then
    local f = io.open(M.VERSION_PATH, "r")
    if f then local v = f:read("*l"); f:close(); return v end
  end
  return nil
end

function M.setLocalVersion(v)
  ensureDir(M.VERSION_PATH)
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
  if a1~=b1 then return a1<b1 and -1 or 1 end
  if a2~=b2 then return a2<b2 and -1 or 1 end
  if a3~=b3 then return a3<b3 and -1 or 1 end
  return 0
end

function M.fetchManifest(cfg)
  local repo = cfg.UPDATE and cfg.UPDATE.REPO
  local manifest = (cfg.UPDATE and cfg.UPDATE.MANIFEST) or "manifest.lua"
  if not repo then return nil, "no_repo" end
  local url = repo .. "/" .. manifest
  local body, err = http_get(url, cfg.UPDATE.TIMEOUT or 15)
  if not body then return nil, err end
  local tmp = "/home/_telehub_manifest.lua"
  local f = assert(io.open(tmp, "w")); f:write(body); f:close()
  local ok, t = pcall(dofile, tmp)
  pcall(fs.remove, tmp)
  if not ok or type(t) ~= "table" then return nil, "bad_manifest" end
  return t
end

local function downloadTo(path, url, timeout)
  ensureDir(path)
  local data, err = http_get(url, timeout)
  if not data then return false, err end
  local tmp = path .. ".new"
  local f = assert(io.open(tmp, "w"))
  f:write(data)
  f:close()
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
  for src, dst in pairs(manifest.files) do
    local url = repo .. "/" .. src
    local ok, err = downloadTo(dst, url, cfg.UPDATE.TIMEOUT or 15)
    if not ok then return false, err end
    changed = true
  end
  if manifest.version then M.setLocalVersion(manifest.version) end
  return changed
end

function M.checkAndMaybeApply(cfg)
  local man = M.fetchManifest(cfg)
  if not man then return false end
  local cur = M.getLocalVersion() or "0.0.0"
  local newer = (M.cmpVersion(cur, man.version or "0.0.0") < 0)
  local mode = (cfg.UPDATE and cfg.UPDATE.AUTO) or "off"
  if newer and mode == "apply" then
    local ok = M.apply(cfg, man)
    return ok and true or false
  end
  return false
end

return M