-- +1 Wings for brainrot
-- Developed by wirlypirly12

return (function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farmrots = setdata.farmrots or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local player = game:GetService("Players").LocalPlayer

    -- // this is needed to prevent the server not updating the player's position when teleporting, which can cause issues with item spawns
    local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]

    local farming = false
    

    -- // this game uses streaming enabled, so we need to use always rendered world spots.
    local worldPositions = { 
        cosmic = Vector3.new(169, 42, 6124),
        spawn = Vector3.new(22, 71, -133)
    }

    local function getSpawnData(name)
        local item = workspace:FindFirstChild("ItemSpawners")
        if not item then return end

        local data = item:FindFirstChild(name)
        return data
    end

    local function waitForUnpause()
        while player.GameplayPaused do
            task.wait(0.1)
        end
    end

    local function teleportTo(pos)
        pos = typeof(pos) == "Vector3" and CFrame.new(pos) or pos
        player.Character.HumanoidRootPart.CFrame = pos

        local waitTime = ((ping:GetValue() * 4) / 1000)
        task.wait(waitTime)

        waitForUnpause()
    end

    -- // needed to store the brainrots, im too lazy to write a proper system for placing the brainrot (maybe i will if vaehz actually pulls this to main)
    local function putToolsAway()
        for i, part in player.Character:GetChildren() do
            if part:IsA("Tool") then
                part.Parent = player.Backpack
            end
        end
    end

    -- // im 16 years old talking writing brainrot scripts, wtf am i doing????
    local function getBrainrot(rot)
        -- // use wait for child since streaming can cause the mesh to not be there when the brainrot is.
        local brainrotMesh = rot:WaitForChild("Mesh", 3) -- we hate infinite yield!!!
        if not brainrotMesh then return end
		
        local proximityPrompt = brainrotMesh:FindFirstChildWhichIsA("ProximityPrompt")
        if not proximityPrompt then return end

        -- // teleport to the rot
        teleportTo(rot.WorldPivot)
        fireproximityprompt(proximityPrompt)

        task.wait()

        -- // this game requires you to be in spawn so the brainrot becomes a tool inside of ur char
        teleportTo(worldPositions.spawn)

        task.wait()

        putToolsAway()

        return true
    end

    local function doFarm(rotContainer)
        for i, v in rotContainer:GetChildren() do
            if getBrainrot(v) then
                teleportTo(worldPositions.cosmic)
            end
        end
    end

    task.spawn(function()
        while task.wait() do
            if farming == false then continue end
            local cosmics = getSpawnData("Cosmic")
            if cosmics == nil then
                -- // teleport
                teleportTo(worldPositions.cosmic)
				continue
            end
            doFarm(cosmics)
        end
    end)

    elements:Toggle("Farming", section, setdata.farmrots, function(value)
        setconfig("farmrots", value)
        farming = value
    end)

    elements:Button("Teleport to spawn", section, function(value)
        teleportTo(worldPositions.spawn)
    end)

end)