-- Merge a Nuke!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MNLock = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.lockbase = setdata.lockbase or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- resolved lazily, never block the UI on a missing remote
    local function nukeRemote(name)
        local folder = replicatedstorage:FindFirstChild("NukeRemotes")
        return folder and folder:FindFirstChild(name) or nil
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
end
