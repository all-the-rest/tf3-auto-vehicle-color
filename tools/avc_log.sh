#!/bin/sh
# Print the mod-relevant lines of the newest Transport Fever 3 log.
# Use after a game restart + load, instead of scrolling the in-game console.
#
#   sh tools/avc_log.sh          # AVC probes + game-script wiring lines
#   sh tools/avc_log.sh all      # the whole tail of the log
set -e

USERDATA="$HOME/Library/Application Support/Steam/userdata"
LOG=$(ls -t "$USERDATA"/*/*/local/crash_dump/stdout.txt 2>/dev/null | head -1) || true
if [ -z "$LOG" ]; then
	echo "no crash_dump/stdout.txt found under $USERDATA" >&2
	exit 1
fi

echo "# $LOG"
if [ "$1" = "all" ]; then
	tail -n 200 "$LOG"
else
	grep -E '\[AVC\]|\[Better|Creating entity for GameScript|Error while (loading|running) game script|Invalid res uri' "$LOG" | tail -n 80
fi
