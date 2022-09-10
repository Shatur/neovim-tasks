local scandir = require('plenary.scandir')
local Path = require('plenary.path')
local utils = {}

local args_regex = vim.regex([[\s\%(\%([^'"]*\(['"]\)[^'"]*\1\)*[^'"]*$\)\@=]])

--- A small wrapper around `vim.notify` that adds plugin title.
---@param msg string
---@param log_level number
function utils.notify(msg, log_level) vim.notify(msg, log_level, { title = 'Tasks' }) end

--- Splits command line arguments respecting quotes.
---@param args string?
---@return table
function utils.split_args(args)
  if not args then
    return {}
  end

  -- Split on spaces unless in quotes.
  local splitted_args = {}
  local match_beg
  while true do
    match_beg = args_regex:match_str(args)
    if match_beg then
      table.insert(splitted_args, args:sub(1, match_beg))
      args = args:sub(match_beg + 2)
    else
      -- Insert last arg left.
      table.insert(splitted_args, args)
      break
    end
  end

  -- Remove quotes
  for i, arg in ipairs(splitted_args) do
    splitted_args[i] = arg:gsub('"', ''):gsub("'", '')
  end
  return splitted_args
end

--- Joins command line arguments respecting spaces by putting double quotes around them.
---@param args table?
---@return string
function utils.join_args(args)
  if not args then
    return ''
  end

  -- Add quotes if argument contain spaces
  for index, arg in ipairs(args) do
    if arg:find(' ') then
      args[index] = '"' .. arg .. '"'
    end
  end

  return table.concat(args, ' ')
end

---@return table
function utils.get_module_names()
  local module_dir = Path:new(debug.getinfo(1).source:sub(2)):parent() / 'module'

  local modules = {}
  for _, entry in ipairs(scandir.scan_dir(module_dir.filename, { depth = 1 })) do
    -- Strip full path and extension
    local extension_len = 4
    local parent_offset = 2
    table.insert(modules, entry:sub(#Path:new(entry):parent().filename + parent_offset, #entry - extension_len))
  end

  return modules
end

--- Find a module by name
---@param module_type string name of a module or `auto` string to pick a first module that match a condition.
---@return table?, string?: module and its name.
function utils.get_module(module_type)
  if module_type == 'auto' then
    for _, name in ipairs(utils.get_module_names()) do
      local module = require('tasks.module.' .. name)
      if module.condition() then
        return module, name
      end
    end

    utils.notify('Unable to autodetect module for this working directory', vim.log.levels.ERROR)
    return nil, nil
  end

  local module = require('tasks.module.' .. module_type)
  if not module then
    utils.notify('Unable to find a module named ' .. module_type, vim.log.levels.ERROR)
    return nil, nil
  end

  return module, module_type
end

return utils
