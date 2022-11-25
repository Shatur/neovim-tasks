local tasks = require('tasks')
local utils = require('tasks.utils')
local constants = require('tasks.constants')
local subcommands = {}

--- Completes `:Task` command.
---@param arg string: Current argument under cursor.
---@param cmd_line string: All arguments.
---@return table: List of all commands matched with `arg`.
function subcommands.complete(arg, cmd_line)
  local matches = {}

  local words = vim.split(cmd_line, ' ', { trimempty = true })
  if not vim.endswith(cmd_line, ' ') then
    -- Last word is not fully typed, don't count it
    table.remove(words, #words)
  end

  local module_dependent_words = { 'start', 'set_task_param', 'set_module_param', 'get_module_param' }
  if #words == 1 then
    for subcommand in pairs(tasks) do
      if vim.startswith(subcommand, arg) and subcommand ~= 'setup' then
        table.insert(matches, subcommand)
      end
    end
  elseif #words == 2 then
    if vim.tbl_contains(module_dependent_words, words[2]) then
      local module_names = utils.get_module_names()
      table.insert(module_names, 'auto') -- Special value for automatic module detection
      for _, module_name in ipairs(module_names) do
        if vim.startswith(module_name, arg) then
          table.insert(matches, module_name)
        end
      end
    end
  elseif #words == 3 then
    if vim.tbl_contains(module_dependent_words, words[2]) then
      local ok, module = pcall(require, 'tasks.module.' .. words[3])
      if ok then
        for key, value in pairs((words[2] == 'get_module_param' or words[2] == 'set_module_param') and module.params or module.tasks) do
          local name = type(key) == 'number' and value or key -- Handle arrays
          if vim.startswith(name, arg) then
            table.insert(matches, name)
          end
        end
      end
    end
  elseif #words == 4 then
    if words[2] == 'set_task_param' then
      for _, param_name in ipairs(constants.task_params) do
        if vim.startswith(param_name, arg) then
          table.insert(matches, param_name)
        end
      end
    end
  end

  return matches
end

--- Run specified subcommand received from completion.
---@param subcommand table
function subcommands.run(subcommand)
  local subcommand_func = tasks[subcommand.fargs[1]]
  if not subcommand_func then
    utils.notify(string.format('No such subcommand named "%s"', subcommand.fargs[1]), vim.log.levels.ERROR)
    return
  end
  local subcommand_info = debug.getinfo(subcommand_func)
  if subcommand_info.isvararg and #subcommand.fargs - 1 < subcommand_info.nparams then
    utils.notify(string.format('Subcommand %s should have at least %s argument(s)', subcommand.fargs[1], subcommand_info.nparams + 1), vim.log.levels.ERROR)
    return
  elseif not subcommand_info.isvararg and #subcommand.fargs - 1 ~= subcommand_info.nparams then
    utils.notify(string.format('Subcommand %s should have %s argument(s)', subcommand.fargs[1], subcommand_info.nparams + 1), vim.log.levels.ERROR)
    return
  end
  subcommand_func(unpack(subcommand.fargs, 2))
end

return subcommands
