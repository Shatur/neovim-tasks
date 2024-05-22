if not vim.fn.has('nvim-0.10.0') then
  require('tasks.utils').notify('Neovim 0.10+ is required for tasks plugin', vim.log.levels.ERROR)
  return
end

local subcommands = require('tasks.subcommands')

vim.api.nvim_create_user_command('Task', subcommands.run, { nargs = '*', complete = subcommands.complete, desc = 'Run or configure a task' })
