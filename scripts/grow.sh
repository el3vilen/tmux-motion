#!/usr/bin/env bash
# grow.sh PANE AXIS FINAL
# Slide a freshly split pane open. The hook in motion.tmux has already split a
# spacer off the new pane, synchronously, so the pane starts one cell wide and
# the spacer holds the rest: the real neighbor got its final size at the split
# and is never touched again. This eases the pane out into the spacer along
# AXIS (x or y) and kills the spacer at the end, which hands the last cells
# over in a single redraw.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-} axis=${2:-} final=${3:-}
[ -n "$pane" ] && [ -n "$final" ] || exit 0
case "$axis" in x|y) ;; *) exit 0 ;; esac
tmux display -p -t "$pane" '' >/dev/null 2>&1 || exit 0

spacer="$(motion_find_spacer "$pane" "$axis")" || exit 0
if ! motion_allowed "$pane"; then
  tmux kill-pane -t "$spacer"
  exit 0
fi

steps="$(motion_get @motion-grow-steps 7)"
duration="$(motion_get @motion-grow-duration 140)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

# The pane plus the border plus the spacer add up to FINAL, so the spacer can
# only shrink to one cell and the pane grows to FINAL - 2 before the hand-over.
reach=$((final - 2))
[ "$reach" -ge 2 ] || { tmux kill-pane -t "$spacer"; exit 0; }

run_id="$$.$RANDOM"
tmux set-option -w -t "$pane" @motion-resize-run "$run_id"
guard="#{==:#{@motion-resize-run},$run_id}"

for ((f = 1; f < steps; f++)); do
  p="$(motion_ease_out $((f * 100 / steps)))"
  size=$((1 + (reach - 1) * p / 100))
  tmux if-shell -F -t "$pane" "$guard" "resize-pane -t $pane -$axis $size" 2>/dev/null || break
  motion_sleep_ms "$frame_ms"
done
tmux kill-pane -t "$spacer" 2>/dev/null
tmux set-option -wu -t "$pane" @motion-resize-run 2>/dev/null
exit 0
