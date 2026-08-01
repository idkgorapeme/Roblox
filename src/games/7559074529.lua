-- Squid Game X (game lobby)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
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
    env.ShowGlass = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autocomplete = setdata.autocomplete or false
    setdata.autorevive = setdata.autorevive or false
    setdata.kill = setdata.kill or false
    setdata.showglass = setdata.showglass or false
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

    -- 1 stud in front of the local player (-Z is forward) and 2 studs up
    local frontOffset = CFrame.new(0, 2, -1)

    -- highlights the safe glass panels.
    -- CanCollide is true on every panel in this game, so it can't tell real from fake.
    -- Instead we look for whatever marks a panel as breakable, checking several
    -- possible signals. Use the "Dump Glass Info" button to see what this game uses.
    local glassHighlights = {}

    local function clearGlassHighlights()
        for part, hl in pairs(glassHighlights) do
            pcall(function() hl:Destroy() end)
            glassHighlights[part] = nil
        end
    end

    local function getGlassFolder()
        local map = workspace:FindFirstChild("Map")
        local glass = map and map:FindFirstChild("Glass")
        return glass and glass:FindFirstChild("Glasses")
    end

    -- returns true when the panel looks safe to stand on
    local function isSafe(part)
        -- 1. explicit attributes the game may set
        for _, key in ipairs({"Fake", "IsFake", "Breakable", "IsBreakable", "Break"}) do
            local attr = part:GetAttribute(key)
            if attr ~= nil then
                return attr == false
            end
        end

        for _, key in ipairs({"Safe", "IsSafe", "Real", "IsReal", "Strong"}) do
            local attr = part:GetAttribute(key)
            if attr ~= nil then
                return attr == true
            end
        end

        -- 2. a marker object parented to the panel
        if part:FindFirstChild("Fake") or part:FindFirstChild("Breakable") then
            return false
        end
        if part:FindFirstChild("Real") or part:FindFirstChild("Safe") then
            return true
        end

        -- 3. some builds tag the fake panel with a BreakGlass/Touch script or a
        --    TouchTransmitter that only the breakable pane carries
        if part:FindFirstChildOfClass("TouchTransmitter") then
            return false
        end

        -- 4. fall back to name, fake panes are often named differently
        local n = part.Name:lower()
        if n:find("fake") or n:find("break") then return false end
        if n:find("real") or n:find("safe") or n:find("strong") then return true end

        return nil
    end

    local function refreshGlass()
        local glasses = getGlassFolder()
        if not glasses then
            clearGlassHighlights()
            return
        end

        local seen = {}

        for _, part in pairs(glasses:GetDescendants()) do
            if part:IsA("BasePart") and isSafe(part) == true then
                seen[part] = true

                if not glassHighlights[part] then
                    local hl = Instance.new("Highlight")
                    hl.Name = "BPGlass"
                    hl.FillColor = Color3.fromRGB(0, 255, 0)
                    hl.FillTransparency = 0.5
                    hl.OutlineColor = Color3.fromRGB(0, 255, 0)
                    hl.OutlineTransparency = 0
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Adornee = part
                    hl.Parent = part

                    glassHighlights[part] = hl
                end
            end
        end

        for part, hl in pairs(glassHighlights) do
            if not seen[part] or not part.Parent then
                pcall(function() hl:Destroy() end)
                glassHighlights[part] = nil
            end
        end
    end

    elements:Toggle("Show Glass", section, setdata.showglass, function(v)
        env.ShowGlass = v
        env.setconfig("showglass", v)

        if not v then
            clearGlassHighlights()
            return
        end

        while env.ShowGlass do
            pcall(refreshGlass)
            task.wait(0.5)
        end

        clearGlassHighlights()
    end)

    -- prints the structure of one glass panel so the detection above can be
    -- pointed at the right property. Run it during a Glass Bridge round.
    elements:Button("Dump Glass Info", section, function()
        local glasses = getGlassFolder()
        if not glasses then
            warn("[BrainrotPolice] no workspace.Map.Glass.Glasses right now")
            return
        end

        local count = 0
        for _, part in pairs(glasses:GetDescendants()) do
            if part:IsA("BasePart") then
                count = count + 1
                if count <= 4 then
                    print("---- glass panel", count, part:GetFullName())
                    print("   ClassName:", part.ClassName, "Name:", part.Name)
                    print("   CanCollide:", part.CanCollide, "Transparency:", part.Transparency)
                    print("   Material:", part.Material, "Color:", part.Color)

                    local attrs = part:GetAttributes()
                    if next(attrs) == nil then
                        print("   attributes: none")
                    else
                        for k, val in pairs(attrs) do
                            print("   attribute:", k, "=", val)
                        end
                    end

                    for _, ch in pairs(part:GetChildren()) do
                        print("   child:", ch.ClassName, ch.Name)
                    end

                    local parent = part.Parent
                    if parent and parent ~= glasses then
                        print("   parent:", parent.ClassName, parent.Name)
                        for k, val in pairs(parent:GetAttributes()) do
                            print("   parent attribute:", k, "=", val)
                        end
                    end
                end
            end
        end

        print("[BrainrotPolice] total glass parts:", count)
    end)

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
