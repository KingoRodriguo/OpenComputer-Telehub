-- install.lua : installe/maj telehub-node depuis un repo GitHub (raw)
-- Usage:
--   install.lua --repo https://raw.githubusercontent.com/<owner>/<repo>/main [--manifest manifest.lua] [--auto off|check|apply]
local component=require("component")
local fs=require("filesystem")
local computer=require("computer")

local internet=component.internet
local args={...}
local function getArg(flag,def)
  for i=1,#args do
    if args[i]==flag and args[i+1] then return args[i+1] end
    local v=args[i]:match("^"..flag.."=(.+)$"); if v then return v end
  end
  return def
end

local REPO=getArg("--repo","https://raw.githubusercontent.com/KingoRodriguo/OpenComputer-Telehub/main")
local MANIFEST=getArg("--manifest","manifest.lua")
local AUTO=getArg("--auto","apply") -- off|check|apply

local function ensureDir(path)
  local dir=fs.path(path) or "/"
  if not fs.exists(dir) then assert(fs.makeDirectory(dir)) end
end

local function http_get(url,timeout)
  if not internet then return nil,"no_internet_card" end
  local handle,reason=internet.request(url,nil,{["User-Agent"]="telehub-installer"})
  if not handle then return nil,reason end
  local data=""; local deadline=computer.uptime()+(timeout or 20)
  for chunk in handle do
    if chunk then data=data..chunk end
    if timeout and computer.uptime()>deadline then return nil,"timeout" end
  end
  return data
end

local function writeFile(path,content)
  ensureDir(path)
  local f=assert(io.open(path,"w")); f:write(content); f:close()
end

local function fetchManifest()
  local url = REPO.."/"..MANIFEST
  io.write("[+] Fetch manifest: ", url, "\n")
  local body, err = http_get(url, 20); assert(body, "manifest http error: "..tostring(err))
  local tmp = "/tmp/_manifest.lua"
  writeFile(tmp, body)
  -- juste après body=...
  if not body then error("manifest http error: "..tostring(err)) end
  print("[debug] first bytes:", (body:sub(1,80):gsub("%s"," ")))

  local ok, t = pcall(dofile, tmp)
  fs.remove(tmp)
  if not ok then
    error("manifest syntax error: "..tostring(t))
  end
  assert(type(t)=="table", "manifest must return a table")
  assert(type(t.files)=="table", "manifest.files must be a table")
  return t
end

local function downloadTo(path,url)
  io.write("    -> ",path,"\n")
  ensureDir(path)
  local data,err=http_get(url,30); assert(data,"download failed: "..tostring(err))
  local tmp=path..".new"
  writeFile(tmp,data)
  if fs.exists(path) then pcall(fs.remove,path..".bak"); pcall(fs.rename,path,path..".bak") end
  assert(fs.rename(tmp,path),"rename failed")
end

local function ensureConfig()
  local dir="/etc/telehub"; local cfg=dir.."/config.lua"
  if not fs.exists(dir) then fs.makeDirectory(dir) end
  if not fs.exists(cfg) then
    io.write("[+] Create default config: ",cfg,"\n")
    local content=table.concat({
      "return {",
      "  UPDATE = {",
      "    AUTO = "..string.format("%q",AUTO)..",",
      "    REPO = "..string.format("%q",REPO)..",",
      "    MANIFEST = "..string.format("%q",MANIFEST)..",",
      "    TIMEOUT = 15,",
      "  },",
      "}\n"
    },"\n")
    writeFile(cfg,content)
  else
    -- Patch REPO/MANIFEST/AUTO si déjà présent (simple remplacement en l'état)
    local f=io.open(cfg,"r"); local cur=f and f:read("*a") or ""; if f then f:close() end
    if cur=="" then
      writeFile(cfg,"return { UPDATE = { AUTO="..string.format("%q",AUTO)..", REPO="..string.format("%q",REPO)..", MANIFEST="..string.format("%q",MANIFEST)..", TIMEOUT=15 }, }\n")
    elseif (not cur:find(REPO,1,true)) or (not cur:find(MANIFEST,1,true)) then
      io.write("[i] Updating UPDATE fields in existing config\n")
      -- très basique: on ajoute/écrase un bloc UPDATE à la fin
      cur = cur:gsub("%s*$","")
      if not cur:match("return%s*{") then cur="return {\n"..cur.."\n}" end
      cur = cur:gsub("}%s*$", "  ,UPDATE = { AUTO="..string.format("%q",AUTO)..", REPO="..string.format("%q",REPO)..", MANIFEST="..string.format("%q",MANIFEST)..", TIMEOUT=15 },\n}\n")
      writeFile(cfg,cur)
    end
  end
end

local function writeVersion(v)
  local vp="/etc/telehub/version"
  io.write("[+] Set version: ",v or "0.0.0","\n")
  writeFile(vp,tostring(v or "0.0.0"))
end

-- main
io.write("[*] telehub-node installer\n")
assert(REPO and REPO:match("^https?://"),"--repo raw GitHub URL required")
local man=fetchManifest()
io.write("[+] Installing files (",tostring(#(function(t)local c=0;for _ in pairs(t) do c=c+1 end; return setmetatable({c}, {__len=function() return c end}) end)(man.files)),")\n") -- affiche le nombre approx
for src,dst in pairs(man.files) do
  local url=REPO.."/"..src
  downloadTo(dst,url)
end
ensureConfig()
writeVersion(man.version or "0.0.0")
io.write("[✓] Done. Entry point: /usr/bin/telehub_node.lua\n")
io.write("    Run: telehub_node.lua\n")
