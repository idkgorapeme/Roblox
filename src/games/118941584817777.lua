-- Steal a Brainrot / World 2 helper

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local httpservice = game:GetService("HttpService")
    local camera = workspace.CurrentCamera

    local plr = players.LocalPlayer

    env.AutoWin = false
    env.AutoBuy = false
    env.KeyFarm = false
    env.KeyHighlight = false
    env.World2Help = false
    env.World2Destroy = false
    env.MacroPlaying = false
    env.MacroRecording = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autowin = setdata.autowin or false
    setdata.autobuy = setdata.autobuy or false
    setdata.keyfarm = setdata.keyfarm or false
    setdata.keyhighlight = setdata.keyhighlight or false
    setdata.world2help = setdata.world2help or false
    setdata.world2destroy = setdata.world2destroy or false
    setdata.glidespeed = setdata.glidespeed or 65
    setdata.flightspeed = setdata.flightspeed or 120
    setdata.buyamount = setdata.buyamount or 5
    setdata.keymode = setdata.keymode or "TP"
    setdata.buy_mysterious = setdata.buy_mysterious ~= false
    setdata.buy_rare = setdata.buy_rare ~= false
    setdata.buy_uncommon = setdata.buy_uncommon ~= false
    setdata.buy_common = setdata.buy_common ~= false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(data))

    local glideSpeed = tonumber(setdata.glidespeed) or 65
    local flightSpeed = tonumber(setdata.flightspeed) or 120
    local buyAmount = tonumber(setdata.buyamount) or 5
    local keyMode = setdata.keymode

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function getChar()
        return plr.Character
    end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- smoothly moves the root toward a target position, returns true when it arrives.
    -- runs one step per frame so it never blocks the toggle thread for long.
    local function glideTo(targetPos, speed, keepAlive)
        local root = getRoot()
        if not root then return false end

        speed = speed or glideSpeed

        while keepAlive() do
            root = getRoot()
            if not root then return false end

            local cur = root.Position
            local delta = targetPos - cur
            local dist = delta.Magnitude

            if dist < 3 then
                root.CFrame = CFrame.new(targetPos)
                root.AssemblyLinearVelocity = Vector3.zero
                return true
            end

            local dt = runservice.Heartbeat:Wait()
            local step = math.min(speed * dt, dist)

            root.CFrame = CFrame.new(cur + delta.Unit * step)
            root.AssemblyLinearVelocity = Vector3.zero
        end

        return false
    end

    ----------------------------------------------------------------
    -- auto win
    ----------------------------------------------------------------

    elements:Textbox("Glide Speed (default 65)", section, tostring(glideSpeed), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        glideSpeed = n
        env.setconfig("glidespeed", n)
    end)

    elements:Toggle("Auto Win", section, setdata.autowin, function(v)
        env.AutoWin = v
        env.setconfig("autowin", v)
        if not v then return end

        while env.AutoWin do
            pcall(function()
                local blocks = workspace:FindFirstChild("Winblocks")
                local block = blocks and blocks:FindFirstChild("WinBlock16")
                if not block then return end

                -- 7 studs above the block
                local target = block.Position + Vector3.new(0, 7, 0)
                glideTo(target, glideSpeed, function() return env.AutoWin end)
            end)

            task.wait(0.2)
        end
    end)

    ----------------------------------------------------------------
    -- auto buy
    ----------------------------------------------------------------

    local function getRemoContainer()
        local packages = replicatedstorage:FindFirstChild("Packages")
        local index = packages and packages:FindFirstChild("_Index")
        local remo = index and index:FindFirstChild("littensy_remo@1.5.3")
        remo = remo and remo:FindFirstChild("remo")
        return remo and remo:FindFirstChild("container")
    end

    local buyCategories = {
        { key = "buy_mysterious", label = "Buy Mysterious", name = "Mysterious" },
        { key = "buy_rare",       label = "Buy Rare",       name = "Rare" },
        { key = "buy_uncommon",   label = "Buy Uncommon",   name = "Uncommon" },
        { key = "buy_common",     label = "Buy Common",     name = "Common" },
    }

    local buyEnabled = {}
    for _, cat in ipairs(buyCategories) do
        buyEnabled[cat.name] = setdata[cat.key] ~= false
    end

    local function doBuyRound()
        local container = getRemoContainer()
        local buyWins = container and container:FindFirstChild("BuyWins")
        if not buyWins then return end

        for _, cat in ipairs(buyCategories) do
            if not env.AutoBuy then return end

            if buyEnabled[cat.name] then
                for _ = 1, buyAmount do
                    if not env.AutoBuy then return end
                    pcall(function()
                        buyWins:FireServer(cat.name)
                    end)
                    task.wait(0.2)
                end

                task.wait(1)
            end
        end
    end

    elements:Textbox("Buy Amount (default 5)", section, tostring(buyAmount), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        buyAmount = math.floor(n)
        env.setconfig("buyamount", buyAmount)
    end)

    for _, cat in ipairs(buyCategories) do
        elements:Toggle(cat.label, section, setdata[cat.key] ~= false, function(v)
            buyEnabled[cat.name] = v
            env.setconfig(cat.key, v)
        end)
    end

    local shopConn
    elements:Toggle("Auto Buy (on restock)", section, setdata.autobuy, function(v)
        env.AutoBuy = v
        env.setconfig("autobuy", v)

        if shopConn then
            shopConn:Disconnect()
            shopConn = nil
        end

        if not v then return end

        local container = getRemoContainer()
        local shopUpdate = container and container:FindFirstChild("ShopUpdate")

        if shopUpdate then
            shopConn = shopUpdate.OnClientEvent:Connect(function()
                if not env.AutoBuy then return end
                task.spawn(doBuyRound)
            end)

            if env.BrainrotPolice and env.BrainrotPolice.track then
                env.BrainrotPolice.track(shopConn)
            end
        else
            warn("[BrainrotPolice] ShopUpdate not found, auto buy will not trigger")
        end

        -- buy once right away so you do not wait a whole restock cycle
        task.spawn(doBuyRound)
    end)

    ----------------------------------------------------------------
    -- special key farm
    ----------------------------------------------------------------

    local function keyPosition(key)
        if key:IsA("BasePart") then
            return key.Position
        elseif key:IsA("Model") then
            if key.PrimaryPart then return key.PrimaryPart.Position end
            local part = key:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.Position end
        end
        return nil
    end

    elements:Textbox("Flight Speed (default 120)", section, tostring(flightSpeed), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        flightSpeed = n
        env.setconfig("flightspeed", n)
    end)

    elements:Toggle("Key Mode: Flight (off = TP)", section, keyMode == "Flight", function(v)
        keyMode = v and "Flight" or "TP"
        env.setconfig("keymode", keyMode)
    end)

    elements:Toggle("Special Key Farm", section, setdata.keyfarm, function(v)
        env.KeyFarm = v
        env.setconfig("keyfarm", v)
        if not v then return end

        while env.KeyFarm do
            pcall(function()
                local folder = workspace:FindFirstChild("SpecialKeys")
                if not folder then return end

                for _, key in pairs(folder:GetChildren()) do
                    if not env.KeyFarm then return end

                    local pos = keyPosition(key)
                    if pos then
                        if keyMode == "Flight" then
                            -- fly straight to the key, no vertical offset
                            glideTo(pos, flightSpeed, function()
                                return env.KeyFarm and key.Parent ~= nil
                            end)
                        else
                            -- tp 8 studs above the key
                            local root = getRoot()
                            if root then
                                root.CFrame = CFrame.new(pos + Vector3.new(0, 8, 0))
                                root.AssemblyLinearVelocity = Vector3.zero
                            end
                            task.wait(1)
                        end
                    end
                end
            end)

            task.wait(0.5)
        end
    end)

    ----------------------------------------------------------------
    -- special key highlight + tracers
    ----------------------------------------------------------------

    local keyHighlights = {}
    local keyTracers = {}
    local tracerConn

    local function keyColor(key)
        if key:IsA("BasePart") then
            return key.Color
        end
        local part = key:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Color or Color3.fromRGB(255, 255, 0)
    end

    local function clearKeyVisuals()
        for key, hl in pairs(keyHighlights) do
            pcall(function() hl:Destroy() end)
            keyHighlights[key] = nil
        end

        for key, line in pairs(keyTracers) do
            pcall(function() line:Remove() end)
            keyTracers[key] = nil
        end

        if tracerConn then
            tracerConn:Disconnect()
            tracerConn = nil
        end
    end

    local function refreshKeyVisuals()
        local folder = workspace:FindFirstChild("SpecialKeys")
        if not folder then
            clearKeyVisuals()
            return
        end

        local seen = {}

        for _, key in pairs(folder:GetChildren()) do
            seen[key] = true

            if not keyHighlights[key] then
                local hl = Instance.new("Highlight")
                hl.Name = "BPKey"
                hl.FillColor = Color3.fromRGB(255, 255, 0)
                hl.FillTransparency = 0.4
                hl.OutlineColor = Color3.fromRGB(255, 255, 0)
                hl.OutlineTransparency = 0
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = key
                hl.Parent = key

                keyHighlights[key] = hl
            end

            -- tracer drawn in the key's own colour
            if Drawing and not keyTracers[key] then
                local ok, line = pcall(function()
                    local l = Drawing.new("Line")
                    l.Thickness = 1.5
                    l.Transparency = 1
                    l.Color = keyColor(key)
                    l.Visible = false
                    return l
                end)

                if ok and line then
                    keyTracers[key] = line
                end
            end
        end

        for key, hl in pairs(keyHighlights) do
            if not seen[key] or not key.Parent then
                pcall(function() hl:Destroy() end)
                keyHighlights[key] = nil
            end
        end

        for key, line in pairs(keyTracers) do
            if not seen[key] or not key.Parent then
                pcall(function() line:Remove() end)
                keyTracers[key] = nil
            end
        end
    end

    local function updateTracers()
        local vpsX, vpsY = camera.ViewportSize.X, camera.ViewportSize.Y

        for key, line in pairs(keyTracers) do
            local pos = key.Parent and keyPosition(key)

            if pos then
                local screen, onScreen = camera:WorldToViewportPoint(pos)
                if onScreen then
                    line.From = Vector2.new(vpsX / 2, vpsY)
                    line.To = Vector2.new(screen.X, screen.Y)
                    line.Visible = true
                else
                    line.Visible = false
                end
            else
                line.Visible = false
            end
        end
    end

    elements:Toggle("Special Key Highlight", section, setdata.keyhighlight, function(v)
        env.KeyHighlight = v
        env.setconfig("keyhighlight", v)

        if not v then
            clearKeyVisuals()
            return
        end

        if Drawing then
            tracerConn = runservice.RenderStepped:Connect(function()
                if not env.KeyHighlight then return end
                pcall(updateTracers)
            end)

            if env.BrainrotPolice and env.BrainrotPolice.track then
                env.BrainrotPolice.track(tracerConn)
            end
        end

        while env.KeyHighlight do
            pcall(refreshKeyVisuals)
            task.wait(1)
        end

        clearKeyVisuals()
    end)

    ----------------------------------------------------------------
    -- world 2 help platforms
    ----------------------------------------------------------------

    local flatPlatforms = {
        { name = "BluePlatform1",  pos = Vector3.new(574.5, 622, 3869),     size = Vector3.new(1225, 1, 84) },
        { name = "BluePlatform2",  pos = Vector3.new(-394.5, 497, 73.5),    size = Vector3.new(51, 1, 197) },
        { name = "BluePlatform3",  pos = Vector3.new(-401.5, 607.5, 726),   size = Vector3.new(45, 1, 198) },
        { name = "BluePlatform4",  pos = Vector3.new(-402, 608, 1380.5),    size = Vector3.new(42, 1, 97) },
        { name = "BluePlatform5",  pos = Vector3.new(-363, 605, 1649),      size = Vector3.new(20, 1, 90) },
        { name = "BluePlatform6",  pos = Vector3.new(-401.5, 606, 2002.5),  size = Vector3.new(41, 1, 425) },
        { name = "BluePlatform7",  pos = Vector3.new(-402, 618.5, 2342),    size = Vector3.new(42, 1, 46) },
        { name = "BluePlatform8",  pos = Vector3.new(-399, 552.5, 522),     size = Vector3.new(80, 105, 86) },
        { name = "BluePlatform9",  pos = Vector3.new(1840.5, 626, 3870),    size = Vector3.new(1083, 4, 50) },
        { name = "BluePlatform10", pos = Vector3.new(2605.5, 637.5, 3872.5),size = Vector3.new(107, 5, 41) },
        { name = "BluePlatform11", pos = Vector3.new(3131, 592, 3872),      size = Vector3.new(164, 1, 40) },
    }

    -- rendered as a long rectangle spanning start -> end
    local slopes = {
        { name = "BlueSlope1",     from = Vector3.new(3282, 593, 3852), to = Vector3.new(3390, 670, 3904), width = 40 },
        { name = "BlueSlope2",     from = Vector3.new(4722, 568, 5120), to = Vector3.new(4996, 686, 5205), width = 40 },
        { name = "BlueSlope3",     from = Vector3.new(5139, 557, 5100), to = Vector3.new(5739, 556, 5187), width = 40 },
        { name = "BluePlatform12", from = Vector3.new(3390, 648, 3904), to = Vector3.new(3295, 648, 5191), width = 40 },
        { name = "BluePlatform13", from = Vector3.new(3295, 648, 5191), to = Vector3.new(4560, 648, 5097), width = 40 },
    }

    local function newPlatform(name, parent)
        local part = Instance.new("Part")
        part.Name = name
        part.Anchored = true
        part.CanCollide = true
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(0, 120, 255)
        part.Transparency = 0.5
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Parent = parent
        return part
    end

    local function buildWorld2Help()
        local existing = workspace:FindFirstChild("World2HelpFolder")
        if existing then existing:Destroy() end

        local folder = Instance.new("Folder")
        folder.Name = "World2HelpFolder"
        folder.Parent = workspace

        for _, def in ipairs(flatPlatforms) do
            local part = newPlatform(def.name, folder)
            part.Size = def.size
            part.CFrame = CFrame.new(def.pos)
        end

        for _, def in ipairs(slopes) do
            local part = newPlatform(def.name, folder)
            local delta = def.to - def.from
            local length = delta.Magnitude

            part.Size = Vector3.new(def.width, 1, length)
            -- centre between the two points, oriented along the line
            part.CFrame = CFrame.lookAt(def.from + delta / 2, def.to)
        end

        return folder
    end

    elements:Toggle("World 2 Help", section, setdata.world2help, function(v)
        env.World2Help = v
        env.setconfig("world2help", v)

        if v then
            pcall(buildWorld2Help)
        else
            local folder = workspace:FindFirstChild("World2HelpFolder")
            if folder then pcall(function() folder:Destroy() end) end
        end
    end)

    ----------------------------------------------------------------
    -- world 2 destroy
    ----------------------------------------------------------------

    -- each entry is a path relative to workspace
    local destroyTargets = {
        { "Stage2", "MovingWalls" },
        { "Stage2", "7" },
        { "Lava_Stage3", "LavaPart" },
        { "NPC_MacaronMonster" },
        { "Twomps" },
        { "Winblocks", "NPC_MacaronMonster" },
        { "Stage8", "Ventilateurs" },
        { "FanEffects" },
        { "NPC9" },
        { "Stage10", "DoorWall1" },
        { "Stage10", "DoorWall2" },
        { "Stage10", "DoorWall3" },
        { "NPC15_World2" },
        { "Stage15", "Levels", "MovingWalls", "MovingWalls" },
    }

    local function resolve(path)
        local node = workspace
        for _, name in ipairs(path) do
            node = node:FindFirstChild(name)
            if not node then return nil end
        end
        return node
    end

    elements:Toggle("World 2 Destroy", section, setdata.world2destroy, function(v)
        env.World2Destroy = v
        env.setconfig("world2destroy", v)
        if not v then return end

        while env.World2Destroy do
            for _, path in ipairs(destroyTargets) do
                if not env.World2Destroy then break end
                pcall(function()
                    local target = resolve(path)
                    if target then target:Destroy() end
                end)
            end

            task.wait(0.5)
        end
    end)

    ----------------------------------------------------------------
    -- macro manager (mode 1: cframe teleport, 50 fps)
    ----------------------------------------------------------------

    local MACRO_FILE = "BrainrotPolice/118941584817777_macro.json"
    local macro = {}

    -- load a previously saved macro
    pcall(function()
        if isfile(MACRO_FILE) then
            macro = httpservice:JSONDecode(readfile(MACRO_FILE)) or {}
        end
    end)

    local function saveMacro()
        pcall(function()
            writefile(MACRO_FILE, httpservice:JSONEncode(macro))
        end)
    end

    elements:Label("Macro Slot 1 (CFrame, 50 FPS)", section)

    elements:Toggle("Record Macro", section, false, function(v)
        env.MacroRecording = v
        if not v then
            saveMacro()
            return
        end

        macro = {}

        task.spawn(function()
            while env.MacroRecording do
                local root = getRoot()
                if root then
                    local c = root.CFrame
                    -- store the full component set so rotation survives the round trip
                    macro[#macro + 1] = { c:GetComponents() }
                end
                task.wait(0.02)
            end
        end)
    end)

    elements:Toggle("Play Macro", section, false, function(v)
        env.MacroPlaying = v
        if not v then return end

        task.spawn(function()
            for _, comp in ipairs(macro) do
                if not env.MacroPlaying then break end

                local root = getRoot()
                if root then
                    root.CFrame = CFrame.new(unpack(comp))
                    root.AssemblyLinearVelocity = Vector3.zero
                end

                task.wait(0.02)
            end

            env.MacroPlaying = false
        end)
    end)

    elements:Button("Clear Macro", section, function()
        macro = {}
        pcall(function()
            if isfile(MACRO_FILE) then delfile(MACRO_FILE) end
        end)
    end)
end
