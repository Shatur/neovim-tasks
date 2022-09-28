local utils = require('tasks.utils')
local Job = require('plenary.job')
local Path = require('plenary.path')
local cargo = {}

-- Modified version of `errorformat` from the official Rust plugin for Vim:
-- https://github.com/rust-lang/rust.vim/blob/4aa69b84c8a58fcec6b6dad6fe244b916b1cf830/compiler/rustc.vim#L32
-- https://github.com/rust-lang/rust.vim/blob/4aa69b84c8a58fcec6b6dad6fe244b916b1cf830/compiler/cargo.vim#L35
-- We display all lines (not only error messages) since we show output in quickfix.
-- Zero-width look-ahead regex is used to avoid marking general messages as errors: %\%%(ignored text%\)%\@!.
local errorformat = [[%Eerror: %\%%(aborting %\|could not compile%\)%\@!%m,]]
  .. [[%Eerror[E%n]: %m,]]
  .. [[%Inote: %m,]]
  .. [[%Wwarning: %\%%(%.%# warning%\)%\@!%m,]]
  .. [[%C %#--> %f:%l:%c,]]
  .. [[%E  left:%m,%C right:%m %f:%l:%c,%Z,]]
  .. [[%.%#panicked at \'%m\'\, %f:%l:%c]]

--- Detects package name from command line arguments.
---@param args table
---@return string?
local function detect_package_name(args)
  for index, value in ipairs(args) do
    if value == '-p' or value == '--package' or value == '--bin' then
      return args[index + 1]
    end
  end
  return nil
end

--- Returns only a packages that can be executed.
---@param packages table: Packages to filter.
---@return table
local function find_executable_packages(packages)
  local executables = {}
  for _, line in pairs(packages) do
    local package = vim.json.decode(line)
    if package.executable and package.executable ~= vim.NIL then
      table.insert(executables, package)
    end
  end
  return executables
end

--- Finds executable package name from a list of packages.
---@param packages table
---@param args table?: Command line arguments that will be used to detect an executable if JSON message from cargo is missing this info.
---@return table?
local function get_executable_package(packages, args)
  local executable_packages = find_executable_packages(packages)
  if #executable_packages == 1 then
    return executable_packages[1]
  end

  -- Try to detect package name from arguments
  local package_name = detect_package_name(args or {})
  if not package_name then
    local available_names = {}
    for _, package in ipairs(executable_packages) do
      table.insert(available_names, package.target.name)
    end
    utils.notify(
      'Could not determine which binary to run\nUse the "--bin" or "--package" option to specify a binary\nAvailable binaries: ' .. table.concat(available_names, ', '),
      vim.log.levels.ERROR
    )
    return nil
  end

  for _, package in ipairs(executable_packages) do
    if package.target.name == package_name then
      return package
    end
  end

  utils.notify(string.format('Unable to find package named "%s"', package_name), vim.log.levels.ERROR)
  return nil
end

---@return table: List of functions for each cargo subcommand that return a task table.
local function get_cargo_subcommands()
  local cargo_subcommands = {}

  local job = Job:new({
    command = 'cargo',
    args = { '--list' },
    enabled_recording = true,
  })
  job:sync()

  if job.code ~= 0 or job.signal ~= 0 then
    utils.notify('Unable to get list of available cargo subcommands', vim.log.levels.ERROR)
    return {}
  end

  local start_offset = 5
  for index, line in ipairs(job:result()) do
    if index ~= 1 and not line:find('alias:') then
      local subcommand_end = line:find(' ', start_offset)
      local subcommand = line:sub(start_offset, subcommand_end and subcommand_end - 1 or nil)
      cargo_subcommands[subcommand] =
        function(module_config, _) return { cmd = 'cargo', args = vim.list_extend({ subcommand }, utils.split_args(module_config.global_cargo_args)), errorformat = errorformat } end
    end
  end

  return cargo_subcommands
end

--- Task
---@return table?
local function build_test(module_config, _)
  return {
    cmd = 'cargo',
    args = vim.list_extend({ 'test', '--no-run', '--message-format=json' }, utils.split_args(module_config.global_cargo_args)),
    errorformat = errorformat,
    ignore_stdout = true,
  }
end

--- Task
---@param module_config table
---@param previous_job table
---@return table?
local function debug_test(module_config, previous_job)
  local package = get_executable_package(previous_job:result(), utils.split_args(module_config.global_cargo_args))
  if not package then
    return
  end

  return {
    cmd = package.executable,
    dap_name = module_config.dap_name,
    errorformat = errorformat,
  }
end

--- Task
---@param module_config table
---@return table?
local function build(module_config, _)
  return {
    cmd = 'cargo',
    args = vim.list_extend({ 'build', '--message-format=json' }, utils.split_args(module_config.global_cargo_args)),
    ignore_stdout = true,
  }
end

--- Task
---@param module_config table
---@param previous_job table
---@return table?
local function debug(module_config, previous_job)
  local package = get_executable_package(previous_job:result(), utils.split_args(module_config.global_cargo_args))
  if not package then
    return
  end

  return {
    cmd = package.executable,
    dap_name = module_config.dap_name,
    errorformat = errorformat,
  }
end

cargo.params = {
  'dap_name',
  'global_cargo_args',
}
cargo.condition = function() return Path:new('Cargo.toml'):exists() end
cargo.tasks = vim.tbl_extend('force', get_cargo_subcommands(), { debug_test = { build_test, debug_test }, debug = { build, debug } })

return cargo
