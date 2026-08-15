--!strict
-- Single reusable number-abbreviation module, used everywhere a number is
-- displayed (score, rates, costs, owned counts, leaderboard entries) so
-- formatting logic never gets duplicated across GUI scripts.
local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T" }

-- Two-letter suffixes beyond T: aa, ab, ..., az, ba, ..., zz (676 tiers,
-- covers absurdly large values). tierIndex 0 = "aa".
local function letterSuffix(tierIndex: number): string
	local first = math.floor(tierIndex / 26) % 26
	local second = tierIndex % 26
	return string.char(97 + first) .. string.char(97 + second)
end

local function trimNumber(value: number): string
	if value == math.floor(value) then
		return tostring(math.floor(value))
	end
	return tostring(value)
end

-- Format(999) = "999", Format(1000) = "1K", Format(1250) = "1.25K",
-- Format(1500000) = "1.5M", Format(2000000000) = "2B".
function NumberFormat.Format(n: number): string
	if n ~= n then -- NaN
		return "0"
	end
	if n == math.huge then
		return "∞"
	end
	if n == -math.huge then
		return "-∞"
	end
	if n < 0 then
		return "-" .. NumberFormat.Format(-n)
	end

	if n < 1000 then
		return trimNumber(math.floor(n + 0.5))
	end

	local tier = 0
	local scaled = n
	while scaled >= 1000 do
		scaled /= 1000
		tier += 1
	end

	local rounded = math.floor(scaled * 100 + 0.5) / 100
	if rounded >= 1000 then
		-- Rounding pushed us back over the next threshold (e.g. 999.995 -> 1000.0) -- bump one more tier.
		scaled /= 1000
		tier += 1
		rounded = math.floor(scaled * 100 + 0.5) / 100
	end

	local suffix = if tier < #SUFFIXES then SUFFIXES[tier + 1] else letterSuffix(tier - #SUFFIXES)
	return trimNumber(rounded) .. suffix
end

return NumberFormat
