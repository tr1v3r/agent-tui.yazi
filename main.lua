local defaults = {
	dsh_bin = "dsh",
	node_bin = "node",
	profile = "dsh-tui",
}

-- setup() runs synchronously; entry() must read its configuration across
-- Yazi's sync boundary rather than from the isolated async plugin state.
local context = ya.sync(function(state)
	local paths = {}
	for _, file in pairs(cx.active.selected) do
		paths[#paths + 1] = tostring(file.url)
	end
	table.sort(paths)
	return paths, tostring(cx.active.current.cwd), state.targets, state.default, state.node_bin
end)

local function targets(opts)
	opts = opts or {}
	local result = {
		dsh = {
			command = { opts.dsh_bin or defaults.dsh_bin, "--profile", opts.profile or defaults.profile },
			adapter = "dsh-tui",
		},
		codex = { command = { "codex" }, adapter = "clipboard" },
		claude = { command = { "claude" }, adapter = "clipboard" },
	}
	for name, target in pairs(opts.targets or {}) do
		result[name] = target
	end
	return result
end

local function notify(content, level)
	ya.notify({ title = "AI CLI", content = content, level = level or "error", timeout = 5 })
end

local function validate(target)
	if type(target) ~= "table" or type(target.command) ~= "table" or #target.command == 0 then
		return "Target command must be a non-empty array, e.g. { 'codex' }."
	end
	for key, value in pairs(target.command) do
		if
			type(key) ~= "number"
			or key % 1 ~= 0
			or key < 1
			or key > #target.command
			or type(value) ~= "string"
			or value:find("%z")
		then
			return "Target command must be an array of strings without NUL bytes."
		end
	end
	for i = 1, #target.command do
		if type(target.command[i]) ~= "string" then
			return "Target command must be a contiguous array of strings."
		end
	end
	if target.command[1] == "" then
		return "Target executable must not be empty."
	end
	local adapter = target.adapter or "clipboard"
	if adapter ~= "dsh-tui" and adapter ~= "clipboard" and adapter ~= "none" then
		return "Unknown adapter: " .. tostring(adapter) .. ". Use dsh-tui, clipboard, or none."
	end
end

-- Plain quoted paths, independent of any CLI's file-mention grammar.
local function clipboard_text(paths)
	local lines = { "Selected files:" }
	for _, path in ipairs(paths) do
		lines[#lines + 1] = '"'
			.. path:gsub('[%z\1-\31\\"]', function(char)
				if char == "\\" or char == '"' then
					return "\\" .. char
				end
				return string.format("\\u%04x", char:byte())
			end)
			.. '"'
	end
	return table.concat(lines, "\n")
end

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
		state.node_bin = opts.node_bin or defaults.node_bin
		state.default = opts.default or "dsh"
		state.targets = targets(opts)
	end,

	entry = function(_, job)
		local paths, cwd, configured_targets, default_target, configured_node = context()
		local name = (job and job.args and job.args[1]) or default_target or "dsh"
		local target = (configured_targets or targets())[name]
		if not target then
			notify("Unknown target: " .. tostring(name) .. ". Configure it in setup().")
			return
		end
		local invalid = validate(target)
		if invalid then
			notify(invalid)
			return
		end

		local node_bin = configured_node or defaults.node_bin
		local adapter = target.adapter or "clipboard"
		if adapter == "clipboard" and #paths > 0 then
			local ok, err = pcall(ya.clipboard, clipboard_text(paths))
			if not ok then
				notify("Could not copy selected paths: " .. tostring(err))
				return
			end
			notify(
				"Selected file paths copied. Paste them into " .. name .. " and add your task before submitting.",
				"info"
			)
		end
		local command

		if adapter == "dsh-tui" and #paths > 0 then
			local inject = config_home() .. "/plugins/dsh-tui.yazi/assets/inject.mjs"
			command =
				Command(node_bin):arg({ inject, "--command", tostring(#target.command) }):arg(target.command):arg(paths)
		else
			command = Command(target.command[1]):arg({ table.unpack(target.command, 2) })
		end
		command:cwd(cwd)

		local permit = ui.hide()
		local ok, err = pcall(function()
			local child, spawn_err =
				command:stdin(Command.INHERIT):stdout(Command.INHERIT):stderr(Command.INHERIT):spawn()

			if child then
				local _, wait_err = child:wait()
				-- Keep exit diagnostics visible until the user returns to Yazi.
				-- Dropping the terminal permit immediately redraws over the resume hint.
				local pause, pause_err = Command(node_bin)
					:arg({
						"-e",
						[[
process.stdout.write('\nPress Enter to return to Yazi… ');
process.stdin.once('data', () => process.exit(0));
process.stdin.once('end', () => process.exit(0));
process.stdin.resume();
]],
					})
					:stdin(Command.INHERIT)
					:stdout(Command.INHERIT)
					:stderr(Command.INHERIT)
					:spawn()
				if pause then
					pause:wait()
				else
					return pause_err
				end
				return wait_err
			end
			return spawn_err
		end)
		permit:drop()

		if not ok or err then
			notify(tostring(err))
		end
	end,
}
