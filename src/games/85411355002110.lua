-- +1 Dash for brainrots

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.Farming = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farmrots = setdata.farmrots or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local endPos = Vector3.new(-74, 63, 15784)
    local colPos = Vector3.new(-74, 20, -447)

    elements:Toggle("Farm Brainrots", section, setdata.farmrots, function(v)
        env.Farming = v
        env.setconfig("farmrots", v)
        if not env.Farming then return end
        while env.Farming do
            plr.Character:MoveTo(endPos)
            local lastPlace = workspace.Map.Spawners:WaitForChild("???xLuck"):WaitForChild("???")

            pcall(function()
                for i, v in pairs(lastPlace:GetChildren()) do
                    if not v:IsA("Model") then continue end

                    repeat
                        task.wait()
                    until not plr.GameplayPaused

                    if not v.PrimaryPart then continue end
                    
                    plr.Character:MoveTo(v.PrimaryPart.Position)
                    
                    local prox = v.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
                    repeat
                        fireproximityprompt(prox)
                        task.wait()
                    until not v or v.Parent ~= lastPlace

                    task.wait(0.5)
                    
                    repeat
                        plr.Character:MoveTo(colPos)
                        task.wait()
                    until not plr.Character:FindFirstChildOfClass("Model")
                    
                    break
                end
            end)
            task.wait()
        end

    end)
end
