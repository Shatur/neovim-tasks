local Path = require('plenary.path')
local utils = require('tasks.utils')
local cmake_utils = require('tasks.cmake_utils.cmake_utils')
local cmake_presets = require('tasks.cmake_utils.cmake_presets')

local function getKeys(tbl)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

local function getTargetNames()
  local build_dir = cmake_utils.getBuildDir()
  if not build_dir:is_dir() then
    utils.notify(string.format('Build directory "%s" does not exist, you need to run "configure" task first', build_dir), vim.log.levels.ERROR)
    return nil
  end

  local reply_dir = cmake_utils.getReplyDir(build_dir)
  local codemodel_targets = cmake_utils.getCodemodelTargets(reply_dir)
  if not codemodel_targets then
    return nil
  end

  local targets = {}
  for _, target in ipairs(codemodel_targets) do
    local target_info = cmake_utils.getTargetInfo(target, reply_dir)
    local target_name = target_info['name']
    if target_name:find('_autogen') == nil then
      table.insert(targets, target_name)
    end
  end

  -- always add 'all' target
  table.insert(targets, 'all')

  return targets
end --

local function makeQueryFiles(build_dir)
  local query_dir = build_dir / '.cmake' / 'api' / 'v1' / 'query'
  if not query_dir:mkdir({ parents = true }) then
    utils.notify(string.format('Unable to create "%s"', query_dir.filename), vim.log.levels.ERROR)
    return false
  end

  local codemodel_file = query_dir / 'codemodel-v2'
  if not codemodel_file:is_file() then
    if not codemodel_file:touch() then
      utils.notify(string.format('Unable to create "%s"', codemodel_file.filename), vim.log.levels.ERROR)
      return false
    end
  end
  return true
end

-- inspired by https://github.com/Shatur/neovim-tasks/blob/master/lua/tasks/module/cmake.lua#L130
-- but modified to also support build kits
local function configure(module_config, _)
  local usePresets = cmake_utils.shouldUsePresets(module_config)

  if usePresets and not module_config.configure_preset then
    utils.notify('No selected configure preset, please select it', vim.log.levels.ERROR)
    return nil
  end

  local build_dir = cmake_utils.getBuildDir()
  build_dir:mkdir({ parents = true })

  if not makeQueryFiles(build_dir) then
    return nil
  end

  local afterSuccessAction = cmake_utils.reconfigureClangd
  -- note: needs to be checked with "== false" to ensure nil is treated as true (the default)
  if module_config.restart_clangd_after_configure == false then
    afterSuccessAction = nil
  end

  if usePresets then
    local currentPreset = module_config.configure_preset

    return {
      cmd = module_config.cmd,
      cwd = module_config.source_dir,
      args = { '--preset', currentPreset, '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON' },
      after_success = afterSuccessAction,
    }
  else
    local buildTypes = cmake_utils.getCMakeBuildTypesFromConfig(module_config)
    local cmakeKits = cmake_utils.getCMakeKitsFromConfig(module_config)
    local build_type_config = buildTypes[module_config.build_type] or { build_type = 'Debug' }
    local build_kit_config = cmakeKits[module_config.build_kit] or { generator = 'Ninja' }

    local cmakeBuildType = build_type_config.build_type

    local generator = build_kit_config.generator and build_kit_config.generator or 'Ninja'
    local buildTypeAware = true
    if build_kit_config.build_type_aware ~= nil then
      buildTypeAware = build_kit_config.build_type_aware
    end

    local args = { '-G', generator, '-B', build_dir.filename, '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON' }
    if buildTypeAware then
      table.insert(args, '-DCMAKE_BUILD_TYPE=' .. cmakeBuildType)
    end
    if module_config.source_dir then
      table.insert(args, '-S')
      table.insert(args, module_config.source_dir)
    end

    if build_kit_config.toolchain_file then
      table.insert(args, '-DCMAKE_TOOLCHAIN_FILE=' .. build_kit_config.toolchain_file)
    end

    if build_kit_config.compilers then
      table.insert(args, '-DCMAKE_C_COMPILER=' .. build_kit_config.compilers.C)
      table.insert(args, '-DCMAKE_CXX_COMPILER=' .. build_kit_config.compilers.CXX)
    end

    if build_type_config.cmake_usr_args then
      for k, v in pairs(build_type_config.cmake_usr_args) do
        table.insert(args, '-D' .. k .. '=' .. v)
      end
    end

    if build_kit_config.cmake_usr_args then
      for k, v in pairs(build_kit_config.cmake_usr_args) do
        table.insert(args, '-D' .. k .. '=' .. v)
      end
    end

    local build_kit = cmakeKits[module_config.build_kit] or { environment_variables = nil }

    return {
      cmd = module_config.cmd,
      args = args,
      env = build_kit.environment_variables,
      after_success = afterSuccessAction,
    }
  end
