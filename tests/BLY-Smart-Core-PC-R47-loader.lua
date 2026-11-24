-- BLY R47 PC loader. Loads only a separate test copy, never the original BLY URL.
local url = "https://raw.githubusercontent.com/alblwymalk01-alt/BLY-2/main/tests/BLY-Smart-Core-PC-TEST-R47.luau"
local function showError(stage, detail)
    local message = "BLY R47 / " .. stage .. ": " .. tostring(detail)
    warn(message)
    pcall(function()
        local player = game:GetService("Players").LocalPlayer
        local pg = player and player:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local old = pg:FindFirstChild("BLY_R47_LoadError")
        if old then old:Destroy() end
        local ui = Instance.new("ScreenGui")
        ui.Name = "BLY_R47_LoadError"
        ui.ResetOnSpawn = false
        ui.DisplayOrder = 9999
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0, 480, 0, 90)
        label.Position = UDim2.new(0.5, -240, 0, 35)
        label.TextWrapped = true
        label.TextSize = 15
        label.BackgroundColor3 = Color3.fromRGB(28, 21, 21)
        label.TextColor3 = Color3.fromRGB(255, 235, 235)
        label.Font = Enum.Font.Code
        label.Text = message
        label.Parent = ui
        ui.Parent = pg
    end)
end
local received, source = pcall(function() return game:HttpGet(url) end)
if not received or type(source) ~= "string" or #source < 30000 then
    showError("DOWNLOAD", received and "invalid-or-short-file" or source)
    return
end
if not source:find("BLY Smart Core R47", 1, true) then
    showError("VERIFY", "unrecognized-source-file")
    return
end
if type(loadstring) ~= "function" then
    showError("COMPILE", "loadstring-unavailable")
    return
end
local code, compileError = loadstring(source)
if type(code) ~= "function" then
    showError("COMPILE", compileError)
    return
end
local ran, runtimeError = pcall(code)
if not ran then showError("STARTUP", runtimeError) end
