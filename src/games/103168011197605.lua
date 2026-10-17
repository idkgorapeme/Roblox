-- Guess The Real Size! / Size Duel (PlaceId 103168011197605)
--
-- From the depth 4 dump:
--   workspace.SizeDuelTables
--     Table01 / PartyTable3_A/3_B / PartyTable4_A/4_B
--     attribs: CategoryLabel ("NORMAL", "ANIMALS", "ANIME 🍥", "FICTION",
--              "GEOGRAPHY", "ASTRONOMY 🌌", "FRUITS 🍓", "ALL", "3 PLAYERS", ...)
--              Hard (bool), PoolDomain, PoolCategory, Status ("0/2 · Take a seat"),
--              LayoutIndex, Party (3/4)
--     Seats: Seat1..SeatN, each with a ProximityPrompt
--            action="Sit" / "Stand up", object="Size Duel", dist 8
--   workspace.Table01 (several standalone duel tables)
--   workspace.ChairShowcaseBuild
--     abyss, champi, chrono, demon, divin, feu, love, monarch, office, radio,
--     rgb, seraph, toilet
--     attribs: ChairId, PriceText ("💰 35000"), ActionText ("Buy · 35000")
--     Seat part -> BuyPrompt (hold 1.0) + RobuxPrompt (hold 0.6)
--   workspace.SizeDuelSpectateScreen x3 (SurfaceGui)
--   workspace.ChairShowcase, Zone shop, ShopTP, SizeDuelSpawn x9
--   ReplicatedStorage.SizeDuel
--     ModuleScripts: Admin, Blaster, BlasterFx, ChairFx, Cosmetics, Daily,
--                    DailyRewards, Effects, Images, KillFx, Levitate, Playtime,
--                    PlaytimeRewards, Products, Rewards, RobuxShop, Shop,
--                    Spectate, Style, Tutorial, ViewportFx
--     RemoteEvent Event      <- the only remote, arguments unknown
--   ReplicatedStorage.SizeDuelChairMeshes/galaxy
--   PlayerGui: SizeDuelDaily, SizeDuelPlaytime, SizeDuelRewards, SizeDuelShop,
--              SizeDuelTroll, SizeDuelTutorial, SizeDuelUI, ProximityPrompts
--   leaderstats: IQ, Precision, Streak, Wins
--   player attributes: Coins, Hints, Inks, Freezes, Revives, Sabotages, Scares,
--     IQMultiplier, Chair, Blaster, Kill, Pass_x2Coins/x2IQ/x2Wins,
--     Playtime, SessionPlaytime, ProgressSaved, Admin, Streak

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local httpservice = game:GetService("HttpService")
    local plr = players.LocalPlayer

    env.SDSit = false
    env.SDClaim = false
    env.SDLog = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.sit = setdata.sit or false
    setdata.claim = setdata.claim or false
    setdata.category = setdata.category or "Any"
    setdata.hardonly = setdata.hardonly or false
    setdata.emptyonly = setdata.emptyonly or true
    setdata.chair = setdata.chair or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(data))

    local LOG_FILE = "BrainrotPolice/sizeduel_traffic.txt"

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

    local function fullName(inst)
        local ok, name = pcall(function() return inst:GetFullName() end)
        if not ok then return tostring(inst) end
        if #name > 200 then name = name:sub(1, 200) .. "..." end
        return name
    end

    local function attr(name)
        local ok, v = pcall(function() return plr:GetAttribute(name) end)
        if ok then return v end
        return nil
    end

    local function leaderstat(name)
        local ls = plr:FindFirstChild("leaderstats")
        local stat = ls and ls:FindFirstChild(name)
        return stat and stat.Value or nil
    end

    local function tweenTo(pos)
        local root = getRoot()
        if not root or not pos then return false end

        return pcall(function()
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end

    local function firePrompt(prompt)
        if not prompt then return false end

        pcall(function()
            if prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
            if prompt.MaxActivationDistance < 100 then prompt.MaxActivationDistance = 100 end
        end)

        if fireproximityprompt then
            return pcall(fireproximityprompt, prompt)
        end

        return false
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

    local lastReport = ""

    ----------------------------------------------------------------
    -- tables
    ----------------------------------------------------------------

    -- table models live in workspace.SizeDuelTables and as bare Table01 models
    -- directly in workspace
    local function isTableModel(inst)
        if not inst:IsA("Model") then return false end
        if inst:FindFirstChildWhichIsA("Seat", true) == nil then return false end

        local parent = inst.Parent
        if parent and parent.Name == "SizeDuelTables" then return true end

        return inst.Name == "Table01" or inst.Name:find("Table", 1, true) ~= nil
    end

    local function tableList()
        local out = {}
        local seen = {}

        local function add(t)
            if seen[t] then return end
            seen[t] = true

            local seats = {}
            for _, d in ipairs(t:GetDescendants()) do
                if d:IsA("Seat") then seats[#seats+1] = d end
            end

            local occupied = 0
            for _, seat in ipairs(seats) do
                local occupant = nil
                pcall(function() occupant = seat.Occupant end)
                if occupant then occupied = occupied + 1 end
            end

            local function a(name)
                local ok, v = pcall(function() return t:GetAttribute(name) end)
                if ok then return v end
                return nil
            end

            out[#out+1] = {
                model = t,
                name = t.Name,
                category = tostring(a("CategoryLabel") or "?"),
                hard = a("Hard") == true,
                status = tostring(a("Status") or "?"),
                domain = tostring(a("PoolDomain") or "?"),
                pool = a("PoolCategory"),
                party = tonumber(a("Party")),
                seats = seats,
                occupied = occupied,
                free = #seats - occupied,
            }
        end

        local folder = workspace:FindFirstChild("SizeDuelTables")
        if folder then
            for _, c in ipairs(folder:GetChildren()) do
                if isTableModel(c) then add(c) end
            end
        end

        for _, c in ipairs(workspace:GetChildren()) do
            if isTableModel(c) then add(c) end
        end

        return out
    end

    local function categories()
        local set = { Any = true }
        for _, t in ipairs(tableList()) do
            if t.category ~= "?" then set[t.category] = true end
        end

        local out = {}
        for k in pairs(set) do out[#out+1] = k end
        table.sort(out)
        return out
    end

    local function tableScore(t)
        -- prefer hard, empty and low party size, then the fullest free table
        local score = 0
        if t.hard then score = score + 100 end
        score = score + t.free * 10
        if t.free == 0 then score = score - 50 end
        if t.party then score = score - t.party end
        return score
    end

    local function bestTable()
        local best, bestScore = nil, -math.huge

        for _, t in ipairs(tableList()) do
            local ok = true

            if setdata.category ~= "Any" and t.category ~= setdata.category then ok = false end
            if setdata.hardonly and not t.hard then ok = false end
            if setdata.emptyonly and t.occupied > 0 then ok = false end
            if t.free <= 0 then ok = false end

            if ok then
                local score = tableScore(t)
                if score > bestScore then best, bestScore = t, score end
            end
        end

        return best, bestScore
    end

    local function freeSeat(t)
        for _, seat in ipairs(t.seats) do
            local occupant = nil
            pcall(function() occupant = seat.Occupant end)

            if not occupant then
                local prompt = seat:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled and tostring(prompt.ActionText):lower():find("sit", 1, true) then
                    return seat, prompt
                end
            end
        end

        return nil, nil
    end

    local function sitAt(t)
        if not t then return false end

        local seat, prompt = freeSeat(t)
        if not seat then
            print("[BrainrotPolice] no free seat at " .. t.name)
            return false
        end

        tweenTo(posOf(seat))
        task.wait(0.15)
        firePrompt(prompt)

        print(string.format("[BrainrotPolice] sat at %s | %s | hard %s | %s",
            t.name, t.category, tostring(t.hard), t.status))
        return true
    end

    local function standUp()
        local found = 0

        for _, t in ipairs(tableList()) do
            for _, seat in ipairs(t.seats) do
                local prompt = seat:FindFirstChildWhichIsA("ProximityPrompt", true)

                if prompt and tostring(prompt.ActionText):lower():find("stand", 1, true) then
                    tweenTo(posOf(seat))
                    task.wait(0.1)
                    firePrompt(prompt)
                    found = found + 1
                end
            end
        end

        print("[BrainrotPolice] stand up prompts fired: " .. found)
        return found
    end

    local function tableText()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== tables ===")

        local list = tableList()
        table.sort(list, function(a, b)
            if a.category == b.category then
                if a.hard == b.hard then return a.status < b.status end
                return a.hard and not b.hard
            end
            return a.category < b.category
        end)

        for _, t in ipairs(list) do
            add(string.format("%-16s | %-14s | hard %-5s | %3d/%d seats | %s | %s",
                t.name, t.category, tostring(t.hard), t.occupied, #t.seats,
                t.status, t.domain))
        end

        add("total tables: " .. #list)
        return table.concat(L, "\n")
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.SDSit then
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")

                if hum and hum.SeatPart then
                    task.wait(2)
                else
                    local t = bestTable()

                    if t then
                        sitAt(t)
                        task.wait(2)
                    else
                        task.wait(1.5)
                    end
                end
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- chairs
    ----------------------------------------------------------------

    local function chairList()
        local out = {}
        local folder = workspace:FindFirstChild("ChairShowcaseBuild")
        if not folder then return out end

        for _, c in ipairs(folder:GetChildren()) do
            if c:IsA("Model") then
                local function a(name)
                    local ok, v = pcall(function() return c:GetAttribute(name) end)
                    if ok then return v end
                    return nil
                end

                local seat = c:FindFirstChild("Seat", true) or c:FindFirstChildWhichIsA("BasePart", true)
                local buy = seat and seat:FindFirstChild("BuyPrompt", true)
                local robux = seat and seat:FindFirstChild("RobuxPrompt", true)

                out[#out+1] = {
                    model = c,
                    id = tostring(a("ChairId") or c.Name),
                    name = c.Name,
                    price = tostring(a("PriceText") or "?"),
                    action = tostring(a("ActionText") or "?"),
                    buy = buy,
                    robux = robux,
                    pos = seat and posOf(seat) or nil,
                }
            end
        end

        table.sort(out, function(a, b) return a.id < b.id end)
        return out
    end

    local function chairText()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== chairs ===")

        for _, c in ipairs(chairList()) do
            add(string.format("%-10s | %-28s | %-16s | buy prompt %s | robux %s",
                c.id, c.name, c.price,
                c.buy and (c.buy.Enabled and "enabled" or "disabled") or "none",
                c.robux and (c.robux.Enabled and "enabled" or "disabled") or "none"))
        end

        return table.concat(L, "\n")
    end

    local function buyChair(id)
        for _, c in ipairs(chairList()) do
            if c.id == id then
                if not c.buy then
                    print("[BrainrotPolice] " .. id .. " has no BuyPrompt (already owned?)")
                    return false
                end

                tweenTo(c.pos)
                task.wait(0.15)
                firePrompt(c.buy)
                print(string.format("[BrainrotPolice] bought %s (%s) | coins before %s",
                    c.name, c.price, tostring(attr("Coins"))))
                task.wait(0.8)
                print("[BrainrotPolice] coins after " .. tostring(attr("Coins")))
                return true
            end
        end

        print("[BrainrotPolice] chair not found: " .. tostring(id))
        return false
    end

    ----------------------------------------------------------------
    -- rewards (gui buttons)
    ----------------------------------------------------------------

    local REWARD_GUIS = { "SizeDuelDaily", "SizeDuelPlaytime", "SizeDuelRewards" }

    local function guiByName(name)
        local gui = plr:FindFirstChildOfClass("PlayerGui")
        return gui and gui:FindFirstChild(name)
    end

    local function rewardButtons()
        local out = {}

        for _, guiName in ipairs(REWARD_GUIS) do
            local gui = guiByName(guiName)
            if gui then
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("TextButton") or d:IsA("ImageButton") then
                        local text = ""
                        if d:IsA("TextButton") then text = tostring(d.Text or "") end

                        out[#out+1] = {
                            button = d,
                            gui = guiName,
                            text = text,
                            name = d.Name,
                            label = guiName .. "." .. fullName(d) .. (text ~= "" and (" [" .. text .. "]") or ""),
                        }
                    end
                end
            end
        end

        return out
    end

    local function clickRewards()
        local list = rewardButtons()
        local clicked = 0

        for _, entry in ipairs(list) do
            local haystack = string.lower(entry.text .. " " .. entry.name)
            local wanted = haystack:find("claim", 1, true)
                or haystack:find("collect", 1, true)
                or haystack:find("reward", 1, true)
                or haystack:find("open", 1, true)

            if wanted and entry.button.Visible then
                local ok = pcall(function() entry.button:Activate() end)
                if ok then
                    clicked = clicked + 1
                    print("[BrainrotPolice] clicked " .. entry.label)
                    task.wait(0.3)
                end
            end
        end

        if clicked == 0 then
            print("[BrainrotPolice] no claim buttons matched, use List GUI Buttons and send the names")
        else
            print("[BrainrotPolice] clicked " .. clicked .. " buttons | coins " .. tostring(attr("Coins")))
        end

        return clicked
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.SDClaim then
                clickRewards()
                task.wait(20)
            else
                task.wait(0.5)
            end
        end
    end)

    local function guiText()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== gui buttons ===")

        for _, entry in ipairs(rewardButtons()) do
            add(string.format("%-22s | %-10s | visible %-5s | %s",
                entry.gui, entry.button.ClassName, tostring(entry.button.Visible), entry.label))
        end

        return table.concat(L, "\n")
    end

    ----------------------------------------------------------------
    -- stats
    ----------------------------------------------------------------

    local function statsText()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== Guess The Real Size! ===")
        add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
        add(string.format("IQ %s | Precision %s | Streak %s | Wins %s",
            tostring(leaderstat("IQ")), tostring(leaderstat("Precision")),
            tostring(leaderstat("Streak")), tostring(leaderstat("Wins"))))
        add(string.format("Coins %s | Hints %s | Inks %s | IQ multiplier %s",
            tostring(attr("Coins")), tostring(attr("Hints")),
            tostring(attr("Inks")), tostring(attr("IQMultiplier"))))
        add(string.format("chair %s | blaster %s | kill effect %s",
            tostring(attr("Chair")), tostring(attr("Blaster")), tostring(attr("Kill"))))
        add(string.format("freezes %s | revives %s | sabotages %s | scares %s",
            tostring(attr("Freezes")), tostring(attr("Revives")),
            tostring(attr("Sabotages")), tostring(attr("Scares"))))
        add(string.format("playtime %s | session %s | progress saved %s",
            tostring(attr("Playtime")), tostring(attr("SessionPlaytime")),
            tostring(attr("ProgressSaved"))))
        add(string.format("passes: x2Coins %s | x2IQ %s | x2Wins %s | admin %s",
            tostring(attr("Pass_x2Coins")), tostring(attr("Pass_x2IQ")),
            tostring(attr("Pass_x2Wins")), tostring(attr("Admin"))))

        add("")
        add(tableText())

        return table.concat(L, "\n")
    end

    ----------------------------------------------------------------
    -- remote logging
    ----------------------------------------------------------------

    local function eventRemote()
        local folder = replicatedstorage:FindFirstChild("SizeDuel")
        return folder and folder:FindFirstChild("Event")
    end

    local logBuf = {}
    local LOG_MAX = 800

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
        if not hookmetamethod or not getnamecallmethod then return false end

        local wrap = newcclosure or function(f) return f end
        local remote = eventRemote()

        local ok = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                if env.SDLog and self == remote and getnamecallmethod() == "FireServer" then
                    pcall(pushLog, "OUT SizeDuel.Event", ...)
                end

                return original(self, ...)
            end))
        end)

        hookInstalled = ok
        return ok
    end

    local function connectEvent()
        local remote = eventRemote()
        if not remote then return end

        local ok, conn = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                if env.SDLog then
                    pcall(pushLog, "IN SizeDuel.Event", ...)
                end
            end)
        end)

        if ok and conn and registry and registry.track then
            pcall(registry.track, conn)
        end
    end

    ----------------------------------------------------------------
    -- module dump
    ----------------------------------------------------------------

    local MODULES = {
        "Shop", "Rewards", "Daily", "DailyRewards", "Playtime", "PlaytimeRewards",
        "Products", "RobuxShop", "Cosmetics", "Spectate", "Tutorial", "Style",
        "ChairFx", "Blaster", "BlasterFx", "Effects", "KillFx", "Levitate",
        "ViewportFx", "Images",
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
                if n > 14 then
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

    local function dumpModules()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        local folder = replicatedstorage:FindFirstChild("SizeDuel")

        add("=== SizeDuel modules ===")
        add("PlaceId: " .. tostring(game.PlaceId))

        if not folder then
            add("SizeDuel folder missing")
        else
            for _, name in ipairs(MODULES) do
                local m = folder:FindFirstChild(name)

                if m and m:IsA("ModuleScript") then
                    local ok, value = pcall(require, m)
                    add(name .. ": " .. (ok and shallow(value, 0, {}) or ("require failed -> " .. tostring(value))))
                else
                    add(name .. ": missing")
                end
            end

            add("")
            add("=== full folder ===")
            for _, c in ipairs(folder:GetChildren()) do
                add(c.ClassName .. " | " .. c.Name)
            end
        end

        lastReport = table.concat(L, "\n")
        publish("module dump", lastReport, "BrainrotPolice/sizeduel_modules.txt")
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Label("Guess The Real Size!", section)

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
    elements:Label("Tables", section)

    elements:Button("List Tables", section, function()
        local text = tableText()
        lastReport = text
        print(text)
    end)

    local cats = categories()

    elements:Dropdown("Category", section, cats, setdata.category, function(v)
        setdata.category = v
        env.setconfig("category", v)
    end)

    elements:Toggle("Hard mode only", section, setdata.hardonly, function(v)
        setdata.hardonly = v
        env.setconfig("hardonly", v)
    end)

    elements:Toggle("Only empty tables", section, setdata.emptyonly, function(v)
        setdata.emptyonly = v
        env.setconfig("emptyonly", v)
    end)

    elements:Button("Sit At Best Table", section, function()
        local t = bestTable()

        if not t then
            print("[BrainrotPolice] no matching table, loosen the filters or press List Tables")
            return
        end

        sitAt(t)
    end)

    elements:Toggle("Auto Sit", section, setdata.sit, function(v)
        env.SDSit = v
        setdata.sit = v
        env.setconfig("sit", v)

        if v then
            local t = bestTable()
            print("[BrainrotPolice] auto sit on" .. (t and (" | target " .. t.name .. " (" .. t.category .. ")") or " | no matching table"))
        else
            print("[BrainrotPolice] auto sit off")
        end
    end)

    elements:Button("Stand Up", section, function()
        standUp()
    end)

    ----------------------------------------------------------------
    elements:Label("Chairs", section)

    elements:Button("List Chairs", section, function()
        local text = chairText()
        lastReport = text
        print(text)
    end)

    local chairIds = {}
    for _, c in ipairs(chairList()) do chairIds[#chairIds+1] = c.id end

    if #chairIds > 0 then
        elements:Dropdown("Chair", section, chairIds, setdata.chair ~= "" and setdata.chair or chairIds[1], function(v)
            setdata.chair = v
            env.setconfig("chair", v)
        end)
    end

    elements:Button("Buy Selected Chair", section, function()
        if (setdata.chair or "") == "" then
            print("[BrainrotPolice] pick a chair first")
            return
        end

        buyChair(setdata.chair)
    end)

    elements:Button("Teleport To Selected Chair", section, function()
        for _, c in ipairs(chairList()) do
            if c.id == setdata.chair then
                tweenTo(c.pos)
                print("[BrainrotPolice] teleported to " .. c.name .. " (" .. c.price .. ")")
                return
            end
        end

        print("[BrainrotPolice] chair not found")
    end)

    ----------------------------------------------------------------
    elements:Label("Rewards", section)

    elements:Button("List GUI Buttons", section, function()
        local text = guiText()
        lastReport = text
        print(text)
    end)

    elements:Button("Click Claim Buttons", section, function()
        clickRewards()
    end)

    elements:Toggle("Auto Claim Rewards", section, setdata.claim, function(v)
        env.SDClaim = v
        setdata.claim = v
        env.setconfig("claim", v)
        print("[BrainrotPolice] auto claim " .. (v and "on" or "off"))
    end)

    ----------------------------------------------------------------
    elements:Label("Diagnostics", section)

    local logWasOn = false

    elements:Toggle("Log SizeDuel.Event", section, false, function(v)
        env.SDLog = v

        if v then
            logWasOn = true
            installHook()
            print("[BrainrotPolice] logging on, sit at a table / buy a chair / claim a reward")
        elseif logWasOn then
            logWasOn = false
            if writefile and #logBuf > 0 then pcall(writefile, LOG_FILE, table.concat(logBuf, "\n")) end
            print("[BrainrotPolice] logging off, saved to " .. LOG_FILE)
        end
    end)

    elements:Button("Copy Event Log", section, function()
        if #logBuf == 0 then
            print("[BrainrotPolice] event log is empty")
            return
        end

        local ok = pcall(setclipboard, table.concat(logBuf, "\n"))
        print("[BrainrotPolice] " .. (ok and ("copied " .. #logBuf .. " lines") or "could not copy"))
    end)

    elements:Button("Fire SizeDuel.Event", section, function()
        local remote = eventRemote()
        if not remote then
            print("[BrainrotPolice] SizeDuel.Event not found")
            return
        end

        pcall(function() remote:FireServer() end)
        print("[BrainrotPolice] SizeDuel.Event fired with no arguments")
    end)

    elements:Button("Dump Modules", section, function()
        task.spawn(function()
            local ok, err = pcall(dumpModules)
            if not ok then print("[BrainrotPolice] module dump failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Copy Last Report", section, function()
        if lastReport == "" then
            print("[BrainrotPolice] nothing captured yet")
            return
        end

        local ok = pcall(setclipboard, lastReport)
        print("[BrainrotPolice] " .. (ok and "report copied" or "could not copy"))
    end)

    connectEvent()
end
