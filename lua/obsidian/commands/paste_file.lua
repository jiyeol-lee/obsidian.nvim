local Path = require "obsidian.path"
local util = require "obsidian.util"
local paste_file = require("obsidian.file_paste").paste_file

---@param client obsidian.Client
return function(client, data)
  local file_folder = Path.new(client.opts.attachments.file_folder)
  if not file_folder:is_absolute() then
    file_folder = client.dir / client.opts.attachments.file_folder
  end

  ---@type string|?
  local default_name
  if client.opts.attachments.file_name_func then
    default_name = client.opts.attachments.file_name_func()
  end

  local path = paste_file {
    fname = data.args,
    default_dir = file_folder,
    default_name = default_name,
    should_confirm = client.opts.attachments.confirm_file_paste,
  }

  if path ~= nil then
    util.insert_text(client.opts.attachments.file_text_func(client, path))
  end
end
