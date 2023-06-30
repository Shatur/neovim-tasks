local path = require("plenary.path")
local os = require('ffi').os:lower()

local function conan_install(module_config, _)
    local build_folder = path:new(vim.loop.cwd(), "build",
                                  os .. "-" .. module_config.build_type)

    if not build_folder:exists() then build_folder:mkdir({parents = true}) end

    local args = {
        "install", "--build=missing", "--output-folder", build_folder.filename
    }

    table.insert(args, "./")
    return {
        cmd = module_config.cmd,
        args = args,
        only_on_error = module_config.only_on_error
    }
end

local conan = {
    params = {'cmd', build_type = {"debug", "release"}},
    condition = function() return path:new('conanfile.txt'):exists() end,
    tasks = {install = conan_install}
}

return conan
