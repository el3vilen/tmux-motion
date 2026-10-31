#!/usr/bin/env bash
# flash.sh PANE
# Pulse the active pane's border and/or background, then fade back to the
# configured style. Runs in the background from a hook; a newer flash on the
# same window supersedes a running one through the @motion-flash-run id.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pane=${1:-}
if [ -z "$pane" ] || ! tmux display -p -t "$pane" '' >/dev/null 2>&1; then
  pane="$(tmux display -p '#{pane_id}')" || exit 0
fi

motion_on @motion-flash on || exit 0
motion_allowed "$pane" || exit 0
# A resize fade owns the styles while it runs and flashes on its own.
[ -z "$(tmux show-option -wqv -t "$pane" @motion-fade-run)" ] || exit 0

# A select-pane on the pane that is already active (mouse wheel scrolling
# routes through select-pane, so does hammering the same direction key) is
# not a transition. Only flash when focus actually moved.
last="$(tmux show-option -gqv @motion-last-pane)"
[ "$last" = "$pane" ] && exit 0
tmux set-option -g @motion-last-pane "$pane"

target="$(motion_get @motion-flash-target border)"
color="$(motion_get @motion-flash-color '#ffffff')"
steps="$(motion_get @motion-flash-steps 5)"
duration="$(motion_get @motion-flash-duration 160)"
[ "$steps" -ge 1 ] 2>/dev/null || steps=1
frame_ms=$((duration / steps))

opts=() attrs=() names=()
case "$target" in
  border) opts=(pane-active-border-style); attrs=(fg); names=(border) ;;
  pane)   opts=(window-active-style);      attrs=(bg); names=(pane) ;;
  both)   opts=(pane-active-border-style window-active-style); attrs=(fg bg); names=(border pane) ;;
  *) exit 0 ;;
esac

# Intensity scales the peak toward the resting color: 100 flashes the full
# color, 30 is a tint. A per-target value wins over the shared one.
intensity="$(motion_get @motion-flash-intensity 100)"

run_id="$$.$RANDOM"
tmux set-option -w -t "$pane" @motion-flash-run "$run_id"

# Remember what the window had before any flash touched it. An in-flight
# flash has already saved it, so never overwrite the saved value.
bases=() saved=()
for i in "${!opts[@]}"; do
  opt=${opts[$i]}
  s="$(tmux show-option -wqv -t "$pane" "@motion-orig-$opt")"
  if [ -z "$s" ]; then
    s="$(tmux show-option -wqv -t "$pane" "$opt")"
    s=${s:-__unset__}
    tmux set-option -w -t "$pane" "@motion-orig-$opt" "$s"
  fi
  saved[i]=$s
  if [ "$s" = "__unset__" ]; then
    bases[i]="$(tmux show-option -gqv "$opt")"
  else
    bases[i]=$s
  fi
done

# Only act while this run is still the newest one for the window. The check
# lives inside tmux so each frame is a single round trip. Styles never hold a
# single quote, so tmux's own quoting carries them through if-shell safely.
guard="#{==:#{@motion-flash-run},$run_id}"

for ((f = 0; f < steps; f++)); do
  p=$((f * 100 / steps))
  p="$(motion_ease_out "$p")"
  cmd=""
  for i in "${!opts[@]}"; do
    base_attr="$(motion_style_get "${bases[$i]}" "${attrs[$i]}")"
    if motion_is_hex "$color" && motion_is_hex "$base_attr"; then
      level="$(motion_get "@motion-flash-${names[$i]}-intensity" "$intensity")"
      peak="$(motion_mix "$base_attr" "$color" "$level")"
      c="$(motion_mix "$peak" "$base_attr" "$p")"
    else
      c=$color
    fi
    style="$(motion_style_set "${bases[$i]}" "${attrs[$i]}" "$c")"
    cmd+="${cmd:+ ; }set-option -w -t '$pane' '${opts[$i]}' '$style'"
  done
  tmux if-shell -F -t "$pane" "$guard" "$cmd" 2>/dev/null || exit 0
  motion_sleep_ms "$frame_ms"
done

# Restore. A window-level value goes back as it was; an inherited one is
# unset so the global or theme value shows through again.
cmd=""
for i in "${!opts[@]}"; do
  if [ "${saved[$i]}" = "__unset__" ]; then
    cmd+="${cmd:+ ; }set-option -wu -t '$pane' '${opts[$i]}'"
  else
    cmd+="${cmd:+ ; }set-option -w -t '$pane' '${opts[$i]}' '${saved[$i]}'"
  fi
  cmd+=" ; set-option -wu -t '$pane' '@motion-orig-${opts[$i]}'"
done
cmd+=" ; set-option -wu -t '$pane' @motion-flash-run"
tmux if-shell -F -t "$pane" "$guard" "$cmd" 2>/dev/null
exit 0
