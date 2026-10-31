#!/usr/bin/env bash
# fade.sh resize CLIENT PANE RESIZE-ARGS...
#   A keyboard resize. Fade the window's text and borders down to the
#   background, resize under a borderless curtain popup while the programs
#   inside redraw, then sweep the curtain off in the direction the border
#   moved. Each pane fades back in as the sweep passes it, and the active pane
#   flashes when its turn comes.
# fade.sh out PANE
#   A mouse drag on a border started. Fade down and stay there until
#   `fade.sh in` or a safety timeout.
# fade.sh in PANE
#   The drag ended. Fade back in, sweeping the way the border was dragged.
#
# tmux styles only recolor text drawn in the default color, so text a program
# colors itself (an editor, a colored prompt) does not fade. The curtain is
# what hides that text while it reflows.
# shellcheck disable=SC2154  # setting() and friends assign through printf -v
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

mode=${1:-}
[ $# -gt 0 ] && shift
client=""
case "$mode" in
  resize) client=${1:-} pane=${2:-}; shift 2 2>/dev/null || exit 0 ;;
  out|in) pane=${1:-} ;;
  *) exit 0 ;;
esac
[ -n "$pane" ] || pane="$(tmux display -p '#{pane_id}')" || exit 0

opts=(window-style window-active-style pane-border-style pane-active-border-style)
settings=(fade fade-bg fade-fg fade-curtain fade-hold fade-out-steps fade-out-duration
  fade-in-steps fade-in-duration fade-sweep fade-drag-timeout flash flash-target
  flash-color flash-intensity flash-border-intensity flash-pane-intensity)

# Everything the fade needs to know, in one round trip.
q=(display -p -t "$pane" '#{window_panes} #{window_zoomed_flag} #{?#{@motion},#{@motion},on} #{?#{@motion-ssh},#{@motion-ssh},on} #{P:#{pane_id} }' ';'
  show-option -wqv -t "$pane" @motion-fade-run ';'
  show-option -wqv -t "$pane" @motion-fade-own ';'
  show-option -wqv -t "$pane" @motion-fade-drag-at ';'
  display -p -t "$pane" '#{P:#{pane_id}/#{pane_left}/#{pane_top}/#{pane_right}/#{pane_bottom} }')
for opt in "${opts[@]}"; do
  q+=(';' show-option -wqv -t "$pane" "@motion-fade-orig-$opt"
    ';' show-option -wqv -t "$pane" "@motion-orig-$opt"
    ';' show-option -wqv -t "$pane" "$opt"
    ';' display -p -t "$pane" "#{E:$opt}")
done
for name in "${settings[@]}"; do
  q+=(';' display -p -t "$pane" "#{@motion-$name}")
done
# Where the curtain goes: the client and window sizes and the status side.
[ -n "$client" ] && q+=(';' display -p -c "$client" -t "$pane" \
  '#{client_width} #{client_height} #{window_width} #{window_height} #{status-position}')
