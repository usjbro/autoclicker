#!/usr/bin/env bash
# Tier 2 feasibility spike: submits test/spike.luau to Roblox's Open Cloud
# Luau-execution API against a published place, polls until it finishes, and
# prints the result. Confirms the whole round trip works before any of this
# gets wired into CI. See the "Confirmed schema" note in
# ~/.claude/plans/soft-honking-mitten.md for where this request/response
# shape came from.
#
# Requires:
#   ROBLOX_API_KEY    - Open Cloud API key with Luau Execution permission on
#                        the target universe (Creator Dashboard > Open Cloud
#                        API Keys). Never pass this on the command line or
#                        commit it -- export it in your shell first.
#   ROBLOX_UNIVERSE_ID
#   ROBLOX_PLACE_ID
#
# Usage: ROBLOX_API_KEY=... ROBLOX_UNIVERSE_ID=... ROBLOX_PLACE_ID=... ./test/openCloudSpike.sh
set -euo pipefail

: "${ROBLOX_API_KEY:?Set ROBLOX_API_KEY (export it, don't inline it)}"
: "${ROBLOX_UNIVERSE_ID:?Set ROBLOX_UNIVERSE_ID}"
: "${ROBLOX_PLACE_ID:?Set ROBLOX_PLACE_ID}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_CONTENT="$(cat "$SCRIPT_DIR/spike.luau")"

BASE_URL="https://apis.roblox.com/cloud/v2"
CREATE_URL="$BASE_URL/universes/$ROBLOX_UNIVERSE_ID/places/$ROBLOX_PLACE_ID/luau-execution-session-tasks"

echo "Submitting task to $CREATE_URL ..." >&2
CREATE_RESPONSE="$(jq -n --arg script "$SCRIPT_CONTENT" '{script: $script}' \
	| curl -sS -X POST "$CREATE_URL" \
		-H "x-api-key: $ROBLOX_API_KEY" \
		-H "Content-Type: application/json" \
		--data-binary @-)"

TASK_PATH="$(echo "$CREATE_RESPONSE" | jq -r '.path // empty')"
if [ -z "$TASK_PATH" ]; then
	echo "Failed to create task. Response:" >&2
	echo "$CREATE_RESPONSE" | jq . >&2
	exit 1
fi
echo "Task created: $TASK_PATH" >&2

STATE="QUEUED"
for _ in $(seq 1 40); do
	sleep 3.5
	POLL_RESPONSE="$(curl -sS -X GET "$BASE_URL/$TASK_PATH" -H "x-api-key: $ROBLOX_API_KEY")"
	STATE="$(echo "$POLL_RESPONSE" | jq -r '.state')"
	echo "State: $STATE" >&2
	case "$STATE" in
	COMPLETE)
		echo "$POLL_RESPONSE" | jq '.output.results'
		exit 0
		;;
	FAILED)
		echo "Task failed:" >&2
		echo "$POLL_RESPONSE" | jq '.error' >&2
		exit 1
		;;
	CANCELLED)
		echo "Task was cancelled." >&2
		exit 1
		;;
	esac
done

echo "Timed out waiting for task to finish (last state: $STATE)." >&2
exit 1
