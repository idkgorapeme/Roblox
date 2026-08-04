-- Murder Mystery 2
-- Coin farming, visuals and account chores only. Nothing here reads or
-- reveals player roles, and nothing eliminates other players.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MMCoins = false
    env.MMCoinEsp = false
    env.MMCodes = false
    env.MMQueue = false
    env.MMPrestige = false
    env.MMCrates = false
    env.MMEvents = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.coins = setdata.coins or false
    setdata.coinesp = setdata.coinesp or false
    setdata.codes = setdata.codes or false
    setdata.queue = setdata.queue or false
    setdata.coindelay = setdata.coindelay or 0.12
    setdata.codelist = setdata.codelist or ""
    setdata.prestige = setdata.prestige or false
    setdata.crates = setdata.crates or false
    setdata.events = setdata.events or false
    setdata.cratename = setdata.cratename or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local coinDelay = tonumber(setdata.coindelay) or 0.12
    local codeList = tostring(setdata.codelist or "")

    local function remote(path)
        local node = replicatedstorage
        for _, name in ipairs(path) do
            node = node:FindFirstChild(name)
            if not node then return nil end
        end
        return node
    end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- finding coins
    --
    -- ReplicatedStorage.Coins only holds the templates. In a round the real
    -- ones are spawned somewhere inside the map model (BioLab, Mansion2, ...)
    -- so we search the whole workspace by name instead of a fixed path.
    ----------------------------------------------------------------

    -- names used by the coin templates, so we match the real thing
    local function templateNames()
        local names = {}
        local folder = replicatedstorage:FindFirstChild("Coins")
        if folder then
            for _, c in pairs(folder:GetDescendants()) do
                if c:IsA("BasePart") or c:IsA("Model") then
                    names[string.lower(c.Name)] = true
                end
            end
        end
        return names
    end

    local coinNames = templateNames()

    local function looksLikeCoin(inst)
        local n = string.lower(inst.Name)
        if coinNames[n] then return true end
        return string.find(n, "coin", 1, true) ~= nil
    end

    local function coinPart(inst)
        if inst:IsA("BasePart") then return inst end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart end
            return inst:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    local function findCoins()
        local out = {}
        local seen = {}

        for _, inst in pairs(workspace:GetDescendants()) do
            if not seen[inst] and (inst:IsA("BasePart") or inst:IsA("Model")) and looksLikeCoin(inst) then
                -- skip the part inside a coin model, we want the model once
                local parentIsCoin = inst.Parent and inst.Parent ~= workspace
                    and (inst.Parent:IsA("Model") and looksLikeCoin(inst.Parent))

                if not parentIsCoin then
                    local part = coinPart(inst)
                    if part then
                        seen[inst] = true
                        out[#out + 1] = { inst = inst, part = part }
                    end
                end
            end
        end

        return out
    end

    ----------------------------------------------------------------
    -- coin farm
    ----------------------------------------------------------------

    elements:Textbox("Coin Delay (default 0.12)", section, tostring(coinDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        coinDelay = n
        env.setconfig("coindelay", n)
    end)

    elements:Button("Count Coins", section, function()
        local coins = findCoins()
        print("[BrainrotPolice] " .. #coins .. " coins visible")
        for i, c in ipairs(coins) do
            if i > 3 then break end
            print("  " .. c.inst:GetFullName())
        end
    end)

    elements:Toggle("Auto Collect Coins", section, setdata.coins, function(v)
        env.MMCoins = v
        env.setconfig("coins", v)
        if not v then return end

        task.spawn(function()
            local announced = false

            while env.MMCoins do
                local root = getRoot()

                if root then
                    local coins = findCoins()

                    if not announced then
                        print("[BrainrotPolice] coin farm: " .. #coins .. " coins found")
                        if #coins == 0 then
                            warn("[BrainrotPolice] no coins found, press Count Coins during a round")
                        end
                        announced = true
                    end

                    -- remember where we were so the farm is not disruptive
                    local origin = root.CFrame

                    for _, c in ipairs(coins) do
                        if not env.MMCoins then break end

                        if c.part and c.part.Parent then
                            local r = getRoot()
                            if r then
                                r.CFrame = CFrame.new(c.part.Position)
                                r.AssemblyLinearVelocity = Vector3.zero

                                -- coins are collected on touch
                                if firetouchinterest then
                                    pcall(function()
                                        firetouchinterest(r, c.part, 0)
                                        firetouchinterest(r, c.part, 1)
                                    end)
                                end

                                task.wait(coinDelay)
                            end
                        end
                    end

                    local r = getRoot()
                    if r then
                        r.CFrame = origin
                        r.AssemblyLinearVelocity = Vector3.zero
                    end
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- coin esp
    ----------------------------------------------------------------

    local coinHighlights = {}

    local function clearCoinEsp()
        for inst, hl in pairs(coinHighlights) do
            pcall(function() hl:Destroy() end)
            coinHighlights[inst] = nil
        end
    end

    elements:Toggle("Coin ESP", section, setdata.coinesp, function(v)
        env.MMCoinEsp = v
        env.setconfig("coinesp", v)

        if not v then
            clearCoinEsp()
            return
        end

        task.spawn(function()
            while env.MMCoinEsp do
                pcall(function()
                    local coins = findCoins()
                    local seen = {}

                    for _, c in ipairs(coins) do
                        seen[c.inst] = true

                        if not coinHighlights[c.inst] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "BPCoin"
                            hl.FillColor = Color3.fromRGB(255, 210, 0)
                            hl.FillTransparency = 0.3
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Adornee = c.inst
                            hl.Parent = c.inst

                            coinHighlights[c.inst] = hl
                        end
                    end

                    for inst, hl in pairs(coinHighlights) do
                        if not seen[inst] or not inst.Parent then
                            pcall(function() hl:Destroy() end)
                            coinHighlights[inst] = nil
                        end
                    end
                end)

                task.wait(1)
            end

            clearCoinEsp()
        end)
    end)

    ----------------------------------------------------------------
    -- code redeem
    ----------------------------------------------------------------

    elements:Textbox("Codes (comma separated)", section, codeList, function(v)
        codeList = v or ""
        env.setconfig("codelist", codeList)
    end)

    elements:Button("Redeem Codes", section, function()
        local rf = remote({ "Remotes", "Extras", "RedeemCode" })
        if not rf then
            warn("[BrainrotPolice] RedeemCode remote not found")
            return
        end

        local n = 0
        for code in string.gmatch(codeList, "[^,]+") do
            code = code:match("^%s*(.-)%s*$")
            if code ~= "" then
                local ok, res = pcall(function()
                    return rf:InvokeServer(code)
                end)
                print("[BrainrotPolice] code " .. code .. " -> " .. tostring(ok and res or "failed"))
                n = n + 1
                task.wait(0.5)
            end
        end

        if n == 0 then
            warn("[BrainrotPolice] no codes entered")
        end
    end)

    ----------------------------------------------------------------
    -- 1v1 auto requeue
    ----------------------------------------------------------------

    elements:Toggle("Auto Requeue 1v1", section, setdata.queue, function(v)
        env.MMQueue = v
        env.setconfig("queue", v)
        if not v then return end

        task.spawn(function()
            while env.MMQueue do
                pcall(function()
                    local ev = remote({ "Remotes", "CustomGames", "Join1v1Queue" })
                    if ev then ev:FireServer() end
                end)

                task.wait(10)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- round rewards
    ----------------------------------------------------------------

    elements:Button("Claim Last Round Rewards", section, function()
        local rf = remote({ "Remotes", "Gameplay", "GetLastRoundRewards" })
        if not rf then
            warn("[BrainrotPolice] GetLastRoundRewards not found")
            return
        end

        local ok, res = pcall(function() return rf:InvokeServer() end)
        print("[BrainrotPolice] round rewards -> " .. tostring(ok and res or "failed"))
    end)

    ----------------------------------------------------------------
    -- prestige
    ----------------------------------------------------------------

    elements:Button("Prestige Now", section, function()
        local ev = remote({ "Remotes", "Inventory", "Prestige" })
        if not ev then
            warn("[BrainrotPolice] Prestige remote not found")
            return
        end

        pcall(function() ev:FireServer() end)
        print("[BrainrotPolice] prestige requested, level "
            .. tostring(plr:GetAttribute("Level"))
            .. " prestige " .. tostring(plr:GetAttribute("Prestige")))
    end)

    elements:Toggle("Auto Prestige", section, setdata.prestige, function(v)
        env.MMPrestige = v
        env.setconfig("prestige", v)
        if not v then return end

        task.spawn(function()
            while env.MMPrestige do
                pcall(function()
                    local ev = remote({ "Remotes", "Inventory", "Prestige" })
                    if ev then ev:FireServer() end
                end)

                task.wait(5)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- event quest track
    ----------------------------------------------------------------

    elements:Button("Show Events", section, function()
        local rf = remote({ "Remotes", "Events", "GetEvents" })
        if not rf then
            warn("[BrainrotPolice] GetEvents not found")
            return
        end

        local ok, res = pcall(function() return rf:InvokeServer() end)
        if not ok then
            warn("[BrainrotPolice] GetEvents failed")
            return
        end

        local httpservice = game:GetService("HttpService")
        local okj, encoded = pcall(function() return httpservice:JSONEncode(res) end)
        local text = okj and encoded or tostring(res)

        print("[BrainrotPolice] events: " .. text)
        pcall(function() setclipboard(text) end)
    end)

    -- claims every reward index on the event track, the server rejects
    -- the ones that are not unlocked yet
    elements:Toggle("Auto Claim Event Track", section, setdata.events, function(v)
        env.MMEvents = v
        env.setconfig("events", v)
        if not v then return end

        task.spawn(function()
            while env.MMEvents do
                local claim = remote({ "SharedServices", "EventInfoService1", "EventList",
                    "Easter2025", "Remotes", "ClaimTrackReward" })

                if claim then
                    for i = 1, 50 do
                        if not env.MMEvents then break end
                        pcall(function() claim:FireServer(i) end)
                        task.wait(0.1)
                    end
                end

                task.wait(30)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- crates
    ----------------------------------------------------------------

    local crateName = tostring(setdata.cratename or "")

    elements:Textbox("Crate Name (see Dump Inventory)", section, crateName, function(v)
        crateName = v or ""
        env.setconfig("cratename", crateName)
    end)

    elements:Button("Open Crate Once", section, function()
        local rf = remote({ "Remotes", "Shop", "OpenCrate" })
        if not rf then
            warn("[BrainrotPolice] OpenCrate not found")
            return
        end

        if crateName == "" then
            warn("[BrainrotPolice] set a crate name first, use Dump Inventory to find it")
            return
        end

        local ok, res = pcall(function() return rf:InvokeServer(crateName) end)
        print("[BrainrotPolice] open " .. crateName .. " -> " .. tostring(ok and res or "failed"))
    end)

    elements:Toggle("Auto Open Crates", section, setdata.crates, function(v)
        env.MMCrates = v
        env.setconfig("crates", v)
        if not v then return end

        if crateName == "" then
            warn("[BrainrotPolice] set a crate name first, use Dump Inventory to find it")
            env.MMCrates = false
            return
        end

        task.spawn(function()
            while env.MMCrates do
                pcall(function()
                    local rf = remote({ "Remotes", "Shop", "OpenCrate" })
                    if rf then rf:InvokeServer(crateName) end
                end)

                task.wait(2)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- inventory dump
    --
    -- Craft, Salvage and Recycle all take item identifiers that are not
    -- guessable. This prints the real inventory so those can be wired up
    -- against actual data instead of an assumption.
    ----------------------------------------------------------------

    elements:Button("Dump Inventory (copies)", section, function()
        local httpservice = game:GetService("HttpService")
        local out = {}

        local function add(line)
            out[#out + 1] = line
            print(line)
        end

        add("PlaceId: " .. tostring(game.PlaceId))
        add("Level: " .. tostring(plr:GetAttribute("Level"))
            .. "  Prestige: " .. tostring(plr:GetAttribute("Prestige"))
            .. "  XP: " .. tostring(plr:GetAttribute("XP")))

        local function dumpRF(label, path, ...)
            local rf = remote(path)
            if not rf then
                add("== " .. label .. ": remote not found")
                return
            end

            local ok, res = pcall(function(...)
                return rf:InvokeServer(...)
            end, ...)

            if not ok then
                add("== " .. label .. ": call failed")
                return
            end

            local okj, encoded = pcall(function()
                return httpservice:JSONEncode(res)
            end)

            add("== " .. label .. ":")
            add(okj and encoded or tostring(res))
        end

        dumpRF("GetFullInventory", { "Remotes", "Extras", "GetFullInventory" })
        dumpRF("GetPlayerData", { "Remotes", "Extras", "GetPlayerData" })
        dumpRF("CheckInventory", { "Remotes", "Extras", "CheckInventory" })

        local text = table.concat(out, "\n")

        pcall(function()
            writefile("BrainrotPolice/inventory_" .. tostring(game.PlaceId) .. ".txt", text)
        end)

        local copied = pcall(function() setclipboard(text) end)
        print("[BrainrotPolice] inventory dump copied=" .. tostring(copied))
    end)
end
