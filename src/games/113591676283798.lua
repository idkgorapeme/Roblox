-- Where Did I Park? (PlaceId 113591676283798, "Hard" sub place)
--
-- The depth 1 dump only shows the folders, not the cars themselves, so this
-- module starts with real diagnostics: it walks the lot, reports every prompt,
-- clickdetector and model attribute, and can highlight cars whose attribute
-- signature is unique (the unlocked car usually is the odd one out).
--
-- On top of that it has a generic "walk to the nearest prompt and fire it"
-- loop, which covers both checking cars and picking up cash.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.WDPAuto = false
    env.WDPHighlight = false
    env.WDPLog = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.auto = setdata.auto or false
    setdata.filter = setdata.filter or "Everything"
    setdata.teleport = setdata.teleport ~= false
    setdata.delay = tonumber(setdata.delay) or 0.4
    setdata.highlight = setdata.highlight or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local autoDelay = math.clamp(tonumber(setdata.delay) or 0.4, 0.05, 5)

    local ROOT_NAMES = { "ParkingWorld", "LocalParkingVisuals", "LocalCity" }
    local CAR_WORDS = { "car", "vehicle", "auto", "check", "inspect", "search", "try", "unlock", "drive", "enter" }
    local CASH_WORDS = { "cash", "coin", "gem", "money", "valuable", "loot", "diamond", "crate", "bag", "wallet" }
    local LOG_FILE = "BrainrotPolice/parking_traffic.txt"
    local SCAN_FILE = "BrainrotPolice/parking_scan.txt"
    local DUMP_FILE = "BrainrotPolice/parking_structure.txt"

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function roots()
        local out = {}
        for _, name in ipairs(ROOT_NAMES) do
            local f = workspace:FindFirstChild(name)
            if f then out[#out+1] = f end
        end
        return out
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

    local function attrsOf(inst)
        local ok, attrs = pcall(function() return inst:GetAttributes() end)
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

    local function hasWord(text, words)
        text = string.lower(tostring(text))
        for _, w in ipairs(words) do
            if string.find(text, w, 1, true) then return true end
        end
        return false
    end

    local function topList(map, n)
        local arr = {}
        for k, v in pairs(map) do arr[#arr+1] = { k = k, v = v } end
        table.sort(arr, function(a, b)
            if a.v == b.v then return tostring(a.k) < tostring(b.k) end
            return a.v > b.v
        end)

        local out = {}
        for i = 1, math.min(#arr, n or 20) do
            out[#out+1] = tostring(arr[i].k) .. " x" .. tostring(arr[i].v)
        end
        return table.concat(out, ", ")
    end

    local function publish(name, text, filename)
        if setclipboard then pcall(setclipboard, text) end
        if writefile then pcall(writefile, filename, text) end

        local lines = 1
        for _ in string.gmatch(text, "\n") do lines = lines + 1 end
        print(string.format("[BrainrotPolice] %s: %d lines, copied, saved to %s", name, lines, filename))

        -- keep the console readable, the full text is on the clipboard and in the file
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
    -- interactables
    ----------------------------------------------------------------

    local function hostOf(obj)
        local host = obj.Parent
        if not host then return nil, nil end

        local model = nil
        if host:IsA("Model") then
            model = host
        else
            model = host:FindFirstAncestorOfClass("Model") or host
        end

        return host, model
    end

    local function collectInteractables()
        local out = {}
        local seen = {}

        for _, root in ipairs(roots()) do
            local ok, desc = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, d in ipairs(desc) do
                    local isPrompt = d:IsA("ProximityPrompt")
                    local isClick = d:IsA("ClickDetector")

                    if (isPrompt or isClick) and not seen[d] then
                        seen[d] = true
                        local host, model = hostOf(d)

                        if host and host.Parent then
                            local action = isPrompt and tostring(d.ActionText) or ""
                            local object = isPrompt and tostring(d.ObjectText) or ""

                            out[#out+1] = {
                                obj = d,
                                kind = isPrompt and "prompt" or "click",
                                host = host,
                                model = model or host,
                                text = fullName(d) .. " " .. action .. " " .. object,
                                label = fullName(d) .. " [" .. action .. " / " .. object .. "]",
                                pos = posOf(model or host),
                            }
                        end
                    end
                end
            end
        end

        return out
    end

    local cache = nil
    local cacheAt = 0

    local function interactions(force)
        local now = os.clock()
        if force or not cache or now - cacheAt > 10 then
            cache = collectInteractables()
            cacheAt = now
        end
        return cache
    end

    local function kindOf(e)
        if hasWord(e.text, CASH_WORDS) then return "cash" end
        if hasWord(e.text, CAR_WORDS) then return "car" end
        return "other"
    end

    local function passesFilter(e)
        if setdata.filter == "Cars" then return kindOf(e) == "car" end
        if setdata.filter == "Cash / Valuables" then return kindOf(e) == "cash" end
        return true
    end

    local function activate(e)
        if e.kind == "prompt" then
            local p = e.obj
            pcall(function()
                if p.HoldDuration > 0 then p.HoldDuration = 0 end
                if p.MaxActivationDistance < 100 then p.MaxActivationDistance = 100 end
            end)

            if fireproximityprompt then
                pcall(fireproximityprompt, p)
            end
        else
            if fireclickdetector then
                pcall(fireclickdetector, e.obj, 100)
            end
        end
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

    ----------------------------------------------------------------
    -- auto interact
    ----------------------------------------------------------------

    local attempted = {}
    local RETRY = 45

    local function bestTarget()
        local root = getRoot()
        if not root then return nil end

        local rootPos = root.Position
        local list = interactions(false)
        local now = os.clock()
        local best, bestDist = nil, math.huge

        for i = 1, #list do
            local e = list[i]
            local obj = e.obj

            if obj and obj.Parent and e.pos and passesFilter(e) then
                local usable = true
                if e.kind == "prompt" and not obj.Enabled then usable = false end

                if usable then
                    local last = attempted[obj]
                    if not last or now - last > RETRY then
                        local dist = (e.pos - rootPos).Magnitude
                        if dist < bestDist then
                            best = e
                            bestDist = dist
                        end
                    end
                end
            end
        end

        return best
    end

    task.spawn(function()
        while true do
            if env.BrainrotPolice ~= registry then break end

            if env.WDPAuto then
                local ok, target = pcall(bestTarget)

                if not ok then
                    print("[BrainrotPolice] auto interact error: " .. tostring(target))
                    task.wait(1)
                elseif target then
                    if setdata.teleport then
                        tpTo(target.pos)
                        task.wait(0.15)
                    end

                    activate(target)
                    attempted[target.obj] = os.clock()
                    task.wait(autoDelay)
                else
                    task.wait(0.75)
                end
            else
                task.wait(0.2)
            end
        end
    end)

    ----------------------------------------------------------------
    -- highlight interactables
    ----------------------------------------------------------------

    local highlights = {}

    local function clearHighlights()
        for target, h in pairs(highlights) do
            pcall(function() h:Destroy() end)
            highlights[target] = nil
        end
    end

    local function colorOf(e)
        local text = e.text
        if hasWord(text, { "unlock", "drive", "enter", "open", "claim", "win" }) then
            return Color3.fromRGB(255, 70, 70)
        end
        if hasWord(text, CASH_WORDS) then
            return Color3.fromRGB(255, 200, 40)
        end
        if hasWord(text, { "check", "inspect", "search", "try" }) then
            return Color3.fromRGB(80, 255, 140)
        end
        return Color3.fromRGB(90, 160, 255)
    end

    local function refreshHighlights()
        local root = getRoot()
        if not root then
            clearHighlights()
            return
        end

        local rootPos = root.Position
        local list = interactions(false)
        local picked = {}

        for i = 1, #list do
            local e = list[i]
            if e.model and e.model.Parent and e.pos then
                local dist = (e.pos - rootPos).Magnitude
                if dist <= 400 then
                    picked[#picked+1] = { e = e, d = dist }
                end
            end
        end

        table.sort(picked, function(a, b) return a.d < b.d end)

        local keep = {}
        for i = 1, math.min(#picked, 120) do
            local e = picked[i].e
            local target = e.model or e.host

            if target and target.Parent then
                keep[target] = true
                local h = highlights[target]

                if not h then
                    h = Instance.new("Highlight")
                    h.Name = "BPDropESP"
                    h.Adornee = target
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.FillTransparency = 0.8
                    h.OutlineTransparency = 0
                    h.Parent = target
                    highlights[target] = h
                end

                local c = colorOf(e)
                h.FillColor = c
                h.OutlineColor = c
            end
        end

        for target, h in pairs(highlights) do
            if not keep[target] or not target.Parent then
                pcall(function() h:Destroy() end)
                highlights[target] = nil
            end
        end
    end

    task.spawn(function()
        while true do
            if env.BrainrotPolice ~= registry then
                clearHighlights()
                break
            end

            if env.WDPHighlight then
                local ok, err = pcall(refreshHighlights)
                if not ok then
                    print("[BrainrotPolice] highlight error: " .. tostring(err))
                end
                task.wait(2)
            else
                if next(highlights) ~= nil then clearHighlights() end
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- remote traffic logger
    ----------------------------------------------------------------

    local watched = {}

    local function refreshWatched()
        local pg = replicatedstorage:FindFirstChild("ParkingGame")
        if pg then
            for _, c in ipairs(pg:GetChildren()) do
                if c:IsA("RemoteEvent") or c:IsA("UnreliableRemoteEvent") or c:IsA("RemoteFunction") then
                    watched[c] = "ParkingGame." .. c.Name
                end
            end
        end

        local global = replicatedstorage:FindFirstChild("ParkingGlobal")
        if global and (global:IsA("RemoteEvent") or global:IsA("UnreliableRemoteEvent")) then
            watched[global] = "ParkingGlobal"
        end
    end

    local function serialize(v, depth, seen)
        depth = depth or 0
        local t = typeof(v)

        if t == "string" then
            if #v > 180 then return string.format("%q..(%d)", string.sub(v, 1, 180), #v) end
            return string.format("%q", v)
        elseif t == "table" then
            if seen[v] then return "<cycle>" end
            if depth >= 3 then return "{...}" end

            seen[v] = true
            local parts = {}
            local n = 0

            for k, val in pairs(v) do
                n = n + 1
                if n > 30 then
                    parts[#parts+1] = "..."
                    break
                end
                parts[#parts+1] = tostring(k) .. "=" .. serialize(val, depth + 1, seen)
            end

            seen[v] = nil
            return "{" .. table.concat(parts, ", ") .. "}"
        elseif t == "Instance" then
            return "<" .. v.ClassName .. " " .. tostring(v.Name) .. ">"
        end

        return tostring(v)
    end

    local LOG_MAX = 2000
    local logBuf = {}
    local logDirty = false

    local function flushLog()
        if writefile and #logBuf > 0 then
            pcall(writefile, LOG_FILE, table.concat(logBuf, "\n"))
        end
        logDirty = false
    end

    local secStart, secCount, dropped = 0, 0, 0

    local function canLog()
        local now = os.clock()
        if now - secStart >= 1 then
            secStart = now
            secCount = 0
        end

        secCount = secCount + 1
        if secCount > 25 then
            dropped = dropped + 1
            return false
        end

        return true
    end

    local function pushLog(tag, ...)
        if not canLog() then return end

        local args = table.pack(...)
        local parts = {}

        for i = 1, math.min(args.n, 12) do
            local ok, s = pcall(serialize, args[i], 0, {})
            parts[#parts+1] = ok and s or "<serialize error>"
        end

        local line = string.format("%s %s %s", os.date("%H:%M:%S"), tag, table.concat(parts, " | "))
        if #line > 1500 then line = string.sub(line, 1, 1500) .. "..." end

        print("[BrainrotPolice] " .. line)

        logBuf[#logBuf+1] = line
        if #logBuf > LOG_MAX then table.remove(logBuf, 1) end
        logDirty = true
    end

    local hookInstalled = false

    local function installHook()
        if hookInstalled then return true end
        if not hookmetamethod or not getnamecallmethod then
            print("[BrainrotPolice] this executor has no hookmetamethod, outgoing traffic cannot be logged")
            return false
        end

        local wrap = newcclosure or function(f) return f end

        local ok = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                local method = getnamecallmethod()

                if env.WDPLog and (method == "FireServer" or method == "InvokeServer") then
                    local label = watched[self]
                    if label then
                        pcall(pushLog, "OUT " .. label, ...)
                    end
                end

                return original(self, ...)
            end))
        end)

        hookInstalled = ok
        if not ok then print("[BrainrotPolice] could not hook __namecall") end
        return ok
    end

    local function connectIncoming()
        refreshWatched()

        for remote, label in pairs(watched) do
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                local ok, conn = pcall(function()
                    return remote.OnClientEvent:Connect(function(...)
                        if not env.WDPLog then return end
                        pcall(pushLog, "IN " .. label, ...)
                    end)
                end)

                if ok and conn and registry and registry.track then
                    pcall(registry.track, conn)
                end
            end
        end
    end

    task.spawn(function()
        while true do
            if env.BrainrotPolice ~= registry then
                flushLog()
                break
            end

            task.wait(5)
            if env.WDPLog and logDirty then flushLog() end
        end
    end)

    ----------------------------------------------------------------
    -- structure scan
    ----------------------------------------------------------------

    local lastReport = ""

    local function runScan()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== Where Did I Park? scan ===")
        add("PlaceId: " .. tostring(game.PlaceId))
        add("JobId: " .. tostring(game.JobId))
        add("Executor: " .. tostring(getgenv().getexec and getgenv().getexec() or "unknown"))

        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            local vals = {}
            for _, v in ipairs(ls:GetChildren()) do
                if v:IsA("ValueBase") then
                    vals[#vals+1] = v.Name .. "=" .. tostring(v.Value)
                end
            end
            add("leaderstats: " .. table.concat(vals, ", "))
        end
        add("player attrs: " .. attrString(attrsOf(plr)))

        local rootList = roots()
        if #rootList == 0 then
            add("no ParkingWorld / LocalParkingVisuals / LocalCity folder found")
        end

        local classCounts = {}
        local modelNames = {}
        local promptTexts = {}
        local promptParents = {}
        local clickParents = {}
        local attrKeys = {}
        local attrValues = {}
        local attrOverflow = {}
        local promptSamples = {}
        local clickSamples = {}
        local attrSamples = {}
        local cashSamples = {}

        local total, modelTotal = 0, 0
        local promptTotal, promptDisabled, clickTotal = 0, 0, 0
        local cashTotal = 0

        for _, root in ipairs(rootList) do
            local ok, desc = pcall(function() return root:GetDescendants() end)

            if not ok then
                add("!! could not walk " .. root.Name)
            else
                add(string.format("root %s | %s | %d descendants", root:GetFullName(), root.ClassName, #desc))
                total = total + #desc

                for _, d in ipairs(desc) do
                    classCounts[d.ClassName] = (classCounts[d.ClassName] or 0) + 1

                    if d:IsA("ProximityPrompt") then
                        promptTotal = promptTotal + 1
                        if not d.Enabled then promptDisabled = promptDisabled + 1 end

                        local textKey = string.format("%q / %q", tostring(d.ActionText), tostring(d.ObjectText))
                        promptTexts[textKey] = (promptTexts[textKey] or 0) + 1

                        local host, model = hostOf(d)
                        local hostKey = (host and host.Name or "?") .. " -> " .. (model and model.Name or "?")
                        promptParents[hostKey] = (promptParents[hostKey] or 0) + 1

                        if #promptSamples < 25 then
                            promptSamples[#promptSamples+1] = string.format(
                                "%s | action=%q object=%q hold=%.2f dist=%.0f enabled=%s los=%s",
                                fullName(d), tostring(d.ActionText), tostring(d.ObjectText),
                                tonumber(d.HoldDuration) or 0, tonumber(d.MaxActivationDistance) or 0,
                                tostring(d.Enabled), tostring(d.RequiresLineOfSight)
                            )
                        end
                    elseif d:IsA("ClickDetector") then
                        clickTotal = clickTotal + 1
                        local host = d.Parent
                        local hostKey = (host and host.Name or "?") .. " -> " .. (host and host.Parent and host.Parent.Name or "?")
                        clickParents[hostKey] = (clickParents[hostKey] or 0) + 1

                        if #clickSamples < 15 then
                            clickSamples[#clickSamples+1] = fullName(d) .. " | maxdist=" .. tostring(d.MaxActivationDistance)
                        end
                    elseif d:IsA("Model") then
                        modelTotal = modelTotal + 1
                        modelNames[d.Name] = (modelNames[d.Name] or 0) + 1

                        local attrs = attrsOf(d)
                        if next(attrs) ~= nil then
                            for k, v in pairs(attrs) do
                                attrKeys[k] = (attrKeys[k] or 0) + 1

                                local byKey = attrValues[k]
                                if not byKey then
                                    byKey = {}
                                    attrValues[k] = byKey
                                end

                                local sv = tostring(v)
                                if byKey[sv] ~= nil then
                                    byKey[sv] = byKey[sv] + 1
                                else
                                    local seenValues = 0
                                    for _ in pairs(byKey) do seenValues = seenValues + 1 end

                                    if seenValues < 50 then
                                        byKey[sv] = 1
                                    else
                                        attrOverflow[k] = true
                                    end
                                end
                            end

                            if #attrSamples < 20 then
                                attrSamples[#attrSamples+1] = fullName(d) .. " {" .. attrString(attrs) .. "}"
                            end
                        end
                    end

                    if hasWord(d.Name, CASH_WORDS) then
                        cashTotal = cashTotal + 1
                        if #cashSamples < 15 then
                            cashSamples[#cashSamples+1] = d.ClassName .. " | " .. fullName(d)
                        end
                    end
                end
            end
        end

        add("")
        add(string.format("totals: descendants=%d models=%d prompts=%d (disabled %d) clickdetectors=%d",
            total, modelTotal, promptTotal, promptDisabled, clickTotal))
        add("classes: " .. topList(classCounts, 25))
        add("model names: " .. topList(modelNames, 25))
        add("prompt texts: " .. topList(promptTexts, 25))
        add("prompt hosts: " .. topList(promptParents, 20))
        add("click hosts: " .. topList(clickParents, 20))
        add("attribute keys: " .. topList(attrKeys, 30))

        local keyArr = {}
        for k, v in pairs(attrKeys) do keyArr[#keyArr+1] = { key = k, n = v } end
        table.sort(keyArr, function(a, b)
            if a.n == b.n then return a.key < b.key end
            return a.n > b.n
        end)

        for i = 1, math.min(#keyArr, 15) do
            local k = keyArr[i].key
            local suffix = attrOverflow[k] and " (50+ values)" or ""
            add(string.format("  attr %s: %s%s", k, topList(attrValues[k], 8), suffix))
        end

        add("")
        add("prompt samples:")
        for _, s in ipairs(promptSamples) do add("  " .. s) end
        add("clickdetector samples:")
        for _, s in ipairs(clickSamples) do add("  " .. s) end
        add("attribute samples:")
        for _, s in ipairs(attrSamples) do add("  " .. s) end
        add("cash-like instances: " .. cashTotal)
        for _, s in ipairs(cashSamples) do add("  " .. s) end

        add("")
        add("=== ReplicatedStorage ===")
        local pg = replicatedstorage:FindFirstChild("ParkingGame")
        if pg then
            add("ParkingGame | " .. pg.ClassName .. " | attrs: " .. attrString(attrsOf(pg)))
            for _, d in ipairs(pg:GetDescendants()) do
                add(string.format("%s | %s | attrs: %s", d.ClassName, fullName(d), attrString(attrsOf(d))))
            end
        end

        local global = replicatedstorage:FindFirstChild("ParkingGlobal")
        if global then
            add("ParkingGlobal | " .. global.ClassName .. " | attrs: " .. attrString(attrsOf(global)))
        end

        local admin = replicatedstorage:FindFirstChild("ParkingAdmin")
        if admin then
            for _, d in ipairs(admin:GetDescendants()) do
                add(string.format("ParkingAdmin %s | %s", d.ClassName, fullName(d)))
            end
        end

        for _, root in ipairs(rootList) do
            local kids = root:GetChildren()
            local parts = {}

            for i = 1, math.min(#kids, 60) do
                parts[#parts+1] = kids[i].ClassName .. ":" .. kids[i].Name
            end

            add("")
            add(string.format("children of %s (%d):", root:GetFullName(), #kids))
            add("  " .. table.concat(parts, ", ") .. (#kids > 60 and " ..." or ""))
        end

        lastReport = table.concat(L, "\n")
        publish("scan", lastReport, SCAN_FILE)
    end

    local function dumpStructure()
        local L = {}
        local CAP = 1500
        local function add(s) L[#L+1] = tostring(s) end

        local function walk(inst, depth, prefix)
            if depth > 3 or #L >= CAP then return end

            local kids = inst:GetChildren()
            for i = 1, math.min(#kids, 150) do
                local c = kids[i]
                add(prefix .. c.ClassName .. " | " .. c.Name)
                if depth < 3 then walk(c, depth + 1, prefix .. "  ") end
                if #L >= CAP then return end
            end

            if #kids > 150 then add(prefix .. "... +" .. (#kids - 150) .. " more") end
        end

        add("=== Where Did I Park? structure ===")
        add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
        add("")

        for _, name in ipairs(ROOT_NAMES) do
            local r = workspace:FindFirstChild(name)
            if r then
                add("[workspace." .. name .. "]")
                walk(r, 1, "  ")
                add("")
            end
        end

        add("[ReplicatedStorage.ParkingGame]")
        local pg = replicatedstorage:FindFirstChild("ParkingGame")
        if pg then walk(pg, 1, "  ") end

        lastReport = table.concat(L, "\n")
        publish("structure dump", lastReport, DUMP_FILE)
    end

    ----------------------------------------------------------------
    -- odd car finder
    ----------------------------------------------------------------

    local oddHighlights = {}

    local function clearOddHighlights()
        for _, h in ipairs(oddHighlights) do
            pcall(function() h:Destroy() end)
        end
        oddHighlights = {}
    end

    local function findOddCars()
        clearOddHighlights()

        local keyCounts = {}
        local valueSets = {}
        local overflow = {}
        local withAttrs = 0

        -- pass 1: which attribute keys exist and how many distinct values they have
        for _, root in ipairs(roots()) do
            local ok, desc = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, d in ipairs(desc) do
                    if d:IsA("Model") then
                        local attrs = attrsOf(d)
                        if next(attrs) ~= nil then
                            withAttrs = withAttrs + 1

                            for k, v in pairs(attrs) do
                                keyCounts[k] = (keyCounts[k] or 0) + 1

                                local set = valueSets[k]
                                if not set then
                                    set = {}
                                    valueSets[k] = set
                                end

                                local sv = tostring(v)
                                if set[sv] == nil then
                                    local seenValues = 0
                                    for _ in pairs(set) do seenValues = seenValues + 1 end
                                    if seenValues < 50 then
                                        set[sv] = true
                                    else
                                        overflow[k] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        print(string.format("[BrainrotPolice] odd car scan: %d models with attributes", withAttrs))

        if withAttrs < 10 then
            print("[BrainrotPolice] not enough models with attributes, press Dump Structure and send the file")
            return
        end

        local stable = {}
        for k, n in pairs(keyCounts) do
            local distinct = 0
            for _ in pairs(valueSets[k]) do distinct = distinct + 1 end

            if not overflow[k] and distinct <= math.max(4, math.floor(n * 0.05)) then
                stable[#stable+1] = { key = k, n = n, distinct = distinct }
            end
        end

        table.sort(stable, function(a, b)
            if a.distinct == b.distinct then return a.n > b.n end
            return a.distinct < b.distinct
        end)

        if #stable > 8 then
            local trimmed = {}
            for i = 1, 8 do trimmed[i] = stable[i] end
            stable = trimmed
        end

        if #stable == 0 then
            print("[BrainrotPolice] no stable attribute keys, every attribute looks unique per car")
            print("[BrainrotPolice] the unlocked car is probably not flagged on the client")
            return
        end

        local keyNames = {}
        for _, s in ipairs(stable) do keyNames[#keyNames+1] = s.key end
        print("[BrainrotPolice] stable keys: " .. table.concat(keyNames, ", "))

        -- pass 2: count signatures built only from the stable keys. Missing keys
        -- are written as "-" so a car that alone carries a marker is different
        -- from the thousands that do not.
        local sigs = {}

        for _, root in ipairs(roots()) do
            local ok, desc = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, d in ipairs(desc) do
                    if d:IsA("Model") then
                        local attrs = attrsOf(d)
                        if next(attrs) ~= nil then
                            local parts = {}
                            for _, s in ipairs(stable) do
                                local v = attrs[s.key]
                                parts[#parts+1] = s.key .. "=" .. (v ~= nil and tostring(v) or "-")
                            end

                            local sig = table.concat(parts, ";")
                            local entry = sigs[sig]

                            if not entry then
                                entry = { n = 0, inst = d, path = fullName(d) }
                                sigs[sig] = entry
                            end

                            entry.n = entry.n + 1
                        end
                    end
                end
            end
        end

        local rare = {}
        for sig, entry in pairs(sigs) do
            if entry.n <= 2 and withAttrs >= 20 then
                rare[#rare+1] = { sig = sig, n = entry.n, inst = entry.inst, path = entry.path }
            end
        end

        table.sort(rare, function(a, b)
            if a.n == b.n then return a.sig < b.sig end
            return a.n < b.n
        end)

        print(string.format("[BrainrotPolice] unique/rare signatures: %d", #rare))

        for i = 1, math.min(#rare, 60) do
            local r = rare[i]
            print(string.format("[BrainrotPolice] rare x%d %s {%s}", r.n, r.path, r.sig))

            if r.inst and r.inst.Parent then
                local h = Instance.new("Highlight")
                h.Name = "BPDropOdd"
                h.Adornee = r.inst
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.FillColor = Color3.fromRGB(255, 40, 40)
                h.OutlineColor = Color3.fromRGB(255, 40, 40)
                h.FillTransparency = 0.5
                h.OutlineTransparency = 0
                h.Parent = r.inst
                oddHighlights[#oddHighlights+1] = h
            end
        end

        if #rare == 0 then
            print("[BrainrotPolice] no odd car found, all cars share the same stable attributes")
        end
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Label("Where Did I Park?", section)
    elements:Label("Press Scan first, the depth 1 dump has no car data.", section)

    elements:Button("Scan Parking Lot (prompts, models, attributes)", section, function()
        task.spawn(function()
            print("[BrainrotPolice] scanning the lot, this can take a few seconds...")
            local ok, err = pcall(runScan)
            if not ok then print("[BrainrotPolice] scan failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Find Odd Cars (unique attributes)", section, function()
        task.spawn(function()
            local ok, err = pcall(findOddCars)
            if not ok then print("[BrainrotPolice] odd scan failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Dump Structure (depth 3)", section, function()
        task.spawn(function()
            local ok, err = pcall(dumpStructure)
            if not ok then print("[BrainrotPolice] dump failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Copy Last Report", section, function()
        local text = lastReport

        if text == "" then
            print("[BrainrotPolice] nothing scanned yet, press Scan or Dump Structure first")
            return
        end

        local ok = pcall(setclipboard, text)
        print("[BrainrotPolice] " .. (ok and "report copied" or "could not copy the report"))
    end)

    elements:Button("Show Stats", section, function()
        local out = {}
        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetChildren()) do
                if v:IsA("ValueBase") then
                    out[#out+1] = v.Name .. ": " .. tostring(v.Value)
                end
            end
        end

        print("[BrainrotPolice] " .. table.concat(out, " | "))
        print("[BrainrotPolice] player attrs: " .. attrString(attrsOf(plr)))

        local list = interactions(false)
        local kinds = { car = 0, cash = 0, other = 0 }
        for _, e in ipairs(list) do
            kinds[kindOf(e)] = (kinds[kindOf(e)] or 0) + 1
        end

        print(string.format("[BrainrotPolice] interactables: %d total | car %d | cash %d | other %d",
            #list, kinds.car or 0, kinds.cash or 0, kinds.other or 0))
    end)

    elements:Label("Automation", section)

    elements:Toggle("Auto Interact (check cars / collect)", section, setdata.auto, function(v)
        env.WDPAuto = v
        setdata.auto = v
        env.setconfig("auto", v)
    end)

    elements:Dropdown("Auto Filter", section, { "Everything", "Cars", "Cash / Valuables" }, setdata.filter, function(v)
        setdata.filter = v
        env.setconfig("filter", v)
    end)

    elements:Toggle("Teleport Before Interacting", section, setdata.teleport, function(v)
        setdata.teleport = v
        env.setconfig("teleport", v)
    end)

    elements:Textbox("Interact Delay (seconds)", section, tostring(autoDelay), function(v)
        local n = tonumber(v)
        if not n then return end

        autoDelay = math.clamp(n, 0.05, 5)
        setdata.delay = autoDelay
        env.setconfig("delay", autoDelay)
    end)

    elements:Button("Interact With Nearest Now", section, function()
        local target = bestTarget()
        if not target then
            print("[BrainrotPolice] no prompt or clickdetector found, run Scan and send the report")
            return
        end

        if setdata.teleport then
            tpTo(target.pos)
            task.wait(0.15)
        end

        activate(target)
        attempted[target.obj] = os.clock()
        print("[BrainrotPolice] interacted: " .. target.label)
    end)

    elements:Label("Visuals", section)

    elements:Toggle("Highlight Interactables (color = prompt type)", section, setdata.highlight, function(v)
        env.WDPHighlight = v
        setdata.highlight = v
        env.setconfig("highlight", v)
    end)

    elements:Button("Clear Highlights", section, function()
        clearHighlights()
        clearOddHighlights()
        print("[BrainrotPolice] highlights cleared")
    end)

    elements:Label("Remote logger (learn the Action arguments)", section)

    local logWasOn = false

    elements:Toggle("Log Remote Traffic", section, false, function(v)
        env.WDPLog = v

        if v then
            logWasOn = true
            installHook()
            refreshWatched()

            print("[BrainrotPolice] logging on, check one car / collect one cash / upgrade once, then turn it off")
        elseif logWasOn then
            logWasOn = false
            flushLog()
            print("[BrainrotPolice] logging off, saved to " .. LOG_FILE .. " - press Copy Traffic Log")
        end
    end)

    elements:Button("Copy Traffic Log", section, function()
        if #logBuf == 0 then
            print("[BrainrotPolice] traffic log is empty, enable logging and play for a moment")
            return
        end

        local text = table.concat(logBuf, "\n")
        local ok = pcall(setclipboard, text)
        print("[BrainrotPolice] " .. (ok and ("copied " .. #logBuf .. " log lines") or "could not copy the log"))
        if dropped > 0 then
            print("[BrainrotPolice] " .. dropped .. " lines were dropped by the rate limit")
        end
    end)

    elements:Button("Clear Traffic Log", section, function()
        logBuf = {}
        dropped = 0
        flushLog()
        print("[BrainrotPolice] traffic log cleared")
    end)

    connectIncoming()
    refreshWatched()
end
