--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local SpeedCalculator = require(Shared:WaitForChild("SpeedCalculator"))

local ClickEvent = ReplicatedStorage:WaitForChild("ClickEvent")
local PurchaseEvent = ReplicatedStorage:WaitForChild("PurchaseEvent")
local ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent")
local RebirthEvent = ReplicatedStorage:WaitForChild("RebirthEvent")
local UpdateSpeedSettingsEvent = ReplicatedStorage:WaitForChild("UpdateSpeedSettingsEvent")
local SyncState = ReplicatedStorage:WaitForChild("SyncState")
local LeaderboardUpdate = ReplicatedStorage:WaitForChild("LeaderboardUpdate")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Characters spawn and walk around the void floor -- hide the default
-- health/backpack UI anyway since this game has no combat/damage and they'd
-- just be unused chrome over our custom GUI.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoclickerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local COLOR_BG = Color3.fromHex("1e1e2f")
local COLOR_PANEL = Color3.fromHex("2a2a3f")
local COLOR_ACCENT = Color3.fromHex("6c5ce7")
local COLOR_ACCENT_DISABLED = Color3.fromHex("444460")
local COLOR_TEXT = Color3.fromHex("f4f4f9")
local COLOR_TEXT_DIM = Color3.fromHex("9a9ab5")
local COLOR_NAV = Color3.fromHex("33333d") -- dark gray, matches the existing GUI's palette
local COLOR_MOVE = Color3.fromHex("2e86de") -- blue, distinguishes "Toggle Moving" from the nav stack
local COLOR_ROBUX = Color3.fromHex("2ecc71")

--------------------------------------------------------------------------------
-- Small reusable UI helpers (avoid repeating the same Instance boilerplate)
--------------------------------------------------------------------------------

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addListLayout(instance: Instance, padding: number, horizontalAlign: Enum.HorizontalAlignment?, fillDirection: Enum.FillDirection?)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = horizontalAlign or Enum.HorizontalAlignment.Center
	layout.FillDirection = fillDirection or Enum.FillDirection.Vertical
	layout.Parent = instance
	return layout
end

local function addPadding(instance: Instance, amount: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, amount)
	padding.PaddingBottom = UDim.new(0, amount)
	padding.PaddingLeft = UDim.new(0, amount)
	padding.PaddingRight = UDim.new(0, amount)
	padding.Parent = instance
	return padding
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, order: number, bold: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Font = if bold then Enum.Font.SourceSansBold else Enum.Font.SourceSans
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, size: UDim2, color: Color3, order: number?): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.Font = Enum.Font.SourceSans
	button.TextSize = 15
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = color
	button.Size = size
	button.BorderSizePixel = 0
	if order then
		button.LayoutOrder = order
	end
	button.Parent = parent
	addCorner(button, 8)
	return button
end

--------------------------------------------------------------------------------
-- Bottom-right navigation: 3 stacked icon buttons + a separate blue "Toggle
-- Moving" button. UIListLayout + AnchorPoint (not hardcoded pixel math) so
-- this holds up across screen sizes.
--------------------------------------------------------------------------------

local navContainer = Instance.new("Frame")
navContainer.Name = "NavContainer"
navContainer.AutomaticSize = Enum.AutomaticSize.Y
navContainer.Size = UDim2.new(0, 64, 0, 0)
navContainer.Position = UDim2.new(1, -20, 1, -20)
navContainer.AnchorPoint = Vector2.new(1, 1)
navContainer.BackgroundTransparency = 1
navContainer.Parent = screenGui
addListLayout(navContainer, 10)

local toggleMovingButton = Instance.new("TextButton")
toggleMovingButton.Name = "ToggleMovingButton"
toggleMovingButton.Text = "🏃"
toggleMovingButton.Font = Enum.Font.SourceSansBold
toggleMovingButton.TextSize = 26
toggleMovingButton.TextColor3 = Color3.new(1, 1, 1)
toggleMovingButton.BackgroundColor3 = COLOR_MOVE
toggleMovingButton.Size = UDim2.new(0, 56, 0, 56)
toggleMovingButton.BorderSizePixel = 0
toggleMovingButton.LayoutOrder = 1
toggleMovingButton.Parent = navContainer
addCorner(toggleMovingButton, 12)

local function addNavButton(icon: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Text = icon
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 26
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = COLOR_NAV
	button.Size = UDim2.new(0, 56, 0, 56)
	button.BorderSizePixel = 0
	button.LayoutOrder = order
	button.Parent = navContainer
	addCorner(button, 12)

	local hoverColor = Color3.fromHex("44444f")
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = hoverColor
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = COLOR_NAV
	end)

	return button
