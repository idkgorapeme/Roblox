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
        { name = "WinBlock6", waitTsunami = true, before = {
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

    -- noclip so walls and stage geometry cannot block the flight
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

        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            -- Physics state leaves the character limp and unmovable
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end

    -- flies to a position, returns true on arrival
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

            local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = true end
        end

        return false
    end

    -- lands on the block: collision back on, pinned in place briefly
    local function dropOnto(part, keepAlive)
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

    -- workspace["NPC & Piege"].Tsunami1.Tsunami
    local function tsunamiPart()
        local npc = workspace:FindFirstChild("NPC & Piege")
        local t1 = npc and npc:FindFirstChild("Tsunami1")
        local t = t1 and t1:FindFirstChild("Tsunami")
        if not t then return nil end

        if t:IsA("BasePart") then return t end
        return t:FindFirstChildWhichIsA("BasePart", true)
    end

    -- blocks until the tsunami has passed x = -150.
    -- the wave can travel either way, so we remember which side it started
    -- on and wait for it to cross over, instead of assuming a direction.
    local TSUNAMI_X = -150

    -- Holds the character perfectly still in the air until the tsunami passes.
    -- Setting the CFrame on a timer is not enough, gravity still acts between
    -- updates, so the root part is ANCHORED for the whole wait. Nothing can
    -- pull us down while anchored.
    local function waitForTsunami(keepAlive, holdPos)
        local part = tsunamiPart()

        if not part then
            warn("[BrainrotPolice] Tsunami not found, skipping the wait")
            return
        end

        local root = getRoot()
        local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")

        -- park us on the spot and freeze
        if root and holdPos then
            root.CFrame = CFrame.new(holdPos)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end

        if hum then
            hum.PlatformStand = true
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.Physics)
            end)
        end

        if root then
            root.Anchored = true
        end

        -- give the character back to the player: unanchor AND undo the
        -- humanoid state, otherwise PlatformStand / Physics keep input dead
        local function unfreeze()
            local r = getRoot()
            if r then
                r.Anchored = false
                r.AssemblyLinearVelocity = Vector3.zero
            end

            local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if h then
                h.PlatformStand = false
                pcall(function()
                    h:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end
        end

        local startedBelow = part.Position.X < TSUNAMI_X
        print(("[BrainrotPolice] holding above the block, waiting for tsunami to pass x=%d (now %.1f)")
            :format(TSUNAMI_X, part.Position.X))

        while keepAlive() do
            -- a respawn gives us a brand new root, so re-anchor it
            local r = getRoot()
            if r and not r.Anchored then
                if holdPos then
                    r.CFrame = CFrame.new(holdPos)
                end
                r.Anchored = true
            end

            part = tsunamiPart()

            -- the wave despawning also counts as passed
            if not part or not part.Parent then
                print("[BrainrotPolice] tsunami gone, continuing")
                unfreeze()
                return
            end

            local x = part.Position.X
            local nowBelow = x < TSUNAMI_X

            if nowBelow ~= startedBelow then
                print(("[BrainrotPolice] tsunami passed x=%d (at %.1f)"):format(TSUNAMI_X, x))
                unfreeze()
                return
            end

            task.wait(0.1)
        end

        -- toggled off mid wait
        unfreeze()
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
            -- never leave the character frozen or unmovable
            pcall(function()
                local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                if root then root.Anchored = false end
            end)
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
                        local prev = winBlockPart(i - 1)
                        local holdPos = prev and (prev.Position + Vector3.new(0, 8, 0))
                            or (getRoot() and getRoot().Position)

                        waitForTsunami(alive, holdPos)
                        if not env.KSWin then break end
                    end

                    -- detour waypoints that lead to this block.
                    -- these MUST be flown before the block itself, otherwise
                    -- the path cuts straight through the map.
                    if def.before then
                        for wp, point in ipairs(def.before) do
                            if not env.KSWin then break end

                            print(("[BrainrotPolice] waypoint %d/%d before %s -> %s")
                                :format(wp, #def.before, def.name, tostring(point)))

                            local reached = flyTo(point, alive)
                            if not reached and env.KSWin then
                                warn("[BrainrotPolice] waypoint not reached: " .. tostring(point))
                            end
                        end
                    end

                    if not env.KSWin then break end

                    local part = winBlockPart(i)

                    if part then
                        print("[BrainrotPolice] flying to " .. def.name)

                        -- hover 8 studs above every block on the way
                        flyTo(part.Position + Vector3.new(0, 8, 0), alive)
                        if not env.KSWin then break end

                        -- only drop on the one the user picked
                        if i == chosenWin then
                            print("[BrainrotPolice] dropping on " .. def.name)
                            dropOnto(part, alive)
                        end
                    else
                        warn("[BrainrotPolice] " .. def.name .. " not found in workspace.Structure")
                    end
                end

                if not env.KSWin then break end

                task.wait(1)
            end

            pcall(function()
                local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                if root then root.Anchored = false end
            end)
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
