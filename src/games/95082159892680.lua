-- +1 speed keyboard escape

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = game:GetService("Players").LocalPlayer

    env.KSWalk = false
    env.KSBuy = false
    env.KSWin = false
    env.KSDestroy = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.walk = setdata.walk or false
    setdata.autowin = setdata.autowin or false
    setdata.winblock = setdata.winblock or 1
    setdata.flyspeed = setdata.flyspeed or 120
    setdata.destroy1 = setdata.destroy1 or false
    setdata.autobuy = setdata.autobuy or false
    setdata.buy_mysterious = setdata.buy_mysterious ~= false
    setdata.buy_rare = setdata.buy_rare ~= false
    setdata.buy_uncommon = setdata.buy_uncommon ~= false
    setdata.buy_common = setdata.buy_common ~= false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    ----------------------------------------------------------------
    -- speed farm
    ----------------------------------------------------------------

    elements:Toggle("Auto Walk Speed", section, setdata.walk, function(v)
        env.KSWalk = v
        env.setconfig("walk", v)
        if not v then return end

        task.spawn(function()
            while env.KSWalk do
                pcall(function()
                    local remotes = replicatedstorage:FindFirstChild("Remotes")
                    local ev = remotes and remotes:FindFirstChild("UpdateSpeed")
                    if ev then
                        ev:FireServer("Walking")
                    end
                end)

                task.wait()
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto win: fly the winblock chain and drop on the chosen one
    ----------------------------------------------------------------

    local runservice = game:GetService("RunService")

    -- winblock N normally lives under Structure.Stage(N+1).
    -- "before" holds the waypoints that must be flown BEFORE that block is
    -- reachable, so continuing past a block automatically takes the detour.
    local WINBLOCKS = {
        { name = "WinBlock1" },
        { name = "WinBlock2" },
        { name = "WinBlock3", before = {
            Vector3.new(-20, 8, 574),
        } },
        { name = "WinBlock4" },
        { name = "WinBlock5" },
        { name = "WinBlock6", waitTsunami = true, walkAfterWait = true,
          waitAt = Vector3.new(2, 77, 1422), before = {
            Vector3.new(-50, 54, 1497),
        } },
        { name = "WinBlock7" },
        { name = "WinBlock8" },
        { name = "WinBlock9", before = {
            Vector3.new(-1432, 337, 1450),
        } },
        { name = "WinBlock10" },
        { name = "WinBlock11", before = {
            Vector3.new(-4296, 296, 1469),
            Vector3.new(-4324, 440, 1491),
        } },
        { name = "WinBlock12", before = {
            Vector3.new(-4452, 471, 1466),
            Vector3.new(-4501, 471, 1125),
            Vector3.new(-4740, 471, 1367),
            Vector3.new(-4940, 471, 1432),
            Vector3.new(-4993, 471, 1640),
            Vector3.new(-5115, 471, 1121),
            Vector3.new(-5247, 471, 1153),
            Vector3.new(-5126, 471, 1456),
        } },
        { name = "WinBlock13", before = {
            Vector3.new(-5678, 476, 1372),
            Vector3.new(-6186, 489, 1429),
            Vector3.new(-6483, 489, 1383),
        } },
    }

    local flySpeed = tonumber(setdata.flyspeed) or 120
    local chosenWin = math.clamp(tonumber(setdata.winblock) or 1, 1, #WINBLOCKS)

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function winBlockPart(i)
        local def = WINBLOCKS[i]
        if not def then return nil end

        local structure = workspace:FindFirstChild("Structure")
        if not structure then return nil end

        -- the usual layout is Structure.Stage(N+1).WinBlockN
        local stage = structure:FindFirstChild("Stage" .. tostring(i + 1))
        local block = stage and stage:FindFirstChild(def.name)

        -- fall back to a deep search so a renamed stage cannot break the chain
        if not block then
            block = structure:FindFirstChild(def.name, true)
        end

        if not block then return nil end

        if block:IsA("BasePart") then return block end
        return block:FindFirstChildWhichIsA("BasePart", true)
    end

    ----------------------------------------------------------------
    -- flight engine
    --
    -- Uses a BodyVelocity / BodyGyro pair instead of writing CFrame every
    -- frame. That is what a normal fly script does: physics still owns the
    -- character, so nothing has to be anchored and PlatformStand is never
    -- touched. Releasing the movers hands control straight back to the player.
    ----------------------------------------------------------------

    local noclipConn
    local flyBV, flyBG

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

    -- removes the movers and fully restores normal control
    local function stopFlight()
        if flyBV then
            pcall(function() flyBV:Destroy() end)
            flyBV = nil
        end
        if flyBG then
            pcall(function() flyBG:Destroy() end)
            flyBG = nil
        end

        pcall(function()
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.Anchored = false
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end

            -- clean out anything an earlier build may have left behind
            if root then
                for _, n in ipairs({ "BPFly", "BPFlyGyro" }) do
                    local old = root:FindFirstChild(n)
                    if old then old:Destroy() end
                end
            end

            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = false
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
    end

    -- creates the movers if they are missing, e.g. after a respawn
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
            flyBV.Name = "BPFly"
            flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBV.P = 1e4
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end

        if not flyBG then
            flyBG = Instance.new("BodyGyro")
            flyBG.Name = "BPFlyGyro"
            flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBG.P = 1e4
            flyBG.D = 500
            flyBG.CFrame = root.CFrame
            flyBG.Parent = root
        end

        return root
    end

    -- flies to a position, returns true on arrival
    local function flyTo(targetPos, keepAlive)
        if not targetPos then return false end

        while keepAlive() do
            local root = ensureFlight()
            if not root then
                task.wait(0.1)
            else
                local delta = targetPos - root.Position
                local dist = delta.Magnitude

                if dist < 4 then
                    if flyBV then flyBV.Velocity = Vector3.zero end
                    return true
                end

                -- constant speed toward the target, physics does the moving
                flyBV.Velocity = delta.Unit * flySpeed

                if flyBG then
                    flyBG.CFrame = CFrame.new(root.Position, targetPos)
                end

                runservice.Heartbeat:Wait()
            end
        end

        return false
    end

    -- hovers on the spot, used while waiting for a hazard
    local function hover(pos, keepAlive)
        local root = ensureFlight()
        if not root then return end

        if flyBV then
            -- counteract gravity by holding zero velocity
            flyBV.Velocity = Vector3.zero
        end

        if pos then
            local delta = pos - root.Position
            if delta.Magnitude > 2 then
                flyBV.Velocity = delta.Unit * math.min(flySpeed, delta.Magnitude * 4)
            end
        end
    end

    -- Walks the character with the humanoid instead of flying. Used where the
    -- game expects real movement, so no body movers and no noclip.
    local function walkTo(targetPos, keepAlive, timeout)
        if not targetPos then return false end

        timeout = timeout or 15
        local elapsed = 0

        while keepAlive() and elapsed < timeout do
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if not hum or not root then
                task.wait(0.1)
                elapsed = elapsed + 0.1
            else
                local dist = (targetPos - root.Position).Magnitude
                if dist < 5 then
                    return true
                end

                hum:MoveTo(targetPos)
                task.wait(0.1)
                elapsed = elapsed + 0.1
            end
        end

        return false
    end

    -- lands on the block: movers off, collision back on
    local function dropOnto(part, keepAlive)
        stopFlight()
        stopNoclip()

        local elapsed = 0
        while elapsed < 0.4 and keepAlive() do
            local root = getRoot()
            if root and part and part.Parent then
                root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
                root.AssemblyLinearVelocity = Vector3.zero
            end
            task.wait(0.05)
            elapsed = elapsed + 0.05
        end
    end

    ----------------------------------------------------------------
    -- tsunami gate
    ----------------------------------------------------------------

    -- workspace["NPC & Piege"].Tsunami1.Tsunami
    local function tsunamiPart()
        local npc = workspace:FindFirstChild("NPC & Piege")
        local t1 = npc and npc:FindFirstChild("Tsunami1")
        local t = t1 and t1:FindFirstChild("Tsunami")
        if not t then return nil end

        if t:IsA("BasePart") then return t end
        return t:FindFirstChildWhichIsA("BasePart", true)
    end

    local TSUNAMI_X = -150

    -- Hovers in place until the tsunami passes. No anchoring and no
    -- PlatformStand, the body movers hold us up, so control comes straight
    -- back when they are removed.
    local function waitForTsunami(keepAlive, holdPos)
        local part = tsunamiPart()

        if not part then
            warn("[BrainrotPolice] Tsunami not found, skipping the wait")
            return
        end

        local startedBelow = part.Position.X < TSUNAMI_X
        print(("[BrainrotPolice] hovering, waiting for tsunami to pass x=%d (now %.1f)")
            :format(TSUNAMI_X, part.Position.X))

        while keepAlive() do
            hover(holdPos, keepAlive)

            part = tsunamiPart()

            -- the wave despawning also counts as passed
            if not part or not part.Parent then
                print("[BrainrotPolice] tsunami gone, continuing")
                return
            end

            local x = part.Position.X
            local nowBelow = x < TSUNAMI_X

            if nowBelow ~= startedBelow then
                print(("[BrainrotPolice] tsunami passed x=%d (at %.1f)"):format(TSUNAMI_X, x))
                return
            end

            runservice.Heartbeat:Wait()
        end
    end

    elements:Textbox("Fly Speed (default 120)", section, tostring(flySpeed), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        flySpeed = n
        env.setconfig("flyspeed", n)
    end)

    elements:Textbox("Win Block (1 - 13)", section, tostring(chosenWin), function(v)
        local n = tonumber(v)
        if not n then return end
        chosenWin = math.clamp(math.floor(n), 1, #WINBLOCKS)
        env.setconfig("winblock", chosenWin)
    end)

    elements:Toggle("Auto Win", section, setdata.autowin, function(v)
        env.KSWin = v
        env.setconfig("autowin", v)
        if not v then
            stopFlight()
            stopNoclip()
            return
        end

        task.spawn(function()
            local alive = function() return env.KSWin end

            while env.KSWin do
                startNoclip()

                -- walk the chain: hover 8 studs over each block in turn and
                -- only drop once we reach the one the user picked
                for i = 1, chosenWin do
                    if not env.KSWin then break end

                    local def = WINBLOCKS[i]

                    -- some blocks are only reachable once a hazard has moved.
                    -- float above the previous block while we wait.
                    if def.waitTsunami then
                        -- park next to the previous block, not above it
                        local holdPos = def.waitAt

                        if not holdPos then
                            local prev = winBlockPart(i - 1)
                            holdPos = prev and (prev.Position + Vector3.new(0, 8, 0))
                                or (getRoot() and getRoot().Position)
                        end

                        -- move to the waiting spot before holding there
                        if holdPos then
                            flyTo(holdPos, alive)
                            if not env.KSWin then break end
                        end

                        waitForTsunami(alive, holdPos)
                        if not env.KSWin then break end
                    end

                    -- some sections have to be done on foot
                    local onFoot = def.walkAfterWait

                    if onFoot then
                        -- stop flying and hand the character back to physics
                        stopFlight()
                        stopNoclip()
                        print("[BrainrotPolice] walking section before " .. def.name)
                    end

                    -- detour waypoints that lead to this block.
                    -- these MUST be crossed before the block itself, otherwise
                    -- the path cuts straight through the map.
                    if def.before then
                        for wp, point in ipairs(def.before) do
                            if not env.KSWin then break end

                            print(("[BrainrotPolice] waypoint %d/%d before %s -> %s")
                                :format(wp, #def.before, def.name, tostring(point)))

                            local reached
                            if onFoot then
                                reached = walkTo(point, alive)
                            else
                                reached = flyTo(point, alive)
                            end

                            if not reached and env.KSWin then
                                warn("[BrainrotPolice] waypoint not reached: " .. tostring(point))
                            end
                        end
                    end

                    if not env.KSWin then break end

                    local part = winBlockPart(i)

                    if part then
                        if onFoot then
                            -- walk to 20 studs in front of the block, then fly
                            -- again only if we still have blocks to reach
                            local root = getRoot()
                            local from = root and root.Position or part.Position
                            local dir = (part.Position - from)
                            dir = Vector3.new(dir.X, 0, dir.Z)

                            if dir.Magnitude > 0.1 then
                                local stopShort = part.Position - dir.Unit * 20
                                print("[BrainrotPolice] walking to 20 studs before " .. def.name)
                                walkTo(Vector3.new(stopShort.X, part.Position.Y, stopShort.Z), alive)
                            end

                            if not env.KSWin then break end

                            -- resume flying for anything past this block
                            if i < chosenWin then
                                startNoclip()
                            end
                        end

                        print("[BrainrotPolice] flying to " .. def.name)

                        -- hover 8 studs above every block on the way
                        flyTo(part.Position + Vector3.new(0, 8, 0), alive)
                        if not env.KSWin then break end

                        -- only drop on the one the user picked
                        if i == chosenWin then
                            print("[BrainrotPolice] dropping on " .. def.name)
                            dropOnto(part, alive)
                            if env.KSWin then
                                startNoclip()
                            end
                        end
                    else
                        warn("[BrainrotPolice] " .. def.name .. " not found in workspace.Structure")
                    end
                end

                if not env.KSWin then break end

                task.wait(1)
            end

            stopFlight()
            stopNoclip()
        end)
    end)

    ----------------------------------------------------------------
    -- world 1 destroy
    ----------------------------------------------------------------

    elements:Toggle("World 1 Destroy", section, setdata.destroy1, function(v)
        env.KSDestroy = v
        env.setconfig("destroy1", v)
        if not v then return end

        task.spawn(function()
            while env.KSDestroy do
                pcall(function()
                    local npc = workspace:FindFirstChild("NPC & Piege")

                    if npc then
                        local tower = npc:FindFirstChild("LavaTower")
                        local lavaPart = tower and tower:FindFirstChild("LavaPart")
                        if lavaPart then lavaPart:Destroy() end

                        local corridor = npc:FindFirstChild("CorridorTrap")
                        if corridor then corridor:Destroy() end
                    end

                    for _, name in ipairs({ "NPC10", "NPC12" }) do
                        local target = workspace:FindFirstChild(name)
                        if target then target:Destroy() end
                    end
                end)

                task.wait(0.5)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto buy: wait for the shop restock event, buy the selected items
    ----------------------------------------------------------------

    local BUY_ORDER = { "Mysterious", "Rare", "Uncommon", "Common" }
    local BUY_KEY = {
        Mysterious = "buy_mysterious",
        Rare       = "buy_rare",
        Uncommon   = "buy_uncommon",
        Common     = "buy_common",
    }

    local BUY_TIMES = 5
    local BUY_DELAY = 0.2

    local buySelected = {}
    for _, name in ipairs(BUY_ORDER) do
        buySelected[name] = setdata[BUY_KEY[name]] ~= false
    end

    -- Finds a remo remote by name. The old version only looked at
    -- container's direct children, which is why nothing ever fired.
    -- This searches the whole remo package, then ReplicatedStorage.
    local function findRemote(name)
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local index = pkgs and pkgs:FindFirstChild("_Index")

        if index then
            for _, child in pairs(index:GetChildren()) do
                if string.sub(child.Name, 1, 14) == "littensy_remo@" then
                    local found = child:FindFirstChild(name, true)
                    if found then return found end
                end
            end
        end

        return replicatedstorage:FindFirstChild(name, true)
    end

    local function fireBuy(itemName)
        local buyWins = findRemote("BuyWins")
        if not buyWins then return false end

        local ok = pcall(function()
            if typeof(buyWins) == "Instance" and buyWins:IsA("RemoteEvent") then
                buyWins:FireServer(itemName)
            elseif typeof(buyWins) == "Instance" and buyWins:IsA("RemoteFunction") then
                buyWins:InvokeServer(itemName)
            elseif typeof(buyWins) == "table" and type(buyWins.fire) == "function" then
                buyWins:fire(itemName)
            end
        end)

        return ok
    end

    local buyRunning = false

    -- one restock = each selected item bought BUY_TIMES times
    local function onRestock()
        if buyRunning or not env.KSBuy then return end
        buyRunning = true

        for _, itemName in ipairs(BUY_ORDER) do
            if not env.KSBuy then break end

            if buySelected[itemName] then
                for _ = 1, BUY_TIMES do
                    if not env.KSBuy then break end
                    fireBuy(itemName)
                    task.wait(BUY_DELAY)
                end
            end
        end

        buyRunning = false
    end

    for _, itemName in ipairs(BUY_ORDER) do
        elements:Toggle("Buy " .. itemName, section, buySelected[itemName], function(v)
            buySelected[itemName] = v
            env.setconfig(BUY_KEY[itemName], v)
        end)
    end

    local shopConn

    elements:Toggle("Auto Buy (on restock)", section, setdata.autobuy, function(v)
        env.KSBuy = v
        env.setconfig("autobuy", v)

        if shopConn then
            pcall(function() shopConn:Disconnect() end)
            shopConn = nil
        end

        if not v then return end

        local shopUpdate = findRemote("ShopUpdate")

        if not shopUpdate then
            warn("[BrainrotPolice] ShopUpdate not found, Auto Buy cannot arm")
            env.KSBuy = false
            return
        end

        if typeof(shopUpdate) == "Instance" and shopUpdate:IsA("RemoteEvent") then
            shopConn = shopUpdate.OnClientEvent:Connect(function()
                task.spawn(onRestock)
            end)

            if env.BrainrotPolice and env.BrainrotPolice.track then
                env.BrainrotPolice.track(shopConn)
            end

            print("[BrainrotPolice] Auto Buy armed on " .. shopUpdate:GetFullName())
        elseif typeof(shopUpdate) == "table" then
            local connected = pcall(function()
                local fn = shopUpdate.connect or shopUpdate.listen
                if type(fn) == "function" then
                    shopConn = fn(shopUpdate, function()
                        task.spawn(onRestock)
                    end)
                end
            end)

            if connected then
                print("[BrainrotPolice] Auto Buy armed on the remo listener")
            else
                warn("[BrainrotPolice] could not connect to ShopUpdate")
                env.KSBuy = false
            end
        end
    end)
end