end

local function build(module_config, _)
  local usePresets = cmake_utils.shouldUsePresets(module_config)

  if usePresets and not module_config.build_preset then
    utils.notify('No selected build preset, please select it', vim.log.levels.ERROR)
    return nil
  end

  if usePresets then
    local buildPreset = module_config.build_preset

    local args = { '--build', '--preset', buildPreset }

    if module_config.target and module_config.target ~= 'all' then
      vim.list_extend(args, { '--target', module_config.target })
    end

    return {
      cmd = module_config.cmd,
      cwd = module_config.source_dir,
      args = args,
    }
  else
    local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
    local cmakeKits = cmake_utils.getCMakeKitsFromConfig(module_config)

    local args = { '--build', build_dir.filename }
    if module_config.target and module_config.target ~= 'all' then
      vim.list_extend(args, { '--target', module_config.target })
    end

    local build_kit = cmakeKits[module_config.build_kit] or { environment_variables = nil }

    return {
      cmd = module_config.cmd,
      args = args,
      env = build_kit.environment_variables,
    }
  end
end

local function build_all(module_config, _)
  local usePresets = cmake_utils.shouldUsePresets(module_config)

  if usePresets and not module_config.build_preset then
    utils.notify('No selected build preset, please select it', vim.log.levels.ERROR)
    return nil
  end

  if usePresets then
    return {
      cmd = module_config.cmd,
      cwd = module_config.source_dir,
      args = { '--build', '--preset', module_config.build_preset },
    }
  else
    local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
    local cmakeKits = cmake_utils.getCMakeKitsFromConfig(module_config)
    local build_kit = cmakeKits[module_config.build_kit] or { environment_variables = nil }

    return {
      cmd = module_config.cmd,
      args = { '--build', build_dir.filename },
      env = build_kit.environment_variables,
    }
  end
end

local function build_current_file(module_config, _)
  local sourceName = vim.fn.expand('%')
  local extension = vim.fn.fnamemodify(sourceName, ':e')

  local headerExtensions = {
    ['h'] = true,
    ['hxx'] = true,
    ['hpp'] = true,
  }

  if #extension == 0 or headerExtensions[extension] then
    vim.notify('Given file is not a source file!', vim.log.levels.ERROR, { title = 'cmake' })
    return nil
  end

  local ninjaTarget = vim.fn.fnameescape(vim.fn.fnamemodify(sourceName, ':p') .. '^')

  local usePresets = cmake_utils.shouldUsePresets(module_config)

  if usePresets and not module_config.build_preset then
    utils.notify('No selected build preset, please select it', vim.log.levels.ERROR)
    return nil
  end

  if usePresets then
    local currentPreset = cmake_presets.get_preset_by_name(module_config.configure_preset, 'configurePresets', module_config.source_dir)

    if not currentPreset or (currentPreset.generator ~= 'Ninja' and currentPreset.generator ~= 'Ninja Multi-Config') then
      vim.notify('Build current file is supported only for Ninja generator at the moment!', vim.log.levels.ERROR, { title = 'cmake' })
      return nil
    end

    return {
      cmd = module_config.cmd,
      cwd = module_config.source_dir,
      args = { '--build', '--preset', module_config.build_preset, '--target', ninjaTarget },
    }
  else
    local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
    local cmakeKits = cmake_utils.getCMakeKitsFromConfig(module_config)
    local build_kit_config = cmakeKits[module_config.build_kit]
    local generator = build_kit_config.generator and build_kit_config.generator or 'Ninja'

    if generator ~= 'Ninja' and generator ~= 'Ninja Multi-Config' then
      vim.notify('Build current file is supported only for Ninja generator at the moment!', vim.log.levels.ERROR, { title = 'cmake' })
      return nil
    end

    local build_kit = cmakeKits[module_config.build_kit] or { environment_variables = nil }

    return {
      cmd = module_config.cmd,
      args = { '--build', build_dir.filename, '--target', ninjaTarget },
      env = build_kit.environment_variables,
    }
  end
end

local function clean(module_config, _)
  local usePresets = cmake_utils.shouldUsePresets(module_config)

  if usePresets and not module_config.build_preset then
    utils.notify('No selected build preset, please select it', vim.log.levels.ERROR)
    return nil
  end

  if usePresets then
    local args = { '--build', '--preset', module_config.build_preset, '--target', 'clean' }

    return {
      cmd = module_config.cmd,
      cwd = module_config.source_dir,
      args = args,
    }
  else
    local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
    local cmakeKits = cmake_utils.getCMakeKitsFromConfig(module_config)
    local build_kit = cmakeKits[module_config.build_kit] or { environment_variables = nil }

    return {
      cmd = module_config.cmd,
      cwd = module_config.source_dir,
      args = { '--build', build_dir.filename, '--target', 'clean' },
      env = build_kit.environment_variables,
    }
  end
