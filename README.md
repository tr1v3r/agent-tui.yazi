# dsh-tui.yazi

Launch AI command-line tools from [Yazi](https://yazi-rs.github.io/) with
files explicitly selected in Yazi. [dsh-TUI](https://dshtui.com/) is the
default; Codex, Claude Code, and custom commands are also supported.

![Select two files in Yazi and open them in an editable dsh-TUI prompt](docs/demo.gif)

- With no selection, the configured command launches without file input.
  The hovered file is deliberately ignored.
- With selected files, dsh-TUI receives editable `@file` mentions. Codex and
  Claude Code receive a quoted path list through the clipboard: paste it
  into the tool, add your task, then submit.
- The built-in targets never submit a prompt automatically.
- Every target starts in Yazi's current directory.
- After the tool exits, its session resume command and diagnostics stay visible.
  Press Enter to return to Yazi.

## Requirements

- Yazi 26.8 or newer
- Node.js ^22.19 or >=24
- The CLI you want to launch, available on `PATH` or configured by full path
- For the default target: `dsh` with a working `dsh-tui` profile
- For clipboard targets: working Yazi clipboard integration (a system
  clipboard helper or a terminal supporting OSC 52)

Tested on macOS. Linux and Windows integration feedback is welcome.

## Install

```sh
ya pkg add tr1v3r/dsh-tui
```

Bind the plugin in `~/.config/yazi/keymap.toml`:

```toml
[mgr]
prepend_keymap = [
	{ on = "<C-t>", run = "plugin dsh-tui", desc = "Launch default AI tool" },
	{ on = [ "g", "x" ], run = "plugin dsh-tui -- codex", desc = "Launch Codex with selected paths" },
	{ on = [ "g", "a" ], run = "plugin dsh-tui -- claude", desc = "Launch Claude Code with selected paths" },
]
```

Restart Yazi after installing or upgrading the plugin.

## Targets

The built-in targets work without `setup()`:

| Target | Command | File adapter |
| --- | --- | --- |
| `dsh` (default) | `dsh --profile dsh-tui` | `dsh-tui` |
| `codex` | `codex` | `clipboard` |
| `claude` | `claude` | `clipboard` |

Pass a target name after `--` in the keybinding, or set `default` in
`~/.config/yazi/init.lua`. Add or replace targets with `targets`:

```lua
require("dsh-tui"):setup({
	default = "codex",
	targets = {
		work = {
			command = { "dsh", "--profile", "work-tui" },
			adapter = "dsh-tui",
		},
		codex = {
			command = { "codex", "--profile", "work" },
			adapter = "clipboard",
		},
		claude = {
			command = { "claude", "--model", "sonnet" },
			adapter = "clipboard",
		},
		custom = {
			command = { "/path/to/my-agent", "--mode", "interactive" },
			adapter = "clipboard",
		},
	},
})
```

For the `work` target, bind `plugin dsh-tui -- work`. Each named target
replaces that target's complete configuration; other targets remain available.
Commands are arrays of executable and arguments, passed directly without a
shell. Paths with spaces remain single arguments.

Available adapters:

- **`dsh-tui`**: use dsh-TUI's injection socket to append an editable draft.
  The selected DSH profile must load dsh-TUI and expose its injection protocol.
  The adapter supports arbitrary launch arguments, including another profile.
- **`clipboard`** (also the default for custom targets): copy selected paths
  as plain quoted text, then launch the command without a prompt argument.
  This replaces the clipboard only when files are selected. File contents are
  not copied; the agent can read the paths when you submit your task. Quotes,
  backslashes, and control characters use JSON string escaping.
- **`none`**: launch only, without passing selected files. Useful for profiles
  that do not provide a terminal prompt or for wrappers handling context themselves.

Only launch commands suited to taking over the terminal. A web or headless
profile does not gain an editable terminal prompt by selecting it here.
For custom commands, any configured prompt arguments retain that CLI's own
submission behavior.

## Legacy configuration

Existing configurations continue to work. These options configure the built-in
`dsh` target and the Node executable used for injection and the return prompt:

```lua
require("dsh-tui"):setup({
	dsh_bin = "dsh",
	node_bin = "node",
	profile = "dsh-tui",
})
```

An explicit `targets.dsh` configuration takes precedence over `dsh_bin` and
`profile`. The install name, Lua module name, and `plugin dsh-tui` binding
remain compatible.

`YAZI_CONFIG_HOME` and `XDG_CONFIG_HOME` are respected when locating the
installed plugin.

## How it works

The plugin reads `cx.active.selected`, resolves the requested target, and hides
Yazi while the command owns the terminal. For the `dsh-tui` adapter with
selected files, the Node helper in `assets/inject.mjs` discovers the newly launched dsh-TUI
injection socket and sends only a `prompt.append` message. It never sends
`prompt.submit`. Keeping the helper under `assets/` ensures `ya pkg` deploys
it with the plugin.

Paths containing whitespace are quoted using dsh-TUI's `@"path with spaces"`
syntax. A path containing both whitespace and a literal double quote is
inserted as plain prompt text because dsh-TUI's mention grammar cannot
represent it safely.

## Development

```sh
luac -p main.lua
node --check assets/inject.mjs
node --test
lua test/main.test.lua
```

## License

MIT
