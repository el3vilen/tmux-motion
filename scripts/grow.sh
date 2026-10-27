#!/usr/bin/env bash
# grow.sh PANE AXIS FINAL
# Ease a freshly split pane from one cell out to FINAL along AXIS (x or y).
# The hook in motion.tmux has already collapsed the pane synchronously; this
# only plays the frames.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-} axis=${2:-} final=${3:-}
[ -n "$pane" ] && [ -n "$final" ] || exit 0
case "$axis" in x|y) ;; *) exit 0 ;; esac
tmux display -p -t "$pane" '' >/dev/null 2>&1 || exit 0
motion_allowed "$pane" || exit 0
[ "$final" -gt 2 ] 2>/dev/null || exit 0

steps="$(motion_get @motion-grow-steps 6)"
duration="$(motion_get @motion-grow-duration 120)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

run_id="$$.$RANDOM"
tmux set-option -w -t "$pane" @motion-resize-run "$run_id"
guard="#{==:#{@motion-resize-run},$run_id}"

for ((f = 1; f <= steps; f++)); do
  p="$(motion_ease_out $((f * 100 / steps)))"
  size=$((final * p / 100))
  [ "$size" -ge 1 ] || size=1
  tmux if-shell -F -t "$pane" "$guard" "resize-pane -t $pane -$axis $size" 2>/dev/null || exit 0
  [ "$f" -lt "$steps" ] && motion_sleep_ms "$frame_ms"
done
tmux if-shell -F -t "$pane" "$guard" "set-option -wu -t $pane @motion-resize-run" 2>/dev/null
exit 0
