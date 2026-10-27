#!/usr/bin/env bash
# kill.sh PANE
# Slide a pane shut along its split axis, then kill it. Bound to a key through
# @motion-kill-bind, because tmux has no hook that fires before a kill.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-}
[ -n "$pane" ] || exit 0
tmux display -p -t "$pane" '' >/dev/null 2>&1 || exit 0

finish() {
  tmux kill-pane -t "$pane"
  exit 0
}

motion_on @motion-shrink on || finish
motion_allowed "$pane" || finish
[ "$(tmux display -p -t "$pane" '#{window_zoomed_flag}')" = "0" ] || finish
[ "$(tmux display -p -t "$pane" '#{window_panes}')" -gt 1 ] || finish

steps="$(motion_get @motion-shrink-steps 8)"
duration="$(motion_get @motion-shrink-duration 180)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

axis="$(motion_pane_axis "$pane")" || finish
case "$axis" in
  x) start="$(tmux display -p -t "$pane" '#{pane_width}')" ;;
  y) start="$(tmux display -p -t "$pane" '#{pane_height}')" ;;
  *) finish ;;
esac
[ "$start" -gt 2 ] || finish

# Take over the window's resize slot so a grow still running on a sibling
# stops fighting us.
tmux set-option -w -t "$pane" @motion-resize-run "kill.$$"

for ((f = 1; f < steps; f++)); do
  p="$(motion_ease_in $((f * 100 / steps)))"
  size=$((start - start * p / 100))
  [ "$size" -ge 1 ] || size=1
  tmux resize-pane -t "$pane" "-$axis" "$size" 2>/dev/null || finish
  motion_sleep_ms "$frame_ms"
done
tmux set-option -wu -t "$pane" @motion-resize-run 2>/dev/null
finish
