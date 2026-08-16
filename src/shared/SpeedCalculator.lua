--!strict
-- The single centralized place movement-speed math lives, so it's never
-- scattered across client/server scripts and stays easy to retune. Every
-- input is clamped/sanitized so this can never produce a negative, NaN, or
-- infinite speed regardless of what's passed in.
local SpeedCalculator = {}

SpeedCalculator.BASE_WALK_SPEED = 16 -- Roblox's own default Humanoid.WalkSpeed
local SPEED_PER_SCORE = 0.01
-- Deliberately matches GameConstants.REBIRTH.Threshold (not imported, to keep
-- this module dependency-free/independently testable) -- reaching rebirth
-- eligibility also means reaching max speed, a legible milestone to aim for.
local SCORE_CAP = 10000 -- max speed caps at BASE_WALK_SPEED + SCORE_CAP * SPEED_PER_SCORE (=116)

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

-- The player's maximum possible movement speed, based on their current
-- score -- deliberately current (not lifetime-earned), so speed rises and
-- falls with it: spending on upgrades or a Reset/Rebirth wiping score back
-- to 0 brings speed back down too, rather than being a one-way permanent
-- stat like totalClicks used to be.
function SpeedCalculator.CalculateMaxSpeed(score: number): number
	local clampedScore = clamp(score, 0, SCORE_CAP)
	return SpeedCalculator.BASE_WALK_SPEED + clampedScore * SPEED_PER_SCORE
end

export type SpeedSettings = {
	score: number,
	useBaseSpeed: boolean,
	speedSliderPercent: number,
}

-- The actual speed to apply: base speed if the player opted into it,
-- otherwise interpolated between base and their max speed by the slider.
function SpeedCalculator.CalculateEffectiveSpeed(session: SpeedSettings): number
	if session.useBaseSpeed then
		return SpeedCalculator.BASE_WALK_SPEED
	end

	local maxSpeed = SpeedCalculator.CalculateMaxSpeed(session.score)
	local percent = clamp(session.speedSliderPercent, 0, 100)
	return SpeedCalculator.BASE_WALK_SPEED + (maxSpeed - SpeedCalculator.BASE_WALK_SPEED) * (percent / 100)
end

return SpeedCalculator
