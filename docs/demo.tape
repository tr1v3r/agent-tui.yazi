Output docs/demo.gif

Require yazi
Require dsh

Set Shell "bash"
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 17
Set Width 1200
Set Height 720
Set Padding 12
Set Framerate 12
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 1ms

Hide
Type `repo_root="$(pwd -P)"`
Enter
Type `demo_root="$(cd /tmp && pwd -P)/agent-tui-demo"`
Enter
Type `rm -rf "$demo_root"`
Enter
Type `mkdir -p "$demo_root/config/plugins/agent-tui.yazi/assets" "$demo_root/workspace"`
Enter
Type `cp "$repo_root/main.lua" "$demo_root/config/plugins/agent-tui.yazi/main.lua"`
Enter
Type `cp "$repo_root/assets/inject.mjs" "$demo_root/config/plugins/agent-tui.yazi/assets/inject.mjs"`
Enter
Type `printf '%s\n' '[mgr]' 'prepend_keymap = [' '  { on = "d", run = "plugin agent-tui", desc = "Launch dsh-TUI with selected files" },' ']' > "$demo_root/config/keymap.toml"`
Enter
Type `printf '%s\n' '# API specification' '' 'Public demo fixture.' > "$demo_root/workspace/api-spec.md"`
Enter
Type `printf '%s\n' 'Public demo notes.' > "$demo_root/workspace/notes with spaces.txt"`
Enter
Type `export YAZI_CONFIG_HOME="$demo_root/config"`
Enter
Type `cd "$demo_root/workspace"`
Enter
Type "clear"
Enter
Type "yazi"
Enter
Sleep 2s
Show

Space
Sleep 750ms
Space
Sleep 1s

Type "d"
Sleep 12s
