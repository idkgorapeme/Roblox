-- smash crate for brainrots

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    local visualCrates = workspace.Crates
    local serverCrates = workspace.ServerInfo
    local brainrotsFold = workspace.Brainrots

    env.Farming = false
    env.CrateRarity = "common"

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farming = setdata.farming or false
    setdata.CrateRarity = setdata.CrateRarity or "common"
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    elements:Textbox("Crate Rarity", section, env.CrateRarity, function(str)
        env.CrateRarity = str:lower()
        getgenv().setconfig("CrateRarity", str:lower())
    end)

    elements:Toggle("Farm Brainrots", section, env.Farming, function(v)
        env.Farming = v
        getgenv().setconfig("farming", v)
        if not v then return end

        while env.Farming do
            pcall(function()
                for i, v in pairs(visualCrates:GetChildren()) do
                if v:GetAttribute("Rarity"):lower() == env.CrateRarity then

                        plr.Character:MoveTo(v.PrimaryPart.Position + Vector3.new(0, 4, 0))
                        local crateServer = serverCrates["1"].Crates:FindFirstChild(v.Name)
                        if crateServer then
                            for i, v in pairs(plr.Backpack:GetChildren()) do
                                if v:GetAttribute("Cooldown") ~= nil then
                                    plr.Character.Humanoid:EquipTool(v)
                                end
                            end

                            task.wait()
                            local Event = game:GetService("ReplicatedStorage").Remotes.HammerActivated
                            repeat
                                Event:FireServer(
                                    crateServer
                                )
                                task.wait()
                            until not v or v.Parent ~= visualCrates
                            task.wait(0.5)
                            firetouchinterest(plr.Character.Head, workspace.Scripted.EnterSpawnTouch, true)
                            task.wait()
                            firetouchinterest(plr.Character.Head, workspace.Scripted.EnterSpawnTouch, false)
                            task.wait(1)
                            plr.Character.Humanoid:UnequipTools()
                        end
                    end
                end
            end)

            task.wait(0.1)
        end
    end)
end
