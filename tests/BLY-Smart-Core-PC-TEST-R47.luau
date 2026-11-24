-- BLY Smart Core R47 | TEST COPY | PC / Solara compatibility-oriented
-- Independent rebuild: no modifications to original BLY script or loader.
-- Built from observed source conventions; in-game verification is still required.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
if not player then error("BLY R47: LocalPlayer unavailable") end
local pg = player:WaitForChild("PlayerGui", 12)
if not pg then error("BLY R47: PlayerGui unavailable") end

local CFG = {
    NeedAt = 70, FillTo = 95, AgentRadius = 1.5, AgentHeight = 5,
    Step = 0.09, Near = 1.8, StuckFor = 2.8, LegTimeout = 9,
    WorkTimeout = 42, WalkMin = 3.5, ScanRadius = 360,
    AttemptCooldown = 75, QuestRefresh = 8, GrowRefresh = 3,
    WaypointSpacing = 4, DryFootprint = 0.8
}
local PREFIX = "BLY_R47_"
local shared
pcall(function() if type(getgenv) == "function" then shared = getgenv() end end)
if type(shared) ~= "table" then shared = _G end
pcall(function()
    local old = shared.BLY_R47_INSTANCE
    if old and type(old.shutdown) == "function" then old.shutdown() end
end)
local app = {
    alive = true, running = false, generation = 0, mode = "SURVIVAL",
    state = "READY", lastError = "", lastAction = "", target = "",
    currentGoal = nil, avoid = {}, known = { Food = {}, Water = {} },
    quests = {}, questStatus = "مهام: لم تُقرأ بعد", growthStatus = "تكبير: لم يبدأ",
    claimRetry = {}, visitedZone = {}, questRetries = {}, scoutVisited = {},
    missed = { Food = 0, Water = 0 }, logs = {}, buttons = {},
    currentMove = Vector3.new(0, 0, 0), hud = nil, lastQuests = 0,
    lastGrowth = 0, lastSource = nil, need = { Food = false, Water = false },
    growthCycleAt = 0, desiredSpecies = nil
}
shared.BLY_R47_INSTANCE = app
local connections = {}
local function connect(event, cb)
    local ok, con = pcall(function() return event:Connect(cb) end)
    if ok and con then table.insert(connections, con) end
    return con
end
local function log(message)
    message = tostring(message or "")
    table.insert(app.logs, os.date("%X") .. " " .. message)
    if #app.logs > 45 then table.remove(app.logs, 1) end
    print("[BLY R47] " .. message)
end
local function status(message)
    app.state = tostring(message or "")
    log(app.state)
end
local function safeCall(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then app.lastError = tostring(a); warn("[BLY R47] " .. app.lastError) end
    return ok, a, b, c
end
local function rig()
    local character = player.Character
    if not character or not character.Parent then return end
    local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if root and humanoid and humanoid.Health > 0 then return character, root, humanoid end
end
local function valid(token, character)
    return app.alive and app.running and app.generation == token
        and character ~= nil and player.Character == character and character.Parent ~= nil
end
local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end
local function dist(a, b)
    return flat(a - b).Magnitude
end
local function clamp(value, lo, hi)
    return math.min(hi, math.max(lo, value))
end
local function readNeed(character, name)
    local value = character:GetAttribute(name)
    local maximum = character:GetAttribute("Max" .. name) or character:GetAttribute(name .. "Max") or 100
    if type(value) ~= "number" or type(maximum) ~= "number" then return nil end
    if maximum <= 0 or value < 0 or value > maximum then return nil end
    return value / maximum * 100
end
local function needs(character)
    return readNeed(character, "Food"), readNeed(character, "Water")
end
local function activeNeed(food, water)
    if not food or not water then return nil end
    if food < CFG.NeedAt then app.need.Food = true end
    if water < CFG.NeedAt then app.need.Water = true end
    if food >= CFG.FillTo then app.need.Food = false end
    if water >= CFG.FillTo then app.need.Water = false end
    if app.need.Water and (not app.need.Food or water <= food) then return "Water" end
    if app.need.Food then return "Food" end
    if app.need.Water then return "Water" end
end
local function isHerbivore(character)
    local diet = character:GetAttribute("FoodType")
    return diet == nil or string.lower(tostring(diet)) == "grass"
end

-- Draw a diagnostic panel before moving anything; no external UI library.
local oldGui = pg:FindFirstChild(PREFIX .. "Panel")
if oldGui then oldGui:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = PREFIX .. "Panel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 900
local okParent = pcall(function() gui.Parent = pg end)
if not okParent then error("BLY R47: cannot create PlayerGui panel") end
local base = Instance.new("Frame")
base.Name = "Panel"
base.Size = UDim2.new(0, 405, 0, 249)
base.Position = UDim2.new(0, 22, 0, 90)
base.BackgroundColor3 = Color3.fromRGB(16, 18, 21)
base.BorderSizePixel = 0
base.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = base
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Text = "BLY SMART CORE R47  |  PC TEST"
title.Size = UDim2.new(1, -20, 0, 31)
title.Position = UDim2.new(0, 11, 0, 6)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.Parent = base
local info = Instance.new("TextLabel")
info.Name = "Diagnostics"
info.Size = UDim2.new(1, -24, 0, 107)
info.Position = UDim2.new(0, 12, 0, 84)
info.BackgroundTransparency = 1
info.TextColor3 = Color3.fromRGB(215, 222, 227)
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true
info.Font = Enum.Font.Code
info.TextSize = 12
info.Text = "جار فحص اللعبة..."
info.Parent = base
local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, -20, 0, 36)
footer.Position = UDim2.new(0, 10, 1, -39)
footer.BackgroundTransparency = 1
footer.TextColor3 = Color3.fromRGB(178, 196, 207)
footer.Font = Enum.Font.Code
footer.TextSize = 11
footer.TextWrapped = true
footer.Text = "بناء مستقل. لا يشتري حيوانات ولا يغير سكربت BLY الأصلي."
footer.Parent = base
local function makeButton(text, x, width, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, width, 0, 37)
    b.Position = UDim2.new(0, x, 0, 43)
    b.BackgroundColor3 = Color3.fromRGB(41, 45, 49)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = base
    local rounding = Instance.new("UICorner")
    rounding.CornerRadius = UDim.new(0, 6)
    rounding.Parent = b
    connect(b.MouseButton1Click, callback)
    return b
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true
local wetParams = RaycastParams.new()
wetParams.FilterType = Enum.RaycastFilterType.Include
wetParams.IgnoreWater = false
wetParams.RespectCanCollide = false
local parametersFor
local function floorAt(point, character)
    rayParams.FilterDescendantsInstances = { character }
    local hit = Workspace:Raycast(point + Vector3.new(0, 35, 0), Vector3.new(0, -95, 0), rayParams)
    if not hit or hit.Normal.Y < 0.78 then return nil end
    local instance = hit.Instance
    if instance and instance:IsA("BasePart") and not instance.CanCollide then return nil end
    if instance and instance:GetAttribute("BLY_Hazard") then return nil end
    return hit
