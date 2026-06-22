local M = {}

---@class obsidian.mappings.MappingConfig
---@field action function
---@field opts table

M.toggle_checkbox = function()
  return { action = "<cmd>ObsidianToggleCheckbox<CR>", opts = { buffer = true, desc = "Toggle Checkbox" } }
end

return M
