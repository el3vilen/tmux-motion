#!/usr/bin/env bash
# Shared helpers for tmux-motion. Sourced, never executed.

# Read a user option (@motion-*) from the global scope, with a default.
motion_get() {
  local v
  v="$(tmux show-option -gqv "$1")"
  printf '%s' "${v:-$2}"
}

# True when the named @motion-* option is "on" (or unset and the default is on).
motion_on() {
  [ "$(motion_get "$1" "$2")" = "on" ]
}

# Global kill switch plus an opt-out for servers reached over SSH, where a
# slow link can turn the frames into visible flicker (@motion-ssh off).
motion_allowed() {
  motion_on @motion on || return 1
  if ! motion_on @motion-ssh on; then
    local ssh
    ssh="$(tmux show-environment -g SSH_CONNECTION 2>/dev/null)"
    case "$ssh" in
      SSH_CONNECTION=?*) return 1 ;;
    esac
    ssh="$(tmux show-environment -t "${1:-}" SSH_CONNECTION 2>/dev/null)"
    case "$ssh" in
      SSH_CONNECTION=?*) return 1 ;;
    esac
  fi
  return 0
}

# sleep for N milliseconds without forking anything but sleep itself.
motion_sleep_ms() {
  local ms=$1 s
  [ "$ms" -gt 0 ] || return 0
  printf -v s '%d.%03d' $((ms / 1000)) $((ms % 1000))
  sleep "$s"
}

motion_is_hex() {
  [[ $1 =~ ^#[0-9a-fA-F]{6}$ ]]
}

# motion_mix FROM TO PERCENT -> "#rrggbb" that is PERCENT of the way from FROM to TO.
motion_mix() {
  local f=${1#\#} t=${2#\#} p=$3
  local fr=$((16#${f:0:2})) fg=$((16#${f:2:2})) fb=$((16#${f:4:2}))
  local tr=$((16#${t:0:2})) tg=$((16#${t:2:2})) tb=$((16#${t:4:2}))
  printf '#%02x%02x%02x' \
    $(( (fr * (100 - p) + tr * p) / 100 )) \
    $(( (fg * (100 - p) + tg * p) / 100 )) \
    $(( (fb * (100 - p) + tb * p) / 100 ))
}

# Ease-out: PERCENT in 0..100 -> eased 0..100. Fast start, slow finish.
motion_ease_out() {
  local x=$((100 - $1))
  printf '%d' $((100 - x * x / 100))
}

# Ease-in: the mirror image. Slow start, fast finish.
motion_ease_in() {
  printf '%d' $(($1 * $1 / 100))
}

# motion_style_get STYLE KEY -> the value of "KEY=" inside a comma separated
# tmux style, or nothing when the key is absent.
motion_style_get() {
  local part
  local IFS=,
  for part in $1; do
    if [[ $part == "$2="* ]]; then
      printf '%s' "${part#*=}"
      return 0
    fi
  done
  return 1
}

# motion_style_set STYLE KEY VALUE -> STYLE with "KEY=VALUE" replaced or appended.
# A style that embeds a format (#{...}) cannot be split safely, so it is
# replaced wholesale for the duration of the animation.
motion_style_set() {
  if [[ $1 == *'#{'* ]]; then
    printf '%s=%s' "$2" "$3"
    return 0
  fi
  local part found=0 out=()
  local IFS=,
  for part in $1; do
    if [[ $part == "$2="* ]]; then
      out+=("$2=$3")
      found=1
    elif [ -n "$part" ]; then
      out+=("$part")
    fi
  done
  [ $found -eq 1 ] || out+=("$2=$3")
  printf '%s' "${out[*]}"
}

# motion_pane_axis PANE -> "x" when the pane sits beside a sibling (it came from
# a left/right split), "y" when it sits above or below one, nothing when the
# pane fills the window. Decided from geometry, since tmux does not record the
# split direction anywhere.
motion_pane_axis() {
  local pane=$1 id l t w h
  local pl pt pw ph
  read -r pl pt pw ph < <(tmux display -p -t "$pane" '#{pane_left} #{pane_top} #{pane_width} #{pane_height}')
  while read -r id l t w h; do
    [ "$id" = "$pane" ] && continue
    if [ "$t" = "$pt" ] && [ "$h" = "$ph" ] &&
       { [ $((l + w + 1)) -eq "$pl" ] || [ $((pl + pw + 1)) -eq "$l" ]; }; then
      printf 'x'
      return 0
    fi
  done < <(tmux list-panes -t "$pane" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}')
  while read -r id l t w h; do
    [ "$id" = "$pane" ] && continue
    if [ "$l" = "$pl" ] && [ "$w" = "$pw" ] &&
       { [ $((t + h + 1)) -eq "$pt" ] || [ $((pt + ph + 1)) -eq "$t" ]; }; then
      printf 'y'
      return 0
    fi
  done < <(tmux list-panes -t "$pane" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}')
  return 1
}
