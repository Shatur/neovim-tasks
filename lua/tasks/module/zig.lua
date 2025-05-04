local Path = require('plenary.path')

local build_type_map = {
  Debug = 'off',
  ReleaseSafe = 'safe',
  ReleaseSmall = 'small',
  ReleaseFast = 'fast',
}

local function zig_command(module_config) return module_config.cmd or 'zig' end
local function build_type(module_config) return module_config.build_type or 'Debug' end

local function build(module_config, _)
  local build_target = module_config.build_step or 'install'
  local bt = build_type_map[build_type(module_config)]
  return {
    cmd = zig_command(module_config),
    args = { 'build', build_target, '--release=' .. bt },
  }
end

local function get_build_steps()
  local allSteps = vim.fn.systemlist('zig build --list-steps')
  local stepNames = {}
  for _, step in ipairs(allSteps) do
    local firstWord = string.gmatch(step, '%w+')()
    table.insert(stepNames, firstWord)
  end
  return stepNames
end

local function clean(_, _)
  -- note: requires unix shell
  return {
    cmd = 'rm',
    args = { '-rf', 'zig-out' },
  }
end

local function clean_cache(_, _)
  -- note: requires unix shell
  return {
    cmd = 'rm',
    args = { '-rf', '.zig-cache' },
  }
end

local function run_file(module_config, _)
  local currentSource = vim.fn.expand('%')
  return {
    cmd = zig_command(module_config),
    args = { 'run', '-O' .. build_type(module_config), currentSource, '--' },
  }
end

local function build_file_as_exe(module_config, _)
  local currentSource = vim.fn.expand('%')
  local srcFilename = vim.fn.fnamemodify(currentSource, ':t:r')
  return {
    cmd = zig_command(module_config),
    args = { 'build-exe', currentSource, '-femit-bin=.zig-cache/run-' .. srcFilename, '-O' .. build_type(module_config) },
  }
end

local function debug_file(module_config, _)
  local currentSource = vim.fn.expand('%')
  local srcFilename = vim.fn.fnamemodify(currentSource, ':t:r')
  return {
    cmd = '.zig-cache/run-' .. srcFilename,
    dap_name = module_config.dap_name,
  }
end

local function test_file(module_config, _)
  local currentSource = vim.fn.expand('%')
  return {
    cmd = zig_command(module_config),
    args = { 'test', '-O' .. build_type(module_config), currentSource },
  }
end

local function build_test_file(module_config, _)
  local currentSource = vim.fn.expand('%')
  local srcFilename = vim.fn.fnamemodify(currentSource, ':t:r')
  return {
    cmd = zig_command(module_config),
    args = { 'test', currentSource, '-femit-bin=.zig-cache/test-' .. srcFilename, '--test-no-exec', '-O' .. build_type(module_config) },
  }
end

local function debug_test_file(module_config, _)
  local currentSource = vim.fn.expand('%')
  local srcFilename = vim.fn.fnamemodify(currentSource, ':t:r')
  return {
    cmd = '.zig-cache/test-' .. srcFilename,
    dap_name = module_config.dap_name,
  }
end

local function get_current_test_filter()
  local test_start_line = vim.fn.search('^test', 'bWn')
  if test_start_line ~= 0 then
    local line_contents = vim.fn.getline(test_start_line)
    local test_filter = string.gsub(line_contents, '^test +"(.+)".+$', '%1')
    return test_filter
  else
    return nil
  end
end

local function run_current_test(module_config, _)
  local currentSource = vim.fn.expand('%')
  local test_filter = get_current_test_filter()
  if test_filter ~= nil then
    return {
      cmd = zig_command(module_config),
      args = { 'test', '-O' .. build_type(module_config), currentSource, '--test-filter', test_filter },
    }
  else
    return {
      cmd = zig_command(module_config),
      args = { 'test', '-O' .. build_type(module_config), currentSource },
    }
  end
end

local function build_current_test(module_config, _)
  local currentSource = vim.fn.expand('%')
  local srcFilename = vim.fn.fnamemodify(currentSource, ':t:r')
  local test_filter = get_current_test_filter()
  if test_filter == nil then
    return {
      cmd = zig_command(module_config),
      args = { 'test', currentSource, '-femit-bin=.zig-cache/test-' .. srcFilename, '--test-no-exec', '-O' .. build_type(module_config) },
    }
  else
    return {
      cmd = zig_command(module_config),
      args = { 'test', currentSource, '-femit-bin=.zig-cache/test-' .. srcFilename, '--test-no-exec', '-O' .. build_type(module_config), '--test-filter', test_filter },
    }
  end
end

return {
  params = {
    'cmd',
    'dap_name',
    build_type = { 'Debug', 'ReleaseSafe', 'ReleaseFast', 'ReleaseSmall' },
    build_step = get_build_steps,
  },
  condition = function() return Path:new('zig.build'):exists() end,
  tasks = {
    build = build,
    clean = clean,
    clean_cache = clean_cache,
    clean_all = { clean, clean_cache },
    run_file = run_file,
    debug_file = { build_file_as_exe, debug_file },
    test_file = test_file,
    debug_test_file = { build_test_file, debug_test_file },
    run_current_test = run_current_test,
    debug_current_test = { build_current_test, debug_test_file },
  },
}