end
local function waterPart()
    local part = Workspace:FindFirstChild("MainWaterPart")
    if part and part:IsA("BasePart") then return part end
end
local function waterAt(point)
    local p = waterPart()
    local origin = point + Vector3.new(0, 32, 0)
    local dir = Vector3.new(0, -85, 0)
    wetParams.FilterDescendantsInstances = p and { Workspace.Terrain, p } or { Workspace.Terrain }
    local hit = Workspace:Raycast(origin, dir, wetParams)
    local candidate
    if hit and (hit.Material == Enum.Material.Water or hit.Instance == p) then
        candidate = hit.Position
    end
    -- Some Savannah Life water planes are transparent: the actual top face is a valid surface.
    if p and p.CFrame.UpVector.Y > 0.99 then
        local top = p.Position.Y + p.Size.Y * 0.5
        if origin.Y >= top and origin.Y + dir.Y <= top then
            local q = p.CFrame:PointToObjectSpace(Vector3.new(point.X, top, point.Z))
            if math.abs(q.X) <= p.Size.X * 0.5 and math.abs(q.Z) <= p.Size.Z * 0.5 then
                local surface = Vector3.new(point.X, top, point.Z)
                if not candidate or candidate.Y < surface.Y then candidate = surface end
            end
        end
    end
    return candidate
end
local function dryAt(point, character)
    local ground = floorAt(point, character)
    if not ground then return nil end
    local water = waterAt(point)
    if water and water.Y >= ground.Position.Y - 0.35 then return nil end
    return ground.Position
end
local function drySegment(a, b, character)
    local length = dist(a, b)
    if length > 30 then return false end
    local steps = math.max(1, math.ceil(length / 2.4))
    local previous
    local path = flat(b - a)
    local side = path.Magnitude > 0.01 and Vector3.new(-path.Z,0,path.X).Unit * CFG.DryFootprint or Vector3.new(0,0,0)
    for i = 0, steps do
        local point = a:Lerp(b, i / steps)
        local checked = dryAt(point, character)
        if not checked or math.abs(checked.Y - point.Y) > 5 then return false end
        if not dryAt(point + side, character) or not dryAt(point - side, character) then return false end
        if previous and math.abs(previous.Y - checked.Y) > 2.8 then return false end
        previous = checked
    end
    return true
end
local function isWetHere(root, character)
    local land = floorAt(root.Position, character)
    local water = waterAt(root.Position)
    return water ~= nil and (not land or water.Y >= land.Position.Y - 0.35)
end
local function cell(p)
    return tostring(math.floor(p.X / 9)) .. ":" .. tostring(math.floor(p.Z / 9))
end
local function excluded(kind, position)
    return (app.avoid[kind .. cell(position)] or 0) > os.clock()
end
local function reject(kind, position, delay)
    if position then app.avoid[kind .. cell(position)] = os.clock() + (delay or CFG.AttemptCooldown) end
end
local function remember(kind, position, water)
    if not position or excluded(kind, position) then return end
    local key = cell(position)
    app.known[kind][key] = { position = position, water = water, at = os.clock() }
end
local function readPrompt(kind)
    local screen = pg:FindFirstChild("EatDrinkDisplayScreenGui")
    if not screen or not screen.Enabled then return nil end
    local label = screen:FindFirstChild("RightTextLabel", true)
    if not label or not label:IsA("TextLabel") then return nil end
    local text = string.lower(label.Text or "")
    if kind == "Water" then
        if string.find(text, "drink", 1, true) or string.find(text, "الشرب", 1, true)
            or string.find(text, "اشرب", 1, true) then return label end
    else
        if string.find(text, "eat", 1, true) or string.find(text, "graz", 1, true)
            or string.find(text, "الأكل", 1, true) or string.find(text, "الرعي", 1, true) then return label end
    end
end
local virtualInput, virtualUser, virtualKeyboard
pcall(function() virtualInput = game:GetService("VirtualInputManager") end)
pcall(function() virtualUser = game:GetService("VirtualUser") end)
pcall(function() virtualKeyboard = UserInputService:CreateVirtualInput() end)
local function sendKey(code)
    if virtualInput then
        local success = pcall(function()
            virtualInput:SendKeyEvent(true, code, false, game)
            task.wait(0.1)
            virtualInput:SendKeyEvent(false, code, false, game)
        end)
        if success then return true, "VIM" end
    end
    if virtualKeyboard then
        local success = pcall(function()
            virtualKeyboard:SendKey(true, code, false)
            task.wait(0.1)
            virtualKeyboard:SendKey(false, code, false)
        end)
        if success then return true, "VirtualInput" end
    end
    local keycodes = { E = 69, R = 82, K = 75 }
    if type(keyclick) == "function" and keycodes[code.Name] then
        local success = pcall(keyclick, keycodes[code.Name])
        if success then return true, "keyclick" end
    end
    if type(keypress) == "function" and type(keyrelease) == "function" then
        local key = keycodes[code.Name]
        if key then
            local success = pcall(function()
                keypress(key)
                task.wait(0.1)
                keyrelease(key)
            end)
            if success then return true, "keypress" end
        end
    end
    return false, "no-supported-key-transport"
