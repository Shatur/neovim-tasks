local Path = require('plenary.path')
local utils = require('tasks.utils')
local scandir = require('plenary.scandir')
local ProjectConfig = require('tasks.project_config')
local os = require('ffi').os:lower()
local cmake = {}

--- Parses build dir expression.
---@param dir string: Path with expressions to replace.
---@param build_type string
---@return table
local function parse_dir(dir, build_type)
    local parsed_dir = dir:gsub('{cwd}', vim.loop.cwd())
    parsed_dir = parsed_dir:gsub('{os}', os)
    parsed_dir = parsed_dir:gsub('{build_type}', build_type:lower())
    return Path:new(parsed_dir)
end

--- Returns reply directory that contains targets information.
---@param build_dir table
---@return unknown
local function get_reply_dir(build_dir)
    return build_dir / '.cmake' / 'api' / 'v1' / 'reply'
end

--- Reads information about target.
---@param codemodel_target table
---@param reply_dir table
---@return table
local function get_target_info(codemodel_target, reply_dir)
    return vim.json.decode((reply_dir / codemodel_target['jsonFile']):read())
end

--- Creates query files that to acess information about targets after CMake configuration.
---@param build_dir table
---@return boolean: Returns `true` on success.
local function make_query_files(build_dir)
    local query_dir = build_dir / '.cmake' / 'api' / 'v1' / 'query'
    if not query_dir:mkdir({parents = true}) then
        utils.notify(string.format('Unable to create "%s"', query_dir.filename),
                     vim.log.levels.ERROR)
        return false
    end

    local codemodel_file = query_dir / 'codemodel-v2'
    if not codemodel_file:is_file() then
        if not codemodel_file:touch() then
            utils.notify(string.format('Unable to create "%s"',
                                       codemodel_file.filename),
                         vim.log.levels.ERROR)
            return false
        end
    end
    return true
end

--- Reads targets information.
---@param reply_dir table
---@return table?
local function get_codemodel_targets(reply_dir)
    local found_files = scandir.scan_dir(reply_dir.filename,
                                         {search_pattern = 'codemodel*'})
    if #found_files == 0 then
        utils.notify('Unable to find codemodel file', vim.log.levels.ERROR)
        return nil
    end
    local codemodel = Path:new(found_files[1])
    local codemodel_json = vim.json.decode(codemodel:read())
    return codemodel_json['configurations'][1]['targets']
end

---@return table?
local function get_target_names()
    local project_config = ProjectConfig.new()
    local build_dir = parse_dir(project_config.cmake.build_dir,
                                project_config.cmake.build_type)
    if not build_dir:is_dir() then
        utils.notify(string.format(
                         'Build directory "%s" does not exist, you need to run "configure" task first',
                         build_dir), vim.log.levels.ERROR)
        return nil
    end

    local reply_dir = get_reply_dir(build_dir)
    local codemodel_targets = get_codemodel_targets(reply_dir)
    if not codemodel_targets then return nil end

    local targets = {}
    for _, target in ipairs(codemodel_targets) do
        local target_info = get_target_info(target, reply_dir)
        local target_name = target_info['name']
        if target_name:find('_autogen') == nil then
            table.insert(targets, target_name)
        end
    end

    return targets
end

--- Finds path to an executable.
---@param build_dir table
---@param name string
---@param reply_dir table
---@return unknown?
local function get_executable_path(build_dir, name, reply_dir)
    for _, target in ipairs(get_codemodel_targets(reply_dir)) do
        if name == target['name'] then
            local target_info = get_target_info(target, reply_dir)
            if target_info['type'] ~= 'EXECUTABLE' then
                utils.notify(string.format(
                                 'Specified target "%s" is not an executable',
                                 name), vim.log.levels.ERROR)
                return nil
            end

            local target_path = Path:new(target_info['artifacts'][1]['path'])
            if not target_path:is_absolute() then
                target_path = build_dir / target_path
            end

            return target_path
        end
    end

    utils.notify(string.format('Unable to find target named "%s"', name),
                 vim.log.levels.ERROR)
    return nil
end

