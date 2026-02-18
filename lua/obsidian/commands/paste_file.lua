local Path = require "obsidian.path"
local util = require "obsidian.util"
local paste_file = require("obsidian.file_paste").paste_file

---@param client obsidian.Client
return function(client, data)
  -- Detect --tmp-dir flag
  local use_tmp_dir = false
  local args = data.args

  if args == "--tmp-dir" then
    use_tmp_dir = true
    args = nil
  elseif args ~= nil and vim.endswith(args, " --tmp-dir") then
    use_tmp_dir = true
    args = util.strip_whitespace(string.sub(args, 1, -string.len " --tmp-dir" - 1))
  end

  -- Determine folder based on flag
  local file_folder
  if use_tmp_dir then
    file_folder = util.get_tmp_dir_path(client.opts.attachments.file_folder)
  else
    file_folder = Path.new(client.opts.attachments.file_folder)
    if not file_folder:is_absolute() then
      file_folder = client.dir / client.opts.attachments.file_folder
    end
  end

  ---@type string|?
  local default_name
  if client.opts.attachments.file_name_func then
    default_name = client.opts.attachments.file_name_func()
  end

  local path = paste_file {
    fname = args,
    default_dir = file_folder,
    default_name = default_name,
    should_confirm = client.opts.attachments.confirm_file_paste,
  }

  if path ~= nil then
    util.insert_text(client.opts.attachments.file_text_func(client, path))
  end
end
