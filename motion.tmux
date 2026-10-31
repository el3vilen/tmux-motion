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
zoom_hooks=(after-resize-pane)
exit_hooks=(pane-died)
# Anything that unzooms behind tmux's back must clear the zoom marker, or the
# next plain resize would look like a zoom out.
reset_hooks=(after-select-layout)

for h in "${flash_hooks[@]}" "${grow_hooks[@]}" "${zoom_hooks[@]}" "${exit_hooks[@]}" "${reset_hooks[@]}"; do
  tmux set-hook -gu "${h}[${INDEX}]" 2>/dev/null
done

# Shrink-on-exit needs remain-on-exit so the dead pane is still there to
# animate. The previous values are kept in @motion options and put back when
# the effect or the plugin is turned off.
restore_remain() {
  local prev
  prev="$(tmux show-option -gqv @motion-remain-prev)"
  if [ -n "$prev" ]; then
    tmux set-option -g remain-on-exit "${prev#value=}"
    tmux set-option -gu @motion-remain-prev
  fi
  prev="$(tmux show-option -gqv @motion-remain-format-prev)"
  if [ -n "$prev" ]; then
    tmux set-option -g remain-on-exit-format "${prev#value=}"
    tmux set-option -gu @motion-remain-format-prev
  fi
}

# Fade on resize. There is no hook before a resize, so the resize keys
# themselves go through fade.sh, which fades first and resizes after. Only
# plain `resize-pane -U|-D|-L|-R [N]` bindings and the default border drag are
# taken over; turning the effect off puts them back as they were.
fade="$(printf '%q' "$DIR/scripts/fade.sh")"
fade_keys() { # on|off
  local line r table key dir n cmd
  local plain='^bind-key +(-r +)?-T +([^ ]+) +([^ \\"'"'"']+) +resize-pane +(-[UDLR])( +([0-9]+))?$'
  local ours='^bind-key +(-r +)?-T +([^ ]+) +([^ \\"'"'"']+) +run-shell +-b +.*fade\.sh resize .* (-[UDLR])( ([0-9]+))?"$'
  while IFS= read -r line; do
    if [[ $line =~ $plain ]] || [[ $line =~ $ours ]]; then
      r=${BASH_REMATCH[1]:+-r} table=${BASH_REMATCH[2]} key=${BASH_REMATCH[3]}
      dir=${BASH_REMATCH[4]} n=${BASH_REMATCH[6]}
      if [ "$1" = on ]; then
        cmd="run-shell -b \"$fade resize '#{client_name}' '#{pane_id}' $dir${n:+ $n}\""
      else
        cmd="resize-pane $dir${n:+ $n}"
      fi
      # shellcheck disable=SC2086  # $r is an optional flag
      tmux bind-key $r -T "$table" "$key" "$cmd"
    fi
  done < <(tmux list-keys -T prefix; tmux list-keys -T root)

  local drag end
  drag="$(tmux list-keys -T root MouseDrag1Border 2>/dev/null)"
  end="$(tmux list-keys -T root MouseDragEnd1Border 2>/dev/null)"
  if [ "$1" = on ]; then
    if [[ $drag =~ MouseDrag1Border\ +resize-pane\ -M$ ]] || [[ $drag == *fade.sh\ out* ]]; then
      tmux bind-key -T root MouseDrag1Border "resize-pane -M ; run-shell -b \"$fade out '#{pane_id}'\""
      [ -z "$end" ] || [[ $end == *fade.sh\ in* ]] &&
        tmux bind-key -T root MouseDragEnd1Border "run-shell -b \"$fade in '#{pane_id}'\""
    fi
  else
    [[ $drag == *fade.sh\ out* ]] && tmux bind-key -T root MouseDrag1Border resize-pane -M
    [[ $end == *fade.sh\ in* ]] && tmux unbind-key -T root MouseDragEnd1Border
  fi
  return 0
}

if ! motion_on @motion on; then
  restore_remain
  fade_keys off
  exit 0
fi

flash="$(printf '%q' "$DIR/scripts/flash.sh")"
kill="$(printf '%q' "$DIR/scripts/kill.sh")"

for h in "${flash_hooks[@]}"; do
  prefix=""
  [ "$h" = after-kill-pane ] && prefix="set-option -w @motion-zoomed 0 ; "
  tmux set-hook -g "${h}[${INDEX}]" "${prefix}run-shell -b \"$flash '#{pane_id}'\""
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
# The spacer takes all but one cell of the new pane, so the neighbor is resized
# once, at the split, and grow.sh only ever trades cells between the new pane
# and the spacer. Panes too small to hold a spacer are left alone.
grow_x="#{?#{e|>:#{pane_width},4},split-window -d -h -t #{pane_id} -l #{e|-:#{pane_width},2} \\\\\\\"$MOTION_SPACER_CMD\\\\\\\" ; run-shell -b \\\\\\\"$DIR/scripts/grow.sh #{pane_id} x #{pane_width}\\\\\\\",if-shell -F 0 x}"
grow_y="#{?#{e|>:#{pane_height},4},split-window -d -v -t #{pane_id} -l #{e|-:#{pane_height},2} \\\\\\\"$MOTION_SPACER_CMD\\\\\\\" ; run-shell -b \\\\\\\"$DIR/scripts/grow.sh #{pane_id} y #{pane_height}\\\\\\\",if-shell -F 0 x}"
cond='#{&&:#{==:#{window_zoomed_flag},0},#{!=:#{@motion-grow},off}}'
for h in "${grow_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" \
    "set-option -w @motion-zoomed 0 ; if-shell -F '$cond' \"run-shell -C 'if-shell -F \\\"$is_x\\\" \\\"$grow_x\\\" \\\"$grow_y\\\"'\""
