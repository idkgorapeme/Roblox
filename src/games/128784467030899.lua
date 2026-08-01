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

    -- the merge remote lives under Packages.Remotes.Networking
    local function netRemote(name)
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local remotes = pkgs and pkgs:FindFirstChild("Remotes")
        local networking = remotes and remotes:FindFirstChild("Networking")
        return networking and networking:FindFirstChild(name) or nil
    end

    local function nilInstances()
        local fn = getnilinstances or get_nil_instances or getnilobjects
        if not fn then return nil end

        local ok, list = pcall(fn)
        if not ok or type(list) ~= "table" then return nil end
        return list
    end

    -- every nuke, not just the first match. the level is not in the name,
    -- a level 1 and a level 16 are both Models called "Nuke", so we collect
    -- all of them and let the server sort out which merges are legal.
    local function getNukes()
        local out = {}
        local list = nilInstances()
        if not list then return out end

        for _, v in next, list do
            local ok, isNuke = pcall(function()
                return typeof(v) == "Instance"
                    and v.ClassName == "Model"
                    and v.Name == "Nuke"
            end)
            if ok and isNuke then
                out[#out + 1] = v
            end
        end

        return out
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
    -- auto merge
    ----------------------------------------------------------------

    elements:Toggle("Auto Merge", section, setdata.merge, function(v)
        env.MNMerge = v
        env.setconfig("merge", v)
        if not v then return end

        if not nilInstances() then
            warn("[BrainrotPolice] this executor has no getnilinstances, Auto Merge cannot work")
            env.MNMerge = false
            return
        end

        task.spawn(function()
            local announced = false

            while env.MNMerge do
                local nukes = getNukes()

                if not announced then
                    print("[BrainrotPolice] Auto Merge: " .. #nukes .. " nukes visible")
                    announced = true
                end

                local pickUp = nukeRemote("PickUp")
                local merge = netRemote("RE/Merge/MergeRequest")
                    or nukeRemote("MergeRequest")

                for _, nuke in ipairs(nukes) do
                    if not env.MNMerge then break end

                    -- pick it up, then request the merge with the same nuke
                    if pickUp then
                        pcall(function()
                            pickUp:FireServer(nuke)
                        end)
                    end

                    if merge then
                        pcall(function()
                            merge:FireServer(nuke)
                        end)
                    end

                    task.wait(0.1)
                end

                task.wait(0.5)
            end
        end)
    end)
end
