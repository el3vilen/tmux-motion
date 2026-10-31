#!/usr/bin/env bash
# Smoke test on a throwaway tmux server. Asserts that grow, flash, shrink and
# reload behave; it cannot judge how the effects look.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=(tmux -L motion-test)
fail=0

check() { # description condition...
  local desc=$1; shift
  if "$@"; then printf 'ok   %s\n' "$desc"; else printf 'FAIL %s\n' "$desc"; fail=1; fi
}
samples() { # pane format count -> space separated samples 50ms apart
  local out="" i
  for ((i = 0; i < $3; i++)); do
    out+="$("${T[@]}" display -p -t "$1" "$2" 2>/dev/null || echo gone) "
    sleep 0.05
  done
  printf '%s' "$out"
}
uniq_count() { tr ' ' '\n' <<< "$1" | grep . | sort -u | wc -l; }

cleanup() { "${T[@]}" kill-server 2>/dev/null; }
trap cleanup EXIT
cleanup

"${T[@]}" -f /dev/null new-session -d -x 120 -y 40
"${T[@]}" set -g pane-active-border-style 'fg=#89b4fa,bg=default'
"${T[@]}" set -g @motion-flash-target both
"${T[@]}" set -g @motion-flash-duration 300
"${T[@]}" set -g @motion-grow-duration 300
"${T[@]}" set -g @motion-shrink-duration 300
"${T[@]}" set -g @motion-zoom-duration 300
"${T[@]}" set -g @motion-kill-bind x
"${T[@]}" set -g @motion-fade-bg '#000000'
"${T[@]}" run-shell "$ROOT/motion.tmux"

check "hooks installed" [ "$({ "${T[@]}" show-hooks -g; "${T[@]}" show-hooks -gw; } | grep -c '\[90\]')" -eq 8 ]
check "remain-on-exit turned on for exit shrink" [ "$("${T[@]}" show -gv remain-on-exit)" = on ]
check "kill key bound" [ -n "$("${T[@]}" list-keys -T prefix x 2>/dev/null)" ]

p1="$("${T[@]}" split-window -h -P -F '#{pane_id}')"
s="$(samples "$p1" '#{pane_width}' 8)"
check "grow passes through several widths ($s)" [ "$(uniq_count "$s")" -ge 4 ]
sleep 0.3
check "grow ends at layout width" [ "$("${T[@]}" display -p -t "$p1" '#{pane_width}')" -eq 59 ]
check "grow leaves no spacer behind" [ "$("${T[@]}" display -p '#{window_panes}')" -eq 2 ]
check "grow clears its layout bookkeeping" [ -z "$("${T[@]}" show -wqv @motion-grow-layout)$("${T[@]}" show -wqv @motion-grow-geo)" ]
check "grow clears its run id" [ -z "$("${T[@]}" show -wqv @motion-resize-run)" ]

"${T[@]}" select-pane -L
sleep 0.1
mid="$("${T[@]}" show -wqv pane-active-border-style)"
check "flash sets a window-level border style ($mid)" [ -n "$mid" ]
sleep 0.5
check "flash restores border" [ -z "$("${T[@]}" show -wqv pane-active-border-style)" ]
check "flash restores active style" [ -z "$("${T[@]}" show -wqv window-active-style)" ]
check "flash clears bookkeeping" [ -z "$("${T[@]}" show -wqv @motion-orig-pane-active-border-style)$("${T[@]}" show -wqv @motion-flash-run)" ]

"${T[@]}" select-pane -R; sleep 0.05; "${T[@]}" select-pane -L; sleep 0.6
check "superseded flash still restores" [ -z "$("${T[@]}" show -wqv pane-active-border-style)" ]

"${T[@]}" select-pane -t %0; sleep 0.05
check "selecting the active pane does not flash" [ -z "$("${T[@]}" show -wqv pane-active-border-style)" ]
sleep 0.3

"${T[@]}" set -w pane-active-border-style 'fg=#ff0000'
"${T[@]}" select-pane -R; sleep 0.6
check "existing window-level style is restored" [ "$("${T[@]}" show -wqv pane-active-border-style)" = 'fg=#ff0000' ]
"${T[@]}" set -wu pane-active-border-style

p2="$("${T[@]}" split-window -v -t %0 -P -F '#{pane_id}')"
s="$(samples %0 '#{pane_height}' 8)"
check "border grow shrinks the neighbor gradually ($s)" [ "$(uniq_count "$s")" -ge 4 ]
sleep 0.3
"${T[@]}" kill-pane -t "$p2"; sleep 0.2
p2="$("${T[@]}" split-window -v -t %0 -P -F '#{pane_id}')"
s="$(samples "$p2" '#{pane_height}' 8)"
check "vertical grow passes through several heights ($s)" [ "$(uniq_count "$s")" -ge 4 ]
sleep 0.3