done

# Zoom. resize-pane -Z fires after-resize-pane with the zoom already applied,
# so the hook undoes it synchronously (commands run from a hook do not fire
# hooks themselves) and lets zoom.sh grow the pane into the zoom. Zoom out
# runs the other way: push the pane to the window size before the first draw,
# shrink it, then put the restored layout back. @motion-zoomed remembers the
# last state so ordinary resizes are told apart from zoom changes.
cond_in='#{&&:#{window_zoomed_flag},#{!=:#{@motion-zoomed},1}}'
cond_out='#{&&:#{==:#{window_zoomed_flag},0},#{==:#{@motion-zoomed},1}}'
cmd_in="set-option -w @motion-zoomed 1 ; set-option -w @motion-zoom-run hook ; resize-pane -Z -t #{pane_id} ; run-shell -b \\\"$DIR/scripts/zoom.sh #{pane_id} in\\\""
cmd_out="set-option -w @motion-zoomed 0 ; set-option -w @motion-zoom-run hook ; set-option -w @motion-zoom-layout \\\"#{window_layout}\\\" ; resize-pane -t #{pane_id} -x #{window_width} -y #{window_height} ; run-shell -b \\\"$DIR/scripts/zoom.sh #{pane_id} out #{pane_width} #{pane_height}\\\""
zoom_guard='#{&&:#{!=:#{@motion-zoom},off},#{==:#{@motion-zoom-run},}}'
for h in "${zoom_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" \
    "if-shell -F '$zoom_guard' \"run-shell -C '#{?$cond_in,$cmd_in,#{?$cond_out,$cmd_out,if-shell -F 0 x}}'\""
done
for h in "${reset_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" "set-option -w @motion-zoomed 0"
done

# Shrink on exit: a pane whose process ended stays as a dead pane just long
# enough to slide shut.
if motion_on @motion-exit on; then
  if [ -z "$(tmux show-option -gqv @motion-remain-prev)" ]; then
    tmux set-option -g @motion-remain-prev "value=$(tmux show-option -gv remain-on-exit)"
    tmux set-option -g @motion-remain-format-prev "value=$(tmux show-option -gv remain-on-exit-format)"
  fi
  tmux set-option -g remain-on-exit on
  tmux set-option -g remain-on-exit-format ''
  # Same two-pass trick as grow: pick the axis from where the neighbors are,
  # split a one-cell spacer off the dead pane inside the hook, then let
  # kill.sh slide the pane into it.
  shrink_x="#{?#{e|>:#{pane_width},3},split-window -d -h -t #{pane_id} -l 1 \\\\\\\"$MOTION_SPACER_CMD\\\\\\\" ; ,}run-shell -b \\\\\\\"$DIR/scripts/kill.sh #{pane_id} x\\\\\\\""
  shrink_y="#{?#{e|>:#{pane_height},3},split-window -d -v -t #{pane_id} -l 1 \\\\\\\"$MOTION_SPACER_CMD\\\\\\\" ; ,}run-shell -b \\\\\\\"$DIR/scripts/kill.sh #{pane_id} y\\\\\\\""
  is_beside="##{?##{==:#{&&:#{pane_at_top},#{pane_at_bottom}},1},1,##{?##{==:#{&&:#{pane_at_left},#{pane_at_right}},1},0,##{?$any_beside,1,0}}}"
  exit_cond='#{&&:#{==:#{window_zoomed_flag},0},#{!=:#{@motion-shrink},off}}'
  for h in "${exit_hooks[@]}"; do
    tmux set-hook -g "${h}[${INDEX}]" \
      "if-shell -F '$exit_cond' \"run-shell -C 'if-shell -F \\\"$is_beside\\\" \\\"$shrink_x\\\" \\\"$shrink_y\\\"'\" \"run-shell -b '$kill #{pane_id}'\""
  done
else
  restore_remain
fi

if motion_on @motion-fade on; then
  fade_keys on
else
  fade_keys off
fi

key="$(motion_get @motion-kill-bind '')"
if [ -n "$key" ]; then
  if motion_on @motion-kill-confirm on; then
    tmux bind-key "$key" confirm-before -p 'kill-pane #P? (y/n)' \
      "run-shell -b \"$kill '#{pane_id}'\""
  else
    tmux bind-key "$key" run-shell -b "$kill '#{pane_id}'"
  fi
fi
