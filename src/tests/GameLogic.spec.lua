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
			rebirthCount = 0,
			totalClicks = 0,
			useBaseSpeed = true,
			speedSliderPercent = 100,
		}
		for key, value in pairs(overrides or {}) do
			base[key] = value
		end
		return base
	end

	describe("GetDefaultSession", function()
		it("should return the documented defaults", function()
			expect(GameLogic.GetDefaultSession()).to.deep.equal(session())
		end)
	end)

	describe("ResetProgress", function()
		it("should zero score and upgrades but preserve clicks/rebirths/settings", function()
			local before = session({
				score = 5000,
				autoClickerCount = 3,
				megaClickerCount = 2,
				clickPowerCount = 1,
				multiplierCount = 4,
				rebirthCount = 2,
				totalClicks = 777,
				useBaseSpeed = false,
				speedSliderPercent = 42,
			})
			local after = GameLogic.ResetProgress(before)

			expect(after.score).to.equal(0)
			expect(after.autoClickerCount).to.equal(0)
			expect(after.megaClickerCount).to.equal(0)
			expect(after.clickPowerCount).to.equal(0)
			expect(after.multiplierCount).to.equal(0)
			expect(after.rebirthCount).to.equal(2)
			expect(after.totalClicks).to.equal(777)
			expect(after.useBaseSpeed).to.equal(false)
			expect(after.speedSliderPercent).to.equal(42)
		end)
	end)

	describe("PerformRebirth", function()
		it("should reset progress and increment rebirthCount", function()
			local before = session({ score = 20000, autoClickerCount = 5, rebirthCount = 1, totalClicks = 100 })
			local after = GameLogic.PerformRebirth(before)

			expect(after.score).to.equal(0)
			expect(after.autoClickerCount).to.equal(0)
			expect(after.totalClicks).to.equal(100)
			expect(after.rebirthCount).to.equal(2)
		end)
	end)

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

		it("should add 25% per rebirth", function()
			expect(GameLogic.CalculateMultiplier(session({ rebirthCount = 2 }))).to.equal(1.5)
		end)

		it("should combine Multiplier upgrades and rebirths", function()
			local result = GameLogic.CalculateMultiplier(session({ multiplierCount = 1, rebirthCount = 1 }))
			expect(result).to.be.near(1.35, 1e-9)
		end)
	end)

	describe("CanRebirth", function()
		it("should be false below the threshold", function()
			expect(GameLogic.CanRebirth(session({ score = 9999 }))).to.equal(false)
		end)

		it("should be true at or above the threshold", function()
			expect(GameLogic.CanRebirth(session({ score = 10000 }))).to.equal(true)
			expect(GameLogic.CanRebirth(session({ score = 15000 }))).to.equal(true)
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

	-- AutoClicker/MegaClicker Rate constants are per-minute (see GameLogic.lua),
	-- so these use a 60-second deltaTime to land on clean expected values.
	describe("CalculateIdleGain", function()
		it("should return 0 with no auto-clickers", function()
			expect(GameLogic.CalculateIdleGain(session(), 10)).to.equal(0)
		end)

		it("should scale with base auto-clickers over a minute", function()
			expect(GameLogic.CalculateIdleGain(session({ autoClickerCount = 5 }), 60)).to.equal(5)
		end)

		it("should weight Mega Auto-Clickers 10x a base auto-clicker over a minute", function()
			expect(GameLogic.CalculateIdleGain(session({ megaClickerCount = 1 }), 60)).to.equal(10)
		end)

		it("should combine both tiers and apply the multiplier over a minute", function()
			local result = GameLogic.CalculateIdleGain(
				session({ autoClickerCount = 2, megaClickerCount = 1, multiplierCount = 1 }),
				60
			)
			-- (2*1 + 1*10) * 1.1 = 13.2
			expect(result).to.be.near(13.2, 1e-9)
		end)
	end)
end
