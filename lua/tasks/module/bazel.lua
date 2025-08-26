local Path = require('plenary.path')
local utils = require('tasks.utils')
local bazel_utils = require('tasks.bazel_utils.bazel_utils')

local function query_bazel_targets()
  local allTargets = vim.fn.systemlist('bazel query //...:all')
  local targets = {}
  for _, candidate in ipairs(allTargets) do
    local bazelTarget = string.gmatch(candidate, '//.+')()
    table.insert(targets, bazelTarget)
  end
  return targets
end

local function bazel_command(module_config) return module_config.cmd or 'bazel' end

local function build_type(module_config)
  if module_config.build_type and module_config.build_type ~= 'fastbuild' then
    return '--compilation_mode=' .. module_config.build_type
  else
    return nil
  end
end

local function global_bazel_args(module_config)
  local default_args = { '--announce_rc', '--show_timestamps', '--color=no', '--curses=no', '--show_progress' }
  if module_config.global_bazel_args then
    return utils.split_args(module_config.global_bazel_args)
  else
    return default_args
  end
end

local Bazel = {
  params = {
    'cmd',
    'dap_name',
    build_type = { 'fastbuild', 'dbg', 'opt' },
    target = query_bazel_targets,
    'compile_commands_refresh_target',
    'bazel_args',
    'global_bazel_args',
    'bazel_compile_commands_tool',
    'bazel_compile_commands_tool_args',
  },
  condition = function() return Path:new('WORKSPACE'):exists() or Path:new('MODULE.bazel'):exists() end,
  tasks = {},
}

local function build(module_config, _)
  local target = module_config.target or '//...'
  return {
    cmd = bazel_command(module_config),
    args = vim.list_extend(vim.list_extend({ 'build', target, build_type(module_config) }, global_bazel_args(module_config)), utils.split_args(module_config.bazel_args)),
  }
end

Bazel.tasks.build = build

function Bazel.tasks.build_all(module_config, _)
  return {
    cmd = bazel_command(module_config),
    args = vim.list_extend(vim.list_extend({ 'build', '//...', build_type(module_config) }, global_bazel_args(module_config)), utils.split_args(module_config.bazel_args)),
  }
end

function Bazel.tasks.clean(_, _)
  return {
    cmd = 'bazel',
    args = { 'clean' },
  }
end

function Bazel.tasks.run(module_config, _)
  if not module_config.target then
    utils.notify('No selected target, please set "target" parameter', vim.log.levels.ERROR)
    return nil
  end
  local target = module_config.target
  return {
    cmd = bazel_command(module_config),
    args = vim.list_extend(vim.list_extend(vim.list_extend({ 'run', target, build_type(module_config) }, global_bazel_args(module_config)), utils.split_args(module_config.bazel_args)), { '--' }),
  }
end

local function run_for_debug(module_config, _)
  if not module_config.target then
    utils.notify('No selected target, please set "target" parameter', vim.log.levels.ERROR)
    return nil
  end
  local _, targetPath = bazel_utils.getCurrentTargetAndExePath()

  local pthTarget = Path:new(targetPath)

  if not pthTarget:is_file() then
    utils.notify(string.format('Selected target "%s" is not debuggable', module_config.target), vim.log.levels.ERROR)
    return nil
  end

  return {
    cmd = pthTarget.filename,
  }
end

local function debug(module_config, _)
  local command = run_for_debug(module_config, nil)
  if not command then
    return nil
  end

  command.dap_name = module_config.dap_name
  -- note: https://github.com/vadimcn/codelldb/discussions/517#discussioncomment-1331286
  -- Bazel replaces the actual source location with "/proc/self/cwd" in order to achieve repeatable builds.
  -- You'll need to add "sourceMap": { ".": "${workspaceFolder}" } to your launch configuration.
  command.dap_config = {
    sourceMap = {
      ['.'] = '${workspaceFolder}',
    },
  }
  return command
end

Bazel.tasks.debug = { build, debug }

function Bazel.tasks.test_all(module_config, _)
  return {
    cmd = bazel_command(module_config),
    args = vim.list_extend(vim.list_extend({ 'test', '//...', build_type(module_config) }, global_bazel_args(module_config)), utils.split_args(module_config.bazel_args)),
  }
end

function Bazel.tasks.test(module_config, _)
  local target = module_config.target or '//...'
  return {
    cmd = bazel_command(module_config),
    args = vim.list_extend(vim.list_extend({ 'test', target, build_type(module_config) }, global_bazel_args(module_config)), utils.split_args(module_config.bazel_args)),
  }
end

local function restartClangd()
  vim.lsp.stop_client(vim.lsp.get_clients({ name = 'clangd' }))
  vim.defer_fn(function() vim.api.nvim_command('edit') end, 500)
end

function Bazel.tasks.refresh_compile_commands(module_config)
  local refreshTarget = module_config.compile_commands_refresh_target or '@hedron_compile_commands//:refresh_all'
  return {
    cmd = bazel_command(module_config),
    args = vim.list_extend(vim.list_extend({ 'run', refreshTarget, build_type(module_config) }, global_bazel_args(module_config)), utils.split_args(module_config.bazel_args)),
    after_success = restartClangd,
  }
end

function Bazel.tasks.external_refresh_compile_commands(module_config)
  local refreshTool = module_config.bazel_compile_commands_tool or 'bazel-compile-commands'
  local refreshArgs = module_config.bazel_compile_commands_tool_args or '--verbose'
  return {
    cmd = refreshTool,
    args = utils.split_args(refreshArgs),
    after_success = restartClangd,
  }
end

return Bazel
