-- Needle In A Haystack (PlaceId 73903875561291) -- the haystack itself
--
-- Key structure from the depth 4 dump:
--   workspace.Dome.Templates       16 hay tile meshes (hay1_tile_v01..v16)
--   workspace.Dome.Tiles           T_0..T_6355   main hay tiles
--   workspace.Dome.Tiles2          T2_<id>       second layer
--   workspace.Dome.Tiles3          T3_<id>       third layer
--   workspace.Dome.Tiles4/.Tiles5  empty, filled lazily
--   workspace.DisturbedTiles       T_<id>_live folders with S1..S64 straw parts
--                                  and G_g8_* group meshes (already moved straws)
--   workspace.SpecialHay           real Parts named T_225_46, T2_5002_10, ...
--                                  (tile id + straw id, special multiplier)
--   workspace.Gems                 Gem_1..Gem_4 (Gem_Hi/Mid/Deep, GemGlow light)
--   workspace.StrawHighlight       Part + SelectionBox, the game's hover marker
--   workspace.HaystackRoom/Pedestal_Socket   ProximityPrompt
--   workspace.HaystackRoom/EscapePadUnit/EscapePad  TouchTransmitter
--   workspace.terminal/Terminal_Screen       ProximityPrompt UpgradePrompt
--   workspace.vent/Vent_Ring                  BillboardGui DepositSign
--   workspace.chargepad                       drone charging
--   workspace.GroupReward/HayPlinth/HayPlinth_Slab  GroupRewardPrompt
--   ReplicatedStorage.HaystackRemotes        21 remotes
--     PullRequest, StrawPulled, DropRequest, DropAllRequest, DropFX,
--     DepositFX, PatchNoticeSeen, NeedleGrab, RemovedSync, CutsceneStart,
--     SettingsUpdate, DevCommand, StarFX, ClientReady, OpenUpgrades,
--     UpgradeRequest, ReturnToLobby, IntroSeen, ResetWorld, TunnelerHold,
--     GemGrab, GemTaken
--   ReplicatedStorage.HaystackConfig, HaystackSlots, HaystackSlots1,
--     DugTiles, HayKinds, StrawGroups, StrawGroupTree, HaystackStats,
--     StatSheet, GemStore, NeedleBadges, TimesStore, TeleportContract
--
-- Player attributes: StrawBalance, Carrying, CarryCap, CashPerStraw,
-- SpecialHayMult, GrabSize, PullRange, PullCooldown, PullSpeedLevel,
-- GrabRank, CarryRank, Gems, GemGain, NeedleIndex, HasNeedle, HoverDepth,
-- HandKinds, StrawsMoved, StatSheet (node levels/prices), Drone*/Tunneler*.
--
-- Pull arguments are not visible in a dump, so the module ships a learner:
-- it raycasts the hay under the cursor, tries the plausible PullRequest shapes
-- one by one and keeps the one the server answers on (StrawPulled).

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local httpservice = game:GetService("HttpService")
    local plr = players.LocalPlayer

    env.NIHPull = false
    env.NIHGems = false
    env.NIHSpecial = false
    env.NIHDrop = false
    env.NIHLog = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.pull = setdata.pull or false
    setdata.gems = setdata.gems or false
    setdata.special = setdata.special or false
    setdata.delay = tonumber(setdata.delay) or 0.55
    setdata.shape = setdata.shape or ""
    setdata.node = setdata.node or "carry"
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(data))

    local pullDelay = math.clamp(tonumber(setdata.delay) or 0.55, 0.25, 5)

    local LOG_FILE = "BrainrotPolice/needle_traffic.txt"

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

    local function numAttr(name, default)
        local v = tonumber(attr(name))
        if v then return v end
        return default
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
    -- remotes
    ----------------------------------------------------------------

    local function remotes()
        return replicatedstorage:FindFirstChild("HaystackRemotes")
    end

    local function remote(name)
        local f = remotes()
        return f and f:FindFirstChild(name)
    end

    local function fire(name, ...)
        local r = remote(name)
        if not r or not (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")) then return false end

        local args = table.pack(...)
        local ok = pcall(function()
            r:FireServer(table.unpack(args, 1, args.n))
        end)

        return ok
    end

    local function invoke(name, ...)
        local r = remote(name)
        if not r or not r:IsA("RemoteFunction") then return nil end

        local args = table.pack(...)
        local ok, result = pcall(function()
            return r:InvokeServer(table.unpack(args, 1, args.n))
        end)

        return ok and result or nil
    end

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
    -- live state
    ----------------------------------------------------------------

    local state = {
        pulled = 0,
        pulledAt = 0,
        gemsTaken = 0,
        lastShape = setdata.shape ~= "" and setdata.shape or nil,
        attempts = 0,
        errors = 0,
    }

    local lastUpdates = {}

    local function connectEvents()
        local f = remotes()
        if not f then return end

        for _, r in ipairs(f:GetChildren()) do
            if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
                local ok, conn = pcall(function()
                    return r.OnClientEvent:Connect(function(...)
                        if r.Name == "StrawPulled" then
                            state.pulled = state.pulled + 1
                            state.pulledAt = os.clock()
                        elseif r.Name == "GemTaken" then
                            state.gemsTaken = state.gemsTaken + 1
                        end

                        if #lastUpdates < 200 then
                            local parts = {}
                            local args = table.pack(...)

                            for i = 1, math.min(args.n, 6) do
                                parts[#parts+1] = tostring(args[i])
                            end

                            lastUpdates[#lastUpdates+1] = r.Name .. "(" .. table.concat(parts, ", ") .. ")"
                        end

                        if env.NIHLog then
                            pcall(pushLog, "IN " .. r.Name, ...)
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
    -- logging
    ----------------------------------------------------------------

    local logBuf = {}
    local LOG_MAX = 1500

    local function pushLog(tag, ...)
        local args = table.pack(...)
        local parts = {}

        for i = 1, math.min(args.n, 10) do
            local v = args[i]
            local ok, s = pcall(function()
                if type(v) == "table" then
                    local inner = {}
                    local n = 0
                    for k, val in pairs(v) do
                        n = n + 1
                        if n > 12 then
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
            print("[BrainrotPolice] no hookmetamethod, cannot log outgoing traffic")
            return false
        end

        local wrap = newcclosure or function(f) return f end
        local names = {}

        local f = remotes()
        if f then
            for _, r in ipairs(f:GetChildren()) do names[r] = r.Name end
        end

        local ok = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                local method = getnamecallmethod()

                if env.NIHLog and names[self] and (method == "FireServer" or method == "InvokeServer") then
                    pcall(pushLog, "OUT " .. names[self], ...)
                end

                return original(self, ...)
            end))
        end)

        hookInstalled = ok
        if not ok then print("[BrainrotPolice] could not hook __namecall") end
        return ok
    end

    ----------------------------------------------------------------
    -- hay helpers
    ----------------------------------------------------------------

    local HAY_ROOTS = { "Dome", "SpecialHay", "DisturbedTiles", "StrawGroupMeshes" }

    local function hayRoots()
        local out = {}
        for _, n in ipairs(HAY_ROOTS) do
            local r = workspace:FindFirstChild(n)
            if r then out[#out+1] = r end
        end
        return out
    end

    local function isHay(inst)
        if not inst then return false end

        local node = inst
        for _ = 1, 8 do
            if not node then break end

            local n = node.Name

            if n == "Dome" or n == "SpecialHay" or n == "DisturbedTiles" or n == "StrawGroupMeshes" then
                return true
            end

            -- room geometry and the lobby tiles are never straw
            if n == "HaystackRoom" or n == "LobbyTiles" or n == "MapLights"
                or n == "ContainmentShell" or n == "SkyWall" or n == "CullShield"
                or n == "CullBacking" or n == "CulledTiles" then
                return false
            end

            local lower = string.lower(n)
            if lower:find("hay_tile", 1, true) or lower:find("hay1_tile", 1, true)
                or lower:find("straw", 1, true) then
                return true
            end

            if n:match("^T_%d+") or n:match("^T2_%d+") or n:match("^T3_%d+") then
                return true
            end

            -- S1..S64 straw parts inside a disturbed tile
            if n:match("^S%d+$") and node.Parent and node.Parent.Name:find("_live", 1, true) then
                return true
            end

            node = node.Parent
        end

        return false
    end

    local function makeRayParams()
        local params = RaycastParams.new()

        local exclude = { workspace:FindFirstChild("StrawHighlight") }
        local char = plr.Character
        if char then exclude[#exclude+1] = char end

        for _, n in ipairs({ "CullShield", "CullBacking", "SkyWall", "ContainmentShell" }) do
            local o = workspace:FindFirstChild(n)
            if o then exclude[#exclude+1] = o end
        end

        local ok = pcall(function()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = exclude
        end)

        if not ok then
            pcall(function()
                params.FilterType = Enum.RaycastFilterType.Blacklist
                params.FilterDescendantsInstances = exclude
            end)
        end

        params.IgnoreWater = true
        return params
    end

    local function rayAt(x, y)
        local cam = workspace.CurrentCamera
        if not cam then return nil end

        local ok, ray = pcall(function()
            return cam:ViewportPointToRay(x, y)
        end)

        if not ok or not ray then return nil end

        local result = workspace:Raycast(ray.Origin, ray.Direction * 800, makeRayParams())
        if result and isHay(result.Instance) then return result end

        return nil
    end

    local function mouseRay()
        local mouse = plr:GetMouse()
        if not mouse then return nil end

        local result = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 800, makeRayParams())
        if result and isHay(result.Instance) then return result end

        return nil
    end

    ----------------------------------------------------------------
    -- pull shape learning
    ----------------------------------------------------------------

    -- every plausible argument list for PullRequest, the server answers with
    -- StrawPulled once one of them is right
    local SHAPES = {
        {
            name = "Hit",
            build = function(hit) return { hit } end,
        },
        {
            name = "Instance",
            build = function(hit) return { hit.Instance } end,
        },
        {
            name = "Instance, Position",
            build = function(hit) return { hit.Instance, hit.Position } end,
        },
        {
            name = "Position, Normal",
            build = function(hit) return { hit.Position, hit.Normal } end,
        },
        {
            name = "Instance, Position, Normal",
            build = function(hit) return { hit.Instance, hit.Position, hit.Normal } end,
        },
        {
            name = "Hit, Position",
            build = function(hit) return { hit, hit.Position } end,
        },
        {
            name = "Instance, Depth",
            build = function(hit) return { hit.Instance, numAttr("HoverDepth", 0) } end,
        },
        {
            name = "Name, Position",
            build = function(hit) return { hit.Instance.Name, hit.Position } end,
        },
    }

    local function shapeByName(name)
        for _, s in ipairs(SHAPES) do
            if s.name == name then return s end
        end
        return nil
    end

    local function fireShape(shape, hit)
        local args = shape.build(hit)
        state.attempts = state.attempts + 1
        return fire("PullRequest", table.unpack(args))
    end

    local function tryShapesOnce(hit)
        for _, shape in ipairs(SHAPES) do
            local before = state.pulled
            local ok = fireShape(shape, hit)
            task.wait(pullDelay + 0.1)

            if state.pulled > before then
                state.lastShape = shape.name
                setdata.shape = shape.name
                env.setconfig("shape", shape.name)
                print("[BrainrotPolice] pull shape learned: " .. shape.name)
                return shape
            end

            if not ok then state.errors = state.errors + 1 end
        end

        print("[BrainrotPolice] none of the shapes produced StrawPulled")
        return nil
    end

    ----------------------------------------------------------------
    -- auto pull
    ----------------------------------------------------------------

    local viewportPoint = { x = 0.5, y = 0.5 }

    local function randomHit()
        local cam = workspace.CurrentCamera
        if not cam then return nil end

        local vp = cam.ViewportSize

        -- aim slightly above the middle, the hay fills the lower half of the
        -- screen when laying in the dome
        for _ = 1, 14 do
            local x = vp.X * (0.15 + math.random() * 0.7)
            local y = vp.Y * (0.25 + math.random() * 0.55)
            local hit = rayAt(x, y)
            if hit then return hit, x, y end
        end

        return nil
    end

    local function cooldownNow()
        return numAttr("PullCooldown", 0.5)
    end

    task.spawn(function()
        local lastPull = 0

        while env.BrainrotPolice == registry do
            if env.NIHPull then
                local now = os.clock()

                if now - lastPull >= math.max(cooldownNow(), pullDelay) then
                    local hit = randomHit()

                    if not hit then
                        hit = mouseRay()
                    end

                    if hit then
                        local shape = state.lastShape and shapeByName(state.lastShape)

                        if not shape then
                            shape = tryShapesOnce(hit)
                        end

                        if shape then
                            fireShape(shape, hit)
                        end

                        lastPull = os.clock()
                    else
                        task.wait(0.2)
                    end
                else
                    task.wait(0.05)
                end
            else
                task.wait(0.2)
            end
        end
    end)

    ----------------------------------------------------------------
    -- special hay
    ----------------------------------------------------------------

    local specialHighlights = {}

    local function clearSpecial()
        for _, h in ipairs(specialHighlights) do
            pcall(function() h:Destroy() end)
        end
        specialHighlights = {}
    end

    local function specialParts()
        local folder = workspace:FindFirstChild("SpecialHay")
        if not folder then return {} end

        local out = {}
        for _, c in ipairs(folder:GetChildren()) do
            if c:IsA("BasePart") then out[#out+1] = c end
        end
        return out
    end

    local function specialList()
        local parts = specialParts()
        local out = {}

        for _, p in ipairs(parts) do
            out[#out+1] = string.format("%s | %s | %.0f, %.0f, %.0f",
                p.Name, p.ClassName, p.Position.X, p.Position.Y, p.Position.Z)
        end

        table.sort(out)
        return out
    end

    local function refreshSpecial()
        if #specialHighlights > 0 then return end

        for _, p in ipairs(specialParts()) do
            local h = Instance.new("Highlight")
            h.Name = "BPNeedleSpecial"
            h.Adornee = p
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillColor = Color3.fromRGB(255, 200, 40)
            h.OutlineColor = Color3.fromRGB(255, 120, 0)
            h.FillTransparency = 0.35
            h.OutlineTransparency = 0
            h.Parent = p
            specialHighlights[#specialHighlights+1] = h
        end
    end

    task.spawn(function()
        local wasOn = false

        while env.BrainrotPolice == registry do
            if env.NIHSpecial then
                local ok, err = pcall(refreshSpecial)
                if not ok then print("[BrainrotPolice] special highlight error: " .. tostring(err)) end
                wasOn = true
                task.wait(3)
            else
                if wasOn then
                    clearSpecial()
                    wasOn = false
                end
                task.wait(0.5)
            end
        end

        clearSpecial()
    end)

    ----------------------------------------------------------------
    -- gems
    ----------------------------------------------------------------

    local gemHighlights = {}

    local function clearGems()
        for _, h in ipairs(gemHighlights) do
            pcall(function() h:Destroy() end)
        end
        gemHighlights = {}
    end

    local function gemList()
        local folder = workspace:FindFirstChild("Gems")
        if not folder then return {} end

        local out = {}
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") or m:IsA("BasePart") then
                out[#out+1] = m
            end
        end
        return out
    end

    local function nearestGem()
        local root = getRoot()
        if not root then return nil end

        local best, bestDist = nil, math.huge
        for _, g in ipairs(gemList()) do
            local p = posOf(g)
            if p then
                local d = (p - root.Position).Magnitude
                if d < bestDist then best, bestDist = g, d end
            end
        end

        return best, bestDist
    end

    -- the gem has no prompt, GemGrab is the remote; try the plausible shapes
    local function grabGem(gem)
        if not gem then return false end

        local id = nil
        local n = gem.Name:match("(%d+)$")
        if n then id = tonumber(n) end

        local candidates = {
            { gem },
            { gem.Name },
            { id },
            { gem, gem.Name },
            { 1 },
        }

        for _, args in ipairs(candidates) do
            local ok = pcall(function()
                local r = remote("GemGrab")
                if not r then error("missing") end
                r:FireServer(table.unpack(args))
            end)

            if ok then
                print("[BrainrotPolice] GemGrab fired with " .. tostring(args[1]))
                task.wait(0.4)
                return true
            end
        end

        print("[BrainrotPolice] GemGrab failed")
        return false
    end

    task.spawn(function()
        local wasOn = false

        while env.BrainrotPolice == registry do
            if env.NIHGems then
                for _, g in ipairs(gemList()) do
                    local p = posOf(g)
                    if p then
                        local h = g:FindFirstChild("BPNeedleGem")
                        if not h then
                            h = Instance.new("Highlight")
                            h.Name = "BPNeedleGem"
                            h.Adornee = g
                            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            h.FillColor = Color3.fromRGB(90, 220, 255)
                            h.OutlineColor = Color3.fromRGB(40, 160, 255)
                            h.FillTransparency = 0.4
                            h.OutlineTransparency = 0
                            h.Parent = g
                            gemHighlights[#gemHighlights+1] = h
                        end
                    end
                end

                wasOn = true
                task.wait(2)
            else
                if wasOn then
                    clearGems()
                    wasOn = false
                end
                task.wait(0.5)
            end
        end

        clearGems()
    end)

    ----------------------------------------------------------------
    -- deposit
    ----------------------------------------------------------------

    local function ventPoint()
        local v = workspace:FindFirstChild("vent")
        if not v then return nil end

        local ring = v:FindFirstChild("Vent_Ring", true)
        return ring and posOf(ring) or posOf(v)
    end

    local function depositAll()
        local p = ventPoint()
        if p then
            tpTo(p)
            task.wait(0.15)
        end

        fire("DropAllRequest")
        print(string.format("[BrainrotPolice] DropAllRequest fired | carrying %s/%s straw balance %s",
            tostring(attr("Carrying")), tostring(attr("CarryCap")), tostring(attr("StrawBalance"))))
    end

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.NIHDrop then
                local carrying = tonumber(attr("Carrying")) or 0
                local cap = tonumber(attr("CarryCap")) or 8

                if carrying > 0 and carrying >= cap then
                    depositAll()
                    task.wait(1.5)
                end

                task.wait(1)
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- stats and modules
    ----------------------------------------------------------------

    local function statSheet()
        local raw = attr("StatSheet")
        if type(raw) == "table" then return raw end
        if type(raw) == "string" then
            local ok, decoded = pcall(function() return httpservice:JSONDecode(raw) end)
            if ok and type(decoded) == "table" then return decoded end
        end
        return nil
    end

    local function disturbed()
        local folder = workspace:FindFirstChild("DisturbedTiles")
        if not folder then return {} end

        local out = {}
        for _, c in ipairs(folder:GetChildren()) do
            if c:IsA("Folder") then out[#out+1] = c end
        end
        return out
    end

    local function statsText()
        local sheet = statSheet()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== Needle In A Haystack (haystack) ===")
        add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
        add(string.format("straw balance %s | carrying %s/%s | cash/straw %s | special mult %s",
            tostring(attr("StrawBalance")), tostring(attr("Carrying")), tostring(attr("CarryCap")),
            tostring(attr("CashPerStraw")), tostring(attr("SpecialHayMult"))))
        add(string.format("pull range %s | pull cooldown %s | grab size %s | gem gain %s | gems %s",
            tostring(attr("PullRange")), tostring(attr("PullCooldown")),
            tostring(attr("GrabSize")), tostring(attr("GemGain")), tostring(attr("Gems"))))
        add(string.format("needle index %s | has needle %s | straws moved %s | hover depth %s",
            tostring(attr("NeedleIndex")), tostring(attr("HasNeedle")),
            tostring(attr("StrawsMoved")), tostring(attr("HoverDepth"))))
        add(string.format("class %s | slots %s | hand kinds %s",
            tostring(attr("ClassKey")), tostring(attr("ClassSlots")), tostring(attr("HandKinds"))))
        add(string.format("level grab %s | carry %s | pull speed %s | range %s | drone %s | tunneler %s",
            tostring(attr("GrabRank")), tostring(attr("CarryRank")),
            tostring(attr("PullSpeedLevel")), tostring(attr("PullRangeLevel")),
            tostring(attr("DroneCount")), tostring(attr("TunnelerCount"))))

        if sheet and sheet.stats then
            local parts = {}
            for k, v in pairs(sheet.stats) do
                parts[#parts+1] = tostring(k) .. "=" .. tostring(v)
            end
            table.sort(parts)
            add("stats: " .. table.concat(parts, ", "))
        end

        if sheet and sheet.nodes then
            add("upgrade nodes:")
            local names = {}
            for k in pairs(sheet.nodes) do names[#names+1] = k end
            table.sort(names)

            for _, k in ipairs(names) do
                local node = sheet.nodes[k]
                add(string.format("  %s | level %s/%s | price %s | rank %s%s",
                    k, tostring(node.rank), tostring(node.max), tostring(node.price),
                    tostring(node.rank), node.squad and " | squad" or ""))
            end
        end

        add("special hay parts: " .. #specialParts())
        add("gems: " .. #gemList())
        add("disturbed tile folders: " .. #disturbed())

        return table.concat(L, "\n")
    end

    local function dumpRemotes()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== HaystackRemotes ===")
        local f = remotes()
        if f then
            for _, r in ipairs(f:GetChildren()) do
                add(r.ClassName .. " | " .. fullName(r))
            end
        end

        add("")
        add("=== special hay (" .. #specialParts() .. ") ===")
        for _, s in ipairs(specialList()) do add(s) end

        add("")
        add("=== gems ===")
        for _, g in ipairs(gemList()) do
            add(string.format("%s | %s", fullName(g), tostring(posOf(g))))
        end

        add("")
        add("=== disturbed tiles ===")
        for _, d in ipairs(disturbed()) do
            add(d.Name .. " | " .. #d:GetChildren() .. " children")
        end

        lastReport = table.concat(L, "\n")
        publish("remote dump", lastReport, "BrainrotPolice/needle_haystack.txt")
    end

    local function dumpModules()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== haystack module data ===")

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

        for _, name in ipairs({
            "HaystackConfig", "HayKinds", "StrawGroups", "StrawGroupTree",
            "DugTiles", "HaystackStats", "StatSheet", "HaystackSlots", "HaystackSlots1"
        }) do
            local m = replicatedstorage:FindFirstChild(name)
            if m and m:IsA("ModuleScript") then
                local ok, result = pcall(require, m)
                add(name .. ": " .. (ok and shallow(result, 0, {}) or ("require failed -> " .. tostring(result))))
            else
                add(name .. ": missing")
            end
        end

        lastReport = table.concat(L, "\n")
        publish("module dump", lastReport)
    end

    ----------------------------------------------------------------
    -- upgrade
    ----------------------------------------------------------------

    local function upgradeNodes()
        local sheet = statSheet()
        if not sheet or not sheet.nodes then return {} end

        local out = {}
        for k in pairs(sheet.nodes) do out[#out+1] = k end
        table.sort(out)
        return out
    end

    local function buyUpgrade(nodeName)
        local sheet = statSheet()
        local node = sheet and sheet.nodes and sheet.nodes[nodeName]
        if node then
            print(string.format("[BrainrotPolice] %s: level %s/%s, price %s, gems %s, straw balance %s",
                nodeName, tostring(node.rank), tostring(node.max), tostring(node.price),
                tostring(attr("Gems")), tostring(attr("StrawBalance"))))
        end

        local ok = fire("UpgradeRequest", nodeName)
        print("[BrainrotPolice] UpgradeRequest(" .. nodeName .. ") " .. (ok and "fired" or "failed"))

        task.wait(0.6)
        local after = statSheet()
        local afterNode = after and after.nodes and after.nodes[nodeName]
        if afterNode then
            print(string.format("[BrainrotPolice] %s now level %s/%s", nodeName,
                tostring(afterNode.rank), tostring(afterNode.max)))
        end
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Label("Needle In A Haystack (Haystack)", section)
    elements:Label("Special hay, gems, auto pull, deposit and upgrades.", section)

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
    elements:Label("Special hay", section)

    elements:Toggle("Highlight Special Hay", section, setdata.special, function(v)
        env.NIHSpecial = v
        setdata.special = v
        env.setconfig("special", v)

        if not v then clearSpecial() end
        print("[BrainrotPolice] special hay " .. (v and "highlighted (" .. #specialParts() .. " parts)" or "off"))
    end)

    elements:Button("List Special Hay", section, function()
        local list = specialList()
        local text = table.concat(list, "\n")
        lastReport = text
        publish("special hay list", text)
    end)

    elements:Button("Copy Special Hay List", section, function()
        local text = table.concat(specialList(), "\n")
        local ok = pcall(setclipboard, text)
        print("[BrainrotPolice] " .. (ok and ("copied " .. #specialList() .. " special hay parts") or "could not copy"))
    end)

    elements:Button("Teleport To Nearest Special Hay", section, function()
        local root = getRoot()
        local parts = specialParts()

        if not root or #parts == 0 then
            print("[BrainrotPolice] no special hay found")
            return
        end

        local best, bestDist = nil, math.huge
        for _, p in ipairs(parts) do
            local d = (p.Position - root.Position).Magnitude
            if d < bestDist then best, bestDist = p, d end
        end

        tpTo(best.Position)
        print(string.format("[BrainrotPolice] teleported to %s (%.0f studs) at %.0f, %.0f, %.0f",
            best.Name, bestDist, best.Position.X, best.Position.Y, best.Position.Z))
    end)

    ----------------------------------------------------------------
    elements:Label("Gems", section)

    elements:Toggle("Highlight Gems", section, setdata.gems, function(v)
        env.NIHGems = v
        setdata.gems = v
        env.setconfig("gems", v)

        if not v then clearGems() end
        print("[BrainrotPolice] gem highlight " .. (v and ("on (" .. #gemList() .. " gems)") or "off"))
    end)

    elements:Button("Teleport To Nearest Gem", section, function()
        local gem, dist = nearestGem()
        if not gem then
            print("[BrainrotPolice] no gems in workspace.Gems")
            return
        end

        tpTo(posOf(gem))
        print(string.format("[BrainrotPolice] teleported to %s (%.0f studs)", gem.Name, dist))
    end)

    elements:Button("Grab Nearest Gem", section, function()
        local gem, dist = nearestGem()
        if not gem then
            print("[BrainrotPolice] no gems found")
            return
        end

        local before = tonumber(attr("Gems")) or 0
        tpTo(posOf(gem))
        task.wait(0.2)

        grabGem(gem)
        task.wait(0.6)

        local after = tonumber(attr("Gems")) or 0
        print(string.format("[BrainrotPolice] tried %s (%.0f studs) | gems %d -> %d (%+d)",
            gem.Name, dist, before, after, after - before))
    end)

    ----------------------------------------------------------------
    elements:Label("Pull straws", section)

    elements:Toggle("Auto Pull", section, setdata.pull, function(v)
        env.NIHPull = v
        setdata.pull = v
        env.setconfig("pull", v)

        print("[BrainrotPolice] auto pull " .. (v and "on" or "off")
            .. (v and (" | shape: " .. tostring(state.lastShape or "learning")) or ""))
    end)

    elements:Textbox("Pull delay (seconds)", section, tostring(pullDelay), function(v)
        local n = tonumber(v)
        if not n then return end

        pullDelay = math.clamp(n, 0.25, 5)
        setdata.delay = pullDelay
        env.setconfig("delay", pullDelay)
    end)

    elements:Button("Learn Pull Shape (uses mouse)", section, function()
        local hit = mouseRay()
        if not hit then
            print("[BrainrotPolice] mouse is not over hay")
            return
        end

        print("[BrainrotPolice] learning on " .. fullName(hit.Instance))
        local shape = tryShapesOnce(hit)

        if shape then
            print("[BrainrotPolice] saved shape: " .. shape.name)
        else
            print("[BrainrotPolice] no shape worked, check the traffic log")
        end
    end)

    local shapeNames = {}
    for _, s in ipairs(SHAPES) do shapeNames[#shapeNames+1] = s.name end

    elements:Dropdown("Pull shape", section, shapeNames, state.lastShape or shapeNames[1], function(v)
        state.lastShape = v
        setdata.shape = v
        env.setconfig("shape", v)
    end)

    elements:Button("Pull Once (mouse)", section, function()
        local hit = mouseRay()
        if not hit then
            print("[BrainrotPolice] mouse is not over hay")
            return
        end

        local shape = state.lastShape and shapeByName(state.lastShape) or SHAPES[1]
        if shape then
            fireShape(shape, hit)
            print("[BrainrotPolice] PullRequest with shape " .. shape.name .. " on " .. hit.Instance.Name)
        end
    end)

    elements:Button("Pull Stats", section, function()
        print(string.format("[BrainrotPolice] pulled %d | attempts %d | errors %d | shape %s | cooldown %s",
            state.pulled, state.attempts, state.errors, tostring(state.lastShape or "none"),
            tostring(attr("PullCooldown"))))
        print(string.format("[BrainrotPolice] carrying %s/%s | straw balance %s | straws moved %s",
            tostring(attr("Carrying")), tostring(attr("CarryCap")),
            tostring(attr("StrawBalance")), tostring(attr("StrawsMoved"))))
    end)

    elements:Button("Select Straw Under Mouse", section, function()
        local hit = mouseRay()
        if not hit then
            print("[BrainrotPolice] mouse is not over hay")
            return
        end

        local marker = workspace:FindFirstChild("StrawHighlight")
        if marker and marker:IsA("BasePart") then
            marker.Position = hit.Position
            marker.Transparency = 0.5

            local box = marker:FindFirstChildOfClass("SelectionBox")
            if box then box.Adornee = marker end
        end

        print(string.format("[BrainrotPolice] %s | %s | %.1f, %.1f, %.1f",
            fullName(hit.Instance), hit.Instance.ClassName,
            hit.Position.X, hit.Position.Y, hit.Position.Z))
    end)

    ----------------------------------------------------------------
    elements:Label("Deposit", section)

    elements:Button("Deposit All (vent)", section, function()
        depositAll()
    end)

    elements:Toggle("Auto Deposit When Full", section, setdata.drop, function(v)
        env.NIHDrop = v
        setdata.drop = v
        env.setconfig("drop", v)
        print("[BrainrotPolice] auto deposit " .. (v and "on" or "off"))
    end)

    elements:Button("Teleport To Vent", section, function()
        local p = ventPoint()
        if p then
            tpTo(p)
            print("[BrainrotPolice] teleported to the vent")
        else
            print("[BrainrotPolice] vent not found")
        end
    end)

    ----------------------------------------------------------------
    elements:Label("Upgrades", section)

    local nodes = upgradeNodes()

    if #nodes > 0 then
        elements:Dropdown("Upgrade node", section, nodes, setdata.node, function(v)
            setdata.node = v
            env.setconfig("node", v)
        end)
    end

    elements:Button("Buy Selected Upgrade", section, function()
        buyUpgrade(setdata.node or "carry")
    end)

    elements:Button("Open Upgrade Menu", section, function()
        local ok = fire("OpenUpgrades")
        print("[BrainrotPolice] OpenUpgrades " .. (ok and "fired" or "failed"))
    end)

    elements:Button("Show Upgrade Nodes", section, function()
        local sheet = statSheet()
        if not sheet or not sheet.nodes then
            print("[BrainrotPolice] no StatSheet on the player")
            return
        end

        local names = {}
        for k in pairs(sheet.nodes) do names[#names+1] = k end
        table.sort(names)

        for _, k in ipairs(names) do
            local n = sheet.nodes[k]
            print(string.format("  %s | %s/%s | price %s", k, tostring(n.rank), tostring(n.max), tostring(n.price)))
        end
    end)

    ----------------------------------------------------------------
    elements:Label("Needle", section)

    elements:Button("Check Needle State", section, function()
        local preview = replicatedstorage:FindFirstChild("DomeCleared")
        local needle = preview and preview:FindFirstChild("NeedlePreview")

        print(string.format("[BrainrotPolice] needle index %s | has needle %s | preview %s",
            tostring(attr("NeedleIndex")), tostring(attr("HasNeedle")),
            needle and (fullName(needle) .. " @ " .. tostring(posOf(needle))) or "none"))
    end)

    elements:Button("Highlight Needle", section, function()
        local found = 0

        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name:lower():find("needle", 1, true) then
                local h = Instance.new("Highlight")
                h.Name = "BPNeedleMark"
                h.Adornee = d
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.FillColor = Color3.fromRGB(255, 60, 60)
                h.OutlineColor = Color3.fromRGB(255, 255, 255)
                h.FillTransparency = 0.2
                h.Parent = d

                print("[BrainrotPolice] needle part: " .. fullName(d) .. " @ " .. tostring(d.Position))
                found = found + 1
            end
        end

        print("[BrainrotPolice] " .. found .. " needle parts highlighted")
    end)

    elements:Button("Grab Needle", section, function()
        local ok = fire("NeedleGrab")
        print("[BrainrotPolice] NeedleGrab " .. (ok and "fired" or "failed")
            .. " | has needle " .. tostring(attr("HasNeedle")))
    end)

    elements:Button("Pedestal Prompt", section, function()
        local room = workspace:FindFirstChild("HaystackRoom")
        local socket = room and room:FindFirstChild("Pedestal_Socket", true)
        local prompt = socket and socket:FindFirstChildOfClass("ProximityPrompt")

        if not prompt then
            print("[BrainrotPolice] Pedestal_Socket prompt not found")
            return
        end

        local p = posOf(socket)
        if p then
            tpTo(p)
            task.wait(0.15)
        end

        pcall(function()
            if prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
            if prompt.MaxActivationDistance < 100 then prompt.MaxActivationDistance = 100 end
        end)

        if fireproximityprompt then pcall(fireproximityprompt, prompt) end
        print("[BrainrotPolice] pedestal prompt fired")
    end)

    elements:Button("Group Reward Prompt", section, function()
        local groupReward = workspace:FindFirstChild("GroupReward")
        local slab = groupReward and groupReward:FindFirstChild("HayPlinth_Slab", true)
        local prompt = slab and slab:FindFirstChildOfClass("ProximityPrompt")

        if not prompt then
            print("[BrainrotPolice] GroupRewardPrompt not found")
            return
        end

        local p = posOf(slab)
        if p then
            tpTo(p)
            task.wait(0.15)
        end

        pcall(function()
            if prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
            if prompt.MaxActivationDistance < 100 then prompt.MaxActivationDistance = 100 end
        end)

        if fireproximityprompt then pcall(fireproximityprompt, prompt) end
        print("[BrainrotPolice] group reward prompt fired | state " .. tostring(attr("GroupRewardState")))
    end)

    ----------------------------------------------------------------
    elements:Label("Diagnostics", section)

    local logOn = false

    elements:Toggle("Log Remote Traffic", section, false, function(v)
        env.NIHLog = v

        if v then
            logOn = true
            installHook()
            print("[BrainrotPolice] logging on, pull one straw by hand / grab one gem / buy one upgrade")
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

    elements:Button("Show Last Update Payloads", section, function()
        if #lastUpdates == 0 then
            print("[BrainrotPolice] no server events seen yet")
            return
        end

        for i = math.max(1, #lastUpdates - 29), #lastUpdates do
            print(string.format("  %d: %s", i, lastUpdates[i]))
        end
    end)

    elements:Button("Copy Last Update Payloads", section, function()
        if #lastUpdates == 0 then
            print("[BrainrotPolice] no server events seen yet")
            return
        end

        local ok = pcall(setclipboard, table.concat(lastUpdates, "\n"))
        print("[BrainrotPolice] " .. (ok and "payloads copied" or "could not copy"))
    end)

    elements:Button("Dump Remotes", section, function()
        task.spawn(function()
            local ok, err = pcall(dumpRemotes)
            if not ok then print("[BrainrotPolice] dump failed: " .. tostring(err)) end
        end)
    end)

    elements:Button("Dump Module Data", section, function()
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

    elements:Label("Manual remote tool", section)

    local remoteNames = {}
    local rf = remotes()
    if rf then
        for _, r in ipairs(rf:GetChildren()) do
            if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
                remoteNames[#remoteNames+1] = r.Name
            end
        end
        table.sort(remoteNames)
    end

    local manualRemote = remoteNames[1] or "ClientReady"

    if #remoteNames > 0 then
        elements:Dropdown("Remote", section, remoteNames, manualRemote, function(v)
            manualRemote = v
        end)
    end

    elements:Textbox("Arguments (comma separated, JSON allowed)", section, setdata.args or "", function(v)
        setdata.args = v
        env.setconfig("args", v)
    end)

    elements:Button("Fire Remote", section, function()
        local args = parseArgs(setdata.args or "")
        local ok = fire(manualRemote, table.unpack(args))
        print("[BrainrotPolice] " .. manualRemote .. " " .. (ok and "fired" or "failed"))
    end)

    connectEvents()
end
