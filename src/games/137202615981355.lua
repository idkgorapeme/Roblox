-- +1 Height Per Jump

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.JHJump = false
    env.JHRebirth = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.jump = setdata.jump or false
    setdata.rebirth = setdata.rebirth or false
    setdata.jumpdelay = setdata.jumpdelay or 0.05
    setdata.ceiling = setdata.ceiling or 3.5
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local jumpDelay = tonumber(setdata.jumpdelay) or 0.05
    local ceilingHeight = tonumber(setdata.ceiling) or 3.5

    local function getChar() return plr.Character end

    local function getHum()
        local char = getChar()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- knit remotes: Packages.Knit.Services.<Service>.RF.<Method>
    ----------------------------------------------------------------

    local function knit(serviceName, kind, methodName)
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local k = pkgs and pkgs:FindFirstChild("Knit")
        local services = k and k:FindFirstChild("Services")
        local service = services and services:FindFirstChild(serviceName)
        local folder = service and service:FindFirstChild(kind)
        return folder and folder:FindFirstChild(methodName) or nil
    end

    local function callRF(serviceName, methodName, ...)
        local rf = knit(serviceName, "RF", methodName)
        if not rf then return false, "remote not found" end

        local args = table.pack(...)
        return pcall(function()
            return rf:InvokeServer(table.unpack(args, 1, args.n))
        end)
    end

    ----------------------------------------------------------------
    -- jump farm
    --
    -- Every jump grants height. A ceiling right above the head cuts the
    -- jump off instantly, so the character lands immediately and can jump
    -- again, bounding the rate by the delay instead of by air time.
    ----------------------------------------------------------------

    local ceilingPart
    local ceilingCFrame
    local ceilingWatch

    local function removeCeiling()
        if ceilingWatch then
            ceilingWatch:Disconnect()
            ceilingWatch = nil
        end

        if ceilingPart then
            pcall(function() ceilingPart:Destroy() end)
            ceilingPart = nil
        end

        ceilingCFrame = nil
    end

    -- clears anything left over from an earlier run of the script
    local function purgeOldCeilings()
        for _, c in pairs(workspace:GetChildren()) do
            if c.Name == "BPJumpCeiling" and c ~= ceilingPart then
                pcall(function() c:Destroy() end)
            end
        end
    end

    -- Placed ONCE where the player stands when the farm is switched on.
    -- The spawn CFrame is remembered and actively restored, so nothing can
    -- drag it along with the character.
    local function buildCeiling()
        removeCeiling()
        purgeOldCeilings()

        local root = getRoot()
        if not root then return false end

        -- frozen copy of the spawn position, not a live reference
        local px, py, pz = root.Position.X, root.Position.Y, root.Position.Z
        ceilingCFrame = CFrame.new(px, py + ceilingHeight, pz)

        local part = Instance.new("Part")
        part.Name = "BPJumpCeiling"
        part.Size = Vector3.new(8, 1, 8)
        part.Anchored = true
        part.CanCollide = true
        part.Transparency = 0.6
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(0, 170, 255)
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.CFrame = ceilingCFrame
        part.Parent = workspace

        ceilingPart = part

        -- watchdog: if anything moves it, put it straight back
        ceilingWatch = part:GetPropertyChangedSignal("CFrame"):Connect(function()
            if not ceilingCFrame or not ceilingPart then return end

            if (ceilingPart.CFrame.Position - ceilingCFrame.Position).Magnitude > 0.05 then
                ceilingPart.CFrame = ceilingCFrame
            end
        end)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(ceilingWatch)
        end

        print(("[BrainrotPolice] ceiling locked at %.1f, %.1f, %.1f")
            :format(px, py + ceilingHeight, pz))

        return true
    end

    elements:Textbox("Jump Delay (default 0.05)", section, tostring(jumpDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.01 then return end
        jumpDelay = n
        env.setconfig("jumpdelay", n)
    end)

    elements:Textbox("Ceiling Height (default 3.5)", section, tostring(ceilingHeight), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        ceilingHeight = n
        env.setconfig("ceiling", n)
    end)

    -- starts off every session, it spawns a part and moves the character
    elements:Toggle("Jump Farm", section, false, function(v)
        env.JHJump = v
        env.setconfig("jump", v)

        if not v then
            removeCeiling()
            return
        end

        if not buildCeiling() then
            warn("[BrainrotPolice] no character yet, toggle again once you have spawned")
            env.JHJump = false
            return
        end

        task.spawn(function()
            while env.JHJump do
                pcall(function()
                    local hum = getHum()
                    if hum and hum.Health > 0 then
                        hum.Jump = true
                    end
                end)

                task.wait(jumpDelay)
            end

            removeCeiling()
        end)
    end)

    ----------------------------------------------------------------
    -- rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.JHRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            while env.JHRebirth do
                callRF("RebirthService", "TryRebirth")
                task.wait(2)
            end
        end)
    end)
end