end
local function guiVisible(object)
    if not object or not object.Parent then return false end
    local node = object
    while node and node ~= pg do
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        if node:IsA("GuiObject") and not node.Visible then return false end
        node = node.Parent
    end
    return node == pg
end
local function click(button)
    if not button or not button:IsA("GuiButton") or not guiVisible(button) then return false end
    if button.AbsoluteSize.X < 4 or button.AbsoluteSize.Y < 4 then return false end
    local x = button.AbsolutePosition.X + button.AbsoluteSize.X / 2
    local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2
    local good = pcall(function()
        local objects = pg:GetGuiObjectsAtPosition(x, y)
        local first = objects and objects[1]
        if first and not (first == button or first:IsDescendantOf(button)) then error("obscured-button") end
    end)
    if not good then return false end
    if virtualInput then
        local success = pcall(function()
            virtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.07)
            virtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if success then return true end
    end
    if virtualKeyboard then
        local success = pcall(function()
            virtualKeyboard:SendMousePosition(Vector2.new(x,y))
            virtualKeyboard:SendMouseButton(Vector2.new(x,y), Enum.UserInputType.MouseButton1, true, 0)
            task.wait(0.07)
            virtualKeyboard:SendMouseButton(Vector2.new(x,y), Enum.UserInputType.MouseButton1, false, 0)
        end)
        if success then return true end
    end
    if virtualUser then
        local camera = Workspace.CurrentCamera
        if camera then
            local success = pcall(function()
                virtualUser:CaptureController()
                virtualUser:Button1Down(Vector2.new(x,y), camera.CFrame)
                task.wait(0.07)
                virtualUser:Button1Up(Vector2.new(x,y), camera.CFrame)
            end)
            if success then return true end
        end
    end
    return false
end
local function questPanel()
    local screen = pg:FindFirstChild("QuestsScreenGui")
    if not screen then return end
    local scroll = screen:FindFirstChild("RefScrollingFrame", true)
    if not scroll then scroll = screen:FindFirstChildWhichIsA("ScrollingFrame", true) end
    return screen, scroll
end
local function textNode(node)
    return node and node:IsA("TextLabel") and node.Text or ""
end
local function questKind(text)
    local s = string.lower(text or "")
    if string.find(s, "group", 1, true) or string.find(s, "clan", 1, true) then return "SKIP" end
    if string.find(s, "swim", 1, true) then return "SKIP" end -- Cannot risk drowning for a quest
    if string.find(s, "explore", 1, true) or string.find(s, "different zones", 1, true) then return "Explore" end
    if string.find(s, "drink", 1, true) then return "Water" end
    if string.find(s, "eat", 1, true) or string.find(s, "graze", 1, true) then return "Food" end
    if string.find(s, "visit", 1, true) or string.find(s, "zone", 1, true) then return "Zone" end
    if string.find(s, "walk", 1, true) or string.find(s, "distance", 1, true) then return "Land" end
    if string.find(s, "play", 1, true) or string.find(s, "surviv", 1, true) then return "Passive" end
    if string.find(s, "grow", 1, true) then return "Passive" end
    return "UNKNOWN"
