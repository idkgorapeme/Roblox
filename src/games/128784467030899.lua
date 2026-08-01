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

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

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
                        print("[BrainrotPolice] Auto Merge: " .. #rockets .. " rockets pulled")
                        announced = true
                    end

                    -- 3 studs in front of the player, stacked slightly apart
                    for i, rocket in ipairs(rockets) do
                        if not env.MNMerge then break end

                        pcall(function()
                            -- a nil parented model is not rendered, so show it
                            if rocket.Parent == nil then
                                rocket.Parent = workspace
                            end

                            local offset = CFrame.new(0, 0, -3)
                            rocket:PivotTo(root.CFrame * offset)

                            -- kill any velocity so they do not drift away
                            for _, part in pairs(rocket:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.AssemblyLinearVelocity = Vector3.zero
                                    part.AssemblyAngularVelocity = Vector3.zero
                                end
                            end
                        end)
                    end
                end

                task.wait(0.05)
            end
        end)
    end)
end
