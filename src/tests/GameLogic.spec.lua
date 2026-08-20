--!strict
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GameLogic = require(ReplicatedStorage.Shared.GameLogic)

	local function session(overrides: { [string]: any }?): GameLogic.Session
		-- Explicitly typed as GameLogic.Session (not inferred) so the dynamic
		-- overrides merge below doesn't widen equippedCosmetic's narrow
		-- "None" | "FlameTrail" | "LightTrail" union to a plain string --
		-- overrides' own values are `any` (keys are runtime strings, not
		-- literals, so they can't be typed narrower), and assigning an `any`
		-- into an inferred-typed table widens the whole table's type unless
		-- the target is already pinned. The `(base :: any)` cast on the
		-- assignment itself (not on `base`'s own declaration) is the same
		-- pattern GameHandlers.lua's applyInPlace already uses for the same
		-- reason: a dynamic-key write into a fixed-field record type.
		local base: GameLogic.Session = {
			score = 0,
			autoClickerCount = 0,
			megaClickerCount = 0,
			clickPowerCount = 0,
			multiplierCount = 0,
			rebirthCount = 0,
			totalClicks = 0,
			useBaseSpeed = true,
			speedSliderPercent = 100,
			ownedWings = false,
			ownedFlameTrail = false,
			ownedLightTrail = false,
			equippedCosmetic = "None",
			completedMazeNorth = false,
			completedMazeSouth = false,
			completedMazeEast = false,
			completedMazeWest = false,
		}
		for key, value in pairs(overrides or {}) do
			(base :: any)[key] = value
		end
		return base
	end

	describe("GetDefaultSession", function()
		it("should return the documented defaults", function()
			-- TestEZ (vendored, v0.4.1) has no built-in deep-equal matcher, so
			-- compare field by field, same as the equivalent Lune assertion in
			-- test/gameLogic.test.luau.
			local default = GameLogic.GetDefaultSession()
			for key, value in pairs(session()) do
				expect(default[key]).to.equal(value)
			end
		end)
	end)

	describe("ResetProgress", function()
		it("should zero score and upgrades but preserve clicks/rebirths/settings/items", function()
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
				ownedWings = true,
				ownedFlameTrail = true,
				equippedCosmetic = "FlameTrail",
				completedMazeNorth = true,
				completedMazeWest = true,
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
			-- Items are owned until rebirth, not wiped by an ordinary Reset --
			-- see PerformRebirth below, which does clear them.
			expect(after.ownedWings).to.equal(true)
			expect(after.ownedFlameTrail).to.equal(true)
			expect(after.equippedCosmetic).to.equal("FlameTrail")
			-- A maze completion bonus is a repeatable-per-run payoff (like an
			-- upgrade), not a permanent unlock (like totalClicks/rebirthCount) --
			-- see GameConstants.MAZE_GOALS's own comment.
			expect(after.completedMazeNorth).to.equal(false)
			expect(after.completedMazeWest).to.equal(false)
		end)
	end)

	describe("PerformRebirth", function()
		it("should reset progress, increment rebirthCount, and clear owned items", function()
			local before = session({
				score = 20000,
				autoClickerCount = 5,
				rebirthCount = 1,
				totalClicks = 100,
				ownedWings = true,
				ownedLightTrail = true,
				equippedCosmetic = "LightTrail",
				completedMazeEast = true,
			})
			local after = GameLogic.PerformRebirth(before)

			expect(after.score).to.equal(0)
			expect(after.autoClickerCount).to.equal(0)
			expect(after.totalClicks).to.equal(100)
			expect(after.rebirthCount).to.equal(2)
			expect(after.ownedWings).to.equal(false)
			expect(after.ownedLightTrail).to.equal(false)
			expect(after.equippedCosmetic).to.equal("None")
			expect(after.completedMazeEast).to.equal(false)
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
	describe("CalculateMazeBonusRate", function()
		it("should be 0 with no completed mazes", function()
			expect(GameLogic.CalculateMazeBonusRate(session())).to.equal(0)
		end)

		it("should return the matching reward for a single completed maze", function()
			expect(GameLogic.CalculateMazeBonusRate(session({ completedMazeNorth = true }))).to.equal(10)
			expect(GameLogic.CalculateMazeBonusRate(session({ completedMazeSouth = true }))).to.equal(20)
			expect(GameLogic.CalculateMazeBonusRate(session({ completedMazeEast = true }))).to.equal(100)
			expect(GameLogic.CalculateMazeBonusRate(session({ completedMazeWest = true }))).to.equal(100000)
		end)

		it("should sum rewards across multiple completed mazes", function()
			local result = GameLogic.CalculateMazeBonusRate(session({
				completedMazeNorth = true,
				completedMazeEast = true,
			}))
			expect(result).to.equal(110)
		end)
	end)

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

		it("should add completed-maze bonuses into the rate, subject to the same multiplier", function()
			local result = GameLogic.CalculateIdleGain(
				session({ completedMazeNorth = true, multiplierCount = 1 }),
				60
			)
			-- 10 * 1.1 = 11
			expect(result).to.be.near(11, 1e-9)
		end)
	end)
end
