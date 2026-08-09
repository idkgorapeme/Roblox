-- +1 Speed Monkey Escape

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.MERebirth = false
    env.MEWin = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.rebirth = setdata.rebirth or false
    setdata.win = setdata.win or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- fixed, matching the other escape modules
    local FLY_SPEED = 1000
    local WIN_POS = Vector3.new(-9457, 388, -242)

    local function getChar() return plr.Character end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function alive()
        local char = getChar()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return hum ~= nil and hum.Health > 0
    end

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.MERebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MERebirth do
                local remotes = replicatedstorage:FindFirstChild("Remotes")
                local ev = remotes and remotes:FindFirstChild("Rebirth")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] Remotes.Rebirth not found")
                    warned = true
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- flight, body movers so control returns cleanly on disable
    ----------------------------------------------------------------

    local flyBV, flyBG
    local noclipConn

    local function startNoclip()
        if noclipConn then return end

        noclipConn = runservice.Stepped:Connect(function()
            local char = getChar()
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

        local char = getChar()
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

            local hum = getChar() and getChar():FindFirstChildOfClass("Humanoid")
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

        -- fixed top speed, easing off near the target with a floor so the
        -- last studs do not crawl
        local speed = math.clamp(dist * 4, 12, FLY_SPEED)
        flyBV.Velocity = delta.Unit * speed

        if flyBG then
            local look = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
            if (look - root.Position).Magnitude > 0.1 then
                flyBG.CFrame = CFrame.new(root.Position, look)
            end
        end

        return false
    end

    ----------------------------------------------------------------
    -- auto win
    ----------------------------------------------------------------

    -- starts off every session, it moves the character
    elements:Toggle("Auto Win", section, false, function(v)
        env.MEWin = v
        env.setconfig("win", v)

        if not v then
            stopFlight()
            stopNoclip()
            return
        end

        task.spawn(function()
            while env.MEWin do
                if not alive() then
                    if flyBV then flyBV.Velocity = Vector3.zero end
                    task.wait(0.5)
                else
                    startNoclip()

                    local startRoot = getRoot()
                    local startPos = startRoot and startRoot.Position
                    local elapsed = 0

                    while env.MEWin do
                        if not alive() then break end

                        local r = getRoot()
                        if not r then break end

                        -- the win teleported us away, that counts as done
                        if startPos and (r.Position - startPos).Magnitude > 500
                            and (r.Position - WIN_POS).Magnitude > 100 then
                            break
                        end

                        if glideStep(WIN_POS, 3) then break end

                        elapsed = elapsed + runservice.Heartbeat:Wait()
                        if elapsed > 30 then break end
                    end

                    if not env.MEWin then break end

                    -- hand control back, then pause before the next run
                    stopFlight()
                    stopNoclip()

                    local waited = 0
                    while waited < 3 and env.MEWin do
                        task.wait(0.1)
                        waited = waited + 0.1
                    end
                end
            end

            stopFlight()
            stopNoclip()
        end)
    end)
end