end

local function purgeBuildDir(module_config, _)
  local build_dir = cmake_utils.getBuildDirFromConfig(module_config)

  return {
    -- TODO: what about Windows?
    cmd = 'rm',
    args = { '-rf', tostring(build_dir) },
  }
end

local function edit_cache(module_config, _)
  local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
  vim.cmd.edit(tostring(build_dir / 'CMakeCache.txt'))
  return nil
end

local function open_build_dir(module_config, _)
  local build_dir = cmake_utils.getBuildDirFromConfig(module_config)

  return {
    cmd = os == 'windows' and 'start' or 'xdg-open',
    args = { build_dir.filename },
    ignore_stdout = true,
    ignore_stderr = true,
  }
end

local function trim(s) return s:match('^%s*(.*%S)') or '' end

local function runCTest(module_config, _)
  local usePresets = cmake_utils.shouldUsePresets(module_config)

  -- assume test preset names are the same as build preset names
  -- TODO: add support for separate test presets if needed
  if usePresets and not module_config.build_preset then
    utils.notify('No selected build preset, please select it', vim.log.levels.ERROR)
    return nil
  end

  local numcpus = trim(vim.fn.system('nproc'))
  if usePresets then
    return {
      cmd = 'ctest',
      cwd = module_config.source_dir,
      args = { '--preset', module_config.build_preset, '-j', numcpus, '--output-on-failure' },
    }
  else
    local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
    local cmakeKits = cmake_utils.getCMakeKitsFromConfig(module_config)
    local build_kit = cmakeKits[module_config.build_kit] or { environment_variables = nil }

    return {
      cmd = 'ctest',
      args = { '-C', module_config.build_type, '-j', numcpus, '--output-on-failure' },
      cwd = tostring(build_dir),
      env = build_kit.environment_variables,
    }
  end
end

local function run(module_config, _)
  if not module_config.target then
    utils.notify('No selected target, please set "target" parameter', vim.log.levels.ERROR)
    return nil
  end

  local build_dir = cmake_utils.getBuildDirFromConfig(module_config)
  if not build_dir:is_dir() then
    utils.notify(string.format('Build directory "%s" does not exist, you need to run "configure" task first', build_dir), vim.log.levels.ERROR)
    return nil
  end

  local target_path = cmake_utils.getExecutablePath(build_dir, module_config.target, cmake_utils.getCurrentBuildType(module_config), cmake_utils.getReplyDir(build_dir))
  if not target_path then
    return
  end

  if not target_path:is_file() then
    utils.notify(string.format('Selected target "%s" is not built', target_path.filename), vim.log.levels.ERROR)
    return nil
  end

  return {
    cmd = target_path.filename,
    cwd = target_path:parent().filename,
  }
end

local function debug(module_config, _)
  local command = run(module_config, nil)
  if not command then
    return nil
  end

  command.dap_name = module_config.dap_name
  return command
end

local function setupCMakeDAP(configure_command)
  local dap = require('dap')
  local args = { '--debugger', '--debugger-pipe=${pipe}' }
  vim.list_extend(args, configure_command.args)

  dap.adapters.cmake = {
    type = 'pipe',
    pipe = '${pipe}',
    executable = {
      command = configure_command.cmd,
      args = args,
    },
  }
  dap.configurations.cmake = {
    type = 'cmake',
    request = 'attach',
    name = 'CMake Debugger',
  }
end

local function configureDebug(module_config, _)
  local command = configure(module_config, nil)
  if not command then
    return nil
  end

  setupCMakeDAP(command)

  command.dap_name = 'cmake'
  return command
end

return {
  params = {
    target = getTargetNames,
    build_type = function() return getKeys(cmake_utils.getCMakeBuildTypes()) end,
    build_kit = function() return getKeys(cmake_utils.getCMakeKits()) end,
    configure_preset = function() return cmake_presets.parse('configurePresets') end,
    build_preset = function() return cmake_presets.parse('buildPresets') end,
    ignore_presets = { true, false },
    restart_clangd_after_configure = { true, false },
  },
  condition = function() return Path:new('CMakeLists.txt'):exists() end,
  tasks = {
    configure = configure,
    configureDebug = configureDebug,
    build = build,
    build_all = build_all,
    build_current_file = build_current_file,
    run = { build, run },
    debug = { build, debug },
    clean = clean,
    rebuild = { clean, build },
    ctest = runCTest,
    purge = purgeBuildDir,
    reconfigure = { purgeBuildDir, configure },
    open_build_dir = open_build_dir,
    edit_cache = edit_cache,
  },
}