end

local mainNavButton = addNavButton("🖱️", 2)
local shopNavButton = addNavButton("🛒", 3)
local settingsNavButton = addNavButton("⚙️", 4)

--------------------------------------------------------------------------------
-- Leaderboard panel (top-right, always on except during Movement mode)
--------------------------------------------------------------------------------

local LEADERBOARD_ROW_COUNT = 10

local leaderboardPanel = Instance.new("Frame")
leaderboardPanel.Name = "LeaderboardPanel"
leaderboardPanel.AutomaticSize = Enum.AutomaticSize.Y
leaderboardPanel.Size = UDim2.new(0, 240, 0, 0)
leaderboardPanel.Position = UDim2.new(1, -20, 0, 20)
leaderboardPanel.AnchorPoint = Vector2.new(1, 0)
leaderboardPanel.BackgroundColor3 = COLOR_BG
leaderboardPanel.BorderSizePixel = 0
leaderboardPanel.Parent = screenGui
addCorner(leaderboardPanel, 12)
addListLayout(leaderboardPanel, 4)
addPadding(leaderboardPanel, 12)

makeLabel(leaderboardPanel, "Leaderboard", 18, COLOR_TEXT, 0, true)

local leaderboardRows = {}
for i = 1, LEADERBOARD_ROW_COUNT do
	local row = makeLabel(leaderboardPanel, "", 13, COLOR_TEXT_DIM, i)
	row.Visible = false
	table.insert(leaderboardRows, row)
end

LeaderboardUpdate.OnClientEvent:Connect(function(entries)
	for i, row in ipairs(leaderboardRows) do
		local entry = entries[i]
		if entry then
			row.Text = ("%d. %s -- %s pts, %s clicks"):format(
				i, entry.username, NumberFormat.Format(entry.score), NumberFormat.Format(entry.totalClicks)
			)
			row.Visible = true
		else
			row.Visible = false
		end
	end
end)

--------------------------------------------------------------------------------
-- Clicker screen: Score/Rate/Total Clicks/Rebirths + the Click button
--------------------------------------------------------------------------------

local clickerPanel = Instance.new("Frame")
clickerPanel.Name = "ClickerPanel"
clickerPanel.AutomaticSize = Enum.AutomaticSize.Y
clickerPanel.Size = UDim2.new(0, 300, 0, 0)
clickerPanel.Position = UDim2.new(0.5, 0, 0, 20)
clickerPanel.AnchorPoint = Vector2.new(0.5, 0)
clickerPanel.BackgroundColor3 = COLOR_BG
clickerPanel.BorderSizePixel = 0
clickerPanel.Parent = screenGui
addCorner(clickerPanel, 12)
addListLayout(clickerPanel, 8)
addPadding(clickerPanel, 16)

local scoreLabel = makeLabel(clickerPanel, "Score: 0", 24, COLOR_TEXT, 1, true)
local rateLabel = makeLabel(clickerPanel, "+0/min", 15, COLOR_TEXT_DIM, 2)
local totalClicksLabel = makeLabel(clickerPanel, "Total Clicks: 0", 15, COLOR_TEXT_DIM, 3)
local rebirthsLabel = makeLabel(clickerPanel, "Rebirths: 0", 15, COLOR_TEXT_DIM, 4)
for _, label in ipairs({ scoreLabel, rateLabel, totalClicksLabel, rebirthsLabel }) do
	label.TextXAlignment = Enum.TextXAlignment.Center
end

local clickButton = Instance.new("TextButton")
clickButton.Name = "ClickButton"
clickButton.Text = "Click me!"
clickButton.Font = Enum.Font.SourceSansBold
clickButton.TextSize = 26
clickButton.TextColor3 = Color3.new(1, 1, 1)
clickButton.BackgroundColor3 = COLOR_ACCENT
clickButton.Size = UDim2.new(0, 220, 0, 70)
clickButton.BorderSizePixel = 0
clickButton.LayoutOrder = 5
clickButton.Parent = clickerPanel
addCorner(clickButton, 8)

--------------------------------------------------------------------------------
-- Shop screen: upgrade cards (name, description, level, pts + Robux cost) + Rebirth
--------------------------------------------------------------------------------

