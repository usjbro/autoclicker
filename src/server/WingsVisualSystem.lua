--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local WingsGeometry = require(Shared:WaitForChild("WingsGeometry"))
local Players = game:GetService("Players")
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

local WingsVisualSystem = {}

-- Wings are a real Roblox Accessory, not a set of parts hand-welded onto
-- HumanoidRootPart -- Humanoid:AddAccessory positions/orients the whole
-- assembly by aligning Handle's own "BodyBackAttachment" Attachment with
-- the matching one Roblox puts on every avatar's torso (UpperTorso on R15,
-- Torso on R6), which is the standard, robust way to attach a back-worn
-- item and avoids hand-rolling that alignment via manual CFrame math on a
-- moving, respawning character.
--
-- One Accessory *template* per style is built once, at server startup,
-- and parented under ReplicatedStorage.WingsTemplates (see buildTemplates
-- below) -- ApplyEquippedWings never constructs geometry itself, it just
-- Clone()s the matching template and calls Humanoid:AddAccessory. This
-- keeps equip/respawn cheap (one Clone vs. dozens of Instance.new +
-- WeldConstraint calls) and gives every wing style a single, inspectable
-- source of truth in ReplicatedStorage rather than rebuilding it from
-- scratch every time.
local WINGS_TEMPLATES_FOLDER_NAME = "WingsTemplates"

-- Name given to the LIVE clone attached to a character -- deliberately
-- distinct from the per-style template names in WINGS_TEMPLATES_FOLDER_NAME
-- (e.g. "Voidtech") so clearWings can find-and-destroy the equipped
-- instance on a character without colliding with the template names.
local WINGS_ACCESSORY_NAME = "CosmeticWings"

-- Every avatar (R15 or R6) has a BodyBackAttachment on its torso-equivalent
-- part by default -- check both names since this game doesn't force a
-- RigType and either could show up depending on the player's avatar.
local function findBackAttachment(character: Model): Attachment?
	for _, torsoName in { "UpperTorso", "Torso" } do
		local torso = character:FindFirstChild(torsoName)
		if torso and torso:IsA("BasePart") then
			local attachment = torso:FindFirstChild("BodyBackAttachment")
			if attachment and attachment:IsA("Attachment") then
				return attachment
			end
		end
	end
	return nil
end

-- Welds `part` rigidly onto `handle` at part's current CFrame (must be set
-- BEFORE calling this, relative to handle's own local origin -- see each
-- buildXSide function below). Built while the whole Accessory is still
-- unparented from the character; the WeldConstraint's locked-in relative
-- offset stays correct once Humanoid:AddAccessory later repositions Handle
-- onto the character's back, since a WeldConstraint holds a *relative*
-- transform regardless of how either part is subsequently moved -- and
-- Instance:Clone() correctly remaps a WeldConstraint's Part0/Part1 to the
-- cloned instances as long as both are descendants of what's being cloned,
-- which they are here (both under the same Accessory).
local function weldPart(part: BasePart, handle: BasePart, accessory: Accessory)
	part.Anchored = false
	part.CanCollide = false
	part.CastShadow = false
	part.Locked = true
	part.Parent = accessory

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

-- Every offset below is relative to Handle's own local origin, which
-- Humanoid:AddAccessory aligns exactly with BodyBackAttachment's world
-- CFrame -- i.e. local (0,0,0) sits right at the back of the torso. This
-- does NOT match HumanoidRootPart's own raw axis convention (front="-Z",
-- see FlightSystem.lua's CFrame.LookVector) -- BodyBackAttachment carries
-- its own authored orientation, confirmed empirically (RGB axis-marker
-- beams welded to Handle, screenshotted in Studio once actually attached
-- to a character) to be: +Y is up (same as expected), +Z is LATERAL
-- (left/right across the back, not front/back), and +X is DEPTH
-- (front/back, not left/right). A rotation therefore needs to happen
-- around X (mixes Y/Z, i.e. up<->lateral) to fan a wing outward to the
-- side, not around Z as a naive port of HumanoidRootPart-relative math
-- would assume -- that was the root cause of wings previously towering
-- above the character's head instead of spreading across the back.
--
-- DEPTH_SIGN below is the one piece we could NOT confirm from the axis
-- markers (they only proved the local Y/Z/X *roles*, not which literal
-- sign of X points away from the chest vs. into it) -- if wings render
-- embedded in the character's chest instead of hugging their back, flip
-- this single constant.
local DEPTH_SIGN = 1