"${T[@]}" run-shell -b "$ROOT/scripts/kill.sh $p2"
s="$(samples "$p2" '#{pane_height}' 8)"
check "shrink passes through several heights ($s)" [ "$(uniq_count "$s")" -ge 4 ]
check "shrink kills the pane" [ "$("${T[@]}" display -p '#{window_panes}')" -eq 2 ]

before="$("${T[@]}" display -p '#{window_layout}')"
"${T[@]}" select-pane -t "$p1"; sleep 0.3
"${T[@]}" resize-pane -Z -t "$p1"
s="$(samples "$p1" '#{pane_width}x#{pane_height}' 7)"
check "zoom in grows through several sizes ($s)" [ "$(uniq_count "$s")" -ge 4 ]
sleep 0.3
check "zoom in ends zoomed" [ "$("${T[@]}" display -p -t "$p1" '#{window_zoomed_flag}')" -eq 1 ]
"${T[@]}" resize-pane -Z -t "$p1"
s="$(samples "$p1" '#{pane_width}x#{pane_height}' 7)"
check "zoom out shrinks through several sizes ($s)" [ "$(uniq_count "$s")" -ge 4 ]
sleep 0.3
check "zoom out restores the layout exactly" [ "$("${T[@]}" display -p '#{window_layout}')" = "$before" ]
check "zoom clears bookkeeping" [ -z "$("${T[@]}" show -wqv @motion-zoom-run)$("${T[@]}" show -wqv @motion-zoom-layout)" ]

p3="$("${T[@]}" split-window -h -t %0 -P -F '#{pane_id}' 'sleep 0.3; exit 0')"
sleep 0.5
s="$(samples "$p3" '#{pane_width}' 8)"
check "exited pane shrinks before it goes ($s)" [ "$(uniq_count "$s")" -ge 3 ]
check "exited pane and its spacer are gone" [ "$("${T[@]}" display -p '#{window_panes}')" -eq 2 ]

check "fade takes over the resize keys" grep -q fade.sh <<< "$("${T[@]}" list-keys -T prefix M-Up)"
check "fade takes over the border drag" grep -q fade.sh <<< "$("${T[@]}" list-keys -T root MouseDrag1Border)"
"${T[@]}" set -g window-style 'fg=#888888,bg=#101010'
"${T[@]}" set -g @motion-fade-out-duration 150
"${T[@]}" set -g @motion-fade-in-duration 300
w="$("${T[@]}" display -p -t %0 '#{pane_width}')"
"${T[@]}" run-shell -b "$ROOT/scripts/fade.sh resize '' %0 -L 3"
s="$(samples %0 '#{s/ /_/:#{window-style}}' 10)"
check "fade steps the text color through several values ($s)" [ "$(uniq_count "$s")" -ge 4 ]
check "fade reaches the background" grep -q 'fg=#101010' <<< "$s"
sleep 0.4
check "fade resizes" [ "$("${T[@]}" display -p -t %0 '#{pane_width}')" -eq $((w - 3)) ]
check "fade restores the styles" [ -z "$("${T[@]}" show -wqv window-style)$("${T[@]}" show -wqv pane-active-border-style)" ]
check "fade clears the pane-level styles of the sweep" [ -z "$("${T[@]}" show -pqv -t %0 window-style)$("${T[@]}" show -pqv -t %0 window-active-style)$("${T[@]}" show -pqv -t "$p1" window-style)" ]
check "fade clears bookkeeping" [ -z "$("${T[@]}" show -w | grep -E 'motion-(fade|orig|flash-run)')" ]
"${T[@]}" run-shell -b "$ROOT/scripts/fade.sh out %0"; sleep 0.3
check "drag start holds the fade" grep -q 'fg=#101010' <<< "$("${T[@]}" show -wqv window-style)"
"${T[@]}" run-shell -b "$ROOT/scripts/fade.sh in %0"; sleep 0.5
check "drag end fades back in" [ -z "$("${T[@]}" show -wqv window-style)$("${T[@]}" show -wqv @motion-fade-run)" ]
"${T[@]}" set -gu window-style

"${T[@]}" run-shell "$ROOT/motion.tmux"
check "reload keeps a single hook set" [ "$({ "${T[@]}" show-hooks -g; "${T[@]}" show-hooks -gw; } | grep -c '\[90\]')" -eq 8 ]
"${T[@]}" set -g @motion off
"${T[@]}" run-shell "$ROOT/motion.tmux"
check "@motion off removes hooks" [ "$({ "${T[@]}" show-hooks -g; "${T[@]}" show-hooks -gw; } | grep -c '\[90\]')" -eq 0 ]
check "@motion off gives the resize keys back" grep -q 'M-Up  *resize-pane -U 5$' <<< "$("${T[@]}" list-keys -T prefix M-Up)"
check "@motion off restores remain-on-exit" [ "$("${T[@]}" show -gv remain-on-exit)" = off ]

exit $fail
