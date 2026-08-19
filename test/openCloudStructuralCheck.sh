#!/usr/bin/env bash
# Tier 2 CI-integrated structural instance test: submits
# test/structuralCheck.luau to Roblox's Open Cloud Luau-execution API,
# which runs a real MapBuilder.Build() inside the actual Roblox engine
# against the published place and asserts real structural properties
# (goal parts exist and are named correctly, no two wings' actual built
# bounding boxes overlap, ReplicatedStorage has exactly the declared
# RemoteEvents). Exits non-zero -- failing the CI job -- if the task
# itself failed OR if it completed but reported any assertion failures.
#
# Requires:
#   ROBLOX_API_KEY    - Open Cloud API key with Luau Execution permission on
#                        the target universe (Creator Dashboard > Open Cloud
#                        API Keys). Never pass this on the command line or
#                        commit it -- export it, or in CI, a repo secret.
#   ROBLOX_UNIVERSE_ID
#   ROBLOX_PLACE_ID
#
# Usage: ROBLOX_API_KEY=... ROBLOX_UNIVERSE_ID=... ROBLOX_PLACE_ID=... ./test/openCloudStructuralCheck.sh
set -euo pipefail

: "${ROBLOX_API_KEY:?Set ROBLOX_API_KEY -- export it, do not inline it}"
: "${ROBLOX_UNIVERSE_ID:?Set ROBLOX_UNIVERSE_ID}"
: "${ROBLOX_PLACE_ID:?Set ROBLOX_PLACE_ID}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/openCloudRun.sh
source "$SCRIPT_DIR/lib/openCloudRun.sh"

RESULTS_JSON="$(openCloudRun "$SCRIPT_DIR/structuralCheck.luau")"

# structuralCheck.luau returns a single-element results array: [{success, failures}].
SUCCESS="$(echo "$RESULTS_JSON" | jq -r '.[0].success')"
if [ "$SUCCESS" != "true" ]; then
	echo "Structural check FAILED:" >&2
	echo "$RESULTS_JSON" | jq -r '.[0].failures[]' >&2
	exit 1
fi

echo "Structural check passed." >&2
