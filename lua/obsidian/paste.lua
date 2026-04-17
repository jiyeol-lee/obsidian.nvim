local Path = require "obsidian.path"
local log = require "obsidian.log"
local util = require "obsidian.util"
local run_job = require("obsidian.async").run_job

local M = {}

--- Clean up a temporary file.
---
---@param path string|? The path to the file to remove
---@return boolean success Whether the file was successfully removed
local function _cleanup_temp_file(path)
  if not path or path == "" then
    return false
  end

  local ok, err = os.remove(path)
  if not ok then
    log.warn("Failed to clean up temporary file: %s (%s)", path, err or "unknown error")
    return false
  end

  return true
end

--- Display name for OS in error messages.
local function os_display_name(os_type)
  if os_type == util.OSType.Darwin then
    return "macOS"
  elseif os_type == util.OSType.Linux then
    return "Linux"
  elseif os_type == util.OSType.Windows then
    return "Windows"
  elseif os_type == util.OSType.Wsl then
    return "WSL"
  elseif os_type == util.OSType.FreeBSD then
    return "FreeBSD"
  else
    return tostring(os_type)
  end
end

--- Check if running on Wayland.
local function _is_wayland()
  if vim.env.WAYLAND_DISPLAY then
    return true
  end
  if vim.env.XDG_SESSION_TYPE == "wayland" then
    return true
  end
  return false
end

--- Check if required tool is available for clipboard detection.
--- Returns (available, missing_tool_name).
local function check_tool_available(clip_type)
  local os_type = util.get_os()

  if clip_type == "image" then
    if os_type == util.OSType.Darwin then
      if vim.fn.executable "pngpaste" == 0 then
        return false, "pngpaste"
      end
    elseif os_type == util.OSType.Linux or os_type == util.OSType.FreeBSD then
      if _is_wayland() then
        if vim.fn.executable "wl-paste" == 0 then
          return false, "wl-paste"
        end
      else
        if vim.fn.executable "xclip" == 0 then
          return false, "xclip"
        end
      end
    end
    -- Windows/WSL: PowerShell always available
  end

  return true, nil
end

