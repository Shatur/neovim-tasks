# Neovim Tasks

A Neovim plugin that provides a stateful task system focused on integration with build systems.

Tasks in this plugin are provided by modules that implement functionality for a specific build system. Modules can have custom parameters which user can set via `:Task set_module_param` (like current target or build type). Tasks consists of one or more commands and have `args` and `env` parameters to set arguments and environment variable respectively. All this settings are serializable and will be stored in configuration file in your project directory.

## Dependencies

- Necessary
  - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for internal helpers.
- Optional
  - [nvim-dap](https://github.com/mfussenegger/nvim-dap) - for debugging.

## Features

- Output directly into quickfix for fast navigation.
- Tasks provided by modules which can have custom parameters.
- Modules are lazy loaded.
- Module for a task name could be determined automatically based on its condition.
- Tasks can run through debugger.
- Tasks can be chained and react on the previous output.
- Task and module parameters are serializable and specific to the current working directly.
- Tasks arguments could be read from parameters and / or extended via additional temporary arguments passed to `:Task` command.

## Available modules

- [CMake](https://cmake.org) via [cmake-file-api](https://cmake.org/cmake/help/latest/manual/cmake-file-api.7.html#codemodel-version-2).
- [Cargo](https://doc.rust-lang.org/cargo).
- [GNU Make](https://www.gnu.org/software/make/)
- [Zig](https://ziglang.org/learn/build-system/)
- [NPM](https://www.npmjs.com/)

You can also write [your own module](#modules-creation-and-configuration).

## Commands

Use the command `:Task` with one of the following arguments:

| Argument(s)                              | Description                                                                  |
| ---------------------------------------- | ---------------------------------------------------------------------------- |
| `start <module> <task>`                  | Starting a task from a module.                                               |
| `set_module_param <module> <param>`      | Set parameter for a module. All parameters are module-specific.              |
| `set_task_param <module> <param> <task>` | Set parameter for a task from a module. The parameter can be `arg` or `env`. |
| `cancel`                                 | Cancel currently running task.                                               |

Modules and tasks will be autocompleted.

Module name can be `auto`, in which case the first module that satisfies the condition will be used.

## Configuration

To configure the plugin, you can call `require('tasks').setup(values)`, where `values` is a dictionary with the parameters you want to override. Here are the defaults:

```lua
local Path = require('plenary.path')
require('tasks').setup({
  default_params = { -- Default module parameters with which `neovim.json` will be created.
    cmake = {
      cmd = 'cmake', -- CMake executable to use, can be changed using `:Task set_module_param cmake cmd`.
      build_dir = tostring(Path:new('{cwd}', 'build', '{os}-{build_type}')), -- Build directory. The expressions `{cwd}`, `{os}` and `{build_type}` will be expanded with the corresponding text values. Could be a function that return the path to the build directory.
      build_type = 'Debug', -- Build type, can be changed using `:Task set_module_param cmake build_type`.
      dap_name = 'lldb', -- DAP configuration name from `require('dap').configurations`. If there is no such configuration, a new one with this name as `type` will be created.
      args = { -- Task default arguments.
        configure = { '-D', 'CMAKE_EXPORT_COMPILE_COMMANDS=1', '-G', 'Ninja' },
      },
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
  save_before_run = true, -- If true, all files will be saved before executing a task.
  params_file = 'neovim.json', -- JSON file to store module and task parameters.
  quickfix = {
    pos = 'botright', -- Default quickfix position.
    height = 12, -- Default height.
  },
  dap_open_command = function() return require('dap').repl.open() end, -- Command to run after starting DAP session. You can set it to `false` if you don't want to open anything or `require('dapui').open` if you are using https://github.com/rcarriga/nvim-dap-ui
```

## Usage examples

### CMake

1. Open a CMake project.
2. Run `configuration` task using `:Task start cmake configure`.
3. Select a target by specifying module parameter with `:Task set_module_param cmake target`. All module parameters are specific to modules. Since CMake can't run targets like Cargo, we introduced a parameter to select the same target for building (appropriate arguments will be passed to CMake automatically) and running.
4. Optionally set arguments using `:Task set_task_param cmake run`.
5. Build and run the project via `:Task start cmake run` or build and debug using `:Task start cmake debug`. You can pass additional arguments to these commands, which will be temporarily added to the arguments from the previous step.

### Cargo

1. Open a Cargo project.
2. Optionally set arguments using `:Task set_task_param cargo run`.
3. Optionally set global cargo arguments using `:Task set_task_param cargo global_cargo_args`.
4. Build and run the project via `:Task start cargo run` or build and debug using `:Task start cargo debug`.

Cargo module doesn't have a `target` param which specific to CMake because `cargo run` automatically pick the binary. If there is multiple binaries, you can set which one you want to run using `--bin` or `--project` in step 2 as you do in CLI.

### GNU Make

1. Open a Make project.
2. Run a Make target `<target>` with `:Task start make <target>`.

To override targets or add custom `make` options, configure the appropriate task:

```lua
require('tasks').setup({
  default_params = {
    ...
    make = {
      cmd = 'make',
      args = {
        all = { '-j10', 'all' },    -- :Task start make all   → make -j10 all
        build = {},                 -- :Task start make build → make
        nuke = { 'clean' },         -- :Task start make nuke  → make clean
      },
    },
    ...
  }
})
```

### Zig

#### Quick start with a zig file

1. Open zig file that contains `main`
2. Run `:Task start zig run_file`
3. To start debugging the file, run `:Task start zig debug_file`

#### Quick start with a project that contains `build.zig` file

1. Open Zig project
2. Select a build step with `:Task set_module_param zig build_step`.
3. Select a build type with `:Task set_module_param zig build_type`
4. Run selected build step with `:Task start zig build`

#### All available zig tasks

- `build` - invokes `zig build` with step configured as `build_step` with build type configured as `build_type`
- `clean` - deletes the `zig-out` folder (works only on Unix shells at the moment)
- `clean_cache` - deletes the `.zig-cache` folder (works only on Unix shells at the moment)
- `clean_all` - invokes forst `clean`, then `clean_cache`
- `run_file` - invokes `zig run` for currently open buffer. Obeys `build_type`
- `debug_file` - starts debugger for currently open buffer (effectively as `run_file`, but under debugger)
- `test_file` - invokes `zig test` for currently open buffer. Obeys `build_type`.
- `debug_test_file` -same as `test_file`, but under debugger
- `run_current_test` - invokes `zig test` for currently open buffer with test filter set to a first test above current cursor location. If test filter cannot be calculated, all tests in current file are run (behavior same as `test_file`).
- `debug_current_test` - same as `run_current_test`, but under debugger

### NPM

1. Open a NPM project
2. Run `:Task start npm install`
3. You can also run any NPM script using `:Task start npm run <script>`

For example, imagine that your `package.json` contains lines like these:

```json
{
    "scripts": {
        "clean": "rimraf build dist",
        "lint": "eslint --ext ts -c .eslintrc.json src",
        "start": "NODE_PATH=$(pwd)/node_modules node $(pwd)/../core/scripts/https-serve.js dist",
        "rollup": "rollup -c rollup.config.js",
    }
}
```

You can map then those commands with code like this:

```lua
vim.keymap.set( "n", "<leader>ni", [[:Task start npm install<cr>]] )
vim.keymap.set( "n", "<leader>nl", [[:Task start npm run lint<cr>]] )
vim.keymap.set( "n", "<leader>nr", [[:Task start npm run rollup<cr>]] )
vim.keymap.set( "n", "<leader>ns", [[:Task start npm run clean<cr>]] )
vim.keymap.set( "n", "<leader>ns", [[:Task start npm run start<cr>]] )
```


## Modules creation and configuration

To create a module just put a lua file under `lua/tasks/module` in your configuration or submit your module as a PR. In this module you need to return a table with the following fields:

```lua
{
  params = {
    -- A table of parameter names. Possible values:
    'parameter_name1', -- A string parameter, on setting user will be prompted with vim.ui.input.
    parameter_name2 = { 'one', 'two' }, -- A table with possible values, on setting user will be prompted with vim.ui.select to pick one of these values.
    parameter_name3 = func, -- A function that generates a string or a table.
  }
  condition = function() return Path:new('file'):exists() end -- A function that returns `true` if this module could be applied to this directory. Used when `auto` is used as module name.
  tasks = {
    -- A table of module tasks. Possible values:
    task_name1 = {
      -- Required parameters:
      cmd = 'command' -- Command to execute.
      -- Optional parameters:
      cwd = 'directory' -- Command working directory. Default to current working directory.
      after_success = callback -- A callback to execute on success.
      dap_name = 'dap_name' -- A debug adapter name. If exists, the task will be launched through the adapter. Usually taken from a module parameter. Implies ignoring all streams below.
      -- Disable a stream output to quickfix. If both are disabled, quickfix will not show up. If you want to capture output of a stream in a next task, you need to disable it.
      ignore_stdout = true,
      ignore_stderr = true,
    },
    task_name2 = func1, -- A function that returns a table as above. Accepts configuration for this module and previous job.
    task_name3 = { func2, func3 }, -- A list of functions as above. Tasks will be executed in chain.
  }
}
```

For a more complex example take a look at [cargo.lua](lua/tasks/module/cargo.lua).

You can also edit existing modules in right in your config. Just import a module using `require('tasks.module.module_name')` and add/remove/modify any fields from the above.
