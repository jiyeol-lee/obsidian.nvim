local log = require "obsidian.log"
local util = require "obsidian.util"

---@param client obsidian.Client
---@param picker obsidian.Picker
---@param alias_entries obsidian.AliasEntry[]
---@param prompt string
local function open_alias_picker(client, picker, alias_entries, prompt)
  if vim.tbl_isempty(alias_entries) then
    log.warn "No aliases found"
    return
  end

  local notes_dir = nil
  if client.opts.notes_subdir ~= nil then
    notes_dir = (client.dir / client.opts.notes_subdir):resolve()
  end

  local daily_dir = nil
  if client.opts.daily_notes and client.opts.daily_notes.folder ~= nil then
    daily_dir = (client.dir / client.opts.daily_notes.folder):resolve()
  end

  ---@type obsidian.PickerEntry[]
  local notes_entries = {}
  ---@type obsidian.PickerEntry[]
  local daily_entries = {}
  ---@type obsidian.PickerEntry[]
  local other_entries = {}

  for _, alias_entry in ipairs(alias_entries) do
    for _, note in ipairs(alias_entry.notes) do
      if note.path ~= nil then
        local note_path = note.path:resolve()
        local rel_path = assert(client:vault_relative_path(note.path, { strict = true }))
        local display = string.format("%s → %s", rel_path, alias_entry.alias)

        local entry = {
          value = { path = note.path },
          display = display,
          ordinal = string.format("%s %s", rel_path, alias_entry.alias),
          filename = tostring(note.path),
        }

        local bucket = other_entries
        if notes_dir and notes_dir:is_parent_of(note_path) then
          bucket = notes_entries
        elseif daily_dir and daily_dir:is_parent_of(note_path) then
          bucket = daily_entries
        end

        bucket[#bucket + 1] = entry
      end
    end
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}
  vim.list_extend(entries, notes_entries)
  vim.list_extend(entries, daily_entries)
  vim.list_extend(entries, other_entries)

  if vim.tbl_isempty(entries) then
    log.warn "No aliases found"
    return
  end

  vim.schedule(function()
    picker:pick(entries, {
      prompt_title = prompt,
      callback = function(value)
        util.open_buffer(value.path)
      end,
    })
  end)
end

---@param client obsidian.Client
return function(client, data)
  local picker = client:picker()
  if not picker then
    log.err "No picker configured"
    return
  end

  local search_term = data.args
  if search_term ~= nil then
    search_term = vim.trim(search_term)
    if string.len(search_term) == 0 then
      search_term = nil
    end
  end

  client:list_aliases_async(search_term, function(alias_entries)
    local prompt
    if search_term ~= nil then
      prompt = string.format("Aliases matching '%s'", search_term)
    else
      prompt = "Aliases"
    end

    open_alias_picker(client, picker, alias_entries, prompt)
  end)
end
