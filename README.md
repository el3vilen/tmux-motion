# tmux-motion

Small transitions for tmux. The active pane pulses when focus moves, new
panes slide open, closed panes slide shut, and zoom grows into place instead
of snapping. Resizing a pane fades the window out and back in, so text
re-wrapping is hidden. Pure shell, one `@plugin` line, no dependencies beyond tmux
itself.

tmux has no animation engine and redraws only when state changes, so these are
short stepped effects (a handful of frames inside 140 to 180 ms), not smooth
60 fps motion. They are meant to be felt as a hint of movement, not watched.

## Effects

| Effect | Trigger | Default |
| ------ | ------- | ------- |
| Flash  | focus moves to another pane, window or session; a pane or window is killed and focus lands somewhere new | on |
| Grow   | a pane is split; the new pane opens from one cell to its final size along the split axis | on |
| Shrink | a pane's process exits (`exit`, `Ctrl-D`), or it is killed through the plugin's key binding; it closes to one cell, then goes | on; the key binding is opt-in, see `@motion-kill-bind` |
| Zoom   | `resize-pane -Z` in either direction; the pane grows into the zoom or shrinks back into the layout | on |
| Fade   | a resize key (`prefix + M-Arrow`, `prefix + C-Arrow`, anything bound to plain `resize-pane -U/-D/-L/-R`) or a border drag with the mouse; the window fades out, resizes, and sweeps back in the direction the border moved, pane by pane, with a flash on the active pane | on |

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
| `@motion-grow-duration` | `140` | milliseconds |
| `@motion-grow-steps` | `7` | frames |
| `@motion-shrink` | `on` | slide panes shut on exit and through `@motion-kill-bind` |
| `@motion-exit` | `on` | animate panes whose process exited; turns on `remain-on-exit` and blanks `remain-on-exit-format` while active, and restores both when turned off |
| `@motion-shrink-duration` | `140` | milliseconds |
| `@motion-shrink-steps` | `7` | frames |
| `@motion-zoom` | `on` | animate zoom in and out |
| `@motion-zoom-duration` | `120` | milliseconds |
| `@motion-zoom-steps` | `3` | frames; every frame reflows every pane, so keep this low |
| `@motion-fade` | `on` | fade on resize; takes over the resize key bindings and the border drag, and gives them back when `off` |
| `@motion-fade-bg` | unset | your terminal's background as `#rrggbb`; styles that say `default` or `terminal` fade toward it, and the curtain uses it. Without it, those styles are left alone |
| `@motion-fade-fg` | unset | your terminal's default text color as `#rrggbb`, so a `fg=terminal` style can be blended instead of switched |
| `@motion-fade-curtain` | `on` | cover the window with a borderless popup while the resized programs redraw (keyboard resizes only) |
| `@motion-fade-hold` | `30` | milliseconds the curtain stays up before the sweep starts |
| `@motion-fade-out-duration`, `@motion-fade-out-steps` | `20`, `2` | fade out, before the resize |
| `@motion-fade-in-duration`, `@motion-fade-in-steps` | `90`, `6` | sweep and fade back in, with the flash |
| `@motion-fade-sweep` | `50` | share of the fade-in, in percent, the sweep takes to cross the window; each pane fades over the rest. `0` fades every pane at once |
| `@motion-fade-drag-timeout` | `10000` | milliseconds a dragged-out fade waits for the drag to end before it fades back in anyway |
| `@motion-kill-bind` | unset | prefix key to bind to shrink-then-kill, for example `x` |
| `@motion-kill-confirm` | `on` | wrap the kill binding in tmux's usual `(y/n)` prompt |
| `@motion-hook-index` | `90` | array index the plugin uses for its hooks; raise it if something of yours already lives there |

Example, a Catppuccin Mocha flavored setup:

