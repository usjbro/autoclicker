#!/usr/bin/env bash
# Tier 2 feasibility spike: submits test/spike.luau to Roblox's Open Cloud
# Luau-execution API against a published place, polls until it finishes,
# and prints the raw result. Diagnostic/manual tool, not run by CI --
# test/openCloudStructuralCheck.sh is the CI-integrated version that
# actually asserts on the result.
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

: "${ROBLOX_API_KEY:?Set ROBLOX_API_KEY -- export it, do not inline it}"
: "${ROBLOX_UNIVERSE_ID:?Set ROBLOX_UNIVERSE_ID}"
: "${ROBLOX_PLACE_ID:?Set ROBLOX_PLACE_ID}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/openCloudRun.sh
source "$SCRIPT_DIR/lib/openCloudRun.sh"

openCloudRun "$SCRIPT_DIR/spike.luau"