-- Every style's wing pieces fan from "pointing straight up" (spreadDeg=0,
-- folded close against the back) toward "pointing straight lateral"
-- (spreadDeg=90, fully spread) as spreadDeg increases, mirrored by side.
-- Built as an explicit direction blend + CFrame.lookAt, not a chained
-- CFrame.Angles(spread,0,0) rotation -- an earlier version of this file
-- used the latter and, verified by hand (matrix derivation, not guessed):
-- swapping which axis a rotation applies to is an orientation-reversing
-- transformation (S*Rz(t)*S = Rx(-t), not Rx(t)), so porting the old
-- Z-axis rotation to X with an unchanged sign quietly inverted the
-- result -- outer, high-spreadDeg feathers ended up drooping toward the
-- ground instead of fanning outward. Directly specifying the intended
-- blend sidesteps that whole class of rotation-sign mistake. The blend
-- itself (WingsGeometry.FanDirection) lives in src/shared/ specifically
-- so it's headlessly testable under Lune (test/wingsGeometry.test.luau)
-- -- this exact class of math has already shipped one real sign bug, and
-- a test is what actually prevents the next one, not another comment.
local function fanCFrame(handle: BasePart, side: number, spreadDeg: number, rootOffset: Vector3): CFrame
	local x, y, z = WingsGeometry.FanDirection(spreadDeg, side)
	local lengthDirection = Vector3.new(x, y, z)
	-- CFrame.lookAt points local -Z at the target, so passing
	-- -lengthDirection makes local +Z (every part in this file's own
	-- "length" axis, via Size.Z) align with lengthDirection instead.
	-- lengthDirection only ever has Y/Z components by construction, so
	-- local +X (depth) is always a safe, never-parallel up-hint -- BUT
	-- verified by hand (the vector triple-product identity, cross-checked
	-- numerically): because it's *exactly* perpendicular to lengthDirection
	-- (not just non-parallel), CFrame.lookAt's resulting local +Y ends up
	-- pinned to exactly this up-hint (0,0,pinned to world depth) regardless
	-- of spreadDeg/side, while local +X is what actually sweeps through the
	-- fan arc -- the reverse of what the naming suggests. Every part built
	-- from this CFrame therefore puts its BROAD dimension on Size.X (the
	-- sweeping axis, so it stays visible face-on as the wing fans) and its
	-- THIN dimension on Size.Y (the pinned-to-depth axis, where staying
	-- thin doesn't matter) -- swapped from the more "obvious" X=thickness/
	-- Y=height assignment, which would instead present each piece edge-on
	-- at high spreadDeg (the same "reads as a thin line" defect this
	-- codebase already fixed once for FlameTrail/LightTrail).
	local orientation = CFrame.lookAt(Vector3.new(), -lengthDirection, Vector3.new(1, 0, 0))
	return handle.CFrame * CFrame.new(rootOffset) * orientation
end

-- Classic Feathered: 5 layered feathers per side, fanning outward/upward
-- from a shoulder point, tapering shorter toward the outer edge. White/
-- cream with a thin gold Neon trim line per feather.
local function buildFeatheredSide(handle: BasePart, accessory: Accessory, side: number)
	local featherCount = 5
	for i = 1, featherCount do
		local t = (i - 1) / (featherCount - 1)
		local spreadDeg = 20 + t * 50
		local length = 2.2 - t * 0.6
		-- Depth grows with t (outer feathers sit slightly further back) --
		-- restores some of the per-feather graduated variation the old,
		-- ambiguous-sign pitch rotation used to give, via a translation
		-- along DEPTH_SIGN's already-confirmed axis instead of another
		-- rotation whose sign would need re-verifying.
		local rootOffset = Vector3.new((0.15 + t * 0.15) * DEPTH_SIGN, 0.3, side * 0.3)
		local baseCFrame = fanCFrame(handle, side, spreadDeg, rootOffset)

		local feather = Instance.new("WedgePart")
		feather.Name = "Feather" .. i
		-- Broad dimension (0.5) on X (sweeps with the fan), thin (0.15) on
		-- Y (pinned to depth) -- see fanCFrame's own comment on why. Note
		-- WedgePart's taper (full Size.Y at one Z end, down to 0 at the
		-- other) always runs along Y regardless of which value is bigger --
		-- that's an engine-fixed property of WedgePart, not something this
		-- swap changes, and it predates this swap (Y was already the
		-- depth-pinned axis before it). The swap only fixes the separate,
		-- already-confirmed silhouette-width issue (X facing the camera).
		feather.Size = Vector3.new(0.5, 0.15, length)
		feather.Color = Color3.fromHex("f4f0e6")
		feather.Material = Enum.Material.SmoothPlastic
		feather.CFrame = baseCFrame
		weldPart(feather, handle, accessory)

		local trim = Instance.new("Part")
		trim.Name = "FeatherTrim" .. i
		trim.Size = Vector3.new(0.05, 0.05, length)
		trim.Color = Color3.fromHex("d4af37")
		trim.Material = Enum.Material.Neon
		trim.CFrame = feather.CFrame
		weldPart(trim, handle, accessory)
	end
