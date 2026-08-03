-- +1 Speed Keyboard Escape | Candy & Chocolate

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.KEWin1 = false
    env.KEWin2 = false
    env.KEDestroy = false
    env.KECoins = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.win1 = setdata.win1 or false
    setdata.win2 = setdata.win2 or false
    setdata.destroy3 = setdata.destroy3 or false
    setdata.coins = setdata.coins or false
    setdata.coindelay = setdata.coindelay or 0.25
    setdata.flyspeed = setdata.flyspeed or 120
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local flySpeed = tonumber(setdata.flyspeed) or 120
    local coinDelay = tonumber(setdata.coindelay) or 0.25

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- resolves a dotted path, returns nil instead of erroring on a missing node
    local function resolve(...)
        local node = workspace
        for _, name in ipairs({...}) do
            if not node then return nil end
            node = node:FindFirstChild(name)
        end
        return node
    end

    -- world position of a part, model or folder
    local function posOf(inst)
        if not inst then return nil end

        if inst:IsA("BasePart") then
            return inst.Position
        end

        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local ok, cf = pcall(function() return inst:GetPivot() end)
            if ok and cf then return cf.Position end
        end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    ----------------------------------------------------------------
    -- noclip, kept on for the whole flight so walls cannot stop us
    ----------------------------------------------------------------

    local noclipConn
    local noclipUsers = 0

    local function startNoclip()
        noclipUsers = noclipUsers + 1
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
        noclipUsers = math.max(noclipUsers - 1, 0)
        if noclipUsers > 0 then return end

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

    -- smoothly flies to a position, returns true once we arrive.
    -- keepAlive lets the toggle interrupt the flight at any point.
    local function flyTo(targetPos, keepAlive)
        if not targetPos then return false end

        while keepAlive() do
            local root = getRoot()
            if not root then return false end

            local delta = targetPos - root.Position
            local dist = delta.Magnitude

            if dist < 4 then
                root.CFrame = CFrame.new(targetPos)
                root.AssemblyLinearVelocity = Vector3.zero
                return true
            end

            local dt = runservice.Heartbeat:Wait()
            local step = math.min(flySpeed * dt, dist)

            root.CFrame = CFrame.new(root.Position + delta.Unit * step)
            root.AssemblyLinearVelocity = Vector3.zero

            -- gravity would drag us down between steps
            local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = true
            end
        end

        return false
    end

    -- pins the character at a position for a while with collision restored,
    -- used after landing so we do not sink through the block
    local function holdAt(pos, duration, keepAlive)
        stopNoclip()

        local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end

        local elapsed = 0
        while elapsed < duration and keepAlive() do
            local root = getRoot()
            if root and pos then
                -- sit slightly above the block so we rest on top of it
                root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
                root.AssemblyLinearVelocity = Vector3.zero
            end

            task.wait(0.05)
            elapsed = elapsed + 0.05
        end

        if keepAlive() then
            startNoclip()
        end
    end

    -- flies to an instance looked up by path
    local function flyToPath(keepAlive, ...)
        return flyTo(posOf(resolve(...)), keepAlive)
    end

    elements:Textbox("Fly Speed (default 120)", section, tostring(flySpeed), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        flySpeed = n
        env.setconfig("flyspeed", n)
    end)

    ----------------------------------------------------------------
    -- auto win 1
    ----------------------------------------------------------------

    elements:Toggle("Auto Win 1", section, setdata.win1, function(v)
        env.KEWin1 = v
        env.setconfig("win1", v)
        if not v then return end

        task.spawn(function()
            local alive = function() return env.KEWin1 end
            startNoclip()

            while env.KEWin1 do
                flyToPath(alive, "Boards&Gamepass", "WinsLeaderboard")
                if not env.KEWin1 then break end

                flyToPath(alive, "Structure", "Stage1", "SAS", "WinBlock32")
                if not env.KEWin1 then break end

                task.wait(1)
            end

            stopNoclip()
            local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end)
    end)

    ----------------------------------------------------------------
    -- auto win 2
    ----------------------------------------------------------------

    -- the middle of the route is plain coordinates
    local win2Points = {
        Vector3.new(-1454, 215, 104),
        Vector3.new(-1453, 213, 610),
        Vector3.new(-1434, 361, 615),
        Vector3.new(-1458, 358, 500),
        Vector3.new(-1231, 340, 476),
        Vector3.new(-1212, 344, 837),
        Vector3.new(-1402, 363, 820),
        Vector3.new(-1405, 376, 725),
        Vector3.new(-1403, 536, 725),
        Vector3.new(-1401, 537, 1440),
        Vector3.new(-1445, 510, 1446),
        Vector3.new(-2032, 509, 1447),
    }

    elements:Toggle("Auto Win 2", section, setdata.win2, function(v)
        env.KEWin2 = v
        env.setconfig("win2", v)
        if not v then return end

        task.spawn(function()
            local alive = function() return env.KEWin2 end
            startNoclip()

            while env.KEWin2 do
                flyToPath(alive, "Boards&Gamepass", "WinsLeaderboard")
                if not env.KEWin2 then break end

                flyTo(Vector3.new(-1492, -61, -540), alive)
                if not env.KEWin2 then break end

                flyTo(Vector3.new(-1455, -57, 76), alive)
                if not env.KEWin2 then break end

                for _, point in ipairs(win2Points) do
                    if not env.KEWin2 then break end
                    flyTo(point, alive)
                end

                if not env.KEWin2 then break end

                flyToPath(alive, "Structure", "Stage6", "SAS", "WinBlock37")
                if not env.KEWin2 then break end

                -- landing: turn collision back on and hold the win block for
                -- the 2s wait, otherwise noclip drops us straight through it
                holdAt(posOf(resolve("Structure", "Stage6", "SAS", "WinBlock37")), 2, alive)
                if not env.KEWin2 then break end

                -- reset so the run starts from spawn again
                stopNoclip()
                pcall(function()
                    local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.PlatformStand = false
                        hum.Health = 0
                    end
                end)

                -- wait for the respawn, then idle the rest of the 5 seconds
                local waited = 0
                while waited < 5 and env.KEWin2 do
                    task.wait(0.1)
                    waited = waited + 0.1
                end

                if not env.KEWin2 then break end

                -- make sure the new character is actually there before flying
                local ready = 0
                while ready < 10 and env.KEWin2 do
                    local char = plr.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if root and root.Parent and hum and hum.Health > 0 then
                        break
                    end
                    task.wait(0.25)
                    ready = ready + 0.25
                end

                if not env.KEWin2 then break end
                startNoclip()
            end

            stopNoclip()
            local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end)
    end)

    ----------------------------------------------------------------
    -- world 3 destroy
    ----------------------------------------------------------------

    elements:Toggle("World 3 Destroy", section, setdata.destroy3, function(v)
        env.KEDestroy = v
        env.setconfig("destroy3", v)
        if not v then return end

        task.spawn(function()
            while env.KEDestroy do
                pcall(function()
                    local npc = workspace:FindFirstChild("NPC & Piege")

                    if npc then
                        -- named targets
                        local lavaStage3 = npc:FindFirstChild("Lava_Stage3")
                        local lavaPart = lavaStage3 and lavaStage3:FindFirstChild("LavaPart")
                        if lavaPart then lavaPart:Destroy() end

                        local lava = npc:FindFirstChild("Lava")
                        if lava then lava:Destroy() end

                        -- index based targets, taken after the named ones are
                        -- gone so the indices refer to what is actually left
                        local kids = npc:GetChildren()
                        for _, i in ipairs({ 7, 6 }) do
                            local child = kids[i]
                            if child and child.Parent then
                                child:Destroy()
                            end
                        end
                    end

                    local monster = workspace:FindFirstChild("NPC_LolMonster")
                    if monster then monster:Destroy() end
                end)

                task.wait(0.5)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- summer coins
    ----------------------------------------------------------------

    -- waits for a living character and returns its root.
    -- this is what makes the farm survive dying: the old code grabbed the
    -- HumanoidRootPart once, and that reference is dead after a respawn.
    local function waitForRoot(keepAlive)
        while keepAlive() do
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if root and root.Parent and hum and hum.Health > 0 then
                return root
            end

            task.wait(0.25)
        end

        return nil
    end

    local function collectCoinTargets()
        local out = {}
        local folder = workspace:FindFirstChild("SummerCoinsLocal")
        if not folder then return out end

        for _, item in ipairs(folder:GetDescendants()) do
            if string.find(string.lower(item.Name), "coin") then
                if item:IsA("BasePart") then
                    out[#out + 1] = item
                elseif item:IsA("Model") then
                    local part = item.PrimaryPart
                        or item:FindFirstChildWhichIsA("BasePart", true)
                    if part then
                        out[#out + 1] = item
                    end
                end
            end
        end

        return out
    end

    elements:Textbox("Coin Delay (default 0.25)", section, tostring(coinDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0 then return end
        coinDelay = n
        env.setconfig("coindelay", n)
    end)

    elements:Toggle("Summer Coins", section, setdata.coins, function(v)
        env.KECoins = v
        env.setconfig("coins", v)
        if not v then return end

        task.spawn(function()
            local alive = function() return env.KECoins end
            local warned = false

            while env.KECoins do
                local targets = collectCoinTargets()

                if #targets == 0 then
                    if not warned then
                        warn("[BrainrotPolice] workspace.SummerCoinsLocal has no coins")
                        warned = true
                    end
                    task.wait(1)
                else
                    warned = false

                    for _, target in ipairs(targets) do
                        if not env.KECoins then break end

                        -- re-acquire every coin, so dying just pauses us
                        -- until the respawn instead of ending the run
                        local root = waitForRoot(alive)
                        if not root then break end

                        -- the coin may have been collected while we travelled
                        if target and target.Parent then
                            pcall(function()
                                if target:IsA("BasePart") then
                                    root.CFrame = target.CFrame + Vector3.new(0, 3, 0)
                                else
                                    root.CFrame = target:GetPivot() + Vector3.new(0, 3, 0)
                                end
                                root.AssemblyLinearVelocity = Vector3.zero
                            end)
                        end

                        task.wait(coinDelay)
                    end
                end

                task.wait(0.5)
            end
        end)
    end)
end
