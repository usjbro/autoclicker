--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local LeaderboardManager = require(script.Parent:WaitForChild("LeaderboardManager"))
local RobuxPurchaseManager = require(script.Parent:WaitForChild("RobuxPurchaseManager"))
local MovementSystem = require(script.Parent:WaitForChild("MovementSystem"))
local SessionLock = require(script.Parent:WaitForChild("SessionLock"))

local ClickEvent = ReplicatedStorage:WaitForChild("ClickEvent")
local PurchaseEvent = ReplicatedStorage:WaitForChild("PurchaseEvent")
local ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent")
local RebirthEvent = ReplicatedStorage:WaitForChild("RebirthEvent")
local UpdateSpeedSettingsEvent = ReplicatedStorage:WaitForChild("UpdateSpeedSettingsEvent")
local SyncState = ReplicatedStorage:WaitForChild("SyncState")

-- State storage for active players
local activeSessions = {}

-- Environment: a large black box encloses the whole play space so the
-- backdrop is solid black instead of Roblox's default sky, with a floor and
-- SpawnLocation inside it for characters to spawn and walk on. Set up before
-- any Player connections below so a joining player can never spawn before
-- the floor exists. Wrapped in pcall so a failure here (e.g. an unsupported
-- property) can never take down the gameplay wiring that follows.
local voidBoxOk, voidBoxErr = pcall(function()
	local voidBox = Instance.new("Part")
	voidBox.Name = "VoidBox"
	voidBox.Size = Vector3.new(4000, 4000, 4000)
	voidBox.CFrame = CFrame.new(0, 0, 0)
	voidBox.Anchored = true
	voidBox.CanCollide = false
	voidBox.CastShadow = false
	voidBox.Material = Enum.Material.SmoothPlastic
	voidBox.Color = Color3.new(0, 0, 0)
	voidBox.Locked = true
	voidBox.Parent = workspace

	local floor = Instance.new("Part")
	floor.Name = "VoidFloor"
	floor.Size = Vector3.new(4000, 4, 4000)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Anchored = true
	floor.CanCollide = true
	floor.CastShadow = false
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.new(0, 0, 0)
	floor.Locked = true
	floor.Parent = workspace

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "VoidSpawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.CFrame = CFrame.new(0, 1, 0)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = true
	spawnLocation.CastShadow = false
	spawnLocation.Material = Enum.Material.SmoothPlastic
	spawnLocation.Color = Color3.new(0, 0, 0)
	spawnLocation.Transparency = 1
	spawnLocation.Locked = true
	spawnLocation.Parent = workspace
end)
if not voidBoxOk then
	warn("Failed to create void environment: " .. tostring(voidBoxErr))
end

local function syncPlayer(player: Player)
	local session = activeSessions[player.UserId]
	if session then
		SyncState:FireClient(player, session)
	end
end

-- Copies every field from newValues into session in place, rather than
-- replacing activeSessions[userId] with a new table outright. Other code
-- (e.g. RobuxPurchaseManager) can hold a reference to a player's session
-- across a yield; replacing the table wholesale would silently orphan that
-- reference from a concurrent Reset/Rebirth.
local function applyInPlace(session: GameLogic.Session, newValues: GameLogic.Session)
	for key, value in pairs(newValues) do
		(session :: any)[key] = value
	end
end

-- Every handler below that touches a player's session is routed through
-- SessionLock, since several of these can yield on a DataStore call
-- mid-operation (Save, in particular) -- without this, e.g. a Reset could
-- zero a session's fields while PlayerRemoving's save for that same player
-- is still in flight, or a disconnect could race a purchase.

-- [SERVER] Handle Click
ClickEvent.OnServerEvent:Connect(function(player)
	SessionLock.Run(player.UserId, function()
		local session = activeSessions[player.UserId]
		if not session then return end

		session.score += GameLogic.CalculateClickGain(session)
		session.totalClicks += 1
		MovementSystem.ApplyEffectiveSpeed(player, session)
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle Purchase
PurchaseEvent.OnServerEvent:Connect(function(player, upgradeId)
	SessionLock.Run(player.UserId, function()
		local session = activeSessions[player.UserId]
		if not session then return end

		if typeof(upgradeId) ~= "string" then return end
		local field = GameConstants.UPGRADE_FIELDS[upgradeId]
		if not field then return end

		local cost = GameLogic.GetUpgradeCost(upgradeId)
		if session.score >= cost then
			session.score -= cost
			session[field] += 1
			syncPlayer(player)
		end
	end)
end)

-- [SERVER] Handle Reset
ResetEvent.OnServerEvent:Connect(function(player)
	SessionLock.Run(player.UserId, function()
		local session = activeSessions[player.UserId]
		if not session then return end

		applyInPlace(session, GameLogic.ResetProgress(session))
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle Rebirth
RebirthEvent.OnServerEvent:Connect(function(player)
	SessionLock.Run(player.UserId, function()
		local session = activeSessions[player.UserId]
		if not session then return end

		if not GameLogic.CanRebirth(session) then return end

		applyInPlace(session, GameLogic.PerformRebirth(session))
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle speed preference changes. The client only ever sends a
-- preference (base speed on/off, slider percent) -- the actual WalkSpeed is
-- always recomputed server-side via MovementSystem, never taken from the client.
UpdateSpeedSettingsEvent.OnServerEvent:Connect(function(player, useBaseSpeed, speedSliderPercent)
	SessionLock.Run(player.UserId, function()
		local session = activeSessions[player.UserId]
		if not session then return end

		if typeof(useBaseSpeed) == "boolean" then
			session.useBaseSpeed = useBaseSpeed
		end

		if typeof(speedSliderPercent) == "number" and speedSliderPercent == speedSliderPercent then
			session.speedSliderPercent = math.clamp(speedSliderPercent, 0, 100)
		end

		MovementSystem.ApplyEffectiveSpeed(player, session)
		syncPlayer(player)
	end)
end)

-- Player Lifecycle
Players.PlayerAdded:Connect(function(player)
	local data = DataManager.Load(player)
	SessionLock.Run(player.UserId, function()
		activeSessions[player.UserId] = data
		-- Covers the case where the character already spawned (default
		-- WalkSpeed) before DataManager.Load finished; MovementSystem.Start's
		-- CharacterAdded hook covers every subsequent (re)spawn.
		MovementSystem.ApplyEffectiveSpeed(player, data)
		syncPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	SessionLock.Run(player.UserId, function()
		local session = activeSessions[player.UserId]
		if session then
			DataManager.Save(player, session)
			LeaderboardManager.SaveScore(player, session.score)
			activeSessions[player.UserId] = nil
		end
	end)
end)

-- Game Loop (Auto-clickers)
task.spawn(function()
	while true do
		local deltaTime = task.wait(GameConstants.TICK_RATE)
		for userId, session in pairs(activeSessions) do
			if session.autoClickerCount > 0 or session.megaClickerCount > 0 then
				local gain = GameLogic.CalculateIdleGain(session, deltaTime)
				session.score += gain
				
				local player = Players:GetPlayerByUserId(userId)
				if player then
					syncPlayer(player)
				end
			end
		end
	end
end)

-- Start Global Leaderboard Manager
LeaderboardManager.Start(function()
	return activeSessions
end)

-- Start Robux Purchase Manager
RobuxPurchaseManager.Start(function()
	return activeSessions
end, syncPlayer)

-- Start Movement System (re-applies WalkSpeed on every character (re)spawn)
MovementSystem.Start(function()
	return activeSessions
end)

print("Autoclicker Server Initialized")
