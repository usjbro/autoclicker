--!strict
-- Pure direction-blend math extracted from WingsVisualSystem.lua's
-- fanCFrame so it's independently testable under Lune (test/
-- wingsGeometry.test.luau) without a running Roblox engine -- the same
-- "pure logic in src/shared, zero Roblox-only globals" pattern
-- MazeGeometry.lua already uses (deliberately no Vector3/CFrame here,
-- since neither exists under Lune; WingsVisualSystem.lua wraps this
-- module's plain-number result into a real Vector3/CFrame.lookAt).
--
-- This exists because this exact class of math has already shipped a real
-- sign bug once (see CLAUDE.md's WingsVisualSystem.lua bullet): swapping
-- which axis a rotation applies to is orientation-reversing, so a wrong
-- sign is easy to introduce and, without a test, easy to ship again.
local WingsGeometry = {}

-- Every wing piece fans from "pointing straight up" (spreadDeg=0, folded
-- close against the back) toward "pointing straight lateral" (spreadDeg=
-- 90, fully spread), mirrored by side (-1 left, 1 right). Returns a unit
-- direction as three plain numbers (x, y, z) -- x is always 0 by
-- construction (the blend only ever mixes up/lateral, never depth).
function WingsGeometry.FanDirection(spreadDeg: number, side: number): (number, number, number)
	local radians = math.rad(spreadDeg)
	local y = math.cos(radians)
	local z = math.sin(radians) * side
	return 0, y, z
end

return WingsGeometry
