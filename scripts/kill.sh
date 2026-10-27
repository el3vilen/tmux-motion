#!/usr/bin/env bash
# kill.sh PANE [AXIS]
# Slide a pane shut, then kill it. A spacer is split off the pane first so
# the space the pane gives up goes to the spacer, not to the real neighbor,
# which grows exactly once when both are killed at the end. The pane-died
# hook makes the spacer itself; the key binding leaves it to this script.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-} axis=${2:-}
[ -n "$pane" ] || exit 0
tmux display -p -t "$pane" '' >/dev/null 2>&1 || exit 0

# A spacer that outlived its animation just goes.
if motion_is_spacer "$pane"; then
  tmux kill-pane -t "$pane"
  exit 0
fi

spacer=""
finish() {
  if [ -n "$spacer" ]; then
    tmux kill-pane -t "$pane" \; kill-pane -t "$spacer" 2>/dev/null
  else
    tmux kill-pane -t "$pane"
  fi
  exit 0
}

if [ -z "$axis" ]; then
  axis="$(motion_pane_axis "$pane")" || axis=x
fi
spacer="$(motion_find_spacer "$pane" "$axis")" || spacer=""

motion_on @motion-shrink on || finish
motion_allowed "$pane" || finish
[ "$(tmux display -p -t "$pane" '#{window_zoomed_flag}')" = "0" ] || finish

case "$axis" in
  x) start="$(tmux display -p -t "$pane" '#{pane_width}')"; flag=-h ;;
  y) start="$(tmux display -p -t "$pane" '#{pane_height}')"; flag=-v ;;
  *) finish ;;
esac
[ "$start" -gt 3 ] || finish

if [ -z "$spacer" ]; then
  motion_hookfree "$pane" "split-window -d $flag -t $pane -l 1 '$MOTION_SPACER_CMD'"
  spacer="$(motion_find_spacer "$pane" "$axis")" || finish
  start=$((start - 2))
fi

steps="$(motion_get @motion-shrink-steps 7)"
duration="$(motion_get @motion-shrink-duration 140)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

# Take over the window's resize slot so a grow still running on a sibling
# stops fighting us.
tmux set-option -w -t "$pane" @motion-resize-run "kill.$$"

for ((f = 1; f < steps; f++)); do
  p="$(motion_ease_out $((f * 100 / steps)))"
  size=$((start - (start - 1) * p / 100))
  [ "$size" -ge 1 ] || size=1
  tmux resize-pane -t "$pane" "-$axis" "$size" 2>/dev/null || finish
  motion_sleep_ms "$frame_ms"
done
tmux set-option -wu -t "$pane" @motion-resize-run 2>/dev/null
finish
