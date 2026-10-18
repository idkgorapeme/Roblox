-- BrainrotPolice dumper
--
-- One call: dumper.run{ depth = 3, cap = 2500, modules = false } -> text, info
--
-- What it collects in a single pass:
--   header          place, job, player, executor, game name
--   services        every service with its child count
--   workspace tree  class | name | attributes | values | prompts
--   ReplicatedStorage tree (includes ReplicatedFirst when not empty)
--   Lighting        the few values that matter for visuals
--   remotes         all RemoteEvent/RemoteFunction/UnreliableRemoteEvent
--   prompts         all ProximityPrompt + ClickDetector with action text
--   values          all ValueBase with their current value
--   attributes      every attribute key with count + most common values
--   player          leaderstats, attributes, PlayerGui, backpack
--   character       humanoid state, tools, accessories, parts
--   modules         every ModuleScript path (and optionally its exported table)
--   summary         class histogram + totals
--
-- The sink caps the output, so a 12k-child folder cannot freeze the game.

local dumper = {}

local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")
local httpservice = game:GetService("HttpService")
local localplayer = players.LocalPlayer

dumper.presets = {
    Standard = { depth = 3, cap = 3000, perLevel = 250 },
    Deep = { depth = 4, cap = 8000, perLevel = 400 },
    Huge = { depth = 6, cap = 20000, perLevel = 800 },
}

local MAX_SCAN = 90000

----------------------------------------------------------------
-- value formatting
----------------------------------------------------------------

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok then return result end
    return fallback
end