--- Copies compile_commands.json file from build directory to the current working directory for LSP integration.
local function copy_compile_commands()
    local project_config = ProjectConfig.new()
    local filename = 'compile_commands.json'
    local source = parse_dir(project_config.cmake.build_dir,
                             project_config.cmake.build_type) / filename
    local destination = Path:new(vim.loop.cwd(), filename)
    source:copy({destination = destination.filename})
end

--- Task
---@param module_config table
---@return table?
local function configure(module_config, _)
    local build_dir = parse_dir(module_config.build_dir,
                                module_config.build_type)
    build_dir:mkdir({parents = true})
    if not make_query_files(build_dir) then return nil end

    local conan_toolchain = build_dir:joinpath('conan_toolchain.cmake')

    io.popen("source " .. build_dir:joinpath("conanbuild.sh"))

    local args = {
        '-B', build_dir.filename, '-D',
        'CMAKE_TOOLCHAIN_FILE=' .. conan_toolchain.filename, '-D',
        'CMAKE_BUILD_TYPE=' .. module_config.build_type
    }

    return {
        cmd = module_config.cmd,
        args = args,
        after_success = copy_compile_commands
    }
end

--- Task
---@param module_config table
---@return table
local function build(module_config, _)
    local build_dir = parse_dir(module_config.build_dir,
                                module_config.build_type)

    local args = {'--build', build_dir.filename}
    if module_config.target then
        vim.list_extend(args, {'--target', module_config.target})
    end

    return {
        cmd = module_config.cmd,
        args = args,
        after_success = copy_compile_commands
    }
end

--- Task
---@param module_config table
---@return table
local function build_all(module_config, _)
    local build_dir = parse_dir(module_config.build_dir,
                                module_config.build_type)

    return {
        cmd = module_config.cmd,
        args = {'--build', build_dir.filename},
        after_success = copy_compile_commands
    }
end

--- Task
---@param module_config table
---@return table?
local function run(module_config, _)
    if not module_config.target then
        utils.notify('No selected target, please set "target" parameter',
                     vim.log.levels.ERROR)
        return nil
    end

    local build_dir = parse_dir(module_config.build_dir,
                                module_config.build_type)
    if not build_dir:is_dir() then
        utils.notify(string.format(
                         'Build directory "%s" does not exist, you need to run "configure" task first',
                         build_dir), vim.log.levels.ERROR)
        return nil
    end

    local target_path = get_executable_path(build_dir, module_config.target,
                                            get_reply_dir(build_dir))
    if not target_path then return end

    if not target_path:is_file() then
        utils.notify(string.format('Selected target "%s" is not built',
                                   target_path.filename), vim.log.levels.ERROR)
        return nil
    end

    return {cmd = target_path.filename, cwd = target_path:parent().filename}
end

--- Task
---@param module_config table
---@return table?
local function debug(module_config, _)
    if module_config.build_type ~= 'Debug' and module_config.build_type ~=
        'RelWithDebInfo' then
        utils.notify(string.format(
                         'For debugging your "build_type" param should be set to "Debug" or "RelWithDebInfo", but your current build type is "%s"'),
                     module_config.build_type, vim.log.levels.ERROR)
        return nil
    end

    local command = run(module_config, nil)
    if not command then return nil end

    command.dap_name = module_config.dap_name
    return command
end

--- Task
---@param module_config table
---@return table
local function clean(module_config, _)
    local build_dir = parse_dir(module_config.build_dir,
                                module_config.build_type)

    return {
        cmd = module_config.cmd,
        args = {'--build', build_dir.filename, '--target', 'clean'},
        after_success = copy_compile_commands
    }
end

--- Task
---@param module_config table
---@return table
local function open_build_dir(module_config, _)
    local build_dir = parse_dir(module_config.build_dir,
                                module_config.build_type)

    return {
        cmd = os == 'windows' and 'start' or 'xdg-open',
        args = {build_dir.filename},
        ignore_stdout = true,
        ignore_stderr = true
    }
end

cmake.params = {
    target = get_target_names,
    build_type = {'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel'},
    'cmd',
    'dap_name'
}
cmake.condition = function() return Path:new('CMakeLists.txt'):exists() end
cmake.tasks = {
    configure = {configure},
    build = {build},
    build_all = build_all,
    run = {build, run},
    debug = {build, debug},
    clean = clean,
    open_build_dir = open_build_dir
}

return cmake
