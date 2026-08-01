-- swing obby for brainrots

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.Farming = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farming = setdata.farming or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    elements:Toggle("Autofarm", section, env.Farming, function(v)
        env.Farming = v
        if not v then return end

        local Event = game:GetService("ReplicatedStorage").Packages.Knit.Services.GameplayService.RF.ReturnToPlot
        Event:InvokeServer()
        task.wait()
        while env.Farming do
            for i, v in pairs(workspace.ActiveBrainrots:GetChildren()) do
                if v:GetAttribute("Zone") == 14 or v:GetAttribute("Zone") == 13 then
                    pcall(function()
                        plr.Character:PivotTo(v.CFrame)
                        repeat fireproximityprompt(v.Attachment.ProximityPrompt) task.wait() until not v or v.Parent ~= workspace.ActiveBrainrots
                        task.wait()
                    end)
                end
            end
            task.wait(1)
        end
    end)
end
