local config = require('tasks.config')
local runner = require('tasks.runner')
local constants = require('tasks.constants')
local utils = require('tasks.utils')
local ProjectConfig = require('tasks.project_config')
local tasks = {}

--- Apply user settings.
---@param values table
function tasks.setup(values) setmetatable(config, { __index = vim.tbl_deep_extend('force', config.defaults, values) }) end

--- Execute a task from a module.
---@param module_type string: Name of a module or `auto` string to pick a first module that match a condition.
---@param task_name string
---@vararg string additional arguments that will be passed to the last task.
function tasks.start(module_type, task_name, ...)
  local current_job_name = runner.get_current_job_name()
  if current_job_name then
    utils.notify(string.format('Another job is currently running: "%s"', current_job_name), vim.log.levels.ERROR)
    return
  end

  local module, module_name = utils.get_module(module_type)
  if not module then
    return
  end

  local commands = module.tasks[task_name]
  if not commands then
    utils.notify(string.format('Unable to find a task named "%s" in module "%s"', task_name, module_name), vim.log.levels.ERROR)
    return
  end

  if config.save_before_run then
    vim.api.nvim_command('silent! wall')
  end

  local project_config = ProjectConfig.new()
  local module_config = project_config[module_name]
  if not vim.tbl_islist(commands) then
    commands = { commands }
  end
  runner.chain_commands(task_name, commands, module_config, { ... })
end

--- Set a module-specific parameter. Settings will be stored on disk.
---@param module_type string: Name of a module or `auto` string to pick a first module that match a condition.
---@param param_name string
function tasks.set_module_param(module_type, param_name)
  local module, module_name = utils.get_module(module_type)
  if not module then
    return
  end

  if not module then
    return
  end

  local project_config = ProjectConfig.new()
  local current_value = vim.tbl_get(project_config, module_name, param_name)

  local param = module.params[param_name]
  if not param then
    if vim.tbl_contains(module.params, param_name) then
      -- Contains a string without a value, request for input
      vim.ui.input({ prompt = string.format('Set "%s" for module "%s"', param_name, module_name), default = current_value }, function(input)
        project_config[module_name][param_name] = input
        project_config:write()
      end)
    else
      utils.notify(string.format('No such parameter "%s" for module "%s"', param_name, module_name), vim.log.levels.ERROR)
    end
    return
  end

  if vim.is_callable(param) then
    param = param()
    if not param then
      return
    end
  end

  -- Put current value first
  if current_value then
    for index, value in ipairs(param) do
      if value == current_value then
        table.remove(param, index)
        break
      end
    end
    table.insert(param, 1, current_value)
  end

  vim.ui.select(param, { prompt = string.format('Select "%s"', param_name) }, function(choice, idx)
    if not idx then
      return
    end
    if not project_config[module_name] then
      project_config[module_name] = {}
    end
    project_config[module_name][param_name] = choice
    project_config:write()
  end)
end

--- Set a parameter for a module task. Settings will be stored on disk.
---@param module_type string: Name of a module or `auto` string to pick a first module that match a condition.
---@param task_name string
---@param param_name string
function tasks.set_task_param(module_type, task_name, param_name)
  local module, module_name = utils.get_module(module_type)
  if not module then
    return
  end
  if not vim.tbl_contains(constants.task_params, param_name) then
    utils.notify(string.format('Unknown task parameter "%s"\nAvailable task parameters: %s', param_name, table.concat(constants.task_params, ', ')), vim.log.levels.ERROR)
    return
  end

  local project_config = ProjectConfig.new()
  local current_value = vim.tbl_get(project_config, module_name, param_name, task_name)
  current_value = current_value and utils.join_args(current_value) or ''
  vim.ui.input({ prompt = string.format('Set "%s" for task "%s" from module "%s": ', param_name, task_name, module_name), default = current_value, completion = 'file' }, function(input)
    if not project_config[module_name] then
      project_config[module_name] = {}
    end
    if not project_config[module_name][param_name] then
      project_config[module_name][param_name] = {}
    end
    project_config[module_name][param_name][task_name] = utils.split_args(input)
    project_config:write()
  end)
end

--- Cancel last current task.
function tasks.cancel()
  if not runner.cancel_job() then
    utils.notify('No running process')
  end
end

return tasks
