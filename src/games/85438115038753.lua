-- My Dropshipping Business (PlaceId 85438115038753)
--
-- From the Deep dump:
--   Player attributes:
--     Money, Sales, SaleBonus, Chapter, MaxActiveOrders, NextVanIn
--     Stock, StockMax, WarehouseStock, WarehouseMax
--     Own_<Product>, Off_<Product>, Avail_<Product>, WH_<Product>
--       Products: StickerPack, KeychainPlush, PhoneGrip, ScentedCandle,
--                 DeskFan, CloudLamp, BobaPlush, Earbuds, GalaxyProjector,
--                 WaffleMaker, SmartWatch, RetroConsole
--     CampaignProduct, CampaignEndsAt, CampaignOrders
--     BulkState (JSON: {"a":{"id":1,"inside":2,"items":[{"p":"WaffleMaker","need":20,"have":2},...]}})
--     UpgradeList (JSON array: [{"id":"Shift2","n":"Shift 2","p":500,"b":true,"a":false,"t":"Gameplay","i":"+1 worker at work"},...])
--     Bought_<UpgradeId> = true
--     Applicants_WarehouseWorker, Applicants_SocialMedia, Applicants_Manager
--       (JSON arrays: [{"id":4112,"name":"Ben","tier":"Pro","cost":5800,"skill":116,"stamina":141},...])
--     Workers_Manager, Workers_SocialMedia, Workers_WarehouseWorker
--     OnShift_Manager, OnShift_SocialMedia, OnShift_WarehouseWorker
--   PlayerGui:
--     LaptopUI, PhoneUI, HUD, ShopUI, SpinUI, StreakUI, PackShop,
--     TraenkeUI, DesignerUI, VipUI
--   Workspace:
--     workspace.Plots.Plot1..Plot6 -> Gate {OwnerUserId, ReservedUserId}, Active
--     workspace.Packages.Package_<Product> {OwnerUserId, ProductId, Labeled, Pickable, OrderId, Reward}
--       -> Box.PickupPrompt
--     workspace.Worker_<id> {OwnerUserId, Department, Mode, Duty, Offer_Skill, Offer_Stamina, Offer_Rank, CampaignState}
--     workspace.NewMap.PostStation, workspace.NewMap.Ineed

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local registry = env.BrainrotPolice

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local httpservice = game:GetService("HttpService")
    local plr = players.LocalPlayer

    env.MDOrder = false
    env.MDAccept = false
    env.MDBuy = false
    env.MDCampaign = false
    env.MDTrain = false
    env.MDPrompts = false
    env.MDClaim = false
    env.MDLog = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.product = setdata.product or "Best Owned"
    setdata.orderQty = tonumber(setdata.orderQty) or 10
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(data))

    local LOG_FILE = "BrainrotPolice/dropshipping_traffic.txt"
    local lastReport = ""

    ----------------------------------------------------------------
    -- product catalog (lowest -> highest tier)
    ----------------------------------------------------------------

    local PRODUCT_ORDER = {
        "StickerPack",
        "KeychainPlush",
        "PhoneGrip",
        "ScentedCandle",
        "DeskFan",
        "CloudLamp",
        "BobaPlush",
        "Earbuds",
        "GalaxyProjector",
        "WaffleMaker",
        "SmartWatch",
        "RetroConsole",
    }

    local PRODUCT_LABELS = {
        StickerPack = "Sticker Pack",
        KeychainPlush = "Keychain Plush",
        PhoneGrip = "Phone Grip",
        ScentedCandle = "Scented Candle",
        DeskFan = "Desk Fan",
        CloudLamp = "Cloud Lamp",
        BobaPlush = "Boba Plush",
        Earbuds = "Earbuds",
        GalaxyProjector = "Galaxy Projector",
        WaffleMaker = "Mini Waffle Maker",
        SmartWatch = "Smart Watch",
        RetroConsole = "Retro Console",
    }

    local PRODUCT_RANK = {}
    for i, id in ipairs(PRODUCT_ORDER) do
        PRODUCT_RANK[id] = i
    end

    ----------------------------------------------------------------
    -- basic helpers
    ----------------------------------------------------------------

    local function attr(name)
        local ok, v = pcall(function() return plr:GetAttribute(name) end)
        if ok then return v end
        return nil
    end

    local function numAttr(name, fallback)
        return tonumber(attr(name)) or fallback or 0
    end

    local function decodeJson(raw)
        if type(raw) ~= "string" or raw == "" then return nil end
        local ok, parsed = pcall(function() return httpservice:JSONDecode(raw) end)
        if ok then return parsed end
        return nil
    end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function posOf(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local ok, cf = pcall(function() return inst:GetPivot() end)
            if ok and cf then return cf.Position end
        end
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function tweenTo(pos)
        local root = getRoot()
        if not root or not pos then return false end

        return pcall(function()
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3.5, 0))
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end

    local function fullName(inst)
        local ok, s = pcall(function() return inst:GetFullName() end)
        return ok and s or tostring(inst)
    end

    local function firePrompt(prompt)
        if not prompt or not prompt.Enabled then return false end

        pcall(function()
            if prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
            if prompt.MaxActivationDistance < 60 then prompt.MaxActivationDistance = 60 end
        end)

        if fireproximityprompt then
            return pcall(fireproximityprompt, prompt)
        end

        local ok = pcall(function()
            prompt:InputHoldBegin()
            task.wait()
            prompt:InputHoldEnd()
        end)
        return ok
    end

    local function fireButton(btn)
        if not btn then return false end
        local fired = false

        if getconnections then
            for _, sigName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" }) do
                local ok, list = pcall(function() return getconnections(btn[sigName]) end)
                if ok and type(list) == "table" then
                    for _, conn in ipairs(list) do
                        if conn.Fire then
                            pcall(function() conn:Fire() end)
                            fired = true
                        elseif conn.Function then
                            pcall(conn.Function)
                            fired = true
                        end
                    end
                end
            end
        end

        if not fired and firesignal then
            for _, sigName in ipairs({ "Activated", "MouseButton1Click" }) do
                local ok = pcall(function() firesignal(btn[sigName]) end)
                if ok then fired = true end
            end
        end

        return fired
    end

    ----------------------------------------------------------------
    -- product state
    ----------------------------------------------------------------

    local function discoverProducts()
        local seen = {}
        local list = {}

        for _, id in ipairs(PRODUCT_ORDER) do
            seen[id] = true
            list[#list+1] = id
        end

        local ok, attrs = pcall(function() return plr:GetAttributes() end)
        if ok and type(attrs) == "table" then
            for k in pairs(attrs) do
                local p = k:match("^Own_(.+)$") or k:match("^Avail_(.+)$") or k:match("^WH_(.+)$")
                if p and not seen[p] then
                    seen[p] = true
                    list[#list+1] = p
                    PRODUCT_RANK[p] = #list
                end
            end
        end

        return list
    end

    local function bestOwnedProduct()
        local best = nil
        local bestRank = -1

        for _, id in ipairs(discoverProducts()) do
            if attr("Own_" .. id) == true then
                local r = PRODUCT_RANK[id] or 0
                if r > bestRank then
                    bestRank = r
                    best = id
                end
            end
        end

        return best or "StickerPack"
    end

    local function targetProduct()
        local sel = setdata.product or "Best Owned"
        if sel == "Best Owned" or sel == "" then
            return bestOwnedProduct()
        end
        return sel
    end

    local function productTotalStock(id)
        return numAttr("Avail_" .. id, 0) + numAttr("WH_" .. id, 0)
    end

    local function hasStockSpace()
        local stock = numAttr("Stock", 0)
        local stockMax = numAttr("StockMax", 0)
        local wh = numAttr("WarehouseStock", 0)
        local whMax = numAttr("WarehouseMax", 0)

        if stockMax > 0 and stock < stockMax then return true end
        if whMax > 0 and wh < whMax then return true end
        if stockMax == 0 and whMax == 0 then return true end
        return false
    end

    ----------------------------------------------------------------
    -- remote discovery + passive learner
    ----------------------------------------------------------------

    local learned = {
        order = nil,    -- { remote = inst, method = "FireServer"|"InvokeServer", args = {...}, productSlot = idx }
        accept = nil,   -- { remote = inst, method = ..., args = {...} }
        upgrade = nil,  -- { remote = inst, method = ..., args = {...}, idSlot = idx }
        campaign = nil, -- { remote = inst, method = ..., args = {...}, productSlot = idx }
        toggle = nil,   -- { remote = inst, method = ..., args = {...}, productSlot = idx }
        train = nil,    -- { remote = inst, method = ..., args = {...}, workerSlot = idx }
        hire = nil,     -- { remote = inst, method = ..., args = {...}, idSlot = idx }
    }

    local function allRemotes()
        local out = {}
        local ok, desc = pcall(function() return replicatedstorage:GetDescendants() end)
        if not ok or not desc then return out end

        for _, d in ipairs(desc) do
            if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") or d:IsA("RemoteFunction") then
                out[#out+1] = d
            end
        end

        table.sort(out, function(a, b) return fullName(a) < fullName(b) end)
        return out
    end

    local function findRemoteByKeywords(keywords, avoid)
        for _, r in ipairs(allRemotes()) do
            local low = (r.Name .. " " .. fullName(r)):lower()
            local bad = false
            if avoid then
                for _, a in ipairs(avoid) do
                    if low:find(a, 1, true) then bad = true break end
                end
            end

            if not bad then
                for _, kw in ipairs(keywords) do
                    if low:find(kw, 1, true) then
                        return r
                    end
                end
            end
        end
        return nil
    end

    local function callRemote(r, ...)
        if not r then return false end
        local args = { ... }
        if r:IsA("RemoteFunction") then
            local ok, res = pcall(function() return r:InvokeServer(table.unpack(args)) end)
            return ok, res
        elseif r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
            local ok = pcall(function() r:FireServer(table.unpack(args)) end)
            return ok
        end
        return false
    end

    local function replayLearned(entry, overrideSlot, overrideVal)
        if not entry or not entry.remote then return false end
        local args = {}
        local n = entry.n or #entry.args
        for i = 1, n do
            args[i] = entry.args[i]
        end
        if overrideSlot and overrideVal ~= nil then
            args[overrideSlot] = overrideVal
        end
        return callRemote(entry.remote, table.unpack(args, 1, n))
    end

    local function classifyOutgoing(remote, method, ...)
        local args = table.pack(...)
        local rname = (remote.Name .. " " .. fullName(remote)):lower()
        local firstStr = type(args[1]) == "string" and args[1]:lower() or ""
        local combined = rname .. " " .. firstStr

        local productSlot = nil
        for i = 1, args.n do
            if type(args[i]) == "string" and PRODUCT_RANK[args[i]] then
                productSlot = i
                break
            end
        end

        -- check upgrade IDs from UpgradeList
        local upgrades = decodeJson(attr("UpgradeList"))
        local upgradeSlot = nil
        if type(upgrades) == "table" then
            local upgSet = {}
            for _, u in ipairs(upgrades) do
                if type(u) == "table" and u.id then upgSet[tostring(u.id)] = true end
            end
            for i = 1, args.n do
                if type(args[i]) == "string" and upgSet[args[i]] then
                    upgradeSlot = i
                    break
                end
            end
        end

        if upgradeSlot or combined:find("upgrade", 1, true) or combined:find("tycoon", 1, true) then
            learned.upgrade = {
                remote = remote,
                method = method,
                args = args,
                n = args.n,
                idSlot = upgradeSlot or (firstStr ~= "" and 2 or 1),
            }
            return
        end

        if productSlot then
            if combined:find("campaign", 1, true) or combined:find("boost", 1, true) or combined:find("social", 1, true) or combined:find("ad", 1, true) then
                learned.campaign = { remote = remote, method = method, args = args, n = args.n, productSlot = productSlot }
                return
            elseif combined:find("off", 1, true) or combined:find("toggle", 1, true) or combined:find("enable", 1, true) or combined:find("disable", 1, true) then
                learned.toggle = { remote = remote, method = method, args = args, n = args.n, productSlot = productSlot }
                return
            else
                learned.order = { remote = remote, method = method, args = args, n = args.n, productSlot = productSlot }
                return
            end
        end

        if combined:find("accept", 1, true) or combined:find("confirm", 1, true) or combined:find("fulfill", 1, true) or combined:find("annehmen", 1, true) then
            learned.accept = { remote = remote, method = method, args = args, n = args.n }
            return
        end

        if combined:find("train", 1, true) or combined:find("skill", 1, true) or combined:find("stamina", 1, true) or combined:find("rank", 1, true) then
            learned.train = { remote = remote, method = method, args = args, n = args.n }
            return
        end

        if combined:find("hire", 1, true) or combined:find("applicant", 1, true) then
            learned.hire = { remote = remote, method = method, args = args, n = args.n }
            return
        end
    end

    ----------------------------------------------------------------
    -- UI scanning helpers (LaptopUI / PhoneUI / HUD / SpinUI / StreakUI)
    ----------------------------------------------------------------

    local SAFE_SCREENS = { "LaptopUI", "PhoneUI", "HUD" }
    local BLOCKED_WORDS = {
        "robux", "r$", "\238\128\130", "pass", "vip", "delete", "reset",
        "fire", "dismiss", "cancel", "decline", "close", "exit", "back",
        "leave", "abbrechen", "schliessen", "entlassen",
    }

    local function buttonLabelText(btn)
        local parts = {}
        local name = tostring(btn.Name or "")
        if name ~= "" then parts[#parts+1] = name end

        if btn:IsA("TextButton") and tostring(btn.Text or "") ~= "" then
            parts[#parts+1] = tostring(btn.Text)
        end

        local ok, desc = pcall(function() return btn:GetDescendants() end)
        if ok and desc then
            for _, d in ipairs(desc) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local t = tostring(d.Text or "")
                    if t ~= "" then parts[#parts+1] = t end
                end
            end
        end

        return table.concat(parts, " | ")
    end

    local function isBlockedText(text)
        local low = tostring(text or ""):lower()
        for _, w in ipairs(BLOCKED_WORDS) do
            if low:find(w, 1, true) then return true end
        end
        return false
    end

    local function containerMatchesProduct(container, productId)
        if not container or not productId then return false end
        local label = (PRODUCT_LABELS[productId] or productId):lower()
        local idLow = productId:lower()

        if container.Name:lower():find(idLow, 1, true) then return true end

        local okAttr, attrs = pcall(function() return container:GetAttributes() end)
        if okAttr and type(attrs) == "table" then
            for _, v in pairs(attrs) do
                if tostring(v):lower() == idLow then return true end
            end
        end

        local okDesc, desc = pcall(function() return container:GetDescendants() end)
        if okDesc and desc then
            for _, d in ipairs(desc) do
                if d.Name:lower():find(idLow, 1, true) then return true end
                if (d:IsA("TextLabel") or d:IsA("TextButton")) then
                    local t = tostring(d.Text or ""):lower()
                    if t:find(idLow, 1, true) or t:find(label, 1, true) then
                        return true
                    end
                end
            end
        end

        return false
    end

    local function findProductCardButtons(productId)
        local out = {}
        local pgui = plr:FindFirstChildOfClass("PlayerGui")
        if not pgui then return out end

        for _, screenName in ipairs(SAFE_SCREENS) do
            local screen = pgui:FindFirstChild(screenName)
            if screen then
                local ok, desc = pcall(function() return screen:GetDescendants() end)
                if ok and desc then
                    for _, inst in ipairs(desc) do
                        if (inst:IsA("Frame") or inst:IsA("ImageLabel") or inst:IsA("CanvasGroup") or inst:IsA("ScrollingFrame"))
                            and containerMatchesProduct(inst, productId) then
                            -- only consider compact card containers, not the whole screen
                            local childrenBtns = {}
                            for _, sub in ipairs(inst:GetDescendants()) do
                                if sub:IsA("TextButton") or sub:IsA("ImageButton") then
                                    childrenBtns[#childrenBtns+1] = sub
                                end
                            end
                            if #childrenBtns > 0 and #childrenBtns <= 12 then
                                for _, btn in ipairs(childrenBtns) do
                                    local txt = buttonLabelText(btn)
                                    if not isBlockedText(txt) then
                                        out[#out+1] = {
                                            button = btn,
                                            text = txt,
                                            card = inst,
                                            path = fullName(btn),
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return out
    end

    ----------------------------------------------------------------
    -- 1. Auto Order Best Stock
    ----------------------------------------------------------------

    local function orderStockOnce()
        local prod = targetProduct()
        local qty = tonumber(setdata.orderQty) or 10

        if not hasStockSpace() then
            return false, "stock is full (" .. tostring(attr("Stock")) .. "/" .. tostring(attr("StockMax")) .. ")"
        end

        local did = false

        -- 1) Replay learned remote if captured
        if learned.order then
            local ok = replayLearned(learned.order, learned.order.productSlot, prod)
            if ok then did = true end
        end

        -- 2) Try matching stock/order remotes in ReplicatedStorage
        local orderRemote = findRemoteByKeywords(
            { "orderstock", "buystock", "restock", "orderproduct", "buyproduct", "stockorder", "purchaseproduct", "supplier", "warehouseorder" },
            { "cancel", "robux" }
        ) or findRemoteByKeywords({ "stock", "order", "supply" }, { "accept", "robux", "cancel", "sort" })

        if orderRemote then
            callRemote(orderRemote, prod, qty)
            callRemote(orderRemote, prod)
            callRemote(orderRemote, "Order", prod, qty)
            callRemote(orderRemote, "Buy", prod, qty)
            did = true
        end

        -- 3) Click order/buy buttons inside the product card in LaptopUI / PhoneUI
        local cardButtons = findProductCardButtons(prod)
        local bestBtn = nil
        local bestScore = -1

        for _, entry in ipairs(cardButtons) do
            local low = entry.text:lower()
            if not low:find("off", 1, true) and not low:find("disable", 1, true) then
                local score = 0
                if low:find("order", 1, true) or low:find("buy", 1, true) or low:find("restock", 1, true) or low:find("kaufen", 1, true) or low:find("bestellen", 1, true) then
                    score = score + 20
                end
                local num = tonumber(low:match("%+(%d+)")) or tonumber(low:match("x(%d+)")) or tonumber(low:match("(%d+)"))
                if num and num <= 500 then
                    score = score + num
                end
                if low:find("max", 1, true) then
                    score = score + 200
                end
                if score > bestScore then
                    bestScore = score
                    bestBtn = entry.button
                end
            end
        end

        if bestBtn and fireButton(bestBtn) then
            did = true
        end

        return did, prod
    end

    ----------------------------------------------------------------
    -- 2. Auto Accept Orders
    ----------------------------------------------------------------

    local ACCEPT_WORDS = {
        "accept", "confirm", "process", "fulfill", "annehmen",
        "take order", "takeorder", "acceptall", "accept all",
        "print label", "ship order", "deliver",
    }

    local function acceptOrdersOnce()
        local count = 0

        -- 1) Replay learned accept remote if captured
        if learned.accept then
            if replayLearned(learned.accept) then
                count = count + 1
            end
        end

        -- 2) Try matching order accept remotes in ReplicatedStorage
        for _, r in ipairs(allRemotes()) do
            local low = (r.Name .. " " .. fullName(r)):lower()
            if (low:find("acceptorder", 1, true) or low:find("orderaccept", 1, true)
                or low:find("acceptall", 1, true) or low:find("takeorder", 1, true)
                or low:find("confirmorder", 1, true) or low:find("processorder", 1, true)
                or low:find("bulkaccept", 1, true))
                and not low:find("robux", 1, true) then
                callRemote(r)
                callRemote(r, true)
                callRemote(r, "AcceptAll")
                count = count + 1
            end
        end

        -- 3) Click Accept / Confirm buttons in LaptopUI / PhoneUI
        local pgui = plr:FindFirstChildOfClass("PlayerGui")
        if pgui then
            for _, screenName in ipairs(SAFE_SCREENS) do
                local screen = pgui:FindFirstChild(screenName)
                if screen then
                    local ok, desc = pcall(function() return screen:GetDescendants() end)
                    if ok and desc then
                        for _, inst in ipairs(desc) do
                            if (inst:IsA("TextButton") or inst:IsA("ImageButton")) and inst.Visible then
                                local txt = buttonLabelText(inst)
                                local low = txt:lower()
                                local ppath = fullName(inst):lower()

                                if not isBlockedText(txt) and not isBlockedText(ppath) then
                                    local matched = false
                                    for _, kw in ipairs(ACCEPT_WORDS) do
                                        if low:find(kw, 1, true) then
                                            matched = true
                                            break
                                        end
                                    end

                                    if matched and fireButton(inst) then
                                        count = count + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return count
    end

    ----------------------------------------------------------------
    -- 3. Only Keep Best Product Active (disable lower products)
    ----------------------------------------------------------------

    local function keepOnlyBestProductActive()
        local best = targetProduct()
        local toggled = 0

        local toggleRemote = (learned.toggle and learned.toggle.remote)
            or findRemoteByKeywords({ "toggleproduct", "productoff", "setproduct", "productactive", "productstate" }, { "robux" })

        for _, id in ipairs(discoverProducts()) do
            if attr("Own_" .. id) == true then
                local isOff = attr("Off_" .. id) == true
                local shouldBeOff = (id ~= best)

                if isOff ~= shouldBeOff then
                    if learned.toggle then
                        replayLearned(learned.toggle, learned.toggle.productSlot, id)
                        toggled = toggled + 1
                    elseif toggleRemote then
                        callRemote(toggleRemote, id, shouldBeOff)
                        callRemote(toggleRemote, id)
                        toggled = toggled + 1
                    end

                    -- Also check toggle buttons inside product card
                    for _, entry in ipairs(findProductCardButtons(id)) do
                        local low = entry.text:lower()
                        if low:find("off", 1, true) or low:find("on", 1, true)
                            or low:find("active", 1, true) or low:find("toggle", 1, true)
                            or low:find("enable", 1, true) or low:find("disable", 1, true) then
                            if fireButton(entry.button) then
                                toggled = toggled + 1
                                break
                            end
                        end
                    end
                end
            end
        end

        return toggled, best
    end

    ----------------------------------------------------------------
    -- 4. Auto Campaign (Boost Best Product)
    ----------------------------------------------------------------

    local function startBestCampaignOnce()
        local best = targetProduct()
        local did = false

        if learned.campaign then
            if replayLearned(learned.campaign, learned.campaign.productSlot, best) then
                did = true
            end
        end

        local campRemote = findRemoteByKeywords(
            { "campaign", "boostproduct", "startcampaign", "socialmedia", "launchad", "marketing" },
            { "robux", "skip" }
        )

        if campRemote then
            callRemote(campRemote, best)
            callRemote(campRemote, "Start", best)
            did = true
        end

        -- Check campaign buttons in LaptopUI / PhoneUI
        local pgui = plr:FindFirstChildOfClass("PlayerGui")
        if pgui then
            for _, screenName in ipairs(SAFE_SCREENS) do
                local screen = pgui:FindFirstChild(screenName)
                if screen then
                    local ok, desc = pcall(function() return screen:GetDescendants() end)
                    if ok and desc then
                        for _, inst in ipairs(desc) do
                            if (inst:IsA("TextButton") or inst:IsA("ImageButton")) and inst.Visible then
                                local txt = buttonLabelText(inst)
                                local low = txt:lower()
                                local pathLow = fullName(inst):lower()
                                if not isBlockedText(txt) and not isBlockedText(pathLow) then
                                    if (low:find("campaign", 1, true) or low:find("start boost", 1, true)
                                        or low:find("promote", 1, true) or low:find("launch", 1, true)
                                        or (pathLow:find("campaign", 1, true) and low:find("start", 1, true))) then
                                        if fireButton(inst) then
                                            did = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return did, best
    end

    ----------------------------------------------------------------
    -- 5. Auto Buy Upgrades (from UpgradeList JSON attribute)
    ----------------------------------------------------------------

    local function availableUpgrades()
        local raw = decodeJson(attr("UpgradeList"))
        local out = {}
        if type(raw) ~= "table" then return out end

        for _, item in ipairs(raw) do
            if type(item) == "table" and item.id then
                local bought = item.b == true or attr("Bought_" .. tostring(item.id)) == true
                local price = tonumber(item.p) or 0
                out[#out+1] = {
                    id = tostring(item.id),
                    name = tostring(item.n or item.id),
                    price = price,
                    bought = bought,
                    avail = item.a == true,
                    tab = tostring(item.t or ""),
                    info = tostring(item.i or ""),
                }
            end
        end

        table.sort(out, function(a, b)
            if a.bought ~= b.bought then return not a.bought end
            if a.price == b.price then return a.id < b.id end
            return a.price < b.price
        end)

        return out
    end

    local function buyUpgradeById(upg)
        if not upg then return false end
        local did = false

        if learned.upgrade then
            if replayLearned(learned.upgrade, learned.upgrade.idSlot, upg.id) then
                did = true
            end
        end

        local upgRemote = findRemoteByKeywords(
            { "buyupgrade", "purchaseupgrade", "upgrade", "tycoonbuy", "buybutton", "build" },
            { "robux", "worker" }
        )

        if upgRemote then
            callRemote(upgRemote, upg.id)
            callRemote(upgRemote, "Buy", upg.id)
            did = true
        end

        -- Also check LaptopUI / PhoneUI button matching upgrade id or name
        local pgui = plr:FindFirstChildOfClass("PlayerGui")
        if pgui then
            local idLow = upg.id:lower()
            local nameLow = upg.name:lower()

            for _, screenName in ipairs(SAFE_SCREENS) do
                local screen = pgui:FindFirstChild(screenName)
                if screen then
                    local ok, desc = pcall(function() return screen:GetDescendants() end)
                    if ok and desc then
                        for _, inst in ipairs(desc) do
                            if inst:IsA("TextButton") or inst:IsA("ImageButton") then
                                local txt = buttonLabelText(inst)
                                local pathLow = fullName(inst):lower()
                                if not isBlockedText(txt) and not isBlockedText(pathLow) then
                                    if pathLow:find(idLow, 1, true)
                                        or txt:lower():find(idLow, 1, true)
                                        or (nameLow ~= "" and txt:lower():find(nameLow, 1, true)) then
                                        if fireButton(inst) then
                                            did = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return did
    end

    local function buyCheapestUpgradeOnce()
        local money = numAttr("Money", 0)
        for _, upg in ipairs(availableUpgrades()) do
            if not upg.bought and upg.price > 0 and money >= upg.price then
                local ok = buyUpgradeById(upg)
                return ok, upg
            end
        end
        return false, nil
    end

    ----------------------------------------------------------------
    -- 6. Workers & Applicants (Train / Hire)
    ----------------------------------------------------------------

    local function parseOffer(raw)
        if type(raw) ~= "string" or raw == "" or raw:sub(1, 1) == "!" then return nil end
        local cost, stat, lvl = raw:match("^(%d+)|(%d+)|(%d+)")
        if not cost then
            cost = raw:match("^(%d+)")
        end
        if not cost then return nil end
        return {
            cost = tonumber(cost) or 0,
            stat = tonumber(stat) or 0,
            level = tonumber(lvl) or 0,
        }
    end

    local function myWorkers()
        local out = {}
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model") and child.Name:match("^Worker_") then
                local owner = child:GetAttribute("OwnerUserId")
                if owner == plr.UserId then
                    local wid = tonumber(child.Name:match("^Worker_(%d+)")) or child.Name
                    out[#out+1] = {
                        model = child,
                        name = child.Name,
                        id = wid,
                        dept = tostring(child:GetAttribute("Department") or ""),
                        mode = tostring(child:GetAttribute("Mode") or ""),
                        duty = tostring(child:GetAttribute("Duty") or ""),
                        onShift = child:GetAttribute("OnShift") == true,
                        skill = parseOffer(child:GetAttribute("Offer_Skill")),
                        stamina = parseOffer(child:GetAttribute("Offer_Stamina")),
                        rankRaw = tostring(child:GetAttribute("Offer_Rank") or ""),
                    }
                end
            end
        end
        table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
        return out
    end

    local function trainCheapestWorkerOnce()
        local money = numAttr("Money", 0)
        local best = nil

        for _, w in ipairs(myWorkers()) do
            for _, statName in ipairs({ "Skill", "Stamina" }) do
                local offer = w[statName:lower()]
                if offer and offer.cost > 0 and offer.cost <= money then
                    if not best or offer.cost < best.cost then
                        best = {
                            worker = w,
                            stat = statName,
                            cost = offer.cost,
                        }
                    end
                end
            end
        end

        if not best then return false, nil end

        local did = false
        if learned.train then
            replayLearned(learned.train, 1, best.worker.id)
            did = true
        end

        local trainRemote = findRemoteByKeywords(
            { "trainworker", "upgradeworker", "workerstat", "workerupgrade", "train", "levelworker" },
            { "robux" }
        )
        if trainRemote then
            callRemote(trainRemote, best.worker.id, best.stat)
            callRemote(trainRemote, best.worker.name, best.stat)
            callRemote(trainRemote, best.worker.model, best.stat)
            did = true
        end

        return did, best
    end

    local function allApplicants()
        local out = {}
        local groups = {
            { key = "Applicants_WarehouseWorker", role = "WarehouseWorker" },
            { key = "Applicants_SocialMedia", role = "SocialMedia" },
            { key = "Applicants_Manager", role = "Manager" },
        }

        for _, g in ipairs(groups) do
            local arr = decodeJson(attr(g.key))
            if type(arr) == "table" then
                for _, a in ipairs(arr) do
                    if type(a) == "table" and a.id then
                        local score = (tonumber(a.skill) or 0) + (tonumber(a.stamina) or 0)
                        out[#out+1] = {
                            id = a.id,
                            name = tostring(a.name or a.id),
                            tier = tostring(a.tier or ""),
                            role = g.role,
                            cost = tonumber(a.cost) or 0,
                            skill = tonumber(a.skill) or 0,
                            stamina = tonumber(a.stamina) or 0,
                            score = score,
                        }
                    end
                end
            end
        end

        table.sort(out, function(a, b)
            if a.score == b.score then return a.cost < b.cost end
            return a.score > b.score
        end)

        return out
    end

    local function hireBestApplicantOnce()
        local money = numAttr("Money", 0)
        for _, app in ipairs(allApplicants()) do
            if app.cost <= money then
                local did = false
                if learned.hire then
                    replayLearned(learned.hire, 1, app.id)
                    did = true
                end

                local hireRemote = findRemoteByKeywords(
                    { "hire", "applicant", "recruit", "employ" },
                    { "robux", "fire" }
                )
                if hireRemote then
                    callRemote(hireRemote, app.role, app.id)
                    callRemote(hireRemote, app.id, app.role)
                    callRemote(hireRemote, app.id)
                    did = true
                end

                return did, app
            end
        end
        return false, nil
    end

    ----------------------------------------------------------------
    -- 7. Own Plot & Package Prompts
    ----------------------------------------------------------------

    local function myPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end

        for _, p in ipairs(plots:GetChildren()) do
            local gate = p:FindFirstChild("Gate")
            if gate and (gate:GetAttribute("OwnerUserId") == plr.UserId or gate:GetAttribute("ReservedUserId") == plr.UserId) then
                return p
            end
            if p:GetAttribute("OwnerUserId") == plr.UserId then
                return p
            end
        end

        return nil
    end

    local function myPackages()
        local folder = workspace:FindFirstChild("Packages")
        local out = {}
        if not folder then return out end

        for _, pkg in ipairs(folder:GetChildren()) do
            if pkg:GetAttribute("OwnerUserId") == plr.UserId then
                out[#out+1] = pkg
            end
        end

        return out
    end

    local function fireOwnPlotAndPackagePrompts()
        local count = 0

        for _, pkg in ipairs(myPackages()) do
            if pkg:GetAttribute("Pickable") == true then
                local prompt = pkg:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled then
                    if firePrompt(prompt) then
                        count = count + 1
                    end
                end
            end
        end

        local plot = myPlot()
        local active = plot and plot:FindFirstChild("Active")
        if active then
            local ok, desc = pcall(function() return active:GetDescendants() end)
            if ok and desc then
                for _, d in ipairs(desc) do
                    if d:IsA("ProximityPrompt") and d.Enabled then
                        local act = tostring(d.ActionText or ""):lower()
                        local obj = tostring(d.ObjectText or ""):lower()
                        if not isBlockedText(act) and not isBlockedText(obj) then
                            if firePrompt(d) then
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end

        return count
    end

    ----------------------------------------------------------------
    -- 8. Spin / Streak Rewards
    ----------------------------------------------------------------

    local function claimRewardsOnce()
        local count = 0
        local pgui = plr:FindFirstChildOfClass("PlayerGui")
        if pgui then
            for _, screenName in ipairs({ "SpinUI", "StreakUI" }) do
                local screen = pgui:FindFirstChild(screenName)
                if screen then
                    local ok, desc = pcall(function() return screen:GetDescendants() end)
                    if ok and desc then
                        for _, inst in ipairs(desc) do
                            if (inst:IsA("TextButton") or inst:IsA("ImageButton")) and inst.Visible then
                                local txt = buttonLabelText(inst)
                                local low = txt:lower()
                                if not isBlockedText(txt) then
                                    if low:find("claim", 1, true) or low:find("spin", 1, true)
                                        or low:find("free", 1, true) or low:find("collect", 1, true)
                                        or low:find("reward", 1, true) then
                                        if fireButton(inst) then
                                            count = count + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return count
    end

    ----------------------------------------------------------------
    -- background loops
    ----------------------------------------------------------------

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDOrder then
                pcall(orderStockOnce)
                task.wait(1.5)
            else
                task.wait(0.4)
            end
        end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDAccept then
                pcall(acceptOrdersOnce)
                task.wait(1.0)
            else
                task.wait(0.4)
            end
        end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDBuy then
                pcall(buyCheapestUpgradeOnce)
                task.wait(2.0)
            else
                task.wait(0.5)
            end
        end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDCampaign then
                pcall(startBestCampaignOnce)
                task.wait(5.0)
            else
                task.wait(0.5)
            end
        end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDTrain then
                pcall(trainCheapestWorkerOnce)
                task.wait(2.0)
            else
                task.wait(0.5)
            end
        end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDPrompts then
                pcall(fireOwnPlotAndPackagePrompts)
                task.wait(0.6)
            else
                task.wait(0.4)
            end
        end
    end)

    task.spawn(function()
        while env.BrainrotPolice == registry do
            if env.MDClaim then
                pcall(claimRewardsOnce)
                task.wait(10.0)
            else
                task.wait(0.5)
            end
        end
    end)

    ----------------------------------------------------------------
    -- remote traffic logger & learner hook
    ----------------------------------------------------------------

    local logBuf = {}
    local LOG_MAX = 800

    local function fmtArg(v, depth)
        depth = depth or 0
        local t = typeof(v)
        if t == "string" then
            if #v > 90 then return string.format("%q..", v:sub(1, 90)) end
            return string.format("%q", v)
        elseif t == "Instance" then
            return "<" .. v.ClassName .. " " .. fullName(v) .. ">"
        elseif t == "table" then
            if depth >= 2 then return "{...}" end
            local p = {}
            local n = 0
            for k, val in pairs(v) do
                n = n + 1
                if n > 10 then p[#p+1] = "..." break end
                p[#p+1] = tostring(k) .. "=" .. fmtArg(val, depth + 1)
            end
            return "{" .. table.concat(p, ", ") .. "}"
        end
        return tostring(v)
    end

    local function recordTraffic(dir, remote, method, ...)
        local args = table.pack(...)
        local parts = {}
        for i = 1, math.min(args.n, 8) do
            local ok, s = pcall(fmtArg, args[i], 0)
            parts[#parts+1] = ok and s or "<err>"
        end

        local line = string.format("%s %s %s.%s(%s)",
            os.date("%H:%M:%S"), dir, fullName(remote), tostring(method), table.concat(parts, ", "))

        logBuf[#logBuf+1] = line
        if #logBuf > LOG_MAX then table.remove(logBuf, 1) end

        if env.MDLog then
            print("[BrainrotPolice] " .. line)
        end
    end

    local hookInstalled = false

    local function installHook()
        if hookInstalled then return true end
        if not hookmetamethod or not getnamecallmethod then return false end

        local wrap = newcclosure or function(f) return f end

        local ok = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer")
                    and typeof(self) == "Instance"
                    and (self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent") or self:IsA("RemoteFunction")) then
                    pcall(classifyOutgoing, self, method, ...)
                    if env.MDLog then
                        pcall(recordTraffic, "OUT", self, method, ...)
                    end
                end
                return original(self, ...)
            end))
        end)

        hookInstalled = ok
        return ok
    end

    installHook()

    ----------------------------------------------------------------
    -- reports
    ----------------------------------------------------------------

    local function statusReport()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        local plot = myPlot()
        local best = bestOwnedProduct()
        local pkgs = myPackages()
        local pickableCount = 0
        local labeledCount = 0
        for _, p in ipairs(pkgs) do
            if p:GetAttribute("Pickable") == true then pickableCount = pickableCount + 1 end
            if p:GetAttribute("Labeled") == true then labeledCount = labeledCount + 1 end
        end

        add("=== My Dropshipping Business ===")
        add(string.format("Money: $%s | Sales: %s | Bonus: %s | Chapter: %s",
            tostring(attr("Money")), tostring(attr("Sales")),
            tostring(attr("SaleBonus")), tostring(attr("Chapter"))))
        add(string.format("Stock: %s / %s | Warehouse: %s / %s | Next Van: %ss",
            tostring(attr("Stock")), tostring(attr("StockMax")),
            tostring(attr("WarehouseStock")), tostring(attr("WarehouseMax")),
            tostring(attr("NextVanIn"))))
        add(string.format("Best Owned Product: %s (%s) | Selected: %s",
            tostring(best), tostring(PRODUCT_LABELS[best] or best), tostring(targetProduct())))
        add(string.format("Campaign Product: %s | Campaign Orders: %s",
            tostring(attr("CampaignProduct")), tostring(attr("CampaignOrders"))))
        add(string.format("My Plot: %s | My Packages in Workspace: %d (%d pickable, %d labeled)",
            plot and plot.Name or "none", #pkgs, pickableCount, labeledCount))

        add("")
        add("--- Owned Products ---")
        for _, id in ipairs(discoverProducts()) do
            if attr("Own_" .. id) == true then
                add(string.format("  %-16s | Avail %-4s | WH %-4s | %s",
                    id, tostring(numAttr("Avail_" .. id, 0)),
                    tostring(numAttr("WH_" .. id, 0)),
                    attr("Off_" .. id) == true and "OFF" or "ACTIVE"))
            end
        end

        local upgs = availableUpgrades()
        local unbought = 0
        add("")
        add("--- Next Unbought Upgrades ---")
        for _, u in ipairs(upgs) do
            if not u.bought then
                unbought = unbought + 1
                if unbought <= 10 then
                    add(string.format("  %-20s | $%-7d | %s (%s)", u.id, u.price, u.name, u.info))
                end
            end
        end
        if unbought == 0 then add("  all listed upgrades bought") end

        local workers = myWorkers()
        add("")
        add("--- My Workers (" .. #workers .. ") ---")
        for _, w in ipairs(workers) do
            local sk = w.skill and ("$" .. w.skill.cost .. " lv" .. w.skill.level) or "max"
            local st = w.stamina and ("$" .. w.stamina.cost .. " lv" .. w.stamina.level) or "max"
            add(string.format("  %-11s | %-12s | %-8s | skill %-12s | stamina %s",
                w.name, w.dept, w.mode, sk, st))
        end

        return table.concat(L, "\n")
    end

    local function scanRemotesAndUIReport()
        local L = {}
        local function add(s) L[#L+1] = tostring(s) end

        add("=== ReplicatedStorage Remotes & Modules ===")
        local remotes = allRemotes()
        add("Remotes (" .. #remotes .. "):")
        for _, r in ipairs(remotes) do
            add("  " .. r.ClassName .. " | " .. fullName(r))
        end

        add("")
        add("ReplicatedStorage Tree:")
        for _, c in ipairs(replicatedstorage:GetChildren()) do
            add("  " .. c.ClassName .. " | " .. c.Name .. " (" .. #c:GetChildren() .. " children)")
            for _, sub in ipairs(c:GetChildren()) do
                add("    " .. sub.ClassName .. " | " .. sub.Name)
            end
        end

        add("")
        add("Learned Remote Signatures:")
        for k, v in pairs(learned) do
            if v and v.remote then
                add("  " .. k .. " -> " .. fullName(v.remote) .. " (" .. tostring(v.method) .. ")")
            end
        end

        add("")
        add("=== LaptopUI / PhoneUI Buttons ===")
        local pgui = plr:FindFirstChildOfClass("PlayerGui")
        if pgui then
            for _, screenName in ipairs({ "LaptopUI", "PhoneUI", "HUD", "SpinUI", "StreakUI" }) do
                local screen = pgui:FindFirstChild(screenName)
                if screen then
                    add("[" .. screenName .. "]")
                    local count = 0
                    local ok, desc = pcall(function() return screen:GetDescendants() end)
                    if ok and desc then
                        for _, d in ipairs(desc) do
                            if d:IsA("TextButton") or d:IsA("ImageButton") then
                                count = count + 1
                                if count <= 80 then
                                    add(string.format("  %s | vis=%s | %s",
                                        fullName(d), tostring(d.Visible), buttonLabelText(d)))
                                end
                            end
                        end
                    end
                    if count > 80 then add("  ... " .. (count - 80) .. " more buttons") end
                end
            end
        end

        return table.concat(L, "\n")
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------

    elements:Label("My Dropshipping Business", section)

    elements:Button("Show Status", section, function()
        lastReport = statusReport()
        print(lastReport)
    end)

    elements:Button("Copy Status", section, function()
        lastReport = statusReport()
        local ok = pcall(setclipboard, lastReport)
        print("[BrainrotPolice] " .. (ok and "status copied" or "could not copy"))
    end)

    ----------------------------------------------------------------
    elements:Label("Auto Order & Accept", section)

    local prodOptions = { "Best Owned" }
    for _, id in ipairs(PRODUCT_ORDER) do
        prodOptions[#prodOptions+1] = id
    end

    elements:Dropdown("Product", section, prodOptions, setdata.product, function(v)
        setdata.product = v
        env.setconfig("product", v)
        print("[BrainrotPolice] target product -> " .. tostring(targetProduct()))
    end)

    elements:Button("Order Best Stock Once", section, function()
        local ok, info = orderStockOnce()
        print("[BrainrotPolice] order stock (" .. tostring(info) .. "): " .. (ok and "triggered" or "no action / full"))
    end)

    elements:Toggle("Auto Order Best Stock", section, false, function(v)
        env.MDOrder = v
        print("[BrainrotPolice] auto order stock " .. (v and ("on (" .. tostring(targetProduct()) .. ")") or "off"))
    end)

    elements:Button("Accept Orders Once", section, function()
        local n = acceptOrdersOnce()
        print("[BrainrotPolice] accept orders triggered (" .. tostring(n) .. " actions)")
    end)

    elements:Toggle("Auto Accept Orders", section, false, function(v)
        env.MDAccept = v
        print("[BrainrotPolice] auto accept orders " .. (v and "on" or "off"))
    end)

    elements:Button("Only Keep Best Product Active", section, function()
        local n, best = keepOnlyBestProductActive()
        print("[BrainrotPolice] best product: " .. tostring(best) .. " | toggled " .. tostring(n) .. " products")
    end)

    elements:Button("Start Campaign (Best Product)", section, function()
        local ok, best = startBestCampaignOnce()
        print("[BrainrotPolice] campaign (" .. tostring(best) .. "): " .. (ok and "triggered" or "not ready"))
    end)

    elements:Toggle("Auto Campaign (Best Product)", section, false, function(v)
        env.MDCampaign = v
        print("[BrainrotPolice] auto campaign " .. (v and "on" or "off"))
    end)

    ----------------------------------------------------------------
    elements:Label("Auto Buy & Workers", section)

    elements:Button("Buy Cheapest Upgrade", section, function()
        local ok, upg = buyCheapestUpgradeOnce()
        if upg then
            print(string.format("[BrainrotPolice] upgrade %s ($%d): %s", upg.name, upg.price, ok and "triggered" or "attempted"))
        else
            print("[BrainrotPolice] no affordable unbought upgrade right now")
        end
    end)

    elements:Toggle("Auto Buy Upgrades", section, false, function(v)
        env.MDBuy = v
        print("[BrainrotPolice] auto buy upgrades " .. (v and "on" or "off"))
    end)

    elements:Button("Train Cheapest Worker Stat", section, function()
        local ok, best = trainCheapestWorkerOnce()
        if best then
            print(string.format("[BrainrotPolice] train %s %s ($%d): %s",
                best.worker.name, best.stat, best.cost, ok and "triggered" or "attempted"))
        else
            print("[BrainrotPolice] no affordable worker stat upgrade")
        end
    end)

    elements:Toggle("Auto Train Workers", section, false, function(v)
        env.MDTrain = v
        print("[BrainrotPolice] auto train workers " .. (v and "on" or "off"))
    end)

    elements:Button("Hire Best Applicant", section, function()
        local ok, app = hireBestApplicantOnce()
        if app then
            print(string.format("[BrainrotPolice] hire %s (%s, %s, $%d): %s",
                app.name, app.role, app.tier, app.cost, ok and "triggered" or "attempted"))
        else
            print("[BrainrotPolice] no affordable applicant found")
        end
    end)

    elements:Toggle("Auto Plot & Package Prompts", section, false, function(v)
        env.MDPrompts = v
        print("[BrainrotPolice] auto plot/package prompts " .. (v and "on" or "off"))
    end)

    elements:Toggle("Auto Claim Spin / Streak", section, false, function(v)
        env.MDClaim = v
        print("[BrainrotPolice] auto claim spin/streak " .. (v and "on" or "off"))
    end)

    ----------------------------------------------------------------
    elements:Label("Teleports", section)

    elements:Button("Teleport To My Plot", section, function()
        local plot = myPlot()
        local pos = posOf(plot)
        if pos and tweenTo(pos) then
            print("[BrainrotPolice] teleported to " .. plot.Name)
        else
            print("[BrainrotPolice] own plot not found")
        end
    end)

    elements:Button("Teleport To Post Station", section, function()
        local map = workspace:FindFirstChild("NewMap")
        local post = map and map:FindFirstChild("PostStation")
        local pos = posOf(post)
        if pos and tweenTo(pos) then
            print("[BrainrotPolice] teleported to PostStation")
        else
            print("[BrainrotPolice] PostStation not found")
        end
    end)

    elements:Button("Teleport To Ineed Agency", section, function()
        local map = workspace:FindFirstChild("NewMap")
        local ineed = map and map:FindFirstChild("Ineed")
        local pos = posOf(ineed)
        if pos and tweenTo(pos) then
            print("[BrainrotPolice] teleported to Ineed Agency")
        else
            print("[BrainrotPolice] Ineed not found")
        end
    end)

    ----------------------------------------------------------------
    elements:Label("Diagnostics", section)

    elements:Button("Scan Remotes & UI (Copy)", section, function()
        lastReport = scanRemotesAndUIReport()
        local ok = pcall(setclipboard, lastReport)
        print(lastReport)
        print("[BrainrotPolice] " .. (ok and "remotes & UI scan copied to clipboard" or "printed to console"))
    end)

    local logWasOn = false

    elements:Toggle("Log Remotes (Auto-Learn)", section, false, function(v)
        env.MDLog = v
        if v then
            logWasOn = true
            installHook()
            print("[BrainrotPolice] remote logger on — click Order / Accept / Buy once in LaptopUI to auto-learn & log")
        elseif logWasOn then
            logWasOn = false
            if writefile and #logBuf > 0 then
                pcall(writefile, LOG_FILE, table.concat(logBuf, "\n"))
            end
            print("[BrainrotPolice] remote logger off, saved to " .. LOG_FILE)
        end
    end)

    elements:Button("Copy Remote Log", section, function()
        if #logBuf == 0 then
            print("[BrainrotPolice] remote log is empty")
            return
        end
        local ok = pcall(setclipboard, table.concat(logBuf, "\n"))
        print("[BrainrotPolice] " .. (ok and ("copied " .. #logBuf .. " lines") or "could not copy"))
    end)
end
