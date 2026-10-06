# dsh-tui.yazi

Launch [dsh-TUI](https://dshtui.com/) from [Yazi](https://yazi-rs.github.io/)
and seed its editable prompt with files explicitly selected in Yazi.

![Select two files in Yazi and open them in an editable dsh-TUI prompt](docs/demo.gif)

- With no selection, dsh-TUI opens with an empty prompt. The hovered file is
  deliberately ignored.
- With one or more selected files, their paths are appended as `@file`
  mentions.
- The prompt is never submitted automatically, so you can keep typing before
  pressing Enter.
- After dsh-TUI exits, its session resume command and diagnostics stay visible.
  Press Enter to return to Yazi.

## Requirements

- Yazi 26.8 or newer
- Node.js ^22.19 or >=24
- `dsh` with a working `dsh-tui` profile

Tested on macOS. Linux and Windows integration feedback is welcome.

## Install

```sh
ya pkg add tr1v3r/dsh-tui
```

Bind the plugin in `~/.config/yazi/keymap.toml`:

```toml
[mgr]
prepend_keymap = [
	{ on = "<C-t>", run = "plugin dsh-tui", desc = "Launch DSH TUI with selected files" },
]
```

Restart Yazi after installing or upgrading the plugin.

## Configuration

The defaults run `dsh --profile dsh-tui` through `node`. Override them in
`~/.config/yazi/init.lua` when needed:

```lua
require("dsh-tui"):setup({
	dsh_bin = "dsh",
	node_bin = "node",
	profile = "dsh-tui",
})
```

`YAZI_CONFIG_HOME` and `XDG_CONFIG_HOME` are respected when locating the
installed plugin.

## How it works

The plugin reads `cx.active.selected`, hides Yazi while dsh-TUI owns the
terminal, and launches the configured profile. When files are selected, the
Node helper in `assets/inject.mjs` discovers the newly launched dsh-TUI
injection socket and sends only a `prompt.append` message. It never sends
`prompt.submit`. Keeping the helper under `assets/` ensures `ya pkg` deploys
it with the plugin.

Paths containing whitespace are quoted using dsh-TUI's `@"path with spaces"`
syntax. A path containing both whitespace and a literal double quote is
inserted as plain prompt text because dsh-TUI's mention grammar cannot
represent it safely.

## License

MIT