```tmux
set -g @motion-flash-target both
set -g @motion-flash-color '#cba6f7'
set -g @motion-flash-pane-intensity 30
set -g @motion-fade-bg '#1e1e2e'
set -g @motion-fade-fg '#cdd6f4'
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

Grow and shrink never resize the real neighbor more than once. Resizing a
pane makes tmux re-wrap its lines and makes the program inside redraw, and
doing that seven times in a row is what a jittery slide looks like. So the
hook splits a throwaway spacer pane off the new pane, inside the hook itself
and before tmux draws the split (commands run from a hook fire no hooks, so
your own `after-split-window` hooks never see it). The neighbor gets its final
size at the split, exactly as it would without the plugin, and the new pane
then grows into the spacer one frame at a time. Killing the spacer at the end
hands over the last cells in a single redraw. Shrink runs the same way in
reverse: the pane slides into a spacer and both are killed together, so the
neighbor expands once.

tmux does not record which way a pane was split, so the hook works it out
with formats: the pane that was split is normally the previously active one,
and whether it now sits beside or above the new pane settles the axis.

A newer effect on the same window supersedes a running one through a run id
stored in a window option, so hammering a key never leaves a stale color or
size behind. Selecting the pane that is already active (mouse-wheel scrolling
routes through `select-pane`) is ignored.

Shrink on exit relies on `remain-on-exit`: the dead pane stays just long
enough to slide shut, with its "Pane is dead" banner blanked, and the plugin
kills it at the end. There is no hook before `kill-pane`, which is why killing
a live pane only animates through the plugin's own key binding. That path
runs from a script rather than a hook, so it parks the spacer split in a
one-shot hook and trips it with a silent `display-message`, which keeps your
own split hooks out of it. A spacer that somehow outlives its animation exits
on its own after 30 seconds and is removed.

Zoom cannot use a spacer: the zoomed pane itself is what changes size, and
every other pane has to give up room, so each frame reflows them all. That is
why zoom defaults to three frames, a quick snap with a hint of motion, and
why `@motion-zoom-steps 1` is the honest setting for a terminal that shows
the jitter. Zoom works around the fact that `resize-pane -Z` has already zoomed by the
time its hook runs. Commands run from a hook do not fire hooks themselves, so
the hook unzooms synchronously, before tmux draws, and the script grows the
pane toward the window size, then restores the saved layout and zooms for real
in one tmux call so the hand-over is a single redraw. Zoom out is the reverse:
the hook pushes the pane to the window size before the first draw, the script
shrinks it, and the restored layout is applied at the end.

Fade has no hook to start from either: tmux only has hooks after a resize,
and by then the panes have the new size. So the plugin rebinds the resize
keys to run `fade.sh`, which steps the text color of `window-style` and
`window-active-style` and both border styles down to the background, then
resizes. The resize and a borderless popup the size of the window go out in
one command list, so tmux draws the popup before the resized panes. The
programs inside redraw under it.

The way back in follows the border: pushed left, the window is uncovered
from the right edge toward the left; pushed up, from the bottom up. Each
frame closes the popup and reopens it over the part the sweep has not
reached, in one command list, so the curtain retreats without a gap. Each
pane fades in through pane-level `window-style` overrides, starting when the
sweep reaches its leading edge, and the active pane flashes on its turn: its
border starts at the flash color and its background starts tinted. A border
drag fades out when the drag starts (`MouseDrag1Border`) and sweeps back in
the direction the mouse moved when it ends (`MouseDragEnd1Border`), without
the curtain, since a popup would take the drag over. Panes that carry their
own pane-level style (`select-pane -P`) are left out of the sweep.

## Caveats

- tmux styles only recolor text drawn in the default color. Text a program
  colors itself (an editor, a colored prompt, `ls` colors) does not fade; for
  keyboard resizes the curtain hides it while it reflows, during a mouse drag
  it stays visible.
- Keys pressed while the fade curtain is up (about 75 ms) go to the popup
  and are dropped. A held resize key repeats more slowly than without the plugin.
- Fade rebinds only plain `resize-pane -U/-D/-L/-R [N]` and the default
  `MouseDrag1Border` binding. A resize bound together with other commands,
  or with `-x`/`-y`, is not touched.

- Every frame is a tmux redraw. Over a slow link the frames can read as
  flicker. Shorten the durations, lower the steps or set `@motion-ssh off`.
- The pane being animated is resized every frame. For grow that is a fresh
  shell and for shrink a pane on its way out, so it rarely matters, but a
  prompt printed while the pane is a few cells wide wraps until the pane
  reaches full width. Zoom resizes a live program and shows it.
- For the length of a grow or shrink the window holds one extra pane, the
  spacer, running `sleep`. Anything that counts or lists panes sees it.
- Zoomed windows are left alone.
- Grow assumes the pane being split is the active one, which is what
  `prefix + %` and `prefix + "` do. A `split-window -t` aimed at another pane
  falls back to geometry and can pick the wrong axis in dense layouts.
- `@motion-exit` sets `remain-on-exit on` globally. Anything else that relies
  on it being off, or that reads dead panes, sees them for the duration of the
  animation. Set `@motion-exit off` to leave the option alone.
- Hooks from other plugins or your own config at the same index are
  overwritten. Change `@motion-hook-index` if that happens.

## Uninstall

Set `@motion off` and reload, or remove the `@plugin` line and run
`prefix + alt + u` in tpm. The plugin only ever sets options named `@motion-*`
and hooks at its index; nothing else is left behind.

## Development

`test/smoke.sh` drives a throwaway tmux server (`-L motion-test`) through a
split, a focus change, a kill, a resize fade and a reload, and asserts on the intermediate
sizes and styles. `shellcheck -x -P scripts motion.tmux scripts/*.sh` keeps the
scripts clean.

## License

MIT
