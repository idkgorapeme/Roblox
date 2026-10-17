-- Where Did I Park? (PlaceId 113591676283798, "Hard" sub place)
--
-- Real structure (Depth 4 dump):
--   workspace.LocalParkingVisuals.Cars          Model Car_<id>, no prompts at all
--   workspace.LocalParkingVisuals.Valuables     Part Valuable_*, ProximityPrompt + ClickDetector
--   workspace.LocalParkingVisuals.MapObjectives Part GemDrop_1..5, ProximityPrompt
--   workspace.LocalParkingVisuals.NearbyCarTag  BillboardGui + CarLabel
--   workspace.LocalParkingVisuals.CarCashEffects
--   workspace.LocalParkingVisuals.Drones
--   ReplicatedStorage.ParkingGame.State         (folder, check at runtime)
--   ReplicatedStorage.ParkingGame.Action / .Update / .CityTravel / ParkingGlobal
--
-- Cars carry no ProximityPrompt and no ClickDetector, so checking a car has to
-- go through ParkingGame.Action. The logger tells us the exact arguments, the
-- module inspector shows whether the unlocked car is flagged client side.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.WDPCollect = false
    env.WDPHighlight = false
    env.WDPCars = false
    env.WDPTag = false
    env.WDPLog = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.collect = setdata.collect or false
    setdata.delay = tonumber(setdata.delay) or 0.25
    setdata.highlight = setdata.highlight or false
    setdata.cars = setdata.cars or false
    setdata.tag = setdata.tag or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local collectDelay = math.clamp(tonumber(setdata.delay) or 0.25, 0.05, 5)

    local LOG_FILE = "BrainrotPolice/parking_traffic.txt"
    local SCAN_FILE = "BrainrotPolice/parking_scan.txt"

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function lp()
        return workspace:FindFirstChild("LocalParkingVisuals")
    end

    local function carsFolder()
        local visuals = lp()
        return visuals and visuals:FindFirstChild("Cars")
    end

    local function nearbyTag()
        local visuals = lp()
        return visuals and visuals:FindFirstChild("NearbyCarTag")
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
        if filename and writefile then pcall(writefile, filename, text) end

        local lines = 1
        for _ in string.gmatch(text, "\n") do lines = lines + 1 end
        print(string.format("[BrainrotPolice] %s: %d lines, copied%s", name, lines,
            filename and (", saved to " .. filename) or ""))

        -- keep the console readable, the full text is on the clipboard
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
    -- cars
    ----------------------------------------------------------------

    local function carList()
        local folder = carsFolder()
        if not folder then return {} end

        local out = {}
        for _, c in ipairs(folder:GetChildren()) do
            if c:IsA("Model") then out[#out+1] = c end
        end
        return out
    end

    local function isMutated(car)
        for _, c in ipairs(car:GetChildren()) do
            if c.Name == "MutationScratch" then return true end
        end
        return false
    end

    -- every car has the same mesh parts; anything extra (MutationScratch, an
    -- added Highlight, a marker part) makes the signature unique
    local function childSignature(car)
        local parts = {}
        for _, c in ipairs(car:GetChildren()) do
            parts[#parts+1] = c.ClassName .. ":" .. c.Name
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end

    local carHighlights = {}

    local function clearCarHighlights()
        for _, h in ipairs(carHighlights) do
            pcall(function() h:Destroy() end)
        end
        carHighlights = {}
    end

    local function markCar(car, color, transparency)
        local h = Instance.new("Highlight")
        h.Name = "BPDropCar"
        h.Adornee = car
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillColor = color
        h.OutlineColor = color
        h.FillTransparency = transparency or 0.85
        h.OutlineTransparency = 0
        h.Parent = car
        carHighlights[#carHighlights+1] = h
    end

    local function nearbyCar()
        local root = getRoot()
        if not root then return nil end

        local best, bestDist = nil, math.huge
        local rootPos = root.Position

        for _, car in ipairs(carList()) do
            local pos = posOf(car)
            if pos then
                local d = (pos - rootPos).Magnitude
                if d < bestDist then best, bestDist = car, d end
            end
        end

        return best, bestDist
    end

    ----------------------------------------------------------------
    -- collectibles (valuables + gem drops)
    ----------------------------------------------------------------

    local function firstPromptOrClick(inst)
        local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then return prompt, "prompt" end

        local click = inst:FindFirstChildWhichIsA("ClickDetector", true)
        if click then return click, "click" end

        return nil, nil
    end

    local function collectibles()
        local visuals = lp()
        if not visuals then return {} end

        local out = {}
        local seen = {}

        local function add(container, kind)
            if not container then return end

            for _, c in ipairs(container:GetChildren()) do
                local obj, otype = firstPromptOrClick(c)
                if obj and not seen[obj] then
                    seen[obj] = true

                    out[#out+1] = {
                        model = c,
                        obj = obj,
                        kind = otype,
                        label = kind .. ": " .. c.Name,
                        pos = posOf(c),
                    }
                end
            end
        end

        add(visuals:FindFirstChild("Valuables"), "valuable")
        add(visuals:FindFirstChild("MapObjectives"), "gem")

        return out
    end

    local function activate(obj, kind)
        if kind == "prompt" then
            pcall(function()
                if obj.HoldDuration > 0 then obj.HoldDuration = 0 end
                if obj.MaxActivationDistance < 150 then obj.MaxActivationDistance = 150 end
            end)

            if fireproximityprompt then pcall(fireproximityprompt, obj) end
        elseif kind == "click" then
            if fireclickdetector then pcall(fireclickdetector, obj, 100) end
        end
    end

    local collectCooldown = {}
    local COLLECT_RETRY = 20

    local function nearestCollectible()
        local root = getRoot()
        if not root then return nil end

        local now = os.clock()
        local rootPos = root.Position
        local best, bestDist = nil, math.huge

        for _, e in ipairs(collectibles()) do
            local last = collectCooldown[e.obj]
            if e.pos and e.obj.Parent and (not last or now - last > COLLECT_RETRY) then
                local d = (e.pos - rootPos).Magnitude
                if d < bestDist then best, bestDist = e, d end
            end
        end

        return best
    end

    task.spawn(function()
        while true do
            if env.BrainrotPolice ~= registry then break end

            if env.WDPCollect then
                local ok, target = pcall(nearestCollectible)

                if not ok then
                    print("[BrainrotPolice] collect error: " .. tostring(target))
                    task.wait(1)
                elseif target then
                    tpTo(target.pos)
                    task.wait(0.12)
                    activate(target.obj, target.kind)
                    collectCooldown[target.obj] = os.clock()
                    task.wait(collectDelay)
                else
                    task.wait(0.6)
                end
            else
                task.wait(0.2)
            end
        end
    end)

    local collectHighlights = {}

    local function clearCollectHighlights()
        for _, h in ipairs(collectHighlights) do
            pcall(function() h:Destroy() end)
        end
        collectHighlights = {}
    end

    local function refreshCollectHighlights()
        local root = getRoot()
        if not root then return end

        local rootPos = root.Position
        local keep = {}

        for _, e in ipairs(collectibles()) do
            if e.model.Parent and e.pos and (e.pos - rootPos).Magnitude <= 600 then
                keep[e.model] = true

                local h = e.model:FindFirstChild("BPDropLoot")
                if not h then
                    h = Instance.new("Highlight")
                    h.Name = "BPDropLoot"
                    h.Adornee = e.model
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.FillTransparency = 0.7
                    h.OutlineTransparency = 0
                    h.Parent = e.model
                    collectHighlights[#collectHighlights+1] = h
                end

                local c = e.label:find("gem") and Color3.fromRGB(80, 220, 255) or Color3.fromRGB(255, 200, 40)
                h.FillColor = c
                h.OutlineColor = c
            end
        end

        for _, h in ipairs(collectHighlights) do
            local m = h.Adornee or h.Parent
            if not m or not keep[m] then
                pcall(function() h:Destroy() end)
            end
        end
    end

    ----------------------------------------------------------------
    -- nearby car tag watcher
    ----------------------------------------------------------------

    local tagWatching = false
    local lastTagText = ""

    local function startTagWatch()
        if tagWatching then return end

        local tag = nearbyTag()
        if not tag then
            print("[BrainrotPolice] NearbyCarTag not found")
            return
        end

        tagWatching = true

        local label = tag:FindFirstChild("CarLabel", true)
        print("[BrainrotPolice] watching NearbyCarTag"
            .. (label and (" | current text: " .. tostring(label.Text)) or " | no CarLabel found"))

        task.spawn(function()
            while tagWatching and env.BrainrotPolice == registry do
                local t = nearbyCar()
                local lbl = tag:FindFirstChild("CarLabel", true)

                if lbl then
                    local text = tostring(lbl.Text)
                    local tagPos = tag.Adornee and posOf(tag.Adornee) or nil
                    local suffix = ""

                    if t then
                        local root = getRoot()
                        local d = root and posOf(t) and (posOf(t) - root.Position).Magnitude or -1
                        suffix = string.format(" | nearest car %s (%.0f studs) mutated=%s",
                            t.Name, d, tostring(isMutated(t)))
                    end

                    if text ~= lastTagText then
                        lastTagText = text
                        print("[BrainrotPolice] tag: " .. text .. suffix
                            .. (tagPos and (" @ " .. tostring(tagPos)) or ""))
                    end
                end

                task.wait(0.5)
            end
        end)
    end

    local function stopTagWatch()
        tagWatching = false
        lastTagText = ""
    end

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

        for _, name in ipairs({ "ParkingGlobal" }) do
            local r = replicatedstorage:FindFirstChild(name)
            if r and (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")) then
                watched[r] = name
            end
        end

        local admin = replicatedstorage:FindFirstChild("ParkingAdmin")
        local req = admin and admin:FindFirstChild("Request")
        if req then watched[req] = "ParkingAdmin.Request" end
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

                if env.WDPLog and watched[self] and (method == "FireServer" or method == "InvokeServer") then
                    pcall(pushLog, "OUT " .. watched[self], ...)
                end

                return original(self, ...)
            end))
        end)

        hookInstalled = ok
        if not ok then print("[BrainrotPolice] could not hook __namecall") end
        return ok
    end

    local lastUpdates = {}

    local function connectIncoming()
        refreshWatched()

        for remote, label in pairs(watched) do
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                local ok, conn = pcall(function()
                    return remote.OnClientEvent:Connect(function(...)
                        if label:find("Update") then
                            lastUpdates[#lastUpdates+1] = serialize(table.pack(...), 0, {})
                            if #lastUpdates > 30 then table.remove(lastUpdates, 1) end
                        end

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
    -- state + module inspection
    ----------------------------------------------------------------

    local function dumpState()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== ParkingGame state ===")
        add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))

        local pg = replicatedstorage:FindFirstChild("ParkingGame")
        if not pg then
            add("ParkingGame folder missing")
        else
            add("ParkingGame attrs: " .. attrString(attrsOf(pg)))

            local state = pg:FindFirstChild("State")
            if not state then
                add("no State folder")
            else
                local function walk(inst, depth, prefix)
                    if depth > 4 then return end

                    for _, c in ipairs(inst:GetChildren()) do
                        local value = ""
                        if c:IsA("ValueBase") then
                            local ok, v = pcall(function() return c.Value end)
                            value = ok and (" = " .. tostring(v)) or " = ?"
                        end

                        add(prefix .. c.ClassName .. " | " .. c.Name .. value
                            .. (#attrString(attrsOf(c)) > 0 and (" | attrs: " .. attrString(attrsOf(c))) or ""))

                        walk(c, depth + 1, prefix .. "  ")
                    end
                end

                walk(state, 1, "  ")
            end
        end

        add("")
        add("=== player ===")
        add("player attrs: " .. attrString(attrsOf(plr)))

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

        publish("state dump", table.concat(L, "\n"))
    end

    -- only modules that look like plain data / config, requiring a UI module
    -- could build gui or start effects as a side effect
    local MODULE_NAMES = {
        "Config", "CarCatalog", "CarModels", "MutationIndex", "CarMutations",
        "CarEscapeConfig", "MainShopCatalog", "PermanentUpgrades",
        "GlobalEventCatalog", "CityLayout"
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
                if n > 12 then
                    parts[#parts+1] = "..."
                    break
                end
                parts[#parts+1] = tostring(k) .. "=" .. shallow(val, depth + 1, seen)
            end

            seen[v] = nil
            return "{" .. table.concat(parts, ", ") .. "}"
        end

        if t == "Instance" then return "<" .. v.ClassName .. " " .. v.Name .. ">" end
        if t == "string" then
            if #v > 120 then return string.format("%q..", string.sub(v, 1, 120)) end
            return string.format("%q", v)
        end

        return tostring(v)
    end

    local function readModules()
        local pg = replicatedstorage:FindFirstChild("ParkingGame")
        if not pg then
            print("[BrainrotPolice] ParkingGame folder missing")
            return
        end

        local L = {}
        local function add(s) L[#L+1] = tostring(s) end
        add("=== ParkingGame modules ===")

        for _, name in ipairs(MODULE_NAMES) do
            local mod = pg:FindFirstChild(name)
            if mod and mod:IsA("ModuleScript") then
                local ok, result = pcall(require, mod)

                if not ok then
                    add(name .. ": require failed -> " .. tostring(result))
                else
                    add(name .. " (" .. typeof(result) .. "): " .. shallow(result, 0, {}))
                end
            else
                add(name .. ": missing")
            end
        end

        publish("module dump", table.concat(L, "\n"))
    end

    ----------------------------------------------------------------
    -- scans
    ----------------------------------------------------------------

    local lastReport = ""

    local function runScan()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== Where Did I Park? scan ===")
        add("PlaceId: " .. tostring(game.PlaceId))
        add("JobId: " .. tostring(game.JobId))

        local cars = carList()
        local visuals = lp()

        add(string.format("cars: %d (folder %s)", #cars, carsFolder() and "found" or "MISSING"))
        add("player attrs: " .. attrString(attrsOf(plr)))

        local modelsEmpty = 0
        local attrKeys = {}
        local attrValues = {}
        local mutated = {}

        for _, car in ipairs(cars) do
            local attrs = attrsOf(car)
            if next(attrs) == nil then modelsEmpty = modelsEmpty + 1 end

            for k, v in pairs(attrs) do
                attrKeys[k] = (attrKeys[k] or 0) + 1

                local byKey = attrValues[k]
                if not byKey then
                    byKey = {}
                    attrValues[k] = byKey
                end

                local sv = tostring(v)
                if byKey[sv] == nil then
                    local n = 0
                    for _ in pairs(byKey) do n = n + 1 end
                    if n < 40 then byKey[sv] = 1 end
                end
            end

            if isMutated(car) then mutated[#mutated+1] = car end
        end

        add(string.format("cars without attributes: %d", modelsEmpty))
        add("car attribute keys: " .. topList(attrKeys, 25))

        for k in pairs(attrKeys) do
            if attrKeys[k] <= 12 then
                add(string.format("  rare key %s (%d cars): %s", k, attrKeys[k], topList(attrValues[k], 10)))
            end
        end

        add(string.format("mutated cars (MutationScratch): %d", #mutated))
        for i = 1, math.min(#mutated, 25) do
            add("  " .. mutated[i].Name .. " @ " .. tostring(posOf(mutated[i])))
        end

        -- child signature: everything that is not the normal 8 meshes
        local normal = "MeshPart:BodyPaint,MeshPart:DarkTrim,MeshPart:Headlights,MeshPart:SmokedGlass,MeshPart:TailLights,MeshPart:Tires,MeshPart:WheelMetal,Part:Collision"
        local odd = {}

        for _, car in ipairs(cars) do
            local sig = childSignature(car)
            if sig ~= normal then
                odd[#odd+1] = { name = car.Name, sig = sig }
            end
        end

        add(string.format("cars with a non standard child set: %d", #odd))
        for i = 1, math.min(#odd, 30) do
            add("  " .. odd[i].name .. " -> " .. odd[i].sig)
        end

        if visuals then
            local function section(name)
                local f = visuals:FindFirstChild(name)
                if not f then
                    add(name .. ": missing")
                    return
                end

                local kids = f:GetChildren()
                local names = {}
                for i = 1, math.min(#kids, 15) do names[#names+1] = kids[i].Name end

                add(string.format("%s: %d children | %s%s", name, #kids,
                    table.concat(names, ", "), #kids > 15 and " ..." or ""))
            end

            for _, name in ipairs({ "Valuables", "MapObjectives", "Drones", "CarCashEffects", "Cars" }) do
                section(name)
            end
        end

        local items = collectibles()
        add(string.format("collectibles with prompts: %d", #items))
        for i = 1, math.min(#items, 20) do
            add(string.format("  %s | %s | %s", items[i].label, items[i].kind, tostring(items[i].pos)))
        end

        local tag = nearbyTag()
        if tag then
            local label = tag:FindFirstChild("CarLabel", true)
            add("NearbyCarTag: enabled=" .. tostring(tag.Enabled)
                .. " adornee=" .. tostring(tag.Adornee)
                .. " text=" .. tostring(label and label.Text))
        else
            add("NearbyCarTag: missing")
        end

        local pg = replicatedstorage:FindFirstChild("ParkingGame")
        local state = pg and pg:FindFirstChild("State")
        if state then
            local names = {}
            for _, c in ipairs(state:GetChildren()) do names[#names+1] = c.ClassName .. ":" .. c.Name end
            add("State: " .. table.concat(names, ", "))
        else
            add("State: missing")
        end

        lastReport = table.concat(L, "\n")
        publish("scan", lastReport, SCAN_FILE)
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Label("Where Did I Park?", section)
    elements:Label("Cars have no prompts. Checking a car goes through ParkingGame.Action, use the logger.", section)

    elements:Button("Scan Lot", section, function()
        task.spawn(function()
            local ok, err = pcall(runScan)
            if not ok then print("[BrainrotPolice] scan failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Dump State Folder", section, function()
        task.spawn(function()
            local ok, err = pcall(dumpState)
            if not ok then print("[BrainrotPolice] state dump failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Read Game Modules (Config, CarCatalog, ...)", section, function()
        task.spawn(function()
            local ok, err = pcall(readModules)
            if not ok then print("[BrainrotPolice] module dump failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Copy Last Report", section, function()
        if lastReport == "" then
            print("[BrainrotPolice] nothing scanned yet")
            return
        end

        local ok = pcall(setclipboard, lastReport)
        print("[BrainrotPolice] " .. (ok and "report copied" or "could not copy"))
    end)

    ----------------------------------------------------------------
    elements:Label("Cars", section)

    elements:Toggle("Highlight All Cars", section, setdata.cars, function(v)
        env.WDPCars = v
        setdata.cars = v
        env.setconfig("cars", v)
    end)

    task.spawn(function()
        local wasOn = false

        while env.BrainrotPolice == registry do
            if env.WDPCars then
                local root = getRoot()
                if root then
                    local rootPos = root.Position
                    local marked = {}

                    for _, car in ipairs(carList()) do
                        local pos = posOf(car)
                        if pos then
                            local d = (pos - rootPos).Magnitude
                            if d <= 250 then
                                marked[car] = true

                                local existing = car:FindFirstChild("BPDropCar")
                                if not existing then
                                    markCar(car, isMutated(car) and Color3.fromRGB(200, 80, 255) or Color3.fromRGB(90, 160, 255))
                                else
                                    local c = isMutated(car) and Color3.fromRGB(200, 80, 255) or Color3.fromRGB(90, 160, 255)
                                    existing.FillColor = c
                                    existing.OutlineColor = c
                                end
                            end
                        end
                    end

                    for _, h in ipairs(carHighlights) do
                        local car = h.Adornee or h.Parent
                        if not car or not marked[car] then
                            pcall(function() h:Destroy() end)
                        end
                    end

                    -- rebuild the list without the destroyed handles
                    local alive = {}
                    for _, h in ipairs(carHighlights) do
                        if h.Parent then alive[#alive+1] = h end
                    end
                    carHighlights = alive
                end

                wasOn = true
                task.wait(1.5)
            else
                if wasOn then
                    clearCarHighlights()
                    wasOn = false
                end
                task.wait(0.5)
            end
        end

        clearCarHighlights()
    end)

    elements:Button("Highlight Mutated Cars", section, function()
        clearCarHighlights()

        local n = 0
        for _, car in ipairs(carList()) do
            if isMutated(car) then
                markCar(car, Color3.fromRGB(200, 80, 255), 0.35)
                print("[BrainrotPolice] mutated: " .. car.Name .. " @ " .. tostring(posOf(car)))
                n = n + 1
            end
        end

        print("[BrainrotPolice] " .. n .. " mutated cars highlighted")
    end)

    elements:Button("Clear Car Highlights", section, function()
        clearCarHighlights()
        print("[BrainrotPolice] car highlights cleared")
    end)

    elements:Button("Show Nearby Car", section, function()
        local car, dist = nearbyCar()
        if not car then
            print("[BrainrotPolice] no cars found")
            return
        end

        print(string.format("[BrainrotPolice] nearest: %s | %.0f studs | mutated=%s | attrs: %s",
            car.Name, dist, tostring(isMutated(car)), attrString(attrsOf(car))))
        print("[BrainrotPolice] path: " .. fullName(car))
    end)

    elements:Toggle("Watch Nearby Car Tag", section, setdata.tag, function(v)
        env.WDPTag = v
        setdata.tag = v
        env.setconfig("tag", v)

        if v then
            startTagWatch()
        else
            stopTagWatch()
            print("[BrainrotPolice] tag watch off")
        end
    end)

    ----------------------------------------------------------------
    elements:Label("Collect (Valuables + Gem Drops)", section)

    elements:Toggle("Auto Collect", section, setdata.collect, function(v)
        env.WDPCollect = v
        setdata.collect = v
        env.setconfig("collect", v)
    end)

    elements:Textbox("Collect Delay (seconds)", section, tostring(collectDelay), function(v)
        local n = tonumber(v)
        if not n then return end

        collectDelay = math.clamp(n, 0.05, 5)
        setdata.delay = collectDelay
        env.setconfig("delay", collectDelay)
    end)

    elements:Button("Collect Nearest Now", section, function()
        local target = nearestCollectible()
        if not target then
            print("[BrainrotPolice] no valuables or gem drops found")
            return
        end

        tpTo(target.pos)
        task.wait(0.12)
        activate(target.obj, target.kind)
        collectCooldown[target.obj] = os.clock()
        print("[BrainrotPolice] collected: " .. target.label)
    end)

    elements:Toggle("Highlight Collectibles", section, setdata.highlight, function(v)
        env.WDPHighlight = v
        setdata.highlight = v
        env.setconfig("highlight", v)

        if not v then clearCollectHighlights() end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.WDPHighlight then
                local ok, err = pcall(refreshCollectHighlights)
                if not ok then print("[BrainrotPolice] highlight error: " .. tostring(err)) end
                task.wait(2)
            else
                task.wait(0.5)
            end
        end

        clearCollectHighlights()
    end)

    ----------------------------------------------------------------
    elements:Label("Learn the Action arguments", section)

    local logWasOn = false

    elements:Toggle("Log Remote Traffic", section, false, function(v)
        env.WDPLog = v

        if v then
            logWasOn = true
            installHook()
            refreshWatched()
            print("[BrainrotPolice] logging on, check one car by hand, then turn it off and copy the log")
        elseif logWasOn then
            logWasOn = false
            flushLog()
            print("[BrainrotPolice] logging off, saved to " .. LOG_FILE .. " - press Copy Traffic Log")
        end
    end)

    elements:Button("Copy Traffic Log", section, function()
        if #logBuf == 0 then
            print("[BrainrotPolice] traffic log is empty")
            return
        end

        local ok = pcall(setclipboard, table.concat(logBuf, "\n"))
        print("[BrainrotPolice] " .. (ok and ("copied " .. #logBuf .. " log lines") or "could not copy"))
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

    elements:Button("Show Last Update Payloads", section, function()
        if #lastUpdates == 0 then
            print("[BrainrotPolice] no Update payloads received yet")
            return
        end

        print("[BrainrotPolice] last " .. #lastUpdates .. " Update payloads:")
        for i = 1, #lastUpdates do
            print(string.format("  %d: %s", i, lastUpdates[i]))
        end
    end)

    elements:Button("Copy Last Update Payloads", section, function()
        if #lastUpdates == 0 then
            print("[BrainrotPolice] no Update payloads received yet")
            return
        end

        local ok = pcall(setclipboard, table.concat(lastUpdates, "\n"))
        print("[BrainrotPolice] " .. (ok and "payloads copied" or "could not copy"))
    end)

    connectIncoming()
    refreshWatched()
end
