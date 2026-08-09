-- +1 Muscle to Push Boulder

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.MPTrain = false
    env.MPWin = false
    env.MPRebirth = false
    env.MPDumbbell = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.train = setdata.train or false
    setdata.traindelay = setdata.traindelay or 0.1
    setdata.win = setdata.win or false
    setdata.world = setdata.world or "World 1"
    setdata.area = setdata.area or 1
    setdata.windelay = setdata.windelay or 1
    setdata.rebirth = setdata.rebirth or false
    setdata.dumbbell = setdata.dumbbell or false
    setdata.flyspeed = setdata.flyspeed or 120
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local trainDelay = tonumber(setdata.traindelay) or 0.1
    local winDelay = tonumber(setdata.windelay) or 1
    local areaNumber = tonumber(setdata.area) or 1
    local flySpeed = tonumber(setdata.flyspeed) or 120

    -- fixed sweep range
    local DB_FROM, DB_TO = 1, 44

    ----------------------------------------------------------------
    -- Packages.Net remotes. The names contain a slash, which some
    -- executors mishandle with plain indexing, so fall back to a
    -- name scan over the children.
    ----------------------------------------------------------------

    local function netRemote(name)
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local net = pkgs and pkgs:FindFirstChild("Net")
        if not net then return nil end

        local direct = net:FindFirstChild(name)
        if direct then return direct end

        for _, child in pairs(net:GetChildren()) do
            if child.Name == name then
                return child
            end
        end

        return nil
    end

    ----------------------------------------------------------------
    -- auto train
    ----------------------------------------------------------------

    elements:Textbox("Train Delay (default 0.1)", section, tostring(trainDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.01 then return end
        trainDelay = n
        env.setconfig("traindelay", n)
    end)

    elements:Toggle("Auto Train", section, setdata.train, function(v)
        env.MPTrain = v
        env.setconfig("train", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MPTrain do
                local ev = netRemote("RE/ClientTrain")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] RE/ClientTrain not found")
                    warned = true
                end

                task.wait(trainDelay)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto win
    --
    -- workspace.Areas["<world folder>"].Area<n>.Win
    ----------------------------------------------------------------

    local WORLD_OPTIONS = { "World 1", "World 2", "World 3", "World 4" }

    local WORLD_FOLDER = {
        ["World 1"] = "Spawn World",
        ["World 2"] = "Future World",
        ["World 3"] = "Heaven World",
        ["World 4"] = "Hell World",
    }

    local worldChoice = tostring(setdata.world or "World 1")
    if not WORLD_FOLDER[worldChoice] then worldChoice = "World 1" end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- resolves the Win part of the selected world and area
    local function winPart()
        local areas = workspace:FindFirstChild("Areas")
        if not areas then return nil, "workspace.Areas missing" end

        local folderName = WORLD_FOLDER[worldChoice]
        local world = areas:FindFirstChild(folderName)
        if not world then return nil, folderName .. " missing" end

        local area = world:FindFirstChild("Area" .. tostring(areaNumber))
        if not area then return nil, folderName .. ".Area" .. areaNumber .. " missing" end

        local win = area:FindFirstChild("Win")
        if not win then return nil, "Area" .. areaNumber .. ".Win missing" end

        if win:IsA("BasePart") then return win end
        return win:FindFirstChildWhichIsA("BasePart", true), nil
    end

    elements:Dropdown("World", section, WORLD_OPTIONS, worldChoice, function(v)
        worldChoice = v
        env.setconfig("world", v)
        print("[BrainrotPolice] world set to " .. v .. " (" .. WORLD_FOLDER[v] .. ")")
    end)

    elements:Textbox("Area (1 - 10)", section, tostring(areaNumber), function(v)
        local n = tonumber(v)
        if not n then return end
        areaNumber = math.clamp(math.floor(n), 1, 10)
        env.setconfig("area", areaNumber)
    end)

    elements:Textbox("Win Delay (default 1)", section, tostring(winDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.1 then return end
        winDelay = n
        env.setconfig("windelay", n)
    end)

    elements:Textbox("Fly Speed (default 120)", section, tostring(flySpeed), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        flySpeed = n
        env.setconfig("flyspeed", n)
    end)

    ----------------------------------------------------------------
    -- flight, body movers so control returns cleanly on disable
    ----------------------------------------------------------------

    local flyBV, flyBG
    local noclipConn

    local function startNoclip()
        if noclipConn then return end

        noclipConn = runservice.Stepped:Connect(function()
            local char = plr.Character
            if not char then return end

            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(noclipConn)
        end
    end

    local function stopNoclip()
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end

        local char = plr.Character
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
    end

    local function stopFlight()
        if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
        if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end

        pcall(function()
            local root = getRoot()
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end

            local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end)
    end

    -- rebuilds the movers on a fresh character after a respawn
    local function ensureFlight()
        local root = getRoot()
        if not root then return nil end

        if flyBV and flyBV.Parent ~= root then
            pcall(function() flyBV:Destroy() end)
            flyBV = nil
        end
        if flyBG and flyBG.Parent ~= root then
            pcall(function() flyBG:Destroy() end)
            flyBG = nil
        end

        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.Name = "BPWinFly"
            flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBV.P = 1e4
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end

        if not flyBG then
            flyBG = Instance.new("BodyGyro")
            flyBG.Name = "BPWinGyro"
            flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBG.P = 1e4
            flyBG.D = 500
            flyBG.CFrame = root.CFrame
            flyBG.Parent = root
        end

        return root
    end

    -- one step toward the target, returns true once we are there
    local function glideStep(targetPos, arriveAt)
        local root = ensureFlight()
        if not root or not flyBV then return false end

        arriveAt = arriveAt or 4

        local delta = targetPos - root.Position
        local dist = delta.Magnitude

        -- a zero length vector has no .Unit, guard against NaN
        if dist < 0.05 or dist <= arriveAt then
            flyBV.Velocity = Vector3.zero
            return true
        end

        -- ease off on approach instead of overshooting
        flyBV.Velocity = delta.Unit * math.min(flySpeed, dist * 4)

        if flyBG then
            local look = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
            if (look - root.Position).Magnitude > 0.1 then
                flyBG.CFrame = CFrame.new(root.Position, look)
            end
        end

        return false
    end

    -- starts off every session, it moves the character
    -- starts off every session, it moves the character
    elements:Toggle("Auto Win", section, false, function(v)
        env.MPWin = v
        env.setconfig("win", v)

        if not v then
            stopFlight()
            stopNoclip()
            return
        end

        task.spawn(function()
            local warned = false

            while env.MPWin do
                local part, err = winPart()

                if not part then
                    if not warned then
                        warn("[BrainrotPolice] " .. tostring(err))
                        warned = true
                    end
                    stopFlight()
                    stopNoclip()
                    task.wait(1)
                else
                    warned = false

                    local hum = plr.Character
                        and plr.Character:FindFirstChildOfClass("Humanoid")

                    if not (hum and hum.Health > 0) then
                        -- dead, do not fling the corpse around
                        if flyBV then flyBV.Velocity = Vector3.zero end
                        task.wait(0.5)
                    else
                        -- noclip so walls and the win block itself cannot
                        -- block the approach
                        startNoclip()

                        -- stage 1: approach point, 50 studs to the left of
                        -- the win block. left is -X in world space.
                        local approach = part.Position + Vector3.new(-50, 0, 0)

                        while env.MPWin and not glideStep(approach, 3) do
                            local h = plr.Character
                                and plr.Character:FindFirstChildOfClass("Humanoid")
                            if not (h and h.Health > 0) then break end

                            if not part.Parent then break end

                            runservice.Heartbeat:Wait()
                        end

                        if not env.MPWin then break end

                        -- stage 2: fly INTO the win block itself, noclip lets
                        -- us sit inside it so the touch registers
                        if part.Parent then
                            local inside = part.Position

                            while env.MPWin and not glideStep(inside, 1) do
                                local h = plr.Character
                                    and plr.Character:FindFirstChildOfClass("Humanoid")
                                if not (h and h.Health > 0) then break end

                                if not part.Parent then break end

                                runservice.Heartbeat:Wait()
                            end
                        end

                        if not env.MPWin then break end

                        -- cut the flight and collision so we simply drop out
                        -- of the block, then pause before the next run
                        stopFlight()
                        stopNoclip()

                        local waited = 0
                        while waited < 5 and env.MPWin do
                            task.wait(0.1)
                            waited = waited + 0.1
                        end
                    end
                end
            end

            stopFlight()
            stopNoclip()
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.MPRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MPRebirth do
                local ev = netRemote("RE/Rebirth")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] RE/Rebirth not found")
                    warned = true
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto buy dumbbells
    --
    -- Walks Dumbbell<from> .. Dumbbell<to>. The server rejects the ones
    -- that are too expensive or already owned, so a plain sweep is enough.
    -- Goes high to low so the best affordable one is bought first.
    ----------------------------------------------------------------

    elements:Toggle("Auto Buy Dumbbell", section, setdata.dumbbell, function(v)
        env.MPDumbbell = v
        env.setconfig("dumbbell", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MPDumbbell do
                local ev = netRemote("RE/BuyDumbbell")

                if not ev then
                    if not warned then
                        warn("[BrainrotPolice] RE/BuyDumbbell not found")
                        warned = true
                    end
                    task.wait(1)
                else
                    warned = false

                    -- highest first, so we upgrade as soon as we can afford it
                    for i = DB_TO, DB_FROM, -1 do
                        if not env.MPDumbbell then break end
                        pcall(function() ev:FireServer("Dumbbell" .. i) end)
                        task.wait(0.1)
                    end

                    task.wait(2)
                end
            end
        end)
    end)
end
