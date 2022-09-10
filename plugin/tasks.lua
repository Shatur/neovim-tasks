if vim.version().minor < 7 then
  require('tasks.utils').notify('Neovim 0.7+ is required for tasks plugin', vim.log.levels.ERROR)
  return
end

local subcommands = require('tasks.subcommands')

vim.api.nvim_create_user_command('Task', subcommands.run, { nargs = '*', complete = subcommands.complete, desc = 'Run or configure a task' })
