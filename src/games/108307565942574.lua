-- RNG Heroes

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.AutoPrestige = false
    env.AutoClickAttack = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autoprestige = setdata.autoprestige or false
    setdata.autoclick = setdata.autoclick or false
    setdata.zone = setdata.zone or "Forest"
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local remotes = replicatedstorage:WaitForChild("Remotes")
    local prestigeRequested = remotes:WaitForChild("PrestigeRequested")
    local reportClickAttack = remotes:WaitForChild("ReportClickAttack")

    local zone = tostring(setdata.zone)

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

    -- true when the enemy is still alive and rendered
    local function isAlive(enemy)
        if not enemy or not enemy.Parent then return false end

        local hum = enemy:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return false end

        local hp = enemy:GetAttribute("Health") or enemy:GetAttribute("HP")
        if hp and hp <= 0 then return false end

        return true
    end

    -- the second remote argument is the enemy id, so we sweep 1-10 to cover
    -- every enemy slot the zone can have.
    local ENEMY_IDS = 10

    -- tries to find the enemy that belongs to a given id, so each id gets its
    -- own position instead of everything being sent to one spot
    local function positionForId(id)
        local folder = workspace:FindFirstChild("EnemyRender")
        if not folder then return nil end

        local kids = folder:GetChildren()

        -- 1. an enemy literally named after the id
        local byName = folder:FindFirstChild(tostring(id))
        if byName and isAlive(byName) then
            return enemyPosition(byName)
        end

        -- 2. an id carrying attribute
        for _, enemy in pairs(kids) do
            if isAlive(enemy) then
                local eid = enemy:GetAttribute("Id")
                    or enemy:GetAttribute("EnemyId")
                    or enemy:GetAttribute("Index")
                if eid and tonumber(eid) == id then
                    return enemyPosition(enemy)
                end
            end
        end

        -- 3. fall back to the nth rendered enemy
        local nth = kids[id]
        if nth and isAlive(nth) then
            return enemyPosition(nth)
        end

        return nil
    end

    elements:Toggle("Auto Click Attack", section, setdata.autoclick, function(v)
        env.AutoClickAttack = v
        env.setconfig("autoclick", v)
        if not v then return end

        task.spawn(function()
            while env.AutoClickAttack do
                local folder = workspace:FindFirstChild("EnemyRender")

                if folder then
                    -- fire every enemy id in the same frame so all of them get hit
                    for id = 1, ENEMY_IDS do
                        task.spawn(function()
                            if not env.AutoClickAttack then return end

                            local pos = positionForId(id)
                            if not pos then return end

                            pcall(function()
                                reportClickAttack:FireServer(zone, id, pos)
                            end)
                        end)
                    end

                    runservice.Heartbeat:Wait()
                else
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
