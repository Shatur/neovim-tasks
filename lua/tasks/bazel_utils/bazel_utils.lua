local Path = require('plenary.path')
local ProjectConfig = require('tasks.project_config')

local BazelUtils = {}

-- Returns the currently active Bazel target and path to it's executable
-- @return string, Path
function BazelUtils.getCurrentTargetAndExePath()
  local bazelConfig = ProjectConfig:new()['bazel']

  local currentWorkDir = Path:new(vim.fn.getcwd())
  local target = string.gsub(bazelConfig.target, '^//', '')
  target = string.gsub(target, ':', '/')
  local targetPath = currentWorkDir / Path:new('bazel-bin') / Path:new(target)
  return bazelConfig.target, tostring(targetPath)
end


return BazelUtils
