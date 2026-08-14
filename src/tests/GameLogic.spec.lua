--!strict
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GameLogic = require(ReplicatedStorage.Shared.GameLogic)

	local function session(overrides)
		local base = {
			score = 0,
			autoClickerCount = 0,
			megaClickerCount = 0,
			clickPowerCount = 0,
			multiplierCount = 0,
		}
		for key, value in pairs(overrides or {}) do
			base[key] = value
		end
		return base
	end

	describe("GetUpgradeCost", function()
		it("should return the flat cost for each upgrade regardless of how many are owned", function()
			expect(GameLogic.GetUpgradeCost("AutoClicker")).to.equal(10)
			expect(GameLogic.GetUpgradeCost("MegaClicker")).to.equal(150)
			expect(GameLogic.GetUpgradeCost("ClickPower")).to.equal(25)
			expect(GameLogic.GetUpgradeCost("Multiplier")).to.equal(500)
		end)

		it("should error for an unknown upgrade id", function()
			expect(function()
				GameLogic.GetUpgradeCost("NotAnUpgrade")
			end).to.throw()
		end)
	end)

	describe("CalculateMultiplier", function()
		it("should be 1 with no Multiplier upgrades", function()
			expect(GameLogic.CalculateMultiplier(session())).to.equal(1)
		end)

		it("should add 10% per Multiplier level", function()
			expect(GameLogic.CalculateMultiplier(session({ multiplierCount = 3 }))).to.equal(1.3)
		end)
	end)

	describe("CalculateClickGain", function()
		it("should return 1 with no Click Power upgrades", function()
			expect(GameLogic.CalculateClickGain(session())).to.equal(1)
		end)

		it("should scale with Click Power levels", function()
			expect(GameLogic.CalculateClickGain(session({ clickPowerCount = 4 }))).to.equal(5)
		end)

		it("should apply the multiplier on top of Click Power", function()
			local result = GameLogic.CalculateClickGain(session({ clickPowerCount = 4, multiplierCount = 1 }))
			expect(result).to.be.near(5.5, 1e-9)
		end)
	end)

	describe("CalculateIdleGain", function()
		it("should return 0 with no auto-clickers", function()
			expect(GameLogic.CalculateIdleGain(session(), 10)).to.equal(0)
		end)

		it("should scale with base auto-clickers over time", function()
			expect(GameLogic.CalculateIdleGain(session({ autoClickerCount = 5 }), 10)).to.equal(50)
		end)

		it("should weight Mega Auto-Clickers 10x a base auto-clicker", function()
			expect(GameLogic.CalculateIdleGain(session({ megaClickerCount = 1 }), 1)).to.equal(10)
		end)

		it("should combine both tiers and apply the multiplier", function()
			local result = GameLogic.CalculateIdleGain(
				session({ autoClickerCount = 2, megaClickerCount = 1, multiplierCount = 1 }),
				1
			)
			-- (2*1 + 1*10) * 1.1 = 13.2
			expect(result).to.be.near(13.2, 1e-9)
		end)
	end)
end
