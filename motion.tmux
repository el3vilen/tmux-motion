#!/usr/bin/env bash
# tmux-motion: small transitions for pane and window changes.
# Entry point for tpm. Safe to run repeatedly: every hook lives at a fixed
# index, so a reload replaces rather than duplicates.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$DIR/scripts/helpers.sh"

INDEX="$(motion_get @motion-hook-index 90)"

flash_hooks=(
  after-select-pane
  after-kill-pane
  session-window-changed
  client-session-changed
)
grow_hooks=(after-split-window)

for h in "${flash_hooks[@]}" "${grow_hooks[@]}"; do
  tmux set-hook -gu "${h}[${INDEX}]" 2>/dev/null
done

motion_on @motion on || exit 0

flash="$(printf '%q' "$DIR/scripts/flash.sh")"
kill="$(printf '%q' "$DIR/scripts/kill.sh")"

for h in "${flash_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" "run-shell -b \"$flash '#{pane_id}'\""
done
# Grow collapses the new pane inside the hook itself, before tmux draws the
# split, so the pane never shows at full size first. That means the split axis
# must be decided by tmux formats rather than by a script. Two expansion
# passes do it: run-shell -C expands the hook once, baking the new pane's
# geometry into literals (plain #{...}), then the if-shell -F it produces
# expands again (the ##{...} forms) and loops over the window's panes to find
# where the pane that was split sits relative to the new one. Beside it: a
# left/right split, animate width. Above or below: animate height.
# Phase-two predicates over the looped pane, with the new pane's geometry baked in.
beside="##{&&:##{==:##{pane_top},#{pane_top}},##{&&:##{==:##{pane_height},#{pane_height}},##{||:##{==:##{pane_left},#{e|+:#{e|+:#{pane_left},#{pane_width}},1}},##{==:##{e|+:##{e|+:##{pane_left},##{pane_width}},1},#{pane_left}}}}}"
stacked="##{&&:##{==:##{pane_left},#{pane_left}},##{&&:##{==:##{pane_width},#{pane_width}},##{||:##{==:##{pane_top},#{e|+:#{e|+:#{pane_top},#{pane_height}},1}},##{==:##{e|+:##{e|+:##{pane_top},##{pane_height}},1},#{pane_top}}}}}"
# The pane that was split is normally the previously active one (pane_last),
# so its position relative to the new pane settles the axis. Only when that
# says nothing does any beside pane count, and a pane spanning the full
# window height or width is unambiguous either way.
last_beside="##{!=:##{P:##{?##{&&:##{pane_last},$beside},x,}},}"
last_stacked="##{!=:##{P:##{?##{&&:##{pane_last},$stacked},y,}},}"
any_beside="##{!=:##{P:##{?$beside,x,}},}"
is_x="##{?##{==:#{&&:#{pane_at_top},#{pane_at_bottom}},1},1,##{?##{==:#{&&:#{pane_at_left},#{pane_at_right}},1},0,##{?$last_beside,1,##{?$last_stacked,0,##{?$any_beside,1,0}}}}}"
grow_x="resize-pane -t #{pane_id} -x 1 ; run-shell -b \\\\\\\"$DIR/scripts/grow.sh #{pane_id} x #{pane_width}\\\\\\\""
grow_y="resize-pane -t #{pane_id} -y 1 ; run-shell -b \\\\\\\"$DIR/scripts/grow.sh #{pane_id} y #{pane_height}\\\\\\\""
cond='#{&&:#{==:#{window_zoomed_flag},0},#{!=:#{@motion-grow},off}}'
for h in "${grow_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" \
    "if-shell -F '$cond' \"run-shell -C 'if-shell -F \\\"$is_x\\\" \\\"$grow_x\\\" \\\"$grow_y\\\"'\""
done

key="$(motion_get @motion-kill-bind '')"
if [ -n "$key" ]; then
  if motion_on @motion-kill-confirm on; then
    tmux bind-key "$key" confirm-before -p 'kill-pane #P? (y/n)' \
      "run-shell -b \"$kill '#{pane_id}'\""
  else
    tmux bind-key "$key" run-shell -b "$kill '#{pane_id}'"
  fi
fi