local function createPopupWindow(name: string, title: string): (Frame, Frame)
	local window = Instance.new("Frame")
	window.Name = name
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.Size = UDim2.new(0, 360, 0, 0)
	window.Position = UDim2.new(0.5, 0, 0.5, 0)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = COLOR_BG
	window.BorderSizePixel = 0
	window.Visible = false
	window.Parent = screenGui
	addCorner(window, 12)
	addListLayout(window, 12)
	addPadding(window, 20)

	makeLabel(window, title, 26, COLOR_TEXT, 1, true).TextXAlignment = Enum.TextXAlignment.Center

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, -40, 0, 0)
	content.BackgroundTransparency = 1
	content.LayoutOrder = 2
	content.Parent = window
	addListLayout(content, 8)

	return window, content
end

local shopWindow, shopContent = createPopupWindow("ShopWindow", "Shop")
local settingsWindow, settingsContent = createPopupWindow("SettingsWindow", "Settings")

local UPGRADE_DISPLAY = {
	{ Id = "AutoClicker", Name = "Auto-Clicker", Effect = "+1/min", Description = "Automatically earns points over time." },
	{ Id = "MegaClicker", Name = "Mega Auto-Clicker", Effect = "+10/min", Description = "A stronger automatic earner." },
	{ Id = "ClickPower", Name = "Click Power", Effect = "+1/click", Description = "Increases points earned per click." },
	{ Id = "Multiplier", Name = "Global Multiplier", Effect = "+10% income", Description = "Boosts all income by a percentage." },
}

local shopRows = {}

for i, upgrade in ipairs(UPGRADE_DISPLAY) do
	local upgradeConstants = GameConstants.UPGRADES[upgrade.Id]
	local cost = GameLogic.GetUpgradeCost(upgrade.Id)

	local card = Instance.new("Frame")
	card.Name = upgrade.Id .. "Card"
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.BackgroundColor3 = COLOR_PANEL
	card.BorderSizePixel = 0
	card.LayoutOrder = i
	card.Parent = shopContent
	addCorner(card, 10)
	addListLayout(card, 4)
	addPadding(card, 10)

	makeLabel(card, ("%s (%s)"):format(upgrade.Name, upgrade.Effect), 16, COLOR_TEXT, 1, true)
	makeLabel(card, upgrade.Description, 13, COLOR_TEXT_DIM, 2)
	local levelLabel = makeLabel(card, "Level: 0", 14, COLOR_TEXT, 3)

	local buttonsRow = Instance.new("Frame")
	buttonsRow.AutomaticSize = Enum.AutomaticSize.Y
	buttonsRow.Size = UDim2.new(1, 0, 0, 36)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.LayoutOrder = 4
	buttonsRow.Parent = card
	addListLayout(buttonsRow, 8, Enum.HorizontalAlignment.Left, Enum.FillDirection.Horizontal)

	local ptsButton = makeButton(buttonsRow, ("Upgrade -- %s pts"):format(NumberFormat.Format(cost)), UDim2.new(0, 150, 0, 36), COLOR_ACCENT)

	local hasDevProduct = upgradeConstants.DevProductId ~= 0
	local robuxButton = makeButton(
		buttonsRow,
		if hasDevProduct then "R$ " .. upgradeConstants.RobuxCost else "Coming soon",
		UDim2.new(0, 150, 0, 36),
		if hasDevProduct then COLOR_ROBUX else COLOR_ACCENT_DISABLED
	)
	robuxButton.AutoButtonColor = hasDevProduct
	robuxButton.Active = hasDevProduct

	ptsButton.MouseButton1Click:Connect(function()
		PurchaseEvent:FireServer(upgrade.Id)
	end)

	if hasDevProduct then
		robuxButton.MouseButton1Click:Connect(function()
			MarketplaceService:PromptProductPurchase(player, upgradeConstants.DevProductId)
		end)
	end

	table.insert(shopRows, {
		Field = GameConstants.UPGRADE_FIELDS[upgrade.Id],
		Cost = cost,
		PtsButton = ptsButton,
		LevelLabel = levelLabel,
	})
end

-- Rebirth card
local rebirthCard = Instance.new("Frame")
rebirthCard.Name = "RebirthCard"
rebirthCard.AutomaticSize = Enum.AutomaticSize.Y
rebirthCard.Size = UDim2.new(1, 0, 0, 0)
rebirthCard.BackgroundColor3 = COLOR_PANEL
rebirthCard.BorderSizePixel = 0
rebirthCard.LayoutOrder = #UPGRADE_DISPLAY + 1
rebirthCard.Parent = shopContent
addCorner(rebirthCard, 10)
addListLayout(rebirthCard, 4)
addPadding(rebirthCard, 10)

