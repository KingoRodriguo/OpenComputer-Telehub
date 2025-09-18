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

local REPO     = getArg("--repo",     "https://raw.githubusercontent.com/<owner>/<repo>/main")
local MANIFEST = getArg("--manifest", "manifest.lua")
local AUTO     = getArg("--auto",     "check")  -- off|check|apply

-- ——— util ————————————————————————————————————————————————————————
local function ensureDirForFile(path)
  local dir = fs.path(path)
  if dir and not fs.exists(dir) then
    assert(fs.makeDirectory(dir))
  end
end

local function http_get(url, timeout)
  if not internet then return nil, "no_internet_card" end
  local handle, reason = internet.request(url, nil, {["User-Agent"]="telehub-setup"})
  if not handle then return nil, reason end
  local data = ""
  local deadline = computer.uptime() + (timeout or 20)
  for chunk in handle do
    if chunk then data = data .. chunk end
    if timeout and computer.uptime() > deadline then
      return nil, "timeout"
    end
  end
  return data
end

local function writeFile(path, content)
  ensureDirForFile(path)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

-- ——— manifest ————————————————————————————————————————————————————
local function fetchManifest()
  local url = REPO .. "/" .. MANIFEST
  io.write("[+] Fetch manifest: ", url, "\n")

  local body, err = http_get(url, 20)
  assert(body, "manifest http error: "..tostring(err))

  local tmp = "/home/_telehub_manifest.lua"  -- OpenOS-safe
  writeFile(tmp, body)

  local ok, t = pcall(dofile, tmp)
  fs.remove(tmp)

  assert(ok, "manifest syntax error: "..tostring(t))
  assert(type(t) == "table", "manifest must return a table")
  assert(type(t.files) == "table", "manifest.files must be a table")
  return t
end

-- ——— téléchargement des fichiers listés ————————————————————————
local function downloadTo(path, url)
  io.write("    -> ", path, "\n")
  local data, err = http_get(url, 30)
  assert(data, "download failed: "..tostring(err))
  local tmp = path .. ".new"
  writeFile(tmp, data)
  if fs.exists(path) then
    pcall(fs.remove, path..".bak")
    pcall(fs.rename, path, path..".bak")
  end
  assert(fs.rename(tmp, path), "rename failed")
end

-- ——— config ——————————————————————————————————————————————————————
local function loadConfig(path)
  if fs.exists(path) then
    local ok, t = pcall(dofile, path)
    if ok and type(t) == "table" then return t end
  end
  return {}
end

local function saveConfig(path, cfgTable)
  local ser = require("serialization")
  writeFile(path, "return "..ser.serialize(cfgTable))
end

local function ensureConfig()
  local cfgDir = "/etc/telehub"
  local cfgPath = cfgDir.."/config.lua"
  if not fs.exists(cfgDir) then fs.makeDirectory(cfgDir) end

  local cfg = loadConfig(cfgPath)
  cfg.UPDATE = cfg.UPDATE or {}
  cfg.UPDATE.AUTO     = AUTO
  cfg.UPDATE.REPO     = REPO
  cfg.UPDATE.MANIFEST = MANIFEST
  cfg.UPDATE.TIMEOUT  = cfg.UPDATE.TIMEOUT or 15

  saveConfig(cfgPath, cfg)
  io.write("[+] Config written: ", cfgPath, "\n")
end

local function writeVersion(v)
  local vp = "/etc/telehub/version"
  writeFile(vp, tostring(v or "0.0.0"))
  io.write("[+] Version set: ", v or "0.0.0", "\n")
end

-- ——— main ————————————————————————————————————————————————————————
io.write("[*] telehub-node setup\n")
assert(REPO and REPO:match("^https?://"), "--repo must be a valid raw GitHub URL")
local man = fetchManifest()

-- compte simple des fichiers
local count = 0; for _ in pairs(man.files) do count = count + 1 end
io.write("[+] Installing files (", tostring(count), ")\n")

for src, dst in pairs(man.files) do
  local url = REPO .. "/" .. src
  downloadTo(dst, url)
end

ensureConfig()
writeVersion(man.version or "0.0.0")

io.write("[✓] Done.\n")
io.write("    Entry point: /usr/bin/telehub_node.lua\n")
io.write("    Run: telehub_node.lua\n")
