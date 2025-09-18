local util = require("telehub.util")
local M = {}

function M.allowedFor(name, cfg)
  if name == nil then return cfg.ACCESS_POLICY == "open" end
  if util.inList(cfg.DENY, name) then return false end
  if cfg.ACCESS_POLICY == "open" then return true end
  if cfg.OWNER and name == cfg.OWNER then return true end
  if util.inList(cfg.ALLOW, name) then return true end
  return false
end

return M