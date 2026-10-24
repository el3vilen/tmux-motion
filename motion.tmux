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
grow="$(printf '%q' "$DIR/scripts/grow.sh")"
kill="$(printf '%q' "$DIR/scripts/kill.sh")"

for h in "${flash_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" "run-shell -b \"$flash '#{pane_id}'\""
done
for h in "${grow_hooks[@]}"; do
  tmux set-hook -g "${h}[${INDEX}]" "run-shell -b \"$grow '#{pane_id}'\""
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
