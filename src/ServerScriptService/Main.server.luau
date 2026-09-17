local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService:WaitForChild("Systems")

local PlayerState = require(Systems.PlayerState)
local MapManager = require(Systems.MapManager)
local AbilitySystem = require(Systems.AbilitySystem)
local CombatSystem = require(Systems.CombatSystem)
local RoundManager = require(Systems.RoundManager)

PlayerState.init()
MapManager.init()
AbilitySystem.init()
CombatSystem.init()
RoundManager.init()
