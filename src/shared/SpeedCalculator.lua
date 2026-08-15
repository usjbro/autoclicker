--!strict
-- The single centralized place movement-speed math lives, so it's never
-- scattered across client/server scripts and stays easy to retune. Every
-- input is clamped/sanitized so this can never produce a negative, NaN, or
-- infinite speed regardless of what's passed in.
local SpeedCalculator = {}

SpeedCalculator.BASE_WALK_SPEED = 16 -- Roblox's own default Humanoid.WalkSpeed
local SPEED_PER_CLICK = 0.05
local CLICK_CAP = 2000 -- max speed caps at BASE_WALK_SPEED + CLICK_CAP * SPEED_PER_CLICK (=116)

local function clamp(value: number, low: number, high: number): number
	if value ~= value then -- NaN
		return low
	end
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

-- The player's maximum possible movement speed, based on lifetime clicks.
function SpeedCalculator.CalculateMaxSpeed(totalClicks: number): number
	local clicks = clamp(totalClicks, 0, CLICK_CAP)
	return SpeedCalculator.BASE_WALK_SPEED + clicks * SPEED_PER_CLICK
end

export type SpeedSettings = {
	totalClicks: number,
	useBaseSpeed: boolean,
	speedSliderPercent: number,
}

-- The actual speed to apply: base speed if the player opted into it,
-- otherwise interpolated between base and their max speed by the slider.
function SpeedCalculator.CalculateEffectiveSpeed(session: SpeedSettings): number
	if session.useBaseSpeed then
		return SpeedCalculator.BASE_WALK_SPEED
	end

	local maxSpeed = SpeedCalculator.CalculateMaxSpeed(session.totalClicks)
	local percent = clamp(session.speedSliderPercent, 0, 100)
	return SpeedCalculator.BASE_WALK_SPEED + (maxSpeed - SpeedCalculator.BASE_WALK_SPEED) * (percent / 100)
end

return SpeedCalculator
