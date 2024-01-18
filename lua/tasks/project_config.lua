local config = require('tasks.config')
local Path = require('plenary.path')

--- Contains all fields from configuration.
---@class ProjectConfig
local ProjectConfig = {}
ProjectConfig.__index = ProjectConfig

--- Reads project configuration JSON into a table.
---@return ProjectConfig
function ProjectConfig.new()
  local project_config
  local params_file = Path:new(config.params_file)
  if params_file:is_file() then
    project_config = vim.json.decode(params_file:read())
  else
    project_config = {}
  end
  project_config = vim.tbl_extend('keep', project_config, config.default_params)
  return setmetatable(project_config, ProjectConfig)
end

--- Writes all values as JSON to disk.
function ProjectConfig:write()
  local params_file = Path:new(config.params_file)
  local tmp_dap_open_command = self.dap_open_command
  self.dap_open_command = nil
  params_file:write(vim.json.encode(self), 'w')
  self.dap_open_command = tmp_dap_open_command
end

return ProjectConfig
