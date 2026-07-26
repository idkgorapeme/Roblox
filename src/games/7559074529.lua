-- Squid Game X (game lobby)

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    local remotes = replicatedstorage:WaitForChild("Remotes")
    local gameStateUpdate = remotes:WaitForChild("GameStateUpdate")
    local requestShowAd = remotes:WaitForChild("RequestShowAdEvent")
    local adAnalytics = remotes:WaitForChild("AdAnalytics")

    env.AutoComplete = false
    env.AutoRevive = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autocomplete = setdata.autocomplete or false
    setdata.autorevive = setdata.autorevive or false
    setdata.finishpos = setdata.finishpos or "0, 0, 0"
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local finishPos = setdata.finishpos

    local function parsePos(str)
        local x, y, z = tostring(str):match("(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)")
        if not x then return nil end
        return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
    end

    local function teleportToFinish()
        local target = parsePos(finishPos)
        if not target then return end

        local char = plr.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        root.CFrame = CFrame.new(target)
        root.AssemblyLinearVelocity = Vector3.zero
    end

    elements:Textbox("Finish Position (X, Y, Z)", section, finishPos, function(v)
        finishPos = v
        env.setconfig("finishpos", v)
    end)

    -- listens for the server telling the client a gamemode started
    local acConn
    elements:Toggle("Auto Complete", section, setdata.autocomplete, function(v)
        env.AutoComplete = v
        env.setconfig("autocomplete", v)

        if acConn then
            acConn:Disconnect()
            acConn = nil
        end

        if not v then return end

        acConn = gameStateUpdate.OnClientEvent:Connect(function(state, gamemode)
            if not env.AutoComplete then return end
            if state ~= "StartGamemode" then return end
            if gamemode ~= "RedLightGreenLight" then return end

            task.wait(1)
            teleportToFinish()
        end)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(acConn)
        end
    end)

    local function revive()
        pcall(function()
            requestShowAd:InvokeServer("Revive")
        end)

        task.wait(1)

        pcall(function()
            adAnalytics:FireServer("Revive", true)
        end)
    end

    local arConn
    local function hookDeath(char)
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end

        if arConn then arConn:Disconnect() end
        arConn = hum.Died:Connect(function()
            if not env.AutoRevive then return end
            revive()
        end)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(arConn)
        end
    end

    local charConn
    elements:Toggle("Auto Revive", section, setdata.autorevive, function(v)
        env.AutoRevive = v
        env.setconfig("autorevive", v)

        if not v then
            if arConn then arConn:Disconnect() arConn = nil end
            if charConn then charConn:Disconnect() charConn = nil end
            return
        end

        if plr.Character then
            hookDeath(plr.Character)
        end

        charConn = plr.CharacterAdded:Connect(hookDeath)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(charConn)
        end
    end)

    elements:Button("Revive Now", section, function()
        revive()
    end)
end
