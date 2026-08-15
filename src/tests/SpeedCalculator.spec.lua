--!strict
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local SpeedCalculator = require(ReplicatedStorage.Shared.SpeedCalculator)

	describe("CalculateMaxSpeed", function()
		it("should equal base speed at 0 clicks", function()
			expect(SpeedCalculator.CalculateMaxSpeed(0)).to.equal(SpeedCalculator.BASE_WALK_SPEED)
		end)

		it("should increase with clicks but cap at a bounded value", function()
			local low = SpeedCalculator.CalculateMaxSpeed(100)
			local high = SpeedCalculator.CalculateMaxSpeed(100000)
			expect(low > SpeedCalculator.BASE_WALK_SPEED).to.equal(true)
			expect(high > low).to.equal(true)
			expect(high <= SpeedCalculator.BASE_WALK_SPEED + 200).to.equal(true)
		end)

		it("should never go negative or NaN for invalid input", function()
			expect(SpeedCalculator.CalculateMaxSpeed(-50)).to.equal(SpeedCalculator.BASE_WALK_SPEED)
			expect(SpeedCalculator.CalculateMaxSpeed(0 / 0)).to.equal(SpeedCalculator.BASE_WALK_SPEED)
		end)
	end)

	describe("CalculateEffectiveSpeed", function()
		it("should return base speed when useBaseSpeed is true, regardless of clicks/slider", function()
			local speed = SpeedCalculator.CalculateEffectiveSpeed({
				totalClicks = 100000,
				useBaseSpeed = true,
				speedSliderPercent = 100,
			})
			expect(speed).to.equal(SpeedCalculator.BASE_WALK_SPEED)
		end)

		it("should interpolate between base and max speed by the slider percent", function()
			local maxSpeed = SpeedCalculator.CalculateMaxSpeed(2000)
			local atZero = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 0 })
			local atHalf = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 50 })
			local atFull = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 100 })

			expect(atZero).to.equal(SpeedCalculator.BASE_WALK_SPEED)
			expect(atHalf).to.be.near((SpeedCalculator.BASE_WALK_SPEED + maxSpeed) / 2, 1e-9)
			expect(atFull).to.equal(maxSpeed)
		end)

		it("should never exceed the calculated max speed even with an out-of-range slider", function()
			local maxSpeed = SpeedCalculator.CalculateMaxSpeed(2000)
			local speed = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 99999 })
			expect(speed <= maxSpeed).to.equal(true)
		end)
	end)
end
