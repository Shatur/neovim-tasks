local path = require("plenary.path")
local os = require('ffi').os:lower()

local function notify_function(msg) 
	return function ()
		vim.notify(msg, "INFO", {
			title = "Conan"
		})
	end
end

local function conan_install(module_config, _)
	local build_folder = path:new(vim.loop.cwd(), "build", os .. "-" .. module_config.build_type)

	if not build_folder:exists() then
		build_folder:mkdir({parents = true})
	end

	local args = {"install", "--install-folder", build_folder.filename }

	table.insert(args, "./")
	return {
		cmd = module_config.cmd,
		args = args,
		after_success = notify_function("Conan installed successfully"),
	}
end

local conan = {
	params = {
		'cmd',
		build_type = {"debug", "release"}
	},
	condition = function ()
		return path:new('conanfile.txt'):exists()
	end,
	tasks = {
		install = conan_install
	}
}

return conan
