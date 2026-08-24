--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

local WingsVisualSystem = {}

-- Every style's parts (both sides) live under one Folder on the character's
-- HumanoidRootPart -- clearing on re-equip/respawn is just destroying this
-- one Folder, rather than tracking a fixed list of individual instance
-- names the way CosmeticsSystem.lua has to (that file's trail/particle/
-- fire/light instances are named individually since they're not grouped
-- under a single container; wings don't need that since every wing part is
-- generated fresh from the same style table every time, nothing persists
-- individual identity across a re-equip).
local WINGS_FOLDER_NAME = "CosmeticWings"

-- Welds `part` rigidly onto `rootPart` at part's current CFrame (must be set
-- BEFORE calling this -- WeldConstraint locks in whatever relative offset
-- exists between the two parts at the moment it's created, so setting the
-- CFrame first is what determines the part's fixed position on the
-- character afterward). Every wing part goes through this, not just
-- Attachments (unlike CosmeticsSystem's trail, which only ever needs
-- Attachments -- a Trail's shape comes from Attachment motion history, but
-- a wing is real welded geometry).
local function weldPart(part: BasePart, rootPart: BasePart, folder: Folder)
	part.Anchored = false
	part.CanCollide = false
	part.CastShadow = false
	part.Locked = true
	part.Parent = folder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part
end

-- Classic Feathered: 5 layered feathers per side, fanning outward/upward
-- from a shoulder point, tapering shorter toward the outer edge. White/
-- cream with a thin gold Neon trim line per feather.
local function buildFeatheredSide(rootPart: BasePart, folder: Folder, side: number)
	local featherCount = 5
	for i = 1, featherCount do
		local t = (i - 1) / (featherCount - 1)
		local spreadDeg = 20 + t * 50
		local length = 2.2 - t * 0.6
		local localCFrame = CFrame.new(side * 0.3, 0.8, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))
			* CFrame.Angles(math.rad(-15 - t * 10), 0, 0)

		local feather = Instance.new("WedgePart")
		feather.Name = "Feather" .. i
		feather.Size = Vector3.new(0.15, 0.5, length)
		feather.Color = Color3.fromHex("f4f0e6")
		feather.Material = Enum.Material.SmoothPlastic
		feather.CFrame = rootPart.CFrame * localCFrame
		weldPart(feather, rootPart, folder)

		local trim = Instance.new("Part")
		trim.Name = "FeatherTrim" .. i
		trim.Size = Vector3.new(0.05, 0.05, length)
		trim.Color = Color3.fromHex("d4af37")
		trim.Material = Enum.Material.Neon
		trim.CFrame = feather.CFrame
		weldPart(trim, rootPart, folder)
	end
end

-- Voidtech: 3 angular blocky panels per side, glowing purple (#6c5ce7,
-- this game's own existing accent color) Neon seam line per panel.
local function buildVoidtechSide(rootPart: BasePart, folder: Folder, side: number)
	local panelCount = 3
	for i = 1, panelCount do
		local t = (i - 1) / (panelCount - 1)
		local spreadDeg = 15 + t * 45
		local length = 2.5 - t * 0.8
		local localCFrame = CFrame.new(side * 0.3, 0.9 - t * 0.3, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))

		local panelHeight = 0.9
		local panel = Instance.new("Part")
		panel.Name = "Panel" .. i
		panel.Size = Vector3.new(0.2, panelHeight, length)
		panel.Color = Color3.fromHex("1e1e2f")
		panel.Material = Enum.Material.SmoothPlastic
		panel.CFrame = rootPart.CFrame * localCFrame
		weldPart(panel, rootPart, folder)

		-- Sits flush on the panel's top edge -- derived from panelHeight
		-- (not a bare magic number) so it stays flush if panelHeight is
		-- ever retuned, same reasoning as buildDemonicSide's glow offset
		-- below being derived from its spine's length.
		local seam = Instance.new("Part")
		seam.Name = "PanelSeam" .. i
		seam.Size = Vector3.new(0.06, 0.06, length)
		seam.Color = Color3.fromHex("6c5ce7")
		seam.Material = Enum.Material.Neon
		seam.CFrame = panel.CFrame * CFrame.new(0, panelHeight / 2, 0)
		weldPart(seam, rootPart, folder)
	end
end

-- Dragon: a jagged fan of 4 dark wedges per side suggesting a solid
-- reptilian membrane -- deliberately a different silhouette/material from
-- Demonic below (solid wedges vs. sparse bone spines), not a recolor of
-- the same shape.
local function buildDragonSide(rootPart: BasePart, folder: Folder, side: number)
	local spineCount = 4
	for i = 1, spineCount do
		local t = (i - 1) / (spineCount - 1)
		local spreadDeg = 10 + t * 65
		local length = 1.8 + t * 1.4
		local localCFrame = CFrame.new(side * 0.3, 0.7, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))
			* CFrame.Angles(math.rad(-10 - t * 25), 0, 0)

		local spine = Instance.new("WedgePart")
		spine.Name = "MembraneSpine" .. i
		spine.Size = Vector3.new(0.12, 0.35, length)
		spine.Color = Color3.fromHex("3a0a0a")
		spine.Material = Enum.Material.SmoothPlastic
		spine.CFrame = rootPart.CFrame * localCFrame
		weldPart(spine, rootPart, folder)
	end
