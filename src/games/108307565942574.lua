-- RNG Heroes

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.AutoPrestige = false
    env.AutoClickAttack = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autoprestige = setdata.autoprestige or false
    setdata.autoclick = setdata.autoclick or false
    setdata.zone = setdata.zone or "Forest"
    setdata.attackid = setdata.attackid or 3
    setdata.clickdelay = setdata.clickdelay or 0.1
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local remotes = replicatedstorage:WaitForChild("Remotes")
    local prestigeRequested = remotes:WaitForChild("PrestigeRequested")
    local reportClickAttack = remotes:WaitForChild("ReportClickAttack")

    local zone = tostring(setdata.zone)
    local attackId = tonumber(setdata.attackid) or 3
    local clickDelay = tonumber(setdata.clickdelay) or 0.1

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

    elements:Textbox("Click Delay (default 0.1)", section, tostring(clickDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0 then return end
        clickDelay = n
        env.setconfig("clickdelay", n)
    end)

    elements:Toggle("Auto Click Attack", section, setdata.autoclick, function(v)
        env.AutoClickAttack = v
        env.setconfig("autoclick", v)
        if not v then return end

        while env.AutoClickAttack do
            pcall(function()
                local folder = workspace:FindFirstChild("EnemyRender")
                if not folder then return end

                for _, enemy in pairs(folder:GetChildren()) do
                    if not env.AutoClickAttack then return end

                    local pos = enemyPosition(enemy)
                    if pos then
                        pcall(function()
                            reportClickAttack:FireServer(zone, attackId, pos)
                        end)

                        task.wait(clickDelay)
                    end
                end
            end)

            task.wait(0.1)
        end
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
