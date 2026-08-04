-- +1 Speed Keyboard Escape | Candy & Chocolate

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local runservice = game:GetService("RunService")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.KEWin1 = false
    env.KEWin2 = false
    env.KEDestroy = false
    env.KECoins = false
    env.KEBuy = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.win1 = setdata.win1 or false
    setdata.win2 = setdata.win2 or false
    setdata.destroy3 = setdata.destroy3 or false
    setdata.coins = setdata.coins or false
    setdata.coindelay = setdata.coindelay or 0.25
    setdata.autobuy = setdata.autobuy or false
    setdata.buy_mysterious = setdata.buy_mysterious ~= false
    setdata.buy_rare = setdata.buy_rare ~= false
    setdata.buy_uncommon = setdata.buy_uncommon ~= false
    setdata.buy_common = setdata.buy_common ~= false
    setdata.buycount = setdata.buycount or 5
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

    -- keeps the speed counter ticking while we fly
    local function sendWalking()
        pcall(function()
            local remotes = replicatedstorage:FindFirstChild("Remotes")
            local ev = remotes and remotes:FindFirstChild("UpdateSpeed")
            if ev then
                ev:FireServer("Walking")
            end
        end)
    end

    -- fires UpdateSpeed on a loop for as long as keepAlive holds
    local function startWalkingSpam(keepAlive)
        task.spawn(function()
            while keepAlive() do
                sendWalking()
                task.wait(0.1)
            end
        end)
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
            startWalkingSpam(alive)

            while env.KEWin1 do
                flyToPath(alive, "Boards&Gamepass", "WinsLeaderboard")
                if not env.KEWin1 then break end

                flyToPath(alive, "Structure", "Stage1", "SAS", "WinBlock32")
                if not env.KEWin1 then break end

                -- landing: collision back on and pin us on the block for the
                -- 1s wait, otherwise noclip drops us straight through the map
                holdAt(posOf(resolve("Structure", "Stage1", "SAS", "WinBlock32")), 0.2, alive)
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
            startWalkingSpam(alive)

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

                -- full respawn, not just a teleport back
                stopNoclip()

                local oldChar = plr.Character

                pcall(function()
                    local hum = oldChar and oldChar:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.PlatformStand = false
                    end
                end)

                -- ask the game to respawn us. break joints is what actually
                -- kills the rig, some games ignore Health = 0 alone.
                pcall(function()
                    if oldChar then
                        local hum = oldChar:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Health = 0 end
                        oldChar:BreakJoints()
                    end
                end)

                -- wait for a genuinely NEW character instance, not the old one
                local newChar
                local waitedRespawn = 0
                while waitedRespawn < 15 and env.KEWin2 do
                    local c = plr.Character
                    if c and c ~= oldChar then
                        local hum = c:FindFirstChildOfClass("Humanoid")
                        local root = c:FindFirstChild("HumanoidRootPart")
                        if hum and root and hum.Health > 0 then
                            newChar = c
                            break
                        end
                    end

                    task.wait(0.25)
                    waitedRespawn = waitedRespawn + 0.25
                end

                if not env.KEWin2 then break end

                if not newChar then
                    warn("[BrainrotPolice] respawn timed out, continuing anyway")
                end

                -- let the spawn settle, then wait the requested 5 seconds
                local waited = 0
                while waited < 5 and env.KEWin2 do
                    task.wait(0.1)
                    waited = waited + 0.1
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

    local BUY_DELAY = 0.2

    local buyCount = tonumber(setdata.buycount) or 5

    local buySelected = {}
    for _, name in ipairs(BUY_ORDER) do
        buySelected[name] = setdata[BUY_KEY[name]] ~= false
    end

    -- Searches the whole remo package, not just container's direct children,
    -- which is why the old version never found the remotes.
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

        return (pcall(function()
            if typeof(buyWins) == "Instance" and buyWins:IsA("RemoteEvent") then
                buyWins:FireServer(itemName)
            elseif typeof(buyWins) == "Instance" and buyWins:IsA("RemoteFunction") then
                buyWins:InvokeServer(itemName)
            elseif typeof(buyWins) == "table" and type(buyWins.fire) == "function" then
                buyWins:fire(itemName)
            end
        end))
    end

    local buyRunning = false

    -- one restock = each selected item bought buyCount times
    local function onRestock()
        if buyRunning or not env.KEBuy then return end
        buyRunning = true

        for _, itemName in ipairs(BUY_ORDER) do
            if not env.KEBuy then break end

            if buySelected[itemName] then
                for _ = 1, buyCount do
                    if not env.KEBuy then break end
                    fireBuy(itemName)
                    task.wait(BUY_DELAY)
                end
            end
        end

        buyRunning = false
    end

    elements:Textbox("Buy Amount (default 5)", section, tostring(buyCount), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        buyCount = math.floor(n)
        env.setconfig("buycount", buyCount)
    end)

    for _, itemName in ipairs(BUY_ORDER) do
        elements:Toggle("Buy " .. itemName, section, buySelected[itemName], function(v)
            buySelected[itemName] = v
            env.setconfig(BUY_KEY[itemName], v)
        end)
    end

    local shopConn

    elements:Toggle("Auto Buy (on restock)", section, setdata.autobuy, function(v)
        env.KEBuy = v
        env.setconfig("autobuy", v)

        if shopConn then
            pcall(function() shopConn:Disconnect() end)
            shopConn = nil
        end

        if not v then return end

        local shopUpdate = findRemote("ShopUpdate")

        if not shopUpdate then
            warn("[BrainrotPolice] ShopUpdate not found, Auto Buy cannot arm")
            env.KEBuy = false
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
                env.KEBuy = false
            end
        end
    end)
end
