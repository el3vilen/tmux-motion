#!/usr/bin/env bash
# grow.sh PANE
# Slide a freshly split pane open: collapse it to one cell along the split
# axis, then ease it out to the size the layout gave it.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-}
[ -n "$pane" ] || exit 0
tmux display -p -t "$pane" '' >/dev/null 2>&1 || exit 0

motion_on @motion-grow on || exit 0
motion_allowed "$pane" || exit 0
[ "$(tmux display -p -t "$pane" '#{window_zoomed_flag}')" = "0" ] || exit 0

steps="$(motion_get @motion-grow-steps 6)"
duration="$(motion_get @motion-grow-duration 120)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

axis="$(motion_pane_axis "$pane")" || exit 0
case "$axis" in
  x) final="$(tmux display -p -t "$pane" '#{pane_width}')" ;;
  y) final="$(tmux display -p -t "$pane" '#{pane_height}')" ;;
  *) exit 0 ;;
esac
[ "$final" -gt 2 ] || exit 0

run_id="$$.$RANDOM"
tmux set-option -w -t "$pane" @motion-resize-run "$run_id"
guard="#{==:#{@motion-resize-run},$run_id}"

for ((f = 0; f <= steps; f++)); do
  p="$(motion_ease_out $((f * 100 / steps)))"
  size=$((final * p / 100))
  [ "$size" -ge 1 ] || size=1
  tmux if-shell -F -t "$pane" "$guard" "resize-pane -t $pane -$axis $size" 2>/dev/null || exit 0
  [ "$f" -lt "$steps" ] && motion_sleep_ms "$frame_ms"
done
tmux if-shell -F -t "$pane" "$guard" "set-option -wu -t $pane @motion-resize-run" 2>/dev/null
exit 0