--- Check if clipboard has image data.
--- Adapted from existing clipboard_is_img() in img_paste.lua.
local function _clipboard_has_image_data()
  local this_os = util.get_os()

  -- Build check command
  local check_cmd
  if this_os == util.OSType.Linux or this_os == util.OSType.FreeBSD then
    if _is_wayland() then
      check_cmd = "wl-paste --list-types"
    else
      check_cmd = "xclip -selection clipboard -o -t TARGETS"
    end
  elseif this_os == util.OSType.Darwin then
    check_cmd = "pngpaste -b 2>&1"
  elseif this_os == util.OSType.Windows or this_os == util.OSType.Wsl then
    check_cmd = 'powershell.exe "Get-Clipboard -Format Image"'
  else
    return false
  end

  -- Execute check
  local ok, handle = pcall(io.popen, check_cmd)
  if not ok or not handle then
    return false
  end

  local content = {}
  for line in handle:lines() do
    content[#content + 1] = line
  end
  handle:close()

  if this_os == util.OSType.Linux or this_os == util.OSType.FreeBSD then
    return vim.tbl_contains(content, "image/png")
  elseif this_os == util.OSType.Darwin then
    return #content > 0 and string.sub(content[1], 1, 9) == "iVBORw0KG"
  elseif this_os == util.OSType.Windows or this_os == util.OSType.Wsl then
    return #content > 0
  end

  return false
end

--- Check if clipboard has a file path (macOS only).
--- Returns (path_or_nil). On non-macOS, always returns nil.
--- NOTE: Does NOT check if the file exists — that's done in paste() flow.
local function _clipboard_has_file_path()
  local os_type = util.get_os()
  if os_type ~= util.OSType.Darwin then
    return nil
  end

  local ok, handle = pcall(
    io.popen,
    [[
    osascript -e '
    set theFiles to (the clipboard as «class furl») as list
    set thePaths to {}
    repeat with aFile in theFiles
        set end of thePaths to POSIX path of aFile
    end repeat
    return thePaths as text
    '
  ]]
  )
  if not ok or not handle then
    return nil
  end

  local content = handle:read "*a"
  handle:close()
  content = content:gsub("%s+$", "")

  if content == "" then
    return nil
  end

  return content
end

--- Detect clipboard content type.
--- Returns (type, cached_path_or_nil).
--- - "image", nil — clipboard has image data
--- - "file_path", "<path>" — clipboard has a file selection (macOS only)
--- - nil, nil — no clipboard content detected
local function detect_clipboard_type()
  -- Check image first (takes priority)
  if _clipboard_has_image_data() then
    return "image", nil
  end

  -- Check file path (macOS only)
  local file_path = _clipboard_has_file_path()
  if file_path then
    return "file_path", file_path
  end

  return nil, nil
end

--- Save clipboard image data to a specific path.
--- Adapted from existing save_clipboard_image() in img_paste.lua.
---
---@param path string The path to save the image to
---@return boolean|integer|? result
local function _save_clipboard_image_to_path(path)
  local this_os = util.get_os()

  if this_os == util.OSType.Linux or this_os == util.OSType.FreeBSD then
    local cmd
    if _is_wayland() then
      cmd = string.format("wl-paste --no-newline --type image/png > '%s'", path)
    else
      cmd = string.format("xclip -selection clipboard -t image/png -o > '%s'", path)
    end

    local result = os.execute(cmd)
    if type(result) == "number" and result > 0 then
      return false
    else
      return result
    end
  elseif this_os == util.OSType.Windows or this_os == util.OSType.Wsl then
    local cmd = 'powershell.exe -c "'
      .. string.format("(get-clipboard -format image).save('%s', 'png')", string.gsub(path, "/", "\\"))
      .. '"'
    return os.execute(cmd)
  elseif this_os == util.OSType.Darwin then
    return run_job("pngpaste", { path })
  else
    log.err("Image saving not implemented for OS '%s'", os_display_name(this_os))
    return false
  end
end

--- Save clipboard image to a temporary file.
---
---@return obsidian.Path|? temp_path The path to the saved temp file, or nil on failure
local function save_clipboard_image_to_tmp()
  math.randomseed(os.time())

  local tmp_dir = Path.new(util.get_tmp_dir_path "obsidian-paste")
  local ok = pcall(function()
    tmp_dir:mkdir { exist_ok = true, parents = true }
  end)
  if not ok or not tmp_dir:exists() then
    log.err "Failed to create temporary directory for clipboard image"
    return nil
  end

  local filename = "clipboard_image_" .. os.time() .. "_" .. tostring(math.random(100000, 999999)) .. ".png"
  local file_path = tmp_dir / filename

  local result = _save_clipboard_image_to_path(tostring(file_path))
  if result == false then
    log.err "Failed to save clipboard image to temporary file"
    -- Attempt to clean up temp directory (ignore errors)
    pcall(function()
      os.remove(tostring(tmp_dir))
    end)
    return nil
  end

  return file_path
end

--- Main paste entry point.
---
---@param client obsidian.Client
M.paste = function(client)
  -- Validate callbacks are configured
  local upload_func = client.opts.attachments.upload_func
  local file_text_func = client.opts.attachments.file_text_func

  if not upload_func then
    log.err "attachments.upload_func is not configured. Please set it in your obsidian.nvim config."
    return
  end
  if not file_text_func then
    log.err "attachments.file_text_func is not configured. Please set it in your obsidian.nvim config."
    return
  end

  -- Detect clipboard type (wrapped in pcall for safety)
  local clip_type, cached_path
  local ok, err = pcall(function()
    clip_type, cached_path = detect_clipboard_type()
  end)
  if not ok then
    log.err("Clipboard detection failed: %s", err)
    return
  end
  if not clip_type then
    log.err "No image data or file path found in clipboard"
    return
  end

  -- Get source path
  local source_path
  local is_temp = false

  if clip_type == "image" then
    -- Check tool availability for image clipboard
    local tool_ok, missing_tool = check_tool_available "image"
    if not tool_ok then
      log.err(
        "%s is required for clipboard detection on %s. Please install it.",
        missing_tool,
        os_display_name(util.get_os())
      )
      return
    end

    local tmp_path = save_clipboard_image_to_tmp()
    if not tmp_path then
      return
    end
    source_path = tostring(tmp_path)
    is_temp = true
  else
    -- File path clipboard (macOS only, path already cached from detection)
    source_path = cached_path

    -- Validate file exists
    local path = Path.new(source_path)
    if not path:exists() then
      log.err("File not found: %s", source_path)
      return
    end

    -- Validate not a directory
    if path:is_dir() then
      log.err("Cannot paste a directory: %s", source_path)
      return
    end
  end

  -- Optional confirmation
  local should_confirm = client.opts.attachments.confirm_paste
  if should_confirm == nil then
    should_confirm = true
  end
  if should_confirm then
    local prompt
    if clip_type == "image" then
      prompt = "Pasting image from clipboard. Continue?"
    else
      prompt = string.format('Pasting from "%s". Continue?', source_path)
    end
    if not util.confirm(prompt) then
      log.warn "Paste aborted"
      if is_temp then
        _cleanup_temp_file(source_path)
      end
      return
    end
  end

  -- Execute upload callback
  local result_url
  ok, err = pcall(function()
    result_url = upload_func(client, source_path)
  end)
  if not ok then
    log.err("upload_func failed: %s", err)
    if is_temp then
      _cleanup_temp_file(source_path)
    end
    return
  end

  -- Handle nil return (graceful abort)
  if result_url == nil then
    if is_temp then
      _cleanup_temp_file(source_path)
    end
    return
  end

  -- Validate return type
  if type(result_url) ~= "string" then
    log.err("upload_func must return a string or nil, got %s", type(result_url))
    if is_temp then
      _cleanup_temp_file(source_path)
    end
    return
  end

  -- Validate non-empty
  if result_url:match "^%s*$" then
    log.err "upload_func returned an empty result"
    if is_temp then
      _cleanup_temp_file(source_path)
    end
    return
  end

  -- Execute text generation callback
  local markdown_text
  ok, err = pcall(function()
    markdown_text = file_text_func(client, result_url)
  end)
  if not ok then
    log.err("file_text_func failed: %s", err)
    if is_temp then
      _cleanup_temp_file(source_path)
    end
    return
  end

  -- Validate return type
  if type(markdown_text) ~= "string" then
    log.err("file_text_func must return a string, got %s", type(markdown_text))
    if is_temp then
      _cleanup_temp_file(source_path)
    end
    return
  end

  -- Insert text (empty string = silent no-op)
  util.insert_text(markdown_text)

  -- Cleanup temp file
  if is_temp then
    _cleanup_temp_file(source_path)
  end
end

return M
