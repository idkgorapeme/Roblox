-- Merge a Nuke!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MNLock = false
    env.MNMerge = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.lockbase = setdata.lockbase or false
    setdata.merge = setdata.merge or false
    setdata.basename = setdata.basename or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- resolved lazily, never block the UI on a missing remote
    local function nukeRemote(name)
        local folder = replicatedstorage:FindFirstChild("NukeRemotes")
        return folder and folder:FindFirstChild(name) or nil
    end

    local function nilInstances()
        local fn = getnilinstances or get_nil_instances or getnilobjects
        if not fn then return nil end

        local ok, list = pcall(fn)
        if not ok or type(list) ~= "table" then return nil end
        return list
    end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- work out which base is ours. it changes every rejoin, so this is
    -- resolved live instead of being hardcoded to Base4.
    ----------------------------------------------------------------

    local baseOverride = tostring(setdata.basename or "")

    local function baseBelongsToMe(base)
        for _, key in ipairs({ "Owner", "OwnerUserId", "OwnerName", "Player", "UserId" }) do
            local attr = base:GetAttribute(key)
            if attr ~= nil then
                if attr == plr.Name or attr == plr.UserId
                    or tostring(attr) == tostring(plr.UserId) then
                    return true
                end
            end
        end

        for _, key in ipairs({ "Owner", "OwnerName", "Player", "OwnerValue" }) do
            local val = base:FindFirstChild(key)
            if val and (val:IsA("StringValue") or val:IsA("ObjectValue")
                or val:IsA("IntValue") or val:IsA("NumberValue")) then
                local v = val.Value
                if v == plr or v == plr.Name or v == plr.UserId
                    or tostring(v) == tostring(plr.UserId) then
                    return true
                end
            end
        end

        for _, d in pairs(base:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
                if string.find(d.Text, plr.Name, 1, true)
                    or string.find(d.Text, plr.DisplayName, 1, true) then
                    return true
                end
            end
        end

        return false
    end

    local function getMyBase()
        local bases = workspace:FindFirstChild("Bases")
        if not bases then return nil end

        if baseOverride ~= "" then
            local forced = bases:FindFirstChild(baseOverride)
                or bases:FindFirstChild("Base" .. baseOverride)
            if forced then return forced end
        end

        for _, base in pairs(bases:GetChildren()) do
            if baseBelongsToMe(base) then
                return base
            end
        end

        -- nothing marked, fall back to the base we are standing closest to
        local root = getRoot()
        if not root then return nil end

        local best, bestDist = nil, math.huge
        for _, base in pairs(bases:GetChildren()) do
            local ok, pivot = pcall(function()
                return base:GetPivot().Position
            end)
            if ok and pivot then
                local dist = (pivot - root.Position).Magnitude
                if dist < bestDist then
                    best, bestDist = base, dist
                end
            end
        end

        return best
    end

    elements:Textbox("Base (empty = auto)", section, baseOverride, function(v)
        baseOverride = v and v:gsub("%s", "") or ""
        env.setconfig("basename", baseOverride)
    end)

    elements:Toggle("Auto Lock Base", section, setdata.lockbase, function(v)
        env.MNLock = v
        env.setconfig("lockbase", v)
        if not v then return end

        task.spawn(function()
            while env.MNLock do
                pcall(function()
                    local rf = nukeRemote("RequestLockBase")
                    if rf then rf:FireServer() end
                end)

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto merge: pull every rocket in front of the player, fully local
    ----------------------------------------------------------------

    -- rockets can sit in workspace.Nukes and also be parented to nil,
    -- collect from both so nothing is missed
    local function getRockets()
        local out = {}
        local seen = {}

        local function add(v)
            local ok, isModel = pcall(function()
                return typeof(v) == "Instance" and v:IsA("Model")
            end)
            if ok and isModel and not seen[v] then
                seen[v] = true
                out[#out + 1] = v
            end
        end

        -- the nukes live under our own base, which changes on every rejoin
        local base = getMyBase()
        local baseNukes = base and base:FindFirstChild("Nukes")
        if baseNukes then
            for _, v in pairs(baseNukes:GetChildren()) do
                add(v)
            end
        end

        -- some builds also keep a global folder
        local folder = workspace:FindFirstChild("Nukes")
        if folder then
            for _, v in pairs(folder:GetChildren()) do
                add(v)
            end
        end

        local list = nilInstances()
        if list then
            for _, v in next, list do
                local ok, isNuke = pcall(function()
                    return typeof(v) == "Instance"
                        and v.ClassName == "Model"
                        and v.Name == "Nuke"
                end)
                if ok and isNuke then
                    add(v)
                end
            end
        end

        return out
    end

    -- prints what the script can actually see, so we can tell whether the
    -- base, the folder or the teleport is the thing that is broken
    elements:Button("Debug Nukes", section, function()
        local bases = workspace:FindFirstChild("Bases")
        print("[BrainrotPolice] workspace.Bases exists:", bases ~= nil)

        if bases then
            local names = {}
            for _, b in pairs(bases:GetChildren()) do
                names[#names + 1] = b.Name
            end
            print("[BrainrotPolice] bases:", table.concat(names, ", "))
        end

        local base = getMyBase()
        print("[BrainrotPolice] detected base:", base and base:GetFullName() or "NONE")

        if base then
            local kids = {}
            for _, c in pairs(base:GetChildren()) do
                kids[#kids + 1] = c.ClassName .. ":" .. c.Name
            end
            print("[BrainrotPolice] base children:", table.concat(kids, ", "))
        end

        local rockets = getRockets()
        print("[BrainrotPolice] rockets found:", #rockets)

        for i, r in ipairs(rockets) do
            if i > 3 then break end
            local pp = r.PrimaryPart
            local anyPart = pp or r:FindFirstChildWhichIsA("BasePart", true)
            print(("  rocket %d: %s | parent=%s | primary=%s | anchored=%s"):format(
                i,
                r:GetFullName(),
                tostring(r.Parent and r.Parent.Name),
                tostring(pp and pp.Name),
                tostring(anyPart and anyPart.Anchored)
            ))
        end

        local root = getRoot()
        print("[BrainrotPolice] your root:", root and tostring(root.Position) or "NO CHARACTER")
    end)

    elements:Toggle("Auto Merge", section, setdata.merge, function(v)
        env.MNMerge = v
        env.setconfig("merge", v)
        if not v then return end

        task.spawn(function()
            local announced = false

            while env.MNMerge do
                local root = getRoot()

                if root then
                    local rockets = getRockets()

                    if not announced then
                        print("[BrainrotPolice] Auto Merge: " .. #rockets .. " nukes pulled")
                        if #rockets == 0 then
                            warn("[BrainrotPolice] no nukes found, press Debug Nukes")
                        end
                        announced = true
                    end

                    -- 3 studs in front of the player, all of them, every tick
                    local target = root.CFrame * CFrame.new(0, 0, -3)

                    for _, rocket in ipairs(rockets) do
                        if not env.MNMerge then break end

                        pcall(function()
                            if rocket.Parent == nil then
                                rocket.Parent = workspace
                            end

                            rocket:PivotTo(target)

                            for _, part in pairs(rocket:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.AssemblyLinearVelocity = Vector3.zero
                                    part.AssemblyAngularVelocity = Vector3.zero
                                end
                            end
                        end)
                    end
                end

                task.wait(0.01)
            end
        end)
    end)
end
