-- Press Key to Drop! (PlaceId 111746173942635)
--
-- Core loop: buy keycaps, place them on your keyboard, press them, balls drop
-- through the plinko board and pay out.
--
-- Everything gameplay relevant runs through sleitnick's net package:
--   ReplicatedStorage.Packages._Index.sleitnick_net@0.2.0.net
--     RF/Collect                 RF/PlaceSlot        RF/PickupSlot
--     RF/SellSlot                RF/QuickStack       RF/EquipBestBrainrots
--     RF/PurchaseUpgrade         RF/Rebirth          RF/ClaimDailyReward
--     RF/ClaimGroupReward        RF/UnlockBallDropLevel
--     RF/ChangePlinkoWorld       RF/PrestigeAction   RF/RedeemCode
--     RF/MoneyTimeSkipAction     RF/OfflineEarningsAction
--     RE/BallDrop                RE/Weather          RE/LuckyBlock
--     RE/SupplyCrateEvent        RE/SupplyCrateClaim
--   ReplicatedStorage.SpinWheelSystem  RequestSpin, SpinResult,
--                                      SpinStateUpdate, ClaimSpinReward
--   ReplicatedStorage.QuestSystem      QuestAction / QuestUpdated
--   ReplicatedStorage.DailyRewardsSystem, PlaytimeRewardsSystem,
--   DailyQuestSystem, PotionSystem     *Action / *Updated
--   ReplicatedStorage.SkillTreeRemotes PurchaseNode, PurchasePlayerNode
--   ReplicatedStorage.KeyboardSystem   KeyboardInventoryAction, KeyShopAction,
--                                      AutoKeyFarmAction
--   ReplicatedStorage.KeyboardOrders   KeyboardOrdersAction / Event
--
-- Plot side: workspace.Plots.Plot1..6, each with
--   KeyboardKeys/Key_SlotNNN  (the pressable keys)
--   KeyboardBoard/Slots       (inventory board)
--   keyboardEditZone, SellingTable, KeyboardBuy, KeyboardSelling,
--   SpinWheel, BallDrop, UpgradeBoard, PrestigePad, PrestigePortal, CodePad
--
-- Player attributes worth reading:
--   AutoKeyFarmUnlocked / AutoKeyFarmEnabled / AutoKeyFarmRunning
--   UpgradeTreeAutoFarmUnlocked, IsInsideOwnPlot, CurrentPlinkoName,
--   PlinkoCharges, SpinTickets, DailyRewardAvailable,
--   PlaytimeRewardAvailableCount, DailyQuestClaimableCount,
--   PrestigeEligible, Rebirths (leaderstats), Money (formatted string)
--
-- Cmdr / AdminAbuse remotes are deliberately not wired up.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local httpservice = game:GetService("HttpService")
    local plr = players.LocalPlayer

    env.PKPress = false
    env.PKCollect = false
    env.PKRebirth = false
    env.PKClaim = false
    env.PKSpin = false
    env.PKLog = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.press = setdata.press or false
    setdata.collect = setdata.collect or false
    setdata.rebirth = setdata.rebirth or false
    setdata.claim = setdata.claim or false
    setdata.spin = setdata.spin or false
    setdata.pressdelay = tonumber(setdata.pressdelay) or 0.4
    setdata.radius = tonumber(setdata.radius) or 60
    setdata.code = setdata.code or ""
    setdata.node = setdata.node or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(data))

    local pressDelay = math.clamp(tonumber(setdata.pressdelay) or 0.4, 0.1, 3)
    local searchRadius = math.clamp(tonumber(setdata.radius) or 60, 20, 300)

    local LOG_FILE = "BrainrotPolice/presskey_traffic.txt"

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function posOf(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local ok, cf = pcall(function() return inst:GetPivot() end)
            if ok and cf then return cf.Position end
        end
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function attrs()
        local ok, a = pcall(function() return plr:GetAttributes() end)
        return (ok and a) or {}
    end

    local function attr(name)
        return attrs()[name]
    end

    local function attrString(a)
        local keys = {}
        for k in pairs(a) do keys[#keys+1] = k end
        table.sort(keys)

        local out = {}
        for _, k in ipairs(keys) do
            out[#out+1] = k .. "=" .. tostring(a[k])
        end
        return table.concat(out, ", ")
    end

    -- leaderstats.Money is abbreviated ("1K", "2.5M", ...), leaderstats.Rebirths
    -- is a plain number
    local function moneyValue()
        local function parse(text)
            local num, suffix = tostring(text or ""):match("([%d%.,]+)%s*([KkMmBbTtQq]?)")
            if not num then return nil end

            local n = tonumber((num:gsub(",", "")))
            if not n then return nil end

            local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15 })[string.lower(suffix or "")] or 1
            return n * mult
        end

        local ls = plr:FindFirstChild("leaderstats")
        if not ls then return nil end

        local money = ls:FindFirstChild("Money")
        if money then return parse(money.Value) end

        return nil
    end

    local function rebirthCount()
        local ls = plr:FindFirstChild("leaderstats")
        local r = ls and ls:FindFirstChild("Rebirths")
        return r and tonumber(r.Value) or 0
    end

    local function moneyText()
        local ls = plr:FindFirstChild("leaderstats")
        local money = ls and ls:FindFirstChild("Money")
        return money and tostring(money.Value) or "?"
    end

    local function tpTo(pos)
        local root = getRoot()
        if not root or not pos then return false end

        return pcall(function()
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end

    local function publish(name, text, filename)
        if setclipboard then pcall(setclipboard, text) end
        if filename and writefile then pcall(writefile, filename, text) end

        local lines = 1
        for _ in string.gmatch(text, "\n") do lines = lines + 1 end
        print(string.format("[BrainrotPolice] %s: %d lines, copied%s", name, lines,
            filename and (", saved to " .. filename) or ""))

        local shown = 0
        for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
            shown = shown + 1
            if shown > 120 then
                print("[BrainrotPolice] ... output truncated, full report is already copied")
                break
            end
            print(line)
        end
    end

    ----------------------------------------------------------------
    -- net package
    ----------------------------------------------------------------

    local NET_DIRS = { "Packages", "_Index", "sleitnick_net@0.2.0", "net" }

    local function netFolder()
        local node = replicatedstorage
        for _, dir in ipairs(NET_DIRS) do
            node = node and node:FindFirstChild(dir)
        end
        return node
    end

    -- names contain a slash, so FindFirstChild and never dot access
    local function netRemote(kind, name)
        local f = netFolder()
        return f and f:FindFirstChild(kind .. "/" .. name)
    end

    local function netInvoke(name, ...)
        local r = netRemote("RF", name)
        if not r then return nil, "missing RF/" .. tostring(name) end

        local args = table.pack(...)
        local ok, result = pcall(function()
            return r:InvokeServer(table.unpack(args, 1, args.n))
        end)

        if not ok then return nil, tostring(result) end
        return result, nil
    end

    local function netFire(name, ...)
        local r = netRemote("RE", name)
        if not r then return false, "missing RE/" .. tostring(name) end

        local args = table.pack(...)
        local ok = pcall(function()
            r:FireServer(table.unpack(args, 1, args.n))
        end)

        return ok, nil
    end

    local function featureRemote(path, name)
        local node = replicatedstorage
        for _, dir in ipairs(path) do
            node = node and node:FindFirstChild(dir)
        end
        return node and node:FindFirstChild(name)
    end

    local function invokeFeature(path, name, ...)
        local r = featureRemote(path, name)
        if not r then return nil, "missing " .. tostring(name) end

        local args = table.pack(...)
        local ok, result = pcall(function()
            return r:InvokeServer(table.unpack(args, 1, args.n))
        end)

        if not ok then return nil, tostring(result) end
        return result, nil
    end

    local function fireFeature(path, name, ...)
        local r = featureRemote(path, name)
        if not r then return false, "missing " .. tostring(name) end

        local args = table.pack(...)
        local ok = pcall(function()
            r:FireServer(table.unpack(args, 1, args.n))
        end)

        return ok, nil
    end

    ----------------------------------------------------------------
    -- parsing helper for manual arguments
    ----------------------------------------------------------------

    local function parseArgs(text)
        text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return {} end

        local out = {}

        for piece in string.gmatch(text .. ",", "([^,]*),") do
            local v = piece:gsub("^%s+", ""):gsub("%s+$", "")

            if v == "true" then
                out[#out+1] = true
            elseif v == "false" then
                out[#out+1] = false
            elseif tonumber(v) then
                out[#out+1] = tonumber(v)
            elseif (v:sub(1, 1) == "{" and v:sub(-1) == "}") or (v:sub(1, 1) == "[" and v:sub(-1) == "]") then
                local ok, decoded = pcall(function() return httpservice:JSONDecode(v) end)
                if ok then out[#out+1] = decoded else out[#out+1] = v end
            elseif v:sub(1, 1) == "\"" and v:sub(-1) == "\"" then
                out[#out+1] = v:sub(2, -2)
            else
                out[#out+1] = v
            end
        end

        return out
    end

    ----------------------------------------------------------------
    -- keycaps
    ----------------------------------------------------------------

    local function plotsFolder()
        return workspace:FindFirstChild("Plots")
    end

    -- a key model looks like Key_SlotNNN and has a BasePart below it
    local function keyModels()
        local out = {}
        local plots = plotsFolder()
        if not plots then return out end

        for _, plot in ipairs(plots:GetChildren()) do
            local keys = plot:FindFirstChild("KeyboardKeys")
            if keys then
                for _, k in ipairs(keys:GetChildren()) do
                    if k:IsA("Model") or k:IsA("BasePart") then
                        out[#out+1] = { model = k, plot = plot, pos = posOf(k) }
                    end
                end
            end
        end

        return out
    end

    local function countKeys(plot)
        local keys = plot:FindFirstChild("KeyboardKeys")
        return keys and #keys:GetChildren() or 0
    end

    local function nearestKey()
        local root = getRoot()
        if not root then return nil, nil end

        local best, bestDist, bestPlot = nil, math.huge, nil
        local rootPos = root.Position

        for _, k in ipairs(keyModels()) do
            if k.pos then
                local d = (k.pos - rootPos).Magnitude
                if d < bestDist then
                    best, bestDist, bestPlot = k, d, k.plot
                end
            end
        end

        return best, bestDist, bestPlot
    end

    -- pressing is a touch on the keycap, so hopping onto its top surface is the
    -- same thing the game does when you step on a key
    local pressedAt = {}
    local PRESS_RETRY = 1.2

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.PKPress then
                local inside = attr("IsInsideOwnPlot") == true
                local root = getRoot()

                if not root then
                    task.wait(0.5)
                elseif not inside then
                    local note = attr("IsInsideOwnPlot")
                    print("[BrainrotPolice] not inside your own plot (IsInsideOwnPlot=" .. tostring(note) .. "), waiting")
                    task.wait(2)
                else
                    local now = os.clock()
                    local best, bestDist = nil, math.huge
                    local rootPos = root.Position

                    for _, k in ipairs(keyModels()) do
                        if k.pos and (k.pos - rootPos).Magnitude <= searchRadius then
                            local last = pressedAt[k.model]
                            if (not last or now - last > PRESS_RETRY) and (k.pos - rootPos).Magnitude < bestDist then
                                best, bestDist = k, (k.pos - rootPos).Magnitude
                            end
                        end
                    end

                    if best then
                        tpTo(best.pos)
                        task.wait(0.1)
                        pressedAt[best.model] = os.clock()
                        task.wait(pressDelay)
                    else
                        task.wait(0.3)
                    end
                end
            else
                task.wait(0.2)
            end
        end
    end)

    ----------------------------------------------------------------
    -- collect / rebirth / claim / spin
    ----------------------------------------------------------------

    local collectState = { calls = 0, moneyBefore = 0, moneyAfter = 0, lastErr = nil }

    local function doCollect(silent)
        local before = moneyValue()
        local result, err = netInvoke("Collect")

        collectState.calls = collectState.calls + 1
        collectState.lastErr = err

        task.wait(0.35)
        local after = moneyValue()

        if before and after then
            collectState.moneyBefore = before
            collectState.moneyAfter = after
        end

        if not silent then
            print(string.format("[BrainrotPolice] RF/Collect -> %s%s | money %s (%s -> %s)",
                tostring(result), err and (" | " .. err) or "",
                moneyText(), tostring(before), tostring(after)))
        end
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.PKCollect then
                doCollect(true)
                task.wait(1)
            else
                task.wait(0.3)
            end
        end
    end)

    local function doRebirth(silent)
        local before = rebirthCount()
        local result, err = netInvoke("Rebirth")
        task.wait(0.6)

        if not silent then
            print(string.format("[BrainrotPolice] RF/Rebirth -> %s%s | rebirths %d -> %d | eligible %s",
                tostring(result), err and (" | " .. err) or "",
                before, rebirthCount(), tostring(attr("PrestigeEligible"))))
        end
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.PKRebirth then
                doRebirth(true)
                task.wait(3)
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- daily / playtime / quests / potions
    ----------------------------------------------------------------

    local claimJobs = {
        { label = "Daily Reward", flag = "DailyRewardAvailable", path = nil, net = "ClaimDailyReward" },
        { label = "Group Reward", flag = nil, path = nil, net = "ClaimGroupReward" },
        { label = "Offline Earnings", flag = "OfflineEarningsWindowOpen", path = nil, net = "OfflineEarningsAction", args = { "Claim" } },
        { label = "Playtime Reward", flag = "PlaytimeRewardAvailableCount", path = { "PlaytimeRewardsSystem" }, name = "PlaytimeRewardAction", args = { "Claim" } },
        { label = "Daily Quest", flag = "DailyQuestClaimableCount", path = { "DailyQuestSystem" }, name = "DailyQuestAction", args = { "Claim" } },
        { label = "Quest", flag = nil, path = { "QuestSystem" }, name = "QuestAction", args = { "Claim" } },
        { label = "Potion", flag = "PotionTokenCount", path = { "PotionSystem" }, name = "PotionAction", args = { "Claim" } },
    }

    local claimResults = {}

    local function runClaim(job, silent)
        local result, err

        if job.net then
            result, err = netInvoke(job.net, table.unpack(job.args or {}))
        else
            result, err = invokeFeature(job.path, job.name, table.unpack(job.args or {}))
        end

        claimResults[#claimResults+1] = string.format("%s -> %s%s", job.label, tostring(result), err and (" (" .. err .. ")") or "")

        if not silent then
            print("[BrainrotPolice] " .. claimResults[#claimResults])
        end

        return result, err
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.PKClaim then
                for _, job in ipairs(claimJobs) do
                    local flag = job.flag and attr(job.flag)
                    local ready = true

                    if job.flag == "DailyRewardAvailable" then
                        ready = flag == true
                    elseif job.flag == "PlaytimeRewardAvailableCount" or job.flag == "DailyQuestClaimableCount" or job.flag == "PotionTokenCount" then
                        ready = (tonumber(flag) or 0) > 0
                    elseif job.flag == "OfflineEarningsWindowOpen" then
                        ready = flag == true
                    elseif job.flag == "GroupRewardState" then
                        local s = tostring(flag)
                        ready = s == "claimable" or s == "ready" or s == "unclaimed"
                    end

                    if ready then
                        runClaim(job, true)
                        task.wait(0.5)
                    end
                end

                task.wait(20)
            else
                task.wait(0.5)
            end
        end
    end)

    local function doSpin(silent)
        local tickets = tonumber(attr("SpinTickets")) or 0

        fireFeature({ "SpinWheelSystem" }, "RequestSpin")
        task.wait(0.8)

        local result = invokeFeature({ "SpinWheelSystem" }, "ClaimSpinReward")
        -- the wheel may also hand out a reward through SpinResult, claim is best effort

        if not silent then
            print(string.format("[BrainrotPolice] spin: tickets %d | request fired | claim -> %s",
                tickets, tostring(result)))
        end
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.PKSpin then
                doSpin(true)
                task.wait(5)
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- upgrades + skill tree + shop actions
    ----------------------------------------------------------------

    local function purchaseUpgrade(id, silent)
        local result, err = netInvoke("PurchaseUpgrade", id)

        if not silent then
            print(string.format("[BrainrotPolice] RF/PurchaseUpgrade(%s) -> %s%s | money %s",
                tostring(id), tostring(result), err and (" | " .. err) or "", moneyText()))
        end

        return result, err
    end

    local function purchaseNode(nodeId, playerNode, silent)
        local name = playerNode and "PurchasePlayerNode" or "PurchaseNode"
        local result, err = invokeFeature({ "SkillTreeRemotes" }, name, nodeId)

        if not silent then
            print(string.format("[BrainrotPolice] %s(%s) -> %s%s", name, tostring(nodeId), tostring(result), err and (" | " .. err) or ""))
        end

        return result, err
    end

    ----------------------------------------------------------------
    -- config module dump
    ----------------------------------------------------------------

    local CONFIG_NAMES = {
        "BallDropConfig", "UpgradesConfig", "RebirthConfig", "PrestigeConfig",
        "PlinkoWorldConfig", "PlinkoBallConfig", "KeyboardKeyConfig",
        "KeyboardOrdersConfig", "SpinWheelConfig", "SupplyCrateConfig",
        "LuckyBlockConfig", "CodesConfig", "DailyRewardsConfig",
        "PlaytimeRewardsConfig", "QuestConfig", "DailyQuestConfig",
        "PotionConfig", "GroupRewardConfig", "PassConfig", "BoostTypes",
        "CurrencyTypes", "Brainrots",
    }

    local function shallow(v, depth, seen)
        depth = depth or 0
        local t = typeof(v)

        if t == "table" then
            if seen[v] then return "<cycle>" end
            if depth >= 2 then return "{...}" end

            seen[v] = true
            local parts = {}
            local n = 0

            for k, val in pairs(v) do
                n = n + 1
                if n > 16 then
                    parts[#parts+1] = "..."
                    break
                end
                parts[#parts+1] = tostring(k) .. "=" .. shallow(val, depth + 1, seen)
            end

            seen[v] = nil
            return "{" .. table.concat(parts, ", ") .. "}"
        end

        if t == "Instance" then return "<" .. v.ClassName .. " " .. v.Name .. ">" end
        if t == "string" and #v > 100 then return string.format("%q..", string.sub(v, 1, 100)) end

        return tostring(v)
    end

    local lastReport = ""

    local function dumpConfigs()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        local cfg = replicatedstorage:FindFirstChild("Config")
        add("=== Config modules ===")

        if not cfg then
            add("Config folder missing")
        else
            for _, name in ipairs(CONFIG_NAMES) do
                local m = cfg:FindFirstChild(name)
                if m and m:IsA("ModuleScript") then
                    local ok, result = pcall(require, m)
                    add(name .. ": " .. (ok and shallow(result, 0, {}) or ("require failed -> " .. tostring(result))))
                else
                    add(name .. ": missing")
                end
            end
        end

        local shared = replicatedstorage:FindFirstChild("Shared")
        if shared then
            add("")
            add("=== plot utils ===")

            for _, name in ipairs({ "PlotUtils", "State", "BallDropBallUtils", "BallDropFreeUtils", "UpgradesUtils" }) do
                local m = shared:FindFirstChild(name)
                if m and m:IsA("ModuleScript") then
                    local ok, result = pcall(require, m)
                    add(name .. ": " .. (ok and shallow(result, 0, {}) or ("require failed -> " .. tostring(result))))
                end
            end
        end

        lastReport = table.concat(L, "\n")
        publish("config dump", lastReport, "BrainrotPolice/presskey_config.txt")
    end

    local function plotsText()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== plots ===")
        add("inside own plot: " .. tostring(attr("IsInsideOwnPlot")))
        add("money " .. moneyText() .. " | rebirths " .. tostring(rebirthCount()))

        local plots = plotsFolder()
        if plots then
            for _, p in ipairs(plots:GetChildren()) do
                local keys = countKeys(p)
                add(string.format("%s | keys %d | pos %s", p.Name, keys, tostring(posOf(p))))
            end
        end

        return table.concat(L, "\n")
    end

    local function statsText()
        local a = attrs()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== Press Key to Drop! ===")
        add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
        add(string.format("money %s | rebirths %d | prestige eligible %s",
            moneyText(), rebirthCount(), tostring(a.PrestigeEligible)))

        add(string.format("auto key farm: unlocked %s (tree %s) | enabled %s | running %s | speed tier %s",
            tostring(a.AutoKeyFarmUnlocked), tostring(a.UpgradeTreeAutoFarmUnlocked),
            tostring(a.AutoKeyFarmEnabled), tostring(a.AutoKeyFarmRunning),
            tostring(a.AutoKeyFarmSpeedTier)))

        add(string.format("plinko: %s | max level %s | charges %s | drops in flight %s",
            tostring(a.CurrentPlinkoName), tostring(a.MaxPlinkoUnlocked),
            tostring(a.PlinkoCharges), tostring(a.PlinkoDropsInFlight)))

        add(string.format("spin tickets %s | keys regen %s | combo %s/%s",
            tostring(a.SpinTickets), tostring(a.KeyboardKeyRegenTime),
            tostring(a.KeyboardCombo), tostring(a.KeyboardComboMax)))

        add(string.format("rewards: daily %s | playtime %s | daily quests %s | potions %s | event tokens %s",
            tostring(a.DailyRewardAvailable), tostring(a.PlaytimeRewardAvailableCount),
            tostring(a.DailyQuestClaimableCount), tostring(a.PotionTokenCount),
            tostring(a.EventTokens)))

        add("")
        add(plotsText())

        return table.concat(L, "\n")
    end

    ----------------------------------------------------------------
    -- traffic logger
    ----------------------------------------------------------------

    local logBuf = {}
    local LOG_MAX = 1200
    local watched = {}

    local function refreshWatched()
        local f = netFolder()
        if f then
            for _, r in ipairs(f:GetChildren()) do
                if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") or r:IsA("RemoteFunction") then
                    watched[r] = r.Name
                end
            end
        end

        for _, folderName in ipairs({
            "SpinWheelSystem", "QuestSystem", "DailyRewardsSystem",
            "PlaytimeRewardsSystem", "DailyQuestSystem", "PotionSystem",
            "SkillTreeRemotes", "KeyboardSystem", "KeyboardOrders",
            "WorldTravelSystem", "EventRemotes", "RemoteEvents", "Remotes"
        }) do
            local folder = replicatedstorage:FindFirstChild(folderName)
            if folder then
                for _, r in ipairs(folder:GetChildren()) do
                    if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") or r:IsA("RemoteFunction") then
                        watched[r] = folderName .. "." .. r.Name
                    end
                end
            end
        end
    end

    local function pushLog(tag, ...)
        local args = table.pack(...)
        local parts = {}

        for i = 1, math.min(args.n, 8) do
            local v = args[i]
            local ok, s = pcall(function()
                if type(v) == "table" then
                    local inner = {}
                    local n = 0
                    for k, val in pairs(v) do
                        n = n + 1
                        if n > 10 then
                            inner[#inner+1] = "..."
                            break
                        end
                        inner[#inner+1] = tostring(k) .. "=" .. tostring(val)
                    end
                    return "{" .. table.concat(inner, ", ") .. "}"
                elseif typeof(v) == "Instance" then
                    return "<" .. v.ClassName .. " " .. v.Name .. ">"
                end
                return tostring(v)
            end)

            parts[#parts+1] = ok and s or "<err>"
        end

        local line = string.format("%s %s %s", os.date("%H:%M:%S"), tag, table.concat(parts, " | "))
        print("[BrainrotPolice] " .. line)

        logBuf[#logBuf+1] = line
        if #logBuf > LOG_MAX then table.remove(logBuf, 1) end
    end

    local hookInstalled = false

    local function installHook()
        if hookInstalled then return true end
        if not hookmetamethod or not getnamecallmethod then
            print("[BrainrotPolice] no hookmetamethod, outgoing traffic cannot be logged")
            return false
        end

        refreshWatched()

        local wrap = newcclosure or function(f) return f end

        local ok = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                local method = getnamecallmethod()

                if env.PKLog and watched[self] and (method == "FireServer" or method == "InvokeServer") then
                    pcall(pushLog, "OUT " .. watched[self], ...)
                end

                return original(self, ...)
            end))
        end)

        hookInstalled = ok
        if not ok then print("[BrainrotPolice] could not hook __namecall") end
        return ok
    end

    local lastEvents = {}

    local function connectEvents()
        refreshWatched()

        for remote, label in pairs(watched) do
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                local ok, conn = pcall(function()
                    return remote.OnClientEvent:Connect(function(...)
                        if #lastEvents < 150 then
                            local parts = {}
                            local args = table.pack(...)
                            for i = 1, math.min(args.n, 5) do
                                parts[#parts+1] = tostring(args[i])
                            end
                            lastEvents[#lastEvents+1] = label .. "(" .. table.concat(parts, ", ") .. ")"
                        end

                        if env.PKLog then
                            pcall(pushLog, "IN " .. label, ...)
                        end
                    end)
                end)

                if ok and conn and registry and registry.track then
                    pcall(registry.track, conn)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Label("Press Key to Drop!", section)

    elements:Button("Show Stats", section, function()
        local text = statsText()
        lastReport = text
        print(text)
    end)

    elements:Button("Copy Stats", section, function()
        local text = statsText()
        lastReport = text
        print("[BrainrotPolice] " .. (pcall(setclipboard, text) and "stats copied" or "could not copy"))
    end)

    ----------------------------------------------------------------
    elements:Label("Keys", section)

    elements:Toggle("Auto Press Keys (own plot only)", section, setdata.press, function(v)
        env.PKPress = v
        setdata.press = v
        env.setconfig("press", v)
        print("[BrainrotPolice] auto press " .. (v and ("on, radius " .. searchRadius .. " studs") or "off"))
    end)

    elements:Textbox("Press delay (seconds)", section, tostring(pressDelay), function(v)
        local n = tonumber(v)
        if not n then return end

        pressDelay = math.clamp(n, 0.1, 3)
        setdata.pressdelay = pressDelay
        env.setconfig("pressdelay", pressDelay)
    end)

    elements:Textbox("Search radius (studs)", section, tostring(searchRadius), function(v)
        local n = tonumber(v)
        if not n then return end

        searchRadius = math.clamp(n, 20, 300)
        setdata.radius = searchRadius
        env.setconfig("radius", searchRadius)
    end)

    elements:Button("Press Nearest Key", section, function()
        local key, dist = nearestKey()
        if not key then
            print("[BrainrotPolice] no keycaps found in workspace.Plots")
            return
        end

        tpTo(key.pos)
        task.wait(0.15)
        print(string.format("[BrainrotPolice] stepped on %s (%.0f studs) in %s | inside own plot %s",
            key.model.Name, dist or -1, key.plot.Name, tostring(attr("IsInsideOwnPlot"))))
    end)

    elements:Button("List Plots And Key Counts", section, function()
        local text = plotsText()
        lastReport = text
        print(text)
    end)

    elements:Button("Try In-Game Auto Key Farm", section, function()
        local paths = { { "KeyboardSystem" } }
        local attempts = { { "Enable" }, { "enable" }, { true }, { "Toggle" }, { "Start" }, { "Auto" } }

        if attr("AutoKeyFarmUnlocked") ~= true then
            print("[BrainrotPolice] AutoKeyFarmUnlocked is false, the in-game auto farm needs the skill tree unlock")
        end

        for _, args in ipairs(attempts) do
            local result, err = invokeFeature(paths[1], "AutoKeyFarmAction", table.unpack(args))
            print(string.format("[BrainrotPolice] AutoKeyFarmAction(%s) -> %s%s | enabled %s | running %s",
                tostring(args[1]), tostring(result), err and (" (" .. err .. ")") or "",
                tostring(attr("AutoKeyFarmEnabled")), tostring(attr("AutoKeyFarmRunning"))))

            if result ~= nil then break end
            task.wait(0.2)
        end
    end)

    ----------------------------------------------------------------
    elements:Label("Money, rebirth, rewards", section)

    elements:Toggle("Auto Collect", section, setdata.collect, function(v)
        env.PKCollect = v
        setdata.collect = v
        env.setconfig("collect", v)
        print("[BrainrotPolice] auto collect " .. (v and "on" or "off"))
    end)

    elements:Button("Collect Now", section, function()
        doCollect(false)
    end)

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.PKRebirth = v
        setdata.rebirth = v
        env.setconfig("rebirth", v)
        print("[BrainrotPolice] auto rebirth " .. (v and "on" or "off"))
    end)

    elements:Button("Rebirth Now", section, function()
        doRebirth(false)
    end)

    elements:Button("Claim Everything Once", section, function()
        claimResults = {}

        for _, job in ipairs(claimJobs) do
            runClaim(job, false)
            task.wait(0.4)
        end

        print("[BrainrotPolice] money now " .. moneyText())
    end)

    elements:Toggle("Auto Claim Rewards", section, setdata.claim, function(v)
        env.PKClaim = v
        setdata.claim = v
        env.setconfig("claim", v)
        print("[BrainrotPolice] auto claim " .. (v and "on" or "off"))
    end)

    elements:Toggle("Auto Spin", section, setdata.spin, function(v)
        env.PKSpin = v
        setdata.spin = v
        env.setconfig("spin", v)
        print("[BrainrotPolice] auto spin " .. (v and ("on | tickets " .. tostring(attr("SpinTickets"))) or "off"))
    end)

    elements:Button("Spin Now", section, function()
        doSpin(false)
    end)

    ----------------------------------------------------------------
    elements:Label("Upgrades and skill tree", section)

    elements:Textbox("Upgrade id / node id", section, setdata.node or "", function(v)
        setdata.node = v
        env.setconfig("node", v)
    end)

    elements:Button("Buy Upgrade", section, function()
        if (setdata.node or "") == "" then
            print("[BrainrotPolice] set an upgrade id first, use Dump Configs to see the ids")
            return
        end

        purchaseUpgrade(setdata.node, false)
    end)

    elements:Button("Buy Skill Tree Node", section, function()
        if (setdata.node or "") == "" then
            print("[BrainrotPolice] set a node id first")
            return
        end

        purchaseNode(setdata.node, false, false)
    end)

    elements:Button("Buy Player Skill Node", section, function()
        if (setdata.node or "") == "" then
            print("[BrainrotPolice] set a node id first")
            return
        end

        purchaseNode(setdata.node, true, false)
    end)

    elements:Button("Unlock Ball Drop Level", section, function()
        local result, err = netInvoke("UnlockBallDropLevel")
        print("[BrainrotPolice] RF/UnlockBallDropLevel -> " .. tostring(result) .. (err and (" (" .. err .. ")") or "")
            .. " | max level " .. tostring(attr("MaxPlinkoUnlocked")))
    end)

    elements:Button("Change Plinko World", section, function()
        local result, err = netInvoke("ChangePlinkoWorld")
        print("[BrainrotPolice] RF/ChangePlinkoWorld -> " .. tostring(result) .. (err and (" (" .. err .. ")") or "")
            .. " | current " .. tostring(attr("CurrentPlinkoName")))
    end)

    elements:Button("Prestige", section, function()
        local result, err = netInvoke("PrestigeAction")
        print("[BrainrotPolice] RF/PrestigeAction -> " .. tostring(result) .. (err and (" (" .. err .. ")") or "")
            .. " | eligible " .. tostring(attr("PrestigeEligible")))
    end)

    ----------------------------------------------------------------
    elements:Label("Keyboard slots and shop", section)

    elements:Button("Quick Stack", section, function()
        local result, err = netInvoke("QuickStack")
        print("[BrainrotPolice] RF/QuickStack -> " .. tostring(result) .. (err and (" (" .. err .. ")") or ""))
    end)

    elements:Button("Equip Best Brainrots", section, function()
        local result, err = netInvoke("EquipBestBrainrots")
        print("[BrainrotPolice] RF/EquipBestBrainrots -> " .. tostring(result) .. (err and (" (" .. err .. ")") or ""))
    end)

    elements:Button("Sell Slot", section, function()
        local result, err = netInvoke("SellSlot", 1)
        print("[BrainrotPolice] RF/SellSlot(1) -> " .. tostring(result) .. (err and (" (" .. err .. ")") or ""))
    end)

    elements:Button("Pickup Slot", section, function()
        local result, err = netInvoke("PickupSlot", 1)
        print("[BrainrotPolice] RF/PickupSlot(1) -> " .. tostring(result) .. (err and (" (" .. err .. ")") or ""))
    end)

    elements:Button("Open Key Shop (action)", section, function()
        local result, err = invokeFeature({ "KeyboardSystem" }, "KeyShopAction", "Open")
        print("[BrainrotPolice] KeyShopAction(Open) -> " .. tostring(result) .. (err and (" (" .. err .. ")") or ""))
    end)

    elements:Button("Keyboard Orders (action)", section, function()
        local result, err = invokeFeature({ "KeyboardOrders" }, "KeyboardOrdersAction", "Get")
        print("[BrainrotPolice] KeyboardOrdersAction(Get) -> " .. tostring(result) .. (err and (" (" .. err .. ")") or ""))
    end)

    ----------------------------------------------------------------
    elements:Label("Codes and travel", section)

    elements:Textbox("Code", section, setdata.code or "", function(v)
        setdata.code = v
        env.setconfig("code", v)
    end)

    elements:Button("Redeem Code", section, function()
        if (setdata.code or "") == "" then
            print("[BrainrotPolice] enter a code first")
            return
        end

        local result, err = netInvoke("RedeemCode", setdata.code)
        print(string.format("[BrainrotPolice] RF/RedeemCode(%s) -> %s%s",
            setdata.code, tostring(result), err and (" (" .. err .. ")") or ""))
    end)

    elements:Button("Teleport (WorldTravelSystem)", section, function()
        local result, err = fireFeature({ "WorldTravelSystem" }, "TeleportRequest")
        print("[BrainrotPolice] TeleportRequest fired " .. (err and ("error: " .. err) or "ok"))
    end)

    elements:Button("Request Rejoin", section, function()
        local result, err = fireFeature({ "AutoRejoinSystem" }, "RequestRejoin")
        print("[BrainrotPolice] RequestRejoin fired " .. (err and ("error: " .. err) or "ok"))
    end)

    ----------------------------------------------------------------
    elements:Label("Diagnostics", section)

    elements:Button("Dump Configs", section, function()
        task.spawn(function()
            local ok, err = pcall(dumpConfigs)
            if not ok then print("[BrainrotPolice] config dump failed: " .. tostring(err)) end
        end)
    end)

    local logOn = false

    elements:Toggle("Log Remote Traffic", section, false, function(v)
        env.PKLog = v

        if v then
            logOn = true
            installHook()
            print("[BrainrotPolice] logging on, press one key by hand / collect / buy one upgrade")
        elseif logOn then
            logOn = false
            if writefile and #logBuf > 0 then pcall(writefile, LOG_FILE, table.concat(logBuf, "\n")) end
            print("[BrainrotPolice] logging off, saved to " .. LOG_FILE)
        end
    end)

    elements:Button("Copy Traffic Log", section, function()
        if #logBuf == 0 then
            print("[BrainrotPolice] traffic log is empty")
            return
        end

        local ok = pcall(setclipboard, table.concat(logBuf, "\n"))
        print("[BrainrotPolice] " .. (ok and ("copied " .. #logBuf .. " lines") or "could not copy"))
    end)

    elements:Button("Clear Traffic Log", section, function()
        logBuf = {}
        print("[BrainrotPolice] traffic log cleared")
    end)

    elements:Button("Show Last Server Events", section, function()
        if #lastEvents == 0 then
            print("[BrainrotPolice] no server events seen yet")
            return
        end

        for i = math.max(1, #lastEvents - 29), #lastEvents do
            print(string.format("  %d: %s", i, lastEvents[i]))
        end
    end)

    elements:Button("Copy Last Server Events", section, function()
        if #lastEvents == 0 then
            print("[BrainrotPolice] no server events seen yet")
            return
        end

        local ok = pcall(setclipboard, table.concat(lastEvents, "\n"))
        print("[BrainrotPolice] " .. (ok and "events copied" or "could not copy"))
    end)

    elements:Button("Copy Last Report", section, function()
        if lastReport == "" then
            print("[BrainrotPolice] nothing captured yet")
            return
        end

        local ok = pcall(setclipboard, lastReport)
        print("[BrainrotPolice] " .. (ok and "report copied" or "could not copy"))
    end)

    ----------------------------------------------------------------
    elements:Label("Manual remote tool", section)

    local netNames = {}
    local nf = netFolder()
    if nf then
        for _, r in ipairs(nf:GetChildren()) do
            if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") or r:IsA("UnreliableRemoteEvent") then
                netNames[#netNames+1] = r.Name
            end
        end
        table.sort(netNames)
    end

    local manualRemote = netNames[1] or "RF/Collect"

    if #netNames > 0 then
        elements:Dropdown("Net remote", section, netNames, manualRemote, function(v)
            manualRemote = v
        end)
    end

    elements:Textbox("Arguments (comma separated, JSON allowed)", section, setdata.args or "", function(v)
        setdata.args = v
        env.setconfig("args", v)
    end)

    elements:Button("Run Net Remote", section, function()
        -- resolve by the full child name, they already carry the RF/ or RE/ prefix
        local f = netFolder()
        local remote = f and f:FindFirstChild(manualRemote)

        if not remote then
            print("[BrainrotPolice] remote not found: " .. tostring(manualRemote))
            return
        end

        local args = parseArgs(setdata.args or "")
        local ok, err

        if remote:IsA("RemoteFunction") then
            local result
            ok, result = pcall(function()
                return remote:InvokeServer(table.unpack(args))
            end)
            print(string.format("[BrainrotPolice] %s -> %s", manualRemote, tostring(result)))
        else
            ok, err = pcall(function()
                remote:FireServer(table.unpack(args))
            end)
            print("[BrainrotPolice] " .. manualRemote .. " " .. (ok and "fired" or ("failed: " .. tostring(err))))
        end
    end)

    connectEvents()
    refreshWatched()
end
