local defaults = {
	dsh_bin = "dsh",
	node_bin = "node",
	profile = "dsh-tui",
}

local selected = ya.sync(function()
	local paths = {}
	for _, file in pairs(cx.active.selected) do
		paths[#paths + 1] = tostring(file.url)
	end
	return paths
end)

local function config_home()
	local custom = os.getenv("YAZI_CONFIG_HOME")
	if custom and custom ~= "" then
		return custom
	end

	if ya.target_os() == "windows" then
		return os.getenv("APPDATA") .. "/yazi/config"
	end

	local xdg = os.getenv("XDG_CONFIG_HOME")
	if xdg and xdg ~= "" then
		return xdg .. "/yazi"
	end
	return os.getenv("HOME") .. "/.config/yazi"
end

return {
	setup = function(state, opts)
		opts = opts or {}
		state.dsh_bin = opts.dsh_bin or defaults.dsh_bin
		state.node_bin = opts.node_bin or defaults.node_bin
		state.profile = opts.profile or defaults.profile
	end,

	entry = function(state)
		local paths = selected()
		local dsh_bin = state.dsh_bin or defaults.dsh_bin
		local profile = state.profile or defaults.profile
		local command

		if #paths == 0 then
			command = Command(dsh_bin):arg({ "--profile", profile })
		else
			local inject = config_home() .. "/plugins/dsh-tui.yazi/assets/inject.mjs"
			command = Command(state.node_bin or defaults.node_bin)
				:arg({ inject, dsh_bin, profile })
				:arg(paths)
		end

		local permit = ui.hide()
		local child, err = command
			:stdin(Command.INHERIT)
			:stdout(Command.INHERIT)
			:stderr(Command.INHERIT)
			:spawn()

		if child then
			child:wait()
		end
		permit:drop()

		if err then
			ya.notify({ title = "DSH TUI", content = tostring(err), level = "error", timeout = 5 })
		end
	end,
}
