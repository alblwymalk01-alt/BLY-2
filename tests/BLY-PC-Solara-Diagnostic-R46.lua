-- BLY PC R46 Solara diagnostic.
-- Diagnostic only: does not alter BLY's original loader or game data.
local SOURCE_URL="https://raw.githubusercontent.com/alblwymalk01-alt/BLY-2/main/tests/BLY-Victory-PC-DryShore-TEST-R46.luau"
local Players=game:GetService("Players")
local player=Players.LocalPlayer
local gui
local label
local function note(stage,description,failed)
  local message="[BLY R46 / "..stage.."] "..tostring(description)
  if failed then warn(message) else print(message) end
  if label then label.Text=message end
end
local okUI,uiErr=pcall(function()
  local pg=player:WaitForChild("PlayerGui",8)
  if not pg then error("PlayerGui unavailable") end
  local old=pg:FindFirstChild("BLY_R46_Diagnostic")
  if old then old:Destroy() end
  gui=Instance.new("ScreenGui")
  gui.Name="BLY_R46_Diagnostic"
  gui.ResetOnSpawn=false
  gui.DisplayOrder=99999
  gui.Parent=pg
  label=Instance.new("TextLabel")
  label.Size=UDim2.new(0,480,0,96)
  label.Position=UDim2.new(0.5,-240,0,36)
  label.BackgroundColor3=Color3.fromRGB(22,22,22)
  label.BackgroundTransparency=0.05
  label.TextColor3=Color3.fromRGB(255,255,255)
  label.Font=Enum.Font.Code
  label.TextSize=16
  label.TextWrapped=true
  label.BorderSizePixel=0
  label.Text="[BLY R46] Starting diagnostic..."
  label.Parent=gui
  local corner=Instance.new("UICorner")
  corner.CornerRadius=UDim.new(0,10)
  corner.Parent=label
end)
if not okUI then warn("[BLY R46] Could not draw checker: "..tostring(uiErr)) end
note("1/4","Checking loadstring",false)
if type(loadstring)~="function" then
 note("FAIL 1/4","Solara loadstring unavailable",true)
 return
end
note("2/4","Downloading R46 source",false)
local fetched,content=pcall(function()return game:HttpGet(SOURCE_URL)end)
if not fetched or type(content)~="string" or #content<100000 then
 note("FAIL 2/4","HttpGet / download failed: "..tostring(content),true)
 return
end
note("3/4","Compiling R46 ("..tostring(#content).." bytes)",false)
local compiled,chunk,compileError=pcall(loadstring,content)
if not compiled then
 note("FAIL 3/4","Compiler crashed: "..tostring(chunk),true)
 return
end
if type(chunk)~="function" then
 note("FAIL 3/4","Syntax/unsupported code: "..tostring(compileError),true)
 return
end
note("4/4","Running R46",false)
local executed,runError=pcall(chunk)
if not executed then
 note("FAIL 4/4","Runtime error: "..tostring(runError),true)
 return
end
note("OK","R46 finished its initial setup. If the BLY UI does not appear, capture the F9 console.",false)
