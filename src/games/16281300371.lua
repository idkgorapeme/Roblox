-- Blade Ball
-- Visual only. Reads the ball and draws where it is heading, nothing is
-- fired at the server and no input is automated.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer
    local camera = workspace.CurrentCamera

    env.BBTrajectory = false
    env.BBHighlight = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.trajectory = setdata.trajectory or false
    setdata.highlight = setdata.highlight or false
    setdata.steps = setdata.steps or 30
    setdata.stepsize = setdata.stepsize or 0.05
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local steps = tonumber(setdata.steps) or 30
    local stepSize = tonumber(setdata.stepsize) or 0.05

    ----------------------------------------------------------------
    -- finding the ball
    ----------------------------------------------------------------

    local function ballPart(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst end
        return inst:FindFirstChildWhichIsA("BasePart", true)
    end

    -- the live ball lives in workspace.Balls
    local function getBall()
        local folder = workspace:FindFirstChild("Balls")
        if not folder then return nil end

        local best, bestSpeed = nil, -1

        for _, child in pairs(folder:GetChildren()) do
            local part = ballPart(child)
            if part then
                -- if several exist, the moving one is the live one
                local speed = part.AssemblyLinearVelocity.Magnitude
                if speed > bestSpeed then
                    best, bestSpeed = part, speed
                end
            end
        end

        return best
    end

    -- the ball usually carries its target on an attribute
    local function ballTarget(part)
        if not part then return nil end

        for _, key in ipairs({ "Target", "target", "TargetPlayer", "CurrentTarget" }) do
            local v = part:GetAttribute(key)
            if v ~= nil and v ~= "" then return tostring(v) end
        end

        local model = part.Parent
        if model then
            for _, key in ipairs({ "Target", "target", "TargetPlayer", "CurrentTarget" }) do
                local v = model:GetAttribute(key)
                if v ~= nil and v ~= "" then return tostring(v) end
            end

            local val = model:FindFirstChild("Target")
            if val and (val:IsA("ObjectValue") or val:IsA("StringValue")) then
                local v = val.Value
                if typeof(v) == "Instance" then return v.Name end
                if v and v ~= "" then return tostring(v) end
            end
        end

        return nil
    end

    ----------------------------------------------------------------
    -- drawing
    ----------------------------------------------------------------

    local hasDrawing = (Drawing ~= nil)
    local lines = {}
    local infoText
    local trajConn

    local function newLine()
        local ok, l = pcall(function()
            local d = Drawing.new("Line")
            d.Thickness = 2
            d.Transparency = 1
            d.Color = Color3.fromRGB(0, 255, 120)
            d.Visible = false
            return d
        end)
        return ok and l or nil
    end

    local function clearDrawings()
        for _, l in ipairs(lines) do
            pcall(function() l:Remove() end)
        end
        lines = {}

        if infoText then
            pcall(function() infoText:Remove() end)
            infoText = nil
        end
    end

    -- simple ballistic step, velocity plus gravity per step
    local function predictPath(part)
        local pos = part.Position
        local vel = part.AssemblyLinearVelocity
        local g = Vector3.new(0, -workspace.Gravity, 0)

        local points = { pos }

        for _ = 1, steps do
            vel = vel + g * stepSize
            pos = pos + vel * stepSize
            points[#points + 1] = pos
        end

        return points
    end

    local function updateTrajectory()
        local part = getBall()

        if not part then
            for _, l in ipairs(lines) do l.Visible = false end
            if infoText then infoText.Visible = false end
            return
        end

        local points = predictPath(part)
        local speed = part.AssemblyLinearVelocity.Magnitude

        -- colour by speed, green when slow, red when it is about to hurt
        local hot = math.clamp(speed / 400, 0, 1)
        local col = Color3.fromRGB(
            math.floor(255 * hot),
            math.floor(255 * (1 - hot)),
            60
        )

        for i = 1, #points - 1 do
            local a, aOn = camera:WorldToViewportPoint(points[i])
            local b, bOn = camera:WorldToViewportPoint(points[i + 1])

            local line = lines[i]
            if not line then
                line = newLine()
                lines[i] = line
            end

            if line then
                if aOn and bOn then
                    line.From = Vector2.new(a.X, a.Y)
                    line.To = Vector2.new(b.X, b.Y)
                    line.Color = col
                    line.Visible = true
                else
                    line.Visible = false
                end
            end
        end

        -- readout next to the ball
        if infoText then
            local screen, onScreen = camera:WorldToViewportPoint(part.Position)

            if onScreen then
                local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                local dist = root and (part.Position - root.Position).Magnitude or 0
                local target = ballTarget(part)

                local txt = string.format("speed %d  dist %d", math.floor(speed), math.floor(dist))
                if target then
                    txt = txt .. "  ->  " .. target
                end

                infoText.Text = txt
                infoText.Position = Vector2.new(screen.X + 12, screen.Y - 6)
                infoText.Color = col
                infoText.Visible = true
            else
                infoText.Visible = false
            end
        end
    end

    ----------------------------------------------------------------
    -- toggles
    ----------------------------------------------------------------

    elements:Textbox("Prediction Steps (default 30)", section, tostring(steps), function(v)
        local n = tonumber(v)
        if not n or n < 2 then return end
        steps = math.floor(n)
        env.setconfig("steps", steps)
    end)

    elements:Textbox("Step Size (default 0.05)", section, tostring(stepSize), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        stepSize = n
        env.setconfig("stepsize", n)
    end)

    elements:Toggle("Ball Trajectory", section, setdata.trajectory, function(v)
        env.BBTrajectory = v
        env.setconfig("trajectory", v)

        if trajConn then
            trajConn:Disconnect()
            trajConn = nil
        end

        if not v then
            clearDrawings()
            return
        end

        if not hasDrawing then
            warn("[BrainrotPolice] this executor has no Drawing api, trajectory needs it")
            env.BBTrajectory = false
            return
        end

        if not infoText then
            local ok, t = pcall(function()
                local d = Drawing.new("Text")
                d.Size = 16
                d.Center = false
                d.Outline = true
                d.Color = Color3.fromRGB(0, 255, 120)
                d.Visible = false
                return d
            end)
            infoText = ok and t or nil
        end

        trajConn = runservice.RenderStepped:Connect(function()
            if not env.BBTrajectory then return end
            pcall(updateTrajectory)
        end)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(trajConn)
        end
    end)

    ----------------------------------------------------------------
    -- ball highlight
    ----------------------------------------------------------------

    local ballHighlight

    elements:Toggle("Ball Highlight", section, setdata.highlight, function(v)
        env.BBHighlight = v
        env.setconfig("highlight", v)

        if not v then
            if ballHighlight then
                pcall(function() ballHighlight:Destroy() end)
                ballHighlight = nil
            end
            return
        end

        task.spawn(function()
            while env.BBHighlight do
                pcall(function()
                    local part = getBall()

                    if not part then
                        if ballHighlight then
                            ballHighlight.Enabled = false
                        end
                        return
                    end

                    if not ballHighlight or not ballHighlight.Parent then
                        ballHighlight = Instance.new("Highlight")
                        ballHighlight.Name = "BPBall"
                        ballHighlight.FillColor = Color3.fromRGB(255, 60, 60)
                        ballHighlight.FillTransparency = 0.4
                        ballHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                        ballHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        ballHighlight.Parent = part
                    end

                    ballHighlight.Enabled = true
                    ballHighlight.Adornee = part
                end)

                task.wait(0.2)
            end

            if ballHighlight then
                pcall(function() ballHighlight:Destroy() end)
                ballHighlight = nil
            end
        end)
    end)
end
