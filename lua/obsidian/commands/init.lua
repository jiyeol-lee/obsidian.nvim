local command_lookups = {
  ObsidianCheck = "obsidian.commands.check",
  ObsidianToggleCheckbox = "obsidian.commands.toggle_checkbox",
  ObsidianToday = "obsidian.commands.today",
  ObsidianYesterday = "obsidian.commands.yesterday",
  ObsidianTomorrow = "obsidian.commands.tomorrow",
  ObsidianDailies = "obsidian.commands.dailies",
  ObsidianNew = "obsidian.commands.new",
  ObsidianSearch = "obsidian.commands.search",
  ObsidianTags = "obsidian.commands.tags",
  ObsidianAlias = "obsidian.commands.alias",
  ObsidianTemplate = "obsidian.commands.template",
  ObsidianNewFromTemplate = "obsidian.commands.new_from_template",
  ObsidianPaste = "obsidian.commands.paste",
  ObsidianQuickSwitch = "obsidian.commands.quick_switch",
  ObsidianWorkspace = "obsidian.commands.workspace",
  ObsidianDebug = "obsidian.commands.debug",
  ObsidianTOC = "obsidian.commands.toc",
}

local M = setmetatable({
  commands = {},
}, {
  __index = function(t, k)
    local require_path = command_lookups[k]
    if not require_path then
      return
    end

    local mod = require(require_path)
    t[k] = mod

    return mod
  end,
})

---@class obsidian.CommandConfig
---@field opts table
---@field complete function|?
---@field func function|? (obsidian.Client, table) -> nil

---Register a new command.
---@param name string
---@param config obsidian.CommandConfig
M.register = function(name, config)
  if not config.func then
    config.func = function(client, data)
      return M[name](client, data)
    end
  end
  M.commands[name] = config
end

---Install all commands.
---
---@param client obsidian.Client
M.install = function(client)
  for command_name, command_config in pairs(M.commands) do
    local func = function(data)
      command_config.func(client, data)
    end

    if command_config.complete ~= nil then
      command_config.opts.complete = function(arg_lead, cmd_line, cursor_pos)
        return command_config.complete(client, arg_lead, cmd_line, cursor_pos)
      end
    end

    vim.api.nvim_create_user_command(command_name, func, command_config.opts)
  end
end

M.register("ObsidianCheck", { opts = { nargs = 0, desc = "Check for issues in your vault" } })

M.register("ObsidianToday", { opts = { nargs = "?", desc = "Open today's daily note" } })

M.register("ObsidianYesterday", { opts = { nargs = 0, desc = "Open the daily note for the previous working day" } })

M.register("ObsidianTomorrow", { opts = { nargs = 0, desc = "Open the daily note for the next working day" } })

M.register("ObsidianDailies", { opts = { nargs = "*", desc = "Open a picker with daily notes" } })

M.register("ObsidianNew", { opts = { nargs = "?", complete = "file", desc = "Create a new note" } })

M.register("ObsidianTags", { opts = { nargs = "*", range = true, desc = "Find tags" } })

M.register("ObsidianAlias", { opts = { nargs = "*", desc = "Find aliases" } })

M.register("ObsidianSearch", { opts = { nargs = "?", desc = "Search vault" } })

M.register("ObsidianTemplate", { opts = { nargs = "?", desc = "Insert a template" } })

M.register("ObsidianNewFromTemplate", { opts = { nargs = "?", desc = "Create a new note from a template" } })

M.register("ObsidianQuickSwitch", { opts = { nargs = "?", desc = "Switch notes" } })

M.register("ObsidianToggleCheckbox", { opts = { nargs = 0, desc = "Toggle checkbox" } })

M.register("ObsidianWorkspace", { opts = { nargs = "?", desc = "Check or switch workspace" } })

M.register("ObsidianPaste", { opts = { nargs = 0, desc = "Paste image or file from clipboard" } })

M.register("ObsidianDebug", { opts = { nargs = 0, desc = "Log some information for debugging" } })

M.register("ObsidianTOC", { opts = { nargs = 0, desc = "Load the table of contents into a picker" } })

return M
