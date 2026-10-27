# tmux-motion

Small transitions for tmux. The active pane pulses when focus moves, new
panes slide open, and killed panes slide shut. Pure shell, one `@plugin`
line, no dependencies beyond tmux itself.

tmux has no animation engine and redraws only when state changes, so these are
short stepped effects (a handful of frames inside 160 to 180 ms), not smooth
60 fps motion. They are meant to be felt as a hint of movement, not watched.

## Effects

| Effect | Trigger | Default |
| ------ | ------- | ------- |
| Flash  | focus moves to another pane, window or session; a pane or window is killed and focus lands somewhere new | on |
| Grow   | a pane is split; the new pane opens from one cell to its final size along the split axis | on |
| Shrink | a pane is killed through the plugin's key binding; it closes to one cell, then dies | off, see `@motion-kill-bind` |

Flash fades the active pane's border color (and optionally its background)
from a peak color back to your theme's color. When the theme color is a plain
`#rrggbb` the fade is interpolated; when it is a named color or a tmux format
the border simply holds the peak color for the duration.

## Requirements

tmux 3.2 or newer. Tested on 3.4.

## Install

With [tpm](https://github.com/tmux-plugins/tpm), add to `tmux.conf` before the
`run '~/.tmux/plugins/tpm/tpm'` line:

```tmux
set -g @plugin 'el3vilen/tmux-motion'
```

Then `prefix + I` to install.

Manual install:

```tmux
run-shell ~/path/to/tmux-motion/motion.tmux
```

Options are plain `set -g` lines and must come before the plugin loads.

## Options

| Option | Default | Meaning |
| ------ | ------- | ------- |
| `@motion` | `on` | master switch; `off` removes every hook on the next load |
| `@motion-ssh` | `on` | set `off` to disable all effects when the tmux server was started inside an SSH session |
| `@motion-flash` | `on` | flash on focus change |
| `@motion-flash-target` | `border` | `border` (pane-active-border-style fg), `pane` (window-active-style bg) or `both` |
| `@motion-flash-color` | `#ffffff` | peak color of the flash |
| `@motion-flash-intensity` | `100` | how far toward the peak color the flash goes; `30` is a tint, `100` the full color |
| `@motion-flash-border-intensity`, `@motion-flash-pane-intensity` | inherit | per-target override of the intensity |
| `@motion-flash-duration` | `160` | total milliseconds |
| `@motion-flash-steps` | `5` | frames; each frame is one redraw |
| `@motion-grow` | `on` | slide new panes open |
| `@motion-grow-duration` | `180` | milliseconds |
| `@motion-grow-steps` | `8` | frames |
| `@motion-shrink` | `on` | slide panes shut when killed through `@motion-kill-bind` |
| `@motion-shrink-duration` | `180` | milliseconds |
| `@motion-shrink-steps` | `8` | frames |
| `@motion-kill-bind` | unset | prefix key to bind to shrink-then-kill, for example `x` |
| `@motion-kill-confirm` | `on` | wrap the kill binding in tmux's usual `(y/n)` prompt |
| `@motion-hook-index` | `90` | array index the plugin uses for its hooks; raise it if something of yours already lives there |

Example, a Catppuccin Mocha flavored setup:

```tmux
set -g @motion-flash-target both
set -g @motion-flash-color '#cba6f7'
set -g @motion-flash-pane-intensity 30
set -g @motion-kill-bind x
```

## How it works

tmux hooks fire after a command has run, with formats expanded for the pane
the command touched. The plugin installs hooks at a fixed array index
(`after-select-pane[90]` and so on) and each hook starts one small script with
`run-shell -b`, so tmux never waits on an animation.

Flash sets a window-scoped override of `pane-active-border-style` or
`window-active-style` for each frame and unsets it at the end, so your global
or theme value is never modified. If the window already had its own value, that
value is restored instead.

Grow collapses the new pane to one cell inside the hook itself, before tmux
draws the split, so the pane is never shown at full size first. tmux does not
record which way a pane was split, so the hook works it out with formats: the
pane that was split is normally the previously active one, and whether it now
sits beside or above the new pane settles the axis. The background script
then steps `resize-pane` back out to the size the layout gave the pane.
Shrink does the same in reverse before `kill-pane`.

A newer effect on the same window supersedes a running one through a run id
stored in a window option, so hammering a key never leaves a stale color or
size behind. Selecting the pane that is already active (mouse-wheel scrolling
routes through `select-pane`) is ignored.

There is no hook before a pane is killed, which is why shrink only works
through the plugin's own key binding.

## Caveats

- Every frame is a tmux redraw. Over a slow link the frames can read as
  flicker. Shorten the durations, lower the steps or set `@motion-ssh off`.
- Grow and shrink resize the neighbor pane too, so full-screen programs in the
  neighbor (vim, less, htop) receive a burst of resize events. Editors reflow
  a few times during the 180 ms.
- Zoomed windows are left alone.
- Grow assumes the pane being split is the active one, which is what
  `prefix + %` and `prefix + "` do. A `split-window -t` aimed at another pane
  falls back to geometry and can pick the wrong axis in dense layouts.
- Hooks from other plugins or your own config at the same index are
  overwritten. Change `@motion-hook-index` if that happens.

## Uninstall

Set `@motion off` and reload, or remove the `@plugin` line and run
`prefix + alt + u` in tpm. The plugin only ever sets options named `@motion-*`
and hooks at its index; nothing else is left behind.

## Development

`test/smoke.sh` drives a throwaway tmux server (`-L motion-test`) through a
split, a focus change, a kill and a reload, and asserts on the intermediate
sizes and styles. `shellcheck -x -P scripts motion.tmux scripts/*.sh` keeps the
scripts clean.

## License

MIT
