local Path = require('plenary.path')

local config = {
  defaults = {
    default_params = {
      cmake = {
        cmd = 'cmake',
        build_dir = tostring(Path:new('{cwd}', 'build', '{os}-{build_type}')),
        build_type = 'Debug',
        dap_name = 'lldb',
        args = {
          configure = { '-D', 'CMAKE_EXPORT_COMPILE_COMMANDS=1', '-G', 'Ninja' },
        },
      },
      cargo = {
        dap_name = 'lldb',
      },
      conan = {
        cmd = "conan",
        build_type = "debug"
      },
      terraform = {
        cmd = "terraform",
      }
    },
    notifications = {
      on_exit = true,
      on_enter = false
    },
    save_before_run = true,
    params_file = 'neovim.json',
    quickfix = {
      pos = 'botright',
      height = 12,
      only_on_error = false
    },
    dap_open_command = function() return require('dap').repl.open() end,
  },
}

setmetatable(config, { __index = config.defaults })

return config
