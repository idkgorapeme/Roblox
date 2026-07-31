-- RNG Heroes

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    local function getRoot(character)
        if not character then return nil end
        return character:FindFirstChild("HumanoidRootPart")
    end

    env.AutoPrestige = false
    env.AutoClickAttack = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autoprestige = setdata.autoprestige or false
    setdata.autoclick = setdata.autoclick or false
    setdata.zone = setdata.zone or "Forest"
    setdata.attackid = setdata.attackid or 3
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local remotes = replicatedstorage:WaitForChild("Remotes")
    local prestigeRequested = remotes:WaitForChild("PrestigeRequested")
    local reportClickAttack = remotes:WaitForChild("ReportClickAttack")

    local zone = tostring(setdata.zone)
    local attackId = tonumber(setdata.attackid) or 3

    ----------------------------------------------------------------
    -- auto click attack
    ----------------------------------------------------------------

    -- enemies can be models, parts or a folder wrapping either
    local function enemyPosition(enemy)
        if enemy:IsA("BasePart") then
            return enemy.Position
        end

        if enemy:IsA("Model") then
            if enemy.PrimaryPart then
                return enemy.PrimaryPart.Position
            end

            local ok, cf = pcall(function()
                return enemy:GetPivot()
            end)
            if ok and cf then return cf.Position end
        end

        local part = enemy:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    elements:Textbox("Zone (default Forest)", section, zone, function(v)
        if not v or v == "" then return end
        zone = v
        env.setconfig("zone", v)
    end)

    elements:Textbox("Attack ID (default 3)", section, tostring(attackId), function(v)
        local n = tonumber(v)
        if not n then return end
        attackId = n
        env.setconfig("attackid", n)
    end)

    -- true when the enemy is still alive and rendered
    local function isAlive(enemy)
        if not enemy or not enemy.Parent then return false end

        local hum = enemy:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return false end

        local hp = enemy:GetAttribute("Health") or enemy:GetAttribute("HP")
        if hp and hp <= 0 then return false end

        return true
    end

    -- nearest living enemy to the character, so we commit to one target
    local function nearestEnemy()
        local folder = workspace:FindFirstChild("EnemyRender")
        if not folder then return nil end

        local root = getRoot(plr.Character)
        local origin = root and root.Position

        local best, bestPos, bestDist = nil, nil, math.huge

        for _, enemy in pairs(folder:GetChildren()) do
            if isAlive(enemy) then
                local pos = enemyPosition(enemy)
                if pos then
                    local dist = origin and (pos - origin).Magnitude or 0
                    if dist < bestDist then
                        best, bestPos, bestDist = enemy, pos, dist
                    end
                end
            end
        end

        return best, bestPos
    end

    elements:Toggle("Auto Click Attack", section, setdata.autoclick, function(v)
        env.AutoClickAttack = v
        env.setconfig("autoclick", v)
        if not v then return end

        task.spawn(function()
            local target, targetPos

            while env.AutoClickAttack do
                -- keep hitting the same enemy until it dies or despawns
                if not isAlive(target) then
                    target, targetPos = nearestEnemy()
                else
                    targetPos = enemyPosition(target) or targetPos
                end

                if target and targetPos then
                    -- one attack per frame, as fast as the game will accept
                    pcall(function()
                        reportClickAttack:FireServer(zone, attackId, targetPos)
                    end)

                    runservice.Heartbeat:Wait()
                else
                    -- nothing to hit, idle cheaply until an enemy renders
                    task.wait(0.2)
                end
            end
        end)
    end)

    elements:Toggle("Auto Prestige", section, setdata.autoprestige, function(v)
        env.AutoPrestige = v
        env.setconfig("autoprestige", v)
        if not v then return end

        while env.AutoPrestige do
            pcall(function()
                prestigeRequested:FireServer()
            end)

            task.wait(1)
        end
    end)
end
