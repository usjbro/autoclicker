--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local LeaderboardManager = require(script.Parent:WaitForChild("LeaderboardManager"))

local ClickEvent = ReplicatedStorage:WaitForChild("ClickEvent")
local PurchaseEvent = ReplicatedStorage:WaitForChild("PurchaseEvent")
local SyncState = ReplicatedStorage:WaitForChild("SyncState")

-- State storage for active players
local activeSessions = {}

-- No character ever spawns (no fall, no health bar).
Players.CharacterAutoLoads = false

local function syncPlayer(player: Player)
	local session = activeSessions[player.UserId]
	if session then
		SyncState:FireClient(player, session)
	end
end

-- [SERVER] Handle Click
ClickEvent.OnServerEvent:Connect(function(player)
	local session = activeSessions[player.UserId]
	if not session then return end

	session.score += GameLogic.CalculateClickGain(session)
	syncPlayer(player)
end)

-- [SERVER] Handle Purchase
PurchaseEvent.OnServerEvent:Connect(function(player, upgradeId)
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

-- Player Lifecycle
Players.PlayerAdded:Connect(function(player)
	local data = DataManager.Load(player)
	activeSessions[player.UserId] = data
	syncPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local session = activeSessions[player.UserId]
	if session then
		DataManager.Save(player, session)
		LeaderboardManager.SaveScore(player, session.score)
		activeSessions[player.UserId] = nil
	end
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

-- Cosmetic: a large black box surrounds the fixed camera so the backdrop is
-- solid black instead of Roblox's default sky. Wrapped in pcall so a failure
-- here (e.g. an unsupported property) can never take down the gameplay
-- wiring above it.
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
end)
if not voidBoxOk then
	warn("Failed to create VoidBox backdrop: " .. tostring(voidBoxErr))
end

print("Autoclicker Server Initialized")
