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
-- references across a respawn.
local ATTACHMENT_TOP_NAME = "CosmeticTrailTop"
local ATTACHMENT_BOTTOM_NAME = "CosmeticTrailBottom"
local TRAIL_NAME = "CosmeticTrail"
local PARTICLE_NAME = "CosmeticParticle"

-- Removes any cosmetic trail/particle instances from a character's root
-- part, if present.
local function clearCosmetic(rootPart: BasePart)
	for _, name in ipairs({ ATTACHMENT_TOP_NAME, ATTACHMENT_BOTTOM_NAME, TRAIL_NAME, PARTICLE_NAME }) do
		local existing = rootPart:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

-- Builds a Trail (optionally with a ParticleEmitter, for the flame variant)
-- between two Attachments on the character's HumanoidRootPart, offset
-- vertically and slightly behind so it streams out behind the character as
-- they move. Both use stock Roblox defaults -- no custom Texture/Image
-- assets, the same constraint the client's nav buttons already work around
-- with Unicode glyphs instead of uploaded images.
local function buildTrail(rootPart: BasePart, colorSequence: ColorSequence, withFlame: boolean)
	local top = Instance.new("Attachment")
	top.Name = ATTACHMENT_TOP_NAME
	top.Position = Vector3.new(0, 1, -0.5)
	top.Parent = rootPart

	local bottom = Instance.new("Attachment")
	bottom.Name = ATTACHMENT_BOTTOM_NAME
	bottom.Position = Vector3.new(0, -1, -0.5)
	bottom.Parent = rootPart

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = colorSequence
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.6
	trail.Parent = rootPart

	if withFlame then
		local particle = Instance.new("ParticleEmitter")
		particle.Name = PARTICLE_NAME
		particle.Color = colorSequence
		particle.Size = NumberSequence.new(0.6)
		particle.Lifetime = NumberRange.new(0.3, 0.6)
		particle.Rate = 40
		particle.Speed = NumberRange.new(2, 4)
		particle.SpreadAngle = Vector2.new(15, 15)
		particle.Parent = top
	end
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
		}), true)
	elseif session.equippedCosmetic == "LightTrail" then
		buildTrail(rootPart, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("ffffff")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("6c5ce7")),
		}), false)
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
