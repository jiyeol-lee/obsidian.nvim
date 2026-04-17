local paste = require "obsidian.paste"

---@param client obsidian.Client
return function(client, _data)
  paste.paste(client)
end
