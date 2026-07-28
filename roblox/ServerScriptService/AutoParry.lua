-- AutoParry ModuleScript (ServerScriptService)
-- Place this ModuleScript into ServerScriptService and require it from your weapon/hit server code.

local AutoParry = {}
local Config = {
    ParryCooldown = 1.2,       -- seconds between parries per player
    MaxAngle = math.rad(60),   -- max facing angle (in radians) to auto-parry
    MaxDistance = 6,           -- max distance (studs) attacker -> victim to parry
    ParryChance = 1.0,         -- 0..1 chance to auto-parry when conditions met
    ParryStun = 0.45,          -- seconds to "stun" the attacker (slow them)
    StunWalkSpeed = 0,         -- walk speed while stunned
    MinHumanoidHealth = 0.0,   -- min relative health to allow parry (0 = no requirement)
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Expect a RemoteEvent named "ParryEvent" in ReplicatedStorage for FX notifications (client animations/sounds)
local ParryEvent = ReplicatedStorage:FindFirstChild("ParryEvent")
if not ParryEvent or not ParryEvent:IsA("RemoteEvent") then
    ParryEvent = nil
end

local cooldowns = {} -- map userId -> timestamp when available

local function restoreHumanoid(humanoid, origWalkSpeed, origJumpPower)
    if not humanoid or not humanoid.Parent then return end
    pcall(function()
        humanoid.WalkSpeed = origWalkSpeed
        if origJumpPower then humanoid.JumpPower = origJumpPower end
    end)
end

-- public: TryParry(victimPlayer, attackerPlayer)
-- returns: success (bool), reason (string)
function AutoParry.TryParry(victimPlayer, attackerPlayer)
    if not victimPlayer or not attackerPlayer then
        return false, "invalid-players"
    end
    if victimPlayer == attackerPlayer then
        return false, "same-player"
    end

    local now = tick()
    if cooldowns[victimPlayer.UserId] and now < cooldowns[victimPlayer.UserId] then
        return false, "on-cooldown"
    end

    local vChar = victimPlayer.Character
    local aChar = attackerPlayer.Character
    if not vChar or not aChar then
        return false, "missing-character"
    end

    local vRoot = vChar:FindFirstChild("HumanoidRootPart")
    local aRoot = aChar:FindFirstChild("HumanoidRootPart")
    local vHum = vChar:FindFirstChildOfClass("Humanoid")
    local aHum = aChar:FindFirstChildOfClass("Humanoid")
    if not vRoot or not aRoot or not vHum or not aHum then
        return false, "missing-parts"
    end

    -- Check optional toggle: BoolValue named "AutoParryEnabled" under Player or Character
    local autoParryFlag = vChar:FindFirstChild("AutoParryEnabled") or victimPlayer:FindFirstChild("AutoParryEnabled")
    if autoParryFlag and autoParryFlag:IsA("BoolValue") and autoParryFlag.Value == false then
        return false, "player-disabled"
    end

    -- distance check
    local dist = (aRoot.Position - vRoot.Position).Magnitude
    if dist > Config.MaxDistance then
        return false, "too-far"
    end

    -- facing check: victim must face attacker within Config.MaxAngle
    local vLook = vRoot.CFrame.LookVector
    local toAttacker = (aRoot.Position - vRoot.Position)
    if toAttacker.Magnitude == 0 then
        return false, "zero-distance"
    end
    local dir = toAttacker.Unit
    local dot = vLook:Dot(dir)
    local angle = math.acos(math.clamp(dot, -1, 1))
    if angle > Config.MaxAngle then
        return false, "wrong-angle"
    end

    -- optional health condition
    if Config.MinHumanoidHealth and vHum.Health and vHum.MaxHealth and vHum.MaxHealth > 0 then
        if (vHum.Health / vHum.MaxHealth) < Config.MinHumanoidHealth then
            return false, "low-health"
        end
    end

    -- chance roll
    if Config.ParryChance < 1 then
        if math.random() > Config.ParryChance then
            return false, "chance-failed"
        end
    end

    -- success: set cooldown
    cooldowns[victimPlayer.UserId] = now + Config.ParryCooldown

    -- apply stun effect to attacker: temporarily set WalkSpeed and JumpPower to configured values
    local origWalk = aHum.WalkSpeed
    local origJump = aHum.JumpPower
    pcall(function()
        aHum.WalkSpeed = Config.StunWalkSpeed
        if aHum.JumpPower ~= nil then aHum.JumpPower = 0 end
    end)

    spawn(function()
        wait(Config.ParryStun)
        restoreHumanoid(aHum, origWalk, origJump)
    end)

    -- Notify clients (victim and attacker) to play parry FX / animations
    if ParryEvent then
        pcall(function()
            ParryEvent:FireClient(victimPlayer, {role = "victim", attacker = attackerPlayer.UserId, pos = vRoot.Position})
        end)
        pcall(function()
            ParryEvent:FireClient(attackerPlayer, {role = "attacker", victim = victimPlayer.UserId, pos = aRoot.Position})
        end)
    end

    return true, "parried"
end

function AutoParry.IsOnCooldown(player)
    if not player then return false end
    local t = cooldowns[player.UserId]
    if not t then return false end
    return tick() < t
end

-- Optional: expose Config to allow runtime tuning via require
AutoParry.Config = Config

return AutoParry
