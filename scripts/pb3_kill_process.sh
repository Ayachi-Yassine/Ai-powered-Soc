#!/usr/bin/env bash
# PB3 - neutralise a malicious process: identify, kill, quarantine, log.
#
# Usage:   sudo ./pb3_kill_process.sh <process-or-file-name>
#
# Notes:
#  - The name comes from an alert, so it is restricted to a safe character set.
#  - pgrep -f also matches this script's own command line (and its parent shell,
#    e.g. an ssh -c invocation), so those PIDs are excluded to avoid self-kill
#    and false "killed" reports.
set -uo pipefail

MALWARE="${1:?usage: $0 <process-or-file-name>}"

if ! [[ "$MALWARE" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: refusing unsafe name '$MALWARE'" >&2
    exit 2
fi

PIDS=()
for pid in $(pgrep -f -- "$MALWARE"); do
    # Skip this script, its parent shell, and the short-lived subshell that runs
    # the pgrep above (a child of this script with the same command line).
    if [ "$pid" = "$$" ] || [ "$pid" = "$PPID" ]; then
        continue
    fi
    if [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$$" ]; then
        continue
    fi
    kill -0 "$pid" 2>/dev/null || continue
    PIDS+=("$pid")
done

if [ "${#PIDS[@]}" -eq 0 ]; then
    echo "no running process matches '$MALWARE'"
    exit 0
fi

kill -9 "${PIDS[@]}"

mkdir -p /quarantine
if [ -e "/tmp/$MALWARE" ]; then
    mv "/tmp/$MALWARE" "/quarantine/${MALWARE}.$(date +%s)"
fi

logger "SOCPilot: $MALWARE (PID ${PIDS[*]}) killed and quarantined"
echo "killed PID(s): ${PIDS[*]}"
