-- +1 Jetpack for Brainrots

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.Farming = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farmrots = setdata.farmrots or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local endPos = Vector3.new(-93, 59, -9943)
    local scndEndPos = Vector3.new(-104, 59, -7863)

    elements:Toggle("Farm Brainrots", section, setdata.farmrots, function(v)
        env.Farming = v
        env.setconfig("farmrots", v)
        if not env.Farming then return end
        while env.Farming do
            plr.Character:MoveTo(endPos)
            task.wait(1)
            for _, fold in pairs(workspace.Brainrots:GetChildren()) do
                for i, br in pairs(fold:GetChildren()) do
                    plr.Character:MoveTo(br.PrimaryPart.Position)
                    local prox = br.AttachmentProximityPrompt:FindFirstChildOfClass("ProximityPrompt")
                    repeat
                        fireproximityprompt(prox)
                        task.wait()
                    until not br or br.Parent ~= fold
                    task.wait()
                    local Event = game:GetService("ReplicatedStorage").Packages._Index["sleitnick_knit@1.7.0"].knit.Services.Game.RF.ClaimRewards
                    Event:InvokeServer()
                    task.wait()
                end
            end

            plr.Character:MoveTo(scndEndPos)
            task.wait(1)
            for _, fold in pairs(workspace.Brainrots:GetChildren()) do
                for i, br in pairs(fold:GetChildren()) do
                    plr.Character:MoveTo(br.PrimaryPart.Position)
                    local prox = br.AttachmentProximityPrompt:FindFirstChildOfClass("ProximityPrompt")
                    repeat
                        fireproximityprompt(prox)
                        task.wait()
                    until not br or br.Parent ~= fold
                    task.wait()
                    local Event = game:GetService("ReplicatedStorage").Packages._Index["sleitnick_knit@1.7.0"].knit.Services.Game.RF.ClaimRewards
                    Event:InvokeServer()
                    task.wait()
                end
            end
        end
    end)
end
