#!/usr/bin/env bash
# Shared submit+poll core for Roblox's Open Cloud Luau Execution API. Not
# run directly -- sourced by test/openCloudSpike.sh and
# test/openCloudStructuralCheck.sh, which each interpret the returned
# result differently (the spike just prints it for a human; the structural
# check treats a {success:false} payload as a CI failure).
#
# On success, prints the task's output.results (a JSON array) to stdout
# and returns 0. On any Open Cloud-level failure (task creation, FAILED,
# CANCELLED, timeout), prints diagnostics to stderr and returns 1 -- does
# NOT interpret the *contents* of a successful result, that's the caller's
# job. Callers must already have ROBLOX_API_KEY/ROBLOX_UNIVERSE_ID/
# ROBLOX_PLACE_ID set (their own `: "${VAR:?...}"` guards should run
# first).
#
# Deliberately avoids two real bugs macOS's stock /bin/bash (3.2, frozen
# since 2007) has under `set -u`: piping one command straight into another
# inside a `$(...)` substitution (misattributes the resulting error to the
# wrong variable/line), and apostrophes inside a message string (can trip
# a parse-time syntax error even inside double quotes) -- see PR #75.
openCloudRun() {
	local luau_file="$1"
	local script_content
	script_content="$(cat "$luau_file")"

	local base_url="https://apis.roblox.com/cloud/v2"
	local create_url="$base_url/universes/$ROBLOX_UNIVERSE_ID/places/$ROBLOX_PLACE_ID/luau-execution-session-tasks"

	local json_payload
	json_payload="$(jq -n --arg script "$script_content" '{script: $script}')"

	echo "Submitting $luau_file to $create_url ..." >&2
	local create_response
	create_response="$(curl -sS -X POST "$create_url" \
		-H "x-api-key: $ROBLOX_API_KEY" \
		-H "Content-Type: application/json" \
		--data-binary "$json_payload")"

	local task_path
	task_path="$(echo "$create_response" | jq -r '.path // empty')"
	if [ -z "$task_path" ]; then
		echo "Failed to create task. Response:" >&2
		echo "$create_response" | jq . >&2
		return 1
	fi
	echo "Task created: $task_path" >&2

	local state="QUEUED"
	local poll_response
	for _ in $(seq 1 40); do
		sleep 3.5
		poll_response="$(curl -sS -X GET "$base_url/$task_path" -H "x-api-key: $ROBLOX_API_KEY")"
		state="$(echo "$poll_response" | jq -r '.state')"
		echo "State: $state" >&2
		case "$state" in
		COMPLETE)
			echo "$poll_response" | jq '.output.results'
			return 0
			;;
		FAILED)
			echo "Task failed:" >&2
			echo "$poll_response" | jq '.error' >&2
			return 1
			;;
		CANCELLED)
			echo "Task was cancelled." >&2
			return 1
			;;
		esac
	done

	echo "Timed out waiting for task to finish (last state: $state)." >&2
	return 1
}
