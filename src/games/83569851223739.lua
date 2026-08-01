-- +1 speed evolve

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.FarmWins = false
    env.FarmEvolve = false
    env.AutoSpeed = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farmwin = setdata.farmwin or false
    setdata.farmevolve = setdata.farmevolve or false
    setdata.farmspeed = setdata.farmspeed or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local winsFold = workspace.Wins

    elements:Toggle("Auto speed", section, env.AutoSpeed, function(v)
        env.AutoSpeed = v
        getgenv().setconfig("farmspeed", v)
        if not v then return end

        while env.AutoSpeed do
            game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("RemoteEventService"):WaitForChild("AddSpeedRemoteEvent"):FireServer()

            task.wait()
        end
    end)

    elements:Toggle("Auto win", section, env.FarmWins, function(v)
        env.FarmWins = v
        getgenv().setconfig("farmwin", v)
        if not v then return end

        while env.FarmWins do
            for i, v in pairs(winsFold:GetChildren()) do
                plr.Character:PivotTo(v:GetPivot())
                task.wait(1)
            end
            task.wait(0.25)
        end
    end)

    elements:Toggle("Auto evolve", section, env.FarmEvolve, function(v)
        env.FarmEvolve = v
        getgenv().setconfig("farmevolve", v)
        if not v then return end

        while env.FarmEvolve do
            local args = {
                {
                    Action = "Evolve"
                }
            }
            game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("RemoteEventService"):WaitForChild("EvolutionRemoteEvent"):FireServer(unpack(args))

            task.wait(1)
        end
    end)
end
