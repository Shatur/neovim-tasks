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
local function build_type(module_config) return module_config.build_type or 'fastbuild' end

local Bazel = {
    params = {
        'cmd',
        'dap_name',
        build_type = { 'fastbuild', 'dbg', 'opt' },
        target = query_bazel_targets,
    },
    condition = function()
        return Path:new('WORKSPACE'):exists() or Path:new('MODULE.bazel'):exists()
    end,
    tasks = {}
}

local function build(module_config, _)
    local target = module_config.target or '//...'
    return {
        cmd = bazel_command(module_config),
        args = { 'build', target, '--compilation_mode=' .. build_type(module_config) },
    }
end

Bazel.tasks.build = build

function Bazel.tasks.build_all(module_config, _)
    return {
        cmd = bazel_command(module_config),
        args = { 'build', '//...', '--compilation_mode=' .. build_type(module_config) },
    }
end

function Bazel.tasks.clean(_, _)
    return {
        cmd = 'bazel',
        args = { 'clean' },
    }
end

local function run(module_config, _)
  if not module_config.target then
    utils.notify('No selected target, please set "target" parameter', vim.log.levels.ERROR)
    return nil
  end
  local _, targetPath = bazel_utils.getCurrentTargetAndExePath()

  local pthTarget = Path:new(targetPath)

  if not pthTarget:is_file() then
    utils.notify(string.format('Selected target "%s" is not built', pthTarget.filename), vim.log.levels.ERROR)
    return nil
  end

  return {
    cmd = pthTarget.filename,
  }
end

Bazel.tasks.run = { build, run }

local function debug(module_config, _)
  local command = run(module_config, nil)
  if not command then
    return nil
  end

  command.dap_name = module_config.dap_name
  return command
end

Bazel.tasks.debug = { build, debug }

function Bazel.tasks.test_all(module_config, _)
    return {
        cmd = bazel_command(module_config),
        args = { 'test', '//...', '--compilation_mode=' .. build_type(module_config) },
    }
end

return Bazel
