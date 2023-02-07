local function terraform_apply(module_config, _)
  local args = {"apply", "-auto-approve", "-no-color", "-input=false"}

  return {
    cmd = module_config.cmd,
    args = args,
  }
end

local function terraform_plan(module_config, _)
  local args = {"plan", "-no-color", "-input=false"}

  return {
    cmd = module_config.cmd,
    args = args,
    only_on_error = false
  }
end

local function terraform_validate(module_config, _)
  local args = {"validate", "-no-color"}

  return {
    cmd = module_config.cmd,
    args = args,
  }
end

local function terraform_init(module_config, _) 
  local args = {"init", "-no-color", "-input=false"}

  return {
    cmd = module_config.cmd,
    args = args,
  }
end

local terraform = {
  params = {
    'cmd',
  },
  condition = function ()
    return true
  end,
  tasks = {
    init = terraform_init,
    validate = {terraform_init, terraform_validate},
    plan = {terraform_init, terraform_validate, terraform_plan},
    apply = {terraform_init, terraform_validate, terraform_apply}
  }
}

return terraform
