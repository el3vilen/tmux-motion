#!/usr/bin/env bash
# zoom.sh PANE in
#   The hook has already unzoomed the pane again, before tmux drew the zoom.
#   Grow it toward the window size, then restore the saved layout and zoom for
#   real in one tmux call, so the hand-over is a single redraw.
# zoom.sh PANE out WIDTH HEIGHT
#   The hook has already pushed the pane to the window size. Shrink it toward
#   WIDTHxHEIGHT, the size the restored layout gives it, then apply that layout.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-} mode=${2:-}
[ -n "$pane" ] || exit 0
tmux display -p -t "$pane" '' >/dev/null 2>&1 || exit 0

run_id="$$.$RANDOM"
tmux set-option -w -t "$pane" @motion-zoom-run "$run_id"
guard="#{==:#{@motion-zoom-run},$run_id}"
release="set-option -wu -t $pane @motion-zoom-run ; set-option -wu -t $pane @motion-zoom-layout"

steps="$(motion_get @motion-zoom-steps 3)"
duration="$(motion_get @motion-zoom-duration 120)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

read -r W H < <(tmux display -p -t "$pane" '#{window_width} #{window_height}')

case "$mode" in
  in)
    if ! motion_allowed "$pane"; then
      tmux resize-pane -Z -t "$pane" \; set-option -wu -t "$pane" @motion-zoom-run
      exit 0
    fi
    layout="$(tmux display -p -t "$pane" '#{window_layout}')"
    read -r from_w from_h < <(tmux display -p -t "$pane" '#{pane_width} #{pane_height}')
    to_w=$W to_h=$H
    # select-layout fires the marker-reset hook, so the marker is set again after it.
    finish="select-layout -t $pane '$layout' ; resize-pane -Z -t $pane ; set-option -w -t $pane @motion-zoomed 1 ; $release"
    ;;
  out)
    layout="$(tmux show-option -wqv -t "$pane" @motion-zoom-layout)"
    to_w=${3:-} to_h=${4:-}
    if [ -z "$layout" ] || [ -z "$to_w" ] || [ -z "$to_h" ] || ! motion_allowed "$pane"; then
      [ -n "$layout" ] && tmux select-layout -t "$pane" "$layout"
      tmux set-option -wu -t "$pane" @motion-zoom-run \; set-option -wu -t "$pane" @motion-zoom-layout
      exit 0
    fi
    read -r from_w from_h < <(tmux display -p -t "$pane" '#{pane_width} #{pane_height}')
    finish="select-layout -t $pane '$layout' ; $release"
    ;;
  *) exit 0 ;;
esac

for ((f = 1; f < steps; f++)); do
  p="$(motion_ease_out $((f * 100 / steps)))"
  w=$((from_w + (to_w - from_w) * p / 100))
  h=$((from_h + (to_h - from_h) * p / 100))
  [ "$w" -ge 1 ] || w=1
  [ "$h" -ge 1 ] || h=1
  tmux if-shell -F -t "$pane" "$guard" "resize-pane -t $pane -x $w -y $h" 2>/dev/null || exit 0
  motion_sleep_ms "$frame_ms"
done
tmux if-shell -F -t "$pane" "$guard" "$finish" 2>/dev/null
exit 0