makeLabel(rebirthCard, ("Rebirth (+%d%% permanent income)"):format(GameConstants.REBIRTH.Bonus * 100), 16, COLOR_TEXT, 1, true)
makeLabel(rebirthCard, "Resets score and upgrades for a permanent bonus.", 13, COLOR_TEXT_DIM, 2)

local rebirthButton = makeButton(rebirthCard, "Rebirth -- requires " .. NumberFormat.Format(GameConstants.REBIRTH.Threshold) .. " score", UDim2.new(1, 0, 0, 36), COLOR_ACCENT_DISABLED, 3)
rebirthButton.AutoButtonColor = false

rebirthButton.MouseButton1Click:Connect(function()
	RebirthEvent:FireServer()
end)

--------------------------------------------------------------------------------
-- Settings screen: Reset Progress + movement speed controls
--------------------------------------------------------------------------------

local resetButton = makeButton(settingsContent, "Reset Progress", UDim2.new(1, 0, 0, 44), Color3.fromHex("3a3a52"), 1)
resetButton.MouseButton1Click:Connect(function()
	ResetEvent:FireServer()
end)

makeLabel(settingsContent, "Movement Speed", 18, COLOR_TEXT, 2, true)

local speedModeRow = Instance.new("Frame")
speedModeRow.AutomaticSize = Enum.AutomaticSize.Y
speedModeRow.Size = UDim2.new(1, 0, 0, 40)
speedModeRow.BackgroundTransparency = 1
speedModeRow.LayoutOrder = 3
speedModeRow.Parent = settingsContent
addListLayout(speedModeRow, 8, Enum.HorizontalAlignment.Left, Enum.FillDirection.Horizontal)

local normalSpeedButton = makeButton(speedModeRow, "Normal Speed", UDim2.new(0, 150, 0, 40), COLOR_ACCENT)
local clickBasedSpeedButton = makeButton(speedModeRow, "Click-Based Speed", UDim2.new(0, 150, 0, 40), COLOR_PANEL)

local currentSpeedLabel = makeLabel(settingsContent, ("Current speed: %d"):format(SpeedCalculator.BASE_WALK_SPEED), 14, COLOR_TEXT_DIM, 4)

-- Custom slider: Roblox has no built-in slider control. Track + draggable
-- handle, percent clamped [0, 100], never exceeds the calculated max speed
-- because CalculateEffectiveSpeed (server-side, authoritative) interpolates
-- between base and max by this percent.
local sliderTrack = Instance.new("Frame")
sliderTrack.Size = UDim2.new(1, 0, 0, 10)
sliderTrack.BackgroundColor3 = COLOR_PANEL
sliderTrack.BorderSizePixel = 0
sliderTrack.LayoutOrder = 5
sliderTrack.Parent = settingsContent
addCorner(sliderTrack, 5)

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(0, 0, 1, 0)
sliderFill.BackgroundColor3 = COLOR_ACCENT
sliderFill.BorderSizePixel = 0
sliderFill.Parent = sliderTrack
addCorner(sliderFill, 5)

local sliderHandle = Instance.new("Frame")
sliderHandle.Size = UDim2.new(0, 18, 0, 18)
sliderHandle.AnchorPoint = Vector2.new(0.5, 0.5)
sliderHandle.Position = UDim2.new(0, 0, 0.5, 0)
sliderHandle.BackgroundColor3 = Color3.new(1, 1, 1)
sliderHandle.BorderSizePixel = 0
sliderHandle.ZIndex = 2
sliderHandle.Parent = sliderTrack
addCorner(sliderHandle, 9)

local sliderPercent = 100
local function setSliderVisual(percent: number)
	sliderFill.Size = UDim2.new(percent / 100, 0, 1, 0)
	sliderHandle.Position = UDim2.new(percent / 100, 0, 0.5, 0)
end
setSliderVisual(sliderPercent)

local useBaseSpeed = true

-- Tracks the last slider value sent to the server that hasn't been confirmed
-- back via SyncState yet, so a stale sync (e.g. the idle-gain tick) can't
-- clobber a just-released drag before the server has processed it.
local pendingSliderPercent: number? = nil

local function sendSpeedSettings()
	pendingSliderPercent = sliderPercent
	UpdateSpeedSettingsEvent:FireServer(useBaseSpeed, sliderPercent)
end

