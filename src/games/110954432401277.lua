-- Needle In A Haystack (PlaceId 110954432401277) -- lobby
--
-- The haystack itself runs in a match place, ActiveRun is empty while sitting
-- in the lobby. This module covers everything the lobby exposes:
--
--   ReplicatedStorage.Lobby.Remotes
--     RemoteFunction ClassAction        class select / class info
--     RemoteEvent    SettingsUpdate    SfxVolume / MusicVolume
--     RemoteFunction EventRsvpCheck     read the current event RSVP state
--     RemoteEvent    EventRsvpDone      RSVP for the event
--     RemoteFunction GemDailyClaim      daily gem chest
--     RemoteEvent    OpenMenu/CloseMenu UI
--     RemoteEvent    CreateGame         start a run
--     RemoteEvent    CancelHold
--     RemoteEvent    LeaveSquad
--     RemoteEvent    Membership
--     RemoteEvent    Rejoin
--
-- Player attributes: Gems, DailyStreak, DailyNextAt, DailyClaimable, DailyDay,
-- DailyAmounts, ClassKey, ClassSlots, GroupRewardState, PB_* and Rank_*,
-- SfxVolume, MusicVolume, ActiveRun.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local httpservice = game:GetService("HttpService")
    local plr = players.LocalPlayer

    env.NIHDaily = false
    env.NIHGroup = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.daily = setdata.daily or false
    setdata.group = setdata.group or false
    setdata.args = setdata.args or ""
    setdata.class = setdata.class or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(data))

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function lobby()
        return replicatedstorage:FindFirstChild("Lobby")
    end

    local function remotesFolder()
        local l = lobby()
        return l and l:FindFirstChild("Remotes")
    end

    local function remote(name)
        local f = remotesFolder()
        return f and f:FindFirstChild(name)
    end

    local function attr(name)
        local ok, v = pcall(function() return plr:GetAttribute(name) end)
        if ok then return v end
        return nil
    end

    local function attrsOf()
        local ok, attrs = pcall(function() return plr:GetAttributes() end)
        if not ok or not attrs then return {} end
        return attrs
    end

    local function attrString(attrs)
        local keys = {}
        for k in pairs(attrs) do keys[#keys+1] = k end
        table.sort(keys)

        local out = {}
        for _, k in ipairs(keys) do
            out[#out+1] = k .. "=" .. tostring(attrs[k])
        end
        return table.concat(out, ", ")
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

    local lastReport = ""

    ----------------------------------------------------------------
    -- remote helpers
    ----------------------------------------------------------------

    -- parses "1, hello, true, {\"a\":1}" into real arguments
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
            elseif v == "nil" then
                out[#out+1] = nil
            elseif tonumber(v) then
                out[#out+1] = tonumber(v)
            elseif (v:sub(1, 1) == "{" and v:sub(-1) == "}") or (v:sub(1, 1) == "[" and v:sub(-1) == "]") then
                local ok, decoded = pcall(function() return httpservice:JSONDecode(v) end)
                if ok then out[#out+1] = decoded else out[#out+1] = v end
            elseif (v:sub(1, 1) == "\"" and v:sub(-1) == "\"") then
                out[#out+1] = v:sub(2, -2)
            else
                out[#out+1] = v
            end
        end

        return out
    end

    local function callRemote(name, method, argsText)
        local r = remote(name)
        if not r then
            print("[BrainrotPolice] remote not found: " .. tostring(name))
            return nil
        end

        local args = parseArgs(argsText)

        if method == "InvokeServer" then
            if not r:IsA("RemoteFunction") then
                print("[BrainrotPolice] " .. name .. " is a " .. r.ClassName .. ", use FireServer")
                return nil
            end

            local ok, result = pcall(function()
                return r:InvokeServer(table.unpack(args, 1, #args))
            end)

            if not ok then
                print("[BrainrotPolice] " .. name .. " invoke failed: " .. tostring(result))
                return nil
            end

            print("[BrainrotPolice] " .. name .. " returned: " .. tostring(result))
            return result
        end

        if not r:IsA("RemoteEvent") and not r:IsA("UnreliableRemoteEvent") then
            print("[BrainrotPolice] " .. name .. " is a " .. r.ClassName .. ", use InvokeServer")
            return nil
        end

        local ok, err = pcall(function()
            r:FireServer(table.unpack(args, 1, #args))
        end)

        print("[BrainrotPolice] " .. name .. (ok and " fired" or (" failed: " .. tostring(err))))
        return ok
    end

    ----------------------------------------------------------------
    -- daily gems
    ----------------------------------------------------------------

    local function dailyAmounts()
        local raw = attr("DailyAmounts")
        if type(raw) == "table" then return raw end
        if type(raw) == "string" then
            local ok, decoded = pcall(function() return httpservice:JSONDecode(raw) end)
            if ok and type(decoded) == "table" then return decoded end
        end
        return {}
    end

    local function daysLeft()
        local nextAt = tonumber(attr("DailyNextAt"))
        if not nextAt then return nil end
        return math.max(0, nextAt - os.time())
    end

    local function dailyStatus()
        local left = daysLeft()
        local amounts = dailyAmounts()
        local day = tonumber(attr("DailyDay")) or 1

        return string.format("day %d | claimable %s | next in %s | rewards %s",
            day,
            tostring(attr("DailyClaimable")),
            left and (math.floor(left / 60) .. "m " .. (left % 60) .. "s") or "?",
            #amounts > 0 and table.concat(amounts, "/") or "?")
    end

    local function claimDaily(silent)
        local r = remote("GemDailyClaim")
        if not r then
            print("[BrainrotPolice] GemDailyClaim remote missing")
            return nil
        end

        local g0 = tonumber(attr("Gems")) or 0
        local ok, result = pcall(function() return r:InvokeServer() end)

        if not ok then
            print("[BrainrotPolice] daily claim failed: " .. tostring(result))
            return nil
        end

        task.wait(0.6)
        local g1 = tonumber(attr("Gems")) or 0

        if not silent then
            print(string.format("[BrainrotPolice] daily claim -> %s | gems %d -> %d (%+d) | %s",
                tostring(result), g0, g1, g1 - g0, dailyStatus()))
        end

        return result
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.NIHDaily then
                local claimable = attr("DailyClaimable") == true
                local left = daysLeft()

                if claimable or (left and left <= 0) then
                    claimDaily(false)
                    task.wait(3)
                end

                task.wait(5)
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- group reward
    ----------------------------------------------------------------

    local function groupPrompt()
        local groupReward = workspace:FindFirstChild("GroupReward")
        if not groupReward then return nil end

        local hay = groupReward:FindFirstChild("HayPlinth")
        if not hay then return nil end

        return hay:FindFirstChild("GroupRewardPrompt", true)
    end

    local function claimGroupReward()
        local prompt = groupPrompt()
        if not prompt then
            print("[BrainrotPolice] GroupRewardPrompt not found")
            return false
        end

        local pos = posOf(prompt.Parent)
        if pos then
            tpTo(pos)
            task.wait(0.15)
        end

        pcall(function()
            if prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
            if prompt.MaxActivationDistance < 100 then prompt.MaxActivationDistance = 100 end
        end)

        if fireproximityprompt then pcall(fireproximityprompt, prompt) end
        print("[BrainrotPolice] fired GroupRewardPrompt | state " .. tostring(attr("GroupRewardState")))
        return true
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.NIHGroup then
                local state = tostring(attr("GroupRewardState"))
                if state == "claimable" or state == "ready" or state == "unclaimed" then
                    claimGroupReward()
                    task.wait(5)
                end

                task.wait(4)
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- classes
    ----------------------------------------------------------------

    local classChoices = {}

    local function classesModule()
        return replicatedstorage:FindFirstChild("Classes")
    end

    local function collectClassNames()
        local out = {}
        local mod = classesModule()

        if mod then
            local ok, result = pcall(require, mod)
            if ok and type(result) == "table" then
                for k, v in pairs(result) do
                    if type(k) == "string" then
                        out[#out+1] = k
                    elseif type(v) == "table" and type(v.Name) == "string" then
                        out[#out+1] = v.Name
                    end
                end
            end
        end

        if #out == 0 then
            local slots = attr("ClassSlots")
            if type(slots) == "table" and type(slots.slots) == "table" then
                for _, n in ipairs(slots.slots) do out[#out+1] = tostring(n) end
            elseif type(slots) == "string" then
                local ok, decoded = pcall(function() return httpservice:JSONDecode(slots) end)
                if ok and type(decoded) == "table" and type(decoded.slots) == "table" then
                    for _, n in ipairs(decoded.slots) do out[#out+1] = tostring(n) end
                end
            end
        end

        if #out == 0 then out = { "drifter" } end

        table.sort(out)
        return out
    end

    local function tryClassAction(className)
        local r = remote("ClassAction")
        if not r then
            print("[BrainrotPolice] ClassAction remote missing")
            return false
        end

        local attempts = {
            { "Select", className },
            { "select", className },
            { "SetClass", className },
            { "Equip", className },
            { className },
        }

        for _, args in ipairs(attempts) do
            local label = {}
            for i = 1, #args do label[i] = tostring(args[i]) end

            local ok, result = pcall(function()
                return r:InvokeServer(table.unpack(args))
            end)

            print(string.format("[BrainrotPolice] ClassAction(%s) -> %s",
                table.concat(label, ", "),
                ok and tostring(result) or ("error " .. tostring(result))))

            if ok and result ~= nil and result ~= false then
                if className and type(result) == "table" and result.Success == false then
                    -- keep trying, the server rejected that shape
                else
                    return true
                end
            end

            task.wait(0.2)
        end

        return false
    end

    ----------------------------------------------------------------
    -- reports
    ----------------------------------------------------------------

    local function statsText()
        local amounts = dailyAmounts()

        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== Needle In A Haystack (lobby) ===")
        add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
        add("Gems: " .. tostring(attr("Gems")))
        add("Class: " .. tostring(attr("ClassKey")) .. " | slots " .. tostring(attr("ClassSlots")))
        add("Daily: " .. dailyStatus())
        add("  amounts: " .. table.concat(amounts, ", "))
        add("GroupReward: " .. tostring(attr("GroupRewardState")))
        add("ActiveRun: " .. tostring(attr("ActiveRun")))
        add("SfxVolume: " .. tostring(attr("SfxVolume")) .. " | MusicVolume: " .. tostring(attr("MusicVolume")))

        local pbs = {}
        local ranks = {}

        for _, k in ipairs({ "Solo", "Duo", "Trio", "Squads", "EasySolo", "EasyDuo", "EasyTrio", "EasySquads" }) do
            local pb = attr("PB_" .. k)
            local rank = attr("Rank_" .. k)

            if pb ~= nil and tonumber(pb) and tonumber(pb) >= 0 then
                pbs[#pbs+1] = k .. "=" .. tostring(pb)
            end
            if rank ~= nil and tonumber(rank) and tonumber(rank) > 0 then
                ranks[#ranks+1] = k .. "=" .. tostring(rank)
            end
        end

        add("Personal bests: " .. (#pbs > 0 and table.concat(pbs, ", ") or "none"))
        add("Ranks: " .. (#ranks > 0 and table.concat(ranks, ", ") or "none"))

        return table.concat(L, "\n")
    end

    local function dumpRemotes()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        local f = remotesFolder()
        add("=== Lobby.Remotes ===")
        add("PlaceId: " .. tostring(game.PlaceId))

        if not f then
            add("Remotes folder missing")
        else
            for _, r in ipairs(f:GetChildren()) do
                add(string.format("%s | %s | attrs: %s", r.ClassName, fullName(r), attrString((function()
                    local ok, a = pcall(function() return r:GetAttributes() end)
                    return ok and a or {}
                end)())))
            end
        end

        local l = lobby()
        if l then
            add("")
            add("=== Lobby modules ===")
            for _, m in ipairs(l:GetChildren()) do
                add(m.ClassName .. " | " .. m.Name)
            end
        end

        add("")
        add("=== player attributes ===")
        add(attrString(attrsOf()))

        lastReport = table.concat(L, "\n")
        publish("remote dump", lastReport, "BrainrotPolice/needle_remotes.txt")
    end

    local function dumpModules()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== lobby module data ===")

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

        local l = lobby()
        if l then
            for _, m in ipairs(l:GetChildren()) do
                if m:IsA("ModuleScript") then
                    local ok, result = pcall(require, m)
                    if ok then
                        add(m.Name .. ": " .. shallow(result, 0, {}))
                    else
                        add(m.Name .. ": require failed -> " .. tostring(result))
                    end
                end
            end
        end

        local classes = classesModule()
        if classes then
            local ok, result = pcall(require, classes)
            add("")
            add("Classes: " .. (ok and shallow(result, 0, {}) or ("require failed -> " .. tostring(result))))
        end

        lastReport = table.concat(L, "\n")
        publish("module dump", lastReport)
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Label("Needle In A Haystack (Lobby)", section)
    elements:Label("The haystack runs in the match place, this tab handles the lobby.", section)

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

    elements:Label("Daily", section)

    elements:Button("Claim Daily Gems", section, function()
        claimDaily(false)
    end)

    elements:Toggle("Auto Claim Daily", section, setdata.daily, function(v)
        env.NIHDaily = v
        setdata.daily = v
        env.setconfig("daily", v)

        print("[BrainrotPolice] auto daily " .. (v and "on" or "off") .. " | " .. dailyStatus())
    end)

    elements:Label("Group reward", section)

    elements:Button("Claim Group Reward", section, function()
        claimGroupReward()
    end)

    elements:Toggle("Auto Claim Group Reward", section, setdata.group, function(v)
        env.NIHGroup = v
        setdata.group = v
        env.setconfig("group", v)

        print("[BrainrotPolice] auto group reward " .. (v and "on (state " .. tostring(attr("GroupRewardState")) .. ")" or "off"))
    end)

    elements:Label("Class", section)

    elements:Button("Show Class Info", section, function()
        print("[BrainrotPolice] ClassKey: " .. tostring(attr("ClassKey")))
        print("[BrainrotPolice] ClassSlots: " .. tostring(attr("ClassSlots")))
        print("[BrainrotPolice] classes found: " .. table.concat(collectClassNames(), ", "))

        local r = remote("ClassAction")
        if r then
            local ok, result = pcall(function() return r:InvokeServer() end)
            print("[BrainrotPolice] ClassAction() -> " .. (ok and tostring(result) or ("error " .. tostring(result))))
        end
    end)

    classChoices = collectClassNames()

    if #classChoices > 0 then
        elements:Dropdown("Class", section, classChoices, attr("ClassKey") or classChoices[1], function(v)
            setdata.class = v
            env.setconfig("class", v)
            print("[BrainrotPolice] class selected in the menu: " .. tostring(v))
        end)
    end

    elements:Button("Apply Selected Class", section, function()
        local name = setdata.class or attr("ClassKey") or (classChoices[1] or "drifter")
        print("[BrainrotPolice] trying to switch class to " .. tostring(name))
        local ok = tryClassAction(name)
        task.wait(0.5)
        print("[BrainrotPolice] ClassKey now: " .. tostring(attr("ClassKey")) .. (ok and "" or " (all shapes rejected)"))
    end)

    elements:Label("Events and settings", section)

    elements:Button("Check Event RSVP", section, function()
        local r = remote("EventRsvpCheck")
        if not r then
            print("[BrainrotPolice] EventRsvpCheck missing")
            return
        end

        local ok, result = pcall(function() return r:InvokeServer() end)
        print("[BrainrotPolice] EventRsvpCheck -> " .. (ok and tostring(result) or ("error " .. tostring(result))))
    end)

    elements:Button("RSVP To Event", section, function()
        local r = remote("EventRsvpDone")
        if not r then
            print("[BrainrotPolice] EventRsvpDone missing")
            return
        end

        pcall(function() r:FireServer() end)
        print("[BrainrotPolice] RSVP fired")
    end)

    elements:Button("Show Audio Settings", section, function()
        print(string.format("[BrainrotPolice] SfxVolume %s | MusicVolume %s",
            tostring(attr("SfxVolume")), tostring(attr("MusicVolume"))))
    end)

    elements:Label("Lobby actions", section)

    elements:Button("Create Game", section, function()
        callRemote("CreateGame", "FireServer", "")
    end)

    elements:Button("Cancel Hold", section, function()
        callRemote("CancelHold", "FireServer", "")
    end)

    elements:Button("Leave Squad", section, function()
        callRemote("LeaveSquad", "FireServer", "")
    end)

    elements:Button("Membership", section, function()
        callRemote("Membership", "FireServer", "")
    end)

    elements:Button("Rejoin", section, function()
        callRemote("Rejoin", "FireServer", "")
    end)

    elements:Label("Manual remote tool", section)

    local remoteNames = {}
    local rf = remotesFolder()
    if rf then
        for _, r in ipairs(rf:GetChildren()) do
            if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") or r:IsA("UnreliableRemoteEvent") then
                remoteNames[#remoteNames+1] = r.Name
            end
        end
        table.sort(remoteNames)
    end

    local manualRemote = remoteNames[1] or "GemDailyClaim"
    local manualMethod = "FireServer"

    if #remoteNames > 0 then
        elements:Dropdown("Remote", section, remoteNames, manualRemote, function(v)
            manualRemote = v
        end)
    end

    elements:Dropdown("Method", section, { "FireServer", "InvokeServer" }, manualMethod, function(v)
        manualMethod = v
    end)

    elements:Textbox("Arguments (comma separated, JSON allowed)", section, setdata.args or "", function(v)
        setdata.args = v
        env.setconfig("args", v)
    end)

    elements:Button("Run Remote", section, function()
        callRemote(manualRemote, manualMethod, setdata.args or "")
    end)

    elements:Button("Dump Remotes", section, function()
        task.spawn(function()
            local ok, err = pcall(dumpRemotes)
            if not ok then print("[BrainrotPolice] dump failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Dump Lobby Module Data", section, function()
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
end
