-- +1 health for brainrot

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.Farming = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farming = setdata.farming or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    elements:Toggle("Farm Brainrots", section, env.Farming, function(v)
        env.Farming = v
        getgenv().setconfig("farming", v)
        if not v then return end

        while env.Farming do
            pcall(function()
                local topRot = nil
                local bestAmt = 0
                for i, br in pairs(workspace.SpawnedBrainrots:GetChildren()) do
                    if br:GetAttribute("CashPerSec") >= bestAmt then
                        bestAmt = br:GetAttribute("CashPerSec")
                        topRot = br
                    end
                end

                plr.Character:MoveTo(topRot.PrimaryPart.Position)

                repeat
                    fireproximityprompt(topRot.PickupHitbox.ProximityPrompt)
                    task.wait()
                until not topRot or topRot.Parent ~= workspace.SpawnedBrainrots

                firetouchinterest(plr.Character.Head, workspace.Map.BrainrotCollectionPart, true)
                task.wait()
                firetouchinterest(plr.Character.Head, workspace.Map.BrainrotCollectionPart, false)
            end)

            task.wait(0.5)
        end
    end)
end