local function setSpeedMode(base: boolean)
	useBaseSpeed = base
	normalSpeedButton.BackgroundColor3 = if base then COLOR_ACCENT else COLOR_PANEL
	clickBasedSpeedButton.BackgroundColor3 = if base then COLOR_PANEL else COLOR_ACCENT
	sendSpeedSettings()
end

normalSpeedButton.MouseButton1Click:Connect(function()
	setSpeedMode(true)
end)
clickBasedSpeedButton.MouseButton1Click:Connect(function()
	setSpeedMode(false)
end)

local draggingSlider = false

local function updateSliderFromInput(inputPosition: Vector2)
	local trackPos = sliderTrack.AbsolutePosition.X
	local trackWidth = sliderTrack.AbsoluteSize.X
	if trackWidth <= 0 then return end

	local relative = (inputPosition.X - trackPos) / trackWidth
	relative = math.clamp(relative, 0, 1)
	sliderPercent = math.floor(relative * 100 + 0.5)
	setSliderVisual(sliderPercent)
end

sliderHandle.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingSlider = true
		pendingSliderPercent = nil
	end
end)

sliderTrack.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingSlider = true
		pendingSliderPercent = nil
		updateSliderFromInput(input.Position)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not draggingSlider then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		updateSliderFromInput(input.Position)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not draggingSlider then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingSlider = false
		sendSpeedSettings()
	end
end)

--------------------------------------------------------------------------------
-- Movement mode overlay: top stats bar + left-side return button
--------------------------------------------------------------------------------

local movementTopBar = Instance.new("Frame")
movementTopBar.Name = "MovementTopBar"
movementTopBar.AutomaticSize = Enum.AutomaticSize.Y
movementTopBar.Size = UDim2.new(0, 260, 0, 0)
movementTopBar.Position = UDim2.new(0.5, 0, 0, 20)
movementTopBar.AnchorPoint = Vector2.new(0.5, 0)
movementTopBar.BackgroundColor3 = COLOR_BG
movementTopBar.BorderSizePixel = 0
movementTopBar.Visible = false
movementTopBar.Parent = screenGui
addCorner(movementTopBar, 12)
addListLayout(movementTopBar, 4)
addPadding(movementTopBar, 12)

local movementScoreLabel = makeLabel(movementTopBar, "Score: 0", 18, COLOR_TEXT, 1, true)
local movementClicksLabel = makeLabel(movementTopBar, "Total Clicks: 0", 14, COLOR_TEXT_DIM, 2)
movementScoreLabel.TextXAlignment = Enum.TextXAlignment.Center
movementClicksLabel.TextXAlignment = Enum.TextXAlignment.Center

local movementReturnButton = Instance.new("TextButton")
movementReturnButton.Name = "MovementReturnButton"
movementReturnButton.Text = "< Return to GUI"
movementReturnButton.Font = Enum.Font.SourceSansBold
movementReturnButton.TextSize = 16
movementReturnButton.TextColor3 = Color3.new(1, 1, 1)
movementReturnButton.BackgroundColor3 = COLOR_ACCENT
movementReturnButton.Size = UDim2.new(0, 170, 0, 48)
movementReturnButton.Position = UDim2.new(0, 20, 0.5, 0)
movementReturnButton.AnchorPoint = Vector2.new(0, 0.5)
movementReturnButton.BorderSizePixel = 0
movementReturnButton.Visible = false
movementReturnButton.Parent = screenGui
addCorner(movementReturnButton, 10)

--------------------------------------------------------------------------------
-- GUI state machine: exactly one of Clicker/Shop/Settings is visible, or
-- Movement mode hides all of them for an unobstructed view of the map.
--------------------------------------------------------------------------------

type Screen = "Clicker" | "Shop" | "Settings" | "Movement"
local currentScreen: Screen = "Clicker"

local function setScreen(screen: Screen)
	currentScreen = screen

	clickerPanel.Visible = screen == "Clicker"
	shopWindow.Visible = screen == "Shop"
	settingsWindow.Visible = screen == "Settings"

	local inMovement = screen == "Movement"
	navContainer.Visible = not inMovement
	leaderboardPanel.Visible = not inMovement
	movementTopBar.Visible = inMovement
	movementReturnButton.Visible = inMovement
end

setScreen("Clicker")

mainNavButton.MouseButton1Click:Connect(function()
	setScreen("Clicker")
end)

shopNavButton.MouseButton1Click:Connect(function()
	setScreen(if currentScreen == "Shop" then "Clicker" else "Shop")
end)

