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

    -- where Auto Complete drops you when a round starts
    local FINISH_POS = Vector3.new(-12200, -790, -2984)

    env.AutoComplete = false
    env.AutoRevive = false
    env.Kill = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autocomplete = setdata.autocomplete or false
    setdata.autorevive = setdata.autorevive or false
    setdata.kill = setdata.kill or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local function getRoot(character)
        if not character then return nil end
        return character:FindFirstChild("HumanoidRootPart")
    end

    local function teleportToFinish()
        local root = getRoot(plr.Character)
        if not root then return end

        root.CFrame = CFrame.new(FINISH_POS)
        root.AssemblyLinearVelocity = Vector3.zero
    end

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

            task.wait(10)
            if not env.AutoComplete then return end
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

    -- 3 studs in front of the local player (-Z is forward)
    local frontOffset = CFrame.new(0, 0, -3)

    elements:Toggle("Kill", section, setdata.kill, function(v)
        env.Kill = v
        env.setconfig("kill", v)
        if not env.Kill then return end

        while env.Kill do
            pcall(function()
                local myRoot = getRoot(plr.Character)
                if not myRoot then return end

                local target = myRoot.CFrame * frontOffset

                for _, other in pairs(players:GetPlayers()) do
                    if other ~= plr then
                        local root = getRoot(other.Character)
                        if root then
                            -- fully local, no remotes: client side CFrame only
                            root.CFrame = target
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                end
            end)

            task.wait(0.05)
        end
    end)
end
