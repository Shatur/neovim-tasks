local Path = require('plenary.path')

local config = {
  defaults = {
  default_params = { -- Default module parameters with which `neovim.json` will be created.
    cmake = {
      cmd = 'cmake', -- CMake executable to use, can be changed using `:Task set_module_param cmake cmd`.
      build_type = 'Debug', -- Build type, can be changed using `:Task set_module_param cmake build_type`.
      build_kit = 'default',  -- default build kit, can be changed using `:Task set_module_param cmake build_kit`.
      dap_name = 'codelldb', -- DAP configuration name from `require('dap').configurations`. If there is no such configuration, a new one with this name as `type` will be created.
      build_dir = tostring(Path:new('{cwd}', 'build', '{build_kit}', '{build_type}')), -- Build directory. The expressions `{cwd}`, `{build_kit}` and `{build_type}` will be expanded with the corresponding text values. Could be a function that return the path to the build directory.
      cmake_kits_file = nil, -- set path to JSON file containing cmake kits
      cmake_build_types_file = nil, -- set path to JSON file containing cmake kits
      clangd_cmdline = { 'clangd', '--background-index', '--clang-tidy', '--header-insertion=never', '--completion-style=detailed', '--offset-encoding=utf-8', '--pch-storage=memory', '--cross-file-rename', '-j=4' }, -- command line for invoking clangd - this array will be extended with --compile-commands-dir and --query-driver after each cmake configure with parameters inferred from build_kit, build_type and build_dir
    },
    zig = {
      cmd = 'zig',            -- zig command which will be invoked
      dap_name = 'codelldb',  -- DAP configuration name from `require('dap').configurations`. If there is no such configuration, a new one with this name as `type` will be created.
      build_type = 'Debug',   -- build type, can be changed using `:Task set_module_param zig build_type`
      build_step = 'install', -- build step, cah be changed using `:Task set_module_param zig build_step`
    },
    cargo = {
        dap_name = 'codelldb',  -- DAP configuration name from `require('dap').configurations`. If there is no such configuration, a new one with this name as `type` will be created.
    },
    npm = {
        cmd = 'npm',                         -- npm command which will be invoked. If using yarn or pnpm, change here.
        working_directory = vim.loop.cwd(),  -- working directory in which NPM will be invoked
    },
    make = {
      cmd = 'make',                 -- make command which will be invoked
      args = {
        all = { '-j10', 'all' },    -- :Task start make all   → make -j10 all
        build = {},                 -- :Task start make build → make
        nuke = { 'clean' },         -- :Task start make nuke  → make clean
      },
    },
  },
    save_before_run = true,
    params_file = 'neovim.json',
    quickfix = {
      pos = 'botright',
      height = 12,
      only_on_error = false,
    },
    dap_open_command = function() return require('dap').repl.open() end,
  },
}

setmetatable(config, { __index = config.defaults })

return config
