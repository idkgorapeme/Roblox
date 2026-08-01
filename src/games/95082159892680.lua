-- +1 speed keyboard escape

return function(section, data)
    print("reached")
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.Farming = false
    env.WinStage = 1

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farming = setdata.farming or false
    setdata.winstage = setdata.winstage or 1
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    print("yeah")

    elements:Label("Currently supports up to 5 stages.", section)

    elements:Textbox("Win Stage", section, tostring(env.WinStage), function(v)
        env.WinStage = tonumber(v)
        getgenv().setconfig("winstage", tonumber(v))
    end)

    local part = Instance.new("Part")
    part.Anchored = true
    part.Size = Vector3.new(10, 1, 546)
    part.Position = Vector3.new(1, 75, 1090)
    part.Parent = workspace

    elements:Toggle("Autofarm", section, env.Farming, function(v)
        env.Farming = v
        getgenv().setconfig("farming", v)

        if not v then return end

        spawn(function()
            while env.Farming do
                local args = {
                    "Walking"
                }
                game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("UpdateSpeed"):FireServer(unpack(args))
                task.wait()
            end
        end)

        while env.Farming do
            pcall(function()
                plr.Character.Humanoid:MoveTo(Vector3.new(2, 9, 282))
                plr.Character.Humanoid.MoveToFinished:Wait()
                if env.WinStage == 1 then
                    plr.Character.Humanoid:MoveTo(workspace.Structure.Stage2.WinBlock1.Position)
                    plr.Character.Humanoid.MoveToFinished:Wait()
                    task.wait(1)
                    return
                end
                plr.Character.Humanoid:MoveTo(Vector3.new(70, 9, 398))
                plr.Character.Humanoid.MoveToFinished:Wait()
                plr.Character.Humanoid:MoveTo(Vector3.new(1, 9, 505))
                plr.Character.Humanoid.MoveToFinished:Wait()
                if env.WinStage == 2 then
                    plr.Character.Humanoid:MoveTo(workspace.Structure.Stage3.WinBlock2.Position)
                    plr.Character.Humanoid.MoveToFinished:Wait()
                    task.wait(1)
                    return
                end

                plr.Character.Humanoid:MoveTo(Vector3.new(19, 9, 541))
                plr.Character.Humanoid.MoveToFinished:Wait()
                plr.Character.Humanoid:MoveTo(Vector3.new(20, 77, 754))
                plr.Character.Humanoid.MoveToFinished:Wait()
                if env.WinStage == 3 then
                    plr.Character.Humanoid:MoveTo(workspace.Structure.Stage4.WinBlock3.Position)
                    plr.Character.Humanoid.MoveToFinished:Wait()
                    task.wait(1)
                    return
                end

                plr.Character.Humanoid:MoveTo(Vector3.new(1, 77, 817))
                plr.Character.Humanoid.MoveToFinished:Wait()
                plr.Character.Humanoid:MoveTo(Vector3.new(1, 77, 1042))
                plr.Character.Humanoid.MoveToFinished:Wait()
                if env.WinStage == 4 then
                    plr.Character.Humanoid:MoveTo(workspace.Structure.Stage5.WinBlock4.Position)
                    plr.Character.Humanoid.MoveToFinished:Wait()
                    task.wait(1)
                    return
                end

                plr.Character.Humanoid:MoveTo(Vector3.new(2, 77, 1363))
                plr.Character.Humanoid.MoveToFinished:Wait()
                if env.WinStage == 5 then
                    plr.Character.Humanoid:MoveTo(workspace.Structure.Stage6.WinBlock5.Position)
                    plr.Character.Humanoid.MoveToFinished:Wait()
                    task.wait(1)
                    return
                end
            end)
        end
    end)

end