settingsNavButton.MouseButton1Click:Connect(function()
	setScreen(if currentScreen == "Settings" then "Clicker" else "Settings")
end)

toggleMovingButton.MouseButton1Click:Connect(function()
	setScreen("Movement")
end)

movementReturnButton.MouseButton1Click:Connect(function()
	setScreen("Clicker")
end)

--------------------------------------------------------------------------------
-- Click input + animation
--------------------------------------------------------------------------------

-- Always tweens relative to the button's fixed original size (never its
-- current, possibly-already-shrunk size), so rapid overlapping clicks can't
-- compound and leave the button permanently smaller.
local clickButtonOriginalSize = clickButton.Size

local function animateClick(btn: GuiButton, originalSize: UDim2)
	local shrunkSize = UDim2.new(
		originalSize.X.Scale, originalSize.X.Offset * 0.96,
		originalSize.Y.Scale, originalSize.Y.Offset * 0.96
	)
	TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = shrunkSize
	}):Play()
	task.delay(0.05, function()
		TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = originalSize
		}):Play()
	end)
end

local function registerClick()
	ClickEvent:FireServer()
	animateClick(clickButton, clickButtonOriginalSize)
end

clickButton.MouseButton1Click:Connect(registerClick)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Space and currentScreen == "Clicker" then
		registerClick()
	end
end)

--------------------------------------------------------------------------------
-- Sync State
--------------------------------------------------------------------------------

SyncState.OnClientEvent:Connect(function(state: GameLogic.Session)
	local scoreText = "Score: " .. NumberFormat.Format(state.score)
	scoreLabel.Text = scoreText
	movementScoreLabel.Text = scoreText

	local clicksText = "Total Clicks: " .. NumberFormat.Format(state.totalClicks)
	totalClicksLabel.Text = clicksText
	movementClicksLabel.Text = clicksText

	rebirthsLabel.Text = "Rebirths: " .. NumberFormat.Format(state.rebirthCount)

	local rate = GameLogic.CalculateIdleGain(state, 60)
	rateLabel.Text = ("+%s/min"):format(NumberFormat.Format(rate))

	local clickGain = GameLogic.CalculateClickGain(state)
	clickButton.Text = ("Click me! (+%s)"):format(NumberFormat.Format(clickGain))

	for _, row in ipairs(shopRows) do
		local owned = state[row.Field]
		row.LevelLabel.Text = "Level: " .. owned

		if state.score < row.Cost then
			row.PtsButton.BackgroundColor3 = COLOR_ACCENT_DISABLED
			row.PtsButton.AutoButtonColor = false
		else
			row.PtsButton.BackgroundColor3 = COLOR_ACCENT
			row.PtsButton.AutoButtonColor = true
		end
	end

	if GameLogic.CanRebirth(state) then
		rebirthButton.Text = "Rebirth now!"
		rebirthButton.BackgroundColor3 = COLOR_ACCENT
		rebirthButton.AutoButtonColor = true
	else
		rebirthButton.Text = "Rebirth -- requires " .. NumberFormat.Format(GameConstants.REBIRTH.Threshold) .. " score"
		rebirthButton.BackgroundColor3 = COLOR_ACCENT_DISABLED
		rebirthButton.AutoButtonColor = false
	end

	-- Settings screen reflects the server-authoritative values, not local drag state.
	useBaseSpeed = state.useBaseSpeed
	normalSpeedButton.BackgroundColor3 = if useBaseSpeed then COLOR_ACCENT else COLOR_PANEL
	clickBasedSpeedButton.BackgroundColor3 = if useBaseSpeed then COLOR_PANEL else COLOR_ACCENT
	-- Skip overwriting the displayed value while actively dragging, or while a
	-- locally-sent value hasn't round-tripped back yet (avoids the handle
	-- visibly snapping back to a stale pre-drag value then jumping forward
	-- again once the real update arrives).
	if not draggingSlider and (pendingSliderPercent == nil or state.speedSliderPercent == pendingSliderPercent) then
		sliderPercent = state.speedSliderPercent
		setSliderVisual(sliderPercent)
		pendingSliderPercent = nil
	end
	currentSpeedLabel.Text = ("Current speed: %d (max %d)"):format(
		math.floor(SpeedCalculator.CalculateEffectiveSpeed(state) + 0.5),
		math.floor(SpeedCalculator.CalculateMaxSpeed(state.totalClicks) + 0.5)
	)
end)

print("Autoclicker Client Initialized")
