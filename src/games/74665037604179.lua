-- Watch Your Money Go Up!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.WMRebirth = false
    env.WMPrestige = false
    env.WMPlaytime = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.rebirth = setdata.rebirth or false
    setdata.prestige = setdata.prestige or false
    setdata.playtime = setdata.playtime or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- lazily resolved, a missing remote can never block the UI
    local function remote(name)
        local folder = replicatedstorage:FindFirstChild("Remotes")
        return folder and folder:FindFirstChild(name) or nil
    end

    -- fires a RemoteEvent or invokes a RemoteFunction, whichever it is
    local function call(name, ...)
        local ev = remote(name)
        if not ev then return false end

        local args = table.pack(...)

        return (pcall(function()
            if ev:IsA("RemoteFunction") then
                ev:InvokeServer(table.unpack(args, 1, args.n))
            else
                ev:FireServer(table.unpack(args, 1, args.n))
            end
        end))
    end

    -- runs a loop in its own thread, never in the toggle callback
    local function loopToggle(label, key, flag, interval, body)
        elements:Toggle(label, section, setdata[key], function(v)
            env[flag] = v
            env.setconfig(key, v)
            if not v then return end

            task.spawn(function()
                while env[flag] do
                    pcall(body)
                    task.wait(interval)
                end
            end)
        end)
    end

    ----------------------------------------------------------------
    -- features
    ----------------------------------------------------------------

    loopToggle("Auto Rebirth", "rebirth", "WMRebirth", 1, function()
        call("RebirthButtonPressed")
        call("RebirthConfirm", true)
    end)

    loopToggle("Auto Prestige", "prestige", "WMPrestige", 2, function()
        call("PrestigeRequest")
    end)

    -- PTR_Claimed_1 .. PTR_Claimed_16 tell us which ones are still open
    loopToggle("Auto Playtime Rewards", "playtime", "WMPlaytime", 10, function()
        for i = 1, 16 do
            if not env.WMPlaytime then break end

            if plr:GetAttribute("PTR_Claimed_" .. i) == false then
                call("PlaytimeRewardClaim", i)
                task.wait(0.2)
            end
        end
    end)
end