motion_query "${q[@]}"
client_geo=""
[ -n "$client" ] && client_geo=${MOTION_Q[$((${#MOTION_Q[@]} - 1))]}
# A pane that is gone makes the whole query fail.
if [ -z "${MOTION_Q[0]:-}" ]; then
  [ "$mode" = resize ] && tmux resize-pane -t "$pane" "$@"
  exit 0
fi
read -r panes zoomed master ssh_ok _ <<< "${MOTION_Q[0]}"
read -ra ids <<< "${MOTION_Q[0]#* * * * }"
prev=${MOTION_Q[1]} own=${MOTION_Q[2]} drag_at=${MOTION_Q[3]} geo_now=${MOTION_Q[4]}
qbase=5
declare -A set=()
for i in "${!settings[@]}"; do
  set[${settings[$i]}]=${MOTION_Q[$((qbase + ${#opts[@]} * 4 + i))]}
done
# setting VAR NAME DEFAULT
setting() { printf -v "$1" '%s' "${set[$2]:-$3}"; }

setting enabled fade on
allowed=1
if [ "${master:-on}" != on ] || [ "$enabled" != on ]; then
  allowed=0
elif [ "${ssh_ok:-on}" != on ]; then
  # Only the SSH opt-out needs the environment looked at.
  motion_allowed "$pane" || allowed=0
fi
if [ "$allowed" = 0 ] || [ "${panes:-1}" -lt 2 ] || [ "$zoomed" = 1 ]; then
  [ "$mode" = resize ] && tmux resize-pane -t "$pane" "$@"
  exit 0
fi
# `in` only ends a fade that a drag started.
[ "$mode" = in ] && [ -z "$prev" ] && exit 0

setting fade_bg fade-bg ''
setting fade_fg fade-fg ''

run_id="$$.$RANDOM"
guard="#{==:#{@motion-fade-run},$run_id}"

# The sweep direction: the way the border moves. A keyboard resize says it in
# its flag. A drag is read from the pane edges: the start of the drag
# recorded them, and the first edge that moved since tells which way.
dir=""
if [ "$mode" = resize ]; then
  for a in "$@"; do
    case "$a" in -L) dir=L ;; -R) dir=R ;; -U) dir=U ;; -D) dir=D ;; esac
  done
elif [ "$mode" = in ]; then
  declare -A was=()
  for g in $drag_at; do was[${g%%/*}]=$g; done
  for g in $geo_now; do
    old=${was[${g%%/*}]:-}
    { [ -n "$old" ] && [ "$old" != "$g" ]; } || continue
    IFS=/ read -r _ l0 t0 r0 b0 <<< "$old"
    IFS=/ read -r _ l1 t1 r1 b1 <<< "$g"
    if [ "$r1" != "$r0" ]; then dir=R; [ "$r1" -lt "$r0" ] && dir=L
    elif [ "$l1" != "$l0" ]; then dir=R; [ "$l1" -lt "$l0" ] && dir=L
    elif [ "$b1" != "$b0" ]; then dir=D; [ "$b1" -lt "$b0" ] && dir=U
    else dir=D; [ "$t1" -lt "$t0" ] && dir=U
    fi
    break
  done
fi

# Remember each style as it was before any effect touched it. A fade already
# in flight saved it; a flash in flight saved it under its own name. Taking
# the run over from a flash stops it: its frames are guarded on its own run
# id, which is cleared here.
saved=() bases=()
cmd="set-option -w -t '$pane' @motion-fade-run '$run_id' ; set-option -wu -t '$pane' @motion-flash-run"
[ "$mode" = out ] && cmd+=" ; set-option -w -t '$pane' @motion-fade-drag-at '$geo_now'"
for i in "${!opts[@]}"; do
  opt=${opts[$i]}
  fade_orig=${MOTION_Q[$((qbase + i * 4))]} flash_orig=${MOTION_Q[$((qbase + 1 + i * 4))]}
  value=${MOTION_Q[$((qbase + 2 + i * 4))]} effective=${MOTION_Q[$((qbase + 3 + i * 4))]}
  s=$fade_orig
  if [ -z "$s" ]; then
    s=${flash_orig:-$value}
    s=${s:-__unset__}
    cmd+=" ; set-option -w -t '$pane' '@motion-fade-orig-$opt' '$s' ; set-option -wu -t '$pane' '@motion-orig-$opt'"
  fi
  saved[i]=$s
  # The base is the style resolved to what it shows: a style built from a
  # format is expanded. Nothing touched the window yet, so the effective
  # value is it; otherwise the saved value is expanded by hand.
  if [ -z "$fade_orig$flash_orig" ]; then
    b=$effective
  else
    b=$s
    [ "$b" = __unset__ ] && b="$(tmux show-option -gqv "$opt")"
    [[ $b == *'#{'* ]] && b="$(tmux display -p -t "$pane" "$b")"
  fi
  bases[i]=$b
done

# The fade-in sets pane-level styles so each pane can be at its own point of
# the sweep. Panes that already carry their own pane-level style (select-pane
# -P) are left out, and the first run of a burst records which they are,
# before any frame of its own could be mistaken for one.
if [ -z "$prev" ]; then
  q=()
  for id in "${ids[@]}"; do
    [ ${#q[@]} -gt 0 ] && q+=(';')
    q+=(show-option -pqv -t "$id" window-style ';' show-option -pqv -t "$id" window-active-style)
  done
  motion_query "${q[@]}"
  own=""
  for i in "${!ids[@]}"; do
    [ -n "${MOTION_Q[$((i * 2))]}${MOTION_Q[$((i * 2 + 1))]}" ] && own+=" ${ids[$i]}"
  done
  own=${own:-" "}
  cmd+=" ; set-option -w -t '$pane' @motion-fade-own '$own'"
fi
tmux if-shell -F 1 "$cmd" 2>/dev/null || exit 0

# mix VAR FROM TO PERMILLE: VAR = FROM blended PERMILLE/1000 of the way to TO.
# Named colors cannot be blended and switch halfway. Fork-free, since a frame
# computes a handful of these per pane.
mix() {
  local f=${2#\#} t=${3#\#} p=$4
  if [[ $2 =~ ^#[0-9a-fA-F]{6}$ && $3 =~ ^#[0-9a-fA-F]{6}$ ]]; then
    printf -v "$1" '#%02x%02x%02x' \
      $(( (16#${f:0:2} * (1000 - p) + 16#${t:0:2} * p) / 1000 )) \
      $(( (16#${f:2:2} * (1000 - p) + 16#${t:2:2} * p) / 1000 )) \
      $(( (16#${f:4:2} * (1000 - p) + 16#${t:4:2} * p) / 1000 ))
  elif [ "$p" -lt 500 ]; then
    printf -v "$1" '%s' "$2"
  else
    printf -v "$1" '%s' "$3"
  fi
}

# style_get VAR STYLE KEY: the KEY= value inside a comma separated style.
style_get() {
  local part
  printf -v "$1" '%s' ""
  local IFS=,
  for part in $2; do
    [[ $part == "$3="* ]] && { printf -v "$1" '%s' "${part#*=}"; return 0; }
  done
  return 0
}

# Each style split into what stays fixed (prefix) and the fg it fades.
# motion_style_set does the splitting once; frames only glue strings.
from=() to=() skip=() pre=()
for i in "${!opts[@]}"; do
  style_get f "${bases[$i]}" fg
  motion_is_hex "$f" || f=${fade_fg:-default}
  style_get b "${bases[$i]}" bg
  motion_is_hex "$b" || b=$fade_bg
  from[i]=$f to[i]=$b skip[i]=0
  [ -n "$b" ] || skip[i]=1
  # The style with fg moved to the end, so a frame appends the new fg.
  s="$(motion_style_set "${bases[$i]}" fg X)"
  s=${s/fg=X/}
  s=${s/,,/,}
  s=${s#,}
  s=${s%,}
  pre[i]=${s:+$s,}
done

# The flash rides on the fade-in: the active border starts at the flash peak
# instead of the background, and the active pane's background starts tinted.
flash=0 peak_border="" peak_bg="" active_bg=""
setting flash_on flash on
if [ "$flash_on" = on ]; then
  flash=1
  setting target flash-target border
  setting color flash-color '#ffffff'
  setting intensity flash-intensity 100
  setting border_level flash-border-intensity "$intensity"
  setting pane_level flash-pane-intensity "$intensity"
  if [ "$target" = border ] || [ "$target" = both ]; then
    mix peak_border "${from[3]}" "$color" "$((border_level * 10))"
  fi
  if [ "$target" = pane ] || [ "$target" = both ]; then
    style_get active_bg "${bases[1]}" bg
    if motion_is_hex "$active_bg" && motion_is_hex "$color"; then
      mix peak_bg "$active_bg" "$color" "$((pane_level * 10))"
    fi
  fi
fi

# style VAR I LEVEL [FLASH]: option I's style at LEVEL (0 normal, 1000 fully
# faded). With FLASH, the active styles show the flash at LEVEL instead.
style() {
  local c bg
  if [ "${4:-0}" = 1 ] && [ "$2" = 3 ] && [ -n "$peak_border" ]; then
    mix c "${from[$2]}" "$peak_border" "$3"
  else
    mix c "${from[$2]}" "${to[$2]}" "$3"
  fi
  if [ "${4:-0}" = 1 ] && [ "$2" = 1 ] && [ -n "$peak_bg" ]; then
    mix bg "$active_bg" "$peak_bg" "$3"
    local _st="${pre[1]//bg=$active_bg/bg=$bg}"
    printf -v "$1" '%sfg=%s' "$_st" "$c"
  else
    printf -v "$1" '%sfg=%s' "${pre[$2]}" "$c"
  fi
}

# window_frame LEVEL -> REPLY: commands setting all four window-level styles.
window_frame() {
  local i s res=""
  for i in "${!opts[@]}"; do
    [ "${skip[$i]}" = 1 ] && continue
    style s "$i" "$1"
    res+="${res:+ ; }set-option -w -t '$pane' '${opts[$i]}' '$s'"
  done
  REPLY=${res:-if-shell -F 0 x}
}

restore() {
  local cmd="" i id
  for i in "${!opts[@]}"; do
    if [ "${saved[$i]}" = __unset__ ]; then
      cmd+="${cmd:+ ; }set-option -wu -t '$pane' '${opts[$i]}'"
    else
      cmd+="${cmd:+ ; }set-option -w -t '$pane' '${opts[$i]}' '${saved[$i]}'"
    fi
    cmd+=" ; set-option -wu -t '$pane' '@motion-fade-orig-${opts[$i]}'"
  done
  for id in "${pane_ids[@]}"; do
    [[ " $own " == *" $id "* ]] && continue
    cmd+=" ; set-option -pu -t '$id' window-style ; set-option -pu -t '$id' window-active-style"
  done
  printf '%s ; set-option -wu -t %s @motion-fade-run ; set-option -wu -t %s @motion-fade-own ; set-option -wu -t %s @motion-fade-drag-at' \
    "$cmd" "'$pane'" "'$pane'" "'$pane'"
}

newest() {
  [ "$(tmux show-option -wqv -t "$pane" @motion-fade-run 2>/dev/null)" = "$run_id" ]
}

now_ms() { printf -v "$1" '%d' $(( ${EPOCHREALTIME/./} / 1000 )); }
# sleep_until START_MS OFFSET_MS: frames keep to the clock however long the
# tmux calls in between took.
sleep_until() {
  local now
  now_ms now
  motion_sleep_ms $(( $1 + $2 - now > 0 ? $1 + $2 - now : 0 ))
}

fade_out() {
  local steps duration f start p
  setting steps fade-out-steps 2
  setting duration fade-out-duration 20
  [ "$steps" -ge 1 ] 2>/dev/null || steps=1
  # Already faded (a fade still in flight): jump straight to the bottom.
  [ -n "$prev" ] && steps=1
  now_ms start
  for ((f = 1; f <= steps; f++)); do
    p=$((f * 1000 / steps))
    p=$((p * p / 1000))
    window_frame "$p"
    tmux if-shell -F -t "$pane" "$guard" "$REPLY" 2>/dev/null || exit 0
    [ "$f" -lt "$steps" ] && sleep_until "$start" $((duration * f / steps))
  done
}

# curtain_cmd COVERED-PERMILLE -> REPLY: commands that put the curtain over the
# part of the window the sweep has not reached yet, or lift it at 0. The
# sweep runs the way the border moved: a border pushed left uncovers the
# window from the right edge toward the left. Closing and reopening go in one
# command list, so tmux draws one frame per step.
curtain_cmd() {
  local c=$1 res="display-popup -C -c '$client'" n x y w h
  [ "$c" -gt 0 ] || { REPLY=$res; return; }
  x=0 y=$((oy + wh)) w=$ww h=$wh
  case "$dir" in
    L) w=$(( (ww * c + 999) / 1000 )) ;;
    R) n=$(( (ww * c + 999) / 1000 )); x=$((ww - n)) w=$n ;;
    U) h=$(( (wh * c + 999) / 1000 )); y=$((oy + h)) ;;
    D) h=$(( (wh * c + 999) / 1000 )) ;;
  esac
  printf -v REPLY "%s ; display-popup -c '%s' -B -E -x %d -y %d -w %d -h %d -s 'bg=%s' 'printf \"\\\\033[?25l\"; exec sleep 3'" \
    "$res" "$client" "$x" "$y" "$w" "$h" "${fade_bg:-default}"
}

# fade_in CURTAIN: sweep back in over the in-duration. Each pane starts its
# own fade when the sweep reaches its leading edge, and finishes it over the
# rest of the time; @motion-fade-sweep is the share of the time the sweep
# itself takes (0: every pane fades at once). With CURTAIN on, the curtain
# retreats ahead of the sweep.
fade_in() {
  local curtain=$1 g steps duration sweep f t start cmd id l tp r b act pos i s level local_t ease cov
  setting steps fade-in-steps 6
  setting duration fade-in-duration 90
  setting sweep fade-sweep 50
  [ "$steps" -ge 1 ] 2>/dev/null || steps=1
  [ -n "$dir" ] || sweep=0
  local sweep_ms=$((duration * sweep / 100)) own_ms=$((duration - duration * sweep / 100))
  [ "$own_ms" -ge 1 ] || own_ms=1

  # Pane positions after the resize, as the delay before each pane's turn.
  local W H geo
  read -r W H geo < <(tmux display -p -t "$pane" '#{window_width} #{window_height} #{P:#{pane_id}/#{pane_left}/#{pane_top}/#{pane_right}/#{pane_bottom}/#{pane_active} }')
  local delays=() actives=()
  pane_ids=()
  for g in $geo; do
    IFS=/ read -r id l tp r b act <<< "$g"
    case "$dir" in
      L) pos=$(( (W - 1 - r) * 1000 / W )) ;;
      R) pos=$(( l * 1000 / W )) ;;
      U) pos=$(( (H - 1 - b) * 1000 / H )) ;;
      D) pos=$(( tp * 1000 / H )) ;;
      *) pos=0 ;;
    esac
    pane_ids+=("$id") delays+=($((sweep_ms * pos / 1000))) actives+=("$act")
  done

  now_ms start
  for ((f = 1; f <= steps; f++)); do
    t=$((duration * f / steps))
    cmd=""
    local active_lv=1000
    for i in "${!pane_ids[@]}"; do
      local_t=$(( (t - ${delays[$i]}) * 1000 / own_ms ))
      ((local_t < 0)) && local_t=0
      ((local_t > 1000)) && local_t=1000
      ease=$(( 1000 - (1000 - local_t) * (1000 - local_t) / 1000 ))
      level=$((1000 - ease))
      [ "${actives[$i]}" = 1 ] && active_lv=$level
      [[ " $own " == *" ${pane_ids[$i]} "* ]] && continue
      if [ "${actives[$i]}" = 1 ]; then
        [ "${skip[1]}" = 1 ] && continue
        style s 1 "$level" "$flash"
        cmd+="${cmd:+ ; }set-option -p -t '${pane_ids[$i]}' window-active-style '$s'"
      else
        [ "${skip[0]}" = 1 ] && continue
        style s 0 "$level"
        cmd+="${cmd:+ ; }set-option -p -t '${pane_ids[$i]}' window-style '$s'"
      fi
    done
    # Borders are window-wide: the inactive ones follow the clock, the
    # active one follows its pane and carries the flash.
    ease=$((1000 - t * 1000 / duration))
    level=$((ease * ease / 1000))
    if [ "${skip[2]}" = 0 ]; then
      style s 2 "$level"
      cmd+="${cmd:+ ; }set-option -w -t '$pane' pane-border-style '$s'"
    fi
    if [ "${skip[3]}" = 0 ]; then
      style s 3 "$active_lv" "$flash"
      cmd+="${cmd:+ ; }set-option -w -t '$pane' pane-active-border-style '$s'"
    fi

    if [ "$curtain" = 1 ]; then
      if [ "$sweep_ms" -gt 0 ]; then
        cov=$(( 1000 - t * 1000 / sweep_ms ))
      else
        cov=0
      fi
      ((cov < 0)) && cov=0
      if [ "$cov" -gt 0 ]; then
        # The popup blocks until closed, so this frame's client waits in the
        # background; the next frame's close lets it go.
        curtain_cmd "$cov"
        tmux if-shell -F -t "$pane" "$guard" "$cmd ; $REPLY" "display-popup -C -c '$client'" >/dev/null 2>&1 &
      else
        curtain_cmd 0
        tmux if-shell -F -t "$pane" "$guard" "$cmd ; $REPLY" "display-popup -C -c '$client'" 2>/dev/null || exit 0
        curtain=0
      fi
    else
      tmux if-shell -F -t "$pane" "$guard" "$cmd" 2>/dev/null || exit 0
    fi
    [ "$f" -lt "$steps" ] && sleep_until "$start" $((duration * f / steps))
  done
  tmux if-shell -F -t "$pane" "$guard" "$(restore)" 2>/dev/null
}

pane_ids=()
case "$mode" in
  resize)
    fade_out
    if ! newest; then
      # A newer press took over; it owns the curtain and the fade-in.
      tmux resize-pane -t "$pane" "$@"
      exit 0
    fi
    use_curtain=0
    setting curtain_on fade-curtain on
    if [ -n "$client" ] && [ "$curtain_on" = on ]; then
      use_curtain=1
      # The popup covers the window area, not the status line. Its -y is the
      # row below its bottom edge; oy is where the window starts.
      read -r cw ch ww wh pos <<< "$client_geo"
      oy=0
      [ "$pos" = top ] && oy=$((ch - wh))
      [ "$ww" -le "$cw" ] || ww=$cw
      # The resize and the popup go in one command list, so tmux draws the
      # curtain before the resized panes. The popup blocks until it is
      # closed, hence the background job; it closes itself if this script
      # dies. Keys pressed while it is up go to it and are dropped.
      tmux resize-pane -t "$pane" "$@" \; display-popup -c "$client" -B -E \
        -x 0 -y $((oy + wh)) -w "$ww" -h "$wh" -s "bg=${fade_bg:-default}" \
        "printf '\\033[?25l'; exec sleep 3" >/dev/null 2>&1 &
      setting hold fade-hold 30
      motion_sleep_ms "$hold"
    else
      tmux resize-pane -t "$pane" "$@"
    fi
    fade_in "$use_curtain"
    ;;
  out)
    fade_out
    # Wait for the drag to end. `fade.sh in` takes the run over; if the end
    # of the drag never arrives (released over a pane), fade in anyway.
    setting timeout fade-drag-timeout 10000
    for ((t = 0; t < timeout; t += 100)); do
      newest || exit 0
      motion_sleep_ms 100
    done
    fade_in 0
    ;;
  in)
    fade_in 0
    ;;
esac
exit 0
