local Path = require('plenary.path')
local zig = {}

--- Task
---@param module_config table
---@return table
local function build(module_config, _)
  return {
    cmd = module_config.cmd,
    args = { 'build' },
  }
end

--- Task
---@param module_config table
---@return table
local function run(module_config, _)
  return {
    cmd = module_config.cmd,
    args = { 'build', 'run' },
  }
end

--- Task
---@param module_config table
---@return table
local function test(module_config, _)
  return {
    cmd = module_config.cmd,
    args = { 'build', 'test' },
  }
end

zig.params = {}
zig.condition = function() return Path:new('build.zig'):exists() end
zig.tasks = {
  build = build,
  run = run,
  test = test,
}

return zig