end

-- Demonic: 3 sparse bone spines per side (not a solid membrane, unlike
-- Dragon above), a glowing red Neon ball at each tip, and a stock
-- Instance.new("Fire") at each tip for trailing embers -- same stock
-- primitive CosmeticsSystem.lua's FlameTrail already relies on for exactly
-- this reason (no custom Texture/Image assets).
local function buildDemonicSide(rootPart: BasePart, folder: Folder, side: number)
	local spineCount = 3
	for i = 1, spineCount do
		local t = (i - 1) / (spineCount - 1)
		local spreadDeg = 15 + t * 60
		local length = 2.0 + t * 1.0
		local localCFrame = CFrame.new(side * 0.3, 0.75, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))
			* CFrame.Angles(math.rad(-15 - t * 20), 0, 0)

		local spine = Instance.new("Part")
		spine.Name = "BoneSpine" .. i
		spine.Size = Vector3.new(0.1, 0.1, length)
		spine.Color = Color3.fromHex("0d0d0d")
		spine.Material = Enum.Material.SmoothPlastic
		spine.CFrame = rootPart.CFrame * localCFrame
		weldPart(spine, rootPart, folder)

		local glow = Instance.new("Part")
		glow.Name = "BoneSpineGlow" .. i
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(0.15, 0.15, 0.15)
		glow.Color = Color3.fromHex("ff2222")
		glow.Material = Enum.Material.Neon
		glow.CFrame = spine.CFrame * CFrame.new(0, 0, -length / 2)
		weldPart(glow, rootPart, folder)

		local embers = Instance.new("Fire")
		embers.Name = "BoneSpineEmbers" .. i
		embers.Size = 1.2
		embers.Heat = 4
		embers.Parent = glow
	end
end

-- Fae: 2 small translucent lobes per side (4 total, dragonfly-style),
-- high transparency + Neon material for a delicate glowing look --
-- deliberately a different silhouette/material from the other 3 "big
-- bold wings" styles.
local function buildFaeSide(rootPart: BasePart, folder: Folder, side: number)
	local lobes = {
		{ y = 0.9, spreadDeg = 25, length = 1.1 },
		{ y = 0.5, spreadDeg = 45, length = 0.8 },
	}
	for i, lobe in ipairs(lobes) do
		local localCFrame = CFrame.new(side * 0.25, lobe.y, -0.2)
			* CFrame.Angles(0, 0, math.rad(side * lobe.spreadDeg))

		local panel = Instance.new("Part")
		panel.Name = "Lobe" .. i
		panel.Size = Vector3.new(0.03, 0.8, lobe.length)
		panel.Color = Color3.fromHex("a29bfe")
		panel.Material = Enum.Material.Neon
		panel.Transparency = 0.55
		panel.CFrame = rootPart.CFrame * localCFrame
		weldPart(panel, rootPart, folder)
	end
end

-- Dispatch table keyed by the same string union as Session.equippedWings
-- (minus "None", which correctly finds nothing and no-ops below) -- every
-- style builds both sides via one shared per-side function, mirrored by
-- sign (-1 left, 1 right), not five one-off left+right implementations.
local SIDE_BUILDERS: { [string]: (BasePart, Folder, number) -> () } = {
	Classic = buildFeatheredSide,
	Voidtech = buildVoidtechSide,
	Dragon = buildDragonSide,
	Demonic = buildDemonicSide,
	Fae = buildFaeSide,
}

local function clearWings(rootPart: BasePart)
	local existing = rootPart:FindFirstChild(WINGS_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Applies session.equippedWings to a player's current character, if any.
-- This is the only place wing geometry gets attached -- called from
-- CharacterAdded below, and directly from GameService.server.lua's
-- EquipWingsEvent handler and RebirthEvent's GameHandlers.HandleRebirth
-- orchestration (both already inside SessionStore.With) so an
-- already-spawned character updates immediately without needing to
-- respawn -- same pattern CosmeticsSystem.ApplyEquippedCosmetic already
-- establishes. PurchaseItemEvent does NOT call this -- buying a Wings
-- style doesn't auto-equip it, same as FlameTrail/LightTrail.
function WingsVisualSystem.ApplyEquippedWings(player: Player, session: GameLogic.Session)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return end

	clearWings(rootPart)

	local buildSide = SIDE_BUILDERS[session.equippedWings]
	if not buildSide then return end -- "None"

	local folder = Instance.new("Folder")
	folder.Name = WINGS_FOLDER_NAME
	folder.Parent = rootPart

	buildSide(rootPart, folder, -1)
	buildSide(rootPart, folder, 1)
end

-- Wings don't survive a respawn (a fresh character has no welded parts at
-- all), so reapply on every character (re)creation -- same pattern
-- CosmeticsSystem.Start/MovementSystem.Start already use.
function WingsVisualSystem.Start(sessionStore: SessionStoreModule)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local session = sessionStore.Peek(player.UserId)
			if session then
				WingsVisualSystem.ApplyEquippedWings(player, session)
			end
		end)
	end)
end

return WingsVisualSystem