end

-- Voidtech: 3 angular blocky panels per side, glowing purple (#6c5ce7,
-- this game's own existing accent color) Neon seam line per panel.
local function buildVoidtechSide(handle: BasePart, accessory: Accessory, side: number)
	local panelCount = 3
	for i = 1, panelCount do
		local t = (i - 1) / (panelCount - 1)
		local spreadDeg = 15 + t * 45
		local length = 2.5 - t * 0.8
		local rootOffset = Vector3.new(0.15 * DEPTH_SIGN, 0.35 - t * 0.3, side * 0.3)
		local baseCFrame = fanCFrame(handle, side, spreadDeg, rootOffset)

		-- Broad dimension (panelHeight) on X (sweeps with the fan), thin
		-- (0.2) on Y (pinned to depth) -- see fanCFrame's own comment on
		-- why.
		local panelHeight = 0.9
		local panel = Instance.new("Part")
		panel.Name = "Panel" .. i
		panel.Size = Vector3.new(panelHeight, 0.2, length)
		panel.Color = Color3.fromHex("1e1e2f")
		panel.Material = Enum.Material.SmoothPlastic
		panel.CFrame = baseCFrame
		weldPart(panel, handle, accessory)

		-- Sits flush on the panel's broad (X) edge -- derived from
		-- panelHeight (not a bare magic number) so it stays flush if
		-- panelHeight is ever retuned, same reasoning as buildDemonicSide's
		-- glow offset below being derived from its spine's length.
		local seam = Instance.new("Part")
		seam.Name = "PanelSeam" .. i
		seam.Size = Vector3.new(0.06, 0.06, length)
		seam.Color = Color3.fromHex("6c5ce7")
		seam.Material = Enum.Material.Neon
		seam.CFrame = panel.CFrame * CFrame.new(panelHeight / 2, 0, 0)
		weldPart(seam, handle, accessory)
	end
end

-- Dragon: a jagged fan of 4 dark wedges per side suggesting a solid
-- reptilian membrane -- deliberately a different silhouette/material from
-- Demonic below (solid wedges vs. sparse bone spines), not a recolor of
-- the same shape.
local function buildDragonSide(handle: BasePart, accessory: Accessory, side: number)
	local spineCount = 4
	for i = 1, spineCount do
		local t = (i - 1) / (spineCount - 1)
		local spreadDeg = 10 + t * 65
		local length = 1.8 + t * 1.4
		-- See buildFeatheredSide's identical comment -- depth grows with
		-- t to restore per-spine variation without a rotation sign guess.
		local rootOffset = Vector3.new((0.15 + t * 0.15) * DEPTH_SIGN, 0.25, side * 0.3)
		local baseCFrame = fanCFrame(handle, side, spreadDeg, rootOffset)

		-- Broad dimension (0.35) on X (sweeps with the fan), thin (0.12)
		-- on Y (pinned to depth) -- see fanCFrame's own comment on why, and
		-- buildFeatheredSide's comment on WedgePart's Y-locked taper.
		local spine = Instance.new("WedgePart")
		spine.Name = "MembraneSpine" .. i
		spine.Size = Vector3.new(0.35, 0.12, length)
		spine.Color = Color3.fromHex("3a0a0a")
		spine.Material = Enum.Material.SmoothPlastic
		spine.CFrame = baseCFrame
		weldPart(spine, handle, accessory)
	end
end

-- Demonic: 3 sparse bone spines per side (not a solid membrane, unlike
-- Dragon above), a glowing red Neon ball at each tip, and a stock
-- Instance.new("Fire") at each tip for trailing embers -- same stock
-- primitive CosmeticsSystem.lua's FlameTrail already relies on for exactly
-- this reason (no custom Texture/Image assets).
local function buildDemonicSide(handle: BasePart, accessory: Accessory, side: number)
	local spineCount = 3
	for i = 1, spineCount do
		local t = (i - 1) / (spineCount - 1)
		local spreadDeg = 15 + t * 60
		local length = 2.0 + t * 1.0
		-- See buildFeatheredSide's identical comment -- depth grows with
		-- t to restore per-spine variation without a rotation sign guess.
		local rootOffset = Vector3.new((0.15 + t * 0.15) * DEPTH_SIGN, 0.3, side * 0.3)
		local baseCFrame = fanCFrame(handle, side, spreadDeg, rootOffset)

		-- Square cross-section (0.1, 0.1) -- no broad/thin swap needed here,
		-- unlike the other styles' fanCFrame-oriented pieces.
		local spine = Instance.new("Part")
		spine.Name = "BoneSpine" .. i
		spine.Size = Vector3.new(0.1, 0.1, length)
		spine.Color = Color3.fromHex("0d0d0d")
		spine.Material = Enum.Material.SmoothPlastic
		spine.CFrame = baseCFrame
		weldPart(spine, handle, accessory)

		-- +length/2 is now unambiguous: fanCFrame builds the spine's own
		-- local +Z to point exactly along its outward/upward fan
		-- direction (see fanCFrame's own comment), so translating along
		-- it reaches the visible tip, not a guessed sign.
		local glow = Instance.new("Part")
		glow.Name = "BoneSpineGlow" .. i
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(0.15, 0.15, 0.15)
		glow.Color = Color3.fromHex("ff2222")
		glow.Material = Enum.Material.Neon
		glow.CFrame = spine.CFrame * CFrame.new(0, 0, length / 2)
		weldPart(glow, handle, accessory)

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
local function buildFaeSide(handle: BasePart, accessory: Accessory, side: number)
	local lobes = {
		{ y = 0.35, spreadDeg = 25, length = 1.1 },
		{ y = 0.1, spreadDeg = 45, length = 0.8 },
	}
	for i, lobe in ipairs(lobes) do
		local rootOffset = Vector3.new(0.1 * DEPTH_SIGN, lobe.y, side * 0.25)
		local baseCFrame = fanCFrame(handle, side, lobe.spreadDeg, rootOffset)

		-- Broad dimension (0.8) on X (sweeps with the fan), thin (0.03)
		-- on Y (pinned to depth) -- see fanCFrame's own comment on why.
		local panel = Instance.new("Part")
		panel.Name = "Lobe" .. i
		panel.Size = Vector3.new(0.8, 0.03, lobe.length)
		panel.Color = Color3.fromHex("a29bfe")
		panel.Material = Enum.Material.Neon
		panel.Transparency = 0.55
		panel.CFrame = baseCFrame
		weldPart(panel, handle, accessory)
	end
end

-- Dispatch table keyed by the same string union as Session.equippedWings
-- (minus "None", which correctly finds nothing and no-ops below) -- every
-- style builds both sides via one shared per-side function, mirrored by
-- sign (-1 left, 1 right), not five one-off left+right implementations.
local SIDE_BUILDERS: { [string]: (BasePart, Accessory, number) -> () } = {
	Classic = buildFeatheredSide,
	Voidtech = buildVoidtechSide,
	Dragon = buildDragonSide,
	Demonic = buildDemonicSide,
	Fae = buildFaeSide,
}

local function clearWings(character: Model)
	local existing = character:FindFirstChild(WINGS_ACCESSORY_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Builds the full Accessory (Handle + both sides' geometry) for a style,
-- entirely unparented from the character -- Humanoid:AddAccessory is what
-- actually attaches it, so nothing here needs the character's real
-- position/orientation. Handle's own Attachment is named "BodyBackAttachment"
-- to match the target on the character's torso (see findBackAttachment) --
-- Roblox's AddAccessory matches Handle's attachment to a body attachment
-- by name, then rigidly repositions Handle (and everything welded to it)
-- so the two coincide. Called once per style by buildTemplates below, not
-- per equip -- ApplyEquippedWings clones the resulting template instead.
local function buildWingsAccessory(buildSide: (BasePart, Accessory, number) -> ()): Accessory
	local accessory = Instance.new("Accessory")
	accessory.AccessoryType = Enum.AccessoryType.Back

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CastShadow = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = accessory

	local attachment = Instance.new("Attachment")
	attachment.Name = "BodyBackAttachment"
	attachment.Parent = handle

	-- Load-bearing: every buildXSide function computes `handle.CFrame *
	-- localCFrame`, which only equals `localCFrame` (the intended
	-- Handle-relative offset) because handle.CFrame is identity here.
	-- Humanoid:AddAccessory (called on a *clone* of this template, from
	-- ApplyEquippedWings) is what later moves Handle onto the character's
	-- actual back -- doing that before this point would shift every part's
	-- placement.
	buildSide(handle, accessory, -1)
	buildSide(handle, accessory, 1)

	return accessory
end

-- Per-style templates, keyed the same way as SIDE_BUILDERS -- built once
-- by buildTemplates (called from Start below) and cloned by
-- ApplyEquippedWings on every equip/respawn, rather than reconstructing
-- dozens of parts from scratch each time.
local wingsTemplates: { [string]: Accessory } = {}

-- Builds one Accessory template per style and parents them under
-- ReplicatedStorage.WingsTemplates -- a single, inspectable source of
-- truth for every wing style's geometry, visible in Studio's Explorer
-- like any other asset, rather than geometry that only exists transiently
-- on whichever characters currently have it equipped.
local function buildTemplates()
	local folder = Instance.new("Folder")
	folder.Name = WINGS_TEMPLATES_FOLDER_NAME
	folder.Parent = ReplicatedStorage

	for styleName, buildSide in pairs(SIDE_BUILDERS) do
		local template = buildWingsAccessory(buildSide)
		template.Name = styleName
		template.Parent = folder
		wingsTemplates[styleName] = template
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

	local template = wingsTemplates[session.equippedWings]
	if template then
		-- Checked BEFORE clearWings below -- a character whose Humanoid or
		-- BodyBackAttachment isn't ready yet (e.g. CharacterAdded firing
		-- before body parts finish replicating, or a non-standard rig)
		-- must not have its existing wings torn off with nothing to
		-- replace them; better to leave the stale-but-visible wings in
		-- place than to leave the player wearing nothing.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local backAttachment = findBackAttachment(character)
		if not humanoid or not backAttachment then
			warn(("WingsVisualSystem: couldn't apply %s wings for %s -- missing %s"):format(
				session.equippedWings,
				player.Name,
				if not humanoid then "Humanoid" else "BodyBackAttachment"
			))
			return
		end

		clearWings(character)
		local clone = template:Clone()
		clone.Name = WINGS_ACCESSORY_NAME
		local ok, err = pcall(function()
			humanoid:AddAccessory(clone)
		end)
		if not ok then
			-- AddAccessory is an engine API call (unlike the plain
			-- Instance.new/WeldConstraint calls building the template
			-- used, neither of which could throw) -- this can be called
			-- from inside GameHandlers.HandleRebirth's orchestration
			-- (before saveScore/sync/saveSession run), so an uncaught
			-- error here would abort the rest of that rebirth, not just
			-- the wings render.
			warn(("WingsVisualSystem: AddAccessory failed for %s -- %s"):format(player.Name, tostring(err)))
			clone:Destroy()
		end
	else -- "None", or (defensively) an unrecognized style
		clearWings(character)
	end
end

-- Wings don't survive a respawn (a fresh character has no accessory at
-- all), so reapply on every character (re)creation -- same pattern
-- CosmeticsSystem.Start/MovementSystem.Start already use.
function WingsVisualSystem.Start(sessionStore: SessionStoreModule)
	-- pcall-wrapped so a failure building templates (e.g. a future edit to
	-- one of the buildXSide functions) can't take down the rest of
	-- GameService.server.lua's initialization -- same reasoning
	-- MapBuilder.Build() is pcall-wrapped for (see its own comment): an
	-- unprotected throw here would propagate out of this call and abort
	-- whatever runs after it in GameService.server.lua (HazardTrailSystem.
	-- Start included), not just leave wings broken. wingsTemplates simply
	-- stays empty on failure, so ApplyEquippedWings degrades to a no-op
	-- (clearWings) rather than crashing anything downstream.
	local ok, err = pcall(function()
		buildTemplates()
	end)
	if not ok then
		warn("WingsVisualSystem: failed to build wing templates: " .. tostring(err))
	end

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
