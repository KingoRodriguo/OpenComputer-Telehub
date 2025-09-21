-- telehub_uninstall.lua
-- Supprime tous les fichiers de Telehub définis dans le manifeste

local fs = require("filesystem")
local pcall = pcall
local manifestPath = "/home/_telehub_manifest.cached.lua" -- ou télécharge-le si nécessaire

-- charge le manifeste
local manifest
local f = io.open(manifestPath, "r")
if f then
    local s = f:read("*a")
    f:close()
    local tmp = "/home/_telehub_manifest_tmp.lua"
    local ftmp = io.open(tmp, "w")
    ftmp:write(s)
    ftmp:close()
    local ok, t = pcall(dofile,tmp)
    pcall(fs.remove,tmp)
    if ok and type(t)=="table" and type(t.files)=="table" then
        manifest = t
    else
        error("Impossible de charger le manifeste")
    end
else
    error("Manifeste non trouvé à "..manifestPath)
end

-- supprime un fichier si il existe
local function removeFile(path)
    if fs.exists(path) then
        local ok, err = pcall(fs.remove, path)
        if ok then
            print("Supprimé :", path)
        else
            print("Erreur suppression :", path, err)
        end
    else
        print("Fichier non trouvé :", path)
    end
end

-- supprime tous les fichiers listés dans le manifeste
for src, dst in pairs(manifest.files) do
    removeFile(dst)
end

-- supprime le fichier de version
removeFile("/etc/telehub/version")

-- Optionnel : supprimer les dossiers vides parents
local function removeEmptyDirs(path)
    local dir = fs.path(path)
    while dir and dir ~= "/" do
        if fs.exists(dir) then
            local ok, files = pcall(fs.list, dir)
            if ok and files then
                local empty = true
                for _ in files do empty = false; break end
                if empty then
                    local ok2, err2 = pcall(fs.remove, dir)
                    if ok2 then print("Dossier vide supprimé :", dir) end
                else
                    break
                end
            end
        end
        dir = fs.path(dir)
    end
end

-- supprime les dossiers vides parents des fichiers
for _, dst in pairs(manifest.files) do
    removeEmptyDirs(dst)
end

print("[✓] Telehub désinstallé")
