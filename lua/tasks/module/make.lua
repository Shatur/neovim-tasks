local Path = require('plenary.path')

return {
  params = { 'cmd' },
  condition = function() return Path:new('Makefile'):exists() end,

  -- This module supports dynamic tasks by using the `__index` metamethod.
  -- By default, for any string `<task>`, calling `Task start make <task>`
  -- will run `make <task>` (i.e., dynamic tasks are mapped to make targets).
  -- This behavior can be customized by overriding the task 'args' parameters
  -- in the `default_params` provided on setup.
  tasks = setmetatable({}, {
    __index = function(_, target)
      return function(module_config, _)
        return {
          cmd = module_config.cmd,
          args = module_config.args and module_config.args[target] or { target },
        }
      end
    end,
  }),
}
