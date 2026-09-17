local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local CombatController = {}

local localPlayer = Players.LocalPlayer
local ShootRequestRemote: RemoteEvent
local ShieldRequestRemote: RemoteEvent
local ShieldChangedRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local shieldStatus: string = Constants.SHIELD_READY
local lastShotAt = -math.huge

-- Public: the crosshair punch in CombatFeedbackController listens here.
local shotFiredEvent = Instance.new("BindableEvent")
CombatController.ShotFired = shotFiredEvent.Event

function CombatController.getShieldStatus(): string
	return shieldStatus
end

function CombatController.isCombatActive(): boolean
	if localState ~= Constants.STATE_SAFE then
		return false
	end
	return currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
end

local playerGui: PlayerGui
local container: GuiObject?
local fillBar: GuiObject?
local emptyOverlay: GuiObject?
local meterTween: Tween? = nil

local function resolveElements()
	if container and container.Parent then return end
	container = nil
	fillBar = nil
	emptyOverlay = nil

	if not playerGui then return end
	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return end

	local fm = gameGui:FindFirstChild("FuelMeter")
	if not fm or not fm:IsA("GuiObject") then return end
	container = fm

	local barBg = fm:FindFirstChild("BarBG")
	if not barBg then return end

	local fill = barBg:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		fillBar = fill
	end
	local overlay = barBg:FindFirstChild("EmptyOverlay")
	if overlay and overlay:IsA("GuiObject") then
		emptyOverlay = overlay
	end
end

local function cancelMeterTween()
	if not meterTween then return end
	meterTween:Cancel()
	meterTween = nil
end

local function tweenFill(targetScale: number, duration: number)
	if not fillBar then return end
	local tween = TweenService:Create(
		fillBar,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(targetScale, 1) }
	)
	meterTween = tween
	tween:Play()
end

local function applyShieldMeter(status: string, duration: number)
	resolveElements()
	cancelMeterTween()
	if not fillBar then return end

	if status == Constants.SHIELD_UP then
		fillBar.Size = UDim2.fromScale(1, 1)
		if emptyOverlay then emptyOverlay.Visible = false end
		if duration > 0 then
			tweenFill(0, duration)
		else
			fillBar.Size = UDim2.fromScale(0, 1)
		end
	elseif status == Constants.SHIELD_COOLDOWN_STATUS then
		fillBar.Size = UDim2.fromScale(0, 1)
		if emptyOverlay then emptyOverlay.Visible = true end
		if duration > 0 then
			tweenFill(1, duration)
		else
			fillBar.Size = UDim2.fromScale(1, 1)
		end
	else
		fillBar.Size = UDim2.fromScale(1, 1)
		if emptyOverlay then emptyOverlay.Visible = false end
	end
end

local function reconcileMeterVisibility()
	resolveElements()
	if not container then return end
	local visible = CombatController.isCombatActive()
	if container.Visible == visible then return end
	container.Visible = visible
end

local function getAimDirection(headPosition: Vector3): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * Constants.PISTOL_RANGE, params)
	local aimPoint = ray.Origin + ray.Direction * Constants.PISTOL_RANGE
	if result then
		aimPoint = result.Position
	end

	local offset = aimPoint - headPosition
	if offset.Magnitude < 0.001 then return nil end
	return offset.Unit
end

local function tryShoot()
	if localState ~= Constants.STATE_SAFE then return end
	if currentPhase ~= Constants.PHASE_ROUND then return end
	if shieldStatus == Constants.SHIELD_UP then return end

	local now = os.clock()
	if now - lastShotAt < Constants.PISTOL_COOLDOWN then return end

	local character = localPlayer.Character
	if not character then return end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local direction = getAimDirection(head.Position)
	if not direction then return end

	lastShotAt = now
	ShootRequestRemote:FireServer(head.Position, direction)
	shotFiredEvent:Fire()
end

local function tryToggleShield()
	if localState ~= Constants.STATE_SAFE then return end
	if currentPhase ~= Constants.PHASE_ROUND then return end

	if shieldStatus == Constants.SHIELD_READY then
		ShieldRequestRemote:FireServer(true)
	elseif shieldStatus == Constants.SHIELD_UP then
		ShieldRequestRemote:FireServer(false)
	end
end

function CombatController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	resolveElements()
	applyShieldMeter(Constants.SHIELD_READY, 0)
	if container then
		container.Visible = false
	end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShootRequestRemote = Remotes:WaitForChild("ShootRequest") :: RemoteEvent
	ShieldRequestRemote = Remotes:WaitForChild("ShieldRequest") :: RemoteEvent
	ShieldChangedRemote = Remotes:WaitForChild("ShieldChanged") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	ShieldChangedRemote.OnClientEvent:Connect(function(status: string, duration: number, _breaksInChain: number)
		shieldStatus = status
		applyShieldMeter(status, duration or 0)
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcileMeterVisibility()
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		reconcileMeterVisibility()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryShoot()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			tryToggleShield()
		end
	end)
end

return CombatController
