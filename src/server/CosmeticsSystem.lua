--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

local CosmeticsSystem = {}

-- Fixed instance names so a re-apply (an equip change on an already-spawned
-- character, or a fresh respawn -- which has none of these anyway, but
-- clearing is still safe/cheap to call unconditionally) can find and remove
-- whatever was there before by name, rather than needing to track
-- references across a respawn. Three trail ribbons (not one) -- see
-- buildTrail's own comment for why a single flat Trail reads as a thin line
-- from most angles even at a wide WidthScale.
local RIBBON_NAMES = { "Left", "Center", "Right" }
local TAIL_ATTACHMENT_NAME = "CosmeticTrailTail" -- Fire/PointLight/ParticleEmitter all hang off this one
local FIRE_NAME = "CosmeticFire"
local LIGHT_NAME = "CosmeticLight"
local PARTICLE_NAME = "CosmeticParticle"

local function fixedInstanceNames(): { string }
	local names = { TAIL_ATTACHMENT_NAME, FIRE_NAME, LIGHT_NAME, PARTICLE_NAME }
	for _, ribbon in ipairs(RIBBON_NAMES) do
		table.insert(names, "CosmeticTrailTop" .. ribbon)
		table.insert(names, "CosmeticTrailBottom" .. ribbon)
		table.insert(names, "CosmeticTrail" .. ribbon)
	end
	return names
end

-- Removes any cosmetic trail/particle/fire/light instances from a
-- character's root part, if present.
local function clearCosmetic(rootPart: BasePart)
	for _, name in ipairs(fixedInstanceNames()) do
		local existing = rootPart:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

-- Requested: the trail should read as genuinely wide light/fire streaming
-- off the character, not a thin line -- researched real references (Sonic's
-- boost trail, the Flash's speedster aura) for what actually sells that:
-- both are wide, glowing streaks tapering toward the tail, not a flat
-- uniform-width ribbon. A single Trail is a flat 2D plane between two
-- Attachments -- wide numerically, but it can still read as thin from many
-- viewing angles. Three parallel ribbons (left/center/right, offset in
-- local X) plus FaceCamera on each is what actually reads as voluminous
-- regardless of angle, not a wider single plane alone.
local RIBBON_OFFSETS = { -0.7, 0, 0.7 } -- studs, local X, one per RIBBON_NAMES entry
local TRAIL_TOP_Y = 1.3
local TRAIL_BOTTOM_Y = -1.3
local TRAIL_BACK_Z = -1.0 -- further behind the character than a purely decorative trail needs, so it clearly streams off the back
local TRAIL_LIFETIME = 0.7

-- Tapers every ribbon from full width right at the character down to a
-- point at the tail -- the standard "speed streak" shape (see Trail's own
-- WidthScale docs) instead of a uniform-width ribbon throughout.
local TRAIL_WIDTH_SCALE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0),
})

local function buildTrailRibbons(rootPart: BasePart, colorSequence: ColorSequence)
	for i, ribbonName in ipairs(RIBBON_NAMES) do
		local offsetX = RIBBON_OFFSETS[i]

		local top = Instance.new("Attachment")
		top.Name = "CosmeticTrailTop" .. ribbonName
		top.Position = Vector3.new(offsetX, TRAIL_TOP_Y, TRAIL_BACK_Z)
		top.Parent = rootPart

		local bottom = Instance.new("Attachment")
		bottom.Name = "CosmeticTrailBottom" .. ribbonName
		bottom.Position = Vector3.new(offsetX, TRAIL_BOTTOM_Y, TRAIL_BACK_Z)
		bottom.Parent = rootPart

		local trail = Instance.new("Trail")
		trail.Name = "CosmeticTrail" .. ribbonName
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = colorSequence
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = TRAIL_WIDTH_SCALE
		trail.FaceCamera = true
		trail.Brightness = 3
		trail.Lifetime = TRAIL_LIFETIME
		trail.Parent = rootPart
	end
end

-- Builds the full cosmetic effect: three trail ribbons (see buildTrailRibbons
-- above) plus a single "tail" Attachment (centered, at the back-most/lowest
-- point) carrying a chaotic ParticleEmitter (both variants now, not just
-- flame -- embers for fire, sparkles for light), a stock Instance.new("Fire")
-- for the flame variant, and a PointLight so "light coming out of the back
-- of the character" is real illumination on nearby surfaces, not just an
-- emissive-looking material. Every effect here uses stock Roblox
-- defaults/built-ins only -- no custom Texture/Image assets, the same
-- constraint the client's nav buttons already work around with Unicode
-- glyphs instead of uploaded images, and HazardTrailSystem.lua's ground
-- trail already relies on for its own Fire instance.
local function buildTrail(rootPart: BasePart, colorSequence: ColorSequence, lightColor: Color3, withFlame: boolean)
	buildTrailRibbons(rootPart, colorSequence)

	local tail = Instance.new("Attachment")
	tail.Name = TAIL_ATTACHMENT_NAME
	tail.Position = Vector3.new(0, TRAIL_BOTTOM_Y, TRAIL_BACK_Z)
	tail.Parent = rootPart

	local particle = Instance.new("ParticleEmitter")
	particle.Name = PARTICLE_NAME
	particle.Color = colorSequence
	-- Grows over its lifetime (small near the character, large by the time
	-- it fades) rather than a fixed size -- mimics real fire/smoke
	-- expanding as it drifts, not a static sprite.
	particle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.8),
	})
	particle.Lifetime = NumberRange.new(0.4, 0.8)
	particle.Rate = 60
	particle.Speed = NumberRange.new(3, 6)
	particle.SpreadAngle = Vector2.new(25, 25)
	particle.LightEmission = 1
	particle.Parent = tail

	if withFlame then
		local fire = Instance.new("Fire")
		fire.Name = FIRE_NAME
		fire.Size = 4
		fire.Heat = 9
		fire.Parent = tail
	end

	local light = Instance.new("PointLight")
	light.Name = LIGHT_NAME
	light.Color = lightColor
	light.Brightness = 2.5
	light.Range = 14
	light.Parent = tail
end

-- Applies session.equippedCosmetic to a player's current character, if any.
-- This is the only place a cosmetic trail gets attached -- called from
-- CharacterAdded below, and directly from GameService.server.lua's
-- PurchaseItemEvent/EquipCosmeticEvent handlers (already inside
-- SessionStore.With) so an already-spawned character updates immediately
-- without needing to respawn.
function CosmeticsSystem.ApplyEquippedCosmetic(player: Player, session: GameLogic.Session)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return end

	clearCosmetic(rootPart)

	if session.equippedCosmetic == "FlameTrail" then
		buildTrail(rootPart, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("ffcc33")),
			ColorSequenceKeypoint.new(0.5, Color3.fromHex("ff6b1a")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("992200")),
		}), Color3.fromHex("ff8833"), true)
	elseif session.equippedCosmetic == "LightTrail" then
		buildTrail(rootPart, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("ffffff")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("6c5ce7")),
		}), Color3.fromHex("a29bfe"), false)
	end
end

-- A trail doesn't survive a respawn (a fresh character has no attachments
-- at all), so reapply it every time a character is (re)created -- same
-- pattern MovementSystem.Start uses for WalkSpeed.
function CosmeticsSystem.Start(sessionStore: SessionStoreModule)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local session = sessionStore.Peek(player.UserId)
			if session then
				CosmeticsSystem.ApplyEquippedCosmetic(player, session)
			end
		end)
	end)
end

return CosmeticsSystem
