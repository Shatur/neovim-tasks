local config = require('tasks.config')
local Job = require('plenary.job')
local utils = require('tasks.utils')
local runner = {}

local last_job

---@param lines table
---@param errorformat string?
local function append_to_quickfix(lines, errorformat)
  vim.fn.setqflist({}, 'a', { efm = errorformat, lines = lines })
  -- Scrolls the quickfix buffer if not active
  if vim.bo.buftype ~= 'quickfix' then
    vim.api.nvim_command('cbottom')
  end
end

---@param errorformat? string
---@return function: A coroutine that reads job data into quickfix.
local function read_to_quickfix(errorformat)
  -- Modified from https://github.com/nvim-lua/plenary.nvim/blob/968a4b9afec0c633bc369662e78f8c5db0eba249/lua/plenary/job.lua#L287
  -- We use our own implementation to process data in chunks because
  -- default Plenary callback processes every line which is very slow for adding to quickfix.
  return coroutine.wrap(function(err, data, is_complete)
    -- We repeat forever as a coroutine so that we can keep calling this.
    local lines = {}
    local result_index = 1
    local result_line = nil
    local found_newline = nil

    while true do
      if data then
        data = data:gsub('\r', '')

        local processed_index = 1
        local data_length = #data + 1

        repeat
          local start = data:find('\n', processed_index, true) or data_length
          local line = data:sub(processed_index, start - 1)
          found_newline = start ~= data_length

          -- Concat to last line if there was something there already.
          --    This happens when "data" is broken into chunks and sometimes
          --    the content is sent without any newlines.
          if result_line then
            result_line = result_line .. line

            -- Only put in a new line when we actually have new data to split.
            --    This is generally only false when we do end with a new line.
            --    It prevents putting in a "" to the end of the results.
          elseif start ~= processed_index or found_newline then
            result_line = line

            -- Otherwise, we don't need to do anything.
          end

          if found_newline then
            if not result_line then
              return vim.api.nvim_err_writeln('Broken data thing due to: ' .. tostring(result_line) .. ' ' .. tostring(data))
            end

            table.insert(lines, err and err or result_line)

            result_index = result_index + 1
            result_line = nil
          end

          processed_index = start + 1
        until not found_newline
      end

      if is_complete and not found_newline then
        table.insert(lines, err and err or result_line)
      end

      if #lines ~= 0 then
        -- Move lines to another variable and send them to quickfix
        local processed_lines = lines
        lines = {}
        vim.schedule(function() append_to_quickfix(processed_lines, errorformat) end)
      end

      if data == nil or is_complete then
        return
      end

      err, data, is_complete = coroutine.yield()
    end
  end)
end

--- Run specified commands in chain.
---@param task_name string: Name of a task to read properties.
---@param commands table: Commands to chain.
---@param module_config table: Module configuration.
---@param addition_args table?: Additional arguments that will be applied to the last command.
---@param previous_job table?: Previous job to read data from, used by this function for recursion.
function runner.chain_commands(task_name, commands, module_config, addition_args, previous_job)
  local command = commands[1]
  if vim.is_callable(command) then
    command = command(module_config, previous_job)
    if not command then
      return
    end
  end

  local cwd = command.cwd or vim.uv.cwd()
  local args = command.args and command.args or {}
  local env = vim.tbl_extend('force', vim.uv.os_environ(), command.env and command.env or {})
  if #commands == 1 then
    -- Apply task parameters only to the last command
    vim.list_extend(args, addition_args)
    vim.list_extend(args, vim.tbl_get(module_config, 'args', task_name) or {})
    env = vim.tbl_extend('force', env, vim.tbl_get(module_config, 'env', task_name) or {})
  end

  if command.dap_name then
    vim.schedule(function()
      local dap = require('dap')
      local dap_config = dap.configurations[command.dap_name] -- Try to get an existing configuration
      local dap_config_args = {
        name = command.cmd,
        request = 'launch',
        program = command.cmd,
        args = args,
        cwd = cwd,
      }
      if command.dap_config then
        dap_config_args = vim.tbl_extend('force', dap_config_args, command.dap_config)
      end
      dap.run(vim.tbl_extend('force', dap_config and dap_config or { type = command.dap_name }, dap_config_args))
      if config.dap_open_command then
        vim.api.nvim_command('cclose')
        config.dap_open_command()
      end
      last_job = dap
    end)
    return
  end

  if vim.fn.executable(command.cmd) == 0 then
    utils.notify(string.format('Command "%s" is not executable', command.cmd), vim.log.levels.ERROR)
    return
  end

  local quickfix_output = not command.ignore_stdout or not command.ignore_stderr
  local job = Job:new({
    command = command.cmd,
    args = args,
    cwd = cwd,
    env = env,
    enable_recording = #commands ~= 1,
    on_start = quickfix_output and vim.schedule_wrap(function()
      vim.fn.setqflist({}, ' ', { title = command.cmd .. ' ' .. table.concat(args, ' ') })
      vim.api.nvim_command(string.format('%s copen %d', config.quickfix.pos, config.quickfix.height))
      vim.api.nvim_command('wincmd p')
    end) or nil,
    on_exit = vim.schedule_wrap(function(_, code, signal)
      if quickfix_output then
        append_to_quickfix({ 'Exited with code ' .. (signal == 0 and code or 128 + signal) })
      end
      if code == 0 and signal == 0 and command.after_success then
        command.after_success()
      end
    end),
  })

  job:start()
  if not command.ignore_stdout then
    job.stdout:read_start(read_to_quickfix(command.errorformat))
  end
  if not command.ignore_stderr then
    job.stderr:read_start(read_to_quickfix(command.errorformat))
  end

  if #commands ~= 1 then
    job:after_success(vim.schedule_wrap(function() runner.chain_commands(task_name, vim.list_slice(commands, 2), module_config, addition_args, job) end))
  end
  last_job = job
end

---@return string?
function runner.get_current_job_name()
  if not last_job then
    return nil
  end

  -- Check if this job was run through debugger.
  if last_job.session then
    local session = last_job.session()
    if not session then
      return nil
    end
    return session.config.program
  end

  if last_job.is_shutdown then
    return nil
  end

  return last_job.command
end

---@return boolean: `true` if a job was canceled or `false` if there is no active job.
function runner.cancel_job()
  if not last_job then
    return false
  end

  -- Check if this job was run through debugger.
  if last_job.session then
    if not last_job.session() then
      return false
    end
    last_job.terminate()
    return true
  end

  if last_job.is_shutdown then
    return false
  end

  last_job:shutdown(1, 9)

  if vim.fn.has('win32') == 1 or vim.fn.has('mac') == 1 then
    -- Kill all children.
    for _, pid in ipairs(vim.api.nvim_get_proc_children(last_job.pid)) do
      vim.uv.kill(pid, 9)
    end
  else
    vim.uv.kill(last_job.pid, 9)
  end
  return true
end

return runner
