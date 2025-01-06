local Path = require "obsidian.path"
local util = require "obsidian.util"
local log = require "obsidian.log"

local M = {}

local function get_full_file_path_from_clipboard()
  -- Let's focus on macos first
  -- TODO: handle window and linux as well
  local handle = io.popen [[
        osascript -e '
        set theFiles to (the clipboard as «class furl») as list
        set thePaths to {}
        repeat with aFile in theFiles
            set end of thePaths to POSIX path of aFile
        end repeat
        return thePaths as text
        '
    ]]
  local clipboard_content = handle:read "*a"
  handle:close()
  return clipboard_content:gsub("%s+$", "")
end

---@param opts { fname: string|?, default_dir: obsidian.Path|string|?, default_name: string|?, should_confirm: boolean|? }|? Options.
---
--- Options:
---  - `fname`: The filename.
---  - `default_dir`: The default directory to put the file file in.
---  - `default_name`: The default name to assign the file.
---  - `should_confirm`: Prompt to confirm before proceeding.
---
--- @return obsidian.Path|? file_path The absolute path to the file file.
M.paste_file = function(opts)
  opts = opts or {}

  local clipboard_file_path = get_full_file_path_from_clipboard()

  -- TODO: add some logic to throw an error if there is no file is copied in the clipboard
  -- Right now, it will never be falsy
  -- if not clipboard_file_path then
  --   log.err "There is no file data in the clipboard"
  --   return
  -- end

  -- Open the source file in read-binary mode
  local src_file = io.open(clipboard_file_path, "rb")
  if not src_file then
    log.err "Error opening source file"
    return
  end

  -- Read the contents of the source file
  local content = src_file:read "*all"
  src_file:close()

  local fname = opts.fname and util.strip_whitespace(opts.fname) or nil

  -- Get filename to save to.
  if fname == nil or fname == "" then
    if opts.default_name ~= nil and not opts.should_confirm then
      fname = opts.default_name
    else
      fname = util.input("Enter file name: ", { default = opts.default_name, completion = "file" })
      if not fname then
        log.warn "Paste aborted"
        return
      end
    end
  end

  assert(fname)
  fname = util.strip_whitespace(fname)

  if fname == "" then
    log.err "Invalid file name"
    return
  end

  local src_file_path = Path.new(clipboard_file_path)
  local new_filename_path = Path.new(fname)

  if src_file_path.suffix then
    new_filename_path = new_filename_path:with_suffix(src_file_path.suffix)
  end

  -- Resolve absolute path to write file to.
  if new_filename_path.name ~= new_filename_path.filename then
    -- fname is a full path
    new_filename_path = new_filename_path:resolve()
  elseif opts.default_dir ~= nil then
    new_filename_path = (Path.new(opts.default_dir) / new_filename_path):resolve()
  else
    log.err "'default_dir' must be provided"
    return
  end

  if opts.should_confirm then
    -- Get confirmation from user.
    if not util.confirm("Saving file to '" .. tostring(new_filename_path) .. "'. Do you want to continue?") then
      log.warn "Paste aborted"
      return
    end
  end

  -- Ensure parent directory exists.
  assert(new_filename_path:parent()):mkdir { exist_ok = true, parents = true }

  -- Open the destination file in write-binary mode
  local dest_file = io.open(new_filename_path.filename, "wb")
  if not dest_file then
    log.err "Error opening destination file"
    return
  end

  -- Write the contents to the destination file
  dest_file:write(content)
  dest_file:close()

  return new_filename_path
end

return M