local function fmt(value, depth)
    depth = depth or 0

    local t = typeof(value)

    if t == "string" then
        if #value > 140 then
            return string.format("%q..(%d)", string.sub(value, 1, 140), #value)
        end
        return string.format("%q", value)
    elseif t == "Instance" then
        return "<" .. value.ClassName .. " " .. tostring(value.Name) .. ">"
    elseif t == "table" then
        if depth >= 2 then return "{...}" end

        local parts = {}
        local n = 0

        for k, v in pairs(value) do
            n = n + 1
            if n > 14 then
                parts[#parts+1] = "..."
                break
            end
            parts[#parts+1] = tostring(k) .. "=" .. fmt(v, depth + 1)
        end

        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    return tostring(value)
end

local function attrOf(inst)
    return safe(function() return inst:GetAttributes() end, {})
end

local function attrText(inst)
    local attrs = attrOf(inst)

    local keys = {}
    for k in pairs(attrs) do keys[#keys+1] = k end
    if #keys == 0 then return "" end

    table.sort(keys)

    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts+1] = tostring(k) .. "=" .. fmt(attrs[k])
    end

    local text = " {" .. table.concat(parts, ", ") .. "}"
    if #text > 220 then text = string.sub(text, 1, 220) .. "..}" end
    return text
end

local function valueText(inst)
    if not inst:IsA("ValueBase") then return "" end

    local value = safe(function() return inst.Value end, nil)
    if value == nil then return "" end

    return " = " .. fmt(value)
end

local function promptText(inst)
    if inst:IsA("ProximityPrompt") then
        return string.format(" [prompt action=%q object=%q hold=%.2f dist=%.0f enabled=%s]",
            tostring(inst.ActionText), tostring(inst.ObjectText),
            tonumber(inst.HoldDuration) or 0, tonumber(inst.MaxActivationDistance) or 0,
            tostring(inst.Enabled))
    elseif inst:IsA("ClickDetector") then
        return string.format(" [click maxdist=%.0f]", tonumber(inst.MaxActivationDistance) or 0)
    end

    return ""
end

local function isRemote(inst)
    return inst:IsA("RemoteEvent")
        or inst:IsA("UnreliableRemoteEvent")
        or inst:IsA("RemoteFunction")
end

local function isInteractive(inst)
    return inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector")
end

----------------------------------------------------------------
-- sink
----------------------------------------------------------------

local function makeSink(cap)
    local out = {}
    local count = 0
    local truncated = false

    local function add(text, force)
        if not force and count >= cap then
            truncated = true
            return false
        end

        out[#out+1] = tostring(text)
        count = count + 1
        return true
    end

    local function stats()
        return truncated, count
    end

    return add, out, stats
end

local function header(add, title, force)
    add("", force)
    add("======== " .. title .. " ========", force)
end

----------------------------------------------------------------
-- tree
----------------------------------------------------------------

local function sortChildren(kids)
    if #kids <= 800 then
        table.sort(kids, function(a, b)
            if a.ClassName == b.ClassName then
                return a.Name < b.Name
            end
            return a.ClassName < b.ClassName
        end)
    end

    return kids
end

-- children that only differ in identity are grouped, a pile of 488 identical
-- "Part | Post" becomes one line instead of 488
local function groupChildren(kids)
    local order = {}
    local map = {}
    local cheap = #kids > 1200

    for _, c in ipairs(kids) do
        local key

        if cheap then
            key = c.ClassName .. "|" .. c.Name
        else
            key = c.ClassName .. "|" .. c.Name .. "|" .. attrText(c) .. valueText(c)
        end

        local entry = map[key]

        if not entry then
            entry = { key = key, inst = c, count = 0 }
            map[key] = entry
            order[#order+1] = entry
        end

        entry.count = entry.count + 1
    end

    table.sort(order, function(a, b) return a.key < b.key end)
    return order
end

----------------------------------------------------------------
-- player avatars and NPC humanoid rigs are noise: full r6/r15 rigs with
-- hundreds of OriginalPosition / AvatarPartScaleType / Animate values.
-- Player avatars get one line; NPC humanoid models keep their model line +
-- attributes and any non-rig gameplay children (carried items, prompts, etc.).
----------------------------------------------------------------

local AVATAR_VALUE_NAMES = {
    OriginalPosition = true,
    OriginalSize = true,
    OriginalPivot = true,
    AvatarPartScaleType = true,
    BodyDepthScale = true,
    BodyHeightScale = true,
    BodyWidthScale = true,
    BodyTypeScale = true,
    BodyProportionScale = true,
    HeadScale = true,
    ScaleDampeningPercent = true,
    RBXRefinementScale = true,
}

local RIG_PART_NAMES = {
    Head = true,
    HumanoidRootPart = true,
    Torso = true,
    UpperTorso = true,
    LowerTorso = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
    LeftFoot = true,
    LeftHand = true,
    LeftLowerArm = true,
    LeftLowerLeg = true,
    LeftUpperArm = true,
    LeftUpperLeg = true,
    RightFoot = true,
    RightHand = true,
    RightLowerArm = true,
    RightLowerLeg = true,
    RightUpperArm = true,
    RightUpperLeg = true,
}

local RIG_CHILD_CLASSES = {
    Accessory = true,
    BodyColors = true,
    Shirt = true,
    Pants = true,
    ShirtGraphic = true,
    CharacterMesh = true,
    Humanoid = true,
    HumanoidDescription = true,
}

local function hasInteractiveDescendant(inst)
    local ok, list = pcall(function() return inst:GetDescendants() end)
    if not ok or not list then return false end

    for _, d in ipairs(list) do
        if isInteractive(d) then return true end
    end

    return false
end

local function isRigChild(child)
    if RIG_CHILD_CLASSES[child.ClassName] then return true end

    if (child:IsA("LocalScript") or child:IsA("Script"))
        and (child.Name == "Animate" or child.Name == "Health") then
        return true
    end

    if child:IsA("BasePart") and RIG_PART_NAMES[child.Name] then
        if not hasInteractiveDescendant(child) then
            return true
        end
    end

    if child:IsA("BillboardGui") and (child.Name == "_Label" or child.Name == "NameTag") then
        return true
    end

    return false
end

local function visibleChildren(inst)
    local kids = inst:GetChildren()

    if inst ~= localplayer.Character
        and inst:IsA("Model")
        and safe(function() return inst:FindFirstChildOfClass("Humanoid") end, nil) ~= nil then
        local keep = {}
        for _, c in ipairs(kids) do
            if not isRigChild(c) then
                keep[#keep+1] = c
            end
        end
        return keep
    end

    return kids
end

local function tree(add, root, maxDepth, perLevel, skip)
    local function walk(inst, depth, prefix)
        if depth > maxDepth then return end

        local kids = visibleChildren(inst)
        local groups = groupChildren(kids)
        local shown = math.min(#groups, perLevel)

        for i = 1, shown do
            local group = groups[i]
            local child = group.inst
            local suffix = group.count > 1 and (" x" .. group.count) or ""

            if skip and skip[child] then
                add(prefix .. child.ClassName .. " | " .. child.Name .. suffix .. " (player avatar, skipped)")
            else
                add(prefix .. child.ClassName .. " | " .. child.Name .. suffix
                    .. attrText(child) .. valueText(child) .. promptText(child))

                local nextKids = visibleChildren(child)
                local childCount = #nextKids

                if childCount > 0 then
                    if depth >= maxDepth then
                        add(prefix .. "    ... " .. childCount .. " children (depth limit)")
                    else
                        if childCount > perLevel then
                            add(prefix .. "    ... " .. childCount .. " children, showing " .. perLevel)
                        end
                        walk(child, depth + 1, prefix .. "    ")
                    end
                end
            end
        end

        if #groups > shown then
            add(prefix .. "... " .. (#groups - shown) .. " more entries")
        end
    end

    walk(root, 1, "")
end

local function avatarModels()
    local set = {}

    if localplayer.Character then set[localplayer.Character] = true end

    local ok, list = pcall(function() return players:GetPlayers() end)

    if ok and list then
        for _, p in ipairs(list) do
            if p.Character then set[p.Character] = true end
        end
    end

    return set
end

local function inAvatar(inst, avatars)
    local node = inst

    for _ = 1, 12 do
        if not node then break end
        if avatars[node] then return true end
        node = node.Parent
    end

    return false
end

local function isNoiseValue(inst, avatars)
    if AVATAR_VALUE_NAMES[inst.Name] then return true end
    if inAvatar(inst, avatars) then return true end

    local parent = inst.Parent
    if parent and parent.Name == "Animate" and parent:IsA("LocalScript") then return true end

    return false
end

----------------------------------------------------------------
-- one pass over every container
----------------------------------------------------------------

local function containers()
    local list = {
        workspace,
        replicatedstorage,
        safe(function() return game:GetService("ReplicatedFirst") end, nil),
        safe(function() return game:GetService("Lighting") end, nil),
        safe(function() return game:GetService("SoundService") end, nil),
        safe(function() return game:GetService("StarterGui") end, nil),
        safe(function() return game:GetService("StarterPack") end, nil),
        safe(function() return game:GetService("StarterPlayer") end, nil),
        safe(function() return game:GetService("TextChatService") end, nil),
    }

    local out = {}
    for _, c in ipairs(list) do
        if c then out[#out+1] = c end
    end

    return out
end

local function scan()
    local avatars = avatarModels()

    local result = {
        filtered = 0,
        classes = {},
        attrKeys = {},
        attrValues = {},
        remotes = {},
        prompts = {},
        values = {},
        scripts = {},
        modules = {},
        instances = 0,
        cut = false,
    }

    local seen = {}

    local function collectAttrs(inst)
        local attrs = attrOf(inst)

        for k, v in pairs(attrs) do
            result.attrKeys[k] = (result.attrKeys[k] or 0) + 1

            local set = result.attrValues[k]
            if not set then
                set = {}
                result.attrValues[k] = set
            end

            local sv = fmt(v)
            if set[sv] ~= nil then
                set[sv] = set[sv] + 1
            else
                local distinct = 0
                for _ in pairs(set) do distinct = distinct + 1 end
                if distinct < 40 then set[sv] = 1 end
            end
        end
    end

    -- the containers themselves carry state too (workspace attributes, etc)
    collectAttrs(workspace)
    collectAttrs(replicatedstorage)

    for _, root in ipairs(containers()) do
        local descendants = safe(function() return root:GetDescendants() end, {})

        for _, inst in ipairs(descendants) do
            if not seen[inst] then
                seen[inst] = true
                result.instances = result.instances + 1

                if result.instances > MAX_SCAN then
                    result.cut = true
                    return result
                end

                local class = inst.ClassName
                result.classes[class] = (result.classes[class] or 0) + 1

                collectAttrs(inst)

                if isRemote(inst) then
                    result.remotes[#result.remotes+1] = inst
                elseif isInteractive(inst) then
                    result.prompts[#result.prompts+1] = inst
                end

                if inst:IsA("ValueBase") then
                    if isNoiseValue(inst, avatars) then
                        result.filtered = result.filtered + 1
                    elseif #result.values < 600 then
                        result.values[#result.values+1] = inst
                    end
                end

                if inst:IsA("ModuleScript") then
                    result.modules[#result.modules+1] = inst
                elseif inst:IsA("Script") or inst:IsA("LocalScript") then
                    if #result.scripts < 300 then
                        result.scripts[#result.scripts+1] = inst
                    end
                end
            end
        end
    end

    return result
end

----------------------------------------------------------------
-- sections
----------------------------------------------------------------

local function topList(map, limit)
    local arr = {}
    for k, v in pairs(map) do arr[#arr+1] = { k = k, v = v } end

    table.sort(arr, function(a, b)
        if a.v == b.v then return tostring(a.k) < tostring(b.k) end
        return a.v > b.v
    end)

    local out = {}
    for i = 1, math.min(#arr, limit or 20) do
        out[#out+1] = tostring(arr[i].k) .. " x" .. tostring(arr[i].v)
    end

    return table.concat(out, ", ")
end

local function gameName()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)

    if ok and info and info.Name then return info.Name end
    return "?"
end

local function dumpHeader(add, detail)
    header(add, "dump")

    add("Game: " .. gameName())
    add("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
    add("Player: " .. tostring(localplayer.Name) .. " (" .. tostring(localplayer.UserId) .. ")"
        .. " | DisplayName: " .. tostring(localplayer.DisplayName))
    add("Executor: " .. tostring(safe(function() return identifyexecutor() end, "unknown")))
    add("Detail: " .. tostring(detail) .. " | " .. os.date("%Y-%m-%d %H:%M:%S"))
end

local function dumpServices(add)
    header(add, "services")

    local services = sortChildren(game:GetChildren())
    local empty = 0

    for _, s in ipairs(services) do
        local kids = #s:GetChildren()

        if kids > 0 then
            add(string.format("%s | %s | %d children", s.ClassName, s.Name, kids))
        else
            empty = empty + 1
        end
    end

    add("(" .. empty .. " empty services hidden)")
end

local function dumpWorld(add)
    header(add, "world")

    add(string.format("Gravity: %.2f | StreamingEnabled: %s | FallenPartsDestroyHeight: %.0f",
        tonumber(workspace.Gravity) or 0,
        tostring(safe(function() return workspace.StreamingEnabled end, "?")),
        tonumber(safe(function() return workspace.FallenPartsDestroyHeight end, 0)) or 0))

    add("workspace attrs: " .. (attrText(workspace) ~= "" and attrText(workspace) or "none"))

    local terrain = safe(function() return workspace:FindFirstChildOfClass("Terrain") end, nil)
    if terrain then
        add("Terrain | size " .. tostring(safe(function() return terrain.Size end, "?")))
    end

    add("Camera: " .. tostring(safe(function()
        local cam = workspace.CurrentCamera
        return string.format("%s | fov %.0f | %s", cam.Name, cam.FieldOfView, tostring(cam.CFrame.Position))
    end, "?")))
end

local function dumpPlayers(add)
    local list = safe(function() return players:GetPlayers() end, {})
    header(add, "players (" .. #list .. ")")

    for _, p in ipairs(list) do
        add(string.format("  %s (%s) | display %s%s", tostring(p.Name), tostring(p.UserId),
            tostring(p.DisplayName), p == localplayer and " | YOU" or ""))
    end

    if #list == 0 then add("  none") end
end

local function dumpLighting(add)
    header(add, "lighting")

    local lighting = safe(function() return game:GetService("Lighting") end, nil)
    if not lighting then
        add("no Lighting service")
        return
    end

    for _, key in ipairs({
        "ClockTime", "TimeOfDay", "Brightness", "Ambient", "OutdoorAmbient",
        "ShadowSoftness", "FogEnd", "FogStart", "FogColor", "GlobalShadows",
        "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation",
    }) do
        local value = safe(function() return lighting[key] end, nil)
        if value ~= nil then
            add("  " .. key .. " = " .. fmt(value))
        end
    end
end

local function dumpRemotes(add, result)
    header(add, "remotes (" .. #result.remotes .. ")")

    local list = {}
    for _, r in ipairs(result.remotes) do
        list[#list+1] = safe(function() return r:GetFullName() end, tostring(r))
    end
    table.sort(list)

    for _, path in ipairs(list) do
        add("  " .. path)
    end

    if #list == 0 then add("  none") end
end

local function dumpPrompts(add, result)
    header(add, "prompts (" .. #result.prompts .. ")")

    local list = {}
    for _, p in ipairs(result.prompts) do
        local path = safe(function() return p:GetFullName() end, tostring(p))
        list[#list+1] = p.ClassName .. " | " .. path .. promptText(p) .. attrText(p)
    end
    table.sort(list)

    for i = 1, math.min(#list, 250) do
        add("  " .. list[i])
    end

    if #list > 250 then
        add("  ... " .. (#list - 250) .. " more")
    end
    if #list == 0 then add("  none") end
end

local function dumpValues(add, result)
    header(add, "values (" .. #result.values .. ")")

    local list = {}
    for _, v in ipairs(result.values) do
        local path = safe(function() return v:GetFullName() end, tostring(v))
        list[#list+1] = v.Name .. " = " .. fmt(safe(function() return v.Value end, nil))
            .. "  <- " .. path
    end
    table.sort(list)

    for i = 1, math.min(#list, 300) do
        add("  " .. list[i])
    end

    if #list > 300 then
        add("  ... " .. (#list - 300) .. " more")
    end
end

local function dumpAttributes(add, result)
    header(add, "attributes")

    local keys = {}
    for k in pairs(result.attrKeys) do keys[#keys+1] = k end
    table.sort(keys)

    for _, k in ipairs(keys) do
        local values = result.attrValues[k] or {}
        add(string.format("  %s (%d) | %s", k, result.attrKeys[k], topList(values, 6)))
    end

    if #keys == 0 then add("  none") end
end

local function dumpScripts(add, result)
    header(add, "scripts (" .. #result.scripts .. ")")

    local list = {}
    for _, s in ipairs(result.scripts) do
        list[#list+1] = s.ClassName .. " | " .. safe(function() return s:GetFullName() end, tostring(s))
    end
    table.sort(list)

    for _, line in ipairs(list) do add("  " .. line) end
    if #list == 0 then add("  none") end
end

local function dumpPlayer(add)
    header(add, "player")

    add(string.format("Name: %s | DisplayName: %s | UserId: %s | AccountAge: %s days",
        tostring(localplayer.Name), tostring(localplayer.DisplayName),
        tostring(localplayer.UserId), tostring(localplayer.AccountAge)))

    local membership = safe(function()
        return tostring(localplayer.MembershipType):gsub("Enum.MembershipType.", "")
    end, "?")
    add("Membership: " .. membership)

    local leaderstats = localplayer:FindFirstChild("leaderstats")
    add("")
    add("leaderstats:")

    if leaderstats then
        for _, stat in ipairs(sortChildren(leaderstats:GetChildren())) do
            add("  " .. stat.ClassName .. " | " .. stat.Name .. " = " .. fmt(safe(function() return stat.Value end, nil)))
        end
    else
        add("  none")
    end

    add("")
    add("player attributes:")
    local attrs = attrOf(localplayer)
    local keys = {}
    for k in pairs(attrs) do keys[#keys+1] = k end
    table.sort(keys)

    for _, k in ipairs(keys) do
        add("  " .. k .. " = " .. fmt(attrs[k]))
    end
    if #keys == 0 then add("  none") end

    add("")
    add("PlayerGui:")

    local gui = safe(function() return localplayer:FindFirstChildOfClass("PlayerGui") end, nil)
    if gui then
        for _, screen in ipairs(sortChildren(gui:GetChildren())) do
            add(string.format("  %s | %s | %d children", screen.ClassName, screen.Name, #screen:GetChildren()))
        end
    else
        add("  none")
    end

    add("")
    add("backpack:")
    local backpack = safe(function() return localplayer:FindFirstChildOfClass("Backpack") end, nil)
    if backpack then
        for _, tool in ipairs(sortChildren(backpack:GetChildren())) do
            add("  " .. tool.ClassName .. " | " .. tool.Name)
        end
    else
        add("  none")
    end
end

local function dumpCharacter(add, depth)
    header(add, "character")

    local character = localplayer.Character
    if not character then
        add("no character")
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        add(string.format("Humanoid | health %s/%s | state %s | walkspeed %s | jumppower %s",
            tostring(humanoid.Health), tostring(humanoid.MaxHealth),
            tostring(safe(function() return humanoid:GetState() end, "?")),
            tostring(humanoid.WalkSpeed), tostring(humanoid.JumpPower)))
    end

    add("")

    if #character:GetChildren() == 0 then
        add("character has no children")
    else
        -- two levels is the whole rig, deeper only reaches the Animate script
        -- and its animation strings
        tree(add, character, 2, 300)
    end
end

local function dumpModulePaths(add, result)
    header(add, "module scripts (" .. #result.modules .. ")")

    local list = {}
    for _, m in ipairs(result.modules) do
        list[#list+1] = safe(function() return m:GetFullName() end, tostring(m))
    end
    table.sort(list)

    for i = 1, math.min(#list, 500) do add("  " .. list[i]) end
    if #list > 500 then add("  ... " .. (#list - 500) .. " more") end
    if #list == 0 then add("  none") end
end

-- require every ModuleScript under ReplicatedStorage and print what it exports
local function dumpModuleTables(add, limit)
    header(add, "module tables")

    local moduleList = {}
    for _, d in ipairs(safe(function() return replicatedstorage:GetDescendants() end, {})) do
        if d:IsA("ModuleScript") then moduleList[#moduleList+1] = d end
    end

    table.sort(moduleList, function(a, b)
        return safe(function() return a:GetFullName() end, "") < safe(function() return b:GetFullName() end, "")
    end)

    local done, failed = 0, 0
    local budget = os.clock() + 8

    for i = 1, math.min(#moduleList, limit) do
        local module = moduleList[i]
        local path = safe(function() return module:GetFullName() end, module.Name)

        local ok, value = pcall(require, module)

        if ok then
            done = done + 1
            add(path .. " (" .. typeof(value) .. ")")
            add("    " .. fmt(value))
        else
            failed = failed + 1
            add(path .. " -> require failed: " .. tostring(value))
        end

        if os.clock() > budget then
            add("... stopped after " .. i .. " modules (time budget)")
            break
        end
    end

    add("")
    add(string.format("required %d modules, %d failed, %d available", done, failed, #moduleList))
end

----------------------------------------------------------------
-- entry point
----------------------------------------------------------------

function dumper.run(opts)
    opts = opts or {}

    local depth = tonumber(opts.depth) or dumper.presets.Standard.depth
    local cap = tonumber(opts.cap) or dumper.presets.Standard.cap
    local perLevel = tonumber(opts.perLevel) or dumper.presets.Standard.perLevel

    local add, out, stats = makeSink(cap)

    local result = scan()

    dumpHeader(add, tostring(opts.detail or "Standard"))
    dumpServices(add)
    dumpWorld(add)
    dumpPlayers(add)
    dumpPlayer(add)

    local lighting = safe(function() return game:GetService("Lighting") end, nil)
    if lighting and #lighting:GetChildren() > 0 then
        dumpLighting(add)
    end

    local avatars = avatarModels()

    dumpRemotes(add, result)
    dumpPrompts(add, result)

    header(add, "ReplicatedStorage")
    tree(add, replicatedstorage, depth, perLevel, avatars)

    local first = safe(function() return game:GetService("ReplicatedFirst") end, nil)
    if first and #first:GetChildren() > 0 then
        header(add, "ReplicatedFirst")
        tree(add, first, depth, perLevel, avatars)
    end

    dumpValues(add, result)
    dumpAttributes(add, result)
    dumpModulePaths(add, result)

    if opts.modules then
        dumpModuleTables(add, tonumber(opts.moduleLimit) or 120)
    end

    dumpScripts(add, result)
    dumpCharacter(add, depth)

    header(add, "workspace")
    tree(add, workspace, depth, perLevel, avatars)

    header(add, "summary", true)
    add("instances scanned: " .. result.instances .. (result.cut and " (scan stopped early)" or ""), true)
    add("remotes: " .. #result.remotes .. " | prompts: " .. #result.prompts
        .. " | values: " .. #result.values .. " | modules: " .. #result.modules
        .. " | scripts: " .. #result.scripts, true)
    add("filtered avatar values: " .. result.filtered, true)
    add("classes: " .. topList(result.classes, 25), true)

    local attrKeys = {}
    for k, v in pairs(result.attrKeys) do attrKeys[#attrKeys+1] = { k = k, v = v } end
    table.sort(attrKeys, function(a, b)
        if a.v == b.v then return a.k < b.k end
        return a.v > b.v
    end)

    local keys = {}
    for i = 1, math.min(#attrKeys, 15) do
        keys[#keys+1] = tostring(attrKeys[i].k) .. " x" .. tostring(attrKeys[i].v)
    end

    add("attribute keys: " .. (table.concat(keys, ", ")), true)

    local truncated, lines = stats()
    add("lines: " .. lines .. " / " .. cap .. (truncated and " (TRUNCATED, raise Detail)" or ""), true)

    local text = table.concat(out, "\n")

    local info = {
        lines = lines,
        chars = #text,
        instances = result.instances,
        remotes = #result.remotes,
        prompts = #result.prompts,
        values = #result.values,
        modules = #result.modules,
        scripts = #result.scripts,
        filtered = result.filtered,
        truncated = truncated,
    }

    return text, info
end

return dumper
