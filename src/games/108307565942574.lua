-- RNG Heroes

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.AutoPrestige = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autoprestige = setdata.autoprestige or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local remotes = replicatedstorage:WaitForChild("Remotes")
    local prestigeRequested = remotes:WaitForChild("PrestigeRequested")

    elements:Toggle("Auto Prestige", section, setdata.autoprestige, function(v)
        env.AutoPrestige = v
        env.setconfig("autoprestige", v)
        if not v then return end

        while env.AutoPrestige do
            pcall(function()
                prestigeRequested:FireServer()
            end)

            task.wait(1)
        end
    end)
end
