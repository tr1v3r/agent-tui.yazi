-- Exercise the plugin entry point with Yazi's host APIs stubbed out.
local fixture
ya = {
	sync = function(fn)
		return function(...)
			return fn(fixture.state, ...)
		end
	end,
	target_os = function()
		return "linux"
	end,
	notify = function(message)
		fixture.notifications[#fixture.notifications + 1] = message
	end,
	clipboard = function(text)
		if fixture.clipboard_error then
			error(fixture.clipboard_error)
		end
		fixture.clipboard = text
	end,
}
ui = {
	hide = function()
		fixture.hidden = true
		return {
			drop = function()
				fixture.dropped = true
			end,
		}
	end,
}
Command = setmetatable({ INHERIT = "inherit" }, {
	__call = function(_, executable)
		local cmd = { executable = executable, args = {} }
		function cmd:arg(args)
			for _, arg in ipairs(args) do
				self.args[#self.args + 1] = arg
			end
			return self
		end
		function cmd:cwd(cwd)
			self.directory = cwd
			return self
		end
		for _, stream in ipairs({ "stdin", "stdout", "stderr" }) do
			cmd[stream] = function(self, mode)
				self[stream .. "_mode"] = mode
				return self
			end
		end
		function cmd:spawn()
			fixture.commands[#fixture.commands + 1] = self
			local index = #fixture.commands
			local spawn_err = fixture.spawn_error or (fixture.spawn_errors or {})[index]
			if spawn_err then
				return nil, spawn_err
			end
			return {
				wait = function()
					if fixture.wait_error then
						error(fixture.wait_error)
					end
					local wait_err = (fixture.wait_errors or {})[index]
					if wait_err then
						return nil, wait_err
					end
					return { success = true }
				end,
			}
		end
		return cmd
	end,
})

local plugin = dofile("main.lua")
local function launch(opts, name, paths)
	fixture = { commands = {}, notifications = {} }
	cx = { active = { selected = {}, current = { cwd = "/work/current" }, hovered = { url = "/work/hovered" } } }
	for i, path in ipairs(paths or {}) do
		cx.active.selected[i] = { url = path }
	end
	local state = {}
	if opts then
		plugin.setup(state, opts)
	end
	fixture.state = state
	return function()
		-- Yazi creates an isolated state for each async invocation.
		plugin.entry({}, { args = { name } })
		return fixture
	end
end

local function equal(actual, expected)
	assert(actual == expected, string.format("Expected %q, got %q", tostring(expected), tostring(actual)))
end

local passed = 0
local function test(name, fn)
	fn()
	passed = passed + 1
	print("ok - " .. name)
end

test("default launch ignores hovered file and uses Yazi's current directory", function()
	local result = launch()()
	local cmd = result.commands[1]
	equal(cmd.executable, "dsh")
	equal(table.concat(cmd.args, "|"), "--profile|dsh-tui")
	equal(cmd.directory, "/work/current")
	equal(cmd.stdin_mode, "inherit")
	equal(cmd.stdout_mode, "inherit")
	equal(cmd.stderr_mode, "inherit")
	assert(result.dropped)
	assert(result.commands[2].args[2]:find("Press Enter to return to Yazi", 1, true))
end)

test("legacy executable, profile, and node options still control DSH injection", function()
	local result = launch(
		{ dsh_bin = "/bin/my dsh", profile = "work-tui", node_bin = "node-custom" },
		nil,
		{ "/work/two files", "/work/one" }
	)()
	local cmd = result.commands[1]
	equal(cmd.executable, "node-custom")
	assert(cmd.args[1]:match("/plugins/agent%-tui.yazi/assets/inject.mjs$"))
	equal(table.concat(cmd.args, "|", 2), "--command|3|/bin/my dsh|--profile|work-tui|/work/one|/work/two files")
	equal(cmd.directory, "/work/current")
	equal(result.clipboard, nil)
end)

test("Codex receives no prompt arguments and copies only marked selections", function()
	local result = launch(nil, "codex", { "/work/one", "/work/two files" })()
	equal(result.commands[1].executable, "codex")
	equal(#result.commands[1].args, 0)
	equal(result.clipboard, 'Selected files:\n"/work/one"\n"/work/two files"')
	equal(result.notifications[1].level, "info")
end)

test("Claude starts without touching the clipboard when nothing is selected", function()
	local result = launch(nil, "claude")()
	equal(result.commands[1].executable, "claude")
	equal(#result.commands[1].args, 0)
	equal(result.clipboard, nil)
end)

test("clipboard paths escape quotes, backslashes, newlines, and control characters", function()
	local path = '/work/a"\\\n\t\1.txt'
	local result = launch(nil, "claude", { path })()
	equal(result.clipboard, 'Selected files:\n"/work/a\\"\\\\\\u000a\\u0009\\u0001.txt"')
end)

test("custom default command preserves arguments without shell interpolation", function()
	local result = launch({
		default = "custom",
		targets = {
			custom = { command = { "/bin/agent with spaces", "--model", "$(touch /tmp/nope); `id`" } },
		},
	}, nil, { "/work/file" })()
	equal(result.commands[1].executable, "/bin/agent with spaces")
	equal(table.concat(result.commands[1].args, "|"), "--model|$(touch /tmp/nope); `id`")
	assert(result.clipboard)
end)

test("named target overrides the configured default", function()
	local result = launch({ default = "claude" }, "codex")()
	equal(result.commands[1].executable, "codex")
end)

test("DSH target allows additional arguments and a different profile", function()
	local result = launch(
		{ targets = {
			work = { command = { "dsh", "--profile", "work-tui", "--debug" }, adapter = "dsh-tui" },
		} },
		"work",
		{ "/work/file" }
	)()
	equal(table.concat(result.commands[1].args, "|", 2), "--command|4|dsh|--profile|work-tui|--debug|/work/file")
end)

test("explicit dsh target takes precedence over legacy profile options", function()
	local result = launch({
		profile = "legacy",
		targets = {
			dsh = { command = { "wrapper", "--profile", "explicit" }, adapter = "dsh-tui" },
		},
	})()
	equal(result.commands[1].executable, "wrapper")
	equal(table.concat(result.commands[1].args, "|"), "--profile|explicit")
end)

test("none adapter deliberately launches without file injection", function()
	local result = launch(
		{ targets = {
			web = { command = { "dsh", "--profile", "web" }, adapter = "none" },
		} },
		"web",
		{ "/work/file" }
	)()
	equal(result.commands[1].executable, "dsh")
	equal(table.concat(result.commands[1].args, "|"), "--profile|web")
	equal(result.clipboard, nil)
end)

test("unknown targets fail before hiding Yazi or changing the clipboard", function()
	local result = launch(nil, "missing", { "/work/file" })()
	equal(#result.commands, 0)
	equal(result.hidden, nil)
	equal(result.clipboard, nil)
	assert(result.notifications[1].content:find("Unknown target", 1, true))
end)

test("invalid targets fail before launching", function()
	for _, target in ipairs({
		{ command = "codex" },
		{ command = {} },
		{ command = { "" } },
		{ command = { "codex", 42 } },
		{ command = { "codex", "a\0b" } },
		{ command = { "codex", [3] = "gap" } },
		{ command = { "codex", flag = "extra" } },
		{ command = { "codex" }, adapter = "typo" },
	}) do
		local result = launch({ targets = { invalid = target } }, "invalid", { "/work/file" })()
		equal(#result.commands, 0)
		equal(result.hidden, nil)
		equal(result.clipboard, nil)
		equal(result.notifications[1].level, "error")
	end
end)

test("clipboard API errors leave Yazi visible and abort the launch", function()
	local run = launch(nil, "codex", { "/work/file" })
	fixture.clipboard_error = "clipboard unavailable"
	local result = run()
	equal(#result.commands, 0)
	equal(result.hidden, nil)
	assert(result.notifications[1].content:find("Could not copy selected paths", 1, true))
end)

test("spawn failures restore Yazi and report an error", function()
	local run = launch(nil, "codex")
	fixture.spawn_error = "executable not found"
	local result = run()
	assert(result.dropped)
	equal(#result.commands, 1)
	equal(result.notifications[1].content, "executable not found")
end)

test("unexpected runtime errors still release Yazi's terminal", function()
	local run = launch()
	fixture.wait_error = "wait failed"
	local result = run()
	assert(result.dropped)
	assert(result.notifications[1].content:find("wait failed", 1, true))
end)

test("tool wait errors survive a subsequent pause spawn failure", function()
	local run = launch()
	fixture.wait_errors = { [1] = "tool wait failed" }
	fixture.spawn_errors = { [2] = "pause spawn failed" }
	local result = run()
	assert(result.dropped)
	equal(#result.commands, 2)
	equal(result.notifications[1].content, "tool wait failed\nReturn-to-Yazi pause: pause spawn failed")
end)

test("tool and pause wait errors are both reported", function()
	local run = launch()
	fixture.wait_errors = { "tool wait failed", "pause wait failed" }
	local result = run()
	assert(result.dropped)
	equal(result.notifications[1].content, "tool wait failed\nReturn-to-Yazi pause: pause wait failed")
end)

test("single tool or pause errors remain visible", function()
	for _, errors in ipairs({
		{ wait_errors = { [1] = "tool wait failed" }, expected = "tool wait failed" },
		{ wait_errors = { [2] = "pause wait failed" }, expected = "pause wait failed" },
		{ spawn_errors = { [2] = "pause spawn failed" }, expected = "pause spawn failed" },
	}) do
		local run = launch()
		fixture.wait_errors = errors.wait_errors
		fixture.spawn_errors = errors.spawn_errors
		local result = run()
		assert(result.dropped)
		equal(result.notifications[1].content, errors.expected)
	end
end)

print(string.format("%d plugin tests passed", passed))
