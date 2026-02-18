local Path = require "obsidian.path"
local util = require "obsidian.util"
local paste_img = require("obsidian.img_paste").paste_img

---@param client obsidian.Client
return function(client, data)
  -- Detect --tmp-dir flag
  local use_tmp_dir = false
  ---@type string|?
  local args = data.args

  if args == "--tmp-dir" then
    use_tmp_dir = true
    args = nil
  elseif args ~= nil and vim.endswith(args, " --tmp-dir") then
    use_tmp_dir = true
    args = util.strip_whitespace(string.sub(args, 1, -string.len " --tmp-dir" - 1))
  end

  -- Determine folder based on flag
  local img_folder
  if use_tmp_dir then
    img_folder = util.get_tmp_dir_path(client.opts.attachments.img_folder)
  else
    img_folder = Path.new(client.opts.attachments.img_folder)
    if not img_folder:is_absolute() then
      img_folder = client.dir / client.opts.attachments.img_folder
    end
  end

  ---@type string|?
  local default_name
  if client.opts.attachments.img_name_func then
    default_name = client.opts.attachments.img_name_func()
  end

  local path = paste_img {
    fname = args,
    default_dir = img_folder,
    default_name = default_name,
    should_confirm = client.opts.attachments.confirm_img_paste,
  }

  if path ~= nil then
    util.insert_text(client.opts.attachments.img_text_func(client, path))
  end
end