end
local function questList()
    local screen, scroll = questPanel()
    if not screen or not scroll then return {}, "واجهة المهام غير محملة" end
    local rows, seen = {}, {}
    local nodes = scroll:GetDescendants()
    for i = 1, math.min(#nodes, 400) do
        local node = nodes[i]
        if node:IsA("TextLabel") then
            local a, b = string.match(node.Text or "", "(%d+)%s*/%s*(%d+)")
            a, b = tonumber(a), tonumber(b)
            if a and b and b > 0 and a <= b then
                local ancestor = node.Parent
                for depth = 1, 5 do
                    if ancestor == nil or ancestor == scroll then break end
                    local title = ancestor:FindFirstChild("TitleTextLabel", true)
                    local desc = ancestor:FindFirstChild("InfoTextLabel", true)
                    if title and desc and title:IsA("TextLabel") and desc:IsA("TextLabel") then
                        local t = title.Text
                        local d = desc.Text
                        local key = t .. ":" .. d .. ":" .. tostring(b)
                        if not seen[key] then
                            seen[key] = true
                            table.insert(rows, {
                                key = key, title = t, desc = d, current = a, maximum = b,
                                kind = questKind(t .. " " .. d), card = ancestor,
                                completed = a >= b, progress = node
                            })
                        end
                        break
                    end
                    ancestor = ancestor.Parent
                end
            end
        end
        if #rows >= 20 then break end
    end
    return rows, nil
end
local function openQuestPanel()
    local screen = questPanel()
    if screen and screen.Enabled and guiVisible(screen) then return true end
    local stats = pg:FindFirstChild("AnimalStatsScreenGui")
    local button = stats and stats:FindFirstChild("QuestsButton", true)
    if not button then return false end
    if not click(button) then return false end
    task.wait(0.3)
    local panel = questPanel()
    return panel ~= nil and panel.Enabled
end
local function refreshQuests()
    if os.clock() - app.lastQuests < CFG.QuestRefresh then return end
    app.lastQuests = os.clock()
    if not openQuestPanel() then
        app.questStatus = "الواجهة مقفلة أو سالورا لا يضغط زر QUESTS"
        return
    end
    local all, seen = {}, {}
    local function collect(bucket)
        local rows = questList()
        for _, q in ipairs(rows) do
            if not seen[q.key] then
                seen[q.key] = true
                q.bucket = bucket
                table.insert(all, q)
            end
        end
    end
    collect("Visible")
    local screen = pg:FindFirstChild("QuestsScreenGui")
    local top = screen and screen:FindFirstChild("TopButtonsFrame", true)
    for _, bucket in ipairs({ "Daily", "Weekly" }) do
        local button = top and top:FindFirstChild(bucket .. "Button")
        if button and click(button) then
            task.wait(0.25)
            collect(bucket)
        end
    end
    app.quests = all
    app.questStatus = "قرأت " .. tostring(#all) .. " مهمة يومية/أسبوعية من الواجهة"
end
local function claimQuests()
    local screen = pg:FindFirstChild("QuestsScreenGui")
    local top = screen and screen:FindFirstChild("TopButtonsFrame", true)
    for _, quest in ipairs(app.quests) do
        if quest.completed and quest.kind ~= "SKIP" and quest.card and quest.card.Parent
            and os.clock() > (app.claimRetry[quest.key] or 0) then
            if quest.bucket == "Daily" or quest.bucket == "Weekly" then
                local tab = top and top:FindFirstChild(quest.bucket .. "Button")
                if tab and guiVisible(tab) then click(tab); task.wait(0.2) end
            end
            local progress = quest.progress and quest.progress.Parent and quest.progress.Text
            local a,b = progress and string.match(progress, "(%d+)%s*/%s*(%d+)")
            if tonumber(a) and tonumber(b) and tonumber(a)>=tonumber(b) then
                local button = quest.card:FindFirstChild("ClaimButton", true)
                if not button then button = quest.card:FindFirstChild("ClickDetectorButton", true) end
                if button and button:IsA("GuiButton") and guiVisible(button) then
                    app.claimRetry[quest.key] = os.clock() + 15
                    if click(button) then
                        app.questStatus = "طلب Claim لـ " .. quest.title .. "; لم أتأكد من تسجيله بعد"
                        task.wait(0.35)
                        app.lastQuests = 0
                    end
                end
            end
        end
    end
end
local function zoneDestination(quest, root, character)
    local zones = Workspace:FindFirstChild("MapZones")
    if not zones then return nil end
    local description = string.lower(quest.title .. " " .. quest.desc)
    local best, cost
    for _, zone in ipairs(zones:GetChildren()) do
        if string.find(description, string.lower(zone.Name), 1, true) then
            local items = zone:IsA("BasePart") and { zone } or zone:GetDescendants()
            for _, part in ipairs(items) do
                if part:IsA("BasePart") then
                    local localPoint = part.CFrame:PointToObjectSpace(root.Position)
                    local edge = Vector3.new(clamp(localPoint.X,-part.Size.X*.47,part.Size.X*.47),
                        0,clamp(localPoint.Z,-part.Size.Z*.47,part.Size.Z*.47))
                    local candidate = part.CFrame:PointToWorldSpace(edge)
                    local dryPoint = dryAt(candidate, character)
                    if dryPoint then
                        local d = dist(root.Position, dryPoint)
                        if not cost or d < cost then best = dryPoint; cost = d end
                    end
                end
            end
        end
    end
    return best
end

-- Conservative dry-land path following using Humanoid:Move, not W-key.
local function moveStop(humanoid)
    app.currentMove = Vector3.new(0,0,0)
    if humanoid and humanoid.Parent then pcall(function() humanoid:Move(Vector3.new(0,0,0), false) end) end
end
-- The default Roblox control script can overwrite Humanoid:Move every frame.
-- Reapply after character controls via BindToRenderStep; fall back to Heartbeat.
local moveBinding = PREFIX .. "Move"
local function movementTick()
    if not app.alive or not app.running then return end
    local direction = app.currentMove
    if not direction or direction.Magnitude < 0.05 then return end
    local _, _, humanoid = rig()
    if humanoid then pcall(function() humanoid:Move(direction, false) end) end
end
local moveBound = pcall(function()
    RunService:UnbindFromRenderStep(moveBinding)
    RunService:BindToRenderStep(moveBinding, Enum.RenderPriority.Character.Value + 5, movementTick)
end)
if not moveBound then connect(RunService.Heartbeat, movementTick) end
local function moveStep(root, humanoid, target, character, token, recovery)
    local prior = root.Position
    local last = os.clock()
    local started = last
    while valid(token, character) and os.clock() - started < CFG.LegTimeout do
        if dist(root.Position, target) <= CFG.Near then moveStop(humanoid); return true, "reached" end
        local v = flat(target - root.Position)
        if v.Magnitude <= 0.05 then moveStop(humanoid); return true, "reached" end
        local direction = v.Unit
        if not recovery then
            local nextPoint = root.Position + direction * math.min(2.3, v.Magnitude)
            if not drySegment(root.Position, nextPoint, character) then
                moveStop(humanoid); return false, "unsafe-water-or-edge" end
        end
        humanoid:Move(direction, false)
        app.currentMove = direction
        task.wait(CFG.Step)
        if dist(root.Position, prior) >= 0.55 then prior = root.Position; last = os.clock() end
        if os.clock() - last > CFG.StuckFor then moveStop(humanoid); return false, "stuck-no-progress" end
    end
    moveStop(humanoid)
    return false, "leg-timeout-or-cancel"
end
local function routeTo(target, character, root, humanoid, token, recovery)
    local delta = dist(root.Position, target)
    if delta < CFG.Near then return true, "already-near" end
    if not recovery and delta <= 28 and drySegment(root.Position, target, character) then
        return moveStep(root, humanoid, target, character, token, false)
    end
    local path
    local ok, err = pcall(function()
        path = PathfindingService:CreatePath({
            AgentRadius = CFG.AgentRadius, AgentHeight = CFG.AgentHeight,
            AgentCanJump = false, AgentCanClimb = false,
            WaypointSpacing = CFG.WaypointSpacing, Costs = { Water = 1000000 }
        })
        path:ComputeAsync(root.Position, target)
    end)
    if not ok or not path or path.Status ~= Enum.PathStatus.Success then
        return false, "Pathfinding-NoPath: " .. tostring(err)
    end
    local points = path:GetWaypoints()
    if #points < 1 then return false, "no-waypoints" end
    local prev = root.Position
    for i = 1, #points do
        if not valid(token, character) then return false, "cancel" end
        local targetPoint = points[i].Position
        if not recovery and not drySegment(prev, targetPoint, character) then
            return false, "waypoint-enters-water" end
        local reached, why = moveStep(root, humanoid, targetPoint, character, token, recovery)
        if not reached then return false, why end
        prev = targetPoint
    end
    return true, "arrived"
end
local function rescueDry(character, root, humanoid, token)
    local choices = {}
    for _, radius in ipairs({ 3, 6, 10, 16, 24, 34 }) do
        for i = 0, 15 do
            local angle = i * math.pi / 8
            local probe = root.Position + Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
            local floor = dryAt(probe, character)
            if floor then table.insert(choices, { position = floor, d = dist(root.Position, floor) }) end
        end
        if #choices > 0 then break end
        task.wait()
    end
    table.sort(choices, function(a,b) return a.d < b.d end)
    for i = 1, math.min(3, #choices) do
        status("خروج طارئ من المويه إلى يابسة")
        local ok = routeTo(choices[i].position, character, root, humanoid, token, true)
        if ok and not isWetHere(root, character) then return true end
    end
    return not isWetHere(root, character)
end

local function shorelineCandidate(dryProbe, wetProbe, character)
    local land = dryProbe
    local water = wetProbe
    for i = 1, 9 do
        local mid = land:Lerp(water, 0.5)
        if waterAt(mid) then water = mid else land = mid end
    end
    local delta = flat(land - water)
    if delta.Magnitude < 0.1 then return nil end
    for _, back in ipairs({ 1.4, 2.2, 3.2, 4.5, 6 }) do
        local point = land + delta.Unit * back
        local p = dryAt(point, character)
        if p and dist(p, water) <= 12 then return p, water end
    end
end
local function findCandidates(kind, character, root, token)
    local results, seen = {}, {}
    local function add(position, water, priority)
        if not position or excluded(kind, position) then return end
        local key = cell(position)
        if seen[key] then return end
        seen[key] = true
        table.insert(results, { pos = position, water = water, priority = priority or dist(position, root.Position) })
    end
    for _, entry in pairs(app.known[kind]) do
        if os.clock() - entry.at < 720 and dryAt(entry.position, character) then
            add(entry.position, entry.water, dist(root.Position, entry.position) * 0.8)
        end
    end
    local centerLand = dryAt(root.Position, character)
    if not centerLand then return results end
    if kind == "Food" then
        for _, radius in ipairs({ 0, 6, 12, 20, 32, 52, 80, 120, 180, 240, 360 }) do
            for i = 0, 19 do
                if not valid(token, character) then return results end
                local a = i * math.pi / 10
                local probe = root.Position + Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius)
                local ground = floorAt(probe, character)
                if ground and ground.Material == Enum.Material.Grass and dryAt(probe, character) then
                    add(ground.Position, nil, dist(root.Position, ground.Position))
                end
            end
            task.wait()
            if #results >= 7 then break end
        end
    else
        for _, radius in ipairs({ 4, 8, 16, 28, 48, 76, 120, 180, 260, 360 }) do
            for i = 0, 23 do
                if not valid(token, character) then return results end
                local a = i * math.pi / 12
                local dir = Vector3.new(math.cos(a),0,math.sin(a))
                local far = root.Position + dir * radius
                local water = waterAt(far)
                if water then
                    local here = root.Position + dir * math.max(0,radius-6)
                    local land = dryAt(here,character)
                    if land then
                        local bank, wet = shorelineCandidate(land, water, character)
                        if bank then add(bank, wet, dist(root.Position, bank)) end
                    else
                        local lo, hi = 0, radius
                        for step = 1, 8 do
                            local mid = (lo + hi)*0.5
                            if waterAt(root.Position+dir*mid) then hi=mid else lo=mid end
                        end
                        local bankLand = dryAt(root.Position+dir*math.max(0,lo-2), character)
                        if bankLand then
                            local bank, wet = shorelineCandidate(bankLand, water, character)
                            if bank then add(bank,wet,dist(root.Position,bank)) end
                        end
                    end
                end
            end
            task.wait()
            if #results >= 5 then break end
        end
    end
    table.sort(results, function(a, b) return a.priority < b.priority end)
    return results
end
local function confirmConsume(kind, character, root, humanoid, token)
    local before = readNeed(character, kind)
    if not before then return false, "stat-unavailable" end
    local press = readPrompt(kind)
    if not press then return false, "no-eat-or-drink-prompt" end
    moveStop(humanoid)
    local triggered = false
    for attempt = 1, 3 do
        if not valid(token, character) then return false, "cancel" end
        local send, transport = sendKey(Enum.KeyCode.E)
        app.lastAction = "E/" .. tostring(transport)
        if not send then return false, "Solara-cannot-send-E" end
        local started = os.clock()
        while os.clock() - started < 7 and valid(token, character) do
            local current = readNeed(character, kind)
            if current and current > before + 0.15 then triggered = true; break end
            task.wait(0.2)
        end
        if triggered then break end
        if not readPrompt(kind) then break end
    end
    if not triggered then return false, "E-sent-but-stat-did-not-increase" end
    local peak = before
    local stableAt = os.clock()
    local deadline = os.clock() + CFG.WorkTimeout
    while valid(token, character) and os.clock() < deadline do
        local current = readNeed(character, kind)
        if not current then break end
        if current > peak + 0.05 then peak = current; stableAt = os.clock() end
        if current >= CFG.FillTo then break end
        if os.clock() - stableAt > 4 then break end
        task.wait(0.25)
    end
    -- Stop action only when game is still showing a stop prompt; never spam E.
    local promptNode = readPrompt(kind)
    if promptNode then
        local raw = string.lower(promptNode.Text)
        if string.find(raw, "stop", 1, true) or string.find(raw, "إيقاف", 1, true) then sendKey(Enum.KeyCode.E) end
    end
    return true, "increased-to-" .. tostring(math.floor(peak))
end
local function scoutDry(kind, character, root, humanoid, token)
    local options = {}
    for _, radius in ipairs({22,45,75,115,165}) do
        for i = 0, 11 do
            if not valid(token, character) then return false, "cancel" end
            local angle = i * math.pi / 6
            local probe = root.Position + Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
            local land = dryAt(probe, character)
            if land and not excluded("Scout", land) then
                local key = cell(land)
                if os.clock() > (app.scoutVisited[key] or 0) then
                    table.insert(options, {pos=land,d=dist(root.Position,land)})
                end
            end
        end
        task.wait()
        if #options > 5 then break end
    end
    table.sort(options, function(a,b) return a.d < b.d end)
    for i=1, math.min(#options, 5) do
        if not valid(token, character) then return false,"cancel" end
        local candidate = options[i]
        local key = cell(candidate.pos)
        app.scoutVisited[key] = os.clock() + 180
        app.target = "SCOUT " .. key
        status("ما لقيت " .. kind .. "; أستكشف يابسة ثانية بدل التوقف")
        local ok,reason = routeTo(candidate.pos, character, root, humanoid, token, false)
        if ok then return true, "scouted-new-area" end
        reject("Scout", candidate.pos, 50)
    end
    return false,"no-safe-scout-destination"
end
local function care(kind, character, root, humanoid, token)
    local started = os.clock()
    local current = readNeed(character, kind)
    if not current then return false, "missing-stat" end
    if kind == "Food" and not isHerbivore(character) then return false, "non-grass-animal-unsupported" end
    if readPrompt(kind) then
        local ok, why = confirmConsume(kind, character, root, humanoid, token)
        if ok then remember(kind, root.Position); return true, why end
    end
    status((kind == "Water" and "أبحث عن ضفة شرب يابسة" or "أبحث عن عشب") .. " | " .. tostring(math.floor(current)) .. "%")
    local candidates = findCandidates(kind, character, root, token)
    if #candidates == 0 then
        return scoutDry(kind, character, root, humanoid, token)
    end
    for i = 1, math.min(8, #candidates) do
        if not valid(token, character) then return false, "cancel" end
        if os.clock() - started > 95 then return false, "resource-search-timeout" end
        local c = candidates[i]
        app.target = kind .. " " .. cell(c.pos) .. " " .. tostring(i) .. "/" .. tostring(#candidates)
        if kind == "Water" and not dryAt(c.pos, character) then
            reject(kind, c.pos)
        else
            local ok, why = routeTo(c.pos, character, root, humanoid, token, false)
            if ok and not isWetHere(root, character) then
                status("وصلت إلى مورد " .. kind .. "; أتحقق من زر التفاعل")
                local success, outcome = confirmConsume(kind, character, root, humanoid, token)
                if success then remember(kind, c.pos, c.water); return true, outcome end
                app.lastAction = outcome
                reject(kind, c.pos)
            else
                app.lastAction = why
                reject(kind, c.pos, 35)
                if isWetHere(root, character) then return false, "unexpectedly-wet" end
            end
        end
    end
    local moved, reason = scoutDry(kind, character, root, humanoid, token)
    if moved then return false, "all-candidates-rejected; scouted-new-area" end
    return false, "all-candidates-rejected: " .. tostring(reason)
end
local function growthValue(character)
    for _, key in ipairs({ "GrowthPercent", "GrowthPercentage", "AgePercent" }) do
        local value = character:GetAttribute(key)
        if type(value) == "number" and value >= 0 and value <= 100 then return value end
    end
    local growth = character:GetAttribute("Growth")
    local maxGrowth = character:GetAttribute("MaxGrowth") or character:GetAttribute("GrowthMax")
    if type(growth) == "number" and type(maxGrowth) == "number" and maxGrowth > 0 then
        return clamp(growth / maxGrowth * 100, 0, 100)
    end
    local hud = pg:FindFirstChild("AnimalStatsScreenGui")
    if hud then
        local n = hud:FindFirstChild("GrowthTextLabel", true)
        if n and n:IsA("TextLabel") then
            local value = tonumber(string.match(n.Text, "(%d+%.?%d*)%%"))
            if value then return value end
        end
    end
end
local function canon(value)
    return string.lower(tostring(value or "")):gsub("[^%a]", "")
end
local function blockedButton(n)
    local item = n
    for i = 1, 4 do
        if not item or item == pg then break end
        if item:GetAttribute("Locked") == true or item:GetAttribute("Owned") == false
            or item:GetAttribute("Unlocked") == false then return true end
        if item:IsA("TextButton") then
            local t = canon(item.Text)
            if string.find(t,"buy",1,true) or string.find(t,"purchase",1,true) then return true end
        end
        item = item.Parent
    end
    return false
end
local function visibleButton(pattern, container)
    local source = container or pg
    local descendants = source:GetDescendants()
    for i = 1, math.min(#descendants, 2400) do
        local n = descendants[i]
        if n:IsA("GuiButton") and guiVisible(n) and not blockedButton(n) then
            local name = canon(n.Name)
            local text = n:IsA("TextButton") and canon(n.Text) or ""
            local matched = string.find(name, pattern, 1, true) or text == pattern
            if not matched then
                local labels = n:GetDescendants()
                for ci = 1, math.min(#labels,20) do
                    local child = labels[ci]
                    if child:IsA("TextLabel") and canon(child.Text) == pattern then matched=true; break end
                end
            end
            if matched then return n end
        end
    end
end
local function growthCreate(character, token)
    if os.clock() - app.growthCycleAt < 120 then return false, "cycle-cooldown" end
    app.growthCycleAt = os.clock()
    local species = character:GetAttribute("AnimalName") or character:GetAttribute("Species")
        or character:GetAttribute("AnimalType")
    if type(species) ~= "string" or #species < 3 then
        return false, "species-not-confirmed; no-reset"
    end
    app.desiredSpecies = species
    local ok, backend = sendKey(Enum.KeyCode.K)
    if not ok then return false, "Solara-does-not-send-K: " .. tostring(backend) end
    status("أنتظر شاشة START بعد الريست؛ نوع الحيوان " .. species)
    local function session() return app.alive and app.running and app.generation == token end
    local function waitForButton(name, seconds, container)
        local limit = os.clock() + seconds
        while session() and os.clock() < limit do
            local b = visibleButton(name, container)
            if b then return b end
            task.wait(0.25)
        end
    end
    local deadline = os.clock() + 35
    local nextClick = 0
    while session() and os.clock() < deadline do
        if os.clock() >= nextClick then
            local start = visibleButton("start")
            if start then click(start) end
            nextClick = os.clock() + 1.7
        end
        if visibleButton("newcharacter") then break end
        task.wait(0.3)
    end
    if not session() then return false, "cancelled" end
    local saved = pg:FindFirstChild("SavedCharactersScreenGui")
    if not saved then return false, "saved-characters-screen-missing" end
    local new = waitForButton("newcharacter", 5, saved)
    if not new or not click(new) then return false, "new-character-not-clickable" end
    local animal = waitForButton(canon(species), 12, saved)
    if not animal or not click(animal) then return false, "owned-animal-not-found-or-unclickable" end
    local customize = waitForButton("customize", 10, saved)
    if customize and not click(customize) then return false, "customize-not-clickable" end
    local names = saved:FindFirstChild("NameFrame", true)
    local box = names and names:FindFirstChildWhichIsA("TextBox", true)
    local oldName = box and box.Text
    local random = waitForButton("randomize", 9, saved)
    if not random or not click(random) then return false, "random-name-not-clickable" end
    local named = false
    local nameDeadline = os.clock() + 3
    while session() and os.clock() < nameDeadline do
        names = saved:FindFirstChild("NameFrame", true)
        box = names and names:FindFirstChildWhichIsA("TextBox", true)
        if box and #box.Text >= 2 and (not oldName or box.Text ~= oldName) then named = true; break end
        task.wait(0.15)
    end
    if not named then return false, "random-name-did-not-change" end
    local create = waitForButton("create", 8, saved)
    if not create or not click(create) then return false, "create-not-clickable" end
    local play = waitForButton("play", 12, saved)
    if not play or not click(play) then return false, "play-not-clickable" end
    local confirmationDeadline = os.clock() + 30
    while session() and os.clock() < confirmationDeadline do
        local newChar = player.Character
        if newChar and newChar ~= character then
            local newRoot = newChar:FindFirstChild("HumanoidRootPart")
            local hum = newChar:FindFirstChildOfClass("Humanoid")
            if newRoot and hum and hum.Health > 0 then
                local newSpecies = newChar:GetAttribute("AnimalName") or newChar:GetAttribute("Species")
                if newSpecies and canon(newSpecies) ~= canon(species) then
                    return false, "unexpected-new-species"
                end
                local growth = growthValue(newChar)
                if growth == nil or growth < 99 then
                    app.growthStatus = "ظهرت شخصية جديدة؛ أرجع لرعاية المويه والأكل"
                    return true, "new-character-verified"
                end
            end
        end
        task.wait(0.3)
    end
    return false, "play-sent-but-new-character-not-verified"
end
local function exploreDestination(quest, root, character)
    local zones = Workspace:FindFirstChild("MapZones")
    if not zones then return nil end
    local choices = {}
    for _, zone in ipairs(zones:GetChildren()) do
        if not app.visitedZone[quest.key .. ":" .. zone.Name] then
            local parts = zone:IsA("BasePart") and {zone} or zone:GetDescendants()
            for _, part in ipairs(parts) do
                if part:IsA("BasePart") then
                    local p = dryAt(part.Position, character)
                    if p and dist(root.Position,p)>7 then
                        table.insert(choices,{point=p,name=zone.Name,distance=dist(root.Position,p)})
                        break
                    end
                end
            end
        end
    end
    table.sort(choices,function(a,b) return a.distance < b.distance end)
    if #choices>0 then return choices[1].point,choices[1].name end
end
local function autoQuests(character, root, humanoid, token)
    refreshQuests()
    claimQuests()
    local best
    for _, q in ipairs(app.quests) do
        if not q.completed and q.kind ~= "SKIP" then
            if q.kind == "Zone" then
                local point = zoneDestination(q, root, character)
                if point then best = {quest = q, point = point}; break end
            elseif q.kind == "Explore" then
                local point, name = exploreDestination(q, root, character)
                if point then best = {quest = q, point = point, zoneName = name}; break end
            elseif q.kind == "Land" then
                best = {quest = q}; break
            elseif q.kind == "Food" or q.kind == "Water" then
                best = {quest = q}; break
            elseif q.kind == "Passive" then
                app.questStatus = "مهمة وقت/نمو: أراقب تقدم اللعبة: " .. q.title
            end
        end
    end
    if not best then return false, "no-supported-quest" end
    local q = best.quest
    app.questStatus = "المهمة: " .. q.title .. " " .. tostring(q.current) .. "/" .. tostring(q.maximum)
    if q.kind == "Food" or q.kind == "Water" then
        local current = readNeed(character, q.kind)
        if current and current < 90 then return care(q.kind, character, root, humanoid, token) end
        return false, "quest-resource-already-full"
    elseif q.kind == "Zone" or q.kind == "Explore" then
        local ok, why = routeTo(best.point, character, root, humanoid, token, false)
        if ok and q.kind == "Explore" and best.zoneName then
            -- Remember visited candidates, but only the game's progress confirms success.
            app.visitedZone[q.key .. ":" .. best.zoneName] = true
        end
        return ok, why
    elseif q.kind == "Land" then
        local start = root.Position
        local candidates = findCandidates("Food", character, root, token)
        for i = 1, #candidates do
            if dist(start, candidates[i].pos) > 12 then
                return routeTo(candidates[i].pos, character, root, humanoid, token, false)
            end
        end
    end
    return false, "no-confirmed-quest-target"
end
local function patrol(character, root, humanoid, token)
    local options = findCandidates("Food", character, root, token)
    for _, candidate in ipairs(options) do
        if dist(root.Position, candidate.pos) >= 15 then
            app.target = "patrol " .. cell(candidate.pos)
            return routeTo(candidate.pos, character, root, humanoid, token, false)
        end
    end
    return false, "no-dry-patrol-target"
end

local function runCycle(token)
    local character, root, humanoid = rig()
    if not character then status("بانتظار سباون الحيوان ووجود Humanoid"); task.wait(1); return end
    local food, water = needs(character)
    if not food or not water then
        status("ما لقيت Attributes Food/Water، أوقف الحركة حتى تظهر النسب")
        task.wait(1); return
    end
    if isWetHere(root, character) then
        if not rescueDry(character, root, humanoid, token) then
            status("داخل المويه ولم أجد طريق خروج آمن")
            task.wait(2)
        end
        return
    end
    local need = activeNeed(food, water)
    if need then
        local ok, why = care(need, character, root, humanoid, token)
        if not ok then
            app.missed[need] = app.missed[need] + 1
            status("فشل " .. need .. ": " .. tostring(why) .. "، المحاولة التالية بمكان مختلف")
            task.wait(2.5)
        else
            app.missed[need] = 0
            status("نجح " .. need .. ": " .. tostring(why))
        end
        return
    end
    if app.mode == "GROWTH" then
        local value = growthValue(character)
        app.growthStatus = value and ("النمو الحالي " .. string.format("%.1f", value) .. "%") or "نسبة النمو غير متاحة"
        if value and value >= 99.9 then
            local ok, result = growthCreate(character, token)
            app.growthStatus = result
            if not ok then status("تكبير: " .. tostring(result)); task.wait(5) end
        else
            patrol(character, root, humanoid, token)
        end
    elseif app.mode == "QUESTS" then
        local ok, reason = autoQuests(character, root, humanoid, token)
        if not ok then
            status("مهام: " .. tostring(reason) .. " | أبحث عن وجهة يابسة")
            patrol(character, root, humanoid, token)
        end
    else
        status("النسب جيدة، أتحرك بين مواقع العشب")
        patrol(character, root, humanoid, token)
    end
    task.wait(0.35)
end

local function stop(message)
    app.running = false
    app.generation = app.generation + 1
    local _, _, h = rig()
    moveStop(h)
    app.target = ""
    app.state = message or "STOPPED"
    log(app.state)
end
local function start(mode)
    stop("تهيئة الوضع " .. mode)
    app.running = true
    app.mode = mode
    app.generation = app.generation + 1
    local token = app.generation
    status("تشغيل " .. mode .. "؛ أتحقق من الطعام والمويه قبل المهمة")
    task.spawn(function()
        while app.alive and app.running and token == app.generation do
            if not app.alive or not app.running or app.generation ~= token then break end
            local ok, err = pcall(runCycle, token)
            if not ok then
                app.lastError = tostring(err)
                status("خطأ محمي: " .. app.lastError)
                local _, _, h = rig()
                moveStop(h)
                task.wait(1.5)
            end
        end
    end)
end
app.shutdown = function()
    app.alive = false
    stop("إيقاف نسخة R47 القديمة")
    if moveBound then pcall(function() RunService:UnbindFromRenderStep(moveBinding) end) end
    for _, con in ipairs(connections) do pcall(function() con:Disconnect() end) end
    if gui and gui.Parent then gui:Destroy() end
end
makeButton("بقاء", 10, 86, function() start("SURVIVAL") end)
makeButton("مهام", 102, 85, function() start("QUESTS") end)
makeButton("تكبير", 193, 85, function() start("GROWTH") end)
makeButton("إيقاف", 284, 108, function() stop("متوقف باختيارك") end)

connect(RunService.Heartbeat, function()
    if not app.alive or not gui.Parent then return end
    local character = player.Character
    local f, w = character and needs(character)
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    local percent = "Food " .. (f and tostring(math.floor(f)) or "?") .. "%  Water " .. (w and tostring(math.floor(w)) or "?") .. "%"
    local first = (app.running and "RUN / " or "STOP / ") .. app.mode .. "  |  " .. percent
    local stateText = app.state
    local targetText = app.target ~= "" and ("Target: " .. app.target .. "\n") or ""
    local extra = app.mode == "QUESTS" and app.questStatus or (app.mode == "GROWTH" and app.growthStatus or app.lastAction)
    info.Text = first .. "\n" .. stateText .. "\n" .. targetText .. tostring(extra)
end)
status("جاهز. اختر البقاء أولا، ثم جرب المهام والتكبير بعد التحقق.")
