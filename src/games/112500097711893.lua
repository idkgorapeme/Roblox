-- Lick a brainrot

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    local httpservice = game:GetService("HttpService")

    env.Farming = false
    env.Strength = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farming = setdata.farming or false
    setdata.strength = setdata.strength or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    elements:Toggle("Farm Brainrots", section, setdata.farming, function(v)
        env.Farming = v
        getgenv().setconfig("farming", v)
        if not v then return end

        while env.Farming do
            spawn(function()
                local Event = game:GetService("ReplicatedStorage").Remotes.OnCast
                Event:InvokeServer(
                    1
                )
                local Event = game:GetService("ReplicatedStorage").Remotes.StartRun
                Event:InvokeServer()
                local Event = game:GetService("ReplicatedStorage").Remotes.FinishRun
                Event:InvokeServer(
                    true
                )
            end)

            task.wait()
        end
    end)

    elements:Toggle("Farm Strength", section, setdata.strength, function(v)
        env.Strength = v
        getgenv().setconfig("strength", v)
        if not v then return end

        while env.Strength do
            local gym = plr.Backpack:FindFirstChild("Gym")
            if gym then
                pcall(function()
                    plr.Character.Humanoid:EquipTool(gym)
                end)
            end

            local Event = game:GetService("ReplicatedStorage").Remotes.doubleStrength
            Event:FireServer()

            task.wait(1)
        end
    end)
end
