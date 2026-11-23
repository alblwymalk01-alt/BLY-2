-- SMART NAV TEST R44: PC and Mobile remain separate; NEVER overwrite original BLY script.
-- BLY-PC-SMART-NAV-TEST-R44-20261123 | TEST COPY ONLY | source preserved | herbivores / FoodType=Grass
-- Script creators: S7M x BLY
-- BLY SMART SURVIVAL / MONOCHROME
local CFG={LionAsset="",Radius=240,Footprint=.8,AgentRadius=1.5,
	AgentHeight=5,FoodAttribute="Food",WaterAttribute="Water",Threshold=70,Target=100,
	FoodMaximum=100,WaterMaximum=100,MaxWadeDepth=1.0,
	HomeOnly=false,AntiAFK=true,QueriesPerFrame=36,AutoRun=true,RunMode="Hold",BoostFactor=1.2,QuestsEnabled=false,AutoClaim=true,Background=true,QuerySliceSeconds=.0015,PathCandidates=4,PathInterval=.8,SensorInterval=.05}
local LION_PNG_BASE64=""
local LAUNCHER_PNG_BASE64=""
local BUTTON_PNG_BASE64=""
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
if UIS.TouchEnabled then CFG.QueriesPerFrame=24 CFG.QuerySliceSeconds=.001 end
local Run=game:GetService("RunService")
local PF=game:GetService("PathfindingService")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
for _,name in {"BLY_Mono","BLY_WE","BLY_Graze","BLY_Copy","BLY_MoveTest","BLYPremium","BLY_Diag","BLY_DataCheck"} do
	local old=pg:FindFirstChild(name)
	if old then
		local event=old:FindFirstChild("Shutdown")
		if event and event:IsA("BindableEvent") then event:Fire() end
		old:Destroy()
	end
end
local vim
pcall(function() vim=game:GetService("VirtualInputManager") end)
local alive,running,unlocked,generation=true,false,false,0
local heldW,heldE=false,false
local perf={frame=0,queries=0,peak=0,total=0,frameSeconds=1/60}
local Brain={fillNeeds={Food=false,Water=false},focused=true,keys={},pulseId=0,quests={},visited={},speedInfo="لم تبدأ الحركة",measuredSpeed=0}
function Brain.worldCare()return Brain.mode=="Growth"or Brain.mode=="Quests"or(Brain.mode=="Survival"and not CFG.HomeOnly)end
Brain.backgroundQueryScopes=setmetatable({},{__mode="k"})
Brain.compat={keyRoutes={},pointerRoutes={},heldKeys={},heldPointers={},rejected={},keyAcks={},lastKey=nil,lastPointer=nil}
function Brain.installInputCompatibility()
 local c=Brain.compat local native=vim local virtual
 pcall(function()virtual=UIS:CreateVirtualInput()end)
 if native then
  table.insert(c.keyRoutes,{name="VirtualInputManager",send=function(down,key)return native:SendKeyEvent(down,key,false,game)end})
  table.insert(c.pointerRoutes,{name="VirtualInputManager",send=function(down,x,y,button)return native:SendMouseButtonEvent(x,y,button,down,game,0)end})
 end
 if virtual then
  table.insert(c.keyRoutes,{name="VirtualInput",send=function(down,key)return virtual:SendKey(down,key,false)end})
  table.insert(c.pointerRoutes,{name="VirtualInput",send=function(down,x,y,button)
   local buttons={Enum.UserInputType.MouseButton1,Enum.UserInputType.MouseButton2,Enum.UserInputType.MouseButton3}
   if not buttons[button+1]then error("unsupported mouse button")end
   if down then virtual:SendMousePosition(Vector2.new(x,y))end
   return virtual:SendMouseButton(Vector2.new(x,y),buttons[button+1],down,0)
  end})
 end
 local user pcall(function()user=game:GetService("VirtualUser")end)
 if user then table.insert(c.pointerRoutes,{name="VirtualUser",send=function(down,x,y,button)
  local camera=workspace.CurrentCamera if not camera then return false end
  local method=button==0 and(down and "Button1Down"or "Button1Up")or(button==1 and(down and "Button2Down"or "Button2Up"))
  if not method then return false end if down then user:CaptureController()end
  return user[method](user,Vector2.new(x,y),camera.CFrame)
 end})end
 local press,release=keypress,keyrelease
 if typeof(press)=="function"and typeof(release)=="function"then
  table.insert(c.keyRoutes,{name="KeyPair",send=function(down,key)
   local name=key.Name local special={Space=32,LeftShift=16,RightShift=16,Escape=27,Return=13,Tab=9,Backspace=8}
   local code=special[name]or(#name==1 and string.byte(name:upper()))
   if not code then error("unsupported key")end
   if down then return press(code)else return release(code)end
  end})
 end
 table.insert(c.keyRoutes,{name="HumanoidMove",send=function(down,key)
  if key.Name~="W"then return false end return Brain.motorKey(down)
 end})
 if UIS.TouchEnabled then table.insert(c.keyRoutes,1,table.remove(c.keyRoutes))end
 table.insert(c.keyRoutes,{name="GameActionButton",send=function(down,key)
  if key.Name~="E"then return false end
  if down then return Brain.actionButtonInput and Brain.actionButtonInput()or false end
  return Brain.compatPointer(0,false,0,0)
 end})
 if UIS.TouchEnabled then table.insert(c.keyRoutes,1,table.remove(c.keyRoutes))end
 if #c.keyRoutes>0 or #c.pointerRoutes>0 then
  vim={SendKeyEvent=function(_,down,key)if not Brain.compatKey(key,down)then error("No supported keyboard backend")end end,
   SendMouseButtonEvent=function(_,x,y,button,down)if not Brain.compatPointer(button,down,x,y)then error("No supported pointer backend")end end}
 end
end
function Brain.compatKey(key,down)
 local c=Brain.compat local pinned=c.heldKeys[key]
 if not down then
  if not pinned then return true end
  local ok,err=pcall(pinned.send,false,key)
  if ok and err~=false then c.heldKeys[key]=nil else c.lastError=tostring(err)end
  return ok and err~=false
 end
 if pinned then return true end
 local id=key.Name
 for _,route in c.keyRoutes do
  local tag=route.name..":"..id
  if(c.rejected[tag]or 0)<=os.clock()then
   local ok,err=pcall(route.send,true,key)
   if ok and err~=false then
    c.heldKeys[key]=route c.lastKey=route.name
    if id=="W"then local m=player and player.Character local r=m and m:FindFirstChild("HumanoidRootPart")if r then c.motion={root=r,position=r.Position,at=os.clock()}end end
    return true
   end
   pcall(route.send,false,key)c.rejected[tag]=os.clock()+15 c.lastError=tostring(err)
  end
 end
 return false
end
function Brain.motorKey(down)
 local c=Brain.compat local m=player and player.Character local h=m and m:FindFirstChildOfClass("Humanoid")
 if not down then c.motorHeld=false if h then h:Move(Vector3.zero,false)end return true end
 if not h then return false end
 if down and(not alive or not running or not unlocked or h.Health<=0 or Brain.chatTyping)then return false end
 c.motorHeld=down
 local direction=down and Brain.motionVector and Brain.motionVector()or Vector3.zero
 if not direction then return false end
 h:Move(direction,false)return true
end
function Brain.motorTick()
 local c=Brain.compat local m=player and player.Character local r=m and m:FindFirstChild("HumanoidRootPart")
 local held=c.heldKeys[Enum.KeyCode.W]
 if held and c.motion and c.motion.root==r and running and unlocked and not Brain.chatTyping then
  local d=r.Position-c.motion.position
  if Vector3.new(d.X,0,d.Z).Magnitude>.25 then c.motion.position=r.Position c.motion.at=os.clock()
  elseif os.clock()-c.motion.at>1.2 then
   c.rejected[held.name..":W"]=os.clock()+15
   if Brain.compatKey(Enum.KeyCode.W,false)then Brain.compatKey(Enum.KeyCode.W,true)end
  end
 end
 if not c.motorHeld then return end
 local h=m and m:FindFirstChildOfClass("Humanoid")
 if not alive or not running or not unlocked or Brain.chatTyping or not h or not r or h.Health<=0 then c.motorHeld=false if h then h:Move(Vector3.zero,false)end return end
 local direction=Brain.motionVector and Brain.motionVector()
 if not direction then return end
 if CFG.HomeOnly and Brain.mode=="Survival"and Brain.homeInside and Brain.homeInside(r.Position)
  and not Brain.homeSegment(r.Position,r.Position+direction*1.5)then h:Move(Vector3.zero,false)return end
 h:Move(direction,false)
end
function Brain.compatPointer(button,down,x,y)
 local c=Brain.compat local pinned=c.heldPointers[button]
 if not down then
  if not pinned then return true end
  local ok,err=pcall(pinned.route.send,false,pinned.x,pinned.y,button)
  if ok and err~=false then c.heldPointers[button]=nil else c.lastError=tostring(err)end return ok and err~=false
 end
 if pinned then return true end
 for _,route in c.pointerRoutes do
  local tag=route.name..":pointer:"..tostring(button)
  if(c.rejected[tag]or 0)<=os.clock()then
   local ok,err=pcall(route.send,true,x,y,button)
   if ok and err~=false then c.heldPointers[button]={route=route,x=x,y=y}c.lastPointer=route.name return true end
   pcall(route.send,false,x,y,button)c.rejected[tag]=os.clock()+15 c.lastError=tostring(err)
  end
 end
 return false
end
function Brain.requestFunction()
 local fn=request or http_request
 if typeof(fn)~="function"then for _,container in {syn or false,http or false,fluxus or false}do if typeof(container)=="table"and typeof(container.request)=="function"then fn=container.request break end end end
 if typeof(fn)~="function"then return end
 return function(options)
  local response=fn(options)
  if typeof(response)=="table"then
   local r=table.clone(response)r.StatusCode=tonumber(r.StatusCode or r.Status or r.status_code or r.status)
   r.Body=r.Body or r.body r.Headers=r.Headers or r.headers return r
  end
  return response
 end
end
Brain.installInputCompatibility()
do
 local function tick()local ok,err=pcall(Brain.motorTick)if not ok then Brain.compat.lastError=tostring(err)end end
 local bound=pcall(function()Run:BindToRenderStep("BLY_COMPAT_MOVE",Enum.RenderPriority.Character.Value+1,tick)end)
 Brain.compat.motorBound=bound
 if not bound then Brain.compat.motorConnection=Run.Heartbeat:Connect(tick)end
end
-- Pure policy:
Brain.policy={}
function Brain.policy.choose(pending,food,water,current,threshold,target)
 if food<threshold then pending.Food=true end
 if water<threshold then pending.Water=true end
 if food>=target then pending.Food=false end
 if water>=target then pending.Water=false end
 if pending.Food and pending.Water and math.min(food,water)<25 then
  if food+5<water then return "Food" end
  if water+5<food then return "Water" end
 end
 if current=="Food"and food>=target and water<target then pending.Water=true return "Water"end
 if current=="Water"and water>=target and food<target then pending.Food=true return "Food"end
 if current=="Food" and pending.Food then
  return "Food"
 end
 if current=="Water" and pending.Water then
  return "Water"
 end
 if pending.Food and pending.Water then return food<water and "Food" or "Water" end
 if pending.Food then return "Food" end
 if pending.Water then return "Water" end
end
function Brain.policy.shouldRestForTravel(kind,food,water)
 if (kind=="Food" or kind=="Water" or kind=="ReturnHome") and food and water and (food<CFG.Threshold or water<CFG.Threshold) then return false end
 return true
end
function Brain.policy.afterAttempt(kind,outcome,food,water,pending)
 if outcome~="plateau" and outcome~="no_increase" and outcome~="other_need" then return end
 local other=kind=="Food" and "Water" or "Food"
 local amount=other=="Food" and food or water
 local own=kind=="Food" and food or water
 if own and own<CFG.Target then pending[kind]=true return kind end
 if amount and own and (amount<CFG.Threshold or pending[other]) then
  pending[other]=true
  return other
 end
end
function Brain.policy.canDefer(kind,food,water)
 local own=kind=="Food" and food or water
 local other=kind=="Food" and water or food
 return own>=CFG.Target or (other<CFG.Threshold and (other<25 or other+10<own))
end
function Brain.policy.questResource(objective,food,water,target)
 if not objective or not objective.passive then return end
 if objective.kind=="Food" and food<target-.2 then return "Food" end
 if objective.kind=="Water" and water<target-.2 then return "Water" end
end
function Brain.policy.coverageFresh(age,travel,horizon,speed)
 return age<=.5 and horizon-travel>math.max(.2,speed*.08)
end
function Brain.policy.pathRetry(goal,now,position)
 if not goal.pathMissAt or (position-goal.pathMissPosition).Magnitude>2 then
  goal.pathMissAt=now goal.pathMissPosition=position goal.pathMisses=0
 end
 goal.pathMisses+=1
 return goal.pathMisses>=4 and now-goal.pathMissAt>=6
end
function Brain.policy.heading(previous,dot)
 if dot>.94 then return true end
 if dot<.65 then return false end
 return previous==true
end
function Brain.policy.groupDue(enabled,needed,now,nextAt)
 return enabled and needed and now>=(nextAt or 0)
end
function Brain.policy.isResting(value,flag)
 if flag==true then return true end
 local lower=string.lower(tostring(value or ""))
 return lower:find("rest",1,true)~=nil or lower=="sitting" or lower=="lying"
end
function Brain.policy.refillOutcome(amount,target,started,now,lastIncrease,firstIncrease,finishedFood,other)
 if amount>=target then return "target" end
 if firstIncrease and now-lastIncrease>=(finishedFood and 1.5 or 6) then return "plateau" end
end
-- Independent UI;
Brain.nativeChat={saved={},open=false,busy=false}
function Brain.chatWrite(object,property,value)
 if not object then return false end
 local ok,previous=pcall(function() return object[property] end) if not ok then return false end
 local row for _,entry in Brain.nativeChat.saved do if entry.object==object and entry.property==property then row=entry break end end
 local written=pcall(function() object[property]=value end)
 if written then if not row then row={object=object,property=property,previous=previous} table.insert(Brain.nativeChat.saved,row) end row.ours=value end
 return written
end
function Brain.restoreNativeChat()
 for _,entry in Brain.nativeChat.saved do pcall(function() if entry.object[entry.property]==entry.ours then entry.object[entry.property]=entry.previous end end) end
 Brain.nativeChat.saved={}
end
function Brain.chatPermission()
 local ok,allowed=pcall(function() return game:GetService("TextChatService"):CanUserChatAsync(player.UserId) end)
 return ok and allowed==true
end
function Brain.chatCanUse(provider,nativeAllowed,licensed)
 return (provider=="global" or provider=="server") and licensed==true
end
function Brain.chatAccess(provider)
 local licensed=unlocked and Brain.license and Brain.license.secret~=nil and (not Brain.licenseExpires or os.clock()<Brain.licenseExpires)
 return Brain.chatCanUse(provider,false,licensed==true)
end
function Brain.chatRoom(provider)
 if provider=="global" then return "global" end
 return "server:"..tostring(game.PlaceId)..":"..(game.JobId~="" and game.JobId or "studio")
end
function Brain.chatHTTP(path,payload)
 local fn=Brain.requestFunction()
 if typeof(fn)~="function" or not Brain.license or not Brain.license.secret then return nil,"الاتصال غير جاهز" end
 payload.userId=player.UserId payload.secret=Brain.license.secret
 local job={}
 task.spawn(function()
  local ok,r=pcall(fn,{Url=Brain.license.base..path,Method="POST",Headers={["Content-Type"]="application/json"},Body=game:GetService("HttpService"):JSONEncode(payload),Timeout=10})
  if ok and typeof(r)=="table" then
   local decoded,data=pcall(function() return game:GetService("HttpService"):JSONDecode(r.Body) end)
   local code=tonumber(r.StatusCode or r.Status) or 0
   if decoded and code>=200 and code<300 then job.data=data else job.error=decoded and data.error or "تعذر الاتصال بالشات" job.retryAfter=decoded and tonumber(data.retryAfter) end
  else job.error="تعذر الاتصال بالشات" end
  job.done=true
 end)
 local untilAt=os.clock()+12
 while alive and not job.done and os.clock()<untilAt do task.wait(.1) end
 return job.data,job.error or "تأخر الاتصال؛ جرّب بعد شوي",job.retryAfter
end
local aim,cameraState
Brain.motionVector=function()return aim end
local activeKind
local lastE="لم يُختبر E داخل الماب بعد"
local waterSamples=0
local waterScanDone=false
local knownShore
local knownDrinkPosition
local lastConsumed
local decisionMode="قرار محلي • أولويات الحاجة + تحقق التفاعل + إعادة التخطيط"
local inputTrace
local links={}
local avoided={}
local imageState="تجهيز صورة الأسد…"
local currentState="متوقف"
local gui,status,debugText,mainToggle,launcher,questToggle
local queryScopes=setmetatable({},{__mode="k"})
local workFrame,workCount,sliceStart=-1,0,0
local pathBusy,nextPathAt=false,0
local safetyBatch=false
local observedDrinkAt=0
local function on(signal,callback)
	local c=signal:Connect(callback) table.insert(links,c) return c
end
Brain.afk={busy=false,lastAt=-math.huge,status="منع الخمول جاهز"}
pcall(function() Brain.afk.service=game:GetService("VirtualUser") end)
function Brain.afkPulse()
 if not CFG.AntiAFK or not alive or not running or not unlocked or Brain.afk.busy then return false end
 if os.clock()-Brain.afk.lastAt<55 then return false end
 local camera=workspace.CurrentCamera local service=Brain.afk.service
 if not camera or not service then Brain.afk.status="منع الخمول غير مدعوم" return false end
 Brain.afk.busy=true Brain.afk.lastAt=os.clock()
 local point=Vector2.zero local view=camera.CFrame
 local ok=pcall(function() service:CaptureController() service:Button2Down(point,view) end)
 task.delay(.08,function()
  local released=pcall(function() service:Button2Up(point,view) end)
  Brain.afk.busy=false Brain.afk.status=(ok and released) and "تم إرسال إشارة منع الخمول" or "المشغّل رفض منع الخمول"
 end)
 return ok
end
on(player.Idled,function() Brain.afkPulse() end)
on(UIS.InputBegan,function(input,processed)
	if input.KeyCode==Enum.KeyCode.E and inputTrace and os.clock()<=inputTrace.untilTime then
		inputTrace.began=true inputTrace.processed=processed
	end
end)
on(UIS.InputEnded,function(input,processed)
	if input.KeyCode==Enum.KeyCode.E and inputTrace and os.clock()<=inputTrace.untilTime then inputTrace.ended=true end
end)
local function new(class,props,parent)
	local o=Instance.new(class) for k,v in pairs(props) do o[k]=v end o.Parent=parent return o
end
local TweenService=game:GetService("TweenService")
local uiTweens={}
local function tweenUI(object,properties,duration)
	local old=uiTweens[object]
	if old then old:Cancel() end
	local tween=TweenService:Create(object,TweenInfo.new(duration or .14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),properties)
	uiTweens[object]=tween tween:Play()
end
local white=Color3.fromRGB(239,245,249)
local gray=Color3.fromRGB(105,115,125)
local dark=Color3.fromRGB(7,9,12)
local function round(o,n) new("UICorner",{CornerRadius=UDim.new(0,n or 10)},o) end
function Brain.uiFont(value)
 for _,code in utf8.codes(tostring(value or "")) do if code>=0x600 and code<=0x6ff then return Enum.Font.Arial end end
 return Enum.Font.GothamMedium
end
local function text(parent,value,x,y,w,h,size)
	return new("TextLabel",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
		Text=value,TextColor3=white,TextWrapped=true,TextSize=size or 14,Font=Brain.uiFont(value)},parent)
end
Brain.buttonSkins={}
function Brain.selectButton(b,selected)
 local skin=Brain.buttonSkins[b] if not skin then return end
 skin.selected=selected
 local active=selected or skin.primary
 tweenUI(skin.tint,{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=active and .10 or .24},.16)
 tweenUI(skin.border,{Color=active and Color3.fromRGB(171,250,255) or Color3.fromRGB(64,174,189),Transparency=active and .08 or .55,Thickness=active and 1.3 or 1},.16)
 if skin.gradient then
  skin.gradient.Rotation=90
  skin.gradient.Color=ColorSequence.new({
   ColorSequenceKeypoint.new(0,active and Color3.fromRGB(59,173,191) or Color3.fromRGB(15,64,73)),
   ColorSequenceKeypoint.new(.40,active and Color3.fromRGB(5,41,48) or Color3.fromRGB(4,28,34)),
   ColorSequenceKeypoint.new(.84,active and Color3.fromRGB(2,28,33) or Color3.fromRGB(3,16,20)),
   ColorSequenceKeypoint.new(1,active and Color3.fromRGB(42,205,220) or Color3.fromRGB(9,63,73))})
 end
end
function Brain.primaryButton(b)
 local skin=Brain.buttonSkins[b]
 if skin then
  skin.primary=true b.TextSize=20
  Brain.selectButton(b,skin.selected)
 end
 return b
end
local function button(parent,value,x,y,w,callback)
 local b=new("TextButton",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,36),BackgroundColor3=Color3.fromRGB(12,14,17),BackgroundTransparency=0,AutoButtonColor=false,
  TextColor3=white,Text=value,TextSize=14,TextTransparency=1,Font=Brain.uiFont(value),BorderSizePixel=0},parent)
 round(b,10)
 local image=new("ImageLabel",{Name="BLY_ButtonArtwork",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image=Brain.buttonTexture or "",ScaleType=Enum.ScaleType.Stretch,ImageTransparency=.88,ImageColor3=Color3.fromRGB(198,204,208),Active=false,BorderSizePixel=0},b)
 round(image,10)
 local tint=new("Frame",{Name="BLY_ButtonShade",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(12,14,17),BackgroundTransparency=.14,BorderSizePixel=0,Active=false},b)
 round(tint,10)
 local glint=new("Frame",{Name="BLY_ButtonGlint",Position=UDim2.new(0,10,0,1),Size=UDim2.new(1,-20,0,1),BackgroundColor3=white,BackgroundTransparency=.55,BorderSizePixel=0,Active=false,ZIndex=b.ZIndex+2},b)
 new("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.1),NumberSequenceKeypoint.new(1,1)})},glint)
 local caption=new("TextLabel",{Name="BLY_ButtonCaption",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text=value,TextColor3=white,TextSize=14,Font=b.Font,Active=false,TextStrokeTransparency=1},b)
 local border=new("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=Color3.fromRGB(191,197,201),Transparency=.84,Thickness=1},b)
 local gradient=new("UIGradient",{Rotation=78},tint)
 Brain.buttonSkins[b]={image=image,tint=tint,border=border,caption=caption,gradient=gradient,selected=false}
 Brain.selectButton(b,false)
 local function sync()
  caption.Text=b.Text caption.TextColor3=b.TextColor3 caption.TextSize=b.TextSize caption.Font=b.Font
  caption.TextWrapped=b.TextWrapped caption.TextXAlignment=b.TextXAlignment caption.TextYAlignment=b.TextYAlignment
  image.ZIndex=b.ZIndex tint.ZIndex=b.ZIndex+1 caption.ZIndex=b.ZIndex+2 glint.ZIndex=b.ZIndex+2
 end
 for _,property in {"Text","TextColor3","TextSize","Font","TextWrapped","TextXAlignment","TextYAlignment","ZIndex"} do on(b:GetPropertyChangedSignal(property),sync) end
 local corner=b:FindFirstChildOfClass("UICorner")
 on(corner:GetPropertyChangedSignal("CornerRadius"),function()
  image:FindFirstChildOfClass("UICorner").CornerRadius=corner.CornerRadius
  tint:FindFirstChildOfClass("UICorner").CornerRadius=corner.CornerRadius
 end)
 sync()
 on(b.MouseEnter,function() tweenUI(tint,{BackgroundTransparency=.02},.12) tweenUI(border,{Transparency=.42},.12) end)
 on(b.MouseLeave,function() Brain.selectButton(b,Brain.buttonSkins[b].selected) end)
 on(b.MouseButton1Down,function() tweenUI(tint,{BackgroundTransparency=0},.07) end)
 on(b.MouseButton1Up,function() Brain.selectButton(b,Brain.buttonSkins[b].selected) end)
 on(b.Activated,callback) return b
end
local function state(message)
	currentState=message
	if status then
		local display=message:gsub("Food","الأكل"):gsub("Water","الشرب")
		if message:find("InputBegan",1,true) then display="تعذر بدء التعبئة؛ أعيد تقييم الموضع" end
		status.Text=display
	end
	if mainToggle then mainToggle.Text=(running and Brain.mode=="Survival" or Brain.requestedMode=="Survival") and "إيقاف البقاء" or "تشغيل البقاء" end
 if questToggle then questToggle.Text=(running and Brain.mode=="Quests" or Brain.requestedMode=="Quests") and "إيقاف المهمات" or "تشغيل المهمات" end
end
local pressSerial=0
local keyPresses={}
local function inputOwnerValid()
	local owner=queryScopes[coroutine.running()]
	return owner==nil or owner==generation
end
Brain.traceRows={} Brain.traceStarted=os.clock() Brain.traceReason=nil
function Brain.motionTrace(event,detail)
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local goal=activeKind and Brain.resourceGoals and Brain.resourceGoals[activeKind]
	local row={t=math.floor((os.clock()-Brain.traceStarted)*100)/100,event=event,detail=detail,
		generation=generation,kind=activeKind,focused=Brain.focused,heldW=heldW,
		goal=goal and {goal.position.X,goal.position.Y,goal.position.Z} or nil}
	if root then
		row.position={root.Position.X,root.Position.Y,root.Position.Z}
		row.speed=Vector2.new(root.AssemblyLinearVelocity.X,root.AssemblyLinearVelocity.Z).Magnitude
	end
	if character then
		row.movement=character:GetAttribute("MovementState") row.targetSpeed=character:GetAttribute("TargetSpeed")
		row.shouldRun=character:GetAttribute("ShouldRun") row.stamina=character:GetAttribute("Stamina")
		row.food=character:GetAttribute("Food") row.water=character:GetAttribute("Water")
	end
	table.insert(Brain.traceRows,row)
	if #Brain.traceRows>240 then table.remove(Brain.traceRows,1) end
end
function Brain.exportTrace()
	local character=player.Character
	local bounds
	if character then pcall(function() local _,size=character:GetBoundingBox() bounds={size.X,size.Y,size.Z} end) end
	local payload={shore=Brain.resourceGoals.Water and Brain.resourceGoals.Water.approachOutcome,growthUI=Brain.growth and Brain.growth.uiReport,growth=Brain.growth and Brain.growth.reading,waterSamples=waterSamples,routeReason=Brain.routeReason,anywhereStatus=Brain.anywhereSummary,build="BLY-PC-SMART-NAV-TEST-R44-20261123",mode=Brain.mode,place=game.PlaceId,animal=character and character:GetAttribute("AnimalName"),
		insideHome=character and Brain.homeInside(character:GetPivot().Position),homeReturn=Brain.homeReturnOutcome,homePlan=Brain.homePlan,resourceScan=Brain.resourceScan,bodyBounds=bounds,agent={radius=CFG.AgentRadius,height=CFG.AgentHeight,footprint=CFG.Footprint},
		runMode=CFG.RunMode,boost=CFG.BoostFactor,inputBackend=Brain.compat.lastKey,pointerBackend=Brain.compat.lastPointer,inputError=Brain.compat.lastError,escapeTransport=Brain.timing and Brain.timing.lastTransport,nearbySurvival=not CFG.HomeOnly,antiIdle=Brain.afk and Brain.afk.status,zone=player:GetAttribute("ZoneName"),
		foodMarkers=Brain.carcassMarkers and Brain.carcassMarkers.report,lastWalk=Brain.lastWalkResult,goalReason=Brain.goalReason,lastState=currentState,controlAge=Brain.controlTickAt and os.clock()-Brain.controlTickAt or nil,
		groupStatus=Brain.groupStatus,groupUI=Brain.groupIntegration and Brain.groupIntegration() or nil,rows=Brain.traceRows}
	return game:GetService("HttpService"):JSONEncode(payload)
end
Brain.traceSavedAt=0
function Brain.saveMotionTrace()
 if typeof(writefile)~="function" or os.clock()-Brain.traceSavedAt<5 then return end
 if not running and not(Brain.growth and Brain.growth.active)and Brain.traceSavedGeneration==generation then return end
 Brain.traceSavedAt=os.clock() Brain.traceSavedGeneration=generation
 pcall(function() writefile("BLY-Anywhere-PC-motion-latest.json",Brain.exportTrace()) end)
end
local function send(key,down,force,expectedPress)
	if not force and not inputOwnerValid() then return false end
 if down and Brain.chatTyping then return false end
	if expectedPress~=nil then
		local current=keyPresses[key]
		if not current or current.serial~=expectedPress then return false end
	end
	if not vim then if down then error("إرسال الأزرار غير متاح في المشغّل") end return false end
	local ok=pcall(function() vim:SendKeyEvent(down,key,false,game) end)
	if not ok and down then error("المشغّل رفض إرسال الزر") end
	if not ok then return false end
	if key==Enum.KeyCode.W or key==Enum.KeyCode.E or key==Enum.KeyCode.LeftShift then Brain.motionTrace(down and "key_down" or "key_up",key.Name.." / "..tostring(Brain.traceReason)) end
	if down then
		pressSerial+=1 keyPresses[key]={serial=pressSerial,generation=generation}
		return pressSerial
	end
	keyPresses[key]=nil
	return true
end
function Brain.pulse(key,duration)
	if not inputOwnerValid() then return false end
	local press=send(key,true)
	if not press then return false end
	Brain.keys[key]=press
	task.delay(math.clamp(duration or .09,.02,.2),function()
		if Brain.keys[key]==press then
			send(key,false,true,press)
			if Brain.keys[key]==press then Brain.keys[key]=nil end
		end
	end)
 return true
end
function Brain.releaseKeys()
	if not inputOwnerValid() then return end
	for key,press in Brain.keys do send(key,false,true,press) Brain.keys[key]=nil end
end
function Brain.setShift(down)
 if not inputOwnerValid()then return false end
 if Brain.shiftHeld==down then return true end
 local ok,result=pcall(send,Enum.KeyCode.LeftShift,down)
 if ok and result then Brain.shiftHeld=down return true end
 if down then Brain.shiftHeld=false Brain.compat.sprintUntil=os.clock()+15 Brain.speedInfo="مشي / احتياط طاقة"end
 return false
end
function Brain.staminaPercent(model)
 local amount=model:GetAttribute("Stamina")
 if typeof(amount)~="number" or amount~=amount then return end
 local maximum=model:GetAttribute("MaxStamina") or model:GetAttribute("StaminaMax")
 if typeof(maximum)=="number" and maximum>0 then amount=amount/maximum*100 end
 return math.clamp(amount,0,100)
end
function Brain.resetSpeed(model)
	Brain.speedModel=model Brain.shiftHeld=false Brain.runToggled=false
	Brain.speedInfo="الركض: Shift" Brain.boostBase=nil Brain.basePeak=0
	Brain.calibrateUntil=os.clock()+1 Brain.energyRest=false
end
function Brain.restoreSpeed()
	Brain.setShift(false)
	if Brain.runToggled and Brain.speedModel==player.Character then Brain.pulse(Enum.KeyCode.LeftShift) end
	Brain.runToggled=false
end
function Brain.speedTick(root,model,allowBoost,allowRun)
 Brain.boostIntent=nil
	local velocity=root.AssemblyLinearVelocity
	local horizontal=Vector3.new(velocity.X,0,velocity.Z)
	local speed=horizontal.Magnitude Brain.measuredSpeed=speed
	local stamina=Brain.staminaPercent(model)
	if model:GetAttribute("StaminaRanOut")==true or (typeof(stamina)=="number" and stamina<25) then Brain.energyRest=true end
	if typeof(stamina)=="number" and stamina>=50 and model:GetAttribute("StaminaRanOut")~=true then Brain.energyRest=false end
	local canRun=CFG.AutoRun and (Brain.compat.sprintUntil or 0)<=os.clock() and heldW and (not Brain.shoreNudge or Brain.rescuing) and not Brain.energyRest and allowRun~=false
	if canRun and not Brain.wasRunning then Brain.runRequestedAt=os.clock() Brain.boostBase=nil Brain.basePeak=speed end
 Brain.wasRunning=canRun
 if canRun then Brain.basePeak=math.max(Brain.basePeak or 0,speed) end
 if CFG.RunMode=="Hold" then Brain.setShift(canRun)
	else
  local movement=string.lower(tostring(model:GetAttribute("MovementState") or ""))
  local observedFast=movement:find("run",1,true)~=nil or movement:find("sprint",1,true)~=nil
  local observedWalk=movement=="walking" or movement=="walk" or movement=="trotting" or movement=="trot"
  if canRun and (observedFast or (Brain.runToggled and not observedWalk)) then Brain.runToggled=true
  elseif canRun~=Brain.runToggled or (canRun and observedWalk and os.clock()-(Brain.lastRunToggleAt or -10)>2) then
   if os.clock()-(Brain.lastRunToggleAt or -10)>.35 then
    Brain.pulse(Enum.KeyCode.LeftShift) Brain.runToggled=canRun Brain.lastRunToggleAt=os.clock()
   end
  end
 end
	Brain.speedInfo=canRun and "الركض بـ Shift" or "مشي / احتياط طاقة"
	if CFG.BoostFactor<=1 then
		if canRun then Brain.basePeak=math.max(Brain.basePeak or 0,speed) end
		return
	end
	if os.clock()<Brain.calibrateUntil or os.clock()-(Brain.runRequestedAt or os.clock())<.8 then Brain.basePeak=math.max(Brain.basePeak,speed) return end
	if not canRun or not allowBoost or not aim or speed<2 or horizontal.Unit:Dot(aim)<.96 then return end
	if os.clock()-(Brain.lastSafeAt or 0)>.15 then return end
	if not Brain.boostBase then
		local declared=model:GetAttribute("TargetSpeed")
		local base=typeof(declared)=="number" and declared>2 and declared or (Brain.basePeak or 0)
		if base<=2 then return end
		Brain.boostBase=math.min(math.max(base,Brain.basePeak or 0,speed),80)
	end
	local target=math.min(Brain.boostBase*CFG.BoostFactor,Brain.boostBase+8,80)
	Brain.boostTarget=target
 Brain.boostIntent={root=root,model=model,token=generation,direction=horizontal.Unit,target=target,base=Brain.boostBase,issued=os.clock()}
end
local function releaseW(reason)
	if not inputOwnerValid() then return end
 Brain.boostIntent=nil
	if heldW then Brain.traceReason=reason or "unspecified" send(Enum.KeyCode.W,false) heldW=false Brain.traceReason=nil end
	Brain.setShift(false)
	if CFG.RunMode=="Toggle" and Brain.runToggled then Brain.pulse(Enum.KeyCode.LeftShift) Brain.runToggled=false end
end
local function release()
	if not inputOwnerValid() then return end
	releaseW()
	if heldE then send(Enum.KeyCode.E,false) heldE=false end
	Brain.releaseKeys()
end
on(Run.Heartbeat,function(dt)
	perf.frame+=1 perf.frameSeconds=perf.frameSeconds*.9+dt*.1
end)
local function queryBudget()
 local planning=Brain.resourcePlanning
 if planning and planning.worker==coroutine.running() and planning.token==generation then planning.beat=os.clock() end
	local owner=queryScopes[coroutine.running()]
	local function check()
		if not alive or (owner~=nil and owner~=generation) then error("BLY_QUERY_CANCELLED") end
  local background=Brain.backgroundQueryScopes[coroutine.running()]
  if background and background.route.prefetchTicket~=background.ticket then error("BLY_QUERY_CANCELLED") end
	end
	check()
	if safetyBatch then
		workCount+=1 perf.total+=1 perf.queries=workCount perf.peak=math.max(perf.peak,workCount)
		return
	end
	while true do
		if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
		local quota=CFG.QueriesPerFrame
  if Brain.backgroundQueryScopes[coroutine.running()] then quota=math.max(1,quota-21) end
  if workCount<quota and os.clock()-sliceStart<CFG.QuerySliceSeconds then break end
		Run.Heartbeat:Wait() check()
	end
	workCount+=1 perf.total+=1 perf.queries=workCount perf.peak=math.max(perf.peak,workCount)
end
local function restoreCamera()
	Run:UnbindFromRenderStep("BLY_MONO_STEER")
	if cameraState and cameraState.camera.Parent then
		local camera=cameraState.camera
		camera.CameraType=cameraState.kind camera.CameraSubject=cameraState.subject camera.CFrame=cameraState.cframe
	end
	cameraState=nil aim=nil Brain.steerCamera=nil
end
local function stop(message,preserveRequest)
	if not inputOwnerValid() then return end
 if not preserveRequest then Brain.requestedMode=nil Brain.fillKind=nil Brain.completedFill=nil end
 if Brain.growth and Brain.growth.active and not preserveRequest and not Brain.growth.transitioning and not Brain.growth.driving then Brain.growth.active=false Brain.growth.sequence+=1 end
	if Brain.leaveRest and player.Character then Brain.leaveRest(player.Character) end
	running=false activeKind=nil Brain.resourceZone=nil Brain.nearSafetyPending=nil Brain.shoreNudge=false Brain.rescuing=false Brain.escapeReturn=false Brain.questSwimming=false Brain.mode=nil CFG.QuestsEnabled=false
	release() Brain.restoreSpeed()
	if Brain.actionOwned and Brain.stopActionVisible and Brain.stopActionVisible() then Brain.pulse(Enum.KeyCode.E) end
	Brain.actionOwned=false restoreCamera()
	if Brain.restoreQuestPanel then Brain.restoreQuestPanel(Brain.activeQuestPanelLease) end
	generation+=1
	if Brain.saveAtlas then Brain.saveAtlas() end
	if message then state(message) end
end
local function rig()
	local model=player.Character
	if not model then return end
	return model,model:FindFirstChild("HumanoidRootPart"),model:FindFirstChildOfClass("Humanoid")
end
local function valid(token,model)
 local m,r,h=rig()
 local allowed=alive and unlocked and (not Brain.licenseExpires or os.clock()<Brain.licenseExpires) and running and generation==token and m==model and r and h and h.Health>0
  and (not cameraState or workspace.CurrentCamera==cameraState.camera)
 if allowed then Brain.workerBeatAt=os.clock() end
 return allowed
end
function Brain.applyBoost()
 local intent=Brain.boostIntent
 if not intent then return end
 if not heldW or not valid(intent.token,intent.model) or os.clock()-intent.issued>.2 or os.clock()-(Brain.lastSafeAt or 0)>.15 then Brain.boostIntent=nil return end
 if Brain.shoreNudge or Brain.energyRest or (Brain.timing and Brain.timing.active) then Brain.boostIntent=nil return end
 local _,root=rig()
 if root~=intent.root then Brain.boostIntent=nil return end
 local velocity=root.AssemblyLinearVelocity
 local horizontal=Vector3.new(velocity.X,0,velocity.Z) local speed=horizontal.Magnitude
 if speed<2 or horizontal.Unit:Dot(intent.direction)<.95 then return end
 local target=math.min(intent.target,intent.base+8,80)
 if speed>=target then return end
 local boosted=horizontal.Unit*target
 root.AssemblyLinearVelocity=Vector3.new(boosted.X,velocity.Y,boosted.Z)
 Brain.boostAppliedAt=os.clock()
end
on(Run.PreSimulation,function()
 if Brain.boostIntent then
  local ok,err=pcall(Brain.applyBoost)
  if not ok then Brain.boostIntent=nil Brain.speedInfo="تعذر تطبيق الزيادة: "..tostring(err) end
 end
end)
function Brain.abandonPath(job)
 if not job or job.cancelled then return end
 job.cancelled=true
 if pathBusy==job then pathBusy=false nextPathAt=os.clock()+CFG.PathInterval end
 if job.thread and typeof(task.cancel)=="function" then pcall(task.cancel,job.thread) end
end
local function computePath(path,from,to,token,model)
 if not Brain.backgroundQueryScopes[coroutine.running()] then releaseW("path_planning") end
 local waiting=os.clock()
 while pathBusy or os.clock()<nextPathAt do
  if type(pathBusy)=="table" and os.clock()-pathBusy.started>3.5 then Brain.abandonPath(pathBusy) end
  if not valid(token,model) or os.clock()-waiting>2 then return false end
  task.wait(.05)
 end
 if not valid(token,model) then return false end
 local job={done=false,ok=false,started=os.clock(),cancelled=false}
 pathBusy=job
 job.thread=task.spawn(function()
  if job.cancelled then return end
  local ok=pcall(function()path:ComputeAsync(from,to)end)
  job.ok=ok and not job.cancelled job.done=true
  if pathBusy==job then pathBusy=false nextPathAt=os.clock()+CFG.PathInterval end
 end)
 local deadline=os.clock()+3
 while not job.done and valid(token,model) and os.clock()<deadline do task.wait(.05) end
 if not job.done then Brain.abandonPath(job) end
 return job.done and job.ok and not job.cancelled and valid(token,model)
end
local function visible(o)
	if not o:IsDescendantOf(pg) or (gui and o:IsDescendantOf(gui)) or ((o:IsA("TextLabel") or o:IsA("TextBox")) and o.TextTransparency>=.95)
		or o.AbsoluteSize.X<1 or o.AbsoluteSize.Y<1 then return false end
	local a=o
	while a and a~=pg do
		if a:IsA("GuiObject") and not a.Visible then return false end
		if a:IsA("ScreenGui") and not a.Enabled then return false end
		if a:IsA("CanvasGroup") and a.GroupTransparency>=.95 then return false end
		a=a.Parent
	end
	return true
end
local function classify(o,kind)
	local value=o.Text
	if o:IsA("TextLabel") then
		local ok,rendered=pcall(function() return o.ContentText end)
		if ok then value=value.." "..rendered end
	end
	value=string.lower(value):gsub("<[^>]->","")
	local observed=o.Name=="RightTextLabel" and o.Parent and o.Parent.Name=="KeyboardGamepadFrame"
	local words=kind=="Food" and {"eat","eating","graze","grazing","للأكل","للاكل","للرعي"} or {"drink","drinking","للشرب","اشرب","لشرب"}
	for _,word in words do
		if string.match(word,"^[a-z]+$") then
			if string.find(value,"%f[%a]"..word.."%f[%A]") then return observed and 2 or 1 end
		elseif string.find(value,word,1,true) then return observed and 2 or 1 end
	end
	return 0
end
local sourceCache,lastLocate=nil,-math.huge
local sensorAt,sensorLabel,sensorKind=-math.huge,nil,nil
local function usableInteraction(source)
 if not source or not visible(source) then return false end
 local value=string.lower(source.Text):gsub("<[^>]->","")
 return classify(source,"Food")>0 or classify(source,"Water")>0 or value:find("stop eating",1,true)~=nil or value:find("stop drinking",1,true)~=nil
  or value:find("إيقاف الأكل",1,true)~=nil or value:find("إيقاف الشرب",1,true)~=nil
end
function Brain.observedActionKind(source)
 if not source then return end
 local value=string.lower(source.Text):gsub("<[^>]->","")
 if value:find("drinking",1,true) or value:find("الشرب",1,true) or classify(source,"Water")>0 then return "Water" end
 if value:find("eating",1,true) or value:find("grazing",1,true) or value:find("الأكل",1,true) or classify(source,"Food")>0 then return "Food" end
end
local function observedSource(force)
 if sourceCache and sourceCache:IsDescendantOf(pg) and usableInteraction(sourceCache) then return sourceCache end
 sourceCache=nil
 if not force and os.clock()-lastLocate<.15 then return end
 lastLocate=os.clock()
 local screen=pg:FindFirstChild("EatDrinkDisplayScreenGui")
 if not screen then return end
 local main=screen:FindFirstChild("MainFrame")
 local keyboard=main and main:FindFirstChild("KeyboardGamepadFrame")
 local preferred=keyboard and keyboard:FindFirstChild("RightTextLabel")
 if usableInteraction(preferred) then sourceCache=preferred return preferred end
 local queue={screen} local index=1 local visited=0
 while index<=#queue and visited<64 do
  local node=queue[index] index+=1
  for _,child in node:GetChildren() do
   visited+=1 if visited>64 then break end queue[#queue+1]=child
   if child:IsA("TextLabel") and visible(child) then
    local value=string.lower(child.Text):gsub("<[^>]->","")
    if classify(child,"Food")>0 or classify(child,"Water")>0 or value:find("stop eating",1,true) or value:find("stop drinking",1,true)
     or value:find("إيقاف الأكل",1,true) or value:find("إيقاف الشرب",1,true) then sourceCache=child return child end
   end
  end
 end
end
local function prompt(kind,force)
	if kind=="Food" and Brain.foodPatchBlocked then
  local m=player.Character local r=m and m:FindFirstChild("HumanoidRootPart")
  if r and Brain.foodPatchBlocked(r.Position,0)then return end
 end
	if force or os.clock()-sensorAt>=CFG.SensorInterval then
		sensorAt=os.clock() sensorLabel=nil sensorKind=nil
		local source=observedSource(force)
		if source and visible(source) then
			local live=string.lower(source.Text)
			Brain.liveAction=live:find("stop drinking",1,true) and "Water" or (live:find("stop eating",1,true) and "Food" or nil)
			if classify(source,"Food")>0 then sensorLabel=source sensorKind="Food"
			elseif classify(source,"Water")>0 then sensorLabel=source sensorKind="Water" end
		end
	end
	if sensorKind==kind and sensorLabel and sensorLabel:IsDescendantOf(pg) then return sensorLabel end
end
function Brain.clearButtonReceipt()
 local receipt=Brain.compat.buttonReceipt
 if receipt then for _,connection in receipt.connections do connection:Disconnect()end end
 Brain.compat.buttonReceipt=nil
end
function Brain.rejectButtonTransport()
 local receipt=Brain.compat.buttonReceipt
 if not receipt or receipt.ack or not receipt.route then return false end
 Brain.compat.rejected[receipt.route..":pointer:0"]=os.clock()+15
 return true
end
function Brain.touchButtonPress(button)
 if not button or not button:IsA("GuiButton")or not visible(button)or not Brain.focused or not inputOwnerValid()then return false end
 if button.AbsoluteSize.X<2 or button.AbsoluteSize.Y<2 then return false end
 local center=button.AbsolutePosition+button.AbsoluteSize/2
 local ok,hits=pcall(function()return pg:GetGuiObjectsAtPosition(center.X,center.Y)end)
 if not ok then return false end
 for _,hit in hits do
  if hit==button or hit:IsDescendantOf(button)then
   Brain.clearButtonReceipt()
   local receipt={button=button,ack=false,connections={}}
   for _,name in {"Activated","MouseButton1Click"}do
    pcall(function()table.insert(receipt.connections,button[name]:Connect(function()receipt.ack=true end))end)
   end
   local accepted=Brain.compatPointer(0,true,center.X,center.Y)
   receipt.route=Brain.compat.lastPointer Brain.compat.buttonReceipt=receipt
   return accepted
  end
  if not button:IsDescendantOf(hit)then return false end
 end
 return false
end
function Brain.actionButtonInput()
 local screen=pg:FindFirstChild("EatDrinkDisplayScreenGui")
 if not screen or not observedSource(true)then return false end
 local queue={screen}local index=1 local candidates={}
 while index<=#queue and index<=80 do
  local node=queue[index]index+=1
  if node:IsA("GuiButton")and visible(node)then
   local name=string.lower(node.Name)
   if not name:find("close",1,true)and not name:find("cancel",1,true)then table.insert(candidates,node)end
  end
  for _,child in node:GetChildren()do table.insert(queue,child)end
 end
 if #candidates~=1 then return false end
 return Brain.touchButtonPress(candidates[1])
end
local function rawSource()
	local source=observedSource()
	if not source then return "مصدر التفاعل غير موجود في مساره المعروف" end
	return string.format("Text=[%s] / visible=%s / alpha=%.2f",source.Text,tostring(visible(source)),source.TextTransparency)
end
local function stats()
	local character=player.Character
	if not character then return end
	local function read(name,defaultMaximum)
		local value=character:GetAttribute(name)
		local maximum=character:GetAttribute("Max"..name) or character:GetAttribute(name.."Max") or defaultMaximum
		if typeof(value)=="number" and value==value and typeof(maximum)=="number" and maximum==maximum
			and maximum>0 and maximum<math.huge and value>=0 and value<=maximum then return value/maximum*100 end
	end
	return read(CFG.FoodAttribute,CFG.FoodMaximum),read(CFG.WaterAttribute,CFG.WaterMaximum)
end
local function waterPart()
	local part=workspace:FindFirstChild("MainWaterPart")
	return part and part:IsA("BasePart") and part or nil
end
local function isWater(hit)
	return hit and (hit.Instance==waterPart() or hit.Material==Enum.Material.Water)
end
function Brain.waterSurface(origin,direction,hit)
 local part=waterPart()
 if not part or part.CFrame.UpVector.Y<.99 then return hit end
 local normal=part.CFrame.UpVector local denom=direction:Dot(normal)
 if denom>=-.0001 then return hit end
 local top=part.Position+normal*(part.Size.Y*.5)
 local t=(top-origin):Dot(normal)/denom
 if t<0 or t>1 then return hit end
 local p=origin+direction*t local q=part.CFrame:PointToObjectSpace(p)
 if math.abs(q.X)>part.Size.X*.5 or math.abs(q.Z)>part.Size.Z*.5 then return hit end
 local distance=(p-origin).Magnitude
 if hit and hit.Distance<=distance+.01 then return hit end
 return {Instance=part,Material=part.Material,Position=p,Normal=normal,Distance=distance}
end
local parameterModel,groundParams,bedParams
local terrainParams=RaycastParams.new()
terrainParams.FilterType=Enum.RaycastFilterType.Include
terrainParams.IgnoreWater=false terrainParams.RespectCanCollide=false
local indexedWater
local function surfaceParameters()
	local part=waterPart()
	if indexedWater~=part or #terrainParams.FilterDescendantsInstances==0 then
		indexedWater=part
		terrainParams.FilterDescendantsInstances=part and {workspace.Terrain,part} or {workspace.Terrain}
	end
	return terrainParams
end
local function parameters(model)
	if parameterModel~=model then
		parameterModel=model
		groundParams=RaycastParams.new() groundParams.FilterType=Enum.RaycastFilterType.Exclude
		groundParams.FilterDescendantsInstances={model} groundParams.IgnoreWater=false groundParams.RespectCanCollide=true
		bedParams=RaycastParams.new() bedParams.FilterType=Enum.RaycastFilterType.Exclude
		bedParams.FilterDescendantsInstances={model} bedParams.IgnoreWater=true bedParams.RespectCanCollide=true
	end
	return groundParams,bedParams
end
local function cast(position,model)
	queryBudget()
	local params=parameters(model)
	local origin=position+Vector3.new(0,10,0)
	local direction=Vector3.new(0,-45,0)
	local ground=workspace:Raycast(origin,direction,params)
	queryBudget()
	local surface=Brain.waterSurface(origin,direction,workspace:Raycast(origin,direction,surfaceParameters()))
	if surface and isWater(surface) and (not ground or surface.Distance<ground.Distance) then return surface end
	return ground or surface
end
local function supportBelow(position,model)
	queryBudget()
	local _,params=parameters(model)
	return workspace:Raycast(position+Vector3.new(0,10,0),Vector3.new(0,-45,0),params)
end
local function terrainAt(position)
	queryBudget()
	local origin=position+Vector3.new(0,700,0)local direction=Vector3.new(0,-1600,0)
	return Brain.waterSurface(origin,direction,workspace:Raycast(origin,direction,surfaceParameters()))
end
local function dry(hit)
	return hit and not isWater(hit) and hit.Normal.Y>.8
		and not hit.Instance:GetAttribute("BLY_Hazard")
		and (not hit.Instance:IsA("BasePart") or hit.Instance.CanCollide)
end
local function walkable(position,model,allowShallow)
	local top=cast(position,model)
	if dry(top) then return top.Position end
	if not allowShallow or not top or not isWater(top) then return end
	local bed=supportBelow(position,model)
	if not dry(bed) then return end
	local depth=top.Position.Y-bed.Position.Y
	if depth>=0 and depth<=CFG.MaxWadeDepth then return bed.Position end
end
local function safeSegment(a,b,model,allowShallow)
	if allowShallow==nil then allowShallow=true end
	local count=math.max(1,math.ceil((b-a).Magnitude/1.8))
	local last=a.Y
	for i=0,count do
		local pos=a:Lerp(b,i/count)
		for _,offset in {Vector3.zero,Vector3.new(CFG.Footprint,0,0),Vector3.new(-CFG.Footprint,0,0),Vector3.new(0,0,CFG.Footprint),Vector3.new(0,0,-CFG.Footprint)} do
			local floor=walkable(pos+offset,model,allowShallow)
			if not floor or math.abs(floor.Y-pos.Y)>2 then return false end
			if offset==Vector3.zero then if math.abs(floor.Y-last)>1.8 then return false end last=floor.Y end
		end
	end
	return true
end
local function fastSafetyRays(position,direction,horizon,model)
	local base=walkable(position,model,true)
	if not base then return false end
	local side=Vector3.new(-direction.Z,0,direction.X)*CFG.Footprint
	for _,fraction in {.5,1} do
		local center=position+direction*horizon*fraction
		for _,offset in {Vector3.zero,side,-side} do
			if Brain.home and Brain.home.strictLane and CFG.HomeOnly and Brain.mode=="Survival"and not Brain.escapeReturn and not Brain.homeInside(center+offset)then return false end
			local floor=walkable(center+offset,model,true)
			local riseLimit=.6+horizon*fraction*.6
			if not floor or math.abs(floor.Y-base.Y)>riseLimit then return false end
		end
	end
	return true
end
local function fastSafety(position,direction,horizon,model)
	if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
	if workCount+21>CFG.QueriesPerFrame then return nil end
	safetyBatch=true
	local ok,result=pcall(fastSafetyRays,position,direction,horizon,model)
	safetyBatch=false
	if not ok then error(result) end
	return result
end
local function immediateSafety(position,direction,model)
 if CFG.HomeOnly and Brain.mode=="Survival" and not Brain.escapeReturn and Brain.homeInside and Brain.homeInside(position)
  and not Brain.homeSegment(position,position+direction*1.5)then return false end
	if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
	if workCount+12>CFG.QueriesPerFrame then return nil end
	safetyBatch=true
	local ok,safe=pcall(function()
		local base=walkable(position,model,true)
		if not base then return false end
		local side=Vector3.new(-direction.Z,0,direction.X)*CFG.Footprint
		for _,offset in {Vector3.zero,side,-side} do
			if CFG.HomeOnly and Brain.mode=="Survival" and not Brain.escapeReturn and Brain.homeInside and Brain.homeInside(position)
			 and not Brain.homeInside(position+direction*.8+offset)then return false end
			local floor=walkable(position+direction*.8+offset,model,true)
			if not floor or math.abs(floor.Y-base.Y)>.8 then return false end
		end
		return true
	end)
	safetyBatch=false
	if not ok then error(safe) end
	return safe
end
function Brain.movementSafety(position,direction,horizon,model)
 if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
 local pending=Brain.nearSafetyPending
 local nearOnly=pending and pending.model==model and os.clock()-pending.at<=.25
  and (position-pending.position).Magnitude<=1 and direction:Dot(pending.direction)>.98
 local required=nearOnly and 12 or 21
 if workCount+required>CFG.QueriesPerFrame then return nil,false end
 safetyBatch=true
 local ok,safe,caution=pcall(function()
  if nearOnly then
   Brain.nearSafetyPending=nil
   local near=immediateSafety(position,direction,model)
   return near==true,near==true
  end
  Brain.nearSafetyPending=nil
  if fastSafetyRays(position,direction,horizon,model) then return true,false end
  if workCount+12>CFG.QueriesPerFrame then
   Brain.nearSafetyPending={model=model,position=position,direction=direction,at=os.clock()}
   return nil,false
  end
  local near=immediateSafety(position,direction,model)
  return near==true,near==true
 end)
 safetyBatch=false
 if not ok then Brain.nearSafetyPending=nil error(safe) end
 return safe,caution
end
local function cell(pos) return math.floor(pos.X/7)..":"..math.floor(pos.Z/7) end
local Atlas={nodes={},routes={},serial=0,visible=false,lastDraw=0,lastSave=0,version=1}
function Atlas.key(kind,p) return kind..":"..math.floor(p.X/12)..":"..math.floor(p.Z/12) end
function Atlas.pack(p) return p and {p.X,p.Y,p.Z} or nil end
function Atlas.unpack(p)
	if typeof(p)~="table" or #p~=3 then return end
	for i=1,3 do local n=p[i] if typeof(n)~="number" or n~=n or math.abs(n)>10000000 then return end end
	return Vector3.new(p[1],p[2],p[3])
end
function Atlas.note(kind,p,state,water)
 if CFG.HomeOnly and Brain.mode=="Survival" then return end
	local key=Atlas.key(kind,p)
	Atlas.serial+=1
	local node=Atlas.nodes[key] or {}
	node.kind=kind node.position=p node.water=water node.state=state
	node.time=os.time() node.order=Atlas.serial node.retry=state=="depleted" and os.time()+90 or (state=="changed" and os.time()+15 or 0)
	Atlas.nodes[key]=node
	local count,oldest,order=0,nil,math.huge
	for k,n in Atlas.nodes do count+=1 if n.order<order then oldest=k order=n.order end end
	if count>192 then Atlas.nodes[oldest]=nil end
end
function Atlas.save(force)
 if CFG.HomeOnly and Brain.mode=="Survival" then return end
	if typeof(writefile)~="function" or (not force and os.clock()-Atlas.lastSave<10) then return end
	Atlas.lastSave=os.clock()
	local nodes={}
	for _,n in Atlas.nodes do
		if os.time()-n.time<3600 then table.insert(nodes,{kind=n.kind,position=Atlas.pack(n.position),water=Atlas.pack(n.water),state=n.state,time=n.time,retry=n.retry}) end
	end
	pcall(function()
		writefile("BLY_Anywhere_PC_Atlas_"..game.PlaceId..".json",game:GetService("HttpService"):JSONEncode({version=1,place=game.PlaceId,nodes=nodes}))
	end)
end
function Atlas.load()
	if typeof(readfile)~="function" then return end
	local ok,raw=pcall(readfile,"BLY_Anywhere_PC_Atlas_"..game.PlaceId..".json")
	if not ok or typeof(raw)~="string" or #raw>200000 then return end
	local decoded,data=pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
	if not decoded or typeof(data)~="table" or data.version~=1 or data.place~=game.PlaceId or typeof(data.nodes)~="table" then return end
	for i,n in data.nodes do
		if typeof(i)~="number" or i>192 then break end
		if typeof(n)=="table" and (n.kind=="Food" or n.kind=="Water") and typeof(n.time)=="number" and os.time()-n.time>=0 and os.time()-n.time<3600 then
			local p,w=Atlas.unpack(n.position),Atlas.unpack(n.water)
			if p then
				Atlas.note(n.kind,p,"cached",w)
				local saved=Atlas.nodes[Atlas.key(n.kind,p)]
				saved.time=n.time saved.retry=typeof(n.retry)=="number" and math.min(n.retry,os.time()+90) or 0
			end
		end
	end
end
function Atlas.candidates(kind,root,model,add)
	local list={}
	for _,n in Atlas.nodes do
		if n.kind==kind and os.time()-n.time<3600 and (n.retry or 0)<=os.time() and (root.Position-n.position).Magnitude<=(Brain.worldCare()and 2800 or CFG.Radius) then table.insert(list,n) end
	end
	table.sort(list,function(a,b) return (a.position-root.Position).Magnitude<(b.position-root.Position).Magnitude end)
	for i,n in list do
		if i>6 then break end
		local hit=cast(n.position,model)
  if not hit and Brain.worldCare()and kind=="Water"and isWater(n.water and terrainAt(n.water))then
   if Brain.requestRegion then Brain.requestRegion(n.position)end add(n.position,n.water,0)
  end
		if dry(hit) then
			if kind=="Water" then
				local wet=n.water and terrainAt(n.water)
				if isWater(wet) and (wet.Position-hit.Position).Magnitude<10 then
					n.position=hit.Position n.water=wet.Position add(hit.Position,wet.Position,-10)
				else n.state="dry_or_unknown" n.retry=os.time()+15 end
			elseif hit.Material==Enum.Material.Grass then add(hit.Position,nil,-3)
			else n.state="depleted" n.retry=os.time()+90 end
		else n.state="changed" n.retry=os.time()+15 end
	end
end
function Atlas.rememberRoute(route,model)
	if not route or not route.points or #route.points<2 then return end
	local points={}
	for i,point in route.points do
		if i>80 then return end
		table.insert(points,{Position=point.Position,Action=point.Action})
	end
	table.insert(Atlas.routes,{points=points,time=os.clock()})
	if #Atlas.routes>8 then table.remove(Atlas.routes,1) end
end
function Atlas.route(from,to,model)
	for _,r in Atlas.routes do
		if os.clock()-r.time<120 then
			local a,b=r.points[1].Position,r.points[#r.points].Position
			local forward=(a-from).Magnitude<5 and (b-to).Magnitude<5
			local reverse=(b-from).Magnitude<5 and (a-to).Magnitude<5
			if forward or reverse then
				local points={} local last=from local safe=true
				for index=1,#r.points do
					local i=forward and index or #r.points-index+1
					local point=r.points[i]
					if not safeSegment(last,point.Position,model,true) then safe=false break end
					table.insert(points,point) last=point.Position
				end
				if safe then return {position=to,points=points} end
			end
		end
	end
end
function Atlas.draw(root)
	if not Atlas.visible or not root then return end
	if os.clock()-Atlas.lastDraw<3 then return end Atlas.lastDraw=os.clock()
	if not Atlas.folder then Atlas.folder=Instance.new("Folder") Atlas.folder.Name="BLY_ResourceMarkers" Atlas.folder.Parent=workspace end
	Atlas.folder:ClearAllChildren()
	local list={}
	for _,n in Atlas.nodes do if os.time()-n.time<90 and (n.retry or 0)<=os.time() then table.insert(list,n) end end
	table.sort(list,function(a,b) return (a.position-root.Position).Magnitude<(b.position-root.Position).Magnitude end)
	for i,n in list do
		if i>24 then break end
		local marker=Instance.new("Part") marker.Name=n.kind.."_"..n.state
		marker.Anchored=true marker.CanCollide=false marker.CanTouch=false marker.CanQuery=false
		marker.Size=Vector3.new(3,.15,3) marker.Position=n.position+Vector3.new(0,.25,0)
		marker.Color=n.kind=="Water" and Color3.fromRGB(125,210,255) or Color3.fromRGB(231,238,242)
		marker.Material=Enum.Material.Neon marker.Transparency=.35 marker.Parent=Atlas.folder
	end
end
Atlas.load()
Brain.saveAtlas=function() Atlas.save(true) end
local function rememberWater(model,root,confirmed)
	if not confirmed and not prompt("Water") then return end
	local memoryGeneration=generation
	knownDrinkPosition=root.Position
	local wetPoint,wetDistance
	for _,radius in {0,2,4,8} do
		for i=0,(radius==0 and 0 or 7) do
			if not alive or memoryGeneration~=generation then return end
			local angle=i*math.pi/4
			local hit=terrainAt(root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
			if isWater(hit) then
				local distance=(hit.Position-root.Position).Magnitude
				if not wetDistance or distance<wetDistance then wetPoint=hit.Position wetDistance=distance end
			end
		end
		if wetPoint then break end
	end
	if wetPoint then knownDrinkPosition=wetPoint end
	local here=cast(root.Position,model)
	if dry(here) and safeSegment(here.Position,here.Position,model) then knownShore=here.Position Atlas.note("Water",knownShore,confirmed and "confirmed" or "observed",wetPoint) Atlas.save(false) return end
	local closest,distance
	for radius=2,14,2 do
		for i=0,11 do
			if not alive or memoryGeneration~=generation then return end
			local angle=i*math.pi/6
			local hit=cast(root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),model)
			if dry(hit) and safeSegment(hit.Position,hit.Position,model) then
				local d=(hit.Position-root.Position).Magnitude
				if not distance or d<distance then closest=hit.Position distance=d end
			end
		end
		if closest then break end
	end
	if closest and alive and memoryGeneration==generation then knownShore=closest Atlas.note("Water",knownShore,confirmed and "confirmed" or "observed",wetPoint) Atlas.save(false) end
end
local function routes(kind,token,model,root)
	local candidates={}
	local used={}
	local floor=walkable(root.Position,model,true)
	if not floor then return end
	local base={Position=floor}
	local function add(position,water,penalty)
		local key=cell(position)
		if (avoided[kind..key] or 0)>os.clock() then return end
		local remembered=Atlas.nodes[Atlas.key(kind,position)]
		if remembered and (remembered.retry or 0)>os.time() then return end
  if kind=="Food"and Brain.worldCare()and Brain.foodPatchBlocked and Brain.foodPatchBlocked(position,2)then return end
		if kind=="Food" and lastConsumed and os.clock()<(Brain.lastFoodUntil or 0) and (position-lastConsumed).Magnitude<8 then return end
		local returnCost=0
		if kind=="Water" then penalty=0 end
		Atlas.note(kind,position,"candidate",water)
		local delta=position-root.Position
		local distance=(kind=="Water" and Vector3.new(delta.X,0,delta.Z).Magnitude or delta.Magnitude)+(penalty or 0)+returnCost
		local existing=used[key]
		if existing then
			if distance<existing.distance then existing.position=position existing.water=water existing.distance=distance end
			return
		end
		local candidate={position=position,water=water,distance=distance,outsideZone=Brain.resourceZone and not Brain.pointInZone(position,Brain.resourceZone) or false}
		used[key]=candidate table.insert(candidates,candidate) return true
	end
	if kind=="Food"then Atlas.candidates(kind,root,model,add)end
	if kind=="Food" then
		local forward=root.CFrame.LookVector
		local offsets={0,22.5,-22.5,45,-45,67.5,-67.5,90,-90,112.5,-112.5,135,-135,157.5,-157.5,180}
		for _,radius in {4,8,12,20,32} do
			for _,degrees in offsets do
				if not valid(token,model) then return end
				if prompt(kind) then return {here=true} end
				local angle=math.rad(degrees)
				local direction=Vector3.new(forward.X*math.cos(angle)-forward.Z*math.sin(angle),0,forward.X*math.sin(angle)+forward.Z*math.cos(angle))
				if direction.Magnitude>.1 then
					local hit=cast(root.Position+direction.Unit*radius,model)
					if dry(hit) and hit.Material==Enum.Material.Grass and math.abs(hit.Position.Y-base.Position.Y)<3 then add(hit.Position,nil,0) end
				end
			end
			if #candidates>0 and radius>=12 then break end
			task.wait()
		end
		if #candidates==0 then
			for radius=48,240,24 do
				for i=0,23 do
					if not valid(token,model) then return end
					if prompt(kind) then return {here=true} end
					local angle=i*math.pi/12
					local hit=cast(root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),model)
					if dry(hit) and hit.Material==Enum.Material.Grass then add(hit.Position,nil,0) end
				end
				task.wait()
			end
		end
	else
		local rootSurface=terrainAt(root.Position)
		local function bankBetween(land,water)
			for refinement=1,(Brain.worldCare()and 12 or 5)do
				if not valid(token,model) then return end
				local hit=terrainAt(land:Lerp(water,.5))
				if not hit then return elseif isWater(hit) then water=hit.Position else land=hit.Position end
    if Vector3.new(land.X-water.X,0,land.Z-water.Z).Magnitude<.25 then break end
			end
			local delta=land-water local horizontal=Vector3.new(delta.X,0,delta.Z)
			if horizontal.Magnitude<.01 then return end
			for _,backoff in {1.2,2.5,4,6}do
    local hit=cast(land+horizontal.Unit*backoff,model)
    if dry(hit)and (hit.Position-water).Magnitude<10 and safeSegment(hit.Position,hit.Position,model,true)then
     add(hit.Position,water,0)return true
    end
   end
		end
		waterSamples=0 waterScanDone=true
		local heading=Brain.worldCare()and Brain.growth and (Brain.growth.waterScanHeading or 0)or 0
  local previous={}local finished={}
  for i=0,23 do previous[i]=rootSurface end
  local radii=Brain.worldCare()and {2,4,8,12,20,32,48,72,104,144,192,240,320,432,576,768,1024,1536,2048,2800}or {2,4,8,12,20,32,48,72,104,144,192,240}
  for _,radius in radii do
   for i=0,23 do
    if finished[i]then continue end
    if not valid(token,model)then return end
    if prompt(kind)then return {here=true}end
    local angle=((i+heading)%24)*math.pi/12
    local probe=root.Position+Vector3.new(math.cos(angle),0,math.sin(angle))*radius
    local hit=terrainAt(probe)
    if not hit and radius>=240 and Brain.worldCare()and Brain.requestRegion and os.clock()>=(Brain.nextRegionRequest or 0)then
     Brain.requestRegion(probe)
     if Brain.growth then Brain.growth.waterScanHeading=(i+heading+1)%24 end
    end
    if isWater(hit)then waterSamples+=1 end
    local before=previous[i]
    if before and hit then
     if dry(before)and isWater(hit)then finished[i]=bankBetween(before.Position,hit.Position)==true
     elseif isWater(before)and dry(hit)then finished[i]=bankBetween(hit.Position,before.Position)==true end
    end
    previous[i]=hit
   end
   if #candidates>0 then break end
   task.wait()
  end
  if #candidates==0 then Atlas.candidates(kind,root,model,add)end
	end
	if #candidates==0 then return end
	table.sort(candidates,function(a,b) if a.outsideZone~=b.outsideZone then return not a.outsideZone end return a.distance<b.distance end)
	local best,bestLength=nil,math.huge
	Brain.routeReason="لا يوجد مسار مؤكد بعد"
	for i,c in candidates do
		if i>CFG.PathCandidates then break end
		if not valid(token,model) then return end
		if prompt(kind) then return {here=true} end
  if Brain.worldCare()and Brain.travelRoute then
   local route=Brain.travelRoute(c.position,token,model,root)
   if route then route.water=c.water route.intendedDestination=c.position return route end
  end
		local cached=Atlas.route(base.Position,c.position,model)
		if cached then cached.water=c.water return cached end
		if (c.position-base.Position).Magnitude<=32 and safeSegment(base.Position,c.position,model,true) then
			return {position=c.position,water=c.water,points={{Position=base.Position},{Position=c.position}}}
		end
		local path=PF:CreatePath({AgentRadius=CFG.AgentRadius,AgentHeight=CFG.AgentHeight,AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=3,Costs={Water=math.huge}})
		local ok=computePath(path,root.Position,c.position,token,model)
		if not valid(token,model) then return end
		local points=ok and path.Status==Enum.PathStatus.Success and path:GetWaypoints() or nil
		local previousPoint,length,safe=base.Position,0,points~=nil
		if points then
			for _,point in points do
				if point.Action==Enum.PathWaypointAction.Jump or not safeSegment(previousPoint,point.Position,model) then safe=false break end
				length+=(point.Position-previousPoint).Magnitude previousPoint=point.Position
			end
		end
		local score=length+c.distance*.15
		if safe and kind=="Water" then return {position=c.position,water=c.water,points=points,path=path} end
		if safe and score<bestLength then bestLength=score best={position=c.position,water=c.water,points=points,path=path} end
		if not safe then Brain.routeReason=points and "رفض فحص الأرض للمسار" or "لم يعط Pathfinding مسارًا" avoided[kind..cell(c.position)]=os.clock()+25 end
	end
	return best
end
on(Run.Heartbeat,function()
	if running and not Brain.focused and CFG.Background and Brain.steerCamera then Brain.steerCamera() end
end)
local function movementFrame()
	Run.Heartbeat:Wait()
	if Brain.steerCamera then Brain.steerCamera() end
end
local function beginCamera()
	local camera=workspace.CurrentCamera
	if not camera then error("الكاميرا غير متاحة") end
	cameraState={camera=camera,kind=camera.CameraType,subject=camera.CameraSubject,cframe=camera.CFrame}
	camera.CameraType=Enum.CameraType.Scriptable
	Brain.steerCamera=function()
		local _,root=rig()
		if running and root and aim and workspace.CurrentCamera==camera then
			camera.CFrame=CFrame.lookAt(root.Position-aim*12+Vector3.new(0,7,0),root.Position+aim*8)
		end
	end
	Run:BindToRenderStep("BLY_MONO_STEER",Enum.RenderPriority.Camera.Value+1,Brain.steerCamera)
end
function Brain.routeLengths(points)
 local remaining={} remaining[#points]=0
 for i=#points-1,1,-1 do
  local delta=points[i+1].Position-points[i].Position
  remaining[i]=(remaining[i+1] or 0)+Vector3.new(delta.X,0,delta.Z).Magnitude
 end
 return remaining
end
function Brain.routeMotion(points,index,position,remaining)
 local delta=points[index].Position-position local flat=Vector3.new(delta.X,0,delta.Z)
 if flat.Magnitude<.01 then return nil,0,remaining[index] or 0 end
 local previous=points[index-1] local segment=previous and points[index].Position-previous.Position or flat
 local line=Vector3.new(segment.X,0,segment.Z)
 local pathDirection=line.Magnitude>.01 and line.Unit or flat.Unit
 local target=flat
 for i=index+1,math.min(#points,index+32) do
  local step=points[i].Position-points[i-1].Position step=Vector3.new(step.X,0,step.Z)
  if step.Magnitude>.01 and step.Unit:Dot(pathDirection)<.995 then break end
  local ahead=points[i].Position-position ahead=Vector3.new(ahead.X,0,ahead.Z)
  if ahead:Dot(pathDirection)<=0 then break end
  target=ahead
  if target.Magnitude>=48 then break end
 end
 return target.Unit,math.min(64,target.Magnitude),flat.Magnitude+(remaining[index] or 0)
end
function Brain.routeStart(points,position)
 local index=1
 while index<#points do
  local segment=points[index+1].Position-points[index].Position local flat=Vector3.new(segment.X,0,segment.Z)
  if flat.Magnitude<.01 then index+=1 continue end
  local offset=position-points[index].Position offset=Vector3.new(offset.X,0,offset.Z)
  local along=offset:Dot(flat.Unit) local lateral=(offset-flat.Unit*along).Magnitude
  if along>=-.1 and lateral<=4 then index+=1 else break end
 end
 return index
end
function Brain.waypointReached(point,previous,position,velocity,hasNext)
 local delta=point-position local flat=Vector3.new(delta.X,0,delta.Z)
 if flat.Magnitude<1.6 then return true end
 if not previous then return false end
 local segment=point-previous segment=Vector3.new(segment.X,0,segment.Z)
 if segment.Magnitude<.01 then return true end
 local direction=segment.Unit local along=flat:Dot(direction)
 local lateral=(flat-direction*along).Magnitude
 local speed=math.max(0,Vector3.new(velocity.X,0,velocity.Z):Dot(direction))
 local threshold=hasNext and math.clamp(speed*.07,.4,1.6) or math.clamp(speed*.05,.25,1)
 return along<=threshold and lateral<=(hasNext and 4 or 3)
end
function Brain.walkPointReached(route,index,kind,position,velocity)
 local point=route.points[index]
 if kind=="ReturnHome"and Brain.home.strictLane and Brain.mode=="Survival"and index==#route.points then
  return Brain.homeReturnReached(position)or Brain.homeDistance(point.Position,position)<=math.max(.4,math.min(.7,CFG.Footprint or .7))
 end
 local previous=route.points[index-1]
 return Brain.waypointReached(point.Position,previous and previous.Position,position,velocity,route.points[index+1]~=nil)
end
function Brain.resourcePromptStopsWalk()
 return heldW and activeKind and not Brain.shoreNudge and not Brain.escapeReturn and prompt(activeKind)
end
-- SMART NAV TEST: Progress is measured toward the waypoint, not by camera/facing alignment.
-- A character can stand still while facing sideways; the old check reset indefinitely.
function Brain.motionProgress(sample,position,velocity,now,attempting,aligned,distance)
 if not sample then
  sample={position=position,at=now,checkAt=now,samples=0,best=distance,progressAt=now}
 end
 local speed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
 if not attempting then
  sample.position=position sample.at=now sample.progressAt=now sample.best=distance
  sample.checkAt=now sample.samples=0
  return sample,false
 end
 if distance<(sample.best or distance)-.75 then
  sample.best=distance sample.progressAt=now sample.position=position
  sample.samples=0
 elseif now-sample.checkAt>=.4 then
  sample.checkAt=now sample.samples+=1
 end
 -- Slow/stationary characters are detected quickly; sideways motion gets more grace.
 local idleFor=now-(sample.progressAt or now)
 local limit=speed<.85 and 5 or 9
 return sample,idleFor>=limit and sample.samples>=5
end
function Brain.pathBlockNear(route,index)
 local blocked=route.blockedAheadIndex
 return blocked~=nil and blocked>=index and blocked<=index+1
end
local function walkHomeCore(route,kind,token,model,root)
	if route.here then return "prompt" end
 local remaining=Brain.routeLengths(route.points)
	local resourceCheck=0
	local arrivalBrake=false
	local nextSafetyAt=0
 local safetyWaitingAt
 local nextWaterCheck=0
 local nextStreamAt=0
	local routeOrigin=root.Position
 local startIndex=Brain.routeStart(route.points,root.Position)
 for pointIndex=startIndex,#route.points do
  local point=route.points[pointIndex]
        route.walkIndex=pointIndex
		local distanceToPoint=(point.Position-root.Position).Magnitude
		local bestDistance=distanceToPoint
		local deadline=os.clock()+math.clamp(distanceToPoint/2+10,15,180)
		local last,lastTime=root.Position,os.clock()
  local progressSample
		local previous=route.points[pointIndex-1] or {Position=routeOrigin}
		local initial=point.Position-(previous and previous.Position or root.Position)
		local initialFlat=Vector3.new(initial.X,0,initial.Z)
		local travelDirection=initialFlat.Magnitude>.1 and initialFlat.Unit or nil
		while valid(token,model) do
   if route.lockedHome and Brain.projectLane(route.points,root.Position,false)>Brain.homeLaneWidth() then releaseW("lane_drift") return "offroute" end
   if Brain.pathBlockNear(route,pointIndex) then releaseW("path_blocked_ahead") return "blocked" end
   if kind=="ReturnHome" and Brain.homeReturnReached(root.Position) then releaseW("home_reached") return "arrived" end
			if kind=="Travel" then
				if not CFG.QuestsEnabled then releaseW() return "quest_off" end
				if Brain.holdZone and Brain.questZoneNow(model)~=Brain.holdZone then releaseW() return "zone_exit" end
				if Brain.travelZone and Brain.questZoneNow(model)==Brain.travelZone then releaseW() return "zone" end
				if os.clock()>=resourceCheck then
					resourceCheck=os.clock()+.25
     if route.questKey then local halt=Brain.travelLoopGuard(route.questKey) if halt then releaseW(halt) return halt end end
					local f,w=stats()
					if not f or not w or f<CFG.Threshold or w<CFG.Threshold then releaseW() return "needs" end
				end
			end
   if os.clock()>=nextStreamAt and Brain.requestRegion then
    nextStreamAt=os.clock()+3
    local upcoming=route.points[math.min(pointIndex+16,#route.points)]
    if upcoming then Brain.requestRegion(upcoming.Position) end
   end
            if os.clock()>=nextWaterCheck then
                nextWaterCheck=os.clock()+.3
                local _,_,h=rig()
                if Brain.waterThreat and Brain.waterThreat(model,root,h) then releaseW("water_danger") return "water_danger" end
            end
   if (kind=="Food" or kind=="Water") and os.clock()>=resourceCheck then
    resourceCheck=os.clock()+.25
    local food,water=stats()
    if food and water then
     local amount=kind=="Food" and food or water local other=kind=="Food" and water or food
     if amount>=CFG.Target and other<CFG.Threshold then releaseW("urgent_other_need") return "needs" end
    end
   end
			local stamina=Brain.staminaPercent(model)
			if typeof(stamina)=="number" and (stamina<25 or (Brain.energyRest and stamina<50) or model:GetAttribute("StaminaRanOut")==true) and Brain.restUntilReady and Brain.policy.shouldRestForTravel(kind,stats()) then
				local rested=Brain.restUntilReady(token,model,root)
				if not valid(token,model) then return "cancelled" end
				last=root.Position lastTime=os.clock() deadline=os.clock()+math.clamp(distanceToPoint/2+10,15,180)
				if rested=="needs" then releaseW("rest_needs") return "needs" end
				if rested=="stalled" then return "rest_stalled" end
 if rested=="water_danger" then return "water_danger" end
			end
			if not Brain.escapeReturn and not Brain.homeInside(root.Position) then releaseW("home_boundary") return "home_boundary" end
			if prompt(kind) then releaseW("resource_prompt") return "prompt" end
			local delta=point.Position-root.Position
			local flat=Vector3.new(delta.X,0,delta.Z)
			if Brain.walkPointReached(route,pointIndex,kind,root.Position,root.AssemblyLinearVelocity) then break end
   if flat.Magnitude<bestDistance-.5 then bestDistance=flat.Magnitude deadline=math.max(deadline,os.clock()+10) end
			if os.clock()>deadline then releaseW("deadline_or_no_progress") return "blocked" end
			local forward,forwardClearance,remainingDistance=Brain.routeMotion(route.points,pointIndex,root.Position,remaining)
   aim=forward or flat.Unit
   if route.transit and route.goalPosition and remainingDistance<=96 and Brain.prefetchTravel then Brain.prefetchTravel(route,token,model) end
			if os.clock()>=nextSafetyAt then
				local from=root.Position
				local horizon=math.min(forwardClearance,math.clamp(root.AssemblyLinearVelocity.Magnitude*.25+3,8,10))
				local safety,cautious=Brain.movementSafety(from,aim,horizon,model)
				if not valid(token,model) then return "cancelled" end
				if safety==nil then
     safetyWaitingAt=safetyWaitingAt or os.clock()
     -- PC-WATER-R42: when the raycast budget never clears, stop waiting and replan.
     if os.clock()-safetyWaitingAt>7 then
      releaseW("safety_scan_stalled")
      Brain.motionHold="تأخر فحص الأرض؛ أجرب مسارا آخر"
      return "blocked"
     end
     deadline=math.max(deadline,os.clock()+10) progressSample=nil lastTime=os.clock()
     if os.clock()-safetyWaitingAt>2 and Brain.requestRegion then Brain.requestRegion(point.Position) end
					local travel=Brain.lastSafeFrom and (from-Brain.lastSafeFrom).Magnitude or math.huge
					local covered=Brain.policy.coverageFresh(os.clock()-(Brain.lastSafeAt or 0),travel,Brain.lastSafeHorizon or 0,root.AssemblyLinearVelocity.Magnitude)
					if not heldW or not covered then releaseW("safety_coverage_expired") Brain.motionHold="أنتظر فحص الخطوة الجاية" Run.Heartbeat:Wait() continue end
					nextSafetyAt=os.clock()+.01
				elseif not safety then
     safetyWaitingAt=nil
					Brain.motionHold="الخطوة قدامي ما تأكدت آمنة"
					releaseW("immediate_ground_unsafe") return "unsafe"
				elseif cautious then
     safetyWaitingAt=nil
					Brain.runtimeCaution=true Brain.cautionRecoveryAt=nil
					Brain.lastSafeAt=os.clock() Brain.lastSafeFrom=from Brain.lastSafeHorizon=.8
					nextSafetyAt=os.clock()+.05
				else
					safetyWaitingAt=nil
     if Brain.runtimeCaution then
						Brain.cautionRecoveryAt=Brain.cautionRecoveryAt or os.clock()
						if os.clock()-Brain.cautionRecoveryAt>=1 then Brain.runtimeCaution=false Brain.cautionRecoveryAt=nil end
					end
					Brain.motionHold=nil
					Brain.lastSafeAt=os.clock() Brain.lastSafeFrom=from Brain.lastSafeHorizon=horizon
					nextSafetyAt=os.clock()+.1
				end
			end
			if (root.Position-last).Magnitude>.4 then last=root.Position lastTime=os.clock() end
			local trulyStuck
   progressSample,trulyStuck=Brain.motionProgress(progressSample,root.Position,root.AssemblyLinearVelocity,os.clock(),heldW,Brain.headingAligned==true,flat.Magnitude)
   if trulyStuck then
    Brain.motionHold="انقطعت الحركة؛ أغير المسار بدل الانتظار"
    Brain.motionTrace("smart_nav_stalled",kind.." / waypoint="..tostring(pointIndex))
    releaseW("confirmed_no_progress") return "blocked"
   end
			if not heldW then
				movementFrame()
				if not valid(token,model) then return "cancelled" end
				if prompt(kind) then releaseW("resource_prompt") return "prompt" end
				heldW=true send(Enum.KeyCode.W,true)
			end
			local endDistance=remainingDistance
			local speed=root.AssemblyLinearVelocity.Magnitude
			local deceleration=model:GetAttribute("Deceleration")
			if typeof(deceleration)~="number" or deceleration<=0 then deceleration=45 end
			local brakingDistance=math.clamp(speed*speed/(2*deceleration)+3,6,22)
			arrivalBrake=arrivalBrake or endDistance<=brakingDistance or (kind=="Water"and Brain.home.recordedStations and Brain.homeDistance(root.Position,Brain.home.water)<40)
			local facing=model:GetAttribute("FacingDirection")
			if typeof(facing)~="Vector3" then
    local velocity=root.AssemblyLinearVelocity local movement=Vector3.new(velocity.X,0,velocity.Z)
    facing=movement.Magnitude>2 and movement or root.CFrame.LookVector
   end
			local heading=Vector3.new(facing.X,0,facing.Z)
			local alignment=heading.Magnitude>.01 and heading.Unit:Dot(aim) or -1
			Brain.headingAligned=Brain.policy.heading(Brain.headingAligned,alignment)
			local aligned=Brain.headingAligned==true
			local runningStraight=aligned and not Brain.runtimeCaution and not arrivalBrake
   local allowRun=aligned and not Brain.runtimeCaution and not arrivalBrake and forwardClearance>math.max(8,brakingDistance+2)
			Brain.speedTick(root,model,runningStraight and forwardClearance>8 and (Brain.lastSafeHorizon or 0)>=8 and endDistance>math.max(14,brakingDistance),allowRun)
			Run.Heartbeat:Wait()
		end
		if not valid(token,model) then releaseW() return "cancelled" end
	end
	if route.nextRouteReady and valid(token,model) then Atlas.rememberRoute(route,model) return "handoff" end
 releaseW("route_segment_end")
	Atlas.rememberRoute(route,model)
	return "arrived"
end
local function walkCore(route,kind,token,model,root)
	if route.here then return "prompt" end
 local remaining=Brain.routeLengths(route.points)
	local resourceCheck=0
	local arrivalBrake=false
	local nextSafetyAt=0
 local safetyWaitingAt
 local nextWaterCheck=0
 local nextStreamAt=0
	local routeOrigin=root.Position
 local startIndex=Brain.routeStart(route.points,root.Position)
 for pointIndex=startIndex,#route.points do
  local point=route.points[pointIndex]
        route.walkIndex=pointIndex
		local distanceToPoint=(point.Position-root.Position).Magnitude
		local bestDistance=distanceToPoint
		local deadline=os.clock()+math.clamp(distanceToPoint/2+10,15,180)
		local last,lastTime=root.Position,os.clock()
  local progressSample
		local previous=route.points[pointIndex-1] or {Position=routeOrigin}
		local initial=point.Position-(previous and previous.Position or root.Position)
		local initialFlat=Vector3.new(initial.X,0,initial.Z)
		local travelDirection=initialFlat.Magnitude>.1 and initialFlat.Unit or nil
		while valid(token,model) do
   if route.lockedLoop and Brain.projectLane(route.points,root.Position,false)>Brain.travelLoopWidth() then releaseW("loop_drift") return "offroute" end
   if Brain.pathBlockNear(route,pointIndex) then releaseW("path_blocked_ahead") return "blocked" end
   if kind=="ReturnHome" and Brain.homeReturnReached(root.Position) then releaseW("home_reached") return "arrived" end
			if kind=="Travel" then
				if not CFG.QuestsEnabled then releaseW() return "quest_off" end
				if Brain.holdZone and Brain.questZoneNow(model)~=Brain.holdZone then releaseW() return "zone_exit" end
				if Brain.travelZone and Brain.questZoneNow(model)==Brain.travelZone then releaseW() return "zone" end
				if os.clock()>=resourceCheck then
					resourceCheck=os.clock()+.25
     if route.questKey then local halt=Brain.travelLoopGuard(route.questKey) if halt then releaseW(halt) return halt end end
					local f,w=stats()
					if not f or not w or (f<CFG.Threshold or w<CFG.Threshold) then releaseW() return "needs" end
				end
			end
   if os.clock()>=nextStreamAt and Brain.requestRegion then
    nextStreamAt=os.clock()+3
    local upcoming=route.points[math.min(pointIndex+16,#route.points)]
    if upcoming then Brain.requestRegion(upcoming.Position) end
   end
            if os.clock()>=nextWaterCheck then
                nextWaterCheck=os.clock()+.3
                local _,_,h=rig()
                if Brain.waterThreat and Brain.waterThreat(model,root,h) then releaseW("water_danger") return "water_danger" end
            end
   if (kind=="Food" or kind=="Water") and os.clock()>=resourceCheck then
    resourceCheck=os.clock()+.25
    local food,water=stats()
    if food and water then
     local amount=kind=="Food" and food or water local other=kind=="Food" and water or food
     if amount>=CFG.Target and other<CFG.Threshold then releaseW("urgent_other_need") return "needs" end
    end
   end
			local stamina=Brain.staminaPercent(model)
			if typeof(stamina)=="number" and (stamina<25 or (Brain.energyRest and stamina<50) or model:GetAttribute("StaminaRanOut")==true) and Brain.restUntilReady and Brain.policy.shouldRestForTravel(kind,stats()) then
				local rested=Brain.restUntilReady(token,model,root)
				if not valid(token,model) then return "cancelled" end
				last=root.Position lastTime=os.clock() deadline=os.clock()+math.clamp(distanceToPoint/2+10,15,180)
				if rested=="needs" then releaseW("rest_needs") return "needs" end
				if rested=="stalled" then return "rest_stalled" end
 if rested=="water_danger" then return "water_danger" end
			end
			if CFG.HomeOnly and not Brain.escapeReturn and Brain.mode~="Quests" and not Brain.homeInside(root.Position) then releaseW("home_boundary") return "home_boundary" end
			if prompt(kind) then releaseW("resource_prompt") return "prompt" end
			local delta=point.Position-root.Position
			local flat=Vector3.new(delta.X,0,delta.Z)
			if Brain.walkPointReached(route,pointIndex,kind,root.Position,root.AssemblyLinearVelocity) then break end
   if flat.Magnitude<bestDistance-.5 then bestDistance=flat.Magnitude deadline=math.max(deadline,os.clock()+10) end
			if os.clock()>deadline then releaseW("deadline_or_no_progress") return "blocked" end
			local forward,forwardClearance,remainingDistance=Brain.routeMotion(route.points,pointIndex,root.Position,remaining)
   aim=forward or flat.Unit
   if route.transit and route.goalPosition and remainingDistance<=96 and Brain.prefetchTravel then Brain.prefetchTravel(route,token,model) end
			if os.clock()>=nextSafetyAt then
				local from=root.Position
				local horizon=math.min(forwardClearance,math.clamp(root.AssemblyLinearVelocity.Magnitude*.25+3,8,10))
				local safety,cautious=Brain.movementSafety(from,aim,horizon,model)
				if not valid(token,model) then return "cancelled" end
				if safety==nil then
     safetyWaitingAt=safetyWaitingAt or os.clock()
     -- PC-WATER-R42: when the raycast budget never clears, stop waiting and replan.
     if os.clock()-safetyWaitingAt>7 then
      releaseW("safety_scan_stalled")
      Brain.motionHold="تأخر فحص الأرض؛ أجرب مسارا آخر"
      return "blocked"
     end
     deadline=math.max(deadline,os.clock()+10) progressSample=nil lastTime=os.clock()
     if os.clock()-safetyWaitingAt>2 and Brain.requestRegion then Brain.requestRegion(point.Position) end
					local travel=Brain.lastSafeFrom and (from-Brain.lastSafeFrom).Magnitude or math.huge
					local covered=Brain.policy.coverageFresh(os.clock()-(Brain.lastSafeAt or 0),travel,Brain.lastSafeHorizon or 0,root.AssemblyLinearVelocity.Magnitude)
					if not heldW or not covered then releaseW("safety_coverage_expired") Brain.motionHold="أنتظر فحص الخطوة الجاية" Run.Heartbeat:Wait() continue end
					nextSafetyAt=os.clock()+.01
				elseif not safety then
     safetyWaitingAt=nil
					Brain.motionHold="الخطوة قدامي ما تأكدت آمنة"
					releaseW("immediate_ground_unsafe") return "unsafe"
				elseif cautious then
     safetyWaitingAt=nil
					Brain.runtimeCaution=true Brain.cautionRecoveryAt=nil
					Brain.lastSafeAt=os.clock() Brain.lastSafeFrom=from Brain.lastSafeHorizon=.8
					nextSafetyAt=os.clock()+.05
				else
					safetyWaitingAt=nil
     if Brain.runtimeCaution then
						Brain.cautionRecoveryAt=Brain.cautionRecoveryAt or os.clock()
						if os.clock()-Brain.cautionRecoveryAt>=1 then Brain.runtimeCaution=false Brain.cautionRecoveryAt=nil end
					end
					Brain.motionHold=nil
					Brain.lastSafeAt=os.clock() Brain.lastSafeFrom=from Brain.lastSafeHorizon=horizon
					nextSafetyAt=os.clock()+.1
				end
			end
			if (root.Position-last).Magnitude>.4 then last=root.Position lastTime=os.clock() end
			local trulyStuck
   progressSample,trulyStuck=Brain.motionProgress(progressSample,root.Position,root.AssemblyLinearVelocity,os.clock(),heldW,Brain.headingAligned==true,flat.Magnitude)
   if trulyStuck then
    Brain.motionHold="انقطعت الحركة؛ أغير المسار بدل الانتظار"
    Brain.motionTrace("smart_nav_stalled",kind.." / waypoint="..tostring(pointIndex))
    releaseW("confirmed_no_progress") return "blocked"
   end
			if not heldW then
				movementFrame()
				if not valid(token,model) then return "cancelled" end
				if prompt(kind) then releaseW("resource_prompt") return "prompt" end
				heldW=true send(Enum.KeyCode.W,true)
			end
			local endDistance=remainingDistance
			local speed=root.AssemblyLinearVelocity.Magnitude
			local deceleration=model:GetAttribute("Deceleration")
			if typeof(deceleration)~="number" or deceleration<=0 then deceleration=45 end
			local brakingDistance=math.clamp(speed*speed/(2*deceleration)+3,6,22)
			arrivalBrake=arrivalBrake or endDistance<=brakingDistance or (kind=="Water"and Brain.home.recordedStations and Brain.homeDistance(root.Position,Brain.home.water)<40)
			local facing=model:GetAttribute("FacingDirection")
			if typeof(facing)~="Vector3" then
    local velocity=root.AssemblyLinearVelocity local movement=Vector3.new(velocity.X,0,velocity.Z)
    facing=movement.Magnitude>2 and movement or root.CFrame.LookVector
   end
			local heading=Vector3.new(facing.X,0,facing.Z)
			local alignment=heading.Magnitude>.01 and heading.Unit:Dot(aim) or -1
			Brain.headingAligned=Brain.policy.heading(Brain.headingAligned,alignment)
			local aligned=Brain.headingAligned==true
			local runningStraight=aligned and not Brain.runtimeCaution and not arrivalBrake
   local allowRun=aligned and not Brain.runtimeCaution and not arrivalBrake and forwardClearance>math.max(8,brakingDistance+2)
			Brain.speedTick(root,model,runningStraight and forwardClearance>8 and (Brain.lastSafeHorizon or 0)>=8 and endDistance>math.max(14,brakingDistance),allowRun)
			Run.Heartbeat:Wait()
		end
		if not valid(token,model) then releaseW() return "cancelled" end
	end
	if route.nextRouteReady and valid(token,model) then Atlas.rememberRoute(route,model) return "handoff" end
 releaseW("route_segment_end")
	Atlas.rememberRoute(route,model)
	return "arrived"
end
function Brain.watchPath(route,token,model)
 if not route.path then return end
 local connections={}
 local function current() return alive and running and generation==token and player.Character==model end
 local ok,connection=pcall(function()
  return route.path.Blocked:Connect(function(index)
   if not current() or not route.walkIndex or index<route.walkIndex then return end
   route.blockedAheadIndex=math.min(route.blockedAheadIndex or math.huge,index)
  end)
 end)
 if not ok then return end table.insert(connections,connection)
 pcall(function() table.insert(connections,route.path.Unblocked:Connect(function(index)
  if current() and route.blockedAheadIndex==index then route.blockedAheadIndex=nil end
 end)) end)
 return {Disconnect=function() for _,signal in connections do signal:Disconnect() end end}
end
local function walk(route,kind,token,model,root)
 local motor=(Brain.mode=="Quests" or not CFG.HomeOnly) and walkCore or walkHomeCore
 for leg=1,64 do
  Brain.motionPhase="walking" route.walkIndex=1 route.blockedAheadIndex=nil
  local pathConnection=Brain.watchPath(route,token,model)
  Brain.motionTrace("walk_begin",kind.." / "..tostring(route.position))
  local ok,result=pcall(motor,route,kind,token,model,root)
  if pathConnection then pathConnection:Disconnect() end
  route.prefetchTicket=nil
  if not ok then if token==generation then Brain.motionPhase=nil end error(result) end
  if result=="handoff" and route.nextRouteReady and valid(token,model) then
   local nextRoute=route.nextRouteReady
   nextRoute.questKey=route.questKey nextRoute.loopJoin=route.loopJoin
   nextRoute.water=route.water nextRoute.exploration=route.exploration nextRoute.intendedDestination=route.intendedDestination
   for key in route do route[key]=nil end
   for key,value in nextRoute do route[key]=value end
   Brain.motionTrace("route_handoff","same destination; W remains held")
  else
   if token==generation then Brain.motionPhase=nil Brain.motionTrace("walk_end",kind.." / "..result) end
   return result
  end
 end
 releaseW("journey_leg_limit") return "blocked"
end
Brain.questCache={} Brain.questStatus="لم تُقرأ المهمات بعد" Brain.questTracker={}
Brain.claimAttempts={} Brain.claimRetryAt={} Brain.questPauseUntil={}
do
 local recordings=game:GetService("HttpService"):JSONDecode([==[[{"place":18214855317,"endZone":"Tshukudu Canyon","points":"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"},{"place":18214855317,"endZone":"Savannah Mirage","points":"pgD2/wz8//9y2wYAt/42AOP9w/5qAL79/f1eAJ/8Ev4DAHr8cf4RAF78mP4AAPL7uv76/+j73P7C/yz8xv54/+f7//4vAFn8+v52AO775v4oAKX7+v4AAAD8A/8AACz87/7//9z78P4BAN77Bf9LAEj85P7jADT80v4PAVX8vv6sAOD72P4KAMT75/5bAO775/5gAOX76f40ANr77f5DAOL77v51AO37//4bACf8Af9/AFj84/57APL74P45AMD7u/0WAJP89/zx/5b9hv3m/7z8bf4lAPb7zv4fAPn79v4MABz87f4OANv77/4MAN/78/4KAO/7Bf8LAC/86f4GAMf7A/8DACv89P4BAPH76v7//8j78P4AAOH7BP/6/y387/75/9z7g/73/3D8jv7z/+/74P74/zb85f71/+H77f72/9z78/73//D76v75/8j77/76/9z79P74//D7//72/xj8A//z/yz88P7v/9v7BP/r/yz88P7j/9375f7e/7L7/P7b/wX8Bf/a/y/8sv3G/7r8lPyw/1P9ZfzE/7n9VPy7/9b9ePy+//L9c/y///D9UPy9/9z9mPzE/wb+YvzF/+f9hvzN//v9Y/zT/+f9hPza//v9T/zg/9v9Tvzn/9z9O/zt/9D9Y/zx/+f9T/zz/9v9mPzz/wb+cPzz/+/9hvzx//v9hPzw//v9l/zv/wX+lfzv/wT+Bf3s/zP9T/7u/zL8yf7x/yr84v75/9/78v4CAPL76v4MAMv78f4UAOL7Bf8dADH89f4eAPD78P4qAN776/4uAMz79f4uAPL76/4xAMv7Bf8uAC/89v4zAPX76/41AMj7Bf85ADD8Cf80AD/86v0zAGn89PwzAIn9svwmANn9nPwlAPn9n/weAP/9uf0UAIz8NP79/yX81vz5/zT92fzy/yr9k/zs/4j9vv3i/8f8dP7a/wX84v7b/zj85/7d/+D79P7l//T7/v7t/xv88P7z/+H77/72/9/77/73/9/77/77/9v7Cf///0T86/4DAMv70f0GAJP8qvwbAF79dPwQAKX98v0DAMH8hP73/xT8YP3u/8381f3j/zn8r/7j/0X82f7Z//f7//7b/y78/v7Y/xf88f7X/9/79P7a/+/7Bv/h/zD8av7g/3P80/zc/z79ufzj/2H9Iv7m/zr8qP74/wb87v4DACD87P4AAPX7kf0CAAP9mfwJAGv9vPzw//X9Q/zZ/8X9X/2FAF/9YP7v/2H8vf4XAAf84v4YAOH76P4kAMz79P4hAPP79f4jAPP7+v43AAn88/4qAO376v7O/8378P6Z/+v76/6W/+L7AP+3/zT8+f7a/w/89P71//X7Bf8KADb88f4jAOf76/47AOb78v5aAPr7a/1hALb8B/5PAFT8n/5PAPH70/4SANT75f/8/9b7bgADAMn7U/8BANv7H/8AABH8/P4AAO778f4AAN377v4AANz7//4AABv89f4AAPD7+f4AAAb8+/4VAAr8BP8aAC787v7+/9f77v7l/9r7BP/n/y38//7r/xz89v7+//X7Af8zACn88P6FAPP76f47ANL7+P44AP37Bv9zACj8/v7V/xP87f56/+H76/7V/9f7Bf/t/zP88/7g/+/76/7y/8779P7r//H7BP/o/y/8Bf/k/zH8Hv/k/5X8bv/q/8n9t//x/+f+"},{"place":18214855317,"endZone":"Pride Rock","points":"7/31/3f8///N3gYAjALC/1v/mALJ/4X/xQM+AHX/1QO7AEr/OQQkABr/5gPn/yf//QNJ/yX/WgOTAGH/9ANaAYr/XwRhAHb/JAQTAHj/AQRiAHz/6ANYAH//QARPAHT/8AMeAH7/QgT9/3L/7gPr/3z/UgTl/3D/PgTi/3L/6gPj/33/KwTh/3T/PwTg/3L/PgTh/3H/PwTl/3H/5wPr/37/UwTv/2//JQT0/3X/PAT4/3P/PgT9/3L/PQT//3P/PAQEAHL//QMCAHv/VAQCAG//FQQAAHj/PQT//3P/PQQCAHL/PwQAAHP/6wP//33/PgT7/3L/7AP5/33/PwT5/3L/6gP5/33/6wP7/37/6QP//33/PwQGAHL/6AMKAH7/OwQWAHL/PgQeAHP/6QMjAH3/vwMqAIP/hgIhAKz/fwEYAM7/"},{"place":18214855317,"endZone":"Hippo Swamp","points":"Jv/1/5b8//8i3wYAMP61/97+kv6M/yj+Gv7u/xn9rf3AALz8nv1HAL38hv1t/2b82v2fABP9l/0WALf8xP3Z/rH84f11ALL89v19AL38r/3Y/zv82v3//oX8Mv6oAAP9+v3eAJ78dP2M/1v8e/26/8z8e/2sALr8Wv0KAAH91vzr/wv9Gf3J/2z94fxPAEf9pPz1/g/9Of3Q/5X94fxZAFb93Pyf/1L92vzu/1D93fzWAHL94vw5AG/9tPwZADz9x/zq/0T9/vys/2P90Pws/yH9H/1G/1v98/yM/zf90PyF/xX97PyK/y/9Hv2w/1X91/xg/wP9AP0u/wf9Av1n/w799fzM/yb9H/0xAHj9wfwXADb9wfz3/zj9mv0UAML8Hv9eAD/8h/+GAOj7s/9IAPL7rv9jANn7MP6XAKX8I/3eAA79tfxTADH9//zN/1n94/yH/xP9F/3F/wz91fx0AF/98PxZAKP9mvxVAG79ofxVAGz9t/zI/z/9+/zZ/0397vy//yH9Nf1v/yT9Gv1D//z8ZP2Q/zH9Iv0///P8Xf2i/xv9OP2X/w/9J/1Z//r8R/3R/0P99/xs/+78IP3Y/zf9D/1q/zz9dPyg/4/9Y/wSAIb/Af0LAJIAe/35/7sBAP76/w0C/v3+/yACLP4AAOUBeP4AAI0BgP4AAHEBq/0AAC4Cc/4AAHIBeP4AAG4BSv4AAJoBTf4AAJcBS/4AAJkBS/4AAJkBU/7+/5EBRP4AAJ8BUf4AAJQBU/4AAJEBS/4AAJkBRf4AAJ8BUP79/5MBS/4BAJkBg/4AAGwBEf4NAEYB2v1VAT0BTf6EAbwAtv0hAgcB9fx3Am4Bx/yaAcwBgPz9AHICe/yNAEcC//saADQByPvm/90Azvvi/+cAEfzm/94A4fvp/70Ap/z0/+j/uPv3/0oADPz7/yMA//sLANX/3fsuAJn/1ftbAGz/DPxmAFz/JfxkAFf/3fteAEn/Bfw5AE7/ovwvAGn/yf0oAJ3/7f4XAND/"},{"place":18214855317,"endZone":"Savannah Heights","points":"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"},{"place":18214855317,"endZone":"Sabie Delta","points":"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"},{"place":18214855317,"endZone":"Savannah Plains","points":"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"},{"place":18214855317,"endZone":"Nyala Forest","points":"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"},{"place":18214855317,"endZone":"Simba Falls","points":"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"},{"place":18214855317,"endZone":"Sablerock","points":"//31/1j8//9D3gYA6wPv/34AEQO3/+P+rgO/AIP+GgRhAEn++QP9/0z+kgPM/3X+1QMXAFv+cQMTAYH+9wNzACr+5gMtAEH+hgNdAFz+sgNqAOz9VwNTAHj9IAI4AHP8ZgMdADz9RgMFAOf9twPw/9v9hgPt/wj+qgPt//j9dAPu/xf+wAPs/+39dwPt/xT+vQPs/+/9hgPu/w3+qAPu//n9iAPv/wz+vQPw/+/9qwPy//j9hgPz/w3+cwP0/xf+rQPz//j9hgPz/w3+rAPx//f9vwPw/+79vwPu/+39swPq/2j//APq/4sAAwTr/yP/uwPb/2z+xAPm/xD+YAMLACf+wQMBAO39wAMFAO79vQMRAO/9cgMYABj+vQMlAO/9ugMtAPH9vAMxAPD90QMyAOX9XwMoACP+iQMkAAz+rQMcAPf9dgMQABb+0gMGAOP9rQP5//j9dQPy/xf+zwPr/+X9rgPp//f90gPn/+T9vAPp//H9rAPp//n9lwPq/wX+mQPp/wP+hgPr/w7+wAPq/+79dAPv/xj+qAPw//v9vgP1/+79cQP6/xn+vAP//+/9cwMCABj+vgMHAO790QMLAOP9qwMNAPn9dAMNABf+vwMRAO79cwMQABf+vgMSAO79vgMVAO79iAMWAAz+qQMbAPr9dAMdABf+vAMlAPH9cgMmABn+hwMrAA/+rAMvAPn9ggMzABL+wQM1AO/9dQMxABj+dAMvABn+rQMtAPr9dwMkABf+vgMgAO/9igMWAAz+rwMPAPf9dwMIABX+hwMDAA3+rgP///f9vQP+/+/9iQMAAAv+dQMDABf+qgMGAPn9vQMLAO79vwMNAO79vgMPAO79vAMSAO79cwMVABf+uwMaAPD9BAQhAGn/+AMtAJwAzwMrAPQACQQuACcByQMpABwBHAQnADcBzAMeAB8BHAQXADYBzAMMAB8BMgQDAD4BCAT3/zEBHATu/zgBLgTk/z0BBQTe/zEBGwTY/zgBGgTT/zgByQPV/yABFwTR/zgBFQTW/zYB6ALl/1sCZgL6/zkDAwL5/08DNALz/y0DqwPr/wwC/APm/4YBFQTq/0gBxQPu/yEBGwTu/zgByAPy/x4BgwPv/4oBxwL0/ycDgAPS/wcC9AM3/5QB6wNh/ksB1gP0/yYBIwTl/zsBGAQv/ygBvgPe/uYAwwM5/8kAoQPC/2cBwAKm/+0CKgIGACsD6gFGAFIDkAGJAX0DjgKPAB8DAgSg//cBvQOW/1QBCgTj/lIBYwN2ABABCgTLAEMBIwT4/z8BOgTG/0YB/gPq/zAB0QMbACEBtgNQAB0BgQPQ/yYCmQH3/qcDhgBxAMcDzgAhAYoD1AL5/1sDPAN6/+QCGAN4/24CXQNR//kBCQQq/+8A0wPq/mQAdQZBAnsAfwQGAF0ARQRr/I8ADQQpAH8A1wMjAJAAjQMIAIwABgP//3sAAAMBAHoAtwIAAG8AbwIAAGQAJQIAAFcAUgMAAIgARQIAAF0ALQIAAG4AUAIAAIQAPgIAAIAAUQIAAIUARgL+/4MAPgIAAIAAPgIAAIEAPgIAAIEARwIAAIIAPgIAAIEAUQL+/4UAUAIAAIUAUAIAAIUAUQIAAIQARwL+/4MAUAIAAIUAPwIAAIEARwIAAIIARwIAAIMAUAL+/4UARwIAAIMASAIAAIMAUAIAAIQATwIAAIUASQIAAIMAUQIAAIUARwIAAIMAPgIAAIAAUQIAAIUAUQIAAIUARwL+/4MAWgIAAIcAWwIAAIcAPgIAAIAARwIAAIMAPgIAAIEABgLj/3wAJwKT/5YAFgKV/5gAHgJ5AJUAqAExAYAA1QKXAdAA7QIvAdoA6QObAPUARgQ2APkAKwQLAO8A+APF/+MABwQEAOcAOQTV//MA3gMNAN4AGATD/+gANgQL//cAdAN3AMsADgTDAPIAAwQ2AOoAIgQcAO8AUASr//QAKwRE/9cAMAQe/6kA2QP//nwAiASW/3IA6wVtAuwA1gScAAwB0QNf/jQBSAMY/TICUgJfAEsCHwKNACICVwJUAowCQQKaAcoC5wJBAZMCBQRhAHoBCQQIABQBGAQBAPUAAQRZAOUA4AMdAOEADgPs/04CjgLl/x4DWALg/3gDKALX/2gDOQLi/48DGALa/1sDFgLY/1cDRALR/6EDIwLT/20DNALV/zMDiQP4/+gB0gMJAEMBDgQSAAUB2QMXAOIAKAQcAP4A0wMaAPgADgQaAFQBygMPAPIBvwMSAAsCcwMVAOwBuwMbABQCzgMdAB8CZgMMAOQBcwMBAOsBogNRAAQCzQMGAB0CpAMqAAcCuQMpACsCRQIkAHgD1AIcALwCegMgAFgCagMcAAQCgQMoAPoBqAMtAAkCjAMUAPgBZwMBAOUBqwNSAAYCjQMpAPgBwQMpABQCcgMiAOkBvgMfABQCzwMYAB0CmgMRAAACdAMMAOsBvAMHABMCggMFAPMBvAMHABQCqgMNAAkCcgMXAOsBzgMiAB4CpwMnAAgCzgMzAB4CpwM4AAgCcAM4AOkBhQM7APUBpwM7AAgCuQM6ABECdQMuAOsBvAMyABMCdgMiAO0BdQMYAOsBigMNAPgBrAMBAAoCvgPy/xUCdAPr/+wBvgPh/xUCvQPb/xYCvgPZ/xYCqgPa/woCgwPc//YBcQPh/+sBvQPi/xUCuQPo/xMCvQPt/xQCuwPy/xQCvAP3/xQCvAP6/xQCvQP6/xQCdAP5/+sBvQP2/xUClgP2//4BqwP2/woCrQP2/wsCvAP3/xQCvAP4/xMCdAP6/+sBvQP8/xQCugP//xICcgMDAOsBuwMHABMCuwMNABQCugMRABMCuQMVABICcgMWAOsBvgMaABYCcgMYAOsBbwMWAOoBcwMVAOwBvQMSABUCvgMOABUCcwMJAOsBvgMGABUCdQMCAO0BvwP8/xUCvgP5/xUChwP2//UBvwPx/xQCqgPv/wgCdgPu/+sB0APp/x0CvAPp/xICqgPq/wgCvgPq/xICcwPt/+oBvAPw/xICzwPy/xwCqwP3/woCvQP6/xMCugP9/xMCcwMAAOsBvAMCABQCdAMEAOsBnQMFAFMC7AH8AOACuAHCAKcDdQGS/z8EfAHi/tkDLgEqAPIDKAEuABYECgEyAMwDDQE5ANYDZAEgANgDRwIiAXwClQJkAgkCvAJCAhgCsAIcAjICsgKMAgMCUAJSA0wBZwINA+cBGgNSAdwCKwNmAHMCSwNAAUoCBANlAfEBSwOuARMCAQOBAd4BDAIPAUYBgAEXAOsA"},{"place":18214855317,"endZone":"Mbali River Bend","points":"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"}]]==])
 local byName={}
 local function decodeRoute(encoded)
  local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local lookup={}
  for i=1,#alphabet do lookup[alphabet:byte(i)]=i-1 end
  local bytes=buffer.create(#encoded/4*3)
  for index=1,#encoded,4 do
   local a,b,c,d=encoded:byte(index,index+3)
   local value=lookup[a]*262144+lookup[b]*4096+lookup[c]*64+lookup[d]
   local offset=(index-1)/4*3
   buffer.writeu8(bytes,offset,math.floor(value/65536))
   buffer.writeu8(bytes,offset+1,math.floor(value/256)%256)
   buffer.writeu8(bytes,offset+2,value%256)
  end
  return bytes
 end
 local function zoneKey(name)
  return typeof(name)=="string" and name:lower():gsub("[^%w]","") or ""
 end
 for _,recording in recordings do
  if game.PlaceId==recording.place then
   local points={}
   local bytes=decodeRoute(recording.points)
   local x,y,z=buffer.readi32(bytes,0),buffer.readi32(bytes,4),buffer.readi32(bytes,8)
   table.insert(points,Vector3.new(x/100,y/100,z/100))
   for offset=12,buffer.len(bytes)-6,6 do
    x+=buffer.readi16(bytes,offset)
    y+=buffer.readi16(bytes,offset+2)
    z+=buffer.readi16(bytes,offset+4)
    table.insert(points,Vector3.new(x/100,y/100,z/100))
   end
   byName[zoneKey(recording.endZone)]={name=recording.endZone,points=points}
  end
 end
 function Brain.recordedQuestZone(name)
  return byName[zoneKey(name)]
 end
 function Brain.recordedZoneMention(description)
  local normalized=description:lower():gsub("%p"," "):gsub("%s+"," ")
  normalized=" "..normalized.." "
  for _,route in byName do
   if normalized:find(" "..route.name:lower().." ",1,true) then return route.name end
  end
 end
 function Brain.recordedQuestZones()
  return byName
 end
 function Brain.questZoneNow(model)
  local name=player:GetAttribute("ZoneName")
  if typeof(name)~="string" or name=="" then
   local character=model or player.Character
   name=character and character:GetAttribute("ZoneName")
  end
  if typeof(name)~="string" or name=="" then return nil end
  local recording=Brain.recordedQuestZone(name)
  return recording and recording.name or name
 end
 local function horizontalDistance(a,b)
  return Vector2.new(a.X-b.X,a.Z-b.Z).Magnitude
 end
 function Brain.recordedQuestSegment(objective,token,model,root)
  local recording=Brain.recordedQuestZone(objective.zone)
  if not recording or objective.hold then return nil,false end
  local points=recording.points
  local progress=Brain.recordedQuestProgress
  if not progress or progress.recording~=recording or progress.key~=objective.key or progress.model~=model then
   progress={recording=recording,key=objective.key,model=model,index=1,failures=0}
   Brain.recordedQuestProgress=progress
  end
  if progress.retryAt and os.clock()<progress.retryAt then return nil,false end
  if progress.index>#points then return nil,false end
  local nearest,nearestDistance
  for index=math.max(1,progress.index-2),math.min(#points,progress.index+7) do
   local point=points[index]
   local distance=horizontalDistance(point,root.Position)
   if distance<=18 and math.abs(point.Y-root.Position.Y)<=13 and (not nearestDistance or distance<nearestDistance) then
    nearest,nearestDistance=index,distance
   end
  end
  local index=progress.index
  if nearest then
   index=math.max(index,nearest)
   if index==nearest and nearestDistance<=4 then index+=1 end
  end
  if index>#points then
   progress.index=index
   return nil,false
  end
  local floor=walkable(root.Position,model,true)
  if not floor or not valid(token,model) then return nil,true end
  local pathPoints={{Position=floor}}
  local endIndex=index-1
  for step=index,math.min(index+6,#points) do
   if not valid(token,model) then return nil,true end
   local previous=pathPoints[#pathPoints].Position
   if horizontalDistance(previous,points[step])>30 then break end
   local nextFloor=walkable(points[step],model,true)
   if not nextFloor or not safeSegment(previous,nextFloor,model,true) then break end
   table.insert(pathPoints,{Position=nextFloor})
   endIndex=step
  end
  if endIndex>=index then
   return {position=pathPoints[#pathPoints].Position,points=pathPoints,recordedEnd=endIndex},true
  end
  local checkpoint=points[index]
  local route=Brain.travelRoute(checkpoint,token,model,root)
  if route then
   route.transit=false
   if horizontalDistance(route.position,checkpoint)<=4 then route.recordedEnd=index end
   return route,true
  end
  progress.failures+=1
  if progress.failures>=3 then
   progress.failures=0
   progress.retryAt=os.clock()+20
   return nil,false
  end
  return nil,true
 end
end
Brain.questFocus={Group=false,Swim=true,Survival=true,PlayTime=true,Land=true,Zone=true,VisitZone=true,Explore=true,Food=true,Water=true,Night=true,Growth=true}
function Brain.questKind(title,description)
	local t=string.lower(title.." "..description)
 if t:find("play time",1,true) or t:find("playtime",1,true) or t:find("time played",1,true) or t:find("play for",1,true) or t:find("hours playing",1,true) or (t:match("%f[%a]play%f[%A]") and (t:find("hour",1,true) or t:find("minute",1,true))) then return "PlayTime" end
	if (t:find("surviv",1,true) or t:find("stay alive",1,true)) and t:find("zone",1,true) then return "Zone" end
	if t:find("explore",1,true) or t:find("different zones",1,true) or t:find("different regions",1,true) or t:find("different areas",1,true) then return "Explore" end
	if t:find("visit",1,true) or (t:find("سافر",1,true) and (t:find("إلى ",1,true) or t:find("الى ",1,true))) then return "VisitZone" end
 if t:find("swim",1,true) or t:find("سباح",1,true) then return "Swim" end
	if t:find("land distance",1,true) or t:find("on land",1,true) or t:find("walk",1,true) or t:find("walking",1,true) or t:find("distance travelled",1,true) or t:find("distance traveled",1,true) or t:find("steps",1,true) or t:find("مشي",1,true) or t:find("امش",1,true) or t:find("سافر",1,true) or t:match("%f[%a]travel%f[%A]") then return "Land" end
	if t:find("night owl",1,true) or t:find("at night",1,true) then return "Night" end
	if t:find("group",1,true) then return "Group" end
	if t:find("swim",1,true) then return "Swim" end
	if t:find("grow",1,true) then return "Growth" end
	if t:find("drink",1,true) or t:find("water bar",1,true) then return "Water" end
	if t:find("eat",1,true) or t:find("food bar",1,true) then return "Food" end
	if t:find("surviv",1,true) or t:find("stay alive",1,true) then return "Survival" end
	return "Other"
end
function Brain.resolveQuestZone(description)
	local quoted=description:match("'([^']+)'") or description:match('"([^"]+)"')
	if quoted then
		local recording=Brain.recordedQuestZone(quoted)
		return recording and recording.name or quoted
	end
	local recorded=Brain.recordedZoneMention(description)
	if recorded then return recorded end
	local zones=workspace:FindFirstChild("MapZones")
	if zones then
		local lower=string.lower(description) local count=0
		for _,zone in zones:GetChildren() do
			count+=1 if count>40 then break end
			if string.find(lower,string.lower(zone.Name),1,true) then return zone.Name end
		end
	end
end
function Brain.questUI()
 local screen=pg:FindFirstChild("QuestsScreenGui")
 if not screen then
  for _,child in pg:GetChildren() do
   if child:IsA("ScreenGui") and string.lower(child.Name):find("quest",1,true) then screen=child break end
  end
 end
 if not screen then return end
 local scroll=screen:FindFirstChild("RefScrollingFrame",true)
 if not scroll then scroll=screen:FindFirstChildWhichIsA("ScrollingFrame",true) end
 local frame=screen:FindFirstChild("Frame")
 if not frame and scroll then
  frame=scroll
  while frame.Parent and frame.Parent~=screen do frame=frame.Parent end
 end
 return screen,frame,scroll
end
function Brain.questAnimal(description)
 local lower=string.lower(description)
 local animal=lower:match("as an? ([%a%s%-]+) for") or lower:match("as ([%a%s%-]+) for") or lower:match("as an? ([%a%s%-]+)%.?$")
 if not animal or animal:find("any",1,true) or animal:find("character",1,true) then return end
 return animal:gsub("^%s+",""):gsub("%s+$","")
end
function Brain.animalMatches(required,current)
 if not required then return true end
 local a=string.lower(tostring(required)):gsub("african%s+",""):gsub("[^%a]","")
 local b=string.lower(tostring(current or "")):gsub("african%s+",""):gsub("[^%a]","")
 a=a:gsub("bushelephant","elephant"):gsub("capebuffalo","buffalo")
 b=b:gsub("bushelephant","elephant"):gsub("capebuffalo","buffalo")
 return a==b
end
function Brain.questClean(value)
 return tostring(value or ""):gsub("<[^>]->",""):gsub("^%s+",""):gsub("%s+$","")
end
function Brain.questRatio(value)
 local clean=Brain.questClean(value):gsub(",",""):gsub("٬",""):gsub("٫",".")
 for digit,number in pairs({["٠"]="0",["١"]="1",["٢"]="2",["٣"]="3",["٤"]="4",["٥"]="5",["٦"]="6",["٧"]="7",["٨"]="8",["٩"]="9"}) do clean=clean:gsub(digit,number) end
 clean=clean:gsub("ألف","k"):gsub("الف","k"):gsub("مليون","m")
 local a,unitA,b,unitB=clean:match("(%d+%.?%d*)%s*(%a*)%s*/%s*(%d+%.?%d*)%s*(%a*)")
 a,b=tonumber(a),tonumber(b)
 local scales={k=1000,K=1000,m=1000000,M=1000000}
 if a then a*=scales[unitA] or 1 end
 if b then b*=scales[unitB] or 1 end
 if a and b and a>=0 and b>0 then return a,b end
end
function Brain.questNodes(parent,limit)
 local queue={parent} local result={} local index=1
 while index<=#queue and #result<limit do
  local node=queue[index] index+=1
  for _,child in node:GetChildren() do
   result[#result+1]=child queue[#queue+1]=child
   if #result>=limit then break end
  end
 end
 return result
end
function Brain.questFields(card,progressNode)
 local nodes=Brain.questNodes(card,80) local progressCount=0
 for _,node in nodes do if node:IsA("TextLabel") and Brain.questRatio(node.Text) then progressCount+=1 end end
 if progressCount~=1 then return end -- Never combine two cards into one fabricated task.
 local info=card:FindFirstChild("InfoFrame",true)
 local title=info and info:FindFirstChild("TitleTextLabel",true)
 local description=info and info:FindFirstChild("InfoTextLabel",true)
 if title and description and title:IsA("TextLabel") and description:IsA("TextLabel") then return title,description end
 local texts={}
 for _,node in nodes do
  if node~=progressNode and node:IsA("TextLabel") then
   local value=Brain.questClean(node.Text) local lower=string.lower(value)
   if #value>=3 and not Brain.questRatio(value) and not lower:find("coin",1,true) and not value:match("^%d+$") then table.insert(texts,{node=node,value=value}) end
  end
 end
 local shortest
 for _,item in texts do
  if Brain.questKind(item.value,"")~="Other" and #item.value<=80 and (not shortest or #item.value<#shortest.value) then shortest=item end
 end
 if not shortest then return end
 local longest
 for _,item in texts do if item~=shortest and #item.value>=12 and (not longest or #item.value>#longest.value) then longest=item end end
 if longest then return shortest.node,longest.node end
end
function Brain.questClaimButton(card)
 if not card or not card.Parent then return end
 local frame=card:FindFirstChild("ClaimFrame",true)
 if frame and frame:IsA("GuiObject") and not frame.Visible then return end
 local candidates=Brain.questNodes(frame or card,80)
 if frame and frame:IsA("GuiButton") then table.insert(candidates,1,frame) end
 local best,priority
 for _,node in candidates do
  if not node:IsA("GuiButton") or not node.Visible or node.AbsoluteSize.X<2 or node.AbsoluteSize.Y<2 then continue end
  local name=node.Name
  local label=node:IsA("TextButton") and Brain.questClean(node.Text):lower() or ""
  local matchesLabel=label=="claim" or label=="استلام" or label=="استلم" or label=="استلام المكافأة"
  local score=matchesLabel and 4 or (frame and name=="ClickDetectorButton" and 3 or (name=="ClaimButton" and 2 or nil))
  if score and (not priority or score>priority) then best,priority=node,score end
 end
 return best
end
function Brain.questClaimReady(quest)
 local title,description,progress=quest.titleObject,quest.descriptionObject,quest.progressObject
 if not quest.row.Parent or not title.Parent or not description.Parent or not progress.Parent then return end
 if Brain.questClean(title.Text)~=quest.title or Brain.questClean(description.Text)~=quest.description then return end
 local current,target=Brain.questRatio(progress.Text)
 if not current or target~=quest.target or current<target then return end
 return Brain.questClaimButton(quest.row)
end
function Brain.readQuestUI(requestedBucket)
 local _,_,scroll=Brain.questUI()
 if not scroll then return {},nil end
 local rows,seen={},{} local inferred
 for _,progress in Brain.questNodes(scroll,320) do
  if #rows>=30 then break end
  if not progress:IsA("TextLabel") then continue end
  local current,target=Brain.questRatio(progress.Text)
  if not current then continue end
  local card=progress.Parent local title,description
  for depth=1,6 do
   if not card or card==scroll then break end
   title,description=Brain.questFields(card,progress)
   if title and description then break end
   card=card.Parent
  end
  if not title or not description then continue end
  local titleText,descriptionText=Brain.questClean(title.Text),Brain.questClean(description.Text)
  local key=titleText.."\31"..descriptionText.."\31"..target
  if seen[key] then continue end seen[key]=true
  local tier=titleText:match("%s([IV]+)$")
  local bucket=(tier=="I" or tier=="II") and "Daily" or ((tier=="III" or tier=="IV") and "Weekly" or nil)
  if bucket then if inferred and inferred~=bucket then inferred="Loaded" else inferred=bucket end end
  local claim=Brain.questClaimButton(card)
  table.insert(rows,{key=key,title=titleText,description=descriptionText,current=current,target=target,
   kind=Brain.questKind(titleText,descriptionText),zone=Brain.resolveQuestZone(descriptionText),requiredAnimal=Brain.questAnimal(descriptionText),
   complete=current>=target,claim=claim,
   row=card,titleObject=title,descriptionObject=description,progressObject=progress,seenAt=os.clock()})
 end
 local bucket=inferred or requestedBucket or "Loaded"
 if #rows>0 then
  for _,q in rows do q.key=bucket.."\30"..q.key q.bucket=bucket end
  if bucket~="Loaded" then Brain.questCache.Loaded=nil end
  Brain.questCache[bucket]={rows=rows,at=os.clock()} Brain.questTab=bucket
 end
 return rows,bucket
end
function Brain.readQuests()
	if os.clock()>=(Brain.nextQuestRead or 0) then Brain.nextQuestRead=os.clock()+1 Brain.readQuestUI() end
	local rows,seen={},{}
	for bucket,snapshot in Brain.questCache do
		if os.clock()-snapshot.at<180 then
			for _,q in snapshot.rows do
    if q.progressObject and q.progressObject.Parent and q.titleObject and q.titleObject.Parent and Brain.questClean(q.titleObject.Text)==q.title
     and q.descriptionObject and Brain.questClean(q.descriptionObject.Text)==q.description then
     local value,target=Brain.questRatio(q.progressObject.Text)
     if value and target==q.target then q.current=value q.complete=value>=target q.seenAt=os.clock() end
    end
				if not seen[q.key] then q.bucket=bucket table.insert(rows,q) seen[q.key]=true end
			end
		end
	end
	Brain.quests=rows
	return rows
end
function Brain.clickQuestUI(button,claimRow)
	if not CFG.QuestsEnabled or not button or not button:IsA("GuiButton") or not Brain.focused or not inputOwnerValid() or not gui.Parent then return false end
	local allowed=button.Name=="DailyButton" or button.Name=="WeeklyButton" or button.Name=="QuestsButton" or button.Name=="CloseButton"
	allowed=allowed or Brain.groupCapability==button
	if claimRow then
		local screen,_,scroll=Brain.questUI()
		if not screen or not scroll or not claimRow:IsDescendantOf(scroll) or Brain.questClaimButton(claimRow)~=button then return false end
		allowed=true
	end
	if not allowed or not button:IsDescendantOf(pg) or not button.Visible or button.AbsoluteSize.X<2 then return false end
	local parent=button
	while parent and parent~=pg do
		if parent:IsA("GuiObject") and not parent.Visible then return false end
		if parent:IsA("ScreenGui") and not parent.Enabled then return false end
		parent=parent.Parent
	end
	local center=button.AbsolutePosition+button.AbsoluteSize/2
	local camera=workspace.CurrentCamera
	if not camera or center.X<1 or center.Y<1 or center.X>=camera.ViewportSize.X or center.Y>=camera.ViewportSize.Y then return false end
	local ok,hits=pcall(function() return pg:GetGuiObjectsAtPosition(center.X,center.Y) end)
	if not ok then return false end
	local hitTarget=false
	for _,hit in hits do
		if hit==button or hit:IsDescendantOf(button) then hitTarget=true break end
		if not button:IsDescendantOf(hit) then
			local decoration=claimRow and hit:IsDescendantOf(claimRow) and not hit:IsA("GuiButton") and not hit:IsA("TextBox")
			if not decoration then return false end
		end
	end
	if not hitTarget then return false end
	return pcall(function()
		vim:SendMouseButtonEvent(center.X,center.Y,0,true,game,0)
		vim:SendMouseButtonEvent(center.X,center.Y,0,false,game,0)
	end)
end
function Brain.claimVisibleQuests(rows,token,model)
 if not CFG.AutoClaim then return end
 local _,_,scroll=Brain.questUI()
 for _,quest in rows do
  if not valid(token,model) or not CFG.AutoClaim or not CFG.QuestsEnabled then return end
  local food,water=stats()
  if not food or not water or (Brain.mode~="Quests" and (food<CFG.Threshold or water<CFG.Threshold)) then return end
  if not quest.complete or os.clock()<(Brain.claimRetryAt[quest.key] or 0) then continue end
  if not Brain.questClaimReady(quest) then continue end
  local previous=scroll and scroll.CanvasPosition
  if scroll and scroll:IsA("ScrollingFrame") then
   local y=quest.row.AbsolutePosition.Y-scroll.AbsolutePosition.Y+previous.Y
   local maxY=math.max(0,scroll.AbsoluteCanvasSize.Y-scroll.AbsoluteSize.Y)
   scroll.CanvasPosition=Vector2.new(previous.X,math.clamp(y-8,0,maxY))
   task.wait(.12)
  end
  if valid(token,model) and CFG.AutoClaim and CFG.QuestsEnabled then
   local button=Brain.questClaimReady(quest)
   local clicked=button and Brain.clickQuestUI(button,quest.row)
   Brain.claimRetryAt[quest.key]=os.clock()+(clicked and 8 or 2)
   if clicked then
    Brain.claimAttempts[quest.key]=os.clock()
    Brain.questStatus="أُرسل طلب استلام "..quest.title.."؛ أنتظر تحديث اللعبة"
    Brain.nextQuestScan=math.min(Brain.nextQuestScan or math.huge,os.clock()+2)
    task.wait(.20)
   elseif button then
    Brain.questStatus="زر الاستلام ظاهر لكن المشغّل لم يرسل الضغط إلى اللعبة"
   end
  end
  if token==generation and scroll and previous and scroll.Parent then scroll.CanvasPosition=previous end
 end
end
function Brain.waitQuestTab(bucket,token,model)
 local deadline=os.clock()+1.5
 local rows,actual={},nil
 repeat
  if not valid(token,model) then return {},nil end
  rows,actual=Brain.readQuestUI(bucket)
  if #rows>0 and actual==bucket then return rows,actual end
  task.wait(.1)
 until os.clock()>=deadline
 return rows,actual
end
function Brain.completedQuestDue()
 if not CFG.AutoClaim then return false end
 for _,q in Brain.readQuests() do
  if q.complete and q.claim and os.clock()>=((Brain.claimRetryAt or {})[q.key] or 0) then return true end
 end
 return false
end
function Brain.questService(token,model)
	if not CFG.QuestsEnabled or os.clock()<(Brain.nextQuestScan or 0) then return end
	Brain.nextQuestScan=os.clock()+45
	if not Brain.focused then Brain.readQuests() Brain.questStatus="قراءة المحمّل؛ تبديل التبويبات ينتظر العودة للعبة" return end
	local f,w=stats()
	if not f or not w or f<20 or w<20 or (Brain.mode~="Quests" and (f<CFG.Threshold or w<CFG.Threshold)) then Brain.nextQuestScan=os.clock()+5 Brain.readQuests() Brain.questStatus="أهتم بالأكل والماء أولًا ثم أكمل المهمة المختارة" return end
	local lease=Brain.suspendQuestPanel and Brain.suspendQuestPanel()
	local opened=false
	local ok,err=pcall(function()
		releaseW()
		local screen,frame=Brain.questUI()
		if not screen or not screen.Enabled or not frame or not frame.Visible then
			local statsUI=pg:FindFirstChild("AnimalStatsScreenGui")
			local main=statsUI and statsUI:FindFirstChild("MainFrame")
			local statsFrame=main and main:FindFirstChild("StatsFrame")
			local buttons=statsFrame and statsFrame:FindFirstChild("ButtonsFrame")
			if not Brain.clickQuestUI((buttons and buttons:FindFirstChild("QuestsButton")) or pg:FindFirstChild("QuestsButton",true)) then
				Brain.nextQuestScan=os.clock()+5 Brain.questStatus="افتح لوحة QUESTS مرة؛ تعذر الوصول لزرها" Brain.readQuestUI() return
			end
			opened=true
        local panelDeadline=os.clock()+1.5
        repeat
         task.wait(.1)
         screen,frame=Brain.questUI()
         if not valid(token,model) then return end
        until (screen and screen.Enabled and frame and frame.Visible) or os.clock()>=panelDeadline
			screen,frame=Brain.questUI()
		end
		if not valid(token,model) or not screen or not screen.Enabled or not frame or not frame.Visible then return end
		local tabs=frame:FindFirstChild("TopButtonsFrame")
		for _,bucket in {"Daily","Weekly"} do
			local nf,nw=stats()
			if not valid(token,model) or not nf or not nw or (nf<20 or nw<20 or (Brain.mode~="Quests" and (nf<CFG.Threshold or nw<CFG.Threshold))) then return end
			Brain.readQuestUI()
			local button=tabs and tabs:FindFirstChild(bucket.."Button")
			local clicked=Brain.clickQuestUI(button)
			if clicked then task.wait(.2) end
			if not valid(token,model) then return end
			local actualRows,actualBucket
			if clicked then actualRows,actualBucket=Brain.waitQuestTab(bucket,token,model) else actualRows,actualBucket=Brain.readQuestUI() end
			if actualBucket==bucket then Brain.questStatus="قرأت "..bucket.." • "..#actualRows.." مهمة"
			else Brain.questStatus="لم يتأكد تبديل "..bucket.."؛ أستخدم الصفوف المقروءة فقط" end
			Brain.claimVisibleQuests(actualRows,token,model)
		end
  local objective=Brain.objective()
  local wanted
  for _,q in Brain.quests do if objective and q.key==objective.key then wanted=q.bucket break end end
  if wanted and (wanted=="Daily"or wanted=="Weekly")and valid(token,model)then
   if Brain.clickQuestUI(tabs and tabs:FindFirstChild(wanted.."Button"))then Brain.waitQuestTab(wanted,token,model)end
  end
	end)
	if opened and valid(token,model) then local _,frame=Brain.questUI() if frame then Brain.clickQuestUI(frame:FindFirstChild("CloseButton")) end end
	if Brain.restoreQuestPanel then Brain.restoreQuestPanel(lease) end
	if not ok or #Brain.quests==0 then Brain.nextQuestScan=os.clock()+5 end
 if not ok then Brain.questStatus="تعذر تحديث الواجهة؛ أستخدم القراءة المؤكدة فقط" end
end
Brain.groupNextAt=0 Brain.groupStatus="بانتظار مهمة مجموعة"
function Brain.groupNodes(parent,limit)
 local queue={parent} local result={} local i=1
 while i<=#queue and #result<limit do
  local node=queue[i] i+=1
  for _,child in node:GetChildren() do
   if child~=gui then table.insert(result,child) table.insert(queue,child) if #result>=limit then break end end
  end
 end
 return result
end
function Brain.uiText(node)
 if node:IsA("TextLabel") or node:IsA("TextButton") then return (string.upper(node.Text):gsub("<[^>]->",""):gsub("^%s+",""):gsub("%s+$","")) end
 return ""
end
function Brain.groupPanel()
 for _,screen in pg:GetChildren() do
  if screen~=gui and screen:IsA("ScreenGui") and string.find(string.lower(screen.Name),"group",1,true) then
   local nodes=Brain.groupNodes(screen,500)
   for _,node in nodes do
    if Brain.uiText(node)=="GROUPING" then
     local frame=node.Parent
     for _=1,6 do
      if not frame or frame==screen then break end
      if frame:IsA("GuiObject") then
       local explore,myGroup=false,false
       for _,child in Brain.groupNodes(frame,350) do
        local label=Brain.uiText(child)
        if label=="EXPLORE" then explore=true elseif label=="MY GROUP" then myGroup=true end
       end
       if explore and myGroup then return screen,frame end
      end
      frame=frame.Parent
     end
    end
   end
  end
 end
end
function Brain.groupButton(parent,label)
 for _,node in Brain.groupNodes(parent,500) do
  if Brain.uiText(node)==label then
   local button=node
   for _=1,4 do
    if button:IsA("GuiButton") then return button end
    button=button.Parent if not button or button==parent then break end
   end
  end
 end
end
function Brain.groupClose(panel)
 for _,node in Brain.groupNodes(panel,120) do
  if node:IsA("GuiButton") and (string.lower(node.Name)=="closebutton" or Brain.uiText(node)=="X" or Brain.uiText(node)=="×") then return node end
 end
end
function Brain.groupClick(button)
 if not button or not button:IsDescendantOf(pg) then return false end
 Brain.groupCapability=button
 local ok=Brain.clickQuestUI(button)
 Brain.groupCapability=nil
 return ok
end
function Brain.groupOpener()
 local screen=pg:FindFirstChild("AnimalStatsScreenGui")
 local main=screen and screen:FindFirstChild("MainFrame")
 local statsFrame=main and main:FindFirstChild("StatsFrame")
 local buttons=statsFrame and statsFrame:FindFirstChild("ButtonsFrame")
 if not buttons then return end
 for _,button in buttons:GetChildren() do
  local name=string.lower(button.Name)
  if button:IsA("GuiButton") and (name:find("group",1,true) or name=="groupingbutton") then return button end
 end
end
function Brain.groupRow(button,panel,animal)
 local row=button.Parent
 for _=1,4 do
  if not row or row==panel then return end
  local nodes=Brain.groupNodes(row,80)
  local species,members,joins,hasCount=false,0,0,false
  for _,node in nodes do
   local label=Brain.uiText(node)
   if label==string.upper(animal) then species=true end
   if label=="JOIN" then joins+=1 end
   local count=label:match("^(%d+)%s*/")
   if count then hasCount=true members=math.max(members,tonumber(count) or 0) end
  end
  if hasCount and joins>=1 then return species and members>=1 and joins==1 end
  row=row.Parent
 end
end
function Brain.groupIntegration()
 local report={buttons={},panel={}}
 local statsUI=pg:FindFirstChild("AnimalStatsScreenGui")
 if statsUI then
  for _,node in Brain.groupNodes(statsUI,250) do
   if node:IsA("GuiButton") then table.insert(report.buttons,node:GetFullName()) end
  end
 end
 local screen,panel=Brain.groupPanel()
 if screen then report.screen=screen.Name end
 if panel then
  for i,node in Brain.groupNodes(panel,250) do
   if node:IsA("GuiButton") then
    table.insert(report.panel,{path=node:GetFullName(),class=node.ClassName,visible=visible(node),label=Brain.uiText(node)})
   end
  end
 end
 return report
end
function Brain.groupService(token,model)
 if not Brain.questFocus or not Brain.questFocus.Group then Brain.groupStatus="مهام القروبات متجاهلة" return end
 local needed=false
 for _,q in Brain.readQuests() do if q.kind=="Group" and not q.complete then needed=true break end end
 if not Brain.policy.groupDue(CFG.QuestsEnabled,needed,os.clock(),Brain.groupNextAt) or not Brain.focused then return end
 local food,water=stats()
 if not food or not water or (Brain.mode~="Quests" and (food<CFG.Threshold or water<CFG.Threshold)) then return end
 Brain.groupNextAt=os.clock()+1200
 releaseW("group_check")
 local lease=Brain.suspendQuestPanel and Brain.suspendQuestPanel()
 local opened=false local panel
 local ok=pcall(function()
  local screen
  screen,panel=Brain.groupPanel()
  if not screen or not screen.Enabled or not panel or not visible(panel) then
   if not Brain.groupClick(Brain.groupOpener()) then Brain.groupStatus="لم أجد زر القروبات؛ افتح القائمة مرة لتسجيل بنيتها" return end
   opened=true task.wait(.3)
   if not valid(token,model) then return end
   screen,panel=Brain.groupPanel()
  end
  if not panel or not visible(panel) then Brain.groupStatus="لم تتأكد نافذة القروبات" return end
  local myGroup=Brain.groupButton(panel,"MY GROUP")
  if myGroup then Brain.groupClick(myGroup) task.wait(.2) end
  if not valid(token,model) then return end
  local noGroup=false
  for _,node in Brain.groupNodes(panel,350) do
   if visible(node) and Brain.uiText(node):find("YOU ARE NOT IN A GROUP",1,true) then noGroup=true break end
  end
  if not noGroup then Brain.groupJoined=true Brain.groupStatus="لم يظهر أنك خارج مجموعة؛ أراقب عدّاد المهمة" return end
  Brain.groupJoined=false
  local explore=Brain.groupButton(panel,"EXPLORE")
  if not Brain.groupClick(explore) then Brain.groupStatus="تعذر فتح استكشاف القروبات" return end
  task.wait(.3)
  if not valid(token,model) then return end
  local animal=tostring(model:GetAttribute("AnimalName") or "")
  local attempted=false
  for _,node in Brain.groupNodes(panel,500) do
   if Brain.uiText(node)=="JOIN" and visible(node) then
    local button=node:IsA("GuiButton") and node or node.Parent
    if button and button:IsA("GuiButton") and Brain.groupRow(button,panel,animal) then
     if Brain.groupClick(button) then
      attempted=true Brain.motionTrace("group_join_attempt",animal)
      Brain.groupStatus="ضغطت انضمام؛ التحقق من العضوية عبر عدّاد المهمة"
      task.wait(.4) break
     end
    end
   end
  end
  if not attempted then Brain.groupStatus="لا مجموعة مناسبة الآن؛ الفحص التالي بعد 20 دقيقة" end
 end)
 if opened and panel and valid(token,model) then Brain.groupClick(Brain.groupClose(panel)) end
 if Brain.restoreQuestPanel then Brain.restoreQuestPanel(lease) end
 if not ok then Brain.groupStatus="تعذر فحص القروبات؛ المحاولة التالية بعد 20 دقيقة" end
end
Brain.questLabels={Land="مشي",Zone="بقاء بمنطقة",VisitZone="زيارة",Explore="استكشاف",Group="قروب",Food="أكل",Water="شرب",Night="بقاء ليلي",Growth="نمو",Survival="بقاء",Swim="سباحة مفحوصة",PlayTime="وقت لعب",Other="غير مدعومة"}
function Brain.questHint(q)
 if q.requiredAnimal and not Brain.animalMatches(q.requiredAnimal,player.Character and player.Character:GetAttribute("AnimalName")) then return "المهمة تحتاج "..q.requiredAnimal.."؛ بدّل الشخصية يدويًا لو تبيها" end
 if q.complete then return "المهمة مكتملة؛ أتحقق من استلامها" end
 if not Brain.questFocus[q.kind] then return "نوع غير مربوط بالتنفيذ؛ لا أدّعي أنه مكتمل" end
 if q.kind=="Zone" or q.kind=="VisitZone" then return "الوجهة: "..tostring(q.zone or "تحتاج قراءة اسم المنطقة") end
 if q.kind=="Land" then return "أكرر دائرتك المسجلة حتى يكتمل عدّاد سافر، وأقدّم الأكل والماء عند الحاجة" end
 if q.kind=="Group" then return Brain.groupStatus end
 if q.kind=="Swim" then return "يواصل السباحة حتى يؤكد عدّاد المهمة الاكتمال، مع خروج للراحة أو الخطر ثم متابعة" end
 if q.kind=="Explore" then return "يزور مناطق مختلفة حتى يكتمل العدد المطلوب في عدّاد اللعبة" end
 if q.kind=="PlayTime" then return "وقت اللعب يتقدم من عدّاد اللعبة؛ أراقب احتياج الحيوان أثناء الانتظار" end
 if q.kind=="Growth" then
  local value=Brain.growthValue and Brain.growthValue(player.Character)
  if value and value>=100 then return "النسخة بالغة؛ تحتاج نسخة صغيرة للنمو. وضع التكبير مستقل" end
  return "يرعى النسخة الحالية أثناء النمو الطبيعي؛ تغيير الحيوان يحتاج اختيارك"
 end
 if q.kind=="Food" or q.kind=="Water" then return "أتفاعل مع المورد المطلوب بعد ظهور خيار اللعبة" end
 return "التقدم والاستلام من عدّاد اللعبة نفسه"
end
function Brain.questSummary()
	local lines={Brain.questStatus,Brain.groupStatus}
	for _,q in Brain.readQuests() do
		local suffix=q.complete and " • مكتملة" or ""
		if not q.complete then
		if q.kind=="Group" then suffix=" • يبحث عن مجموعة كل 20 دقيقة"
		elseif q.kind=="Swim" then suffix=" • مسار ماء مفحوص وخروج لليابس"
		elseif q.kind=="Growth" then suffix=" • بقاء دون مسح نمو"
		elseif q.kind=="Other" then suffix=" • نوع غير مدعوم" end
		if (q.kind=="Zone" or q.kind=="VisitZone") and (not q.zone or #Brain.zoneParts(q.zone)==0) then suffix=" • المنطقة غير معروفة أو غير محمّلة" end
		end
		table.insert(lines,(q.bucket or "Loaded").." • "..q.title.." "..q.current.."/"..q.target..suffix)
	end
	return table.concat(lines,"\n")
end
Brain.zoneMemory={}
function Brain.zoneParts(name)
	local zones=workspace:FindFirstChild("MapZones")
	local zone=zones and zones:FindFirstChild(name)
 if zones and not zone then
  local wanted=string.lower(tostring(name)):gsub("[^%w]","")
  for index,candidate in zones:GetChildren() do
   if index>50 then break end
   if string.lower(candidate.Name):gsub("[^%w]","")==wanted then zone=candidate break end
  end
 end
	if not zone then return Brain.zoneMemory[name] or {} end
 if zone:IsA("BasePart") then
  Brain.zoneMemory[name]={{CFrame=zone.CFrame,Size=zone.Size,Position=zone.Position}} return {zone}
 end
	local parts={}
	for _,part in zone:GetChildren() do
		if part:IsA("BasePart") then table.insert(parts,part) if #parts>=12 then break end end
	end
 if #parts>0 then
  local snapshot={}
  for _,part in parts do table.insert(snapshot,{CFrame=part.CFrame,Size=part.Size,Position=part.Position}) end
  Brain.zoneMemory[name]=snapshot
 end
 return #parts>0 and parts or (Brain.zoneMemory[name] or {})
end
function Brain.zoneAnchor(name,root,model)
	local best,bestDistance,hint,hintDistance
	for _,part in Brain.zoneParts(name) do
		local localRoot=part.CFrame:PointToObjectSpace(root.Position)
		local half=part.Size/2
		local inset=math.min(12,half.X/3,half.Z/3)
		local x=math.clamp(localRoot.X,-half.X+inset,half.X-inset)
		local z=math.clamp(localRoot.Z,-half.Z+inset,half.Z-inset)
		for _,offset in {Vector3.new(x,0,z),Vector3.zero,Vector3.new(half.X*.4,0,0),Vector3.new(-half.X*.4,0,0),Vector3.new(0,0,half.Z*.4),Vector3.new(0,0,-half.Z*.4)} do
			local world=part.CFrame:PointToWorldSpace(offset)
			local horizontal=Vector3.new(world.X-root.Position.X,0,world.Z-root.Position.Z).Magnitude
   if not hintDistance or horizontal<hintDistance then hint=world hintDistance=horizontal end
   local hit=terrainAt(Vector3.new(world.X,root.Position.Y,world.Z))
			if dry(hit) then
				local inside=part.CFrame:PointToObjectSpace(hit.Position)
				if math.abs(inside.X)<half.X and math.abs(inside.Z)<half.Z then
					local distance=(hit.Position-root.Position).Magnitude
					if not bestDistance or distance<bestDistance then best=hit.Position bestDistance=distance end
				end
			end
		end
	end
	if not best and hint and Brain.requestRegion then Brain.requestRegion(hint) end
 return best or hint
end
function Brain.questScore(q,currentZone)
 if Brain.questFocus and not Brain.questFocus[q.kind] then return end
 if q.kind=="Food" and player.Character then
  local diet=player.Character:GetAttribute("FoodType")
  if diet and string.lower(tostring(diet))~="grass" then return end
 end
 if q.requiredAnimal and not Brain.animalMatches(q.requiredAnimal,player.Character and player.Character:GetAttribute("AnimalName")) then return end
 if q.kind=="Growth" and Brain.growthValue and player.Character then
  local growth=Brain.growthValue(player.Character) if growth and growth>=100 then return end
 end
 if q.complete or (type(q.current)=="number" and type(q.target)=="number" and q.current>=q.target) then return end
	if (Brain.questPauseUntil[q.key] or 0)>os.clock() then return end
	if (q.kind=="Zone" or q.kind=="VisitZone") and q.zone then
		if currentZone==q.zone then return 0 end
		if Brain.recordedQuestZone(q.zone) or #Brain.zoneParts(q.zone)>0 then return 10 end
		return
	end
	if q.kind=="Explore" then return 30 end
	if q.kind=="Land" then return 40 end
 if q.kind=="Swim" then return 50 end
 if q.kind=="PlayTime" then return 80 end
	if q.kind=="Group" then
  if (Brain.groupNextAt or 0)>os.clock() and not Brain.groupJoined then return end
  return 90
 end
	if q.kind=="Night" then
  local hour=game:GetService("Lighting").ClockTime
  if hour>=6 and hour<18 then return end
  return 70
 end
	if q.kind=="Food" or q.kind=="Water" or q.kind=="Growth" or q.kind=="Survival" then return 80 end
end
function Brain.pointInZone(position,name)
	for _,part in Brain.zoneParts(name) do
		local p=part.CFrame:PointToObjectSpace(position) local h=part.Size/2
		if math.abs(p.X)<h.X and math.abs(p.Y)<h.Y and math.abs(p.Z)<h.Z then return true end
	end
	return false
end
Brain.explorePlans={}
function Brain.exploreTarget(q,current,root)
 local plan=Brain.explorePlans[q.key]
 if not plan or q.current<plan.progress then
  plan={progress=q.current,visited={},blocked={}} Brain.explorePlans[q.key]=plan
  if Brain.questDestinations then Brain.questDestinations[q.key]=nil end
 end
 plan.progress=q.current
 if current and current~="" then
  plan.visited[current]=true
  if plan.target==current then plan.target=nil if Brain.questDestinations then Brain.questDestinations[q.key]=nil end end
 end
 if plan.target and not plan.visited[plan.target] then return plan.target end
 local names={} local seen={}
 local zones=workspace:FindFirstChild("MapZones")
 if zones then for i,zone in zones:GetChildren() do if i>50 then break end names[#names+1]=zone.Name seen[zone.Name]=true end end
 for name in Brain.zoneMemory do
  if not seen[name] then names[#names+1]=name seen[name]=true end
 end
 for _,recording in Brain.recordedQuestZones() do
  if not seen[recording.name] then names[#names+1]=recording.name seen[recording.name]=true end
 end
 local best,distance
 for _,name in names do
  if not plan.visited[name] and (plan.blocked[name] or 0)<=os.clock() then
   local parts=Brain.zoneParts(name)
   for _,part in parts do
    local delta=part.Position-root.Position local d=Vector3.new(delta.X,0,delta.Z).Magnitude
    if not distance or d<distance then best=name distance=d end
   end
   local recording=Brain.recordedQuestZone(name)
   if #parts==0 and recording then
    local delta=recording.points[#recording.points]-root.Position
    local d=Vector3.new(delta.X,0,delta.Z).Magnitude
    if not distance or d<distance then best=name distance=d end
   end
  end
 end
 plan.target=best
 return best
end
function Brain.objective()
	local rows=Brain.readQuests()
	local current=Brain.questZoneNow()
	if typeof(current)=="string" then Brain.visited[current]=true end
	local now=os.clock() local best,bestScore
	local land=false
	for _,q in rows do
		if not q.complete and q.kind=="Land" then land=true end
		local tracker=Brain.questTracker[q.key]
		if not tracker then tracker={value=q.current,at=now} Brain.questTracker[q.key]=tracker end
		if q.current~=tracker.value then
			if q.current<tracker.value and q.kind=="Explore" then Brain.visited={} if current then Brain.visited[current]=true end end
			tracker.value=q.current tracker.at=now
		end
		local score=Brain.questScore(q,current)
		if score~=nil then
			local expected=((q.kind=="Zone" or q.kind=="VisitZone") and current==q.zone) or q.kind=="Land"
			if tracker.expected~=expected then tracker.expected=expected tracker.at=now end
			if Brain.activeQuest==q.key and expected and now-tracker.at>100 then
				Brain.questPauseUntil[q.key]=now+60 Brain.activeQuest=nil
				Brain.questStatus="لا زيادة مؤكدة في "..q.title.."؛ أؤجلها وأجرب غيرها"
			else
				if Brain.activeQuest==q.key and (q.kind=="Land" or q.kind=="Explore" or q.kind=="Zone" or q.kind=="VisitZone" or q.kind=="Swim") then score=score-1000 end
				if not bestScore or score<bestScore then best=q bestScore=score end
			end
		end
	end
	if not best then Brain.activeQuest=nil return end
	if Brain.activeQuest~=best.key then
		Brain.activeQuest=best.key
		Brain.questTracker[best.key].at=now
	end
	local q=best
	if q.kind=="Zone" or q.kind=="VisitZone" then return {zone=q.zone,hold=current==q.zone,patrol=q.kind=="Zone" and current==q.zone and land,label=q.title,key=q.key,kind=q.kind} end
 if q.kind=="Explore" then
  local _,root=rig()
  local destination=root and Brain.exploreTarget(q,current,root)
  if destination then return {zone=destination,label=q.title,key=q.key,kind="Explore"} end
  Brain.questStatus="أنتظر منطقة أخرى محمّلة أو تحديث عدّاد الزيارات"
  Brain.questPauseUntil[q.key]=now+20 Brain.activeQuest=nil return
 end
	if q.kind=="Land" then return {patrol=true,label=q.title,key=q.key,kind="Land"} end
	return {passive=true,label=q.title,key=q.key,kind=q.kind}
end
Brain.questDestinations={}
Brain.landPatrolPlans=Brain.landPatrolPlans or {}
function Brain.landPatrolTarget(objective,root,model)
	local key=objective.key or "land_patrol"
	local plan=Brain.landPatrolPlans[key]
	local function allowed(position)
		if not position or not dry(terrainAt(position)) then return false end
		if objective.zone and not Brain.pointInZone(position,objective.zone) then return false end
		return true
	end
	if not plan then
		local originHit=terrainAt(root.Position)
		if not dry(originHit) then return nil end
		local center=originHit.Position
		for _,radius in {18,15,12,9} do
			local points={} local good=true
			for i=1,12 do
				local angle=(i-1)*math.pi*2/12
				local probe=center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
				local hit=terrainAt(probe)
				if not dry(hit) or (objective.zone and not Brain.pointInZone(hit.Position,objective.zone)) then good=false break end
				points[i]=hit.Position
			end
			if good then plan={center=center,points=points,index=1,radius=radius} break end
		end
		if not plan then return nil end
		Brain.landPatrolPlans[key]=plan
	end
	for offset=0,#plan.points-1 do
		local index=((plan.index+offset-1)%#plan.points)+1
		local point=plan.points[index]
		if allowed(point) then plan.index=index return point end
	end
	Brain.landPatrolPlans[key]=nil
	return nil
end
-- Recorded travel lap:
function Brain.installTravelLoop()
 Brain.travelLoopPoints={}
 for _,p in {{-6352.46,-1.57,4443.19},{-6355.21,-1.47,4438.61},{-6360.15,-1.28,4431.88},{-6367.67,-0.96,4421.84},{-6375.52,-0.62,4411.41},{-6383.75,-0.23,4401.92},{-6393.11,0.17,4392.59},{-6402.39,0.51,4384.32},{-6412.74,0.9,4376.14},{-6423.96,1.25,4369.18},{-6436.51,1.52,4365.39},{-6448.82,1.57,4364.34},{-6461.61,1.16,4366.53},{-6473.42,-0.34,4372.7},{-6479.09,-1.49,4382.62},{-6482.49,-3,4394.99},{-6483.75,-3.47,4407.14},{-6482.65,-3.47,4420.16},{-6478.56,-3.47,4431.95},{-6472.67,-3.1,4443.69},{-6464.79,-2.95,4453.88},{-6455.15,-2.57,4461.53},{-6444.11,-1.87,4469},{-6432.33,-1.16,4474.94},{-6420.7,-0.62,4478.42},{-6407.48,-0.51,4479.78},{-6393.99,-0.79,4479.6},{-6381.12,-1.09,4477.96},{-6368.76,-1.41,4473.64},{-6358.21,-1.62,4466.04},{-6352.52,-1.75,4457.94},{-6351.52,-1.62,4450.17},{-6351.59,-1.6,4445.44},{-6351.62,-1.59,4444.76}} do table.insert(Brain.travelLoopPoints,Vector3.new(p[1],p[2],p[3]))end
 Brain.travelLoopPlace=18214855317
end
Brain.installTravelLoop()
function Brain.travelLoopCounter(key)
 for _,q in Brain.readQuests() do
  if q.key==key then
   if q.kind~="Land" or type(q.current)~="number" or type(q.target)~="number" or q.target<=0 then return nil,"unavailable"end
   if q.complete or q.current>=q.target then return q,"complete"end
   if q.seenAt and os.clock()-q.seenAt>10 then return nil,"unavailable"end
   return q,"active"
  end
 end
 return nil,"unavailable"
end
function Brain.travelLoopGuard(key)
 local _,phase=Brain.travelLoopCounter(key)
 if phase=="complete" then return "quest_complete"end
 if phase~="active" then return "quest_unavailable"end
end
function Brain.travelLoopWidth()return math.max(8,CFG.AgentRadius*2+2)end
function Brain.travelLoopStep(objective,token,model,root)
 if game.PlaceId~=Brain.travelLoopPlace then state("دائرة سافر تخص الماب المسجل")return true end
 local q,phase=Brain.travelLoopCounter(objective.key)
 if phase~="active" then
  releaseW("travel_counter_"..phase)Brain.nextQuestScan=0
  if phase=="complete" then
   Brain.travelLoopState=nil if Brain.activeQuest==objective.key then Brain.activeQuest=nil end
   state("اكتملت سافر حسب عدّاد اللعبة؛ أتحقق من الاستلام والمهمة التالية")
  else Brain.nextTravel=os.clock()+1 state("أنتظر قراءة عدّاد سافر الحالي قبل مواصلة المشي")end
  return true
 end
 local points=Brain.travelLoopPoints local n=#points
 local function nextIndex(i)return i%n+1 end
 local nearest,distance
 for i,p in points do local d=Brain.homeDistance(root.Position,p)if not distance or d<distance then nearest=i distance=d end end
 local session=Brain.travelLoopState
 if not session or session.key~=q.key or session.model~=model or session.target~=q.target or q.current<session.counter then
  session={key=q.key,model=model,target=q.target,index=nearest,counter=q.current}Brain.travelLoopState=session
 end
 session.counter=q.current
 if Brain.homeDistance(root.Position,points[session.index])>32 and not session.joinIndex then session.index=nearest end
 local target=points[session.joinIndex or session.index]
 local route
 local outside=Brain.projectLane(points,root.Position,true)>Brain.travelLoopWidth()
 if session.joinIndex or outside then
  session.joinIndex=session.joinIndex or session.index
  target=points[session.joinIndex]
  if Brain.homeDistance(root.Position,target)>5 then
   route=Brain.worldTravelRoute(target,token,model,root)
   if route then route.loopJoin=true end
  else session.index=nextIndex(session.joinIndex)session.joinIndex=nil end
 end
 if not route and not session.joinIndex then
  if Brain.homeDistance(root.Position,points[session.index])<=4 then session.index=nextIndex(session.index)end
  local plan={{Position=root.Position}}local indices={}local previous=root.Position local index=session.index
  for _=1,n do
   if not valid(token,model) then return true end
   local floor=walkable(points[index],model,false)
   if not floor or not safeSegment(previous,floor,model,false) then
    if not floor and Brain.requestRegion then Brain.requestRegion(points[index])end
    break
   end
   table.insert(plan,{Position=floor})indices[#plan]=index previous=floor index=nextIndex(index)
  end
  if #plan>1 then route={position=previous,points=plan,lockedLoop=true,loopIndices=indices,nextLoopIndex=index}end
 end
 if not route then
  releaseW("recorded_loop_wait")Brain.nextTravel=os.clock()+1
  state("دائرة سافر محفوظة؛ أنتظر مقطعًا يابسًا قابلًا للمشي بدل تغيير المسار")return true
 end
 route.questKey=q.key
 Brain.travelZone=nil Brain.holdZone=nil
 state("سافر على دائرتك المسجلة • "..string.format("%.0f / %.0f",q.current,q.target))
 local result=walk(route,"Travel",token,model,root)
 if not valid(token,model) then return true end
 if result=="quest_complete" then
  Brain.travelLoopState=nil Brain.nextQuestScan=0
  if Brain.activeQuest==q.key then Brain.activeQuest=nil end
  state("اكتملت سافر حسب اللعبة؛ أنتقل للمهمة التالية")return true
 end
 if route.loopJoin then
  if Brain.homeDistance(root.Position,points[session.joinIndex])<=5 then session.index=nextIndex(session.joinIndex)session.joinIndex=nil end
 elseif result=="arrived" then session.index=route.nextLoopIndex
 elseif route.loopIndices then session.index=route.loopIndices[route.walkIndex or 2] or session.index end
 if result=="quest_unavailable" then Brain.nextQuestScan=0 Brain.nextTravel=os.clock()+1
 elseif result~="arrived" and result~="needs" and result~="quest_off" then Brain.nextTravel=os.clock()+1 end
 return true
end
function Brain.questStep(token,model,root)
	if not CFG.QuestsEnabled or os.clock()<(Brain.nextTravel or 0) then return false end
	local objective=Brain.objective()
	if not objective then return false end
	if objective.kind=="Land" and Brain.travelLoopPoints then return Brain.travelLoopStep(objective,token,model,root) end
	if objective.passive and objective.kind=="Swim" then
  return Brain.swimQuest and Brain.swimQuest(objective,token,model,root) or false
 end
 if objective.passive then
		state(objective.kind=="Group" and Brain.groupStatus or ("متابعة "..objective.label.." حسب عدّاد اللعبة")) return true
	end
	if objective.hold and not objective.patrol then
		state("بقاء داخل "..objective.zone.." • أتحقق من تقدم المهمة") return true
	end
	local recordedRoute,usingRecording=Brain.recordedQuestSegment(objective,token,model,root)
	if not valid(token,model) then return true end
	if usingRecording then
		if not recordedRoute then
			Brain.nextTravel=os.clock()+1
			state("أفحص المقطع التالي من الطريق المسجّل إلى "..objective.zone)
			return true
		end
		Brain.travelZone=objective.zone
		state("الطريق المسجّل إلى "..objective.zone)
		local result=walk(recordedRoute,"Travel",token,model,root)
		if token==generation then Brain.travelZone=nil end
		if not valid(token,model) then return true end
		local progress=Brain.recordedQuestProgress
		if result=="arrived" then
			progress.failures=0
			if recordedRoute.recordedEnd then progress.index=recordedRoute.recordedEnd+1 end
		elseif result=="zone" then
			Brain.recordedQuestProgress=nil
		elseif result~="needs" and result~="quest_off" then
			progress.failures+=1
			if progress.failures>=3 then progress.failures=0 progress.retryAt=os.clock()+20 end
		end
		return true
	end
	local destination=Brain.questDestinations[objective.key]
	if destination and (Vector3.new(destination.X,root.Position.Y,destination.Z)-root.Position).Magnitude<(objective.patrol and 3.5 or 6) then
		destination=nil Brain.questDestinations[objective.key]=nil
		if objective.patrol then
			local plan=Brain.landPatrolPlans and Brain.landPatrolPlans[objective.key]
			if plan then plan.index=(plan.index%#plan.points)+1 end
		end
	end
	if destination then
	elseif objective.patrol then
		destination=Brain.landPatrolTarget(objective,root,model)
		if not destination then
			Brain.nextTravel=os.clock()+1
			state("أبحث عن دائرة مشي آمنة على اليابسة")
			return true
		end
	elseif objective.zone then
		state("مهمة "..objective.label.." • أتجه إلى "..objective.zone)
		destination=Brain.zoneAnchor(objective.zone,root,model)
	else
		local facing=model:GetAttribute("FacingDirection")
		if typeof(facing)~="Vector3" then facing=root.CFrame.LookVector end
		local forward=Vector3.new(facing.X,0,facing.Z)
		if forward.Magnitude<.01 then forward=Vector3.new(1,0,0) end
		for _,degrees in {0,30,-30,60,-60,180} do
			local angle=math.rad(degrees)
			local direction=Vector3.new(forward.Unit.X*math.cos(angle)-forward.Unit.Z*math.sin(angle),0,forward.Unit.X*math.sin(angle)+forward.Unit.Z*math.cos(angle))
			local hit=terrainAt(root.Position+direction*480)
			if dry(hit) then destination=hit.Position break end
		end
	end
	if not valid(token,model) then return true end
	if destination then Brain.questDestinations[objective.key]=destination end
	if destination and Brain.requestRegion then Brain.requestRegion(destination) end
	local route=destination and Brain.travelRoute(destination,token,model,root)
	if route and objective.hold then
		for _,point in route.points do if not Brain.pointInZone(point.Position,objective.zone) then route=nil break end end
	end
	if not valid(token,model) then return true end
	if not route then
		Brain.questRouteFailures=Brain.questRouteFailures or {}
		local failures=(Brain.questRouteFailures[objective.key] or 0)+1
		Brain.questRouteFailures[objective.key]=failures
  local destinationKnown=destination and terrainAt(destination)
  if not destinationKnown then
   if destination and Brain.requestRegion then Brain.requestRegion(destination) end
   Brain.nextTravel=os.clock()+.5 state("الوجهة محفوظة؛ أنتظر تحميل الطريق إليها") return true
  end
		if failures>=3 then
   if objective.kind=="Explore" then
    local plan=Brain.explorePlans[objective.key]
    if plan and plan.target then plan.blocked[plan.target]=os.clock()+60 plan.target=nil end
    Brain.questDestinations[objective.key]=nil
   end
   Brain.questPauseUntil[objective.key]=os.clock()+20 Brain.activeQuest=nil Brain.questRouteFailures[objective.key]=0
  end
		Brain.nextTravel=os.clock()+2 state("أراجع مسار نفس المهمة وأواصل مراقبة الموارد") return true
	end
	Brain.questRouteFailures=Brain.questRouteFailures or {} Brain.questRouteFailures[objective.key]=0
	if objective.hold then Brain.travelZone=nil else Brain.travelZone=objective.zone end
	Brain.holdZone=objective.hold and objective.zone or nil
	state("تنفيذ "..objective.label.." • الاكتمال حسب عدّاد اللعبة")
	local result=walk(route,"Travel",token,model,root)
	if token==generation then Brain.travelZone=nil Brain.holdZone=nil end
	if not valid(token,model) then return true end
	if result~="arrived" and result~="needs" and result~="zone" and result~="quest_off" then
		avoided["Travel"..cell(route.position)]=os.clock()+10 Brain.nextTravel=os.clock()+.5
	end
	return true
end
-- One exact destination;
function Brain.travelRoute(destination,token,model,root,prefetch)
 if not prefetch then releaseW("travel_planning") end
 local floor=walkable(root.Position,model,true)
 if not floor or not valid(token,model) then return end
 local delta=destination-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
 if flat.Magnitude<2 then return {position=floor,goalPosition=destination,points={}} end
 if Brain.requestRegion then Brain.requestRegion(destination) end
 local targetFloor=terrainAt(destination)
 local candidates={}
 if dry(targetFloor) and flat.Magnitude<=2800 then candidates[1]={position=targetFloor.Position,final=true} end
 for _,distance in {256,128,64,32,16} do
  if distance<flat.Magnitude-3 then
   local intended=root.Position+flat.Unit*distance
   local hit=terrainAt(intended)
   if dry(hit) and (avoided["Travel"..cell(hit.Position)] or 0)<=os.clock() then
    table.insert(candidates,{position=hit.Position,final=false})
   end
  end
 end
 for index,candidate in candidates do
  if not valid(token,model) then return end
  if index>4 then break end
  local position=candidate.position
  local path=PF:CreatePath({AgentRadius=CFG.AgentRadius,AgentHeight=CFG.AgentHeight,AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=5,Costs={Water=math.huge}})
  if computePath(path,root.Position,position,token,model) and path.Status==Enum.PathStatus.Success then
   local points=path:GetWaypoints() local safe=#points>0 local previous=floor local checked=0 local prefix=prefetch and 8 or 48
   for _,point in points do
    if point.Action==Enum.PathWaypointAction.Jump then safe=false break end
    if checked<prefix then
     local segment=point.Position-previous local length=segment.Magnitude
     local endpoint=length>0 and previous+segment.Unit*math.min(length,prefix-checked) or point.Position
     if not safeSegment(previous,endpoint,model,true) then safe=false break end
     checked+=(endpoint-previous).Magnitude
    end
    previous=point.Position
   end
   if safe and (points[#points].Position-position).Magnitude<6 then
    return {position=position,points=points,path=path,goalPosition=destination,transit=not candidate.final,exactDestination=candidate.final}
   end
  end
  if (position-floor).Magnitude<=256 and safeSegment(floor,position,model,true) then
   return {position=position,points={{Position=floor},{Position=position}},goalPosition=destination,transit=not candidate.final,exactDestination=candidate.final}
  end
 end
 Brain.routeReason="أنتظر مسارًا لنفس الوجهة؛ لا أبدّلها بنقاط جانبية"
end
function Brain.prefetchTravel(route,token,model)
 if route.prefetchTicket or not route.transit or not route.goalPosition or os.clock()<(route.nextPrefetchAt or 0) then return end
 local ticket={} route.prefetchTicket=ticket
 local destination=route.goalPosition local future=route.position
 task.spawn(function()
  local worker=coroutine.running() queryScopes[worker]=token
  Brain.backgroundQueryScopes[worker]={route=route,ticket=ticket}
  pcall(function()
   for attempt=1,3 do
    if not valid(token,model) or route.prefetchTicket~=ticket then return end
    if Brain.requestRegion then Brain.requestRegion(future) end
    local nextRoute=Brain.travelRoute(destination,token,model,{Position=future},true)
    if route.prefetchTicket~=ticket or not valid(token,model) then return end
    if nextRoute and (nextRoute.position-future).Magnitude>4 then route.nextRouteReady=nextRoute return end
    task.wait(.5)
   end
  end)
  queryScopes[worker]=nil Brain.backgroundQueryScopes[worker]=nil
  if route.prefetchTicket==ticket and not route.nextRouteReady then route.prefetchTicket=nil route.nextPrefetchAt=os.clock()+.5 end
 end)
end
function Brain.foodExplore(token,model,root)
	Brain.foodVisits=Brain.foodVisits or {}
	local remembered,distance
	for _,n in Atlas.nodes do
		if n.kind=="Food" and n.state~="depleted" and (n.retry or 0)<=os.time() and os.time()-n.time<3600 then
			local d=(n.position-root.Position).Magnitude
			if d>120 and (not distance or d<distance) then remembered=n.position distance=d end
		end
	end
	if remembered then
		local route=Brain.travelRoute(remembered,token,model,root)
		if route then route.exploration=true route.intendedDestination=remembered return route end
	end
	local candidates={}
	for i=0,11 do
		if not valid(token,model) then return end
		local angle=i*math.pi/6
		local hit=terrainAt(root.Position+Vector3.new(math.cos(angle)*85,0,math.sin(angle)*85))
		if dry(hit) then
			local key=cell(hit.Position)
			if (Brain.foodVisits[key] or 0)<os.clock() then
				table.insert(candidates,{position=hit.Position,key=key,score=(hit.Material==Enum.Material.Grass and 0 or 100)+(hit.Position-root.Position).Magnitude})
			end
		end
	end
	table.sort(candidates,function(a,b) return a.score<b.score end)
	for i,c in candidates do
		if i>2 then break end
		Brain.foodVisits[c.key]=os.clock()+180
		local route=Brain.travelRoute(c.position,token,model,root)
		if route then route.exploration=true return route end
	end
end
function Brain.waterExplore(token,model,root)
	Brain.waterVisits=Brain.waterVisits or {}
	local nearest,distance
	for _,n in Atlas.nodes do
		if n.kind=="Water" and os.time()-n.time<3600 then
			local d=(n.position-root.Position).Magnitude
			if d>CFG.Radius and (not distance or d<distance) then nearest=n.position distance=d end
		end
	end
	if nearest then
		local route=Brain.travelRoute(nearest,token,model,root)
		if route then route.exploration=true route.intendedDestination=nearest return route end
	end
	local candidates={}
	local level=waterPart() and waterPart().Position.Y
	for i=0,11 do
		if not valid(token,model) then return end
		local angle=i*math.pi/6
		local hit=terrainAt(root.Position+Vector3.new(math.cos(angle)*70,0,math.sin(angle)*70))
		if dry(hit) then
			local key=cell(hit.Position)
			if (Brain.waterVisits[key] or 0)<os.clock() then
				local score=level and math.abs(hit.Position.Y-level) or (hit.Position-root.Position).Magnitude
				table.insert(candidates,{position=hit.Position,key=key,score=score})
			end
		end
	end
	table.sort(candidates,function(a,b) return a.score<b.score end)
	for i,c in candidates do
		if i>2 then break end
		Brain.waterVisits[c.key]=os.clock()+180
		local route=Brain.travelRoute(c.position,token,model,root)
		if route then route.exploration=true return route end
	end
end
Brain.resourceGoals={}
Brain.spentFood={}
function Brain.foodPatchBlocked(p,margin)
 local now=os.clock()
 for i=#Brain.spentFood,1,-1 do
  local item=Brain.spentFood[i]
  if now>=item.untilTime then table.remove(Brain.spentFood,i)
  else local d=p-item.position if Vector3.new(d.X,0,d.Z).Magnitude<item.radius+(margin or 0)then return true end end
 end
 return false
end
function Brain.rejectFoodPatch(p,reason)
 if Brain.home and Brain.home.fixedResources then
  table.insert(Brain.spentFood,{position=p,radius=3.5,untilTime=os.clock()+(reason=="plateau"and 8 or 3)})
  if #Brain.spentFood>24 then table.remove(Brain.spentFood,1)end
  Brain.clearResourceGoal("Food",reason)return
 end
 table.insert(Brain.spentFood,{position=p,radius=12,untilTime=os.clock()+60})
 if #Brain.spentFood>24 then table.remove(Brain.spentFood,1)end
 local goal=Brain.resourceGoals.Food
 if goal then avoided["Food"..cell(goal.position)]=os.clock()+60 end
 Brain.clearResourceGoal("Food",reason) Brain.motionTrace("food_patch_spent",reason)
end
function Brain.clearResourceGoal(kind,reason)
	Brain.motionTrace("goal_clear",kind.." / "..tostring(reason))
	Brain.resourceGoals[kind]=nil Brain.goalReason=reason
end
function Brain.resourceFailure(kind,reason)
	Brain.motionTrace("route_failure",kind.." / "..tostring(reason))
	local goal=Brain.resourceGoals[kind]
	if not goal then return end
	goal.failures+=1 Brain.goalReason=reason
 if kind=="Food" and (reason=="لم يبدأ التفاعل عند المورد" or reason=="لم يظهر خيار المورد عند الوجهة")then
  local key=kind..cell(goal.position)
  local cooldown=(Brain.worldCare()or (Brain.home and Brain.home.strictLane and Brain.mode=="Survival"))and 3 or 45
  avoided[key]=os.clock()+cooldown
  if Brain.home and Brain.home.avoid then Brain.home.avoid[key]=os.clock()+cooldown end
  Brain.clearResourceGoal(kind,"لم يستجب المورد عند الوصول إليه")return
 end
	if reason=="لم يبدأ التفاعل عند المورد" or reason=="لم يظهر خيار المورد عند الوجهة" then
		goal.sourceFailures=(goal.sourceFailures or 0)+1
		if goal.sourceFailures>=3 then
			avoided[kind..cell(goal.position)]=os.clock()+20
			Brain.clearResourceGoal(kind,"لم يستجب المورد عند الوصول إليه") return
		end
	end
 -- PC-WATER-R42: a visually close but unreachable bank must not trap the worker.
 if kind=="Water" and goal.failures>=6 then
  avoided[kind..cell(goal.position)]=os.clock()+25
  Brain.clearResourceGoal(kind,"تكررت عراقيل الوصول إلى الضفة؛ أبحث عن ضفة أخرى")
  return
 end
	if goal.failures>=3 then goal.blockedUntil=os.clock()+2 end
end
function Brain.resourceRoute(kind,token,model,root)
	releaseW("resource_planning")
	if prompt(kind,true) then return {here=true} end
	local goal=Brain.resourceGoals[kind]
	if goal then
  local travel=(root.Position-goal.position).Magnitude
  if travel<(goal.bestDistance or math.huge)-3 then
   goal.bestDistance=travel goal.progressAt=os.clock()
  end
  local staleFor=os.clock()-(goal.progressAt or goal.selectedAt or os.clock())
  if staleFor>22 and not prompt(kind,true) then
   avoided[kind..cell(goal.position)]=os.clock()+45
   Brain.clearResourceGoal(kind,"لم أتقدم نحو الهدف منذ 22 ثانية؛ أبحث عن بديل")
   goal=nil
  end
 end
	if goal then
		if not goal.exploration then
			local floor=cast(goal.position,model)
			local wet=kind=="Water" and goal.water and terrainAt(goal.water)
			goal.landKnown=floor and dry(floor) or false
			if not floor or (kind=="Water" and (not goal.water or not wet)) then
				goal.needsData=true
    if Brain.requestRegion then Brain.requestRegion(goal.position) end
    Brain.goalReason="أنتظر تحميل موضع المورد المحفوظ"
    if kind=="Water" then
     goal.missingSince=goal.missingSince or os.clock()
     if os.clock()-goal.missingSince>15 then
      avoided[kind..cell(goal.position)]=os.clock()+25
      Brain.clearResourceGoal(kind,"لم يتم تحميل ضفة الماء؛ أبحث عن ضفة أخرى")
      goal=nil
     end
    end
			elseif not dry(floor) or (kind=="Water" and not isWater(wet)) then
				Brain.clearResourceGoal(kind,"تغير المورد أو غمرت المياه الضفة") goal=nil
			else
				goal.needsData=false goal.position=floor.Position goal.missingSince=nil
				if wet then goal.water=wet.Position end
			end
		end
	end
	if goal then
		if not valid(token,model) then return end
		local delta=goal.position-root.Position
		local distance=Vector3.new(delta.X,0,delta.Z).Magnitude
		if distance<(goal.bestDistance or math.huge)-5 then
			goal.bestDistance=distance goal.failures=0 goal.blockedUntil=0
		end
		if (goal.blockedUntil or 0)>os.clock() then return end
  if kind=="Water" and not goal.needsData then
   if not goal.shoreSide and distance<16 and
     ((goal.shoreFailures or 0)>=2 or (goal.failures or 0)>=2) then
    local detour=Brain.shoreSideRoute(goal,token,model,root)
    if detour then return detour end
   end
   local resumed=Brain.resumeShoreApproach(goal,model,root) if resumed then return resumed end
  end
		if goal.needsData and distance<8 and not goal.landKnown then return end
		local route
		if distance<2 then route={position=goal.position,points={}}
		else route=Brain.travelRoute(goal.position,token,model,root) end
		if not valid(token,model) then return end
		if not route then
   if goal.needsData then Brain.goalReason="أنتظر تحميل الطريق؛ الوجهة محفوظة" if Brain.requestRegion then Brain.requestRegion(goal.position) end return end
   Brain.resourceFailure(kind,"تعذر إعادة تخطيط الطريق لنفس الهدف")
   if kind=="Water" and goal and not goal.shoreSide then
    local sideRoute=Brain.shoreSideRoute(goal,token,model,root)
    if sideRoute then return sideRoute end
   end
   if Brain.policy.pathRetry(goal,os.clock(),root.Position) then
    avoided[kind..cell(goal.position)]=os.clock()+25
    Brain.clearResourceGoal(kind,"تأكد تعذر الطريق؛ أختار موردًا آخر")
   end
   return
  end
  goal.pathMissAt=nil goal.pathMissPosition=nil goal.pathMisses=0
		route.water=goal.water route.exploration=goal.exploration
		route.transit=goal.needsData or (route.position-goal.position).Magnitude>3
		route.goalPosition=goal.position
		return route
	end
	local route=routes(kind,token,model,root)
	if not route and valid(token,model) then
		if kind=="Water"then
   if not Brain.worldCare()then route=Brain.waterExplore(token,model,root)else Brain.routeReason="أبحث عن أقرب ضفة مؤكدة؛ لا أتحرك لاتجاه عشوائي"end
		else route=Brain.foodExplore(token,model,root) end
	end
	if not valid(token,model) then return end
	if route and route.position then
		local position=route.intendedDestination or route.position
		Brain.resourceGoals[kind]={position=position,water=route.water,exploration=route.exploration==true,failures=0,selectedAt=os.clock(),bestDistance=(root.Position-position).Magnitude}
		route.goalPosition=position route.transit=(route.position-position).Magnitude>3
		Brain.goalReason="وجهة مثبتة"
		Brain.motionTrace("goal_selected",kind.." / "..tostring(position))
	end
	return route
end
-- BLY ANYWHERE TEST: fallback exploration for grass-eating animals, not fixed beach coordinates.
local normalWorldResourceRoute=Brain.resourceRoute
Brain.anywhereVisited={Food={},Water={}}
Brain.anywhereNextAt={Food=0,Water=0}
Brain.anywhereSweep={Food=0,Water=0}
Brain.anywhereSummary="جاهز للبحث من مكان الشخصية الحالي"
-- SMART NAV TEST: confirmed grass / water bank gets priority; otherwise explore dry ground.
function Brain.anywhereExplore(kind,token,model,root)
 if kind~="Food" and kind~="Water" then return end
 local now=os.clock()
 if now<(Brain.anywhereNextAt[kind] or 0) then return end
 local seen=Brain.anywhereVisited[kind]
 local candidates={}
 local collected={}
 local origin=root.Position
 local spokes=UIS.TouchEnabled and 10 or 16
 local radii=UIS.TouchEnabled and {18,36,64,100,150} or {18,36,64,100,150,210}
 local sweep=Brain.anywhereSweep[kind] or 0
 Brain.anywhereSweep[kind]=(sweep+1)%2
 local startLand=cast(origin,model)
 local landOnRay={}
 local verified=0
 local function candidateAt(position,water,confirmed,score)
  local key=cell(position)
  if collected[key] or (seen[key] or 0)>now or (avoided[kind..key] or 0)>now then return end
  if kind=="Food" and Brain.foodPatchBlocked and Brain.foodPatchBlocked(position,2) then return end
  collected[key]=true
  table.insert(candidates,{position=position,water=water,key=key,confirmed=confirmed,score=score})
  if confirmed then verified+=1 end
 end
 -- Only land that has passed the dry/steepness check can become a navigation target.
 for _,radius in radii do
  for i=0,spokes-1 do
   if not valid(token,model) then return end
   if prompt(kind,true) then return {here=true} end
   local angle=(i*math.pi*2/spokes)+(sweep*math.pi/spokes)
   local direction=Vector3.new(math.cos(angle),0,math.sin(angle))
   local hit=terrainAt(origin+direction*radius)
   if kind=="Water" and isWater(hit) then
    -- A water hit is NOT a walking target. Locate the shoreline between land and water.
    local prior=landOnRay[i] or (dry(startLand) and startLand.Position or nil)
    if prior and verified<8 then
     local land=prior
     local wet=hit.Position
     for n=1,7 do
      local midpoint=land:Lerp(wet,.5)
      local probe=terrainAt(midpoint)
      if not probe then break end
      if isWater(probe) then wet=probe.Position
      elseif dry(probe) then land=probe.Position
      else break end
     end
     local inland=land-wet
     local flat=Vector3.new(inland.X,0,inland.Z)
     if flat.Magnitude>.1 then
      for _,backoff in {1.5,3,5,8} do
       local bank=cast(land+flat.Unit*backoff,model)
       if dry(bank) and (bank.Position-wet).Magnitude<14 and safeSegment(bank.Position,bank.Position,model,true) then
        candidateAt(bank.Position,wet,true,-90+radius*.15)
        break
       end
      end
     end
    end
   elseif dry(hit) and math.abs(hit.Position.Y-origin.Y)<18 then
    landOnRay[i]=hit.Position
    local grass=hit.Material==Enum.Material.Grass
    local confirmed=kind=="Food" and grass
    candidateAt(hit.Position,nil,confirmed and true or false,(confirmed and -60 or 75)+radius*.4)
   end
  end
  -- A modest scan budget prevents one failed search from freezing the whole worker.
  if verified>=5 then break end
  task.wait()
 end
 table.sort(candidates,function(a,b)return a.score<b.score end)
 Brain.anywhereNextAt[kind]=os.clock()+2
 local checked=0
 for _,candidate in candidates do
  if checked>=(UIS.TouchEnabled and 4 or 6) or not valid(token,model) then break end
  checked+=1
  local route=Brain.worldTravelRoute(candidate.position,token,model,root)
  if route then
   local confirmed=candidate.confirmed==true
   seen[candidate.key]=os.clock()+(confirmed and 45 or 100)
   route.water=candidate.water
   route.exploration=not confirmed
   route.intendedDestination=candidate.position
   route.goalPosition=candidate.position
   route.transit=(route.position-candidate.position).Magnitude>3
   Brain.resourceGoals[kind]={position=candidate.position,water=candidate.water,
    exploration=not confirmed,failures=0,selectedAt=os.clock(),progressAt=os.clock(),
    bestDistance=(root.Position-candidate.position).Magnitude}
   Brain.routeReason=confirmed and (kind=="Food" and "تأكدت من أرض Grass؛ أتحقق من زر الأكل" or "رصدت مويه وضفة يابسة؛ أتحقق من زر الشرب")
    or "أستكشف أرضا يابسة جديدة بحثا عن المورد"
   Brain.anywhereSummary=Brain.routeReason
   Brain.motionTrace("smart_nav_candidate",kind.." / "..(confirmed and "confirmed / " or "explore / ")..candidate.key)
   return route
  end
  seen[candidate.key]=os.clock()+25
 end
 Brain.anywhereNextAt[kind]=os.clock()+5
 Brain.routeReason="لم أجد طريقا يابسا آمنا بعد؛ أعيد البحث ولا أدخل المويه عشوائيا"
 Brain.anywhereSummary=Brain.routeReason
end
Brain.worldResourceRoute=function(kind,token,model,root)
 local route=normalWorldResourceRoute(kind,token,model,root)
 if route or not valid(token,model) then return route end
 -- Keep quest-specific routes untouched. Preserve a resource goal until its own retry logic releases it.
 if (Brain.mode~="Survival" and Brain.mode~="Growth") or Brain.resourceGoals[kind] then return end
 return Brain.anywhereExplore(kind,token,model,root)
end
Brain.home={strictLane=true,fixedResources=true,recordedStations=true,food=Vector3.new(-6332.30615234375,-1.9332330226898193,4435.01953125),water=Vector3.new(-6583.68310546875,-20.156749725341797,4545.6865234375),foodRadius=55,waterRadius=90,corridor=20,route={Vector3.new(-6332.30615234375,-1.9332330226898193,4435.01953125),Vector3.new(-6334.9032,-1.8775,4436.1426),Vector3.new(-6337.5002,-1.8218,4437.2656),Vector3.new(-6340.0972,-1.766,4438.3887),Vector3.new(-6342.4412,-1.7087,4439.3855),Vector3.new(-6344.7852,-1.6515,4440.3823),Vector3.new(-6347.1292,-1.5942,4441.3792),Vector3.new(-6349.4731,-1.5369,4442.376),Vector3.new(-6351.8741,-1.4753,4443.4034),Vector3.new(-6354.2751,-1.4138,4444.4309),Vector3.new(-6356.6761,-1.3523,4445.4583),Vector3.new(-6359.0771,-1.2908,4446.4857),Vector3.new(-6361.478,-1.2292,4447.5132),Vector3.new(-6363.796,-1.1673,4448.5247),Vector3.new(-6366.114,-1.1054,4449.5362),Vector3.new(-6368.4319,-1.0434,4450.5478),Vector3.new(-6370.7499,-0.9815,4451.5593),Vector3.new(-6373.0679,-0.9196,4452.5708),Vector3.new(-6375.54,-0.8619,4453.65),Vector3.new(-6378.0122,-0.8043,4454.7292),Vector3.new(-6380.4844,-0.7466,4455.8084),Vector3.new(-6382.9565,-0.689,4456.8876),Vector3.new(-6385.4287,-0.6313,4457.9668),Vector3.new(-6387.8956,-0.5744,4459.0588),Vector3.new(-6390.3625,-0.5174,4460.1508),Vector3.new(-6392.8294,-0.4605,4461.2428),Vector3.new(-6395.2963,-0.4035,4462.3348),Vector3.new(-6397.7632,-0.3466,4463.4268),Vector3.new(-6400.2277,-0.3166,4464.5208),Vector3.new(-6402.6923,-0.2867,4465.6148),Vector3.new(-6405.1568,-0.2568,4466.7089),Vector3.new(-6407.6214,-0.2269,4467.8029),Vector3.new(-6410.0859,-0.1969,4468.897),Vector3.new(-6412.4065,-0.2329,4469.9261),Vector3.new(-6414.7271,-0.2689,4470.9552),Vector3.new(-6417.0478,-0.3048,4471.9843),Vector3.new(-6419.3684,-0.3408,4473.0134),Vector3.new(-6421.689,-0.3768,4474.0425),Vector3.new(-6424.0167,-0.5322,4475.0752),Vector3.new(-6426.3444,-0.6877,4476.1079),Vector3.new(-6428.6722,-0.8431,4477.1406),Vector3.new(-6430.9999,-0.9986,4478.1733),Vector3.new(-6433.3276,-1.154,4479.2061),Vector3.new(-6435.7992,-1.392,4480.3041),Vector3.new(-6438.2708,-1.63,4481.4021),Vector3.new(-6440.7424,-1.8679,4482.5002),Vector3.new(-6443.214,-2.1059,4483.5982),Vector3.new(-6445.6855,-2.3439,4484.6963),Vector3.new(-6447.9859,-2.5524,4485.721),Vector3.new(-6450.2863,-2.761,4486.7457),Vector3.new(-6452.5867,-2.9696,4487.7704),Vector3.new(-6454.8871,-3.1781,4488.7951),Vector3.new(-6457.1875,-3.3867,4489.8198),Vector3.new(-6459.6165,-3.3972,4490.8999),Vector3.new(-6462.0455,-3.4077,4491.98),Vector3.new(-6464.4745,-3.4182,4493.0601),Vector3.new(-6466.9035,-3.4287,4494.1401),Vector3.new(-6469.3325,-3.4392,4495.2202),Vector3.new(-6471.8117,-3.9463,4496.3553),Vector3.new(-6474.2909,-4.4535,4497.4903),Vector3.new(-6476.7701,-4.9606,4498.6254),Vector3.new(-6479.2493,-5.4677,4499.7604),Vector3.new(-6481.7285,-5.9749,4500.8955),Vector3.new(-6484.0322,-6.3696,4502.0614),Vector3.new(-6486.3359,-6.7644,4503.2273),Vector3.new(-6488.6396,-7.1591,4504.3933),Vector3.new(-6490.9434,-7.5539,4505.5592),Vector3.new(-6493.2471,-7.9486,4506.7251),Vector3.new(-6495.6405,-7.8346,4507.8131),Vector3.new(-6498.034,-7.7206,4508.9011),Vector3.new(-6500.4274,-7.6065,4509.9891),Vector3.new(-6502.8209,-7.4925,4511.0771),Vector3.new(-6505.2144,-7.3785,4512.165),Vector3.new(-6507.7332,-7.4021,4513.2918),Vector3.new(-6510.2521,-7.4258,4514.4186),Vector3.new(-6512.7709,-7.4494,4515.5453),Vector3.new(-6515.2897,-7.4731,4516.6721),Vector3.new(-6517.8086,-7.4967,4517.7988),Vector3.new(-6520.1667,-7.8774,4518.9888),Vector3.new(-6522.5248,-8.2581,4520.1787),Vector3.new(-6524.8829,-8.6388,4521.3687),Vector3.new(-6527.241,-9.0194,4522.5586),Vector3.new(-6529.5991,-9.4001,4523.7485),Vector3.new(-6532.3353,-9.0409,4524.9585),Vector3.new(-6535.0715,-8.6816,4526.1685),Vector3.new(-6537.8077,-8.3224,4527.3784),Vector3.new(-6540.5439,-7.9631,4528.5884),Vector3.new(-6542.9513,-8.559,4529.5875),Vector3.new(-6545.3586,-9.1549,4530.5866),Vector3.new(-6547.7659,-9.7508,4531.5857),Vector3.new(-6550.1732,-10.3467,4532.5849),Vector3.new(-6552.5806,-10.9426,4533.584),Vector3.new(-6554.9678,-11.8635,4534.5133),Vector3.new(-6557.355,-12.7844,4535.4426),Vector3.new(-6559.7422,-13.7053,4536.3719),Vector3.new(-6562.1294,-14.6262,4537.3012),Vector3.new(-6564.5166,-15.5471,4538.2305),Vector3.new(-6567.1471,-16.4902,4539.2485),Vector3.new(-6569.7776,-17.4334,4540.2666),Vector3.new(-6572.4081,-18.3765,4541.2847),Vector3.new(-6575.0386,-19.3197,4542.3027),Vector3.new(-6577.1647,-19.5309,4543.1356),Vector3.new(-6579.2909,-19.742,4543.9684),Vector3.new(-6581.417,-19.9532,4544.8013),Vector3.new(-6583.68310546875,-20.156749725341797,4545.6865234375)},avoid={}}
function Brain.homeDistance(a,b)
 local delta=a-b return Vector3.new(delta.X,0,delta.Z).Magnitude
end
function Brain.projectLane(points,position,recorded)
 local best,nearest,index=math.huge,nil,nil
 for i=1,#points-1 do
  local a=recorded and points[i] or points[i].Position
  local b=recorded and points[i+1] or points[i+1].Position
  local edge=Vector3.new(b.X-a.X,0,b.Z-a.Z)
  local offset=Vector3.new(position.X-a.X,0,position.Z-a.Z)
  local length=edge:Dot(edge)
  local t=length>.001 and math.clamp(offset:Dot(edge)/length,0,1) or 0
  local p=a:Lerp(b,t) local distance=Brain.homeDistance(position,p)
  if distance<best then best=distance nearest=p index=i end
 end
 return best,nearest,index
end
function Brain.homeLaneWidth()
 if Brain.home.strictLane and Brain.mode=="Survival"then return math.max(4,(CFG.AgentRadius or 1.5)*2+1)end
 return math.max(8,(CFG.AgentRadius or 1.5)*2+2)
end
function Brain.homeLeashDue(position)
 if not CFG.HomeOnly or Brain.mode~="Survival" then return false end
 if Brain.home.strictLane then
  if Brain.homeInside(position)and Brain.stopActionVisible and Brain.stopActionVisible()then return false end
  return Brain.projectLane(Brain.home.route,position,true)>Brain.homeLaneWidth()*.7
 end
 if Brain.home.fixedResources and (Brain.homeDistance(position,Brain.home.food)<=Brain.home.foodRadius or Brain.homeDistance(position,Brain.home.water)<=Brain.home.waterRadius)then return false end
 if Brain.stopActionVisible and Brain.stopActionVisible() then return false end
 local distance=Brain.projectLane(Brain.home.route,position,true)
 if distance<=Brain.homeLaneWidth() then return false end
 if Brain.homeStation and Brain.homeDistance(position,Brain.homeStation)<=Brain.homeLaneWidth() then return false end
 for _,goal in Brain.resourceGoals do if Brain.homeDistance(position,goal.position)<=12 then return false end end
 if prompt("Food",true) or prompt("Water",true) then return false end
 return true
end
function Brain.homeReturnReached(position)
 if Brain.home.strictLane and Brain.mode=="Survival"then return Brain.projectLane(Brain.home.route,position,true)<=math.max(.75,CFG.Footprint or .8)end
 if Brain.homeInside(position)and not Brain.homeLeashDue(position)then return true end
 if Brain.homeReturnGoal then return Brain.homeDistance(position,Brain.homeReturnGoal)<=math.max(4,CFG.AgentRadius or 1.5) end
 return Brain.homeInside(position) and not Brain.homeLeashDue(position)
end
function Brain.homeInside(position)
 local home=Brain.home
 if home.strictLane and Brain.mode=="Survival"then return Brain.projectLane(home.route,position,true)<=Brain.homeLaneWidth()end
 if Brain.homeDistance(position,home.food)<=home.foodRadius or Brain.homeDistance(position,home.water)<=home.waterRadius then return true end
 for _,point in home.route do if Brain.homeDistance(position,point)<=home.corridor then return true end end
 return false
end
function Brain.homeSegment(a,b)
 for i=0,math.max(1,math.ceil((b-a).Magnitude/3)) do
  local count=math.max(1,math.ceil((b-a).Magnitude/3))
  if not Brain.homeInside(a:Lerp(b,i/count)) then return false end
 end
 return true
end
function Brain.homePath(destination,token,model,root)
 releaseW("home_planning")
 Brain.homePlan={stage="support",from={root.Position.X,root.Position.Y,root.Position.Z},to={destination.X,destination.Y,destination.Z}}
 if not Brain.homeInside(root.Position) or not Brain.homeInside(destination) then Brain.routeReason="ابدأ داخل شاطئك المسجل؛ لا أبحث خارجه" return end
 local start=walkable(root.Position,model,true)
 local finish=walkable(destination,model,true)
 if not start then Brain.homePlan.stage="missing_start_support"return end
 if finish and Brain.homeDistance(start,finish)<=12 and Brain.homeSegment(start,finish) and safeSegment(start,finish,model,true) then
  return {position=finish,points={{Position=start},{Position=finish}}}
 end
 local nearestStart,nearestEnd,startDistance,endDistance
 for index,p in Brain.home.route do
  local a,b=Brain.homeDistance(root.Position,p),Brain.homeDistance(destination,p)
  if not startDistance or a<startDistance then nearestStart=index startDistance=a end
  if not endDistance or b<endDistance then nearestEnd=index endDistance=b end
 end
 local joins={}
 for index,p in Brain.home.route do table.insert(joins,{index=index,distance=Brain.homeDistance(start,p)})end
 table.sort(joins,function(a,b)return a.distance<b.distance end)
 for attempt,join in joins do
  if attempt>12 or not valid(token,model)then break end
  local p=walkable(Brain.home.route[join.index],model,true)
  if p and Brain.homeSegment(start,p)and safeSegment(start,p,model,true)then nearestStart=join.index break end
 end
 Brain.homePlan.stage="recorded_lane"Brain.homePlan.join=nearestStart
 local points={{Position=start}} local previous=start local good=true
 local step=nearestStart<=nearestEnd and 1 or -1
 local guide={{Position=start}}
 for index=nearestStart,nearestEnd,step do table.insert(guide,{Position=Brain.home.route[index]}) end
 table.insert(guide,{Position=finish})
 for index=nearestStart,nearestEnd,step do
  if not valid(token,model) then return end
  local point=walkable(Brain.home.route[index],model,true)
  if not point or not Brain.homeSegment(previous,point) or not safeSegment(previous,point,model,true) then good=false break end
  if (point-previous).Magnitude>2 then table.insert(points,{Position=point}) previous=point end
  if Brain.home.recordedStations and Brain.homeDistance(start,previous)>=64 and index~=nearestEnd then good=false break end
 end
 if good and finish and Brain.homeSegment(previous,finish) and safeSegment(previous,finish,model,true) then
  table.insert(points,{Position=finish}) return {position=finish,points=points,lockedHome=true}
 end
 if Brain.home.recordedStations and #points>=3 and Brain.homeDistance(start,previous)>=6 then
  Brain.homePlan.stage="checked_prefix"
  return {position=previous,points=points,lockedHome=true,transit=true,goalPosition=destination}
 end
 if not finish then Brain.homePlan.stage="missing_goal_support"return end
 local path=PF:CreatePath({AgentRadius=CFG.AgentRadius,AgentHeight=CFG.AgentHeight,AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=5,Costs={Water=math.huge}})
 Brain.homePlan.stage="pathfinding"
 if computePath(path,start,finish,token,model) and path.Status==Enum.PathStatus.Success then
  local route=path:GetWaypoints() previous=start
  for _,point in route do
   if not valid(token,model) then return end
   local drift=Brain.projectLane(guide,point.Position,false)
   local localArea=Brain.home.fixedResources and (Brain.homeDistance(point.Position,Brain.home.food)<=Brain.home.foodRadius or Brain.homeDistance(point.Position,Brain.home.water)<=Brain.home.waterRadius)
   if (not localArea and drift>Brain.homeLaneWidth()) or point.Action==Enum.PathWaypointAction.Jump or not Brain.homeSegment(previous,point.Position) or not safeSegment(previous,point.Position,model,true) then Brain.homePlan.stage="path_rejected"return end
   previous=point.Position
  end
  Brain.homePlan.stage="path_ready"return {position=finish,points=route,path=path,lockedHome=true}
 end
 Brain.homePlan.stage="no_path"Brain.homePlan.status=tostring(path.Status)
end
Brain.worldTravelRoute=Brain.travelRoute
Brain.travelRoute=function(destination,token,model,root)
 if not CFG.HomeOnly or Brain.mode=="Quests" then return Brain.worldTravelRoute(destination,token,model,root) end
 return Brain.homePath(destination,token,model,root)
end
function Brain.homeCandidates(kind,token,model,root)
 local home=Brain.home local candidates={} local seen={}
 local laneFood=kind=="Food"and home.strictLane and Brain.mode=="Survival"
 if kind=="Water"and home.recordedStations and Brain.homeDistance(root.Position,home.water)>40 then
  if prompt(kind,true)then return {here=true}end
  local p=walkable(home.water,model,true)
  p=p or home.water
  return {{position=p,distance=Brain.homeDistance(root.Position,p),recordedStation=true}}
 end
 local function add(p,water)
  if not Brain.homeInside(p) or (home.avoid[kind..cell(p)] or 0)>os.clock() or (avoided[kind..cell(p)] or 0)>os.clock() then return end
  if kind=="Food"and (Brain.foodPatchBlocked(p,2)or (not laneFood and Brain.homeDistance(p,home.food)>home.foodRadius))then return end
  if kind=="Water" and Brain.homeDistance(p,home.water)>home.waterRadius then return end
  if kind=="Food" and lastConsumed and os.clock()<(Brain.lastFoodUntil or 0) and Brain.homeDistance(p,lastConsumed)<8 then return end
  local n=Atlas.nodes[Atlas.key(kind,p)]
  if n and n.state=="depleted" and os.time()-n.time<120 then return end
  local key=cell(p) if seen[key] then return end seen[key]=true
  table.insert(candidates,{position=p,water=water,recordedStation=kind=="Food"and home.recordedStations,distance=Brain.homeDistance(p,root.Position)})
 end
 if laneFood then
  local function sample(p)
   if not valid(token,model)then return end
   if not Brain.homeInside(p)then return end
   local hit=terrainAt(p)
   if dry(hit)and tostring(hit.Material):lower():find("grass",1,true)then add(hit.Position,nil)end
  end
  for _,radius in {0,4,8,12,18}do
   for i=0,(radius==0 and 0 or 7)do
    if not valid(token,model)then return end
    if prompt(kind,true)then return {here=true}end
    local angle=i*math.pi/4
    sample(root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
   end
  end
  for _,point in home.route do
   if not valid(token,model)then return end
   if prompt(kind,true)then return {here=true}end
   if Brain.homeDistance(point,root.Position)<=60 then sample(point)end
  end
 elseif kind=="Food" then
  for _,radius in {0,8,16,24,36,48,55} do
   for i=0,(radius==0 and 0 or 15) do
    if not valid(token,model) then return end
    if prompt(kind,true) then return {here=true} end
    local angle=i*math.pi/8
    local hit=terrainAt(home.food+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
    if dry(hit) and tostring(hit.Material):lower():find("grass",1,true) then add(hit.Position,nil) end
   end
  end
 else
  local function bank(a,b)
   local land,water=a.Position,b.Position
   for _=1,6 do
    if not valid(token,model) then return end
    local hit=terrainAt(land:Lerp(water,.5))
    if dry(hit) then land=hit.Position elseif isWater(hit) then water=hit.Position else return end
   end
   local delta=land-water local flat=Vector3.new(delta.X,0,delta.Z)
   if flat.Magnitude<.01 then return end
   local hit=terrainAt(land+flat.Unit*(CFG.Footprint+1))
   if dry(hit) and safeSegment(hit.Position,hit.Position,model,false) then add(hit.Position,water) end
  end
  local function pair(a,b)
   if dry(a) and isWater(b) then bank(a,b) elseif isWater(a) and dry(b) then bank(b,a) end
  end
  local previous
  for _,point in home.route do
   if not valid(token,model) then return end
   if prompt(kind,true) then return {here=true} end
   local hit=terrainAt(point)
   if isWater(hit) then waterSamples+=1 end
   if previous and hit then pair(previous,hit) end
   previous=hit
  end
  for i=0,15 do
   local angle=i*math.pi/8 local direction=Vector3.new(math.cos(angle),0,math.sin(angle))
   previous=nil
   for _,radius in {0,8,16,28,44,64,88} do
    if not valid(token,model) then return end
    local hit=terrainAt(home.water+direction*radius)
    if isWater(hit) then waterSamples+=1 end
    if previous and hit then pair(previous,hit) end
    previous=hit
   end
  end
  waterScanDone=true
 end
 if kind=="Food"and home.recordedStations and #candidates==0
  and Brain.homeDistance(root.Position,home.food)>home.foodRadius then
  table.insert(candidates,{position=home.food,distance=Brain.homeDistance(root.Position,home.food),recordedStation=true})
 end
 table.sort(candidates,function(a,b) return a.distance<b.distance end)
 return candidates
end
function Brain.resourceRoute(kind,token,model,root)
 releaseW("home_resource_planning")
 if game.PlaceId~=18214855317 then error("تسجيل الشاطئ يخص مابًا آخر") end
 if not Brain.homeInside(root.Position) then Brain.routeReason="قف داخل شاطئك المسجل ثم شغّل البوت" return end
 if prompt(kind,true) then return {here=true} end
 local goal=Brain.resourceGoals[kind]
 if goal and kind=="Water"and goal.recordedStation and Brain.home.recordedStations and Brain.homeDistance(root.Position,Brain.home.water)<=40 then
  Brain.clearResourceGoal(kind,"تغير الماء أو رقعة الأكل داخل الشاطئ")goal=nil
 end
 if goal then
  if goal.recordedStation then
   local route=Brain.homePath(goal.position,token,model,root)
   if route then route.goalPosition=goal.position route.transit=route.transit==true return route end
   return
  end
  local land=terrainAt(goal.position)
  local water=goal.water and terrainAt(goal.water)
  local stationFloor=goal.recordedStation and walkable(goal.position,model,true)
  if not land or (kind=="Water" and not goal.recordedStation and not goal.exploration and not water) then Brain.goalReason="أنتظر بيانات شاطئك؛ الوجهة محفوظة" return end
  if (not dry(land)and not stationFloor) or (kind=="Water" and not goal.recordedStation and not goal.exploration and not isWater(water)) or (kind=="Food" and not goal.exploration and not tostring(land.Material):lower():find("grass",1,true)) then
   Brain.clearResourceGoal(kind,"تغير الماء أو رقعة الأكل داخل الشاطئ") goal=nil
  else
   goal.position=stationFloor or land.Position if water then goal.water=water.Position end
   if (goal.blockedUntil or 0)>os.clock() then return end
   if kind=="Water" then local resumed=Brain.resumeShoreApproach(goal,model,root) if resumed then return resumed end end
   local route=Brain.homePath(goal.position,token,model,root)
   if route then
    goal.pathMissAt=nil goal.pathMissPosition=nil goal.pathMisses=0
    route.water=goal.water route.goalPosition=goal.position route.transit=route.transit==true route.exploration=goal.exploration return route
   end
   if Brain.policy.pathRetry(goal,os.clock(),root.Position) then
    Brain.home.avoid[kind..cell(goal.position)]=os.clock()+30
    Brain.clearResourceGoal(kind,"الطريق انسد؛ أبحث عن مورد ثاني داخل الشاطئ")
    return Brain.homeResourceRoute(kind,token,model,root)
   end
   Brain.goalReason="أراجع الطريق لنفس الوجهة داخل شاطئك" return
  end
 end
 local candidates=Brain.homeCandidates(kind,token,model,root)
 if not candidates then return end
 if candidates.here then return candidates end
 Brain.resourceScan={kind=kind,count=#candidates,fixed=true}Brain.motionTrace("resource_candidates",kind.." / "..#candidates)
 for i,candidate in candidates do
  if i>6 then break end
  if not valid(token,model) then return end
  if prompt(kind,true) then return {here=true} end
  if kind=="Water"and candidate.water and Brain.home.recordedStations then
   local _,join=Brain.projectLane(Brain.home.route,candidate.position,true)
   local back=join and terrainAt(join)
   if not dry(back)or not Brain.exitSegment(candidate.position,back.Position,model,0)then
    Brain.home.avoid[kind..cell(candidate.position)]=os.clock()+20 continue
   end
   candidate.returnPosition=back.Position
  end
  local route=Brain.homePath(candidate.position,token,model,root)
  if route then
   Brain.resourceGoals[kind]={position=candidate.position,water=candidate.water,returnPosition=candidate.returnPosition,recordedStation=candidate.recordedStation,liveResource=true,failures=0,selectedAt=os.clock()}
   route.water=candidate.water route.goalPosition=candidate.position route.transit=route.transit==true route.exploration=candidate.exploration
   Brain.resourceGoals[kind].exploration=candidate.exploration
   Brain.goalReason="وجهة ثابتة داخل شاطئك الأساسي" Brain.motionTrace("home_goal",kind.." / "..tostring(route.position))
   return route
  end
  Brain.home.avoid[kind..cell(candidate.position)]=os.clock()+45
 end
 Brain.routeReason="ما تأكد لي مورد آمن داخل شاطئك للحين"
end
Brain.homeResourceRoute=Brain.resourceRoute
Brain.resourceRoute=function(kind,token,model,root)
 if not CFG.HomeOnly or Brain.mode=="Quests" then return Brain.worldResourceRoute(kind,token,model,root) end
 return Brain.homeResourceRoute(kind,token,model,root)
end
function Brain.planResource(kind,token,model,root)
 local planning={worker=coroutine.running(),token=token,started=os.clock(),beat=os.clock(),kind=kind}
 Brain.resourcePlanning=planning Brain.motionTrace("resource_plan_begin",kind)
 local ok,route=pcall(Brain.resourceRoute,kind,token,model,root)
 if Brain.resourcePlanning==planning then Brain.resourcePlanning=nil end
 if not ok then error(route)end
 return route
end
function Brain.resourcePlanLive(now,token)
 local plan=Brain.resourcePlanning
 return plan and plan.token==token and now-plan.started<25 and now-plan.beat<6
end
function Brain.refillAttemptLive(now,token,model)
 local attempt=Brain.refillAttempt
 return attempt and attempt.token==token and attempt.model==model and now-attempt.started<(attempt.kind=="Food" and 18 or 11) and now-attempt.beat<3
end
local function settle(token,model,root)
 releaseW("settle_for_interaction")
 local deadline=os.clock()+5 local stableSince local stablePosition
 while valid(token,model) and os.clock()<deadline do
  local velocity=root.AssemblyLinearVelocity local speed=Vector2.new(velocity.X,velocity.Z).Magnitude
  local movement=string.lower(tostring(model:GetAttribute("MovementState") or ""))
  local idle=movement=="idle" or movement=="idling" or movement=="standing"
  local p=Vector3.new(root.Position.X,0,root.Position.Z)
  if not stablePosition then stablePosition=p stableSince=os.clock() end
  local drift=(p-stablePosition).Magnitude
  if drift>.25 or (speed>=1.5 and not idle) then stablePosition=p stableSince=os.clock()
  elseif os.clock()-stableSince>=.35 then return true end
  task.wait(.1)
 end
 return false
end
function Brain.rememberShoreApproach(route,model,root,outcome)
 local goal=Brain.resourceGoals.Water
 if not goal or not route.goalPosition or Brain.homeDistance(goal.position,route.goalPosition)>3 then return end
 goal.approachPosition=root.Position goal.approachModel=model goal.approachOutcome=outcome
 goal.approachAt=os.clock()
 Brain.motionTrace("shore_approach",outcome)
 if outcome=="drink_available" then
  goal.shoreFailures=0 goal.shorePlan=nil
 else
  -- PC-WATER-R42: do not retry the exact same unsafe direction indefinitely.
  goal.shoreFailures=(goal.shoreFailures or 0)+1
  goal.shorePlan=nil
  if goal.shoreFailures>=3 then
   avoided["Water"..cell(goal.position)]=os.clock()+25
   Brain.clearResourceGoal("Water","الحافة لا تعطي تفاعل شرب؛ أغير الضفة")
  end
 end
end
-- R45: alternative shoreline search. Walk around the water on confirmed dry land
-- instead of repeatedly pushing forward into the same unsafe bank.
function Brain.shoreSideRoute(goal,token,model,root)
 if not goal or not goal.water or not valid(token,model) then return end
 local water=goal.water
 local origin=root.Position
 local delta=Vector3.new(origin.X-water.X,0,origin.Z-water.Z)
 if delta.Magnitude<.1 then return end
 local outward=delta.Unit
 local tangent=Vector3.new(-outward.Z,0,outward.X)
 local choices={}
 for _,side in {1,-1} do
  for _,shift in {8,16,26} do
   local probe=water+outward*7+tangent*(shift*side)
   local bank=cast(probe,model)
   if dry(bank) and isWater(terrainAt(bank.Position-outward*5)) then
    local key=cell(bank.Position)
    if (avoided["Water"..key] or 0)<os.clock() then
     table.insert(choices,{position=bank.Position,key=key,distance=(bank.Position-origin).Magnitude})
    end
   end
  end
 end
 table.sort(choices,function(a,b)return a.distance<b.distance end)
 for i,c in choices do
  if i>4 or not valid(token,model) then break end
  local route=Brain.travelRoute(c.position,token,model,root)
  if route then
   avoided["Water"..cell(goal.position)]=os.clock()+90
   Brain.resourceGoals.Water={position=c.position,water=water,exploration=false,failures=0,
    selectedAt=os.clock(),progressAt=os.clock(),bestDistance=c.distance,shoreSide=true}
   route.water=water route.goalPosition=c.position
   Brain.goalReason="أغير الضفة جانبيا بدل الوقوف أمام المويه"
   Brain.motionTrace("shore_side_route",c.key)
   return route
  end
  avoided["Water"..c.key]=os.clock()+35
 end
end
function Brain.resumeShoreApproach(goal,model,root)
 if not goal.water or not goal.approachPosition or goal.approachModel~=model then return end
 if (goal.approachAt and os.clock()-goal.approachAt>12) or (goal.shoreFailures or 0)>=3 then
  goal.approachPosition=nil goal.approachModel=nil goal.shorePlan=nil
  return
 end
 if Brain.homeDistance(root.Position,goal.approachPosition)>3 then
  goal.approachPosition=nil goal.approachModel=nil goal.shorePlan=nil return
 end
 return {position=root.Position,goalPosition=goal.position,water=goal.water,points={},transit=false,shoreArrival=true}
end
local function approachShore(route,token,model,root)
 if not route.water then return false end
 local goal=Brain.resourceGoals.Water
 if goal and (not route.goalPosition or Brain.homeDistance(goal.position,route.goalPosition)>3) then goal=nil end
 local plan=goal and goal.shorePlan
 if plan and (plan.model~=model or not goal.approachPosition or Brain.homeDistance(root.Position,goal.approachPosition)>3) then plan=nil end
 local origin=plan and plan.origin or root.Position
 local direction=plan and plan.direction
 local limit=plan and plan.limit
 if not direction then
  local delta=route.water-origin local flat=Vector3.new(delta.X,0,delta.Z)
  if flat.Magnitude<.01 then
   local bank=route.goalPosition or route.position
   if bank then local away=origin-bank flat=Vector3.new(away.X,0,away.Z) end
  end
  if flat.Magnitude<.01 then
   local available=prompt("Water",true)~=nil
   if not available and goal then Brain.rememberShoreApproach(route,model,root,"no_approach_direction") end
   return available
  end
  direction=flat.Unit
  limit=math.clamp(flat.Magnitude+math.max(2,CFG.AgentRadius or 2),4,12)
  if goal then goal.shorePlan={model=model,origin=origin,direction=direction,limit=limit} end
 end
 local deadline=os.clock()+8 local outcome="range_exhausted" local lastSafeAt local safeFrom
 releaseW("shore_approach_start") Brain.shoreNudge=true
 local ok,result=pcall(function()
  while valid(token,model) and os.clock()<deadline do
   if prompt("Water",true) then outcome="drink_available" return true end
   local travel=root.Position-origin local distance=Vector3.new(travel.X,0,travel.Z).Magnitude
   if distance>=limit then break end
   aim=direction
   if CFG.HomeOnly and Brain.mode~="Quests" and not Brain.homeInside(root.Position+aim) then outcome="home_boundary" break end
   local _,_,humanoid=rig()
   if Brain.waterThreat and Brain.waterThreat(model,root,humanoid) then outcome="water_danger" break end
   local safe=immediateSafety(root.Position,direction,model)
   if safe==false then outcome="unsafe_next_step" break end
   if safe==nil then
    local drift=safeFrom and (root.Position-safeFrom).Magnitude or math.huge
    if not lastSafeAt or os.clock()-lastSafeAt>.2 or drift>.3 then releaseW("shore_safety_wait") end
    Run.Heartbeat:Wait() continue
   end
   lastSafeAt=os.clock() safeFrom=root.Position
   movementFrame()
   if not valid(token,model) then return false end
   if prompt("Water",true) then outcome="drink_available" return true end
   if not heldW then heldW=true send(Enum.KeyCode.W,true) end
   Run.Heartbeat:Wait()
  end
  local available=prompt("Water",true)~=nil
  if available then outcome="drink_available" end
  return available
 end)
 releaseW("shore_approach_"..outcome)
 if token==generation then Brain.shoreNudge=false Brain.rememberShoreApproach(route,model,root,outcome) end
 if not ok then error(result) end
 return result
end
function Brain.exitFloor(position,model)
 local top=cast(position,model)
 if dry(top) then return top.Position,0 end
 if not isWater(top) then return end
 local bed=supportBelow(position,model)
 if not dry(bed) then return end
 local depth=top.Position.Y-bed.Position.Y
 if depth<0 then return end
 return bed.Position,depth
end
function Brain.exitSegment(a,b,model,maxDepth)
 local offsets={Vector3.zero,Vector3.new(CFG.Footprint,0,0),Vector3.new(-CFG.Footprint,0,0),Vector3.new(0,0,CFG.Footprint),Vector3.new(0,0,-CFG.Footprint)}
 local heights={}local ceiling=maxDepth or 0
 for index,offset in offsets do
  local floor,depth=Brain.exitFloor(a+offset,model)
  if not floor then return false end
  heights[index]=floor.Y ceiling=math.max(ceiling,depth)
 end
 local count=math.max(1,math.ceil((b-a).Magnitude/1.5))
 for i=0,count do
  local position=a:Lerp(b,i/count)
  for index,offset in offsets do
   local floor,depth=Brain.exitFloor(position+offset,model)
   if not floor or depth>ceiling+.15 or math.abs(floor.Y-heights[index])>1.8 then return false end
   heights[index]=floor.Y
  end
 end
 return true
end
function Brain.exitStep(position,direction,model)
 local side=Vector3.new(-direction.Z,0,direction.X)*CFG.Footprint
 for _,offset in {Vector3.zero,side,-side}do
  local startFloor,startDepth=Brain.exitFloor(position+offset,model)
  local ahead,nextDepth=Brain.exitFloor(position+direction*.6+offset,model)
  if not startFloor or not ahead or nextDepth>startDepth+.15 or math.abs(ahead.Y-startFloor.Y)>.9 then return false end
 end
 return true
end
local function retreatToShore(token,model,root)
 releaseW("exit_planning")
 local floor,depth=Brain.exitFloor(root.Position,model)
 if not floor then return false end
 local bank
 local function accept(position)
  local hit=cast(position,model)
  return dry(hit) and (not CFG.HomeOnly or Brain.mode=="Quests" or Brain.homeInside(hit.Position)) and safeSegment(hit.Position,hit.Position,model,false)
   and Brain.exitSegment(floor,hit.Position,model,depth) and hit.Position
 end
 if Brain.drinkExitBank and (Brain.drinkExitBank-root.Position).Magnitude<128 then bank=accept(Brain.drinkExitBank)end
 if not bank and not Brain.worldCare()and Brain.home.recordedStations then
  for index=#Brain.home.route-1,1,-1 do
   local p=Brain.home.route[index]
   if Brain.homeDistance(p,root.Position)<=64 then bank=accept(p)if bank then break end end
  end
 end
 if not bank and knownShore and (knownShore-root.Position).Magnitude<60 then bank=accept(knownShore) end
 if not bank then
  for radius=2,64,2 do
   for i=0,15 do
    if not valid(token,model) then return false end
    local angle=i*math.pi/8
    bank=accept(root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
    if bank then break end
   end
   if bank then break end
  end
 end
 if not bank then Brain.motionTrace("exit_failed","no_supported_non_deeper_bank") return false end
 knownShore=bank
 Brain.motionTrace("exit_begin",tostring(bank))
 local deadline=os.clock()+35
 local lastPosition=root.Position local progressAt=os.clock()
 Brain.shoreNudge=true -- Suppress resource-prompt W guard only during this checked exit.
 Brain.setShift(false)
 while valid(token,model) and os.clock()<deadline do
  local here
  if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
  if workCount+20>CFG.QueriesPerFrame then Run.Heartbeat:Wait() continue end
  safetyBatch=true
  local landOK,onLand=pcall(function() here=cast(root.Position,model) return dry(here) end)
  safetyBatch=false
  if not landOK then error(onLand) end
  if onLand then
   releaseW("exit_on_land") Brain.shoreNudge=false Brain.motionTrace("exit_complete","") return true
  end
  local delta=bank-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
  if flat.Magnitude<.5 then break end
  aim=flat.Unit
  if CFG.HomeOnly and Brain.mode~="Quests" and not Brain.homeInside(root.Position+aim*1.2) then break end
  if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
  safetyBatch=true
  local checkOK,stepOK=pcall(Brain.exitStep,root.Position,aim,model)
  safetyBatch=false
  if not checkOK then error(stepOK) end
  if not stepOK then break end
  if not valid(token,model) then break end
  movementFrame()
  if not valid(token,model) then break end
  if not heldW then heldW=true send(Enum.KeyCode.W,true) end
  if (root.Position-lastPosition).Magnitude>.35 then lastPosition=root.Position progressAt=os.clock() end
  if os.clock()-progressAt>2 then break end
  task.wait(.08)
 end
 releaseW("exit_blocked") if token==generation then Brain.shoreNudge=false end
 return false
end
-- Emergency recovery runs before hunger/thirst decisions
Brain.rescueAvoid={}
function Brain.waterThreat(model,root,humanoid)
 local movement=string.lower(tostring(model:GetAttribute("MovementState") or ""))
 local swimming=movement:find("swim",1,true)~=nil or movement:find("drown",1,true)~=nil
 if humanoid and humanoid:GetState()==Enum.HumanoidStateType.Swimming then swimming=true end
 local oxygen=model:GetAttribute("Oxygen")
 local oxygenMax=model:GetAttribute("MaxOxygen")or model:GetAttribute("OxygenMax")
 if typeof(oxygen)=="number"and typeof(oxygenMax)=="number"and oxygenMax>0 then oxygen=oxygen/oxygenMax*100 end
 if swimming or (typeof(oxygen)=="number"and oxygen<97)then return true end
 if prompt("Water",true)then return false end
 if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
 if workCount+6>CFG.QueriesPerFrame then return swimming and true or nil end
 safetyBatch=true
 local ok,danger=pcall(function()
  local surface=terrainAt(root.Position)
  local footing=cast(root.Position,model)
  if dry(footing) and (not isWater(surface) or footing.Position.Y>=surface.Position.Y+.1) then return false end
  if not isWater(surface) then return swimming end
  local bed=supportBelow(root.Position,model)
  return bed and surface.Position.Y-bed.Position.Y>CFG.MaxWadeDepth+.35 or false
 end)
 safetyBatch=false
 if not ok then error(danger) end
 return danger
end
function Brain.rescueLine(a,b,model)
 if CFG.HomeOnly and Brain.mode=="Survival" and Brain.homeInside(a) and not Brain.homeSegment(a,b)then return false end
 local count=math.max(1,math.ceil((b-a).Magnitude/5))
 local previous,wasDry
 for i=0,count do
  local hit=terrainAt(a:Lerp(b,i/count))
  if not hit or (not isWater(hit) and not dry(hit)) then return false end
  if hit.Instance and hit.Instance:GetAttribute("BLY_Hazard") then return false end
  if previous and dry(hit) then
   local rise=hit.Position.Y-previous.Position.Y
   if rise>(wasDry and 4 or 3) then return false end
  end
  previous=hit wasDry=dry(hit)
 end
 return previous and dry(previous)
end
function Brain.chooseDryBank(token,model,root)
 local candidates={} local seen={}
 local function add(position)
  local hit=terrainAt(position)
  if not dry(hit) or not safeSegment(hit.Position,hit.Position,model,false) then return end
  if CFG.HomeOnly and Brain.mode=="Survival" and not Brain.homeInside(hit.Position)then return end
  local key=cell(hit.Position)
  if seen[key] or (Brain.rescueAvoid[key] or 0)>os.clock() then return end
  seen[key]=true
  table.insert(candidates,{position=hit.Position,distance=(Vector3.new(hit.Position.X,root.Position.Y,hit.Position.Z)-root.Position).Magnitude})
 end
 if knownShore and (knownShore-root.Position).Magnitude<256 then add(knownShore) end
 local wet=terrainAt(root.Position)
 for _,radius in {4,8,16,24,40,64,96,144,192,256} do
  for i=0,15 do
   if not valid(token,model) then return end
   local angle=i*math.pi/8
   local position=root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
   local land=terrainAt(position)
   if dry(land) then
    if isWater(wet) then
     local a,b=land.Position,wet.Position
     for _=1,6 do
      local middle=terrainAt(a:Lerp(b,.5))
      if dry(middle) then a=middle.Position elseif isWater(middle) then b=middle.Position else break end
     end
     local delta=a-b local flat=Vector3.new(delta.X,0,delta.Z)
     if flat.Magnitude>.01 then add(a+flat.Unit*math.max(3,CFG.Footprint+1)) end
    else add(land.Position) end
   end
  end
  if #candidates>=3 then break end
 end
 table.sort(candidates,function(a,b) return a.distance<b.distance end)
 for index,candidate in candidates do
  if index>8 or not valid(token,model) then break end
  if Brain.rescueLine(root.Position,candidate.position,model) then return candidate.position end
 end
end
function Brain.rescueStep(root,bank,model)
 if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
 if workCount+8>CFG.QueriesPerFrame then return nil end
 safetyBatch=true
 local ok,safe,land=pcall(function()
  local target=terrainAt(bank)
  if not dry(target) then return false,false end
  local here=cast(root.Position,model)
  local surfaceHere=terrainAt(root.Position)
  local landed=dry(here) and (not isWater(surfaceHere) or here.Position.Y>=surfaceHere.Position.Y+.1)
  local delta=bank-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
  if flat.Magnitude<.01 then return true,landed end
  local nextHit=terrainAt(root.Position+flat.Unit*2)
  if CFG.HomeOnly and Brain.mode=="Survival" and Brain.homeInside(root.Position)and not Brain.homeInside(root.Position+flat.Unit*2)then return false,false end
  if not nextHit or (not dry(nextHit) and not isWater(nextHit)) then return false,false end
  if nextHit.Instance and nextHit.Instance:GetAttribute("BLY_Hazard") then return false,false end
  queryBudget()
  local params=parameters(model)
  local wall=workspace:Raycast(root.Position+Vector3.new(0,2,0),flat.Unit*3,params)
  if wall and not isWater(wall) and wall.Normal.Y<.5 then return false,false end
  return true,landed
 end)
 safetyBatch=false
 if not ok then error(safe) end
 return safe,land
end
function Brain.rescueToLand(token,model,root)
 releaseW("water_rescue")
 if Brain.stopActionVisible and Brain.stopActionVisible() then
  if not Brain.finishAction(token,model) then return false end
 end
 state("الماء ارتفع؛ أبحث عن طلعة لليابسة")
 local bank=Brain.chooseDryBank(token,model,root)
 if not valid(token,model) then return false end
 if not bank then Brain.motionTrace("rescue_no_bank","") state("ما تأكدت لي طلعة آمنة لليابس؛ أعيد الفحص") return false end
 Brain.rescuing=true Brain.shoreNudge=true
 Brain.motionTrace("rescue_target",tostring(bank))
 local lastPosition=root.Position local progressAt=os.clock()
 local deadline=os.clock()+math.clamp((root.Position-bank).Magnitude/2+15,20,140)
 local escaped=false local jumped=false
 local ok,err=pcall(function()
  while valid(token,model) and os.clock()<deadline do
   local safe,onLand=Brain.rescueStep(root,bank,model)
   if safe==false then break end
   if safe==nil then Run.Heartbeat:Wait() continue end
   if onLand then
    releaseW("rescue_land_check")
    local hit=cast(root.Position,model)
    if dry(hit) and safeSegment(hit.Position,hit.Position,model,false) then escaped=true break end
   end
   local delta=bank-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
   if flat.Magnitude<.3 then break end
   aim=flat.Unit movementFrame()
   if not valid(token,model) then break end
   if not heldW then heldW=true send(Enum.KeyCode.W,true) end
   Brain.speedTick(root,model,false,true)
   if (root.Position-lastPosition).Magnitude>.35 then lastPosition=root.Position progressAt=os.clock() end
   if os.clock()-progressAt>1 and flat.Magnitude<8 and not jumped then Brain.pulse(Enum.KeyCode.Space) jumped=true end
   if os.clock()-progressAt>3 then break end
   state("أطلع لليابسة أول؛ بعدها أكمل")
   Run.Heartbeat:Wait()
  end
 end)
 releaseW("rescue_end")
 if token==generation then Brain.rescuing=false Brain.shoreNudge=false end
 if not ok then error(err) end
 if escaped then knownShore=bank Brain.motionTrace("rescue_complete",tostring(root.Position))
 else Brain.rescueAvoid[cell(bank)]=os.clock()+20 Brain.motionTrace("rescue_replan",tostring(bank)) end
 return escaped
end
function Brain.requestRegion(point)
 if os.clock()<(Brain.nextRegionRequest or 0) or Brain.regionRequestBusy then return end
 Brain.nextRegionRequest=os.clock()+5 Brain.regionRequestBusy=true
 task.spawn(function()
  pcall(function()player:RequestStreamAroundAsync(point,1)end)
  Brain.regionRequestBusy=false
 end)
end
function Brain.homewardRoute(destination,token,model,root)
 releaseW("homeward_plan")
 local from=walkable(root.Position,model,true)
 if not from then return end
 local delta=destination-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
 if flat.Magnitude<.35 then return end
 for _,step in {math.min(1000,flat.Magnitude),math.min(180,flat.Magnitude),math.min(90,flat.Magnitude)} do
  if not valid(token,model) then return end
  local intended=root.Position+flat.Unit*step
  local hit=terrainAt(intended)
  if not hit then Brain.requestRegion(intended) continue end
  if not dry(hit) then continue end
  local path=PF:CreatePath({AgentRadius=CFG.AgentRadius,AgentHeight=CFG.AgentHeight,AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=6,Costs={Water=math.huge}})
  if computePath(path,from,hit.Position,token,model) and path.Status==Enum.PathStatus.Success then
   local points=path:GetWaypoints() local previous=from local safe=true
   for _,point in points do
    if not valid(token,model) then return end
    if point.Action==Enum.PathWaypointAction.Jump or not safeSegment(previous,point.Position,model,true) then safe=false break end
    previous=point.Position
   end
   if safe and #points>0 and (points[#points].Position-hit.Position).Magnitude<5 then
    return {position=hit.Position,points=points,goalPosition=destination,path=path}
   end
  end
 end
 return nil
end
function Brain.returnHomeAfterRescue(token,model,root)
 if not CFG.HomeOnly or Brain.mode~="Survival"or(Brain.homeInside(root.Position)and not Brain.homeLeashDue(root.Position))then Brain.homeReturnGoal=nil return true end
 if Brain.stopActionVisible and Brain.stopActionVisible()and not Brain.finishAction(token,model)then return false end
 Brain.homeReturnAvoid=Brain.homeReturnAvoid or {}
 Brain.homeReturnOutcome="outside_or_off_lane"
 local options={}local seen={}
 local function add(p)
  if not p then return end local key=cell(p)
  if seen[key]or(Brain.homeReturnAvoid[key]or 0)>os.clock()then return end
  seen[key]=true table.insert(options,{position=p,key=key,distance=Brain.homeDistance(root.Position,p)})
 end
 local lane=Brain.home.beachBoundary or Brain.home.route
 local _,join=Brain.projectLane(lane,root.Position,true)
 add(Brain.homeReturnGoal)add(join)add(Brain.home.food)add(Brain.home.water)
 for index,p in lane do if index==1 or index%5==0 or index==#lane then add(p)end end
 table.sort(options,function(a,b)return a.distance<b.distance end)
 local attempts=0
 for _,candidate in options do
  if not valid(token,model)then return false end
  local hit=terrainAt(candidate.position)
  if dry(hit)and Brain.homeInside(hit.Position)then
   attempts+=1 Brain.homeReturnGoal=hit.Position
   local route=Brain.homewardRoute(hit.Position,token,model,root)
   if route then
    state("الرجوع للشاطئ الأساسي؛ الوجهة ثابتة والطريق مفحوص")
    Brain.motionTrace("home_return_attempt",tostring(hit.Position))Brain.escapeReturn=true
    local ok,result=pcall(walk,route,"ReturnHome",token,model,root)
    if token==generation then Brain.escapeReturn=false end
    if not ok then error(result)end
    if Brain.homeReturnReached(root.Position)then Brain.homeReturnGoal=nil Brain.homeReturnOutcome="returned"return true end
   end
   Brain.homeReturnAvoid[candidate.key]=os.clock()+20 Brain.homeReturnGoal=nil
   Brain.motionTrace("home_return_retry",candidate.key)
   if attempts>=3 then break end
  end
 end
 if join then Brain.requestRegion(join)end
 Brain.homeReturnOutcome="no_checked_return_path"
 state("الوجهة شاطئك؛ أنتظر تحميل طريق صالح وأعيد المحاولة")return false
end
local function tapE(token,model)
	if not valid(token,model) then return end
	if UIS:GetFocusedTextBox() then UIS:GetFocusedTextBox():ReleaseFocus() end
	inputTrace={began=false,ended=false,processed=nil,untilTime=os.clock()+2}
	local press=send(Enum.KeyCode.E,true)
	if not press then return end
	heldE=true
	task.wait(.18)
	if not valid(token,model) then return end
	send(Enum.KeyCode.E,false,false,press) heldE=false
end
function Brain.stopActionVisible()
 local source=observedSource()
 if not source or not visible(source) then return false end
 local text=string.lower(source.Text):gsub("<[^>]->","")
 return string.find(text,"stop drinking",1,true)~=nil
  or string.find(text,"stop eating",1,true)~=nil
  or string.find(text,"stop grazing",1,true)~=nil
  or string.find(text,"إيقاف الشرب",1,true)~=nil
  or string.find(text,"إيقاف الأكل",1,true)~=nil
end
function Brain.finishAction(token,model)
 if not Brain.stopActionVisible() then Brain.actionOwned=false return true end
 releaseW("finish_consumption") Brain.setShift(false)
 Brain.motionTrace("consume_stop_requested",rawSource())
 tapE(token,model)
 local deadline=os.clock()+2
 while valid(token,model) and os.clock()<deadline do
  if not Brain.stopActionVisible() then
   sensorAt=-math.huge Brain.actionOwned=false Brain.motionTrace("consume_stopped","") return true
  end
  task.wait(.1)
 end
 Brain.motionTrace("consume_stop_unconfirmed",rawSource())
 return false
end
function Brain.leaveRest(model)
 if not Brain.restOwned then return end
 if Brain.policy.isResting(model:GetAttribute("MovementState"),model:GetAttribute("IsResting")) then Brain.pulse(Enum.KeyCode.R) end
 Brain.restOwned=false
end
function Brain.restUntilReady(token,model,root)
 releaseW("energy_rest")
 Brain.motionTrace("rest_begin","")
 local start=os.clock()
 local stamina=Brain.staminaPercent(model)
 local land=cast(root.Position,model)
 if dry(land) and not Brain.policy.isResting(model:GetAttribute("MovementState"),model:GetAttribute("IsResting")) then
  Brain.pulse(Enum.KeyCode.R)
  task.wait(.4)
  if not valid(token,model) then return "cancelled" end
  Brain.restOwned=true
 end
 while valid(token,model) do
  local _,_,h=rig()
  if Brain.waterThreat and Brain.waterThreat(model,root,h) then Brain.leaveRest(model) return "water_danger" end
  local food,water=stats()
  if not food or not water then Brain.leaveRest(model) error("انقطعت النسب أثناء الراحة") end
  stamina=Brain.staminaPercent(model)
  if food<CFG.Threshold or water<CFG.Threshold then Brain.leaveRest(model) return "needs" end
  if typeof(stamina)~="number" or stamina>=65 then
   Brain.leaveRest(model)
   local standDeadline=os.clock()+2
   while valid(token,model) and Brain.policy.isResting(model:GetAttribute("MovementState"),model:GetAttribute("IsResting")) and os.clock()<standDeadline do task.wait(.1) end
   if Brain.policy.isResting(model:GetAttribute("MovementState"),model:GetAttribute("IsResting")) then return "stalled" end
   Brain.energyRest=false Brain.motionTrace("rest_complete",tostring(stamina)) return "ready"
  end
  if os.clock()-start>90 then Brain.leaveRest(model) Brain.motionTrace("rest_stalled",tostring(stamina)) return "stalled" end
  state("راحة الطاقة • "..string.format("%.0f%%",stamina).." • الوجهة محفوظة")
  task.wait(.3)
 end
 return "cancelled"
end
function Brain.consumeCore(kind,token,model,root,resume)
	local f,w=stats()
	local before=kind=="Food" and f or w
	if before==nil then error("انقطعت قراءة المورد قبل التفاعل") end
	local started=os.clock()
	local peak=before
	local lastIncrease=started
	local firstIncrease=false
	local presses=resume and 0 or 1
	local lastPress=started
	local outcome="timeout"
	local after=before
	releaseW()
	if not resume then tapE(token,model) end
	Brain.actionOwned=true
	while valid(token,model) and os.clock()-started<90 do
  local attempt=Brain.refillAttempt
  if attempt and attempt.token==token and attempt.model==model then attempt.beat=os.clock()end
  if CFG.HomeOnly and Brain.home and Brain.home.strictLane and Brain.mode=="Survival"and not Brain.homeInside(root.Position)then outcome="off_lane"break end
        local _,_,h=rig()
        if Brain.waterThreat and Brain.waterThreat(model,root,h) then outcome="water_danger" break end
		releaseW()
		f,w=Brain.awaitStats(token,model)
		if f==nil or w==nil then error("انقطعت نسب البقاء أثناء التعبئة") end
		after=kind=="Food" and f or w
		local now=os.clock()
		if after>peak+.02 then
			peak=after lastIncrease=now firstIncrease=true
		end
		if after>=CFG.Target then outcome="target" break end
		local movementState=model:GetAttribute("MovementState")
		local finishedFood=kind=="Food" and firstIncrease and not prompt("Food",true) and (movementState=="Idling" or movementState=="Idle")
		local actionState=string.lower(tostring(movementState or ""))
		local activeState=kind=="Food" and (actionState:find("eat",1,true) or actionState:find("graz",1,true))
   or kind=="Water" and actionState:find("drink",1,true)
  local activePrompt=Brain.stopActionVisible() and Brain.observedActionKind(observedSource())==kind
  local plateauGrace=finishedFood and 1.5 or (UIS.TouchEnabled and (activeState or activePrompt)and 8 or (kind=="Food"and 3 or 6))
  if firstIncrease and now-lastIncrease>=plateauGrace then outcome="plateau"break end
  local startGrace=UIS.TouchEnabled and (activeState or activePrompt)and 12 or 8
  if not firstIncrease and not activeState and not activePrompt and not resume and presses<3
   and now-lastPress>=3 and prompt(kind,true) and not Brain.stopActionVisible() then
   state("لم يبدأ "..kind.." بعد؛ أعيد E عند نفس المورد قبل تغيير الوجهة")
   if UIS.TouchEnabled then Brain.rejectButtonTransport()end
   tapE(token,model) presses+=1 lastPress=os.clock()
  end
		if not firstIncrease and now-started>=startGrace then outcome="no_increase" break end
		state("تعبئة "..kind.." • "..string.format("%.1f%%",after).." • ثابت دون W أو E إضافي")
		task.wait(.15)
	end
	if not valid(token,model) then return false,after,"cancelled",before end
	releaseW()
	if not Brain.finishAction(token,model) then outcome="stop_unconfirmed" end
	return firstIncrease,after,outcome,before
end
local function consumeOnce(kind,token,model,root,resume)
 if kind=="Water"and Brain.resourceGoals and Brain.resourceGoals.Water then Brain.drinkExitBank=Brain.resourceGoals.Water.returnPosition or Brain.resourceGoals.Water.position end
 if kind=="Water"and not Brain.worldCare()and Brain.home and Brain.home.recordedStations and not(Brain.resourceGoals and Brain.resourceGoals.Water and Brain.resourceGoals.Water.returnPosition)then
  for index=#Brain.home.route-1,1,-1 do
   local p=Brain.home.route[index]
   if Brain.homeDistance(p,Brain.home.water)>=8 and Brain.homeDistance(p,root.Position)<=32 then
    local hit=cast(p,model)if dry(hit)then Brain.drinkExitBank=hit.Position break end
   end
  end
 end
 local attempt={kind=kind,token=token,model=model,started=os.clock(),beat=os.clock()}
 Brain.refillAttempt=attempt
 local ok,confirmed,after,outcome,before=pcall(Brain.consumeCore,kind,token,model,root,resume)
 if Brain.refillAttempt==attempt then Brain.refillAttempt=nil end
 if not ok then error(confirmed)end
 if outcome=="target"and after and after>=CFG.Target then Brain.completedFill=kind activeKind=nil Brain.motionTrace("fill_complete",kind)end
 if kind=="Food" and (outcome=="plateau" or outcome=="no_increase")and Brain.rejectFoodPatch then Brain.rejectFoodPatch(root.Position,outcome)end
 return confirmed,after,outcome,before
end
local function nudgeIntoWater(token,model,root)
	local waterPoint,distance
	for _,radius in {2,4,6} do
		for i=0,7 do
			if not valid(token,model) then return false end
			local angle=i*math.pi/4
			local hit=terrainAt(root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
			if isWater(hit) then
				local d=(hit.Position-root.Position).Magnitude
				if not distance or d<distance then waterPoint=hit.Position distance=d end
			end
		end
		if waterPoint then break end
	end
	if not waterPoint then return false end
	if perf.frameSeconds>.05 then return false end
	local delta=waterPoint-root.Position
	local flat=Vector3.new(delta.X,0,delta.Z)
	if flat.Magnitude<.1 then return false end
	local direction=flat.Unit
	if CFG.HomeOnly and Brain.mode~="Quests" and not Brain.homeInside(root.Position+direction*3) then return false end
	local start=root.Position
	local floor=walkable(start,model,true)
	local ahead=walkable(start+direction*3,model,true)
	if not floor or not ahead or not safeSegment(floor,ahead,model,true) then return false end
	if not valid(token,model) then return false end
	aim=direction
	Brain.shoreNudge=true
	local ok,moved=pcall(function()
		movementFrame()
		if not valid(token,model) then return false end
		heldW=true send(Enum.KeyCode.W,true)
		local deadline=os.clock()+.65
		while valid(token,model) and os.clock()<deadline do
   local _,_,h=rig()
   if Brain.waterThreat and Brain.waterThreat(model,root,h) then break end
   local safe=immediateSafety(root.Position,direction,model)
   if safe==false then break end
   if safe==nil then releaseW("shore_budget_wait") Run.Heartbeat:Wait() continue end
   if not heldW then heldW=true send(Enum.KeyCode.W,true) end
			local travel=root.Position-start
			if Vector3.new(travel.X,0,travel.Z).Magnitude>=1.2 then break end
			Run.Heartbeat:Wait()
		end
		return (root.Position-start).Magnitude>.1
	end)
	releaseW() if token==generation then Brain.shoreNudge=false end
	if not ok then error(moved) end
	return moved
end
local function inputSummary()
	if not inputTrace then return "E لم يُرسل بعد" end
	return "InputBegan="..tostring(inputTrace.began).." / InputEnded="..tostring(inputTrace.ended).." / processed="..tostring(inputTrace.processed)
end
function Brain.awaitStats(token,model)
 local deadline=os.clock()+12
 repeat
  local f,w=stats()
  if f~=nil and w~=nil then return f,w end
  releaseW("stats_wait")
  if not valid(token,model) then return end
  state("أنتظر رجوع بيانات الأكل والماء") task.wait(.25)
 until os.clock()>=deadline
 return nil,nil
end
function Brain.workerFinished(token,ok,err,mode)
 if token~=generation then return end
 local _,_,h=rig()
 local recover=alive and unlocked and (not Brain.licenseExpires or os.clock()<Brain.licenseExpires) and running and h and h.Health>0
 local reason=tostring(err or "انقطع التشغيل")
 stop(ok and "انقطع التحكم؛ أعيد التهيئة" or ("تعذر مؤقت: "..reason),true)
 if not recover then return end
 Brain.workerRetry=(Brain.workerRetry or 0)+1
 local restartToken=generation
 local function retry(attempt)
  local f,w=stats()
  local critical=f and w and math.min(f,w)<20
  local delaySeconds=critical and math.min(3,attempt) or math.min(30,5*2^math.min(attempt-1,3))
  Brain.autoResumeAt=os.clock()+delaySeconds
  state("أعيد محاولة الوضع بعد "..delaySeconds.." ث؛ السبب محفوظ في الفحص")
  task.delay(delaySeconds,function()
   if not alive or not unlocked or running or generation~=restartToken or not Brain.start then return end
   if Brain.licenseExpires and os.clock()>=Brain.licenseExpires then state("أنتظر تجديد التفعيل؛ أعد التشغيل بعد الاتصال") return end
   Brain.start(mode,true)
   if alive and unlocked and not running and generation==restartToken then retry(attempt+1) end
  end)
 end
 retry(Brain.workerRetry)
end
local function choose(food,water,current)
 if Brain.completedFill then
  local done=Brain.completedFill local other=done=="Food"and "Water"or"Food"
  Brain.completedFill=nil Brain.fillNeeds[done]=false
  if (other=="Food"and food or water)<CFG.Target then Brain.fillNeeds[other]=true current=other end
 end
 local kind=Brain.policy.choose(Brain.fillNeeds,food,water,current or Brain.fillKind,CFG.Threshold,CFG.Target)
 Brain.fillKind=kind return kind
end
function Brain.policy.swimContinue(oxygen,stamina,health,initialHealth,food,water,seconds,hasProgress)
 if oxygen==nil or stamina==nil or food==nil or water==nil then return false,"missing_safety_data" end
 if oxygen<92 then return false,"oxygen" end
 if stamina<35 then return false,"stamina" end
 if health<initialHealth-.5 then return false,"damage" end
 if food<CFG.Threshold or water<CFG.Threshold then return false,"needs" end
 if seconds>=12 and not hasProgress then return false,"no_quest_progress" end
 return true
end
function Brain.swimVitals(model)
 local oxygen=model:GetAttribute("Oxygen") local stamina=model:GetAttribute("Stamina")
 local oxygenMax=model:GetAttribute("MaxOxygen") or model:GetAttribute("OxygenMax")
 if typeof(oxygen)~="number" or typeof(stamina)~="number" then return end
 if oxygenMax==nil and oxygen>0 and oxygen<=1 then return end
 oxygenMax=oxygenMax or 100
 local staminaMax=model:GetAttribute("MaxStamina") or model:GetAttribute("StaminaMax") or 100
 if oxygenMax<=0 or staminaMax<=0 or oxygen<0 or oxygen>oxygenMax or stamina<0 or stamina>staminaMax then return end
 return oxygen/oxygenMax*100,stamina/staminaMax*100
end
function Brain.swimWetPoint(point,model)
 local surface=terrainAt(point)
 if not isWater(surface) or surface.Instance:GetAttribute("BLY_Hazard") then return end
 local bed=supportBelow(surface.Position,model)
 if not bed or bed.Normal.Y<.55 or bed.Instance:GetAttribute("BLY_Hazard") then return end
 local depth=surface.Position.Y-bed.Position.Y
 if depth<math.max(2.5,CFG.AgentHeight*.70) or depth>math.min(20,CFG.AgentHeight*1.8) then return end
 return surface.Position
end
function Brain.swimWaterLine(a,b,model)
 for i=0,math.ceil((b-a).Magnitude/3) do
  local count=math.max(1,math.ceil((b-a).Magnitude/3))
  if not Brain.swimWetPoint(a:Lerp(b,i/count),model) then return false end
 end
 return true
end
function Brain.swimCourseAt(bank,token,model)
 for _,radius in {12,18,24,32,40,48} do
  for i=0,11 do
   if not valid(token,model) then return end
   local angle=i*math.pi/6 local direction=Vector3.new(math.cos(angle),0,math.sin(angle))
   local middle=Brain.swimWetPoint(bank+direction*radius,model)
   if middle then
    local side=Vector3.new(-direction.Z,0,direction.X)
    local a=Brain.swimWetPoint(middle+side*5,model) local b=Brain.swimWetPoint(middle-side*5,model)
    if a and b and Brain.swimWaterLine(a,b,model) and Brain.rescueLine(a,bank,model) and Brain.rescueLine(b,bank,model) then return {a=a,b=b,bank=bank} end
   end
  end
 end
end
function Brain.swimStep(root,destination,course,model)
 if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock() end
 if workCount+8>CFG.QueriesPerFrame then return nil end
 safetyBatch=true
 local ok,result=pcall(function()
  if not dry(terrainAt(course.bank)) then return false end
  local here=terrainAt(root.Position)
  if not here or (not isWater(here) and not dry(here)) or here.Instance:GetAttribute("BLY_Hazard") then return false end
  if (Vector3.new(root.Position.X,course.bank.Y,root.Position.Z)-course.bank).Magnitude>60 then return false end
  if isWater(here) then
   local bed=supportBelow(here.Position,model)
   if not bed or here.Position.Y-bed.Position.Y>math.min(20,CFG.AgentHeight*1.8) then return false end
   if root.Position.Y<here.Position.Y-(CFG.AgentHeight*.6+2) then return false end
  end
  local delta=destination-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
  if flat.Magnitude<.1 then return true end
  local nextHit=terrainAt(root.Position+flat.Unit*2)
  if not nextHit or (not dry(nextHit) and not isWater(nextHit)) or nextHit.Instance:GetAttribute("BLY_Hazard") then return false end
  if isWater(nextHit) then
   local bed=supportBelow(nextHit.Position,model)
   if not bed or nextHit.Position.Y-bed.Position.Y>math.min(20,CFG.AgentHeight*1.8) then return false end
  end
  queryBudget()
  local params=parameters(model)
  local wall=workspace:Raycast(root.Position+Vector3.new(0,2,0),flat.Unit*3,params)
  if wall and not isWater(wall) and wall.Normal.Y<.5 then return false end
  return true
 end)
 safetyBatch=false if not ok then error(result) end return result
end
function Brain.isActuallySwimming(model,humanoid)
 local movement=string.lower(tostring(model:GetAttribute("MovementState") or ""))
 if movement:find("swim",1,true) and not movement:find("not",1,true) then return true end
 local ok,result=pcall(function() return humanoid:GetState()==Enum.HumanoidStateType.Swimming end)
 return ok and result==true
end
-- Owner-recorded swim entry
function Brain.installSwimRecording()
 Brain.recordedSwim={place=18214855317,points={},firstSwim=9,maxDepth=22}
 for _,p in {{-6560.41,-8.68,4507.34},{-6555.87,-5.91,4511.72},{-6559.66,-9.3,4519.05},{-6570.12,-14.1,4521.52},{-6582.01,-18.19,4524.57},{-6592.74,-20.27,4531.46},{-6602.34,-21.74,4540.55},{-6611.18,-24.29,4550.6},{-6618.79,-29.24,4559.56},{-6625.21,-28.42,4569.01},{-6631.24,-28.37,4577.1},{-6636.82,-28.38,4584.06}} do table.insert(Brain.recordedSwim.points,Vector3.new(p[1],p[2],p[3]))end
end
Brain.installSwimRecording()
function Brain.recordedSwimCounter(key)
 for _,q in Brain.readQuests() do
  if q.key==key then
   if q.kind~="Swim" or type(q.current)~="number" or type(q.target)~="number" or q.target<=0 or (q.seenAt and os.clock()-q.seenAt>10) then return nil,"unavailable"end
   if q.complete or q.current>=q.target then return q,"complete"end
   return q,"active"
  end
 end
 return nil,"unavailable"
end
function Brain.recordedSwimCheck(root,target,model)
 if workFrame~=perf.frame then workFrame=perf.frame workCount=0 sliceStart=os.clock()end
 if workCount+10>CFG.QueriesPerFrame then return nil end
 safetyBatch=true
 local ok,safe=pcall(function()
  local delta=target-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
  if flat.Magnitude<.1 then return true end
  for _,p in {root.Position,root.Position+flat.Unit*math.min(3,flat.Magnitude)} do
   local hit=terrainAt(p)
   if not hit or (not dry(hit) and not isWater(hit)) or hit.Instance:GetAttribute("BLY_Hazard")then return false end
   if isWater(hit)then
    local bed=supportBelow(hit.Position,model)
    if not bed or bed.Instance:GetAttribute("BLY_Hazard") or hit.Position.Y-bed.Position.Y>Brain.recordedSwim.maxDepth+8 then return false end
    if root.Position.Y<hit.Position.Y-(CFG.AgentHeight*.6+2)then return false end
   end
  end
  queryBudget()
  local wall=workspace:Raycast(root.Position+Vector3.new(0,1,0),flat.Unit*math.min(3,flat.Magnitude),parameters(model))
  return not wall or isWater(wall) or wall.Normal.Y>=.5
 end)
 safetyBatch=false if not ok then error(safe)end return safe
end
function Brain.recordedSwimQuest(objective,token,model,root)
 local course=Brain.recordedSwim local points=course.points local n=#points
 local _,_,h=rig()
 local function defer(message,seconds)
  releaseW("recorded_swim_defer")Brain.questPauseUntil[objective.key]=os.clock()+(seconds or 30)Brain.activeQuest=nil state(message)return true
 end
 if game.PlaceId~=course.place then return defer("تسجيل السباحة يخص الماب المسجل")end
 local q,phase=Brain.recordedSwimCounter(objective.key)
 if phase~="active"then
  releaseW("recorded_swim_counter")Brain.nextQuestScan=0
  if phase=="complete"then Brain.activeQuest=nil end
  return true
 end
 local oxygen,stamina=Brain.swimVitals(model)
 if not h or not oxygen or not stamina then return defer("السباحة تنتظر قراءة الأكسجين والطاقة")end
 if oxygen<99 or stamina<65 then return defer("أستريح على البر قبل إكمال السباحة",8)end
 if Brain.stopActionVisible() and not Brain.finishAction(token,model)then return true end
 if not valid(token,model)then return true end
 local nearest,distance=1,math.huge
 for i,p in points do local d=Brain.homeDistance(root.Position,p)if d<distance then nearest=i distance=d end end
 if distance>math.max(10,CFG.AgentRadius*2+3)then
  if not dry(cast(root.Position,model))then Brain.rescueToLand(token,model,root)return true end
  local route=Brain.worldTravelRoute(points[1],token,model,root)
  if route and valid(token,model)then state("أتجه لبداية مسار السباحة المسجل")walk(route,"Travel",token,model,root)
  else return defer("أنتظر طريقًا قابلًا للمشي لبداية تسجيل السباحة",5)end
  return true
 end
 local bank=cast(points[1],model)
 if not dry(bank)then return defer("أنتظر تأكيد يابسة بداية مسار السباحة",5)end
 local index=math.min(nearest+1,n)local direction=1 local returning=false local outcome
 local started=os.clock()local lastPosition=root.Position local movedAt=started local health=h.Health
 local initial=q.current local lastValue=q.current local progressAt=started local swimAt local entryAt
 local nextScan=0 local nextCheck=0 local checked=false local lastUi=0 local completed=false local landed=false
 local function goBack(reason)
  if returning then return end
  returning=true outcome=reason if direction==1 then index=math.max(1,index-1)end direction=-1 nextCheck=0
 end
 Brain.questSwimming=true Brain.shoreNudge=true Brain.motionPhase="swimming"Brain.setShift(false)
 local ok,err=pcall(function()
  while valid(token,model)do
   local now=os.clock()
   if now>=nextScan then
    nextScan=now+.5 q,phase=Brain.recordedSwimCounter(objective.key)
    if phase=="complete"then completed=true goBack("complete")
    elseif phase~="active"then goBack("unavailable")
    elseif q.current>lastValue then lastValue=q.current progressAt=now end
   end
   oxygen,stamina=Brain.swimVitals(model)local food,water=stats()
   if not returning then
    if not CFG.QuestsEnabled then goBack("off")
    elseif not oxygen or not stamina or not food or not water then goBack("vitals")
    elseif oxygen<96 or stamina<50 or food<CFG.Threshold or water<CFG.Threshold or h.Health<health-.5 then goBack("needs")end
   end
   local actually=Brain.isActuallySwimming(model,h)
   if actually then swimAt=swimAt or now end
   if not returning then
    if index>=course.firstSwim then entryAt=entryAt or now end
    if not swimAt and entryAt and now-entryAt>25 then goBack("entry")end
    if swimAt and now-math.max(swimAt,progressAt)>20 then goBack("progress")end
    if now-started>180 then goBack("rest")end
   end
   if Brain.projectLane(points,root.Position,true)>math.max(12,CFG.AgentRadius*2+4)then outcome="drift"break end
   local target=points[index]local flat=Vector3.new(target.X-root.Position.X,0,target.Z-root.Position.Z)
   if flat.Magnitude<=3 then
    if returning and index==1 then
     if dry(cast(root.Position,model))then landed=true break else outcome="exit"break end
    end
    if not returning and index==n then
     if not actually then goBack("entry")else direction=-1 index=n-1 end
    elseif not returning and direction==-1 and index==1 then direction=1 index=2
    else index=math.clamp(index+direction,1,n)end
    nextCheck=0 continue
   end
   if now>=nextCheck then checked=Brain.recordedSwimCheck(root,target,model)nextCheck=now+.2 end
   if checked==false then outcome="blocked"break end
   if checked==nil then releaseW("swim_geometry_wait")Run.Heartbeat:Wait()continue end
   aim=flat.Unit movementFrame()if not valid(token,model)then break end
   if not heldW then heldW=true send(Enum.KeyCode.W,true)end
   if (root.Position-lastPosition).Magnitude>.3 then lastPosition=root.Position movedAt=now end
   if now-movedAt>3 then outcome="stuck"break end
   if now-lastUi>.5 then
    lastUi=now state(returning and "أرجع للبر على نفس مسار السباحة" or ((actually and "سباحة فعلية على تسجيلك" or "أدخل الماء على تسجيلك").." • "..string.format("%.0f / %.0f",lastValue,q and q.target or 0)))
   end
   Run.Heartbeat:Wait()
  end
 end)
 releaseW("recorded_swim_end")
 if token==generation then Brain.questSwimming=false Brain.shoreNudge=false Brain.motionPhase=nil end
 if valid(token,model) and not landed and not dry(cast(root.Position,model))then Brain.rescueToLand(token,model,root)end
 if not ok then error(err)end
 if not valid(token,model)then return true end
 if completed then Brain.nextQuestScan=0 Brain.activeQuest=nil state("اكتملت السباحة حسب عدّاد اللعبة؛ أتحقق من المهمة التالية")return true end
 if outcome=="entry"or outcome=="progress"then return defer("ما تأكد تقدم السباحة لهذا الحيوان؛ رجعت للبر",45)end
 if outcome=="blocked"or outcome=="drift"or outcome=="stuck"then return defer("تعذر إكمال المسار؛ أعدت فحص الخروج للبر",10)end
 Brain.nextTravel=os.clock()+2 return true
end
function Brain.swimQuest(objective,token,model,root)
 if Brain.recordedSwim and Brain.homeDistance(root.Position,Brain.recordedSwim.points[1])<180 then return Brain.recordedSwimQuest(objective,token,model,root)end
 local _,_,h=rig() local oxygen,stamina=Brain.swimVitals(model)
 local function defer(reason)
  Brain.questPauseUntil[objective.key]=os.clock()+60 Brain.activeQuest=nil
  state(reason) return true
 end
 if not h or not oxygen or not stamina then return defer("مهمة السباحة تنتظر قراءة أكسجين وطاقة مؤكدة؛ أكمل بقية المهام") end
 if oxygen<99 or stamina<65 then return defer("أؤجل السباحة حتى يرجع الأكسجين والطاقة") end
 if Brain.stopActionVisible() and not Brain.finishAction(token,model) then return true end
 local footing=cast(root.Position,model)
 if not dry(footing) then Brain.rescueToLand(token,model,root) return true end
 local route=Brain.resourceRoute("Water",token,model,root)
 if not valid(token,model) then return true end
 if route and not route.here and route.position and (route.position-root.Position).Magnitude>7 then
  state("مهمة السباحة؛ أتجه لشاطئ محدد أولًا")
  walk(route,"Travel",token,model,root) return true
 end
 local bank=footing.Position
 if not safeSegment(bank,bank,model,false) then return defer("ما تأكدت طلعة آمنة للسباحة") end
 local course=Brain.swimCourseAt(bank,token,model)
 if not valid(token,model) then return true end
 if not course then return defer("ما تأكد مسار سباحة قصير وطلعة يابسة؛ أجرب مهمة ثانية") end
 local before=0
 for _,q in Brain.readQuests() do if q.key==objective.key then before=q.current break end end
 local initialHealth=h.Health
 local started=os.clock() local progress=false local lastPosition=root.Position local progressAt=started
 local destination=course.a local stage=1 local outcome="return_to_land"
 local swimmingStarted=nil local lastQuestValue=before local lastQuestProgressAt=os.clock()
 Brain.questSwimming=true Brain.shoreNudge=true Brain.motionPhase="swimming" Brain.setShift(false)
 local ok,err=pcall(function()
  while valid(token,model) and CFG.QuestsEnabled do
   local f,w=stats() oxygen,stamina=Brain.swimVitals(model)
   local q,phase=Brain.recordedSwimCounter(objective.key)
   if phase=="complete"then outcome="complete"return end
   if phase~="active"then Brain.nextQuestScan=0 outcome="counter_unavailable"return end
   if q.current>lastQuestValue then progress=true lastQuestValue=q.current lastQuestProgressAt=os.clock()end
   if Brain.isActuallySwimming(model,h) then swimmingStarted=swimmingStarted or os.clock() end
   if not swimmingStarted and os.clock()-started>25 then outcome="entry_failed" return end
   local swimElapsed=swimmingStarted and os.clock()-swimmingStarted or 0
   if swimmingStarted and progress and os.clock()-lastQuestProgressAt>20 then outcome="no_quest_progress" return end
   local proceed,reason=Brain.policy.swimContinue(oxygen,stamina,h.Health,initialHealth,f,w,swimElapsed,progress)
   if not proceed then outcome=reason return end
   local safe=Brain.swimStep(root,destination,course,model)
   if safe==false then outcome="unsafe_course" return end
   if safe==nil then Run.Heartbeat:Wait() continue end
   local delta=destination-root.Position local flat=Vector3.new(delta.X,0,delta.Z)
   if flat.Magnitude<2 then
    if not swimmingStarted then outcome="entry_too_shallow" return end
    stage+=1 destination=stage%2==0 and course.b or course.a
   end
   delta=destination-root.Position flat=Vector3.new(delta.X,0,delta.Z)
   if flat.Magnitude>.1 then aim=flat.Unit end
   movementFrame() if not valid(token,model) then return end
   if not heldW then heldW=true send(Enum.KeyCode.W,true) end
   if (root.Position-lastPosition).Magnitude>.3 then lastPosition=root.Position progressAt=os.clock() end
   if os.clock()-progressAt>2 then outcome="stuck" return end
   state((swimmingStarted and "سباحة فعلية • أكسجين " or "أدخل لمسار السباحة • أكسجين ")..string.format("%.0f%%",oxygen))
   Run.Heartbeat:Wait()
  end
 end)
 releaseW("swim_return")
 if token==generation then Brain.questSwimming=false Brain.shoreNudge=false Brain.motionPhase=nil end
 if valid(token,model) then Brain.rescueToLand(token,model,root) end
 if not ok then error(err) end
 if outcome=="complete" then Brain.nextQuestScan=0 Brain.activeQuest=nil end
 if outcome=="entry_failed" or outcome=="entry_too_shallow" then return defer("الموضع ما فعّل السباحة للحيوان؛ رجعت لليابس بدل الدوران على الطرف") end
 if outcome=="no_quest_progress" then return defer("ما زاد عدّاد السباحة؛ رجعت لليابس وأجرب مهمة ثانية") end
 return true
end
function Brain.configureBody(model,root)
 local ok,_,size=pcall(function() return model:GetBoundingBox() end)
 if ok and typeof(size)=="Vector3" then
  CFG.AgentRadius=math.clamp(math.min(size.X,size.Z)*.35,1.5,5)
  CFG.AgentHeight=math.clamp(size.Y,5,12)
  CFG.Footprint=math.clamp(CFG.AgentRadius*.5,.8,2)
 end
 Brain.motionTrace("body_configured",tostring(CFG.AgentRadius).." / "..tostring(CFG.AgentHeight))
end
function Brain.growthCareKind(food,water,model,current)
 if not Brain.worldCare()or not Brain.growth or Brain.growth.waterModel==model or food<CFG.Threshold then return current end
 if current=="Food"and Brain.fillNeeds.Food then return current end
 if prompt("Water",true)then
  Brain.growth.waterModel=model
  if water<CFG.Target then Brain.fillNeeds.Water=true return "Water"end
  return current
 end
 return "Water"
end
function Brain.policy.questCare(food,water,latched,threshold,target)
 if latched=="Food"and food<target then return "Food"end
 if latched=="Water"and water<target then return "Water"end
 if food<threshold or water<threshold then return food<=water and "Food"or "Water"end
end
function Brain.questCareKind(food,water,model,objective)
 if Brain.questNeedModel~=model then Brain.questNeed=nil Brain.questNeedModel=model end
 local need=Brain.policy.questCare(food,water,Brain.questNeed,CFG.Threshold,CFG.Target)
 Brain.questNeed=need
 Brain.fillKind=need Brain.completedFill=nil Brain.pendingNeed=nil
 Brain.fillNeeds={Food=need=="Food",Water=need=="Water"}
 return need or Brain.policy.questResource(objective,food,water,CFG.Target)
end
local function startHome(mode,automatic)
	if not unlocked then state("بانتظار تفعيل الإدارة") return end
	if running then stop("متوقف؛ التحكم اليدوي متاح") return end
	if not vim then state("إرسال الأزرار غير متاح") return end
	if UIS:GetFocusedTextBox() then UIS:GetFocusedTextBox():ReleaseFocus() end
	local model,root,h=rig()
	if not root or not h or h.Health<=0 then state("الغزال غير جاهز") return end
	if game.PlaceId~=18214855317 then state("تسجيل الشاطئ يخص ماب Savannah Life فقط") return end
	local food,water=stats()
	if food==nil or water==nil then state("لم أقرأ Character.Food/Water بمقياس صالح؛ أوقفت البدء دون نسب مخترعة") return end
	local diet=model:GetAttribute("FoodType")
	if mode~="Quests" and diet~=nil and string.lower(tostring(diet))~="grass" then state("هذا الملف مخصص لـ FoodType=Grass؛ نوع الحيوان الحالي مختلف") return end
	if Brain.needModel~=model then Brain.fillNeeds={Food=false,Water=false} Brain.fillKind=nil Brain.completedFill=nil Brain.needModel=model end
	Brain.nearSafetyPending=nil
 if not automatic or Brain.homeRouteModel~=model then Brain.resourceGoals={} Brain.homeStation=nil end
 Brain.homeRouteModel=model Brain.runtimeCaution=false Brain.motionHold=nil Brain.headingAligned=false
	Brain.configureBody(model,root)
	Brain.resetSpeed(model)
	Brain.healthySince=nil
 running=true generation+=1 local token=generation Brain.workerBeatAt=os.clock() Brain.sessionHealthState=nil
	task.spawn(function()
		local worker=coroutine.running() queryScopes[worker]=token
		local ok,err=xpcall(function()
			if mode=="Probe" then
				state("اختبار E دون مشي؛ انتظار السكون")
				if not settle(token,model,root) then error("الغزال لم يسكن") end
				local before=rawSource() tapE(token,model)
				task.wait(2)
				if not valid(token,model) then return end
				lastE="قبل: "..before.." / بعد: "..rawSource().." / "..inputSummary()
				stop("انتهى الاختبار؛ تفاصيله في الفحص") return
			end
			beginCamera()
			local current
			local retryAt={Food=0,Water=0}
			local failure={Food="",Water=""}
			local function waitFor(seconds)
				local deadline=os.clock()+seconds
				while valid(token,model) and os.clock()<deadline do task.wait(math.min(.1,math.max(.01,deadline-os.clock()))) end
			end
			while valid(token,model) do
                Brain.controlTickAt=os.clock()
                Brain.healthySince=Brain.healthySince or os.clock()
                if os.clock()-Brain.healthySince>120 then Brain.workerRetry=0 end
                local _,_,waterHumanoid=rig()
                if Brain.waterThreat and Brain.waterThreat(model,root,waterHumanoid) then
                    local escaped=Brain.rescueToLand(token,model,root)
                    if not valid(token,model) then return end
                    if not escaped then waitFor(1) end
                    continue
                end
                if CFG.HomeOnly and Brain.mode=="Survival" and (not Brain.homeInside(root.Position) or Brain.homeLeashDue(root.Position)) then
                    Brain.returnHomeAfterRescue(token,model,root)
                    if not valid(token,model) then return end
                    waitFor(.5) continue
                end
				local f,w=Brain.awaitStats(token,model)
				if f==nil or w==nil then error("انقطع مصدر Food/Water الحقيقي؛ توقفت بدل اتخاذ قرار بلا بيانات") end
				if CFG.QuestsEnabled and not (current and Brain.resourceGoals[current]) then
					if Brain.completedQuestDue() then Brain.nextQuestScan=0 end
     Brain.questService(token,model)
					Brain.groupService(token,model)
					if not valid(token,model) then return end
					f,w=stats()
					if not f or not w then error("انقطعت النسب بعد قراءة المهمات") end
				end
				local previous=current
				if mode=="Quests"then
     local objective=Brain.objective()
     Brain.resourceZone=objective and objective.hold and objective.zone or nil
     current=Brain.questCareKind(f,w,model,objective)
    else current=Brain.growthCareKind(f,w,model,choose(f,w,current))end
    if Brain.worldCare()and current=="Water"and f<CFG.Threshold and not Brain.resourceGoals.Water and prompt("Food",true)then current="Food"Brain.fillNeeds.Food=true end
				local kind=current
				if kind and retryAt[kind]>os.clock() then
					local other=kind=="Food" and "Water" or "Food"
					local amount=other=="Food" and f or w
					if mode~="Quests" and retryAt[other]<=os.clock() and Brain.fillNeeds[other] and Brain.policy.canDefer(kind,f,w) then
						kind=other current=other
					else
						activeKind=nil releaseW()
						state("مراقبة مستمرة؛ إعادة محاولة "..kind.." بعد "..math.ceil(retryAt[kind]-os.clock()).." ث: "..failure[kind])
						waitFor(.5) continue
					end
				end
				activeKind=kind
                if Brain.stopActionVisible() then
                    local source=observedSource()
                    local action=Brain.observedActionKind(source)
                    if kind==action then
                        local confirmed,after,outcome=consumeOnce(kind,token,model,root,true)
                        if not valid(token,model) then return end
                        if confirmed then Brain.homeStation=root.Position end
                        if after and after>=CFG.Target then Brain.clearResourceGoal(kind,"اكتملت التعبئة") end
                        local ff,ww=stats()
                        current=Brain.policy.afterAttempt(kind,outcome,ff,ww,Brain.fillNeeds) or current
                        if outcome=="plateau" then retryAt[kind]=os.clock()+(kind=="Food" and .2 or 3) end
                        if outcome=="stop_unconfirmed" then waitFor(3) end
                        continue
                    end
                    state("إنهاء التفاعل السابق قبل الانتقال")
                    if not Brain.finishAction(token,model) then waitFor(3) continue end
                end
				if not kind then
					releaseW()
					if CFG.QuestsEnabled and Brain.questStep(token,model,root) then waitFor(.5) continue end
					state("مراقبة مستمرة؛ التحرك عند انخفاض الشبع أو الارتواء تحت 70%")
					waitFor(.5) continue
				end
				decisionMode="قرار بالقيم الحقيقية من Character • تفعيل <70% / تعبئة حتى 100%"
				if not prompt(kind) then
					local here=cast(root.Position,model)
					if not walkable(root.Position,model,true) and not retreatToShore(token,model,root) then
						if not valid(token,model) then return end
						retryAt[kind]=os.clock()+15 failure[kind]="لم أؤكد مسار خروج ضحل؛ لا أتحرك في عمق مجهول"
						releaseW() state(failure[kind]) waitFor(1) continue
					end
					state(kind=="Water" and "الارتواء منخفض؛ أبحث عن ماء وشاطئ قابل للوصول" or "الشبع منخفض؛ أبحث عن رقعة Grass وخيار الأكل الحقيقي")
					local route=Brain.planResource(kind,token,model,root)
					if not valid(token,model) then return end
					if not route then
						retryAt[kind]=os.clock()+(Brain.resourceGoals[kind] and .5 or 2)
						failure[kind]=Brain.resourceGoals[kind] and "الوجهة محفوظة؛ أنتظر طريقًا مؤكدًا إليها" or (Brain.routeReason or "لم أجد موردًا محمّلًا بمسار آمن قريب")
						releaseW() state(failure[kind]) waitFor(.5) continue
					end
					state("المشي للمورد المطلوب؛ E ينتظر ظهور تفاعل الماب")
					local result=walk(route,kind,token,model,root)
					for repairAttempt=1,2 do
						if not valid(token,model) or not route.position or (result~="offroute" and result~="blocked") then break end
						local destination,water,exploration=route.position,route.water,route.exploration
						local transit,goalPosition=route.transit,route.goalPosition
						Brain.routeReason="إعادة تخطيط إلى نفس الوجهة"
						local repaired=Brain.travelRoute(destination,token,model,root)
						if not repaired or (repaired.position-destination).Magnitude>2 then break end
						repaired.water=water repaired.exploration=exploration repaired.transit=transit repaired.goalPosition=goalPosition route=repaired
						result=walk(route,kind,token,model,root)
					end
					Brain.lastWalkResult=result
					if not valid(token,model) then return end
					if result~="arrived" and result~="prompt" and not prompt(kind,true) then
						Brain.resourceFailure(kind,result)
						retryAt[kind]=os.clock()+.3
						failure[kind]="أعيد فحص الطريق إلى الوجهة المثبتة"
						state(failure[kind]) continue
					end
					if result=="arrived" and route.transit and not prompt(kind,true) then
						state("أكمل الطريق إلى نفس الوجهة") waitFor(.05) continue
					end
					if route.exploration and result=="arrived" and not prompt(kind,true) then
      avoided[kind..cell(route.position)]=os.clock()+90
						Brain.clearResourceGoal(kind,"اكتمل فحص نطاق الاستكشاف")
						state("أفحص الموارد في النطاق الذي وصلت إليه") waitFor(.1) continue
					end
					if route.position and result~="arrived" and result~="prompt" then avoided[kind..cell(route.position)]=os.clock()+10 end
					if result=="arrived" and kind=="Water" and route.water and not prompt(kind) then approachShore(route,token,model,root) end
					if not valid(token,model) then return end
					waitFor(.4)
					if not valid(token,model) then return end
					if not prompt(kind) then
						if kind=="Water" and knownShore and (root.Position-knownShore).Magnitude<10 then knownShore=nil knownDrinkPosition=nil end
						retryAt[kind]=os.clock()+(kind=="Food" and .2 or 5) failure[kind]="لم يظهر خيار المورد عند الوجهة؛ سأعيد التقييم"
						local goal=Brain.resourceGoals[kind]
						if goal and (root.Position-goal.position).Magnitude<10 then Brain.resourceFailure(kind,"لم يظهر خيار المورد عند الوجهة") end
						releaseW() state(failure[kind]) continue
					end
				end
				releaseW()
				if not settle(token,model,root) then
					if not valid(token,model) then return end
					retryAt[kind]=os.clock()+.8 failure[kind]="أنتظر السكون الحقيقي قبل ضغط E" continue
				end
				if not valid(token,model) then return end
				if not prompt(kind,true) then waitFor(.3) continue end
				if prompt(kind=="Food" and "Water" or "Food") then error("تفاعلا أكل وشرب ظاهران معًا؛ أوقفت التفاعل الملتبس") end
				local confirmed,after,consumeOutcome,before=consumeOnce(kind,token,model,root)
				for attempt=1,4 do
					if confirmed or kind~="Water" or consumeOutcome~="no_increase" or not valid(token,model) then break end
					local beforeNudge=after
					state("لم تبدأ زيادة الماء؛ أتقدم خطوة قصيرة مفحوصة عند الحافة")
					if not nudgeIntoWater(token,model,root) then break end
					if not settle(token,model,root) or not valid(token,model) then break end
					local _,nowWater=stats()
					local resumed=nowWater and beforeNudge and nowWater>beforeNudge+.02
					if not resumed and not prompt("Water",true) then break end
					confirmed,after,consumeOutcome,before=consumeOnce(kind,token,model,root,resumed)
				end
				if not valid(token,model) then return end
				lastE=kind.." / قبل="..tostring(before).." / بعد="..tostring(after).." / نتيجة="..consumeOutcome.." / "..inputSummary()
				if not confirmed then
                    local ff,ww=stats()
                    current=Brain.policy.afterAttempt(kind,consumeOutcome,ff,ww,Brain.fillNeeds) or current
					local goal=Brain.resourceGoals[kind]
					if goal and (root.Position-goal.position).Magnitude<10 then Brain.resourceFailure(kind,"لم يبدأ التفاعل عند المورد") end
					retryAt[kind]=os.clock()+3
					if kind=="Food" then
						Brain.failedFood={key=cell(root.Position),untilTime=os.clock()+12}
						Atlas.note("Food",root.Position,"changed")
						retryAt[kind]=os.clock()+.2
					end
					failure[kind]="لم تُسجل زيادة بعد E؛ "..inputSummary()
					state(failure[kind]) waitFor(.5) continue
				end
				Brain.homeStation=root.Position
				if after and after>=CFG.Target then Brain.clearResourceGoal(kind,"اكتملت التعبئة") end
				if kind=="Water" then rememberWater(model,root,true)
				else
					Atlas.note("Food",root.Position,"confirmed")
					if not prompt("Food",true) and consumeOutcome=="plateau" then
						lastConsumed=root.Position Brain.lastFoodUntil=os.clock()+60 Atlas.note("Food",root.Position,"depleted") Brain.clearResourceGoal(kind,"نفدت الرقعة بعد الأكل")
					end
				end
				if consumeOutcome=="plateau" and not prompt(kind,true) then avoided[kind..cell(root.Position)]=os.clock()+(kind=="Water" and 8 or 60) end
				local ff,ww=stats()
                current=Brain.policy.afterAttempt(kind,consumeOutcome,ff,ww,Brain.fillNeeds) or current
                retryAt[kind]=consumeOutcome=="plateau" and (os.clock()+(kind=="Food" and .2 or 3)) or 0 failure[kind]=""
				state("تأكدت زيادة "..kind.."؛ أعيد تقييم النسب")
				waitFor(.1)
				if kind=="Food" and consumeOutcome=="plateau" and valid(token,model) and not prompt("Food",true) then Atlas.note("Food",root.Position,"depleted") end
				Atlas.save(false)
			end
		end,function(e) return tostring(e) end)
		queryScopes[worker]=nil
		Brain.workerFinished(token,ok,err,mode)
	end)
end
local function startQuests(mode,automatic)
 Brain.mode=mode CFG.HomeOnly=false CFG.QuestsEnabled=true
 CFG.AutoRun=true if CFG.RunMode=="Off"then CFG.RunMode="Hold"end
 Brain.nextQuestScan=0 Brain.nextTravel=0 Brain.activeQuest=nil Brain.questNeed=nil
 startHome(mode,automatic)
end
local function start(mode,automatic)
 if Brain.taqshee and (Brain.taqshee.busy or Brain.taqshee.pending) then state("أكمل أو ألغِ التقشيع أولًا") return end
 if Brain.chatTyping then state("أكمل كتابة رسالتك لاستكمال البوت") return end
 if not automatic and not running and Brain.requestedMode==mode then stop("ألغيت إعادة التشغيل التلقائي") return end
 if automatic and running then return end
 if not automatic and Brain.growth and Brain.growth.active and not Brain.growth.driving then Brain.growth.active=false Brain.growth.sequence+=1 end
 if not unlocked then state("بانتظار تفعيل الإدارة") return end
 if running then
  local same=Brain.mode==mode
  stop("أوقفت الوضع السابق")
  if same then return end
 end
 Brain.requestedMode=mode
 if mode=="Quests" then
  Brain.resourceRoute=Brain.worldResourceRoute
  Brain.travelRoute=Brain.worldTravelRoute
  startQuests(mode,automatic)
 elseif mode=="Growth"or mode=="Survival"then
  CFG.HomeOnly=false Brain.resourceRoute=Brain.worldResourceRoute Brain.travelRoute=Brain.worldTravelRoute
  Brain.mode=mode CFG.QuestsEnabled=false
  startHome(mode,automatic)
 else
  CFG.HomeOnly=true
  Brain.resourceRoute=Brain.homeResourceRoute
  Brain.travelRoute=CFG.HomeOnly and Brain.homePath or Brain.worldTravelRoute
  Brain.mode="Survival" CFG.QuestsEnabled=false
  startHome(mode,automatic)
 end
end
Brain.start=start
function Brain.policy.sessionHealth(sample,previous)
 local now=sample.now
 local needs=sample.food and sample.water and (sample.food<CFG.Threshold or sample.water<CFG.Threshold or sample.pending==true)
 local critical=needs and math.min(sample.food,sample.water)<20
 if not previous or previous.token~=sample.token or previous.model~=sample.model then
  previous={token=sample.token,model=sample.model,progressAt=now,motionAt=now,refillAt=now,x=sample.x,z=sample.z,food=sample.food,water=sample.water,stamina=sample.stamina}
 end
 if now-(sample.beat or now)>(needs and (critical and 10 or 20) or 45) then return previous,"worker_not_responding" end
 if not needs then previous.progressAt=now previous.motionAt=now previous.refillAt=now end
 local progress=(sample.food and previous.food and sample.food>previous.food+.02)
  or (sample.water and previous.water and sample.water>previous.water+.02)
 if progress then previous.refillAt=now end
 if sample.x and previous.x and ((sample.x-previous.x)^2+(sample.z-previous.z)^2)>1 then
  previous.motionAt=now previous.x=sample.x previous.z=sample.z
  if not sample.goalKey then progress=true end
 end
 if sample.goalKey and sample.distance then
  if previous.goalKey~=sample.goalKey then previous.goalKey=sample.goalKey previous.bestDistance=sample.distance
  elseif sample.distance<(previous.bestDistance or sample.distance)-1 then previous.bestDistance=sample.distance progress=true end
 end
 if progress then previous.progressAt=now end
 previous.food=sample.food previous.water=sample.water previous.stamina=sample.stamina
 if needs and now-(previous.motionAt or now)>=(critical and 8 or 18) and now-(previous.refillAt or now)>=(critical and 8 or 18) then return previous,"need_without_progress" end
 if needs and now-previous.progressAt>=(critical and 15 or 45) then return previous,"need_without_progress" end
 return previous,nil
end
function Brain.superviseSession()
 if Brain.chatTyping then
  if UIS:GetFocusedTextBox() then return end
  if Brain.resumeChatTyping then Brain.resumeChatTyping() end
 end
 if not alive or not running or not Brain.requestedMode then Brain.sessionHealthState=nil return end
 if not unlocked or (Brain.licenseExpires and os.clock()>=Brain.licenseExpires) then return end
 local model,root,h=rig()
 if not root or not h or h.Health<=0 then return end
 local food,water=stats()
 if food and food<CFG.Threshold then Brain.fillNeeds.Food=true end
 if water and water<CFG.Threshold then Brain.fillNeeds.Water=true end
 local kind=activeKind or (food and water and (food<water and "Food" or "Water"))
 local goal=kind and Brain.resourceGoals[kind]
 local sample={now=os.clock(),token=generation,model=model,beat=Brain.workerBeatAt,
  food=food,water=water,stamina=Brain.staminaPercent(model),x=root.Position.X,z=root.Position.Z,
  pending=(Brain.fillNeeds.Food and food and food<CFG.Target)or(Brain.fillNeeds.Water and water and water<CFG.Target),
  goalKey=goal and (kind..cell(goal.position)),distance=goal and Brain.homeDistance(root.Position,goal.position)}
 local nextState,reason=Brain.policy.sessionHealth(sample,Brain.sessionHealthState)
 Brain.sessionHealthState=nextState
 if not reason then return end
 local protected=Brain.resourcePlanLive(sample.now,generation)or Brain.refillAttemptLive(sample.now,generation,model)
 local grace=food and water and math.min(food,water)<20 and 24 or 40
 if protected and sample.now-nextState.progressAt<grace then return end
 local mode=Brain.requestedMode
 Brain.motionTrace("session_recovery",reason)
 if reason=="need_without_progress" and goal then
  Brain.home.avoid[kind..cell(goal.position)]=os.clock()+25 avoided[kind..cell(goal.position)]=os.clock()+25
  Brain.clearResourceGoal(kind,"لا تقدم فعلي؛ أراجع المورد")
  if kind=="Water" then knownShore=nil knownDrinkPosition=nil end
 end
 stop("أعيد تهيئة البقاء؛ الطلب محفوظ",true)
 Brain.sessionHealthState=nil
 Brain.autoResumeAt=os.clock()+2
 local token=generation
 task.delay(2,function()
  if alive and unlocked and not running and generation==token and Brain.requestedMode==mode then Brain.start(mode,true) end
 end)
end
function Brain.resumeRequested()
 if Brain.chatTyping then
  if UIS:GetFocusedTextBox() then return end
  if Brain.resumeChatTyping then Brain.resumeChatTyping() end
 end
 if not alive or running or not unlocked or not Brain.requestedMode then return end
 if os.clock()<(Brain.autoResumeAt or 0) then return end
 if Brain.licenseExpires and os.clock()>=Brain.licenseExpires then return end
 if Brain.growth and Brain.growth.active then return end
 Brain.autoResumeAt=os.clock()+5
 Brain.start(Brain.requestedMode,true)
end
task.spawn(function()
 while alive do
  task.wait(2)
  if alive then
   local ok,err=pcall(Brain.superviseSession)
   if not ok then Brain.supervisorError=tostring(err) end
   if running then Brain.motionTrace("sample",Brain.motionPhase or currentState) end
   if Brain.saveMotionTrace then Brain.saveMotionTrace() end
   local resumed,resumeError=pcall(Brain.resumeRequested)
   if not resumed then Brain.supervisorError=tostring(resumeError) end
  end
 end
end)
gui=new("ScreenGui",{Name="BLY_Mono",IgnoreGuiInset=true,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
local shutdown=new("BindableEvent",{Name="Shutdown"},gui)
on(gui.Destroying,function()
 Run:UnbindFromRenderStep("BLY_COMPAT_MOVE")
 if Brain.compat.motorConnection then Brain.compat.motorConnection:Disconnect()Brain.compat.motorConnection=nil end
 Brain.clearButtonReceipt()
end)
local window=new("CanvasGroup",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(700,500),BackgroundColor3=Color3.fromRGB(2,16,19),BorderSizePixel=0,ClipsDescendants=true,Visible=false,GroupTransparency=1},gui)
round(window,28)
new("UIStroke",{Color=Color3.fromRGB(170,252,255),Transparency=.03,Thickness=2.2},window)
local rim=new("Frame",{Position=UDim2.fromOffset(2,2),Size=UDim2.new(1,-4,1,-4),BackgroundTransparency=1,BorderSizePixel=0,Active=false},window)
round(rim,28) new("UIStroke",{Color=Color3.fromRGB(35,190,213),Thickness=4,Transparency=.55},rim)
local scale=new("UIScale",{},window)
local background=new("ImageLabel",{Position=UDim2.fromScale(0,0),Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ImageTransparency=.86,ScaleType=Enum.ScaleType.Crop},window)
round(background,28)
local tint=new("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(2,15,18),BackgroundTransparency=.34,BorderSizePixel=0},window)
round(tint,28)
new("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.58,.25),NumberSequenceKeypoint.new(1,.56)})},tint)
local headerPortrait=new("ImageLabel",{Position=UDim2.fromOffset(28,10),Size=UDim2.fromOffset(58,58),BackgroundColor3=Color3.fromRGB(14,14,17),Image="",ImageRectOffset=Vector2.new(0,0),ImageRectSize=Vector2.new(0,0),ScaleType=Enum.ScaleType.Crop},window)
round(headerPortrait,12)
new("UIStroke",{Color=Color3.new(0,0,0),Thickness=2},headerPortrait)
local portraitRim=new("Frame",{Position=UDim2.fromOffset(2,2),Size=UDim2.new(1,-4,1,-4),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=2},headerPortrait)
round(portraitRim,10)
new("UIStroke",{Color=white,Thickness=1,Transparency=.22},portraitRim)
local header=text(window,"BLY / VICTORY",109,9,280,34,25)
header.TextXAlignment=Enum.TextXAlignment.Left header.Font=Enum.Font.Bodoni header.Active=true
local signature=text(window,"S7M × BLY  •  لعبة في البقاء في البرية",109,43,280,16,11) signature.TextXAlignment=Enum.TextXAlignment.Left signature.TextColor3=Color3.fromRGB(188,194,198)
local uiSequence=0
Brain.uiWanted=false
local function setWindowShown(wanted)
	Brain.uiWanted=wanted uiSequence+=1
	if not wanted and Brain.aboutPanel then Brain.aboutPanel.Visible=false end
	local sequence=uiSequence
	if wanted then
		window.Visible=true
		tweenUI(window,{GroupTransparency=0},.18)
	else
		tweenUI(window,{GroupTransparency=1},.14)
		task.delay(.16,function()
			if alive and sequence==uiSequence and not Brain.uiWanted then window.Visible=false end
		end)
	end
end
Brain.suspendQuestPanel=function()
	local lease={sequence=uiSequence,generation=generation,wasVisible=window.Visible,chatVisible=Brain.chat and Brain.chat.panel.Visible,chatSequence=Brain.chat and Brain.chat.sequence}
	Brain.activeQuestPanelLease=lease
 if Brain.chat then Brain.chat.panel.Visible=false end
	window.Visible=false
	return lease
end
Brain.restoreQuestPanel=function(lease)
	if Brain.activeQuestPanelLease==lease then Brain.activeQuestPanelLease=nil end
	if alive and window.Parent and lease and lease.generation==generation and lease.sequence==uiSequence and Brain.uiWanted and lease.wasVisible then window.Visible=true end
 if alive and lease and lease.generation==generation and Brain.chat and Brain.chat.sequence==lease.chatSequence and lease.chatVisible then Brain.chat.panel.Visible=true end
end
local content=new("Frame",{Position=UDim2.fromOffset(0,70),Size=UDim2.fromOffset(700,430),BackgroundTransparency=1},window)
local mini=button(window,"−",602,20,32,function()
	setWindowShown(false)
end)
local close=button(window,"×",646,20,32,function() gui:Destroy() end)
mini.Size=UDim2.fromOffset(32,30) close.Size=UDim2.fromOffset(32,30)
Brain.aboutPanel=new("Frame",{Position=UDim2.fromOffset(20,62),Size=UDim2.fromOffset(660,414),BackgroundColor3=Color3.fromRGB(9,11,14),BackgroundTransparency=0,Visible=false,Active=true,ZIndex=80},window)
round(Brain.aboutPanel,24)
new("UIStroke",{Color=Color3.fromRGB(199,205,209),Transparency=.35,Thickness=1},Brain.aboutPanel)
local aboutTitle=text(Brain.aboutPanel,"من نحن",28,26,604,34,24) aboutTitle.ZIndex=82
local aboutNames=text(Brain.aboutPanel,"S7M  ×  BLY",28,78,604,38,28) aboutNames.ZIndex=82 aboutNames.TextColor3=Color3.fromRGB(200,206,210)
local aboutBody=text(Brain.aboutPanel,"حياك في بي إل واي.\n\nالبقاء الحر يبدأ من مكان الحيوان الحالي، ويفحص أقرب عشب وضفاف ماء مع مسار آمن. إذا لم يجد موردا، يستكشف اليابسة تدريجيا دون الاعتماد على شاطئ ثابت. يبدأ عند نزول أي نسبة تحت 70% ويكمل التعبئة إلى 100%. إذا احتاج المورد الثاني يخدمه قبل إكمال التعبئة. تكبير الحيوانات للعواشب المشتراة فقط.\n\nالمهمات لها تشغيل مستقل، وينفّذ منها الأنواع المدعومة فقط. سباحة المهام مشروطة بقراءة الأكسجين ومسار خروج مفحوص. التكبير له زر مستقل.\n\nوقت ارتفاع الماء، يحاول يطلع لليابسة قبل ما يكمل.",32,128,596,212,18)
aboutBody.Font=Enum.Font.Arial aboutBody.LineHeight=1.12 aboutBody.ZIndex=82
aboutBody.TextXAlignment=Enum.TextXAlignment.Right aboutBody.TextYAlignment=Enum.TextYAlignment.Top
local aboutClose=button(Brain.aboutPanel,"رجوع",210,358,240,function() Brain.aboutPanel.Visible=false end) aboutClose.ZIndex=83
local aboutButton=button(window,"من نحن",478,20,104,function() Brain.aboutPanel.Visible=true end) aboutButton.Size=UDim2.fromOffset(104,30) aboutButton.TextSize=12
local chatButton=button(window,"شات",394,20,74,function() Brain.toggleChat() end)
chatButton.Name="BLY_SeparateChat" chatButton.Size=UDim2.fromOffset(74,30) chatButton.TextSize=12 Brain.chatButton=chatButton
function Brain.chatTextHeight(value,width,size)
 local ok,bounds=pcall(function() return game:GetService("TextService"):GetTextSize(value,size,Enum.Font.Arial,Vector2.new(width,1000)) end)
 return math.clamp(ok and bounds.Y or (math.ceil(utf8.len(value)/math.max(1,math.floor(width/(size*.6))))*size),size,112)
end
function Brain.chatBubble(message)
 local chat=Brain.chat
 if not chat or not message or not message.id or chat.muted[tostring(message.userId)] then return end
 local id=tostring(message.id)
 if chat.bubbleSeen[id] then return end
 local target=Players:GetPlayerByUserId(tonumber(message.userId) or 0)
 local character=target and target.Character
 local root=character and (character:FindFirstChild("Head",true) or character:FindFirstChild("HumanoidRootPart"))
 if not root or not root:IsA("BasePart") then root=character and character:FindFirstChild("HumanoidRootPart") end
 if not root then return end
 chat.bubbleSeen[id]=true table.insert(chat.bubbleOrder,id)
 if #chat.bubbleOrder>100 then chat.bubbleSeen[table.remove(chat.bubbleOrder,1)]=nil end
 local userId=tostring(message.userId) local previous=chat.bubbles[userId]
 if previous then previous:Destroy() end
 local h=math.min(86,Brain.chatTextHeight(tostring(message.text),224,14))+32
 local offset=3.5 pcall(function() if root.Name=="HumanoidRootPart" then offset=math.clamp(character:GetExtentsSize().Y*.5+1.5,3.5,14) end end)
 local bubble=new("BillboardGui",{Name="BLY_ChatBubble",Adornee=root,Size=UDim2.fromOffset(252,h+10),StudsOffsetWorldSpace=Vector3.new(0,offset,0),AlwaysOnTop=false,MaxDistance=100},gui)
 chat.bubbles[userId]=bubble
 local card=new("Frame",{Size=UDim2.new(1,0,1,-10),BackgroundColor3=Color3.fromRGB(13,23,30),BackgroundTransparency=0,BorderSizePixel=0},bubble) round(card,12)
 new("UIStroke",{Color=Color3.fromRGB(145,220,236),Thickness=1,Transparency=.25},card)
 local tail=new("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,1,-10),Size=UDim2.fromOffset(10,10),Rotation=45,BackgroundColor3=Color3.fromRGB(13,23,30),BorderSizePixel=0},bubble)
 local brand=text(card,"BLY  •  @"..tostring(message.username),10,4,232,16,10) brand.TextColor3=Color3.fromRGB(140,206,221)
 local body=text(card,tostring(message.text),12,22,228,h-26,14) body.RichText=false body.TextTruncate=Enum.TextTruncate.AtEnd
 local pop=new("UIScale",{Scale=.88},card)
 TweenService:Create(pop,TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1}):Play()
 task.delay(6,function() if chat.bubbles[userId]==bubble then chat.bubbles[userId]=nil end bubble:Destroy() end)
end
function Brain.createChatUI()
 local chat={provider="global",nativeAllowed=false,nativeChecked=false,nativeChecking=false,allowed=false,rows={},seen={},muted={},hidden={},cursor=0,consented=false,pollBusy=false,sendBusy=false,sequence=0,bubbles={},bubbleSeen={},bubbleOrder={},nearCursor=0,nearBusy=false,receiving=true}
 Brain.chat=chat
 local ink=Color3.fromRGB(5,15,21) local cyan=Color3.fromRGB(102,227,250) local muted=Color3.fromRGB(153,198,213)
 local function edge(o,r,opacity,thickness)
  round(o,r) new("UIStroke",{Color=cyan,Transparency=opacity,Thickness=thickness or 1},o)
 end
 local function surface(name,parent,z,color,alpha)
  return new("Frame",{Name=name,BackgroundColor3=color or ink,BackgroundTransparency=alpha or 0,BorderSizePixel=0,ZIndex=z},parent)
 end
 local panel=surface("BLY_ChatPanel",gui,100,ink,.43)
 panel.Position=UDim2.fromOffset(16,78) panel.Size=UDim2.fromOffset(464,280) panel.Visible=false panel.Active=true
 chat.panel=panel edge(panel,24,.12,1.5)
 local scale=new("UIScale",{},panel)
 local inner=surface("InnerRim",panel,101,ink,1)
 inner.Position=UDim2.fromOffset(3,3) inner.Size=UDim2.new(1,-6,1,-6) edge(inner,21,.76,2)
 local glow=surface("HeaderGlow",panel,100,Color3.fromRGB(25,113,143),.76)
 glow.Size=UDim2.new(1,0,0,68) round(glow,23)
 new("UIGradient",{Rotation=105,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(.45,.73),NumberSequenceKeypoint.new(1,1)})},glow)
 local accent=surface("Skyline",panel,101,cyan)
 accent.Position=UDim2.fromOffset(12,46) accent.Size=UDim2.new(1,-24,0,1)
 new("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.52,.25),NumberSequenceKeypoint.new(1,1)})},accent)
 local top=surface("DragHeader",panel,101,ink,1) top.Size=UDim2.new(1,0,0,46) top.Active=true
 local portrait=new("ImageLabel",{Position=UDim2.fromOffset(12,7),Size=UDim2.fromOffset(34,34),BackgroundColor3=Color3.fromRGB(8,26,36),Image=Brain.iconAsset or "",ScaleType=Enum.ScaleType.Fit,ZIndex=102},top)
 edge(portrait,13,.34) chat.portrait=portrait
 local heading=text(top,"BLY  /  COMMUNITY",55,6,250,22,18)
 heading.Font=Enum.Font.Bodoni heading.TextXAlignment=Enum.TextXAlignment.Left heading.TextWrapped=false heading.TextTruncate=Enum.TextTruncate.AtEnd heading.ZIndex=102 heading.Active=true
 local signature=text(top,"S7M × BLY  •  نظام الدردشة",56,28,240,14,10)
 signature.TextXAlignment=Enum.TextXAlignment.Left signature.TextColor3=muted signature.ZIndex=102
 signature.TextWrapped=false signature.TextTruncate=Enum.TextTruncate.AtEnd
 local close=button(panel,"×",0,17,32,function() Brain.toggleChat(false) end)
 close.Position=UDim2.new(1,-37,0,9) close.Size=UDim2.fromOffset(26,27) close.TextSize=19 close.ZIndex=104
 local restore=button(panel,"إظهار الكل",0,17,86,function() chat.hidden={} chat.muted={} Brain.chatSelect(chat.provider) chat.delivery.Text="أُعيدت الرسائل وأُلغي الكتم" end)
 restore.Position=UDim2.new(1,-116,0,9) restore.Size=UDim2.fromOffset(71,27) restore.TextSize=12 restore.ZIndex=104
 local globalTab=button(panel,"كل الدردشات",17,75,200,function() Brain.chatSelect("global") end)
 local serverTab=button(panel,"سيرفرك • BLY",227,75,200,function() Brain.chatSelect("server") end)
 globalTab.ZIndex=102 serverTab.ZIndex=102 globalTab.TextSize=15 serverTab.TextSize=15 chat.tabs={server=serverTab,global=globalTab}
 local notice=surface("ChannelNotice",panel,101,Color3.fromRGB(10,40,51),.57) edge(notice,13,.44)
 local note=text(notice,"",10,0,0,35,13)
 note.Size=UDim2.new(1,-20,1,0) note.TextXAlignment=Enum.TextXAlignment.Right note.TextColor3=Color3.fromRGB(191,232,242) note.ZIndex=102 chat.note=note
 local list=new("ScrollingFrame",{Position=UDim2.fromOffset(227,169),Size=UDim2.fromOffset(684,252),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),ScrollBarThickness=3,ScrollBarImageColor3=cyan,ZIndex=101},panel)
 new("UIPadding",{PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)},list)
 local messageLayout=new("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},list) chat.list=list
 on(messageLayout:GetPropertyChangedSignal("AbsoluteContentSize"),function() list.CanvasSize=UDim2.fromOffset(0,messageLayout.AbsoluteContentSize.Y+12) end)
 local input=new("TextBox",{BackgroundColor3=Color3.fromRGB(7,28,39),BackgroundTransparency=.39,TextColor3=white,PlaceholderColor3=muted,Text="",PlaceholderText="اكتب رسالتك هنا…",ClearTextOnFocus=false,TextSize=16,Font=Enum.Font.Arial,TextXAlignment=Enum.TextXAlignment.Right,TextWrapped=false,TextEditable=false,RichText=false,ZIndex=102},panel)
 edge(input,12,.5) new("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},input) chat.input=input
 local sendButton=button(panel,"إرسال",0,0,110,function() Brain.chatSend() end)
 sendButton.TextSize=16 sendButton.ZIndex=103 chat.sendButton=sendButton Brain.primaryButton(sendButton)
 chat.delivery=text(panel,"",0,0,0,18,12) chat.delivery.TextColor3=muted chat.delivery.ZIndex=102
 chat.join=button(panel,"دخول الشات وبدء الكتابة",0,0,240,function()
  if not chat.allowed then return end
  chat.consented=true Brain.chatSelect("global")
 end) chat.join.ZIndex=104 chat.join.Visible=false
 local function layoutRow(entry)
  local narrow=chat.compact and (chat.messageWidth or 680)<310
  entry.author.Size=UDim2.fromOffset(narrow and 78 or 99,22)
  entry.time.Position=UDim2.fromOffset(narrow and 91 or 114,7)
  entry.time.Size=UDim2.fromOffset(narrow and 39 or 46,22)
  local left=chat.compact and 11 or 163
  local right=chat.compact and 14 or 115
  local bodyHeight=Brain.chatTextHeight(entry.content,math.max(90,(chat.messageWidth or 680)-left-right-16),15)
  local rowHeight=chat.compact and bodyHeight+38 or math.max(38,bodyHeight+17)
  entry.row.Size=UDim2.new(1,-4,0,rowHeight)
  entry.body.Position=UDim2.fromOffset(left,chat.compact and 29 or 8)
  entry.body.Size=UDim2.new(1,-left-right,0,bodyHeight)
 end
 local nativeWindow
 chat.integrated=false
 function Brain.chatAdd(message)
  if message.provider~=chat.provider or chat.muted[tostring(message.userId)] then return false end
  local key=message.provider..":"..tostring(message.id)
  if chat.seen[key] or chat.hidden[key] then return false end
  local shouldScroll=list.CanvasPosition.Y+list.AbsoluteSize.Y>=list.CanvasSize.Y.Offset-36
  local own=tostring(message.userId)==tostring(player.UserId)
  local content=tostring(message.text) local username=tostring(message.username)
  local row=new("Frame",{Name="ChatMessage",Size=UDim2.new(1,-4,0,40),BackgroundColor3=own and Color3.fromRGB(11,43,56) or Color3.fromRGB(7,29,39),BackgroundTransparency=.49,BorderSizePixel=0,ZIndex=102,LayoutOrder=#chat.rows+1},list)
  round(row,12) new("UIStroke",{Color=Color3.fromRGB(82,182,208),Transparency=.83,Thickness=1},row)
  local author=text(row,"@"..username,11,7,99,22,13)
  author.TextWrapped=false author.TextTruncate=Enum.TextTruncate.AtEnd author.TextXAlignment=Enum.TextXAlignment.Left author.TextColor3=white author.ZIndex=103 author.RichText=false
  local stamp=tonumber(message.createdAt)
  local timeLabel=text(row,stamp and stamp>0 and os.date("%H:%M",stamp) or "",114,7,46,22,12)
  timeLabel.TextColor3=Color3.fromRGB(109,197,218) timeLabel.ZIndex=103
  local body=text(row,content,0,0,0,18,15)
  body.TextXAlignment=Enum.TextXAlignment.Right body.TextYAlignment=Enum.TextYAlignment.Top body.RichText=false body.ZIndex=103
  local entry={row=row,body=body,author=author,time=timeLabel,content=content,username=username,userId=tostring(message.userId),key=key}
  layoutRow(entry)
  local function rowAction(caption,x,callback)
   local action=new("TextButton",{Position=UDim2.new(1,x,0,7),Size=UDim2.fromOffset(caption=="كتم" and 44 or 22,22),BackgroundTransparency=.12,BackgroundColor3=Color3.fromRGB(46,66,76),Text=caption,TextColor3=Color3.fromRGB(167,195,205),TextSize=13,Font=Enum.Font.Arial,ZIndex=104},row)
   round(action,6) action.Activated:Connect(callback)
  end
  rowAction("×",-28,function()
   chat.hidden[key]=true row.Visible=false chat.delivery.Text="أُخفيت هذه الرسالة فقط • إظهار الكل يعيدها"
  end)
  if tostring(message.userId)~=tostring(player.UserId) then
   rowAction("كتم",-104,function()
    local userId=tostring(message.userId) chat.muted[userId]=true
    for _,entry in chat.rows do if entry.userId==userId then entry.row.Visible=false end end
    if chat.bubbles[userId] then chat.bubbles[userId]:Destroy() chat.bubbles[userId]=nil end
    chat.delivery.Text="كُتم المستخدم عندك • إظهار الكل يلغي الكتم"
   end)
  end
  rowAction("!",-54,function()
   task.spawn(function() local result,err=Brain.chatHTTP("/api/chat/report",{id=message.id}) if alive then chat.delivery.Text=result and "وصل البلاغ للإدارة" or err end end)
  end)
  chat.seen[key]=true
  table.insert(chat.rows,entry)
  if #chat.rows>60 then local old=table.remove(chat.rows,1) chat.seen[old.key]=nil old.row:Destroy() end
  for i,entry in chat.rows do entry.row.LayoutOrder=i end
  if shouldScroll then task.defer(function() if alive and list.Parent then list.CanvasPosition=Vector2.new(0,list.CanvasSize.Y.Offset) end end) end
  return true
 end
 function Brain.chatClear()
  for _,entry in chat.rows do entry.row:Destroy() end chat.rows={} chat.seen={}
 end
 function Brain.chatPoll()
  if chat.pollBusy or not Brain.chatAccess(chat.provider) or (chat.provider=="global" and not chat.consented) or not panel.Visible then return end
  chat.pollBusy=true local sequence=chat.sequence local provider=chat.provider
  local ok,result,err=pcall(Brain.chatHTTP,"/api/chat/read",{after=chat.cursor,room=Brain.chatRoom(provider)})
  chat.pollBusy=false
  if not alive or not panel.Visible or sequence~=chat.sequence then return end
  if ok and result then
   for _,message in result.messages or {} do message.provider=provider Brain.chatAdd(message) chat.cursor=math.max(chat.cursor,tonumber(message.id) or 0) end
   note.Text=provider=="global" and "شات BLY العام • للمفعّلين في كل السيرفرات • سجل آخر 24 ساعة" or "شات BLY في سيرفرك • للمفعّلين هنا فقط • سجل آخر 24 ساعة"
  else note.Text=ok and err or "تعذر تحديث الشات" end
 end
 function Brain.chatSelect(provider)
  chat.sequence+=1 chat.provider=provider chat.allowed=Brain.chatAccess(provider) Brain.chatClear() chat.cursor=0
  for name,b in chat.tabs do Brain.selectButton(b,name==provider) end
  local globalReady=provider=="global" and chat.consented
  input.TextEditable=chat.allowed and (provider=="server" or globalReady) and not (provider=="server" and chat.integrated)
  input.Active=input.TextEditable
  input.PlaceholderText=provider=="global" and (chat.consented and "اكتب رسالة في شات BLY…" or "اضغط دخول الشات أولًا…") or "اكتب رسالة للسيرفر…"
  sendButton.Active=input.TextEditable
  sendButton.TextColor3=input.TextEditable and white or Color3.fromRGB(111,133,143)
  input.Visible=not (provider=="server" and chat.integrated) sendButton.Visible=input.Visible
  chat.join.Visible=provider=="global" and not chat.consented and chat.allowed
  list.Visible=not (provider=="server" and chat.integrated) and not chat.join.Visible
  if nativeWindow then
   nativeWindow.Visible=provider=="server"
   local channels=game:GetService("TextChatService"):FindFirstChild("TextChannels")
   nativeWindow.Target=channels and channels:FindFirstChild("RBXGeneral")
  end
  if not chat.allowed then note.Text="شات BLY يحتاج تفعيلًا ساريًا واتصالًا بخدمته"
  elseif provider=="global" then
   note.Text="شات BLY المستقل للمفعّلين • رسائلك تظهر لهم • سجل آخر 24 ساعة"
   task.spawn(Brain.chatPoll)
  else
   note.Text="شات BLY في سيرفرك • يصل فقط لمن يشغّل السكربت هنا"
   task.spawn(Brain.chatPoll)
  end
 end
 function Brain.chatSend()
  if chat.sendBusy then chat.delivery.Text="أنتظر تأكيد الرسالة السابقة…" return end
  if not Brain.chatAccess(chat.provider) then chat.delivery.Text="التفعيل غير جاهز؛ حدّث الاتصال" return end
  if os.clock()<(chat.nextSendAt or 0) then chat.delivery.Text="انتظر "..math.ceil(chat.nextSendAt-os.clock()).." ثانية" return end
  local raw=input.Text local value=raw:match("^%s*(.-)%s*$") if value=="" then return end
  if Brain.vipParse and Brain.vipParse(value)then Brain.vipSubmit(value)input.Text=""return end
  if Brain.taqsheeParse and Brain.taqsheeParse(value) then Brain.taqsheeSubmit(value) input.Text="" return end
  if not utf8.len(value) or utf8.len(value)>200 then chat.delivery.Text="اختصر الرسالة إلى 200 حرف" return end
  if chat.provider=="global" and not chat.consented then chat.delivery.Text="اضغط دخول الشات أولًا" return end
  chat.sendBusy=true local provider=chat.provider
  sendButton.Text="…" chat.delivery.Text="جارٍ إرسال الرسالة…"
  task.spawn(function()
   local success=false local failure="تعذر الإرسال" local retryAfter
   local ok,err=pcall(function()
    if not Brain.chatAccess(provider) then failure="انتهى التفعيل؛ حدّث الاتصال" return end
    local room=Brain.chatRoom(provider)
    if not chat.pendingSend or chat.pendingSend.text~=value or chat.pendingSend.room~=room then chat.pendingSend={text=value,room=room,id=game:GetService("HttpService"):GenerateGUID(false)} end
    local result,problem,waitSeconds=Brain.chatHTTP("/api/chat/send",{text=value,room=room,clientId=chat.pendingSend.id})
    if not result or result.ok~=true then failure=problem retryAfter=waitSeconds return end
    success=true chat.pendingSend=nil
    if not alive then return end
    local message=result.message
    if message then
     message.provider=provider
     local rendered,renderError=pcall(Brain.chatAdd,message)
     if not rendered then chat.lastRenderError=tostring(renderError) end
     pcall(Brain.chatBubble,message)
    end
    if input.Text==raw then input.Text="" end
   end)
   chat.sendBusy=false
   if not alive then return end
   sendButton.Text="إرسال"
   if success then
    chat.nextSendAt=os.clock()+1 chat.delivery.Text="تم إرسال الرسالة ✓"
    task.spawn(Brain.chatPoll)
   else
    chat.nextSendAt=os.clock()+math.max(1,retryAfter or 1)
    chat.delivery.Text=ok and (failure or "تعذر الإرسال؛ الرسالة محفوظة في الخانة") or "تعذر إكمال الإرسال؛ حاول مرة ثانية"
    if not ok then chat.lastSendError=tostring(err) end
   end
  end)
 end
 function Brain.chatNearby()
  if chat.nearBusy or not chat.receiving or not Brain.chatAccess("server") then return end
  chat.nearBusy=true
  local ok,result=pcall(Brain.chatHTTP,"/api/chat/nearby",{after=chat.nearCursor,room=Brain.chatRoom("server"),includeGlobal=chat.consented})
  chat.nearBusy=false
  if not ok or not result or not alive then return end
  for _,message in result.messages or {} do
   chat.nearCursor=math.max(chat.nearCursor,tonumber(message.id) or 0)
   pcall(Brain.chatBubble,message)
  end
 end
 function Brain.pauseChatTyping()
  if Brain.chatTyping then return end
  Brain.chatTyping=true
  if Brain.growth and Brain.growth.active then
   Brain.growth.active=false Brain.growth.sequence+=1 chat.growthResume=Brain.growth.sequence
   local mode=Brain.mode stop("توقفت الأزرار أثناء كتابة الرسالة",true) chat.resume={mode=mode,token=generation}
  elseif running then
   local mode=Brain.mode stop("توقفت الأزرار أثناء كتابة الرسالة",true) chat.resume={mode=mode,token=generation}
  end
 end
 function Brain.resumeChatTyping()
  Brain.chatTyping=false
  local lease=chat.resume local growthSequence=chat.growthResume chat.resume=nil chat.growthResume=nil
  if lease then task.defer(function()
   if not alive or Brain.chatTyping or running or generation~=lease.token then return end
   if growthSequence and Brain.growth.sequence==growthSequence and not Brain.growth.active then Brain.beginGrowth()
   elseif not growthSequence and Brain.requestedMode==lease.mode then Brain.start(lease.mode,true) end
  end) end
 end
 on(input.Focused,Brain.pauseChatTyping)
 on(input.FocusLost,function(enter) Brain.resumeChatTyping() if enter then Brain.chatSend() end end)
 on(input:GetPropertyChangedSignal("Text"),function() local count=utf8.len(input.Text) if count and count>200 then input.Text=string.sub(input.Text,1,utf8.offset(input.Text,201)-1) end end)
 function Brain.toggleChat(wanted)
  if wanted==nil then wanted=not panel.Visible end
  chat.sequence+=1
  if wanted then
   panel.Visible=true chat.receiving=true Brain.nativeChat.open=true Brain.selectButton(Brain.chatButton,true)
   Brain.chatSelect(chat.provider)
  else
   input:ReleaseFocus() Brain.resumeChatTyping()
   panel.Visible=false Brain.nativeChat.open=false Brain.selectButton(Brain.chatButton,false)
  end
 end
 local dragging,startInput,startPosition
 local function begin(inputEvent)
  if inputEvent.UserInputType==Enum.UserInputType.MouseButton1 or inputEvent.UserInputType==Enum.UserInputType.Touch then dragging=true startInput=inputEvent.Position startPosition=panel.AbsolutePosition end
 end
 on(top.InputBegan,begin) on(heading.InputBegan,begin)
 on(UIS.InputChanged,function(event)
  if not dragging or not workspace.CurrentCamera then return end
  if event.UserInputType~=Enum.UserInputType.MouseMovement and event.UserInputType~=Enum.UserInputType.Touch then return end
  local pos=startPosition+Vector2.new(event.Position.X-startInput.X,event.Position.Y-startInput.Y) local viewport=workspace.CurrentCamera.ViewportSize
  panel.Position=UDim2.fromOffset(math.clamp(pos.X,8,math.max(8,viewport.X-panel.AbsoluteSize.X-8)),math.clamp(pos.Y,52,math.max(52,viewport.Y-panel.AbsoluteSize.Y-8)))
 end)
 on(UIS.InputEnded,function(event) if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
 local function fit()
  local camera=workspace.CurrentCamera
  if not camera then return end
  local viewport=camera.ViewportSize
  local w=math.clamp(viewport.X-24,292,464)
  local h=280
  scale.Scale=math.clamp(math.min(1,(viewport.X-16)/w,(viewport.Y-64)/h),.25,1)
  panel.Size=UDim2.fromOffset(w,h)
  panel.Position=UDim2.fromOffset(math.max(8,viewport.X-w*scale.Scale-14),math.max(52,math.min(68,viewport.Y-h*scale.Scale-10)))
  chat.compact=w<425
  heading.Text=w<390 and "BLY / CHAT" or "BLY  /  COMMUNITY"
  heading.Size=UDim2.fromOffset(w-177,22)
  signature.Size=UDim2.fromOffset(w-177,14)
  local tabWidth=math.floor((w-32)/2)
  globalTab.Position=UDim2.fromOffset(12,51)
  globalTab.Size=UDim2.fromOffset(tabWidth,28)
  serverTab.Position=UDim2.fromOffset(20+tabWidth,51)
  serverTab.Size=UDim2.fromOffset(tabWidth,28)
  local width=w-24
  local sendWidth=68
  chat.messageWidth=width
  notice.Position=UDim2.fromOffset(12,86)
  notice.Size=UDim2.fromOffset(width,24)
  note.TextSize=w<390 and 10 or 11
  list.Position=UDim2.fromOffset(12,116)
  list.Size=UDim2.fromOffset(width,101)
  input.Position=UDim2.fromOffset(12,224)
  input.Size=UDim2.fromOffset(width-sendWidth-8,34)
  sendButton.Position=UDim2.fromOffset(w-12-sendWidth,224)
  sendButton.Size=UDim2.fromOffset(sendWidth,34)
  chat.join.Position=UDim2.fromOffset(24,144)
  chat.join.Size=UDim2.fromOffset(width-24,33)
  chat.delivery.Position=UDim2.fromOffset(12,260)
  chat.delivery.Size=UDim2.fromOffset(width,15)
  for _,entry in chat.rows do layoutRow(entry) end
 end
 chat.fit=fit
 fit() on(workspace:GetPropertyChangedSignal("CurrentCamera"),fit)
 task.spawn(function()
  while alive do if panel.Visible then pcall(Brain.chatPoll) end pcall(Brain.chatNearby) task.wait(4) end
 end)
 Brain.chatSelect("global")
end
Brain.createChatUI()
local login=new("Frame",{Position=UDim2.fromOffset(20,18),Size=UDim2.fromOffset(330,285),BackgroundColor3=Color3.fromRGB(10,12,15),BackgroundTransparency=.12},content)
round(login,18)
new("UIStroke",{Color=white,Transparency=.82,Thickness=1},login)
text(login,"BLY | Victory",16,16,298,32,21)
text(login,"التفعيل بموافقة الإدارة • @"..player.Name,16,58,298,28,15)
local activationLabel=text(login,"بانتظار إرسال طلب التفعيل",18,100,294,58,16)
activationLabel.TextWrapped=true
local dashboard=new("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false},content)
local pages={}
for _,name in {"survival","settings","diagnostics","quests","growth","war","looks"} do pages[name]=new("Frame",{Position=UDim2.fromOffset(20,58),Size=UDim2.fromOffset(660,315),BackgroundTransparency=1,Visible=name=="survival"},dashboard) end
local tabButtons={}
local function selectTab(name)
	for keyName,page in pages do page.Visible=keyName==name end
	for keyName,b in tabButtons do Brain.selectButton(b,keyName==name) end
end
tabButtons.survival=button(dashboard,"البقاء",20,4,87,function() selectTab("survival") end)
tabButtons.settings=button(dashboard,"الإعدادات",115,4,87,function() selectTab("settings") end)
tabButtons.diagnostics=button(dashboard,"الفحص",210,4,87,function() selectTab("diagnostics") end)
tabButtons.quests=button(dashboard,"المهام",305,4,87,function() selectTab("quests") end)
tabButtons.growth=button(dashboard,"تكبير الحيوانات",400,4,102,function() selectTab("growth") end)
tabButtons.war=button(dashboard,"WAR",510,4,62,function() selectTab("war") end)
tabButtons.looks=button(dashboard,"شكل",580,4,100,function()
 selectTab("looks")
 if Brain.refreshAppearanceRoster then Brain.refreshAppearanceRoster() end
end)
function Brain.tabIcon(b,kind)
 local icon=new("Frame",{Name="BLY_TabIcon",Position=UDim2.new(1,-24,.5,-7),Size=UDim2.fromOffset(14,14),BackgroundTransparency=1,Active=false,ZIndex=b.ZIndex+3},b)
 local function part(x,y,w,h,rotation)
  return new("Frame",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=Color3.fromRGB(215,221,225),BorderSizePixel=0,Rotation=rotation or 0,Active=false,ZIndex=icon.ZIndex},icon)
 end
 local function ring(x,y,size)
  local o=part(x,y,size,size) o.BackgroundTransparency=1 round(o,20)
  new("UIStroke",{Color=Color3.fromRGB(215,221,225),Thickness=1.4,Transparency=.1},o) return o
 end
 if kind=="survival" then local leaf=part(4,1,7,11,36) round(leaf,8) part(2,9,1,6,36)
 elseif kind=="settings" then
  ring(3,3,8) ring(6,6,2)
  for _,v in {{6,0,2,3},{6,11,2,3},{0,6,3,2},{11,6,3,2}} do part(v[1],v[2],v[3],v[4]) end
 elseif kind=="diagnostics" then ring(1,1,8) part(9,8,2,6,-43)
 elseif kind=="quests" then part(2,1,1,13) part(4,2,9,6)
 elseif kind=="growth" then
  for _,v in {{4,7,7,6},{1,3,3,4},{5,0,3,4},{10,3,3,4}} do local o=part(v[1],v[2],v[3],v[4]) round(o,8) end
 elseif kind=="looks" then
  local diamond=part(3,3,8,8,45) diamond.BackgroundTransparency=1 round(diamond,2)
  new("UIStroke",{Color=white,Thickness=1.25,Transparency=.1},diamond)
  local shine=part(6,6,2,2,45) round(shine,1)
 elseif kind=="about" then
  ring(1,1,12) round(part(6,4,2,2),1) round(part(6,7,2,4),1)
 elseif kind=="chat" then
  local bubble=part(1,2,12,9) bubble.BackgroundTransparency=1 round(bubble,3)
  new("UIStroke",{Color=white,Thickness=1.2,Transparency=.12},bubble)
  part(3,10,2,4,40)
  for x=4,10,3 do round(part(x,6,1,1),1) end
 else part(6,0,2,15,43) part(6,0,2,15,-43) part(0,10,5,1,43) part(9,10,5,1,-43) end
 local skin=Brain.buttonSkins[b]
 if skin then skin.caption.Size=UDim2.new(1,-21,1,0) end
end
for name,b in tabButtons do
 b.Size=UDim2.fromOffset(b.Size.X.Offset,32)
 b.TextSize=name=="quests" and 11 or 14
 Brain.tabIcon(b,name)
end
Brain.tabIcon(aboutButton,"about")
Brain.tabIcon(chatButton,"chat")
selectTab("survival")
function Brain.createSilverLion()
 local enabled=false
 local activeLook
 local geometryConnection
 local geometryMeshes={}
 local boundModel,boundRoot
 local effects={}
 local furImages={}
 local restoreFur={}
 local furEpoch=0
 local ice=Color3.fromRGB(181,212,246)
 local function clearAppearance()
  furEpoch+=1
  if geometryConnection then
   geometryConnection:Disconnect()
   geometryConnection=nil
  end
  boundModel,boundRoot=nil,nil
  for i=#restoreFur,1,-1 do pcall(restoreFur[i]) end
  table.clear(restoreFur)
  for _,image in furImages do image:Destroy() end
  table.clear(furImages)
  for _,object in effects do object:Destroy() end
  table.clear(effects)
  for _,mesh in geometryMeshes do mesh:Destroy() end
  table.clear(geometryMeshes)
 end
 local function attachment(root,frame)
  local node=new("Attachment",{Name="BLY_SilverLion",CFrame=frame},root)
  table.insert(effects,node)
  return node
 end
 local page=pages.looks
 local selectedKey,selectedName
 local skinButton,checkButton,galaxyButton,royalButton,pinkButton
 local rosterButtons={}
 local appearanceInfo={
  spino={title="سباينو الشبح",detail="جلد فحمي وتفاصيل فضية · عيون بيضاء مشعّة"},
  skydragon={title="تنين الرماد",detail="حراشف فحمية وأجنحة نحاسية · اضغط E مطولًا لنفث النار"},
  lion={title="الأسد الأحمر",detail="الأسد الأحمر أو أسد الذهب الملكي أو أسد المجرة"},
  elephant={title="فيل روح السراب",detail="جلد ليلي بخطوط تركواز مضيئة وعروق سماوية على الأذنين"},
  rhinoceros={title="حارس الكريستال الشفقي",detail="جلد بنفسجي ليلي وعروق فوشية وسماوية وقرن بلوري متوهج"},
  leopard={title="فهد العقيق الأخضر",detail="فرو فحمي ووردات زمردية وخيوط خضراء مضيئة"},
  crocodile={title="تمساح الحمم",detail="حراشف فحمية وشقوق حمم · عين كهرمانية · جناحان وقرون"},
 }
 local function panel(x,width)
  local box=new("Frame",{
   Position=UDim2.fromOffset(x,0),Size=UDim2.fromOffset(width,311),
   BackgroundColor3=Color3.fromRGB(4,24,31),BackgroundTransparency=.27,BorderSizePixel=0,
  },page)
  round(box,14)
  new("UIStroke",{Color=Color3.fromRGB(100,224,238),Transparency=.34,Thickness=1.25},box)
  return box
 end
 local left=panel(2,232)
 local right=panel(245,413)
 Brain.looksArtPanels={left,right}
 text(left,"حيواناتي",10,9,218,25,17).TextColor3=ice
 local list=new("ScrollingFrame",{
  Position=UDim2.fromOffset(10,42),Size=UDim2.fromOffset(218,215),
  BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),
  AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=ice,
 },left)
 new("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)},list)
 local heading=text(right,"اختر حيوانًا",14,12,382,31,20)
 heading.TextColor3=white
 heading.Font=Enum.Font.Bodoni
 heading.TextSize=24
 local details=text(right,"تظهر المظاهر المتوفرة للحيوان هنا",14,59,382,52,15)
 round(details,10)
 local feedback=text(right,"المظاهر تظهر عندك داخل اللعبة",14,227,382,68,12)
 feedback.TextColor3=Color3.fromRGB(174,205,225)
 local function currentAnimal(expectedKey)
  local model,root,humanoid=rig()
  if not model or (humanoid and humanoid.Health<=0) then return end
  root=root or model.PrimaryPart
  if not root or not root:IsA("BasePart") then return end
  local key=Brain.appearanceAnimal(model)
  if key==((expectedKey=="galaxy" or expectedKey=="royal") and "lion" or expectedKey=="pinkelephant" and "elephant" or expectedKey) then return model,root end
 end
 local function renderGallery()
  heading.Text=selectedName or "اختر حيوانًا"
  local info=appearanceInfo[selectedKey]
  details.Text=info and info.detail or (selectedKey and "ما فيه مظاهر لهذا الحيوان حاليًا" or "تظهر المظاهر المتوفرة للحيوان هنا")
  details.Position=UDim2.fromOffset(24,info and 61 or 203)
  details.Size=UDim2.fromOffset(362,info and 52 or 35)
  details.BackgroundTransparency=info and 1 or .30
  details.BackgroundColor3=Color3.fromRGB(5,32,40)
  skinButton.Visible=info~=nil
  checkButton.Visible=info~=nil
  local lionSelected=selectedKey=="lion"
  local elephantSelected=selectedKey=="elephant"
  galaxyButton.Visible=lionSelected
  royalButton.Visible=lionSelected
  pinkButton.Visible=elephantSelected
  if lionSelected then
   details.Size=UDim2.fromOffset(362,38)
   skinButton.Position=UDim2.fromOffset(19,111)
   skinButton.Size=UDim2.fromOffset(372,32)
   galaxyButton.Position=UDim2.fromOffset(19,151)
   galaxyButton.Size=UDim2.fromOffset(178,30)
   royalButton.Position=UDim2.fromOffset(207,151)
   royalButton.Size=UDim2.fromOffset(180,30)
   checkButton.Position=UDim2.fromOffset(19,189)
   checkButton.Size=UDim2.fromOffset(372,30)
   feedback.Position=UDim2.fromOffset(14,226)
   feedback.Size=UDim2.fromOffset(382,68)
   skinButton.Text="تطبيق الأسد الأحمر"
   Brain.selectButton(skinButton,enabled and activeLook=="lion")
  end
  if not lionSelected then
   skinButton.Position=UDim2.fromOffset(19,140)
   skinButton.Size=UDim2.fromOffset(372,38)
   checkButton.Position=UDim2.fromOffset(19,189)
   checkButton.Size=UDim2.fromOffset(372,30)
   feedback.Position=UDim2.fromOffset(14,227)
   feedback.Size=UDim2.fromOffset(382,68)
  end
  if elephantSelected then
   skinButton.Position=UDim2.fromOffset(19,119)
   skinButton.Size=UDim2.fromOffset(178,32)
   pinkButton.Position=UDim2.fromOffset(207,119)
   pinkButton.Size=UDim2.fromOffset(180,32)
   checkButton.Position=UDim2.fromOffset(19,158)
   checkButton.Size=UDim2.fromOffset(368,30)
   feedback.Position=UDim2.fromOffset(14,197)
   feedback.Size=UDim2.fromOffset(382,95)
   skinButton.Text=enabled and activeLook=="elephant" and "إزالة روح السراب" or "فيل روح السراب"
   Brain.selectButton(skinButton,enabled and activeLook=="elephant")
   pinkButton.Text=enabled and activeLook=="pinkelephant" and "إزالة الفيل الوردي" or "الفيل الوردي"
   Brain.selectButton(pinkButton,enabled and activeLook=="pinkelephant")
  end
  if lionSelected then
   local activeGalaxy=enabled and activeLook=="galaxy"
   galaxyButton.Text=activeGalaxy and "إزالة أسد المجرة" or "تطبيق أسد المجرة"
   Brain.selectButton(galaxyButton,activeGalaxy)
   local activeRoyal=enabled and activeLook=="royal"
   royalButton.Text=activeRoyal and "إزالة أسد الذهب" or "أسد الذهب الملكي"
   Brain.selectButton(royalButton,activeRoyal)
  end
  if info and not elephantSelected then
   local selectedActive=enabled and activeLook==selectedKey
   skinButton.Text=selectedActive and "إزالة "..info.title or "تطبيق "..info.title
   Brain.selectButton(skinButton,selectedActive)
  end
 end
 local applyFur
 function Brain.refreshSilverLion()
  if not enabled then return end
  local model,root
  if unlocked then model,root=currentAnimal(activeLook) end
  if model==boundModel and root==boundRoot then return end
  clearAppearance()
  if model then
   local ok,problem=pcall(function()
    boundModel,boundRoot=model,root
   end)
   if not ok then
    clearAppearance()
    enabled=false
    feedback.Text="تعذر عرض المظهر: "..tostring(problem)
    renderGallery()
   else
    feedback.Text=activeLook=="spino" and "أجهّز سباينو الشبح…" or activeLook=="galaxy" and "أجهّز أسد المجرة…" or activeLook=="royal" and "أجهّز قناع الذهب الملكي…" or activeLook=="skydragon" and "أجهّز مجسّم تنين الرماد…" or activeLook=="elephant" and "أجهّز فيل روح السراب…" or activeLook=="pinkelephant" and "أجهّز الفيل الوردي…" or activeLook=="rhinoceros" and "أجهّز حارس الكريستال الشفقي…" or activeLook=="leopard" and "أجهّز فهد العقيق الأخضر…" or activeLook=="lion" and "أجهّز فرو الأسد الأحمر وجناحيه…" or "أجهّز حراشف الحمم ومؤثراتها…"
    task.spawn(applyFur,model,furEpoch,activeLook)
   end
  end
 end
 function Brain.clearSilverLion()
  enabled=false
  activeLook=nil
  clearAppearance()
 end
 local function chooseAppearance(look)
  if enabled and activeLook==look then
   Brain.clearSilverLion()
   feedback.Text="رجع المظهر الأصلي"
   renderGallery()
   return
  end
  if not unlocked or not appearanceInfo[selectedKey] or not currentAnimal(look) then
   feedback.Text="العب بالحيوان المختار أولًا، ثم اضغط تطبيق المظهر"
   return
  end
  Brain.clearSilverLion()
  enabled=true
  activeLook=look
  Brain.refreshSilverLion()
  renderGallery()
 end
 skinButton=button(right,"تطبيق الأسد الأحمر",19,140,372,function() chooseAppearance(selectedKey) end)
 pinkButton=button(right,"الفيل الوردي",207,189,180,function() chooseAppearance("pinkelephant") end)
 pinkButton.Size=UDim2.fromOffset(180,32)
 pinkButton.Visible=false
 galaxyButton=button(right,"تطبيق أسد المجرة",19,189,232,function() chooseAppearance("galaxy") end)
 galaxyButton.Size=UDim2.fromOffset(178,30)
 galaxyButton.Visible=false
 royalButton=button(right,"أسد الذهب الملكي",207,189,180,function() chooseAppearance("royal") end)
 royalButton.Size=UDim2.fromOffset(180,30)
 royalButton.Visible=false
 skinButton.Size=UDim2.fromOffset(372,38)
 skinButton.Visible=false
 local function imageContent(object,property,legacyProperty)
  local ok,content=pcall(function()
   local value=object[property]
   if value.SourceType~=Enum.ContentSourceType.None then return value end
  end)
  if ok and content then return content end
  if not legacyProperty then return end
  local uriOk,uri=pcall(function() return object[legacyProperty] end)
  if uriOk and typeof(uri)=="string" and uri~="" then return Content.fromUri(uri) end
 end
 local function readTexture(mesh,appearance)
  if appearance then return imageContent(appearance,"ColorMapContent","ColorMap") end
  return imageContent(mesh,"TextureContent","TextureID")
 end
 local function editableSurfaceMap(assets,content,isCurrent,cache)
  if not content or not isCurrent() then return end
  local ok,object=pcall(function() return content.Object end)
  if ok and typeof(object)=="Instance" and object:IsA("EditableImage") then return content end
  local uriOk,uri=pcall(function() return content.Uri end)
  local cacheKey=uriOk and typeof(uri)=="string" and uri~="" and uri or nil
  if cacheKey and cache[cacheKey]~=nil then return cache[cacheKey] or nil end
  local loaded,image=pcall(function() return assets:CreateEditableImageAsync(content) end)
  if not loaded or not image then
   if cacheKey then cache[cacheKey]=false end
   return
  end
  if not isCurrent() then image:Destroy() return end
  table.insert(furImages,image)
  local editable=Content.fromObject(image)
  if cacheKey then cache[cacheKey]=editable end
  return editable
 end
 local function installFur(mesh,appearance,image,assets,isCurrent,glow,isEye,mapCache,emissiveTint,muteEmission)
  local color=Content.fromObject(image)
  if appearance or glow then
   local maps={ColorMap=color,EmissiveMask=glow and Content.fromObject(glow)}
   if appearance then
    mapCache=mapCache or {}
    maps.NormalMap=editableSurfaceMap(assets,imageContent(appearance,"NormalMapContent","NormalMap"),isCurrent,mapCache)
    maps.RoughnessMap=editableSurfaceMap(assets,imageContent(appearance,"RoughnessMapContent","RoughnessMap"),isCurrent,mapCache)
    maps.MetalnessMap=editableSurfaceMap(assets,imageContent(appearance,"MetalnessMapContent","MetalnessMap"),isCurrent,mapCache)
    if not glow and not muteEmission then
     maps.EmissiveMask=editableSurfaceMap(assets,imageContent(appearance,"EmissiveMaskContent"),isCurrent,mapCache)
    end
   end
   if not isCurrent() then return false end
   local created,replacement=pcall(function() return assets:CreateSurfaceAppearanceAsync(maps) end)
   if glow and (not created or not replacement) and isCurrent() then
    glow=nil
    maps.EmissiveMask=nil
    created,replacement=pcall(function() return assets:CreateSurfaceAppearanceAsync(maps) end)
   end
   if not created then error(replacement) end
   if not replacement then return false end
   if not isCurrent() or mesh:FindFirstChildOfClass("SurfaceAppearance")~=appearance then
    replacement:Destroy()
    return false
   end
   local ok,problem=pcall(function()
    if appearance then
     replacement.AlphaMode=appearance.AlphaMode
     replacement.ResampleMode=appearance.ResampleMode
     replacement.EmissiveStrength=muteEmission and 0 or appearance.EmissiveStrength
     replacement.EmissiveTint=appearance.EmissiveTint
     replacement.Name=appearance.Name
    else
     replacement.AlphaMode=Enum.AlphaMode.Transparency
    end
    if glow then
     replacement.EmissiveStrength=isEye and 1.6 or 1.8
     replacement.EmissiveTint=emissiveTint or (isEye and Color3.fromRGB(255,182,65) or Color3.fromRGB(255,77,22))
    end
    if appearance then appearance.Parent=nil end
    replacement.Parent=mesh
   end)
   if not ok then
    replacement:Destroy()
    if appearance and appearance.Parent==nil then appearance.Parent=mesh end
    error(problem)
   end
   table.insert(restoreFur,function()
    replacement:Destroy()
    if appearance and appearance.Parent==nil and mesh.Parent then appearance.Parent=mesh end
   end)
  else
   if not isCurrent() or mesh:FindFirstChildOfClass("SurfaceAppearance") then return false end
   local original=mesh.TextureContent
   mesh.TextureContent=color
   table.insert(restoreFur,function()
    if mesh.TextureContent==color then mesh.TextureContent=original end
   end)
  end
  local originalColor=mesh.Color
  local neutral=Color3.new(1,1,1)
  mesh.Color=neutral
  table.insert(restoreFur,function()
   if mesh.Color==neutral then mesh.Color=originalColor end
  end)
  return true
 end
 local function texturePriority(mesh)
  local name=mesh.Name:lower()
  if name:find("horn",1,true) then return 0 end
  if name:find("mane",1,true) then return 0 end
  if name:find("head",1,true) then return 1 end
  if name:find("body",1,true) or name:find("torso",1,true) then return 2 end
  return 3
 end
 local function lavaPixels(pixels,width,firstRow,height,isEye,glowPixels)
  for offset=0,buffer.len(pixels)-4,4 do
   local alpha=buffer.readu8(pixels,offset+3)
   if alpha>0 then
    local luma=.2126*buffer.readu8(pixels,offset)+.7152*buffer.readu8(pixels,offset+1)+.0722*buffer.readu8(pixels,offset+2)
    local red,green,blue,glow
    if isEye then
     local iris=math.clamp((luma-30)/105,0,1)
     red,green,blue,glow=8+247*iris,5+144*iris,4+34*iris,145*iris
    else
     local pixel=offset/4
     local u=(pixel%width)/width
     local v=(firstRow+math.floor(pixel/width))/height
     local vein=math.noise(u*10,v*10,.37)+.32*math.noise(u*33,v*35,1.14)
     local cluster=math.clamp((math.noise(u*4,v*4,8)+.14)*3.3,0,1)
     local hot=math.clamp(1-math.abs(vein-.04)*37,0,1)*cluster
     local belly=math.clamp((luma-140)/106,0,1)
     hot*=1-.72*belly
     local baseRed=18+.25*luma+40*belly
     local baseGreen=9+.13*luma+36*belly
     local baseBlue=10+.10*luma+27*belly
     red=baseRed+(255-baseRed)*hot
     green=baseGreen+(149-baseGreen)*hot*hot
     blue=baseBlue+(40-baseBlue)*hot*hot
     glow=255*hot*hot
    end
    buffer.writeu8(pixels,offset,math.floor(red+.5))
    buffer.writeu8(pixels,offset+1,math.floor(green+.5))
    buffer.writeu8(pixels,offset+2,math.floor(blue+.5))
    if glowPixels then
     local intensity=math.floor(glow+.5)
     buffer.writeu8(glowPixels,offset,intensity)
     buffer.writeu8(glowPixels,offset+1,intensity)
     buffer.writeu8(glowPixels,offset+2,intensity)
    end
   end
   if glowPixels then buffer.writeu8(glowPixels,offset+3,255) end
  end
 end
 local function findAnimalHead(model)
  local head=model:FindFirstChild("Head",true)
  if head and head:IsA("BasePart") then return head end
  for _,item in model:GetDescendants() do
   if item:IsA("MeshPart") and item.Transparency<.95 and item.Name:lower():find("head",1,true) then
    return item
   end
  end
 end
 local function createDecorationBuilder(model,assets,isCurrent)
  local decorations={}
  geometryConnection=Run.RenderStepped:Connect(function()
   for _,item in decorations do
    if item.anchor.Parent then
     local frame=item.frame and item.frame(item.anchor) or item.anchor.CFrame
     item.part.CFrame=frame*CFrame.new(item.center)
    end
   end
  end)
  local function buildDecoration(anchor,vertices,faces,name,frameFor,material)
   if not isCurrent() or not anchor:IsDescendantOf(model) then return false end
   local editable=assets:CreateEditableMesh()
   if not editable then return false end
   table.insert(geometryMeshes,editable)
   local low,high=vertices[1][1],vertices[1][1]
   for _,vertex in vertices do
    local p=vertex[1]
    low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
    high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
   end
   local center=(low+high)*.5
   local ids,colors={},{}
   for index,vertex in vertices do
    ids[index]=editable:AddVertex(vertex[1]-center)
    colors[index]=editable:AddColor(vertex[2],1)
   end
   for _,face in faces do
    local a,b,c=face[1],face[2],face[3]
    local id=editable:AddTriangle(ids[a],ids[b],ids[c])
    editable:SetFaceColors(id,{colors[a],colors[b],colors[c]})
   end
   local part=assets:CreateMeshPartAsync(Content.fromObject(editable))
   if not part then return false end
   if not isCurrent() then part:Destroy() return false end
   part.Name=name
   part.Anchored=true
   part.CanCollide=false
   part.CanTouch=false
   part.CanQuery=false
   part.CastShadow=false
   part.Color=Color3.new(1,1,1)
   part.Material=material or Enum.Material.SmoothPlastic
   local frame=frameFor and frameFor(anchor) or anchor.CFrame
   part.CFrame=frame*CFrame.new(center)
   table.insert(effects,part)
   table.insert(decorations,{part=part,anchor=anchor,center=center,frame=frameFor})
   part.Parent=workspace
   return part,center
  end
  return buildDecoration
 end
 local function addRib(vertices,faces,points,radii,color)
   local start=#vertices
   local ringSize=10
   for i,point in points do
    local previous=points[math.max(1,i-1)]
    local nextPoint=points[math.min(#points,i+1)]
    local tangent=(nextPoint-previous).Unit
    local reference=math.abs(tangent:Dot(Vector3.yAxis))>.93 and Vector3.xAxis or Vector3.yAxis
    local side=tangent:Cross(reference).Unit
    local up=tangent:Cross(side).Unit
    for j=0,ringSize-1 do
     local angle=2*math.pi*j/ringSize
     local radius=radii[i]
     table.insert(vertices,{point+(side*math.cos(angle)+up*math.sin(angle))*radius,color})
    end
   end
   for i=0,#points-2 do
    for j=0,ringSize-1 do
     local a=start+i*ringSize+j+1
     local b=start+i*ringSize+(j+1)%ringSize+1
     table.insert(faces,{a,b,b+ringSize})
     table.insert(faces,{a,b+ringSize,a+ringSize})
    end
   end
  end
 local function makeDragonMeshes(model,root,assets,isCurrent)
  local box,bounds=model:GetBoundingBox()
  local unit=math.clamp(math.min(bounds.X,bounds.Z)*.25,.7,3.5)
  local ember=Color3.fromRGB(103,38,32)
  local soot=Color3.fromRGB(38,28,27)
  local gold=Color3.fromRGB(160,62,37)
  local rim=Color3.fromRGB(65,29,26)
  local buildDecoration=createDecorationBuilder(model,assets,isCurrent)
  local head=findAnimalHead(model)
  local forward=root.CFrame.LookVector
  if head then
   local offset=head.Position-root.Position
   if Vector3.new(offset.X,0,offset.Z).Magnitude>.4 then forward=offset end
  end
  forward=Vector3.new(forward.X,0,forward.Z)
  forward=forward.Magnitude>.01 and forward.Unit or Vector3.new(0,0,-1)
  local localForward=root.CFrame:VectorToObjectSpace(forward)
  localForward=Vector3.new(localForward.X,0,localForward.Z)
  localForward=localForward.Magnitude>.01 and localForward.Unit or -Vector3.zAxis
  local lateral=localForward:Cross(Vector3.yAxis).Unit
  local wingCount=0
  local hide=Color3.fromRGB(43,26,24)
  local ridge=Color3.fromRGB(69,43,36)
  local crease=Color3.fromRGB(24,17,19)
  local lavaEdge=Color3.fromRGB(225,65,13)
  local lavaCore=Color3.fromRGB(255,140,39)
  for _,side in {-1,1} do
   local wingVertices,wingFaces={},{}
   local fissures,fissureFaces={},{}
   local function addCrack(points,width)
    local outer,core={},{}
    for index,p in points do
     local t=(index-1)/(#points-1)
     local radius=math.max(.09,math.sin(math.pi*t)^.75)*(1-.28*t)*width*unit
     outer[index]=radius
     core[index]=radius*.40
    end
    addRib(fissures,fissureFaces,points,outer,lavaEdge)
    for i,p in points do points[i]=p+Vector3.yAxis*(outer[i]*.88) end
    addRib(fissures,fissureFaces,points,core,lavaCore)
   end
   local function point(x,y,z)
    return (lateral*(side*x)+Vector3.yAxis*y+localForward*(1.24-z))*unit
     +Vector3.yAxis*(root.Size.Y*.38)
   end
   local shoulder=point(.36,-.12,.01)
   local elbow=point(.92,.51,.14)
   local wrist=point(1.61,.92,.29)
   local tip=point(3.60,.22,1.85)
   local fingers={tip,point(2.86,.05,2.25),point(2.04,-.05,2.24),point(1.25,-.10,1.85),point(.64,-.03,1.18),shoulder}
   local scallops={point(3.01,.30,1.57),point(2.44,.22,1.71),point(1.65,.12,1.65),point(.94,.05,1.28),point(.61,.04,.57)}
   local function ribPoint(edge,t)
    return wrist:Lerp(edge,t)+Vector3.yAxis*(math.sin(math.pi*t)*.18*unit)
   end
   for index,notch in scallops do
    local a,b=fingers[index],fingers[index+1]
    local function edgePoint(u)
     return a:Lerp(b,u):Lerp(notch,math.sin(math.pi*u)*.84)
    end
    local function surface(t,u)
     local slack=math.sin(math.pi*u)
     local bend=math.sin(math.pi*t)
     local folds=(math.cos(u*6*math.pi+t*5)*.018-.15)*slack*bend
     return ribPoint(edgePoint(u),t)+Vector3.yAxis*(folds*unit)
    end
    local first=#wingVertices
    local steps,rows=10,9
    table.insert(wingVertices,{wrist,crease})
    for row=1,rows do
     local t=row/rows
     for column=0,steps do
      local u=column/steps
      local grain=.5+.5*math.sin(row*2.1+column*4.7+index*6.4)
      local warmth=math.sin(math.pi*u)*math.sin(math.pi*t)
      local color=crease:Lerp(hide,.48+.34*warmth):Lerp(ridge,warmth*(.08+.18*grain))
      table.insert(wingVertices,{surface(t,u),color})
     end
    end
    local function panelFace(aIndex,bIndex,cIndex)
     table.insert(wingFaces,{aIndex,bIndex,cIndex})
     table.insert(wingFaces,{aIndex,cIndex,bIndex})
    end
    for column=1,steps do
     panelFace(first+1,first+1+column,first+2+column)
    end
    for row=1,rows-1 do
     for column=1,steps do
      local aIndex=first+1+(row-1)*(steps+1)+column
      local bIndex=aIndex+steps+1
      panelFace(aIndex,bIndex,bIndex+1)
      panelFace(aIndex,bIndex+1,aIndex+1)
     end
    end
    local hem={}
    for i=0,8 do table.insert(hem,edgePoint(i/8)) end
    addRib(wingVertices,wingFaces,hem,
     {.008*unit,.013*unit,.014*unit,.017*unit,.018*unit,.017*unit,.014*unit,.013*unit,.008*unit},hide)
    for row=1,5 do
     local t=.22+row*.106
     for column=1,4 do
      local u=.14+column*.14+(row%2)*.063
      local seed=row*3.2+column*5.6+index*1.9
      local dt=.020+math.sin(seed)*.006
      local du=.044+math.cos(seed)*.013
      local offset=Vector3.yAxis*(.012*unit)
      local firstScale=#wingVertices
      table.insert(wingVertices,{surface(t-dt,u)+offset,crease})
      table.insert(wingVertices,{surface(t,u-du)+offset,hide})
      table.insert(wingVertices,{surface(t+dt,u)+offset,crease})
      table.insert(wingVertices,{surface(t,u+du)+offset,hide})
      table.insert(wingVertices,{surface(t,u)+offset*1.7,hide:Lerp(ridge,.20+.23*math.cos(seed)^2)})
      for j=1,4 do panelFace(firstScale+j,firstScale+j%4+1,firstScale+5) end
     end
    end
    local crack={}
    for i=0,10 do
     local t=.24+i*.060
     local u=.48+math.sin(i*1.08+index*1.7)*.095+math.sin(i*2.49)*.052
     table.insert(crack,surface(t,u)+Vector3.yAxis*(.023*unit))
    end
    addCrack(crack,index%2==0 and .014 or .010)
    local branch={}
    for i=0,4 do
     local t=.54+i*.037
     local u=.48+math.sin(5*1.08+index*1.7)*.095+math.sin(5*2.49)*.052+i*.057
     table.insert(branch,surface(t,u)+Vector3.yAxis*(.022*unit))
    end
    addCrack(branch,.007)
   end
   local arm={shoulder,point(.58,.14,.06),elbow,point(1.22,.75,.19),wrist}
   addRib(wingVertices,wingFaces,arm,{.16*unit,.143*unit,.109*unit,.087*unit,.066*unit},hide)
   local armCrack={}
   for index=1,#arm-1 do
    for step=0,2 do
     local t=step/3
     local shift=math.sin(index*3+step*2.3)*.039*unit
     local heights={.155,.136,.104,.081,.065}
     local height=(heights[index]*(1-t)+heights[index+1]*t+.008)*unit
     table.insert(armCrack,arm[index]:Lerp(arm[index+1],t)+lateral*shift+Vector3.yAxis*height)
    end
   end
   table.insert(armCrack,wrist+Vector3.yAxis*(.073*unit))
   addCrack(armCrack,.015)
   for index,edge in fingers do
    local rib={}
    local width=index==1 and 1.28 or 1
    for i=0,7 do table.insert(rib,ribPoint(edge,i/7)) end
    addRib(wingVertices,wingFaces,rib,
     {.052*unit*width,.047*unit*width,.038*unit*width,.031*unit,.024*unit,.019*unit,.012*unit,.004*unit},hide)
   end
   addRib(wingVertices,wingFaces,{wrist,point(1.71,.99,.25),point(1.82,1.00,.14),point(1.89,.95,.07)},
    {.057*unit,.042*unit,.020*unit,.003*unit},ridge)
   local function wingFrame(part)
    local t=os.clock()*1.72
    local roll=side*(.14*math.sin(t)+.021*math.sin(t*2+.40))
    local sweep=side*.045*math.sin(t+.30)
    return part.CFrame*CFrame.new(shoulder)*CFrame.fromAxisAngle(localForward,roll)
     *CFrame.fromAxisAngle(Vector3.yAxis,sweep)*CFrame.new(-shoulder)
   end
   local wing,center=buildDecoration(root,wingVertices,wingFaces,"BLY_LavaWing",wingFrame)
   if wing and isCurrent() then
    wingCount+=1
    local origin=attachment(wing,CFrame.new(point(2.52,.29,1.54)-center))
    new("ParticleEmitter",{
     Texture="rbxasset://textures/particles/sparkles_main.dds",
     Color=ColorSequence.new(Color3.fromRGB(255,200,92),Color3.fromRGB(239,67,19)),
     Rate=5,LightEmission=1,LightInfluence=0,Lifetime=NumberRange.new(.35,.64),
     Speed=NumberRange.new(.55,1.65),SpreadAngle=Vector2.new(38,38),Acceleration=Vector3.yAxis*1.2,
     Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.022*unit),
      NumberSequenceKeypoint.new(.23,.065*unit),NumberSequenceKeypoint.new(1,0)}),
     Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),
      NumberSequenceKeypoint.new(.20,.09),NumberSequenceKeypoint.new(1,1)}),
    },origin)
    local glow=buildDecoration(root,fissures,fissureFaces,"BLY_LavaWingFissures",wingFrame,Enum.Material.Neon)
    if glow and isCurrent() then
     glow.Transparency=.12
     local pulse=TweenService:Create(glow,TweenInfo.new(1.05,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Transparency=.43})
     pulse:Play()
     table.insert(restoreFur,function() pulse:Cancel() end)
    end
   end
   if not isCurrent() then return false,false,false end
  end
  local wings=wingCount==2
  local horns=false
  if head and head:IsA("BasePart") and isCurrent() then
   local vertices,faces={},{}
   local hornUnit=math.clamp(head.Size.X*.39,.35,unit)
   for _,side in {-1,1} do
    local x=side*head.Size.X*.29
    local y=head.Size.Y*.36
    addRib(vertices,faces,{
     Vector3.new(x,y,-hornUnit*.32),
     Vector3.new(x+side*hornUnit*.08,y+hornUnit*.30,-hornUnit*.17),
     Vector3.new(x+side*hornUnit*.16,y+hornUnit*.49,hornUnit*.13),
     Vector3.new(x+side*hornUnit*.23,y+hornUnit*.60,hornUnit*.49),
     Vector3.new(x+side*hornUnit*.25,y+hornUnit*.64,hornUnit*.92),
     Vector3.new(x+side*hornUnit*.18,y+hornUnit*.68,hornUnit*1.43),
    },{hornUnit*.25,hornUnit*.22,hornUnit*.17,hornUnit*.12,hornUnit*.065,hornUnit*.008},soot)
   end
   horns=buildDecoration(head,vertices,faces,"BLY_LavaHorns")
  end
  local function addScute(vertices,faces,base,direction,scale)
   local side=direction:Cross(Vector3.yAxis).Unit
   local first=#vertices
   table.insert(vertices,{base+direction*.38*scale,soot})
   table.insert(vertices,{base+side*.28*scale,rim})
   table.insert(vertices,{base-direction*.46*scale,soot})
   table.insert(vertices,{base-side*.28*scale,rim})
   table.insert(vertices,{base-direction*.09*scale+Vector3.new(0,.46*scale,0),gold})
   for i=1,4 do
    local a,b,c=first+i,first+i%4+1,first+5
    table.insert(faces,{a,b,c})
    table.insert(faces,{a,c,b})
   end
  end
  local rear=-forward
  local half=math.abs(rear:Dot(box.RightVector))*bounds.X/2+math.abs(rear:Dot(box.LookVector))*bounds.Z/2
  local reach=math.clamp((box.Position-root.Position):Dot(rear)+half,unit*2,80)
  local tailNodes={}
  for _,item in model:GetDescendants() do
   if item.Name:lower():find("tail",1,true) and (item:IsA("Bone") or (item:IsA("BasePart") and item.Transparency<.95)) then
    local position=item:IsA("Bone") and item.TransformedWorldCFrame.Position or item.Position
    local distance=(position-root.Position):Dot(rear)
    if distance>unit*.7 then table.insert(tailNodes,{node=item,distance=distance}) end
   end
  end
  table.sort(tailNodes,function(a,b) return a.distance<b.distance end)
  local joints={}
  for _,item in tailNodes do
   if #joints>=9 then break end
   if #joints==0 or item.distance-joints[#joints].distance>unit*.42 then table.insert(joints,item) end
  end
  local filter=RaycastParams.new()
  filter.FilterType=Enum.RaycastFilterType.Include
  filter.FilterDescendantsInstances={model}
  local vertices,faces={},{}
  local traces,traceFaces={},{}
  local direction=root.CFrame:VectorToObjectSpace(forward)
  direction=Vector3.new(direction.X,0,direction.Z)
  direction=direction.Magnitude>.01 and direction.Unit or Vector3.new(0,0,-1)
  local edge=direction:Cross(Vector3.yAxis).Unit
  local span=#joints>=2 and math.min(reach,joints[1].distance) or reach
  for i=0,13 do
   local fraction=i/14
   local point=root.Position+rear*span*fraction
   local origin=Vector3.new(point.X,box.Position.Y+bounds.Y+3,point.Z)
   local hit=workspace:Raycast(origin,Vector3.new(0,-(bounds.Y*2+6),0),filter)
   if hit and hit.Instance.Transparency<.95 then
    local base=root.CFrame:PointToObjectSpace(hit.Position)
    local scale=unit*(.76-.47*fraction)
    addScute(vertices,faces,base,direction,scale)
    local first=#traces
    table.insert(traces,{base+direction*.25*scale+edge*.060*scale,gold})
    table.insert(traces,{base+direction*.25*scale-edge*.060*scale,gold})
    table.insert(traces,{base-direction*.09*scale+Vector3.new(0,.464*scale,0),gold})
    table.insert(traceFaces,{first+1,first+2,first+3})
    table.insert(traceFaces,{first+1,first+3,first+2})
   end
  end
  local dorsal
  if #vertices>0 and isCurrent() then
   dorsal=buildDecoration(root,vertices,faces,"BLY_LavaDorsalScutes")
   if isCurrent() then buildDecoration(root,traces,traceFaces,"BLY_LavaDorsalGlow",nil,Enum.Material.Neon) end
  end
  local tail=false
  if #joints>=2 and isCurrent() then
   local shape,triangles={},{}
   addScute(shape,triangles,Vector3.zero,Vector3.new(0,0,-1),unit*.58)
   local function tailFrame(node)
    local position=node:IsA("Bone") and node.TransformedWorldCFrame.Position or node.Position
    local height=node:IsA("Bone") and unit*.19 or node.Size.Y*.40
    local point=position+Vector3.new(0,height,0)
    return CFrame.lookAt(point,point+forward)
   end
   local template,center=buildDecoration(joints[1].node,shape,triangles,"BLY_LavaTailScute",tailFrame)
   if template then
    tail=true
    for i=2,#joints do
     local node=joints[i].node
     local scale=math.max(.26,1-(i-1)/#joints*.72)
     local scute=template:Clone()
     scute.Size=template.Size*scale
     scute.CFrame=tailFrame(node)*CFrame.new(center*scale)
     table.insert(effects,scute)
     table.insert(decorations,{part=scute,anchor=node,center=center*scale,frame=tailFrame})
     scute.Parent=workspace
    end
   end
  end
  return wings,horns,tail or not not dorsal
 end
 local function makeInfernoLion(model,root,assets,isCurrent)
  local box,bounds=model:GetBoundingBox()
  local unit=math.clamp(math.min(bounds.X,bounds.Z)*.34,.65,3.5)
  local head=findAnimalHead(model)
  local front=head and root.CFrame:PointToObjectSpace(head.Position) or -Vector3.zAxis
  front=Vector3.new(front.X,0,front.Z)
  front=front.Magnitude>.30 and front.Unit or -Vector3.zAxis
  local right=front:Cross(Vector3.yAxis).Unit
  local bodyBasis=CFrame.lookAt(Vector3.zero,front)
  local build=createDecorationBuilder(model,assets,isCurrent)
  local white=Color3.fromRGB(255,176,108)
  local cream=Color3.fromRGB(175,40,31)
  local gold=Color3.fromRGB(239,71,29)
  local bronze=Color3.fromRGB(103,43,33)
  local coal=Color3.fromRGB(26,12,16)
  local wine=Color3.fromRGB(74,17,25)
  local flame=Color3.fromRGB(255,53,21)
  local fireTip=Color3.fromRGB(255,146,43)
  local wingCount=0
  local surface=RaycastParams.new()
  surface.FilterType=Enum.RaycastFilterType.Include
  local visibleParts={}
  for _,part in model:GetDescendants() do
   if part:IsA("BasePart") and part.Transparency<.95 then table.insert(visibleParts,part) end
  end
  surface.FilterDescendantsInstances=visibleParts
  local function pose(node)
   return node:IsA("Bone") and node.TransformedWorldCFrame or node.CFrame
  end
  local function findPoseAnchor(target,kind,side)
   local best,bestScore=nil,math.huge
   for _,node in model:GetDescendants() do
    if not (node:IsA("Bone") or node:IsA("BasePart")) or node==root then continue end
    local name=node.Name:lower()
    local matches
    if kind=="shoulder" then
     matches=name:find("spine",1,true) or name:find("chest",1,true) or name:find("shoulder",1,true)
      or name:find("torso",1,true) or name:find("ribcage",1,true)
    else
     matches=name:find("foot",1,true) or name:find("paw",1,true) or name:find("ankle",1,true)
      or name:find("shin",1,true) or name:find("hind",1,true) or name:find("leg",1,true)
    end
    if not matches then continue end
    local position=pose(node).Position
    local localPosition=(root.CFrame*bodyBasis):PointToObjectSpace(position)
    if side and (localPosition.X*side<0 or localPosition.Z<0) then continue end
    local distance=(position-target).Magnitude
    local score=distance+(node:IsA("Bone") and 0 or .32*unit)
    if kind=="shoulder" and name:find("shoulder",1,true) then score+=.40*unit end
    if distance<unit*2 and score<bestScore then best,bestScore=node,score end
   end
   return best or root
  end
  local avatarFrame=root.CFrame*bodyBasis
  local function shoulderPivot(side)
   local fallback=Vector3.new(side*.29,root.Size.Y/unit*.19,-.46)*unit
   local from=avatarFrame:PointToWorldSpace(fallback+Vector3.yAxis*(bounds.Y+unit))
   local hit=workspace:Raycast(from,-avatarFrame.UpVector*(bounds.Y*2+2*unit),surface)
   if not hit then return fallback end
   local top=avatarFrame:PointToObjectSpace(hit.Position)
   return Vector3.new(fallback.X,top.Y-.36*unit,fallback.Z)
  end
  local function makeWing(side)
   local vertices,faces={},{}
   local pivot=shoulderPivot(side)
   local wingBind=root.CFrame*bodyBasis
   local anchor=findPoseAnchor(wingBind:PointToWorldSpace(pivot),"shoulder")
   local bind=pose(anchor):ToObjectSpace(wingBind)
   local function p(x,y,z) return pivot+Vector3.new(side*x*.93,y*.90,z)*unit end
   local function v(position,color)
    table.insert(vertices,{position,color})
    return #vertices
   end
   local function tri(a,b,c)
    table.insert(faces,{a,b,c})
    table.insert(faces,{a,c,b})
   end
   local shoulder=p(-.16,-.12,.05)
   local elbow=p(.80,.68,.17)
   local wrist=p(1.77,1.57,.23)
   local far=p(3.95,.87,1.54)
   local function stem(points,radii,color)
    for i,width in radii do radii[i]=width*unit end
    addRib(vertices,faces,points,radii,color)
   end
   local ends={far,p(3.35,.13,2.25),p(2.54,-.28,2.38),p(1.67,-.45,1.95),p(.71,-.36,1.31),shoulder}
   local dips={p(3.36,.57,1.67),p(2.85,.17,1.95),p(2.03,-.03,1.71),p(1.14,-.12,1.34),p(.52,.02,.57)}
   for panel,dip in dips do
    local function membrane(t,u)
     local bow=math.sin(math.pi*u)
     local edge=ends[panel]:Lerp(ends[panel+1],u):Lerp(dip,bow*.90)
     return wrist:Lerp(edge,t)+Vector3.yAxis*((.20-.34*bow)*math.sin(math.pi*t)*unit)
    end
    local previous
    local tip=v(wrist,coal)
    for row=1,9 do
     local t=row/9
     local current={}
     for column=0,10 do
      local u=column/10
      local glow=math.sin(u*math.pi)^2*t^1.8
      local ripple=.5+.5*math.sin(17*t+u*9+panel)
      current[column+1]=v(membrane(t,u),coal:Lerp(wine,.38+glow*.5):Lerp(flame,glow*(.12+.16*ripple)))
     end
     for i=1,10 do
      if previous then
       tri(previous[i],current[i],current[i+1])
       tri(previous[i],current[i+1],previous[i+1])
      else
       tri(tip,current[i],current[i+1])
      end
     end
     previous=current
    end
    local split={}
    for i=0,7 do
     local t=.27+i*.096
     local u=.56+math.sin(i*1.7+panel)*.094+math.sin(i*3.2)*.07
     table.insert(split,membrane(t,u)+Vector3.yAxis*.016*unit)
    end
    stem(split,{.001,.010,.013,.011,.010,.009,.007,.001},flame)
    local edge={}
    for i=0,5 do table.insert(edge,membrane(i/5,0)) end
    stem(edge,{.061,.055,.044,.031,.019,.005},coal)
   end
   stem({shoulder,p(.38,.36,.07),elbow,p(1.28,1.26,.15),wrist},
    {.195,.142,.10,.077,.060},coal)
   for i=1,4 do
    local t=i/5
    stem({p(.06+t*.41,.03+t*.32,.04),p(.19+t*.52,.09+t*.35,.14),p(.28+t*.47,.11+t*.30,.29)},
     {.041,.045,.004},wine:Lerp(coal,t*.40))
   end
   stem({p(.13,.23,.02),p(.46,.58,.07),p(.90,.90,.14),p(1.32,1.35,.16),p(1.76,1.63,.21)},
    {.013,.021,.016,.014,.003},wine:Lerp(flame,.39))
   stem({wrist,p(1.82,1.69,.16),p(1.95,1.73,.05),p(2.08,1.62,-.11)},
    {.069,.050,.025,.004},bronze)
   local function frame(anchor)
    local time=os.clock()
    local cycle=time*1.85
    local lift=math.sin(cycle)*.19+math.sin(cycle*2)*.017
    return pose(anchor)*bind*CFrame.new(pivot)
     *CFrame.Angles(.077*math.sin(cycle+.7),side*.10*math.sin(cycle-.35),side*lift)*CFrame.new(-pivot)
   end
   local wing,center=build(anchor,vertices,faces,"BLY_InfernoWing",frame)
   if not wing or not isCurrent() then return end
   wingCount+=1
   local nodes={p(1.83,1.39,.48),p(2.52,.79,1.32),p(3.41,.54,1.76)}
   local tint=Color3.fromRGB(255,48,14)
   for i,position in nodes do
    local node=attachment(wing,CFrame.new(position-center))
    local aura=new("ParticleEmitter",{
     Texture="rbxasset://textures/particles/fire_main.dds",
     Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,198,84)),
      ColorSequenceKeypoint.new(.43,Color3.fromRGB(255,77,23)),ColorSequenceKeypoint.new(1,wine)}),
     Rate=10,EmissionDirection=Enum.NormalId.Top,Lifetime=NumberRange.new(.43,.76),
     Speed=NumberRange.new(unit*.62,unit*1.25),Acceleration=Vector3.yAxis*2.1,
     Drag=2,SpreadAngle=Vector2.new(23,28),LightEmission=.88,LightInfluence=0,
     Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.14*unit),
      NumberSequenceKeypoint.new(.37,(i==3 and .53 or .66)*unit),NumberSequenceKeypoint.new(1,.20*unit)}),
     Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.42),
      NumberSequenceKeypoint.new(.29,.17),NumberSequenceKeypoint.new(1,1)}),
    },node)
    new("ParticleEmitter",{
     Texture="rbxasset://textures/particles/sparkles_main.dds",
     Color=ColorSequence.new(Color3.fromRGB(255,179,70),tint),Rate=7,
     EmissionDirection=Enum.NormalId.Top,LightEmission=1,LightInfluence=0,Lifetime=NumberRange.new(.43,.89),
     Speed=NumberRange.new(.75,2.45),SpreadAngle=Vector2.new(40,40),Drag=2,
     Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.031*unit),
      NumberSequenceKeypoint.new(.27,.080*unit),NumberSequenceKeypoint.new(1,0)}),
     Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.28),
      NumberSequenceKeypoint.new(.23,.10),NumberSequenceKeypoint.new(1,1)}),
    },node)
    if i==2 then
     local light=new("PointLight",{Range=math.clamp(unit*2.7,2,9),Brightness=.62,Color=tint,Shadows=false},node)
     local connection=Run.RenderStepped:Connect(function()
      if not node.Parent then return end
      local pulse=.5+.5*math.sin(os.clock()*4.3+side*.65)
      light.Brightness=.27+.37*pulse
      aura.Rate=9+6*pulse
     end)
     table.insert(restoreFur,function() connection:Disconnect() end)
    end
   end
  end
  makeWing(-1)
  if not isCurrent() then return wingCount,false end
  makeWing(1)
  if not isCurrent() then return wingCount,false end
  local ground=RaycastParams.new()
  ground.FilterType=Enum.RaycastFilterType.Exclude
  ground.FilterDescendantsInstances={model}
  ground.IgnoreWater=true
  ground.RespectCanCollide=true
  local fallback=box.Position.Y-root.Position.Y-bounds.Y/2+.28
  local lastProbe=-math.huge
  local floorOffset,groundNormal=fallback,Vector3.yAxis
  local function groundFrame(part)
   local now=os.clock()
   local forward=part.CFrame:VectorToWorldSpace(front)
   forward=Vector3.new(forward.X,0,forward.Z)
   forward=forward.Magnitude>.01 and forward.Unit or -Vector3.zAxis
   local center=part.Position-forward*(unit*.16)
   if now-lastProbe>.12 then
    lastProbe=now
    local lift=math.max(unit*2,bounds.Y)
    local hit=workspace:Raycast(center+Vector3.yAxis*lift,-Vector3.yAxis*(lift*2+2),ground)
    if hit and hit.Normal.Y>.45 then
     floorOffset=hit.Position.Y-center.Y+.23
     groundNormal=hit.Normal
    else
     floorOffset,groundNormal=fallback,Vector3.yAxis
    end
   end
   local x=forward:Cross(groundNormal).Unit
   return CFrame.fromMatrix(center+Vector3.yAxis*floorOffset,x,groundNormal)*CFrame.Angles(0,now*.21,0)
  end
  local function addShackle()
   local body=root.CFrame*bodyBasis
   local groundY=groundFrame(root).Position.Y-.23
   local rest=Vector3.new(unit*.42,groundY-root.Position.Y+unit*.28,unit*.95)
   local leg,ankle,bestScore
   for _,node in model:GetDescendants() do
    if not (node:IsA("Bone") or node:IsA("BasePart")) or node==root then continue end
    local name=node.Name:lower()
    local ankleName=name:find("ankle",1,true) or name:find("hock",1,true)
    local pawName=name:find("foot",1,true) or name:find("paw",1,true) or name:find("toe",1,true)
    local lowerName=name:find("shin",1,true) or name:find("lowerleg",1,true)
    if not (ankleName or pawName or lowerName) then continue end
    local world=pose(node).Position
    local point=body:PointToObjectSpace(world)
    if point.X<unit*.12 or point.Z<unit*.19 or math.abs(point.Y-rest.Y)>unit*.69 then continue end
    local rank=ankleName and 0 or pawName and .13 or .31
    local score=(point-rest).Magnitude+unit*rank
    if not bestScore or score<bestScore then leg,ankle,bestScore=node,point,score end
   end
   local target=ankle or rest
   local sampleHeight=ankle and math.clamp(ankle.Y+unit*.075,rest.Y-unit*.16,rest.Y+unit*.33) or rest.Y
   local actualCenter,radius,surfacePart
   for _,deltaZ in {0,-.10,.10,-.21,.21} do
    local z=target.Z+deltaZ*unit
    local outer=body:PointToWorldSpace(Vector3.new(target.X+unit*.70,sampleHeight,z))
    local inner=body:PointToWorldSpace(Vector3.new(math.max(.02*unit,target.X-unit*.52),sampleHeight,z))
    local along=outer-inner
    local outHit=workspace:Raycast(outer,-along,surface)
    local inHit=workspace:Raycast(inner,along,surface)
    if outHit and inHit and outHit.Instance==inHit.Instance then
     local width=(outHit.Position-inHit.Position).Magnitude
     local midpoint=outHit.Position:Lerp(inHit.Position,.5)
     local localCenter=body:PointToObjectSpace(midpoint)
     if width>unit*.095 and width<unit*.59 and localCenter.X>unit*.12
      and math.abs(localCenter.X-target.X)<unit*.35 then
      actualCenter,radius,surfacePart=midpoint,width*.5,outHit.Instance
      break
     end
    end
   end
   if not leg and not actualCenter then return end
   local center=actualCenter or body:PointToWorldSpace(Vector3.new(target.X,sampleHeight,target.Z))
   leg=leg or surfacePart
   if not leg or not leg:IsDescendantOf(model) then return end
   radius=math.clamp((radius or unit*.14)+unit*.021,unit*.106,unit*.292)
   local cuffLocal=pose(leg):ToObjectSpace(CFrame.fromMatrix(center,body.RightVector,body.UpVector))
   local function cuffFrame()
    return pose(leg)*cuffLocal
   end
   local function chainPin()
    return cuffFrame():PointToWorldSpace(Vector3.new(radius*.23,-unit*.034,radius*.98))
   end
   local metal=Color3.fromRGB(37,27,31)
   local edges=Color3.fromRGB(115,83,64)
   local cuff,cuffFaces={},{}
   local function loop(vertices,faces,width,height,thickness,color,flat)
    local points,radii={},{}
    for j=0,16 do
     local t=j*math.pi/8
     local a,b=math.cos(t),math.sin(t)
     local x=math.sign(a)*math.abs(a)^.69*width
     local y=math.sign(b)*math.abs(b)^.69*height
     table.insert(points,flat and Vector3.new(x,0,y) or Vector3.new(x,y,0))
     table.insert(radii,thickness)
    end
    addRib(vertices,faces,points,radii,color)
   end
   loop(cuff,cuffFaces,radius,radius*.95,unit*.036,metal,true)
   for _,height in {-.047,.047} do
    local start=#cuff+1
    loop(cuff,cuffFaces,radius*1.02,radius*.97,unit*.015,edges,true)
    for j=start,#cuff do cuff[j][1]+=Vector3.yAxis*(height*unit) end
   end
   for i=0,5 do
    local angle=i*math.pi/3
    local radial=Vector3.new(math.cos(angle),0,math.sin(angle))
    addRib(cuff,cuffFaces,{
     radial*(radius*.98)-Vector3.yAxis*(unit*.037),
     radial*(radius+unit*.026),radial*radius+Vector3.yAxis*(unit*.038),
    },{unit*.014,unit*.021,unit*.010},edges)
   end
   addRib(cuff,cuffFaces,{Vector3.new(-radius*.21,0,radius*.92),Vector3.new(radius*.18,-unit*.035,radius*1.10),
    Vector3.new(radius*.42,0,radius*.90)},{unit*.018,unit*.033,unit*.018},edges)
   local band=build(leg,cuff,cuffFaces,"BLY_EclipseShackle",cuffFrame,Enum.Material.Metal)
   if not band or not isCurrent() then return end
   local links,faces={},{}
   local count=10
   local spacing=unit*.33
   loop(links,faces,spacing*.37,spacing*.72,unit*.029,metal:Lerp(edges,.39),false)
   local renderLinks={}
   local frames={}
   local nodes,previous={},{}
   local start=chainPin()
   local rear=(root.CFrame*bodyBasis).LookVector
   for i=0,count do
    local point=start-rear*(spacing*i)
    nodes[i],previous[i]=point,point
   end
   local function linkFrame(i)
    return frames[i] or CFrame.new(nodes[i])
   end
   local link,center=build(root,links,faces,"BLY_EclipseChainLink",function() return linkFrame(1) end,Enum.Material.Metal)
   if not link or not isCurrent() then return end
   for i=2,count do
    local part=link:Clone()
    part.CFrame=linkFrame(i)*CFrame.new(center)
    part.Parent=workspace
    table.insert(effects,part)
    renderLinks[i]=part
   end
   local sparkNode=attachment(renderLinks[count],CFrame.identity)
   local sparks=new("ParticleEmitter",{
    Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=0,
    Color=ColorSequence.new(fireTip,flame),LightEmission=1,LightInfluence=0,
    Speed=NumberRange.new(1.7,4.4),Lifetime=NumberRange.new(.25,.49),SpreadAngle=Vector2.new(42,42),
    Acceleration=Vector3.yAxis*1.1,
    Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.092*unit),NumberSequenceKeypoint.new(.32,.064*unit),NumberSequenceKeypoint.new(1,0)}),
    Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.17),NumberSequenceKeypoint.new(1,1)}),
   },sparkNode)
   local lastGround,pointOnGround,normal=-math.huge,nil,Vector3.yAxis
   local lastSpark=-math.huge
   local connection=Run.RenderStepped:Connect(function(dt)
    if not isCurrent() or not leg.Parent then return end
    dt=math.clamp(dt,1/240,1/28)
    local now=os.clock()
    local body=root.CFrame*bodyBasis
    local back=-body.LookVector
    local horizontal=Vector3.new(back.X,0,back.Z)
    back=horizontal.Magnitude>.1 and horizontal.Unit or Vector3.zAxis
    local pin=chainPin()
    if (pin-nodes[0]).Magnitude>unit*4 then
     for i=1,count do
      nodes[i]=pin+back*(spacing*i)
      previous[i]=nodes[i]
     end
    end
    nodes[0]=pin
    if now-lastGround>.10 then
     lastGround=now
     local hit=workspace:Raycast(nodes[count]+Vector3.yAxis*unit*1.5,-Vector3.yAxis*unit*5,ground)
     if hit and hit.Normal.Y>.45 then
      pointOnGround,normal=hit.Position,hit.Normal
     else
      pointOnGround=nil
     end
    end
    for i=1,count do
     local position=nodes[i]
     local guide=pin+back*(spacing*i*.92)
     local pull=guide-position
     pull=Vector3.new(pull.X,0,pull.Z)
     local drift=pull*(7*dt*dt)
     nodes[i]=position+(position-previous[i])*.91+drift-Vector3.yAxis*(65*dt*dt)
     previous[i]=position
    end
    for _=1,5 do
     for i=1,count do
      local delta=nodes[i]-nodes[i-1]
      local correction=delta.Magnitude>.001 and delta.Unit*(delta.Magnitude-spacing) or Vector3.zero
      if i==1 then nodes[i]-=correction else nodes[i]-=correction*.5 nodes[i-1]+=correction*.5 end
      if pointOnGround then
       local clearance=(nodes[i]-pointOnGround):Dot(normal)-unit*.075
       if clearance<0 then nodes[i]-=normal*clearance end
      end
     end
    end
    for i=1,count do
     local a,b=nodes[i-1],nodes[i]
     local delta=b-a
     if delta.Magnitude>.001 then
      local up=delta.Unit
      local reference=math.abs(up.Y)>.90 and Vector3.zAxis or Vector3.yAxis
      local side=reference:Cross(up).Unit
      frames[i]=CFrame.fromMatrix(a:Lerp(b,.5),side,up)*CFrame.Angles(0,i%2*math.pi*.5,0)
      if renderLinks[i] then renderLinks[i].CFrame=frames[i]*CFrame.new(center) end
     end
    end
    local tip=nodes[count]
    if pointOnGround and now-lastSpark>.19 and (tip-pointOnGround):Dot(normal)<unit*.21
     and (tip-previous[count]).Magnitude>dt*.64 then
     lastSpark=now
     sparks:Emit(8)
    end
   end)
   table.insert(restoreFur,function() connection:Disconnect() end)
  end
  local function haloFrame(part,center)
   local t=os.clock()
   local anchor=part.CFrame*center
   local position=anchor.Position+Vector3.yAxis*(math.sin(t*1.55)*.075*unit)
   local camera=workspace.CurrentCamera
   local facing=camera and camera.CFrame.Position-position or anchor.LookVector
   facing=Vector3.new(facing.X,0,facing.Z)
   facing=facing.Magnitude>.04 and facing.Unit or -Vector3.zAxis
   return CFrame.lookAt(position,position+facing)*CFrame.Angles(.05*math.sin(t),0,.10*math.sin(t*.9))
  end
  local function makeSigil(anchor,center,radius,vertical)
   local vertices,faces={},{}
   local function radial(angle,r)
    local x,y=math.cos(angle)*r,math.sin(angle)*r
    return vertical and Vector3.new(x,y,0) or Vector3.new(x,0,y)
   end
   local function arc(a,b,r,width,tint)
    local n=#vertices
    table.insert(vertices,{radial(a,r-width),tint})
    table.insert(vertices,{radial(a,r+width),tint})
    table.insert(vertices,{radial(b,r+width),tint})
    table.insert(vertices,{radial(b,r-width),tint})
    table.insert(faces,{n+1,n+2,n+3})
    table.insert(faces,{n+1,n+3,n+4})
    table.insert(faces,{n+1,n+3,n+2})
    table.insert(faces,{n+1,n+4,n+3})
   end
   for i=0,59 do
    local a,b=math.pi*i/30,math.pi*(i+1)/30
    local tint=i>=15 and i<45 and gold or flame
    local sweep=.5+.5*math.sin((a+b)*1.5-.7)
    arc(a,b,radius,radius*(vertical and (.007+.009*sweep) or .010),tint:Lerp(white,vertical and .36 or .21))
    if i%5~=4 then arc(a,b,radius*(vertical and .948 or .89),radius*.0044,tint) end
    if vertical and i%5<3 then arc(a,b,radius*1.034,radius*.004,tint:Lerp(white,.19)) end
    if i%5==0 then
     addRib(vertices,faces,{radial(a,radius*1.025),radial(a,radius*(i%15==0 and 1.18 or 1.085))},
      {radius*.012,radius*.001},tint:Lerp(white,.35))
    end
   end
   local function frame(part)
    if vertical then return haloFrame(part,center) end
    return groundFrame(part)
   end
   return build(anchor,vertices,faces,vertical and "BLY_EclipseHalo" or "BLY_EclipseGroundSigil",frame,Enum.Material.Neon)
  end
  makeSigil(root,nil,unit*2.48,false)
  if not isCurrent() then return wingCount,false end
  for _,side in {-1,1} do
   local color=side<0 and gold or flame
   local origin=attachment(root,CFrame.new(right*(side*unit*1.17)+Vector3.yAxis*(floorOffset+.17)))
   new("ParticleEmitter",{
    Texture="rbxasset://textures/particles/sparkles_main.dds",
    Color=ColorSequence.new(color,color:Lerp(white,.48)),Rate=6,
    LightEmission=.95,LightInfluence=0,Lifetime=NumberRange.new(.56,1.25),
    Speed=NumberRange.new(.35,1.45),SpreadAngle=Vector2.new(54,54),
    Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.038*unit),NumberSequenceKeypoint.new(1,0)}),
    Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.17),NumberSequenceKeypoint.new(1,1)}),
   },origin)
   new("PointLight",{Range=math.clamp(unit*3.8,3,11),Brightness=.39,Color=color,Shadows=false},origin)
  end
  local chainOk,chainError=pcall(addShackle)
  if not chainOk and isCurrent() then warn("BLY Eclipse chain: "..tostring(chainError)) end
  if not head or not isCurrent() then return wingCount,false end
  local headBasis=head.CFrame:ToObjectSpace(CFrame.lookAt(head.Position,head.Position+root.CFrame:VectorToWorldSpace(front)))
  local halo,haloCenter=makeSigil(head,headBasis*CFrame.new(0,head.Size.Y*.72,unit*.70),unit*1.18,true)
  if not isCurrent() then return wingCount,halo~=false end
  if halo then
   local haloSpark=attachment(halo,CFrame.new(Vector3.new(0,unit*1.18,0)-haloCenter))
   new("ParticleEmitter",{
    Texture="rbxasset://textures/particles/sparkles_main.dds",
    Color=ColorSequence.new(white,gold),Rate=2,LightEmission=1,LightInfluence=0,
    Lifetime=NumberRange.new(.28,.49),Speed=NumberRange.new(.08,.28),
    Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.08*unit),NumberSequenceKeypoint.new(.40,.20*unit),NumberSequenceKeypoint.new(1,0)}),
    Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(.36,.12),NumberSequenceKeypoint.new(1,1)}),
   },haloSpark)
  end
  local ornaments,ornamentFaces={},{}
  local top=head.Size.Y*.39
  local function jewel(a,b,c,width,color)
   local direction=(c-a).Unit
   local across=direction:Cross(Vector3.zAxis)
   across=across.Magnitude>.01 and across.Unit or Vector3.xAxis
   local i=#ornaments
   table.insert(ornaments,{a,color})
   table.insert(ornaments,{b-across*width,color:Lerp(coal,.25)})
   table.insert(ornaments,{c,color})
   table.insert(ornaments,{b+across*width,color:Lerp(coal,.16)})
   table.insert(ornaments,{b-Vector3.zAxis*width,color:Lerp(white,.36)})
   for k=1,4 do
    table.insert(ornamentFaces,{i+k,i+k%4+1,i+5})
    table.insert(ornamentFaces,{i+k,i+5,i+k%4+1})
   end
  end
  local brow={}
  for i=-7,7 do
   local t=i/7
   table.insert(brow,Vector3.new(t*.36*unit,top+(.018+.075*(1-t*t))*unit,
    (-.39+.14*t*t)*unit))
  end
  local trim={}
  local radii={}
  for i,point in brow do
   trim[i]=point+Vector3.new(0,.047,-.016)*unit
   radii[i]=(.013+.018*math.sin(math.pi*(i-1)/(#brow-1)))*unit
  end
  addRib(ornaments,ornamentFaces,brow,radii,bronze:Lerp(gold,.49))
  addRib(ornaments,ornamentFaces,trim,radii,cream:Lerp(gold,.58))
  for _,index in {4,8,12} do
   local base=brow[index]
   local middle=index==8
   local h=(middle and .195 or .105)*unit
   local edge=Vector3.new((index-8)*.005*unit,h,-.035*unit)
   jewel(base-Vector3.yAxis*.052*unit,base+Vector3.new(0,h*.31,-.046*unit),
    base+edge,(middle and .060 or .041)*unit,gold:Lerp(cream,.40))
   if middle then
    local gem=base+Vector3.new(0,.034,-.091)*unit
    jewel(gem-Vector3.yAxis*.035*unit,gem,gem+Vector3.yAxis*.077*unit,.033*unit,white)
   end
  end
  local function horn(x,y,z) return Vector3.new(unit*x,top+unit*y,unit*z) end
  addRib(ornaments,ornamentFaces,{horn(.245,-.075,.005),horn(.315,.045,.056),horn(.403,.16,.13),
   horn(.457,.28,.205),horn(.464,.39,.23),horn(.417,.465,.195),horn(.35,.504,.14)},
   {unit*.093,unit*.082,unit*.068,unit*.055,unit*.038,unit*.021,unit*.003},coal)
  addRib(ornaments,ornamentFaces,{horn(.278,.01,-.056),horn(.362,.129,.04),horn(.412,.226,.107),
   horn(.445,.335,.173),horn(.435,.424,.171)},
   {unit*.008,unit*.013,unit*.012,unit*.008,unit*.002},wine:Lerp(flame,.64))
  local crown,center=build(head,ornaments,ornamentFaces,"BLY_EclipseCrown",function(part)
   return part.CFrame*headBasis*CFrame.Angles(0,.022*math.sin(os.clock()*1.85),0)
  end)
  if crown and isCurrent() then
   local jewelLight=attachment(crown,CFrame.new(brow[8]-center))
   new("PointLight",{Range=math.clamp(unit*1.7,1.6,5),Brightness=.34,Color=gold,Shadows=false},jewelLight)
  end
  if not isCurrent() then return wingCount,not not halo end
  local collar={}
  local chest=math.max(3*unit,(head.Position-root.Position).Magnitude+unit)
  avatarFrame=root.CFrame*bodyBasis
  for i=-6,6 do
   local across=i/6
   local y=(-.49+.37*math.abs(across))*unit
   local from=avatarFrame:PointToWorldSpace(Vector3.new(across*.64*unit,y,-chest))
   local hit=workspace:Raycast(from,-avatarFrame.LookVector*chest*1.6,surface)
   if not hit or hit.Instance.Transparency>.95 then break end
   table.insert(collar,avatarFrame:PointToObjectSpace(hit.Position+hit.Normal*.078*unit))
  end
  if #collar==13 then
   ornaments,ornamentFaces={},{}
   local radii={}
   for index=1,#collar do radii[index]=unit*(index%2==0 and .021 or .032) end
   addRib(ornaments,ornamentFaces,collar,radii,gold)
   local center=collar[7]-Vector3.zAxis*.05*unit
   jewel(center+Vector3.yAxis*.14*unit,center,center-Vector3.yAxis*.21*unit,unit*.135,fireTip)
   build(root,ornaments,ornamentFaces,"BLY_EclipsePendant",function(part) return part.CFrame*bodyBasis end)
  end
  return wingCount,not not halo
 end
 local function infernoPixels(pixels,width,firstRow,height,isEye,glowPixels,royal)
  for offset=0,buffer.len(pixels)-4,4 do
   local alpha=buffer.readu8(pixels,offset+3)
   if alpha==0 then continue end
   local r=buffer.readu8(pixels,offset)
   local g=buffer.readu8(pixels,offset+1)
   local b=buffer.readu8(pixels,offset+2)
   local luma=.2126*r+.7152*g+.0722*b
   local red,green,blue,glow
   if isEye then
    local iris=math.clamp((math.max(r,g,b)-24)/130,0,1)
    if royal then
     red=86+169*iris
     green=48+158*iris^2
     blue=8+43*iris^2
     glow=238*iris^2
    else
     red=12+243*iris
     green=2+31*iris^2
     blue=6+17*iris^2
     glow=230*iris^2
    end
   else
    if royal then
     red=48+.34*luma
     green=29+.235*luma
     blue=17+.12*luma
     glow=0
    else
     local pixel=offset/4
     local u=(pixel%width)/width
     local v=(firstRow+math.floor(pixel/width))/height
     local vein=math.noise(u*9,v*9,.72)+.29*math.noise(u*28,v*31,1.45)
     local cluster=math.clamp((math.noise(u*4,v*4,8)+.10)*3,0,1)
     local heat=math.clamp(1-math.abs(vein-.037)*48,0,1)^2*cluster
     red=8+.16*luma+26*heat
     green=3+.025*luma+5*heat
     blue=6+.04*luma+4*heat
     glow=0
    end
   end
   buffer.writeu8(pixels,offset,math.floor(red+.5))
   buffer.writeu8(pixels,offset+1,math.floor(green+.5))
   buffer.writeu8(pixels,offset+2,math.floor(blue+.5))
   if glowPixels then
    local intensity=math.floor(glow+.5)
    buffer.writeu8(glowPixels,offset,intensity)
    buffer.writeu8(glowPixels,offset+1,intensity)
    buffer.writeu8(glowPixels,offset+2,intensity)
    buffer.writeu8(glowPixels,offset+3,255)
   end
  end
 end
 local function miragePixels(pixels,width,firstRow,height,isEye,glowPixels)
  for offset=0,buffer.len(pixels)-4,4 do
   if buffer.readu8(pixels,offset+3)==0 then continue end
   local u=(offset/4%width)/width
   local v=(firstRow+math.floor(offset/4/width))/height
   local r,g,b,glow
   if isEye then
    local iris=math.clamp((math.max(buffer.readu8(pixels,offset),buffer.readu8(pixels,offset+1),buffer.readu8(pixels,offset+2))-24)/130,0,1)
    r,g,b,glow=18+20*iris,80+160*iris,104+151*iris,225*iris
   else
    local luma=.2126*buffer.readu8(pixels,offset)+.7152*buffer.readu8(pixels,offset+1)+.0722*buffer.readu8(pixels,offset+2)
    local warp=.16*math.noise(u*8,v*9,.21)
    local flow=math.sin((u*2.15+.18*math.sin(v*6.2)+warp)*math.pi*2)
    local river=math.clamp(1-math.abs(flow)*8.5,0,1)^1.25
    local branch=math.clamp(1-math.abs(math.noise(u*12+flow,v*14,2.9))*16,0,1)*river*.55
    local star=math.clamp((math.noise(u*52,v*52,7.4)-.29)*8,0,1)
    local glowMix=math.clamp(river+branch+star*.22,0,1)
    local depth=math.clamp(luma/255,.14,.75)
    r=7+23*depth+16*glowMix
    g=15+43*depth+180*glowMix
    b=27+62*depth+192*glowMix
    glow=238*glowMix
   end
   buffer.writeu8(pixels,offset,math.floor(r+.5))
   buffer.writeu8(pixels,offset+1,math.floor(g+.5))
   buffer.writeu8(pixels,offset+2,math.floor(b+.5))
   if glowPixels then
    local intensity=math.floor(glow+.5)
    buffer.writeu8(glowPixels,offset,intensity)
    buffer.writeu8(glowPixels,offset+1,intensity)
    buffer.writeu8(glowPixels,offset+2,intensity)
    buffer.writeu8(glowPixels,offset+3,255)
   end
  end
 end
 local function auroraPixels(pixels,width,firstRow,height,isEye,glowPixels,isHorn)
  for offset=0,buffer.len(pixels)-4,4 do
   if buffer.readu8(pixels,offset+3)==0 then continue end
   local u=(offset/4%width)/width
   local v=(firstRow+math.floor(offset/4/width))/height
   local r,g,b,glow
   if isEye then
    local iris=math.clamp((math.max(buffer.readu8(pixels,offset),buffer.readu8(pixels,offset+1),buffer.readu8(pixels,offset+2))-22)/135,0,1)
    r,g,b,glow=63+180*iris,39+128*iris,136+119*iris,240*iris
   elseif isHorn then
    local crystal=.5+.5*math.sin((u*.78+v*.48)*math.pi*2)
    local facet=math.clamp(.5+.5*math.sin((u*5+v*3)*math.pi),.16,1)
    r,g,b=72+150*crystal*facet,99+119*(1-crystal)*facet,185+68*facet
    glow=190*facet
   else
    local luma=.2126*buffer.readu8(pixels,offset)+.7152*buffer.readu8(pixels,offset+1)+.0722*buffer.readu8(pixels,offset+2)
    local warp=.15*math.noise(u*8,v*8,.63)
    local flow=math.sin((u*1.9+.16*math.sin(v*5.5)+warp)*math.pi*2)
    local vein=math.clamp(1-math.abs(flow)*9,0,1)^1.4
    local branch=math.clamp(1-math.abs(math.noise(u*14+flow,v*17,3.7))*17,0,1)*vein*.58
    local glowMix=math.clamp(vein+branch,0,1)
    local depth=math.clamp(luma/255,.12,.72)
    local pulse=.5+.5*math.sin((u+v*.31)*math.pi*2)
    r=15+25*depth+78*glowMix*pulse
    g=12+23*depth+67*glowMix
    b=31+53*depth+176*glowMix
    glow=236*glowMix
   end
   buffer.writeu8(pixels,offset,math.floor(r+.5))
   buffer.writeu8(pixels,offset+1,math.floor(g+.5))
   buffer.writeu8(pixels,offset+2,math.floor(b+.5))
   if glowPixels then
    local intensity=math.floor(glow+.5)
    buffer.writeu8(glowPixels,offset,intensity)
    buffer.writeu8(glowPixels,offset+1,intensity)
    buffer.writeu8(glowPixels,offset+2,intensity)
    buffer.writeu8(glowPixels,offset+3,255)
   end
  end
 end
 local function emeraldPixels(pixels,width,firstRow,height,isEye,glowPixels)
  for offset=0,buffer.len(pixels)-4,4 do
   if buffer.readu8(pixels,offset+3)==0 then continue end
   local u=(offset/4%width)/width
   local v=(firstRow+math.floor(offset/4/width))/height
   local r,g,b,glow
   if isEye then
    local iris=math.clamp((math.max(buffer.readu8(pixels,offset),buffer.readu8(pixels,offset+1),buffer.readu8(pixels,offset+2))-22)/135,0,1)
    r,g,b,glow=63+153*iris,90+163*iris,45+105*iris,218*iris
   else
    local luma=.2126*buffer.readu8(pixels,offset)+.7152*buffer.readu8(pixels,offset+1)+.0722*buffer.readu8(pixels,offset+2)
    local gx,gy=u*8,v*5
    local ix,iy=math.floor(gx),math.floor(gy)
    local dx=(gx-ix-.5)+math.noise(ix,iy,2.1)*.07
    local dy=(gy-iy-.5)+math.noise(ix,iy,4.7)*.07
    local radius=math.sqrt((dx/.39)^2+(dy/.34)^2)
    local angle=math.atan2(dy,dx)
    local petals=.72+.28*math.sin(angle*5+math.noise(ix,iy,8.3)*1.7)
    local rosette=math.clamp(1-math.abs(radius-.67)*7,0,1)*math.clamp(petals,0,1)
    local flow=math.sin((u*1.35+.13*math.sin(v*6.1)+.08*math.noise(u*8,v*8,1.7))*math.pi*2)
    local current=math.clamp(1-math.abs(flow)*11,0,1)^2*.42
    local depth=math.clamp(luma/255,.12,.68)
    r=5+19*depth+20*math.clamp(rosette+current,0,1)
    g=9+22*depth+173*rosette+75*current
    b=13+25*depth+43*rosette+77*current
    glow=226*math.clamp(rosette*.9+current*.55,0,1)
   end
   buffer.writeu8(pixels,offset,math.floor(r+.5))
   buffer.writeu8(pixels,offset+1,math.floor(g+.5))
   buffer.writeu8(pixels,offset+2,math.floor(b+.5))
   if glowPixels then
    local intensity=math.floor(glow+.5)
    buffer.writeu8(glowPixels,offset,intensity)
    buffer.writeu8(glowPixels,offset+1,intensity)
    buffer.writeu8(glowPixels,offset+2,intensity)
    buffer.writeu8(glowPixels,offset+3,255)
   end
  end
 end
 local function pinkPixels(pixels,width,firstRow,height,isEye,glowPixels)
  for offset=0,buffer.len(pixels)-4,4 do
   if buffer.readu8(pixels,offset+3)==0 then continue end
   local r0=buffer.readu8(pixels,offset)
   local g0=buffer.readu8(pixels,offset+1)
   local b0=buffer.readu8(pixels,offset+2)
   local r,g,b,glow
   if isEye then
    local iris=math.clamp((math.max(r0,g0,b0)-22)/135,0,1)
    r,g,b,glow=38+217*iris,13+82*iris,22+94*iris,120*iris
   else
    local luma=(.2126*r0+.7152*g0+.0722*b0)/255
    local shade=.53+.47*math.clamp(luma,0,1)^.62
    r,g,b,glow=255*shade,197*shade,223*shade,0
   end
   buffer.writeu8(pixels,offset,math.floor(r+.5))
   buffer.writeu8(pixels,offset+1,math.floor(g+.5))
   buffer.writeu8(pixels,offset+2,math.floor(b+.5))
   if glowPixels then
    local intensity=math.floor(glow+.5)
    buffer.writeu8(glowPixels,offset,intensity)
    buffer.writeu8(glowPixels,offset+1,intensity)
    buffer.writeu8(glowPixels,offset+2,intensity)
    buffer.writeu8(glowPixels,offset+3,255)
   end
  end
 end
 local function breathOrigin(model,head,root)
  local offset=head.Position-root.Position
  local forward=Vector3.new(offset.X,0,offset.Z)
  if forward.Magnitude<.4 then
   local look=root.CFrame.LookVector
   forward=Vector3.new(look.X,0,look.Z)
  end
  forward=forward.Magnitude>.01 and forward.Unit or -Vector3.zAxis
  local frame,size=head.CFrame,head.Size
  local longAxis=size.Z>=size.X and frame.LookVector or frame.RightVector
  local horizontal=Vector3.new(longAxis.X,0,longAxis.Z)
  if horizontal.Magnitude>.5 then
   horizontal=horizontal.Unit
   local alignment=horizontal:Dot(forward)
   if math.abs(alignment)>.72 then forward=alignment>0 and horizontal or -horizontal end
  end
  local function frontOf(part)
   local basis,dimensions=part.CFrame,part.Size
   local half=(math.abs(forward:Dot(basis.RightVector))*dimensions.X
    +math.abs(forward:Dot(basis.UpVector))*dimensions.Y
    +math.abs(forward:Dot(basis.LookVector))*dimensions.Z)*.5
   return (part.Position-head.Position):Dot(forward)+half
  end
  local front=frontOf(head)
  local mouthHeight=head.Position.Y-size.Y*.26
  local lateral=forward:Cross(Vector3.yAxis).Unit
  local marker,markerFront=nil,-math.huge
  local mouthParts={head}
  local mouthBone,headBone
  for _,object in model:GetDescendants() do
   local name=object.Name:lower():gsub("[^%a]","")
   if object:IsA("Attachment") or object:IsA("Bone") then
    if object:IsA("Bone") and (name=="head" or name=="skull" or name=="headbone") then
     if not headBone or object:IsDescendantOf(head) then headBone=object end
    end
    if name=="mouth" or name=="mouthattachment" or name=="muzzle" or name=="snout" or name=="snouttip" or name=="mouthtip" then
     local position=object:IsA("Bone") and object.TransformedWorldCFrame.Position or object.WorldPosition
     local delta=position-head.Position
     local ahead=delta:Dot(forward)
     if math.abs(delta:Dot(lateral))<math.max(.35,math.min(size.X,size.Z)*.22) and ahead>markerFront then
      marker,markerFront=position,ahead
      mouthBone=object:IsA("Bone") and object or (object.Parent and object.Parent:IsA("Bone") and object.Parent or nil)
     end
    end
   elseif object:IsA("BasePart") and object.Transparency<.95 and object~=head then
    if name:find("jaw",1,true) or name:find("snout",1,true) or name:find("muzzle",1,true) or name:find("teeth",1,true) then
     table.insert(mouthParts,object)
     local reach=frontOf(object)
     if reach>front then
      front=reach
      mouthHeight=math.clamp(object.Position.Y,head.Position.Y-size.Y*.48,head.Position.Y+size.Y*.14)
     end
    end
   end
  end
  local distance=math.max(.13,math.min(size.X,size.Z)*.035)
  local filter=RaycastParams.new()
  filter.FilterType=Enum.RaycastFilterType.Include
  filter.FilterDescendantsInstances=mouthParts
  if marker and markerFront>=front*.83 then mouthHeight=marker.Y end
  local nose
  local probe=head.Position+forward*(front+distance+size.Y*.30)
  for _,height in {0,.09,-.08,.17} do
   local sample=Vector3.new(probe.X,mouthHeight+height*size.Y,probe.Z)
   local hit=workspace:Raycast(sample,-forward*(front*.52+distance+size.Y*.30),filter)
   if hit and hit.Normal:Dot(forward)>.18 then
    local ahead=(hit.Position-head.Position):Dot(forward)
    if not nose or ahead>nose then nose=ahead end
   end
  end
  local reach=nose or (marker and markerFront>=front*.83 and markerFront) or front
  local position=head.Position+forward*(reach+distance)
  local muzzleUp=head.CFrame.UpVector
  if math.abs(muzzleUp:Dot(forward))>.84 then muzzleUp=Vector3.yAxis end
  local lift=math.clamp(size.Y*.105,.035,.22)
  position=Vector3.new(position.X,mouthHeight,position.Z)+muzzleUp*lift
  local pitchAxis=size.Z>=size.X and head.CFrame.LookVector or head.CFrame.RightVector
  if pitchAxis:Dot(forward)<0 then pitchAxis=-pitchAxis end
  if pitchAxis:Dot(forward)<.62 then pitchAxis=forward end
  local bindBone=marker and markerFront>=front*.83 and mouthBone or headBone
  return CFrame.lookAt(position,position+pitchAxis,muzzleUp),bindBone
 end
 local function addLavaLight(root)
  local span=math.clamp(math.max(root.Size.X,root.Size.Z),3.5,10)
  local underbelly=attachment(root,CFrame.new(0,-root.Size.Y*.34,0))
  new("SpotLight",{
   Face=Enum.NormalId.Bottom,Angle=122,Range=span*1.6,
   Color=Color3.fromRGB(255,100,30),Brightness=1.4,Shadows=false,
  },underbelly)
  new("PointLight",{
   Range=span*.85,Color=Color3.fromRGB(255,63,16),Brightness=.26,Shadows=false,
  },underbelly)
 end
 local function startBreath(model,root,isCurrent)
  local head=findAnimalHead(model)
  if not head then return end
  local mouthFrame,bone=breathOrigin(model,head,root)
  local origin=attachment(head,head.CFrame:ToObjectSpace(mouthFrame))
  local boneOffset=bone and bone.TransformedWorldCFrame:ToObjectSpace(mouthFrame)
  local scale=math.clamp(head.Size.Magnitude*.12,.55,1.25)
  local warmth=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/fire_main.dds",Rate=0,
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(10,7),
   Speed=NumberRange.new(.9*scale,2.5*scale),Lifetime=NumberRange.new(.13,.22),
   Drag=2,Acceleration=Vector3.new(0,.75,0),LightEmission=.65,LightInfluence=0,
   Color=ColorSequence.new(Color3.fromRGB(255,170,76),Color3.fromRGB(146,38,22)),
   Size=NumberSequence.new({
    NumberSequenceKeypoint.new(0,.13*scale),NumberSequenceKeypoint.new(.46,.34*scale),
    NumberSequenceKeypoint.new(1,.22*scale),
   }),
   Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,.57),NumberSequenceKeypoint.new(.56,.74),NumberSequenceKeypoint.new(1,1),
   }),
  },origin)
  local sparks=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=0,
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(14,9),
   Speed=NumberRange.new(2.3*scale,4.6*scale),Lifetime=NumberRange.new(.16,.28),
   Drag=2,Acceleration=Vector3.new(0,1.1,0),LightEmission=1,LightInfluence=0,
   Color=ColorSequence.new(Color3.fromRGB(255,210,113),Color3.fromRGB(231,66,26)),
   Size=NumberSequence.new({
    NumberSequenceKeypoint.new(0,.073*scale),NumberSequenceKeypoint.new(1,.015*scale),
   }),
   Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(.52,.25),NumberSequenceKeypoint.new(1,1),
   }),
  },origin)
  local plume=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/fire_main.dds",Rate=0,
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(11,10),
   Speed=NumberRange.new(9*scale,16*scale),Lifetime=NumberRange.new(.28,.46),
   Drag=1.7,Acceleration=Vector3.yAxis*2.1,LightEmission=.86,LightInfluence=0,
   Color=ColorSequence.new(Color3.fromRGB(255,207,94),Color3.fromRGB(211,47,13)),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.23*scale),
    NumberSequenceKeypoint.new(.43,.83*scale),NumberSequenceKeypoint.new(1,.48*scale)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.29),
    NumberSequenceKeypoint.new(.32,.16),NumberSequenceKeypoint.new(1,1)}),
  },origin)
  local embers=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=0,
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(21,15),
   Speed=NumberRange.new(6*scale,11*scale),Lifetime=NumberRange.new(.27,.48),
   Drag=2.4,Acceleration=Vector3.yAxis*1.8,LightEmission=1,LightInfluence=0,
   Color=ColorSequence.new(Color3.fromRGB(255,218,117),Color3.fromRGB(248,65,17)),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22*scale),
    NumberSequenceKeypoint.new(.31,.16*scale),NumberSequenceKeypoint.new(1,0)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.08),NumberSequenceKeypoint.new(1,1)}),
  },origin)
  local manualFlame=plume:Clone()
  manualFlame.Lifetime=NumberRange.new(.43,.68)
  manualFlame.Speed=NumberRange.new(11*scale,19*scale)
  manualFlame.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.25*scale),
   NumberSequenceKeypoint.new(.38,1.0*scale),NumberSequenceKeypoint.new(1,.52*scale)})
  manualFlame.Parent=origin
  local function validMouth()
   return isCurrent() and origin.Parent and head:IsDescendantOf(model)
  end
  local function aim()
   if boneOffset and bone:IsDescendantOf(model) then
    origin.CFrame=head.CFrame:ToObjectSpace(bone.TransformedWorldCFrame*boneOffset)
   end
  end
  local follow
  if boneOffset then
   follow=Run.RenderStepped:Connect(function()
    if validMouth() then aim() end
   end)
  end
  local nextFire,nextBite=0,0
  local queuedAt,revision
  local markers={}
  local function clearMarkers()
   for _,connection in markers do connection:Disconnect() end
   table.clear(markers)
  end
  local function cancelBite()
   queuedAt=nil
   revision=(revision or 0)+1
   clearMarkers()
  end
  local function biteAfter(delay,track)
   if not validMouth() or os.clock()<nextBite then return end
   if queuedAt and (not track or os.clock()-queuedAt>.19) then return end
   cancelBite()
   queuedAt=os.clock()
   local ticket=revision
   local function finish()
    if ticket~=revision then return end
    cancelBite()
    if not validMouth() then return end
    nextBite=os.clock()+.33
    aim()
    embers:Emit(8)
    plume:Emit(3)
   end
   if track then
    for _,name in {"JawClose","BiteEnd","Hit"} do
     table.insert(markers,track:GetMarkerReachedSignal(name):Connect(function()
      if queuedAt and os.clock()-queuedAt>=.14 then finish() end
     end))
    end
   end
   task.delay(delay,finish)
  end
  local input=UIS.InputBegan:Connect(function(key,processed)
   if processed or UIS:GetFocusedTextBox() or not validMouth() then return end
   if key.KeyCode==Enum.KeyCode.F and os.clock()>=nextFire then
    nextFire=os.clock()+1.25
    nextBite=os.clock()+.32
    cancelBite()
    aim()
    manualFlame:Emit(15)
    embers:Emit(8)
    for i,count in {12,8} do
     task.delay(i*.11,function()
      if not validMouth() then return end
      aim()
      manualFlame:Emit(count)
      embers:Emit(i==1 and 5 or 3)
     end)
    end
   elseif key.UserInputType==Enum.UserInputType.MouseButton1 then
    biteAfter(.28)
   end
  end)
  local animator=model:FindFirstChildWhichIsA("Animator",true)
  local animations
  if animator then
   animations=animator.AnimationPlayed:Connect(function(track)
    local name=(track.Name.." "..(track.Animation and track.Animation.Name or "")):lower()
    if not (name:find("bite",1,true) or name:find("attack",1,true) or name:find("snap",1,true)) then return end
    if name:find("idle",1,true) then return end
    biteAfter(math.clamp(.28/math.max(track.Speed,.25),.19,.40),track)
   end)
  end
  table.insert(restoreFur,function()
   input:Disconnect()
   if animations then animations:Disconnect() end
   if follow then follow:Disconnect() end
   cancelBite()
  end)
  task.spawn(function()
   while validMouth() do
    task.wait(1.9+math.random()*.55)
    if validMouth() and not queuedAt and os.clock()>=nextBite and os.clock()>=nextFire then
     aim()
     warmth:Emit(1)
     sparks:Emit(2)
    end
   end
  end)
 end
 local function makeSkyDragon(model,root,assets,isCurrent)
  local box,bounds=model:GetBoundingBox()
  local unit=math.clamp(bounds.Y*.225,.42,3.15)
  local rawHead=findAnimalHead(model)
  local heading=rawHead and root.CFrame:PointToObjectSpace(rawHead.Position) or -Vector3.zAxis
  heading=Vector3.new(heading.X,0,heading.Z)
  heading=heading.Magnitude>.20 and heading.Unit or -Vector3.zAxis
  local facing=CFrame.lookAt(Vector3.zero,heading)
  local body=root.CFrame*facing
  local coal=Color3.fromRGB(20,17,18)
  local slate=Color3.fromRGB(49,42,42)
  local bronze=Color3.fromRGB(107,78,59)
  local belly=Color3.fromRGB(130,98,73)
  local horn=Color3.fromRGB(175,143,108)
  local leather=Color3.fromRGB(102,39,28)
  local ember=Color3.fromRGB(164,59,37)
  local orange=Color3.fromRGB(255,133,40)
  local buildDragonMesh=createDecorationBuilder(model,assets,isCurrent)
  local function makeMesh(node,vertices,faces,name,frame,material)
   local part,center=buildDragonMesh(node,vertices,faces,name,frame,material)
   if part and material~=Enum.Material.Neon then part.CastShadow=true end
   return part,center
  end
  local anchors={}
  local function pose(node)
   return node:IsA("Bone") and node.TransformedWorldCFrame or node.CFrame
  end
  for _,node in model:GetDescendants() do
   if node:IsA("Bone") or (node:IsA("BasePart") and node~=root) then
    table.insert(anchors,{node=node,name=node.Name:lower(),point=body:PointToObjectSpace(pose(node).Position)})
   end
  end
  local function anchorFor(names,target,side)
   local best,score
   for _,entry in anchors do
    if side and entry.point.X*side<unit*.07 then continue end
    for rank,name in names do
     if entry.name:find(name,1,true) then
      local distance=(entry.point-target).Magnitude+unit*((rank-1)*.45+(entry.node:IsA("Bone") and 0 or .14))
      if not score or distance<score then best,score=entry.node,distance end
      break
     end
    end
   end
   return best
  end
  local function bound(anchor,position)
   local bind=pose(anchor):ToObjectSpace(body*CFrame.new(position))
   return function(node) return pose(node)*bind end
  end
  local function vertex(vertices,p,color)
   table.insert(vertices,{p,color})
   return #vertices
  end
  local function face(faces,a,b,c,twoSided)
   table.insert(faces,{a,b,c})
   if twoSided then table.insert(faces,{a,c,b}) end
  end
  local function point(x,y,z)
   return Vector3.new(x,y,z)*unit
  end
  local function ridge(vertices,faces,base,normal,direction,wide,long,depth,color)
   local lateral=normal:Cross(direction)
   if lateral.Magnitude<.01 then return end
   lateral=lateral.Unit
   local first=vertex(vertices,base-direction*(long*.48),color:Lerp(coal,.26))
   local l=vertex(vertices,base-lateral*(wide*.5),color:Lerp(coal,.23))
   local tip=vertex(vertices,base+direction*(long*.57)+normal*depth*.32,color:Lerp(coal,.12))
   local r=vertex(vertices,base+lateral*(wide*.5),color:Lerp(slate,.18))
   local crown=vertex(vertices,base+normal*depth,color)
   face(faces,first,l,crown,true) face(faces,l,tip,crown,true)
   face(faces,tip,r,crown,true) face(faces,r,first,crown,true)
  end
  local function shell(vertices,faces,rings,detail,armored,bellyPlates)
   local first=#vertices
   local columns={}
   for i,row in rings do
    local p,rx,ry=row[1],row[2]*unit,row[3]*unit
    local direction=(rings[math.min(#rings,i+1)][1]-rings[math.max(1,i-1)][1]).Unit
    local reference=math.abs(direction.Y)>.93 and Vector3.zAxis or Vector3.yAxis
    local lateral=direction:Cross(reference).Unit
    local up=lateral:Cross(direction).Unit
    if up.Y<0 and math.abs(direction.Y)<.8 then lateral,up=-lateral,-up end
    columns[i]={p,lateral,up,direction,rx,ry}
    for j=0,detail-1 do
     local angle=2*math.pi*j/detail
     local w,h=math.cos(angle),math.sin(angle)
     local grain=.5+.5*math.sin(i*6.43+j*4.71)
     local tint=coal:Lerp(slate,.38+.51*grain)
     if bellyPlates and h<-.54 then tint=tint:Lerp(belly,math.min(.72,-h*.68)) end
     vertex(vertices,p+lateral*(rx*w)+up*(ry*h),tint)
    end
   end
   for i=0,#rings-2 do
    for j=0,detail-1 do
     local a=first+i*detail+j+1
     local b=first+i*detail+(j+1)%detail+1
     face(faces,a,a+detail,b)
     face(faces,b,a+detail,b+detail)
    end
   end
   local cap0=vertex(vertices,rings[1][1],coal)
   local cap1=vertex(vertices,rings[#rings][1],coal)
   for j=0,detail-1 do
    local a,b=first+j+1,first+(j+1)%detail+1
    local last=(#rings-1)*detail
    face(faces,cap0,a,b)
    face(faces,cap1,b+last,a+last)
   end
   if not armored then return end
   for i=1,#columns-1 do
    local row,nextRow=columns[i],columns[i+1]
    local center,lateral,up,direction=row[1]:Lerp(nextRow[1],.46),row[2],row[3],row[4]
    local width,height=(row[5]+nextRow[5])*.5,(row[6]+nextRow[6])*.5
    local length=(nextRow[1]-row[1]).Magnitude
    for j=0,detail-1 do
     local angle=2*math.pi*(j+(i%2)*.43)/detail
     local w,h=math.cos(angle),math.sin(angle)
     local normal=(lateral*w+up*h).Unit
     local color=slate:Lerp(bronze,.11+.16*(.5+.5*math.sin(j*7.31+i*3.29)))
     local span=math.max(width,height)*3.8/detail
     if bellyPlates and h<-.65 then color=color:Lerp(belly,.57) span*=1.27 end
     ridge(vertices,faces,center+lateral*(width*w)+up*(height*h)+normal*(unit*.006),
      normal,direction,span,length*.77,math.min(unit*.053,width*.17),color)
    end
   end
  end
  local function rings(rows)
   local output={}
   for _,row in rows do table.insert(output,{point(row[1],row[2],row[3]),row[4],row[5]}) end
   return output
  end
  local function tube(vertices,faces,points,radii,color)
   for i,value in radii do radii[i]=value*unit end
   addRib(vertices,faces,points,radii,color)
  end
  local headAnchor=anchorFor({"head","skull","neck"},point(0,1.4,-.56)) or rawHead or root
  local sourceHead=body:PointToObjectSpace(pose(headAnchor).Position)
  local headPosition=point(0,math.clamp(sourceHead.Y/unit,1.16,2.04),math.clamp(sourceHead.Z/unit,-1.02,-.54))
  local torso,torsoFaces={},{}
  shell(torso,torsoFaces,rings({
   {0,.18,-1.10,.043,.072},{0,.21,-1.05,.21,.30},{0,.25,-.94,.39,.46},{0,.15,-.71,.51,.56},{0,.04,-.43,.59,.61},{0,0,-.12,.62,.61},
   {0,-.09,.22,.57,.54},{0,-.15,.54,.47,.44},{0,-.20,.88,.32,.32},{0,-.23,1.08,.19,.22},
  }),17,true,true)
  local neckStart=point(0,.20,-.67)
  local neckEnd=headPosition+point(0,-.29,.16)
  local neck={}
  for i=0,9 do
   local t=i/9
   local center=neckStart:Lerp(neckEnd,t)+point(0,0,.14*math.sin(t*math.pi))
   table.insert(neck,{center,.33-.16*t,.29-.11*t})
   if i>=2 and i<=8 then
    local n=center+point(0,.04,.25-.09*t)
    ridge(torso,torsoFaces,n,Vector3.zAxis,Vector3.yAxis,unit*.19,unit*.23,unit*(.12+.05*t),bronze)
   end
  end
  shell(torso,torsoFaces,neck,15,true,true)
  if not makeMesh(root,torso,torsoFaces,"BLY_DragonTorso",bound(root,Vector3.zero)) then return end
  local head,headFaces={},{}
  shell(head,headFaces,rings({
   {0,.02,.30,.22,.26},{0,.06,.09,.35,.35},{0,.05,-.17,.36,.30},{0,-.01,-.37,.29,.25},
   {0,-.06,-.60,.25,.18},{0,-.07,-.81,.215,.14},{0,-.075,-.89,.158,.12},
  }),18,true,false)
  for _,side in {-1,1} do
   tube(head,headFaces,{
    point(side*.24,.27,.07),point(side*.34,.44,.12),point(side*.42,.64,.21),
    point(side*.45,.77,.27),point(side*.40,.91,.27),
   },{.106,.093,.065,.038,.003},bronze:Lerp(horn,.32))
   tube(head,headFaces,{
    point(side*.30,.12,.19),point(side*.48,.23,.30),point(side*.61,.36,.44),point(side*.69,.43,.52),
   },{.084,.057,.032,.003},bronze)
   tube(head,headFaces,{
    point(side*.29,-.095,.16),point(side*.45,-.105,.32),point(side*.56,-.07,.51),
   },{.079,.045,.003},slate)
   tube(head,headFaces,{
    point(side*.30,.145,-.39),point(side*.33,.22,-.25),point(side*.31,.21,-.09),
   },{.037,.077,.043},bronze)
   for i=1,3 do
    local z=.02+i*.086
    ridge(head,headFaces,point(side*.27,.01-i*.032,z),Vector3.xAxis*side,Vector3.zAxis,unit*.21,unit*.25,unit*.10,slate)
   end
  end
  local headFrame=bound(headAnchor,headPosition)
  local skull,headCenter=makeMesh(headAnchor,head,headFaces,"BLY_DragonSkull",headFrame)
  if not skull then return end
  local iris,irisFaces={},{}
  for _,side in {-1,1} do
   shell(iris,irisFaces,rings({{side*.321,.097,-.357,.036,.031},
    {side*.351,.126,-.289,.071,.043},{side*.351,.116,-.223,.060,.037},{side*.323,.091,-.164,.025,.022}}),9,false,false)
  end
  for _,item in iris do item[2]=orange end
  makeMesh(headAnchor,iris,irisFaces,"BLY_DragonEyes",headFrame,Enum.Material.Neon)
  local holding,jawOpen=false,0
  local jaw,jawFaces={},{}
  shell(jaw,jawFaces,rings({
   {0,-.20,.14,.23,.10},{0,-.25,-.19,.267,.115},{0,-.255,-.45,.225,.10},
   {0,-.25,-.70,.18,.076},{0,-.245,-.86,.13,.06},
  }),15,true,false)
  for _,side in {-1,1} do
   for i=0,5 do
    local x=side*(.244-i*.013)
    local z=-.28-i*.09
    tube(jaw,jawFaces,{point(x,-.21,z),point(x*.96,-.17,z+.015),point(x*.92,-.118,z+.027)},
     {.020,.014,.002},horn)
   end
  end
  local jawJoint=point(0,-.15,.11)
  local function jawFrame(node)
   local target=holding and 1 or 0
   jawOpen+=math.clamp(target-jawOpen,-.15,.15)
   return headFrame(node)*CFrame.new(jawJoint)*CFrame.Angles(-.37*jawOpen,0,0)*CFrame.new(-jawJoint)
  end
  if not makeMesh(headAnchor,jaw,jawFaces,"BLY_DragonJaw",jawFrame) then return end
  local nativeWingCount=0
  for _,side in {-1,1} do
   local pivot=point(side*.34,.31,-.38)
   local node=anchorFor({"wingupper","upperwing","wing","wrist"},pivot+point(side*.7,0,0),side) or root
   if node~=root then nativeWingCount+=1 end
   local bind=bound(root,pivot)
   local sample=node~=root and pose(node):VectorToObjectSpace(body.RightVector*side)
   local vertices,faces={},{}
   local function wing(x,y,z) return point(side*x,y,z) end
   local base=wing(0,0,0)
   local elbow=wing(1.18,.46,.20)
   local wrist=wing(2.69,.98,.29)
   local fingers={wing(5.31,.05,1.94),wing(4.23,-.47,2.68),wing(3.12,-.74,3.0),
    wing(1.94,-.62,2.64),wing(.90,-.46,1.73),base}
   local web={wing(4.54,.17,1.81),wing(3.62,-.10,2.17),wing(2.45,-.24,2.17),
    wing(1.42,-.20,1.76),wing(.50,-.05,.79)}
   for panel,notch in web do
    local a,b=fingers[panel],fingers[panel+1]
    local function membrane(t,u)
     local bow=math.sin(math.pi*u)
     local edge=a:Lerp(b,u):Lerp(notch,bow*.90)
     return wrist:Lerp(edge,t)+Vector3.yAxis*((.22-.32*bow)*math.sin(math.pi*t)*unit)
    end
    local last
    local apex=vertex(vertices,wrist,coal)
    for row=1,13 do
     local t=row/13
     local current={}
     for column=0,15 do
      local u=column/15
      local grain=.5+.5*math.noise(t*12,u*14,panel)
      local striation=.5+.5*math.sin(u*91+t*10+grain*3)
      local warm=math.sin(math.pi*u)*math.sin(math.pi*t*.80)
      local color=coal:Lerp(leather,.13+warm*.68):Lerp(ember,(grain*.23+striation*.08)*warm)
      current[column+1]=vertex(vertices,membrane(t,u),color)
     end
     for i=1,15 do
      if last then
       face(faces,last[i],current[i],current[i+1],true)
       face(faces,last[i],current[i+1],last[i+1],true)
      else face(faces,apex,current[i],current[i+1],true) end
     end
     last=current
    end
    local spar,hem={},{}
    for i=0,8 do
     table.insert(spar,membrane(i/8,0))
     table.insert(hem,membrane(1,i/8))
    end
    tube(vertices,faces,spar,{.085,.074,.062,.050,.038,.026,.019,.012,.004},slate:Lerp(bronze,.25))
    tube(vertices,faces,hem,{.004,.011,.014,.016,.016,.016,.014,.011,.004},leather:Lerp(coal,.51))
    for branch=1,2 do
     local points={}
     for step=0,5 do
      local t=.28+step*.11
      local u=(branch==1 and .21 or .67)+math.sin(step*1.1+panel)*.058
      table.insert(points,membrane(t,u)+Vector3.yAxis*(unit*.011))
     end
     tube(vertices,faces,points,{.003,.009,.011,.010,.007,.002},bronze:Lerp(leather,.59))
    end
   end
   tube(vertices,faces,{wing(-.19,-.08,-.02),base,wing(.54,.19,.09),elbow,wing(1.93,.76,.23),wrist},
    {.19,.225,.165,.118,.087,.065},slate)
   for plate=0,5 do
    local t=plate/6
    local center=base:Lerp(elbow,t)+wing(0,.18-.075*t,0)
    ridge(vertices,faces,center,Vector3.yAxis,Vector3.xAxis*side,unit*(.21-.08*t),unit*.25,unit*.056,slate:Lerp(bronze,.17))
   end
   tube(vertices,faces,{wrist,wing(2.82,1.23,.20),wing(2.97,1.24,.04),wing(3.11,1.14,-.12)},
    {.082,.063,.030,.004},horn)
   local roll,sweep,phase=0,0,0
   local updated=os.clock()
   local function wingPose()
    local shoulder=bind(root)
    local now=os.clock()
    local dt=math.clamp(now-updated,0,.10)
    updated=now
    local targetRoll,targetSweep
    if sample and node:IsDescendantOf(model) then
     local outward=shoulder:VectorToObjectSpace(pose(node):VectorToWorldSpace(sample))
     targetRoll=math.clamp(math.atan2(outward.Y,math.abs(outward.X)+.10),-.78,.86)
     targetSweep=math.clamp(math.atan2(outward.Z,math.abs(outward.X)+.20),-.22,.34)
    else
     local moving=root.AssemblyLinearVelocity.Magnitude>5
     phase=(phase+dt*(moving and 7.2 or 1.8))%(2*math.pi)
     targetRoll=math.sin(phase)*(moving and .34 or .045)
     targetSweep=.06*math.cos(phase)
    end
    local blend=1-math.exp(-18*dt)
    roll+=(targetRoll-roll)*blend
    sweep+=(targetSweep-sweep)*blend
    return shoulder*CFrame.Angles(0,-side*sweep,side*roll)
   end
   if not makeMesh(root,vertices,faces,"BLY_DragonWing",wingPose) then return end
  end
  local floor=math.clamp((box.Position.Y-bounds.Y*.5-root.Position.Y)/unit,-1.9,-.49)
  for _,side in {-1,1} do
   local pivot=point(side*.38,floor+.35,.54)
   local node=anchorFor({"ankle","foot","talon","toe","leg"},pivot,side) or root
   local legs,faces={},{}
   shell(legs,faces,rings({
    {0,.95,-.24,.25,.26},{side*.05,.66,-.17,.21,.22},{side*.075,.36,-.04,.15,.16},
    {side*.035,.13,.08,.105,.117},{0,-.16,.08,.11,.102},{0,-.26,-.025,.135,.109},
   }),13,true,true)
   for toe=-1,1 do
    local x=toe*.112
    tube(legs,faces,{point(x*.58,-.235,.01),point(x,-.30,-.16),point(x*1.42,-.325,-.32)},
     {.072,.065,.042},slate)
    tube(legs,faces,{point(x*1.41,-.317,-.28),point(x*1.47,-.31,-.39),point(x*1.5,-.359,-.51)},
     {.048,.033,.003},horn)
   end
   if not makeMesh(node,legs,faces,"BLY_DragonClaws",bound(node,pivot)) then return end
  end
  local tailAnchor=anchorFor({"tailbase","tailroot","tail"},point(0,-.23,1.05)) or root
  local tailBind=bound(tailAnchor,point(0,-.23,1.01))
  local tail,tailFaces={},{}
  local taper={}
  for i=0,18 do
   local t=i/18
   local center=point(-1.04*t^1.5,-.29*t+.36*t^4,3.66*t)
   local r=.253*(1-t)^1.45+.008
   table.insert(taper,{center,r,r*.88})
   if i>=1 and i<=15 then
    ridge(tail,tailFaces,center+point(0,r*.83,0),Vector3.yAxis,Vector3.zAxis,unit*r*.97,unit*.245,unit*(.21-.12*t),bronze)
   end
  end
  shell(tail,tailFaces,taper,12,true,true)
  local function tailFrame(node)
   return tailBind(node)*CFrame.Angles(0,math.sin(os.clock()*2.35)*.075,0)
  end
  if not makeMesh(tailAnchor,tail,tailFaces,"BLY_DragonTail",tailFrame) then return end
  if not isCurrent() then return end
  local mouth=attachment(skull,CFrame.new(point(0,-.21,-.91)-headCenter))
  local flame=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/fire_main.dds",Rate=58,Enabled=false,
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(9,8),
   Speed=NumberRange.new(9*unit,15*unit),Lifetime=NumberRange.new(.32,.53),Drag=1.4,
   LightEmission=.95,LightInfluence=0,Acceleration=Vector3.yAxis*1.15,
   Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,225,139)),
    ColorSequenceKeypoint.new(.36,orange),ColorSequenceKeypoint.new(1,Color3.fromRGB(130,27,17))}),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.17*unit),NumberSequenceKeypoint.new(.42,.59*unit),
    NumberSequenceKeypoint.new(1,.27*unit)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.28),NumberSequenceKeypoint.new(.27,.14),
    NumberSequenceKeypoint.new(1,1)}),
  },mouth)
  local sparks=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=27,Enabled=false,
   EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(18,14),Speed=NumberRange.new(9*unit,16*unit),
   Lifetime=NumberRange.new(.23,.46),Drag=2.3,LightEmission=1,LightInfluence=0,
   Color=ColorSequence.new(Color3.fromRGB(255,212,105),orange),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.074*unit),NumberSequenceKeypoint.new(1,0)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.07),NumberSequenceKeypoint.new(1,1)}),
  },mouth)
  local light=new("PointLight",{Color=orange,Range=math.clamp(unit*4,2,11),Brightness=.95,Enabled=false,Shadows=false},mouth)
  local function breathe(value)
   if value and (not isCurrent() or UIS:GetFocusedTextBox()) then return end
   if holding==value then return end
   holding=value
   flame.Enabled=value
   sparks.Enabled=value
   light.Enabled=value
   if value then flame:Emit(7) sparks:Emit(4) end
  end
  local began=UIS.InputBegan:Connect(function(input,processed)
   if not processed and input.KeyCode==Enum.KeyCode.E then breathe(true) end
  end)
  local ended=UIS.InputEnded:Connect(function(input)
   if input.KeyCode==Enum.KeyCode.E then breathe(false) end
  end)
  local unfocused=UIS.WindowFocusReleased:Connect(function() breathe(false) end)
  local textFocus=UIS.TextBoxFocused:Connect(function() breathe(false) end)
  table.insert(restoreFur,function()
   breathe(false)
   began:Disconnect()
   ended:Disconnect()
   unfocused:Disconnect()
   textFocus:Disconnect()
  end)
  local hiddenParts={}
  local function hideBirdPart(part)
   if part:IsA("BasePart") and hiddenParts[part]==nil then
    hiddenParts[part]=part.LocalTransparencyModifier
    part.LocalTransparencyModifier=1
   end
  end
  local function restoreBirdPart(part)
   local previous=hiddenParts[part]
   if previous~=nil then
    hiddenParts[part]=nil
    if part.LocalTransparencyModifier==1 then part.LocalTransparencyModifier=previous end
   end
  end
  local added=model.DescendantAdded:Connect(hideBirdPart)
  local removing=model.DescendantRemoving:Connect(restoreBirdPart)
  for _,part in model:GetDescendants() do hideBirdPart(part) end
  local renderKey="BLY_DragonVisibility"
  table.insert(restoreFur,function()
   Run:UnbindFromRenderStep(renderKey)
   added:Disconnect()
   removing:Disconnect()
   for part in hiddenParts do restoreBirdPart(part) end
  end)
  Run:BindToRenderStep(renderKey,Enum.RenderPriority.Last.Value+1,function()
   if not isCurrent() then return end
   for part in hiddenParts do
    if part.LocalTransparencyModifier~=1 then part.LocalTransparencyModifier=1 end
   end
  end)
  return nativeWingCount
 end
 local function galaxyPixel(u,v)
  local x,y=(u-.49)*2.65,(v-.48)*2.82
  local radius=math.sqrt(x*x+y*y*2.1)
  local spiral=math.atan2(y*1.45,x)-radius*5.8
  local grain=math.noise(u*9,v*9,11)*.68+math.noise(u*23,v*23,6)*.32
  local haze=math.clamp(.43+grain*1.25,0,1)
  local arm=(.5+.5*math.cos(spiral*2+grain*.95))^4*math.exp(-radius*2.32)
  local core=math.exp(-radius*radius*34)*.31
  local plume=(.5+.5*math.sin(u*12-v*7+grain*1.45))^2
  local mist=arm*.58+haze*.25+plume*.13
  local ix,iy=math.floor(u*152),math.floor(v*152)
  local seed=(ix*73856093+iy*19349663)%9973
  local star=seed%137<3 and math.max(0,1-2.3*math.sqrt((u*152-ix-.5)^2+(v*152-iy-.5)^2)) or 0
  local blue=.5+.5*math.sin(spiral+1.1)
  return math.min(255,27+mist*(93-39*blue)+core*193+star*183),
   math.min(255,23+mist*(62+43*blue)+core*155+star*196),
   math.min(255,61+mist*165+core*161+star*180),
   math.min(255,13+mist*69+core*121+star*186)
 end
 local function makeAuroraRhino(model,root,assets,isCurrent)
  local head=findAnimalHead(model)
  if not head then return false end
  local violet=Color3.fromRGB(194,92,255)
  local cyan=Color3.fromRGB(96,236,255)
  local buildDecoration=createDecorationBuilder(model,assets,isCurrent)
  local count=0
  for _,horn in model:GetDescendants() do
   if not horn:IsA("MeshPart") or horn.Transparency>=.95 or not horn.Name:lower():find("horn",1,true) then continue end
   count+=1
   local frame,size=horn.CFrame,horn.Size
   local axes={{axis=Vector3.xAxis,length=size.X},{axis=Vector3.yAxis,length=size.Y},{axis=Vector3.zAxis,length=size.Z}}
   table.sort(axes,function(a,b) return a.length>b.length end)
   local longAxis,wideAxis,depthAxis=axes[1],axes[2],axes[3]
   local params=RaycastParams.new()
   params.FilterType=Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances={horn}
   params.RespectCanCollide=false
   local function sample(t,s,face)
    local localPoint=longAxis.axis*(t*longAxis.length*.44)+wideAxis.axis*(s*wideAxis.length*.38)+depthAxis.axis*(face*depthAxis.length*.8)
    local origin=frame:PointToWorldSpace(localPoint)
    local direction=frame:VectorToWorldSpace(-depthAxis.axis*face)
    local hit=workspace:Raycast(origin,direction*(depthAxis.length*2+size.Magnitude*.35),params)
    if hit and hit.Instance==horn then
     return frame:PointToObjectSpace(hit.Position+hit.Normal*.008),frame:VectorToObjectSpace(hit.Normal)
    end
    return localPoint,depthAxis.axis*face
   end
   local verts,faces={},{}
   local function facet(a,b,c,color)
    local start=#verts
    table.insert(verts,{a,color}) table.insert(verts,{b,cyan}) table.insert(verts,{c,violet})
    table.insert(faces,{start+1,start+2,start+3}) table.insert(faces,{start+1,start+3,start+2})
   end
   local tRadius=longAxis.length*.038
   local sRadius=wideAxis.length*.095
   for index=1,5 do
    local t=-.34+(index-1)*.17
    local s=(index%2==0 and .17 or -.15)
    for _,face in {-1,1} do
     local c,n=sample(t,s,face)
     local a=sample(t-tRadius/longAxis.length,s-sRadius/wideAxis.length,face)
     local b=sample(t+tRadius/longAxis.length,s-sRadius/wideAxis.length,face)
     local d=sample(t+tRadius/longAxis.length,s+sRadius/wideAxis.length,face)
     local e=sample(t-tRadius/longAxis.length,s+sRadius/wideAxis.length,face)
     local tip=c+n*math.max(depthAxis.length*.13,size.Magnitude*.018)
     facet(a,b,tip,index%2==0 and cyan or violet)
     facet(b,d,tip,violet)
     facet(d,e,tip,cyan)
     facet(e,a,tip,index%2==0 and violet or cyan)
    end
   end
   if isCurrent() then buildDecoration(horn,verts,faces,"BLY_AuroraHornFacet",function(part) return part.CFrame end,Enum.Material.Neon) end
   local light=new("PointLight",{Color=cyan,Brightness=.46,Range=math.clamp(size.Magnitude*1.35,2,5),Shadows=false},attachment(horn,CFrame.identity))
   task.spawn(function() while isCurrent() and light.Parent do light.Brightness=.34+.20*(.5+.5*math.sin(os.clock()*2.1)) task.wait(.06) end end)
  end
  local headLight=new("PointLight",{Color=violet,Brightness=.35,Range=math.clamp(head.Size.Magnitude*1.5,2,6),Shadows=false},attachment(head,CFrame.new(0,head.Size.Y*.18,0)))
  local emitter=new("ParticleEmitter",{Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=7,
   Color=ColorSequence.new(violet,cyan),LightEmission=1,LightInfluence=0,Lifetime=NumberRange.new(.85,1.65),
   Speed=NumberRange.new(.10,.34),SpreadAngle=Vector2.new(170,170),Drag=1.8,RotSpeed=NumberRange.new(-45,45),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.035),NumberSequenceKeypoint.new(.38,.15),NumberSequenceKeypoint.new(1,0)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.45,.32),NumberSequenceKeypoint.new(1,1)})},attachment(root,CFrame.new(0,.2,0)))
  task.spawn(function() while isCurrent() and headLight.Parent do headLight.Brightness=.24+.18*(.5+.5*math.sin(os.clock()*1.65)) task.wait(.06) end end)
  local bodyParts={}
  for _,part in model:GetDescendants() do
   local name=part.Name:lower()
   if part:IsA("BasePart") and part.Transparency<.95 and not name:find("horn",1,true)
    and not name:find("head",1,true) and not name:find("eye",1,true) and not name:find("nose",1,true) then
    table.insert(bodyParts,part)
   end
  end
  local bodyBasis=CFrame.lookAt(Vector3.zero,root.CFrame:VectorToObjectSpace(Vector3.new((head.Position-root.Position).X,0,(head.Position-root.Position).Z)).Unit)
  local bodyFrame=root.CFrame*bodyBasis
  local low=Vector3.new(math.huge,math.huge,math.huge)
  local high=Vector3.new(-math.huge,-math.huge,-math.huge)
  for _,part in bodyParts do for _,sx in {-1,1} do for _,sy in {-1,1} do for _,sz in {-1,1} do
   local p=bodyFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(sx*part.Size.X*.5,sy*part.Size.Y*.5,sz*part.Size.Z*.5)))
   low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
   high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
  end end end end
  if #bodyParts>0 then
   local bounds=high-low
   local center=(low+high)*.5
   local halfWidth=math.max(bounds.X*.5,.2)
   local params=RaycastParams.new()
   params.FilterType=Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances=bodyParts
   params.RespectCanCollide=false
   local function bodyPoint(side,y,z)
    local origin=bodyFrame:PointToWorldSpace(Vector3.new(side*halfWidth*1.4,y,z))
    local hit=workspace:Raycast(origin,-bodyFrame.RightVector*(side*halfWidth*2.8),params)
    if hit then return bodyFrame:PointToObjectSpace(hit.Position+hit.Normal*.018) end
    return Vector3.new(side*halfWidth,y,z)
   end
   local verts,faces={},{}
   local unit=math.max(bounds.Y*.018,.035)
   for _,side in {-1,1} do for index=1,3 do
    local z=center.Z+(index-2)*bounds.Z*.22
    local y=center.Y+bounds.Y*.06
    local dx=bounds.Z*.052
    local dy=bounds.Y*.065
    local a={bodyPoint(side,y-dy,z-dx),bodyPoint(side,y,z),bodyPoint(side,y+dy,z+dx)}
    local b={bodyPoint(side,y-dy,z+dx),bodyPoint(side,y,z),bodyPoint(side,y+dy,z-dx)}
    addRib(verts,faces,a,{unit*.18,unit*.9,unit*.12},index%2==0 and violet or cyan)
    addRib(verts,faces,b,{unit*.12,unit*.9,unit*.18},index%2==0 and cyan or violet)
   end end
   if isCurrent() then buildDecoration(root,verts,faces,"BLY_AuroraRhinoCrosses",function(part) return part.CFrame*bodyBasis end,Enum.Material.Neon) end
  end
  return count>0
 end
 local function makeMirageElephant(model,root,assets,isCurrent)
  local head=findAnimalHead(model)
  if not head then return false end
  local cyan=Color3.fromRGB(40,232,222)
  local ice=Color3.fromRGB(155,255,247)
  local buildDecoration=createDecorationBuilder(model,assets,isCurrent)
  local ears={}
  for _,part in model:GetDescendants() do
   if part:IsA("MeshPart") and part.Transparency<.95 then
    local name=part.Name:lower()
    local delta=part.Position-head.Position
    local side=math.abs(delta:Dot(root.CFrame.RightVector))
    local depth=math.abs(delta:Dot(root.CFrame.LookVector))
    local nearHead=math.abs(delta.Y)<head.Size.Y*.95 and depth<head.Size.Z*1.2
    if name:find("ear",1,true) or (nearHead and side>head.Size.X*.38 and part.Size.Magnitude<head.Size.Magnitude*1.65) then
     table.insert(ears,part)
    end
   end
  end
  for _,ear in ears do
   local verts,faces={},{}
   local frame,size=ear.CFrame,ear.Size
   local params=RaycastParams.new()
   params.FilterType=Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances={ear}
   params.RespectCanCollide=false
   local function earPoint(x,y)
    local origin=frame.Position+frame.RightVector*(x*size.X*.43)+frame.UpVector*(y*size.Y*.43)+frame.LookVector*(size.Magnitude*.8)
    local hit=workspace:Raycast(origin,-frame.LookVector*(size.Magnitude*1.6),params)
    if hit and hit.Instance==ear then return frame:PointToObjectSpace(hit.Position+hit.Normal*.025) end
    return Vector3.new(x*size.X*.43,y*size.Y*.43,-size.Z*.5-.025)
   end
   local scale=math.max(size.Magnitude*.018,.025)
   local main={earPoint(-.48,-.43),earPoint(-.30,-.23),earPoint(-.10,-.04),earPoint(.10,.12),earPoint(.32,.31),earPoint(.48,.43)}
   addRib(verts,faces,main,{scale*.18,scale*.65,scale,scale*.82,scale*.55,scale*.08},ice)
   for _,branch in {
    {earPoint(-.31,-.23),earPoint(-.12,-.34),earPoint(.12,-.39),earPoint(.36,-.35)},
    {earPoint(-.10,-.04),earPoint(-.30,.10),earPoint(-.44,.29)},
    {earPoint(.10,.12),earPoint(.04,.34),earPoint(-.04,.47)},
    {earPoint(.30,.30),earPoint(.47,.20),earPoint(.50,.02)},
   } do
    local radii={}
    for i=1,#branch do radii[i]=scale*((i==1 or i==#branch) and .06 or .36) end
    addRib(verts,faces,branch,radii,cyan)
   end
   if isCurrent() then
    buildDecoration(ear,verts,faces,"BLY_MirageEarVeins",function(part) return part.CFrame end,Enum.Material.Neon)
   end
  end
  local node=attachment(head,CFrame.new(0,0,0))
  new("PointLight",{Color=cyan,Brightness=.65,Range=math.clamp(head.Size.Magnitude*1.5,2,6),Shadows=false},node)
  new("ParticleEmitter",{Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=5,
   Color=ColorSequence.new(ice,cyan),LightEmission=1,LightInfluence=0,Lifetime=NumberRange.new(.7,1.35),
   Speed=NumberRange.new(.12,.42),SpreadAngle=Vector2.new(160,160),Drag=1,
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.035),NumberSequenceKeypoint.new(.35,.12),NumberSequenceKeypoint.new(1,0)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(.55,.35),NumberSequenceKeypoint.new(1,1)})},attachment(root,CFrame.new(0,.2,0)))
  return #ears>0
 end
 local function makeEmeraldLeopard(model,root,isCurrent)
  local head=findAnimalHead(model)
  if not head then return false end
  local mint=Color3.fromRGB(119,255,192)
  local light=new("PointLight",{Color=mint,Brightness=.42,Range=math.clamp(head.Size.Magnitude*1.7,2,6),Shadows=false},
   attachment(head,CFrame.new(0,head.Size.Y*.12,0)))
  new("ParticleEmitter",{Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=6,
   Color=ColorSequence.new(Color3.fromRGB(53,204,114),mint),LightEmission=.95,LightInfluence=0,
   Lifetime=NumberRange.new(.75,1.5),Speed=NumberRange.new(.10,.38),SpreadAngle=Vector2.new(170,170),
   Drag=1.6,RotSpeed=NumberRange.new(-38,38),Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.035),
    NumberSequenceKeypoint.new(.4,.13),NumberSequenceKeypoint.new(1,0)}),Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.5,.35),NumberSequenceKeypoint.new(1,1),
   })},attachment(root,CFrame.new(0,.15,0)))
  task.spawn(function() while isCurrent() and light.Parent do light.Brightness=.30+.2*(.5+.5*math.sin(os.clock()*1.8)) task.wait(.06) end end)
  return true
 end
 local function makePinkElephant(model,root,assets,isCurrent)
  if not isCurrent() then return false end
  local head=findAnimalHead(model) or root
  local forward=root.CFrame.LookVector
  local delta=head.Position-root.Position
  if Vector3.new(delta.X,0,delta.Z).Magnitude>.3 then forward=Vector3.new(delta.X,0,delta.Z).Unit end
  local basis=CFrame.lookAt(Vector3.zero,forward)
  local modelFrame=CFrame.new(root.Position)*basis
  local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
  local tusks,headBone={},nil
  local tuskBones={}
  for _,part in model:GetDescendants() do
   local name=part.Name:lower()
   if part:IsA("Bone") then
    if name=="head" or name=="headbone" then headBone=part end
    if name:find("tusk",1,true) then table.insert(tuskBones,part) end
   elseif part:IsA("BasePart") and part.Transparency<.95 then
    if name:find("tusk",1,true) then table.insert(tusks,part) end
    for _,sx in {-1,1} do for _,sy in {-1,1} do for _,sz in {-1,1} do
     local p=modelFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size*Vector3.new(sx,sy,sz)*.5))
     low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
     high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
    end end end
   end
  end
  local width=math.clamp((high.X-low.X)*.43,.8,8)
  local function anchorFrame(anchor)
   return anchor:IsA("Bone") and anchor.TransformedWorldCFrame or anchor.CFrame
  end
  local decorations={}
  local function bow(anchor,position,scale,name)
   local frame=CFrame.new(position)*basis
   local relative=anchorFrame(anchor):ToObjectSpace(frame)
   local pieces={}
   local function piece(size,offset,rotation,color,mesh)
    local part=new("Part",{Name=name,Size=size*scale,Color=color,Material=Enum.Material.SmoothPlastic,
     Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false},workspace)
    if mesh then new("SpecialMesh",{MeshType=mesh},part) end
    local localFrame=CFrame.new(offset*scale)*CFrame.Angles(0,0,rotation)
    part.CFrame=frame*localFrame
    table.insert(effects,part)
    table.insert(pieces,{part=part,offset=localFrame})
   end
   local bright=Color3.fromRGB(255,105,181)
   local rim=Color3.fromRGB(255,156,207)
   for _,side in {-1,1} do
    piece(Vector3.new(.76,.47,.22),Vector3.new(side*.40,.09,0),side*.24,bright,Enum.MeshType.Sphere)
    piece(Vector3.new(.57,.13,.03),Vector3.new(side*.43,.12,-.115),side*.24,rim,Enum.MeshType.Sphere)
    piece(Vector3.new(.22,.55,.075),Vector3.new(side*.21,-.36,.035),side*.27,bright)
   end
   piece(Vector3.new(.25,.30,.28),Vector3.new(0,.015,-.045),0,rim,Enum.MeshType.Sphere)
   table.insert(decorations,{anchor=anchor,relative=relative,pieces=pieces})
  end
  local headAnchor=headBone or head
  local candidates={}
  for _,tusk in tusks do
   local length=math.max(tusk.Size.X,tusk.Size.Y,tusk.Size.Z)
   local axis=tusk.Size.X>=tusk.Size.Y and tusk.Size.X>=tusk.Size.Z and Vector3.xAxis
    or tusk.Size.Y>=tusk.Size.Z and Vector3.yAxis or Vector3.zAxis
   for _,sign in {-1,1} do
    local p=tusk.CFrame:PointToWorldSpace(axis*length*.43*sign)
    local localPoint=modelFrame:PointToObjectSpace(p)
    local side=localPoint.X>=0 and 1 or -1
    local score=-localPoint.Z-localPoint.Y*.3
    if not candidates[side] or score>candidates[side].score then candidates[side]={anchor=tusk,position=p,score=score} end
   end
  end
  for _,side in {1} do
   local candidate=candidates[side]
   local closestBone,closestDistance=nil,math.huge
   for _,bone in tuskBones do
    local p=anchorFrame(bone).Position
    if modelFrame:PointToObjectSpace(p).X>=0 then
     local distance=candidate and (p-candidate.position).Magnitude or (p-head.Position).Magnitude*-1
     if distance<closestDistance then closestBone,closestDistance=bone,distance end
    end
   end
   if closestBone then
    candidate={anchor=closestBone,position=candidate and candidate.position or anchorFrame(closestBone).Position}
   end
   local fallback=anchorFrame(headAnchor).Position+basis.RightVector*(side*width*.34)-Vector3.yAxis*(width*.46)+forward*(width*.48)
   bow(candidate and candidate.anchor or headAnchor,(candidate and candidate.position or fallback)+forward*(width*.04),width*.21,
    "BLY_PinkRightTuskBow")
  end
  geometryConnection=Run.RenderStepped:Connect(function()
   if not isCurrent() then return end
   for _,item in decorations do
    if item.anchor.Parent then
     local frame=anchorFrame(item.anchor)*item.relative
     for _,piece in item.pieces do if piece.part.Parent then piece.part.CFrame=frame*piece.offset end end
    end
   end
  end)
  local node=attachment(root,CFrame.new(0,.2,0))
  new("ParticleEmitter",{Name="BLY_PinkSparkles",Texture="rbxasset://textures/particles/sparkles_main.dds",
   Rate=4,Color=ColorSequence.new(Color3.fromRGB(255,205,229),Color3.fromRGB(255,133,184)),
   LightEmission=.35,LightInfluence=.2,Lifetime=NumberRange.new(.65,1.15),
   Speed=NumberRange.new(.12,.40),SpreadAngle=Vector2.new(170,170),Drag=1.5,
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.035),NumberSequenceKeypoint.new(.4,.10),NumberSequenceKeypoint.new(1,0)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,1)})},node)
  new("PointLight",{Color=Color3.fromRGB(255,170,207),Brightness=.18,Range=math.clamp(head.Size.Magnitude,2,5),Shadows=false},attachment(head,CFrame.identity))
  return true
 end
 local function makeRoyalLion(model,root,assets,isCurrent)
  local head=findAnimalHead(model)
  if not head then return false end
  local forward=head.Position-root.Position
  forward=Vector3.new(forward.X,0,forward.Z)
  forward=forward.Magnitude>.2 and forward.Unit or root.CFrame.LookVector
  local headBasis=head.CFrame:ToObjectSpace(CFrame.lookAt(head.Position,head.Position+forward))
  local unit=math.clamp(root.Size.Magnitude/3,.6,2.5)
  local width=math.max(head.Size.X,head.Size.Z*.75)*.90
  local height=head.Size.Y*.80
  local gold=Color3.fromRGB(230,169,54)
  local bright=Color3.fromRGB(255,221,122)
  local shade=Color3.fromRGB(151,94,28)
  local faceFrame=head.CFrame*headBasis
  local maskParams=RaycastParams.new()
  maskParams.FilterType=Enum.RaycastFilterType.Include
  maskParams.FilterDescendantsInstances={head}
  maskParams.RespectCanCollide=false
  local vertices,faces={},{}
  local function point(x,y,offset)
   local faceY=y-.32
   local dx,dy=x*width,faceY*height
   local origin=faceFrame.Position+faceFrame.RightVector*dx+faceFrame.UpVector*dy+faceFrame.LookVector*(head.Size.Magnitude*.85)
   local hit=workspace:Raycast(origin,-faceFrame.LookVector*(head.Size.Magnitude*1.7),maskParams)
   if hit and hit.Instance==head then
    return faceFrame:PointToObjectSpace(hit.Position+hit.Normal*(unit*.012+(offset or 0)*unit))
   end
   local curve=head.Size.Z*(x*x*.16+faceY*faceY*.10)
   return Vector3.new(dx,dy,-head.Size.Z*.50+curve-unit*.035-(offset or 0)*unit)
  end
  local function triangle(a,b,c)
   table.insert(faces,{a,b,c})
   table.insert(faces,{a,c,b})
  end
  local function surfaceBand(path,thickness,color)
   local left,right={},{}
   for index,p in path do
    local previous=path[math.max(1,index-1)]
    local following=path[math.min(#path,index+1)]
    local dx=(following[1]-previous[1])*width
    local dy=(following[2]-previous[2])*height
    local length=math.max(math.sqrt(dx*dx+dy*dy),.001)
    local nx,ny=-dy/length,dx/length
    local half=width*thickness*.5
    left[index]=point(p[1]+nx*half/width,p[2]+ny*half/height,.014)
    right[index]=point(p[1]-nx*half/width,p[2]-ny*half/height,.014)
   end
   local ids={}
   for index=1,#path do
    ids[index]={#vertices+1,#vertices+2}
    table.insert(vertices,{left[index],color})
    table.insert(vertices,{right[index],shade})
   end
   for index=1,#path-1 do
    triangle(ids[index][1],ids[index][2],ids[index+1][1])
    triangle(ids[index][2],ids[index+1][2],ids[index+1][1])
   end
  end
  for _,side in {-1,1} do
   surfaceBand({{side*.09,.22},{side*.28,.235},{side*.43,.19},{side*.48,.10},
    {side*.47,-.035},{side*.39,-.15},{side*.25,-.18},{side*.11,-.12},{side*.07,-.015},{side*.09,.22}},.052,gold)
  end
  surfaceBand({{-.48,.18},{-.39,.25},{-.25,.29},{-.12,.305},{0,.31},{.12,.305},{.25,.29},{.39,.25},{.48,.18}},.065,bright)
  surfaceBand({{0,.245},{0,.17},{0,.09},{0,.01},{0,-.07},{0,-.15},{0,-.22},{0,-.28}},.048,gold)
  surfaceBand({{-.39,-.13},{-.30,-.21},{-.17,-.255},{0,-.27},{.17,-.255},{.30,-.21},{.39,-.13}},.032,shade)
  local gemCenter=point(0,.315,.04)
  local gemCorners={point(-.024,.315,.04),point(0,.345,.04),point(.024,.315,.04),point(0,.285,.04)}
  for i=1,4 do
   local start=#vertices
   table.insert(vertices,{gemCorners[i],gold})
   table.insert(vertices,{gemCorners[i%4+1],bright})
   table.insert(vertices,{gemCenter,shade})
   triangle(start+1,start+2,start+3)
  end
  local buildDecoration=createDecorationBuilder(model,assets,isCurrent)
  local mask,center=buildDecoration(head,vertices,faces,"BLY_RoyalGoldMask",function(part)
   return part.CFrame*headBasis
  end,Enum.Material.Metal)
  if not mask or not isCurrent() then return false end
  local jewel=attachment(mask,CFrame.new(gemCenter-center))
  new("PointLight",{Color=bright,Brightness=.24,Range=math.clamp(unit*1.3,1,3),Shadows=false},jewel)
  local localForward=root.CFrame:VectorToObjectSpace(forward)
  local bodyBasis=CFrame.lookAt(Vector3.zero,localForward)
  local bodyFrame=root.CFrame*bodyBasis
  local bodyParts,allBodyParts={},{}
  for _,part in model:GetDescendants() do
   if part:IsA("BasePart") and part.Transparency<.95 then
    table.insert(allBodyParts,part)
    if part:IsA("MeshPart") and part.Name:lower():find("mane",1,true) then table.insert(bodyParts,part) end
   end
  end
  if #bodyParts==0 then bodyParts=allBodyParts end
  local low=Vector3.new(math.huge,math.huge,math.huge)
  local high=Vector3.new(-math.huge,-math.huge,-math.huge)
  for _,part in bodyParts do
   for _,sx in {-1,1} do for _,sy in {-1,1} do for _,sz in {-1,1} do
    local world=part.CFrame:PointToWorldSpace(Vector3.new(sx*part.Size.X*.5,sy*part.Size.Y*.5,sz*part.Size.Z*.5))
    local p=bodyFrame:PointToObjectSpace(world)
    low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
    high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
   end end end
  end
  local bodyBounds=high-low
  local bodyCenter=(low+high)*.5
  local bodyParams=RaycastParams.new()
  bodyParams.FilterType=Enum.RaycastFilterType.Include
  bodyParams.FilterDescendantsInstances=bodyParts
  bodyParams.RespectCanCollide=false
  local halfWidth=math.max(bodyBounds.X*.5,.15)
  local function flankPoint(side,yOffset,zOffset)
   local y=bodyCenter.Y+yOffset*bodyBounds.Y
   local zPos=bodyCenter.Z+zOffset*bodyBounds.Z
   local start=bodyFrame:PointToWorldSpace(Vector3.new(side*(halfWidth*1.45),y,zPos))
   local hit=workspace:Raycast(start,-bodyFrame.RightVector*(side*halfWidth*2.9),bodyParams)
   if hit then return bodyFrame:PointToObjectSpace(hit.Position+hit.Normal*(unit*.035)) end
   return Vector3.new(side*halfWidth,y,zPos)
  end
  local engravingVertices,engravingFaces={},{}
  for _,side in {-1,1} do
   local diamond={flankPoint(side,.18,-.10),flankPoint(side,.04,-.20),
    flankPoint(side,-.10,-.10),flankPoint(side,.04,.015),flankPoint(side,.18,-.10)}
   addRib(engravingVertices,engravingFaces,diamond,{unit*.014,unit*.060,unit*.018,unit*.060,unit*.014},bright)
   local sweep={flankPoint(side,.19,-.20),flankPoint(side,.13,-.12),flankPoint(side,.055,-.035),
    flankPoint(side,-.04,.055),flankPoint(side,-.14,.14)}
   addRib(engravingVertices,engravingFaces,sweep,{unit*.014,unit*.052,unit*.064,unit*.048,unit*.014},gold)
   local accent={flankPoint(side,.11,-.13),flankPoint(side,.19,-.06),flankPoint(side,.22,.005)}
   addRib(engravingVertices,engravingFaces,accent,{unit*.012,unit*.045,unit*.012},shade)
  end
  if isCurrent() then
   buildDecoration(root,engravingVertices,engravingFaces,"BLY_RoyalBodyEngraving",function(part)
    return part.CFrame*bodyBasis
   end,Enum.Material.Metal)
  end
  local scale=math.clamp(root.Size.Magnitude/3,.6,2.5)
  local motes={}
  for i=1,18 do
   local bead=new("Part",{Name="BLY_RoyalGoldMote",Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,
    CastShadow=false,Shape=Enum.PartType.Ball,Material=Enum.Material.Neon,
    Color=i%4==0 and bright or gold,Size=Vector3.one*(.045+(i%3)*.018)*scale,
    Transparency=.18},workspace)
   table.insert(effects,bead)
   motes[i]=bead
  end
  local spark=attachment(root,CFrame.new(0,.15*scale,0))
  new("ParticleEmitter",{Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=4,
   Color=ColorSequence.new(bright,gold),LightEmission=.95,LightInfluence=0,
   Lifetime=NumberRange.new(.55,1.05),Speed=NumberRange.new(.2,.68),SpreadAngle=Vector2.new(160,160),Drag=1.8,
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.055*scale),NumberSequenceKeypoint.new(.35,.13*scale),NumberSequenceKeypoint.new(1,0)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.18),NumberSequenceKeypoint.new(.42,.35),NumberSequenceKeypoint.new(1,1)})},spark)
  local connection=Run.RenderStepped:Connect(function()
   if not isCurrent() then return end
   local now=os.clock()
   for i,bead in motes do
    local angle=now*.48+i*math.pi*(3-math.sqrt(5))
    local band=(i%3)-1
    local radius=(1.05+(i%5)*.16)*scale
    local localPoint=Vector3.new(math.cos(angle)*radius,band*.64*scale+math.sin(now*.7+i)*.12*scale,
     math.sin(angle)*radius*1.25)
    bead.Position=root.CFrame:PointToWorldSpace(localPoint)
    bead.Transparency=.12+.38*(.5+.5*math.sin(now*2.1+i))
   end
  end)
  table.insert(restoreFur,function() connection:Disconnect() end)
  return true
 end
 local function makeGalaxyLion(model,root,assets,isCurrent)
  local violet=Color3.fromRGB(140,93,255)
  local blue=Color3.fromRGB(77,182,255)
  local pearl=Color3.fromRGB(235,230,255)
  local indigo=Color3.fromRGB(17,10,53)
  local whiteEye=Color3.new(1,1,1)
  local head=findAnimalHead(model) or root
  local scale=math.clamp(root.Size.Magnitude/3,.6,2.5)
  local holder=new("Folder",{Name="BLY_GalaxyLion"},workspace)
  table.insert(effects,holder)
  local function node(parent,name,material,color,size,transparency)
   return new("Part",{Name=name,Anchored=true,CanCollide=false,CanQuery=false,CanTouch=false,
    CastShadow=false,Material=material,Color=color,Transparency=transparency or 0,Size=size},parent)
  end
  local function spark(parent,color,size)
   local bead=node(parent,"BLY_Star",Enum.Material.Neon,color,Vector3.one*size)
   bead.Shape=Enum.PartType.Ball
   return bead
  end
  local function orbit(parent,radiusX,radiusY,width,color,transparency,quarters)
   local center=node(parent,"BLY_Orbit",Enum.Material.SmoothPlastic,pearl,Vector3.one*.1,1)
   local points={}
   for i=0,3 do
    local a=i*math.pi/2
    local position=Vector3.new(radiusX*math.cos(a),radiusY*math.sin(a),0)
    local tangent=Vector3.new(-radiusX*math.sin(a),radiusY*math.cos(a),0)
    points[i+1]=new("Attachment",{CFrame=CFrame.fromMatrix(position,tangent.Unit,Vector3.zAxis)},center)
   end
   for i=1,quarters or 4 do
    local handle=(i%2==1 and radiusY or radiusX)*.55228475
    local nextHandle=(i%2==1 and radiusX or radiusY)*.55228475
    new("Beam",{Attachment0=points[i],Attachment1=points[i%4+1],CurveSize0=handle,CurveSize1=nextHandle,
     Width0=width,Width1=width,Segments=12,Color=ColorSequence.new(color),LightEmission=1,
     Transparency=NumberSequence.new(transparency or .10),FaceCamera=true},center)
   end
   return center
  end
  local halo=orbit(holder,1.04*scale,.66*scale,.021*scale,pearl,.22)
  local haloTrail=orbit(holder,1.04*scale,.66*scale,.069*scale,Color3.fromRGB(150,146,255),.85)
  local arcColor=Color3.fromRGB(182,108,255)
  local violetArc=orbit(holder,1.17*scale,.63*scale,.037*scale,arcColor,.12,2)
  violetArc.Name="BLY_VioletArc"
  local arcGlow=orbit(holder,1.17*scale,.63*scale,.102*scale,arcColor,.78,2)
  local footGlow=node(holder,"BLY_FootMist",Enum.Material.SmoothPlastic,indigo,Vector3.one*.1,1)
  local floorLight=new("PointLight",{Color=Color3.fromRGB(176,107,255),Range=7.4*scale,Brightness=1.36,Shadows=false},footGlow)
  local floorMist=new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/smoke_main.dds",Rate=7,Enabled=false,
   Lifetime=NumberRange.new(.82,1.38),Speed=NumberRange.new(.26*scale,.62*scale),
   SpreadAngle=Vector2.new(74,74),RotSpeed=NumberRange.new(-54,54),LightEmission=.75,LightInfluence=.2,
   Color=ColorSequence.new(Color3.fromRGB(80,94,255),Color3.fromRGB(197,125,255)),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.28*scale),NumberSequenceKeypoint.new(.55,1.78*scale),
    NumberSequenceKeypoint.new(1,2.05*scale)}),Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.33,.61),NumberSequenceKeypoint.new(1,1),
   }),
  },new("Attachment",{},footGlow))
  local floorParams=RaycastParams.new()
  floorParams.FilterType=Enum.RaycastFilterType.Exclude
  floorParams.FilterDescendantsInstances={model,holder}
  local floorHeight,groundCheck
  local dust,starOrigins={},{}
  local lastStarUpdate
  for i=1,42 do
   local star=spark(holder,i%4==0 and pearl or (i%2==0 and blue or violet),(.046+i%4*.014)*scale)
   if i%5==0 then
    local flare=new("BillboardGui",{Size=UDim2.fromScale(.33*scale,.33*scale),LightInfluence=0,MaxDistance=125},star)
    new("ImageLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
     Image="rbxasset://textures/particles/sparkles_main.dds",ImageColor3=star.Color,ImageTransparency=.24},flare)
   end
   dust[i]=star
  end
  new("PointLight",{Color=violet,Brightness=.49,Range=5.5*scale,Shadows=false},attachment(root,CFrame.new(0,.2*scale,0)))
  new("ParticleEmitter",{
   Texture="rbxasset://textures/particles/sparkles_main.dds",Rate=13,Lifetime=NumberRange.new(.74,1.35),
   Speed=NumberRange.new(.21*scale,.54*scale),SpreadAngle=Vector2.new(160,160),LightEmission=1,LightInfluence=0,
   Color=ColorSequence.new(blue,pearl),Size=NumberSequence.new({
    NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.33,.12*scale),NumberSequenceKeypoint.new(1,0),
   }),Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.25,.19),NumberSequenceKeypoint.new(1,1),
   }),
  },attachment(head,CFrame.new(0,.18*scale,0)))
  local portal,sky,originalLight,enterHeight
  local lanterns,postEffects={},{}
  local galaxyOn=false
  local lighting=game:GetService("Lighting")
  local function closePortal()
   if portal then portal.folder:Destroy() portal=nil end
  end
  local function exitSky()
   for _,effect in postEffects do effect:Destroy() end
   table.clear(postEffects)
   if sky then sky:Destroy() sky=nil end
   if originalLight then
    for key,item in originalLight do
     pcall(function() if lighting[key]==item.applied then lighting[key]=item.previous end end)
    end
    originalLight=nil
   end
   table.clear(lanterns)
   galaxyOn=false
  end
  local function enterSky()
   closePortal()
   galaxyOn=true
   sky=new("Folder",{Name="BLY_GalaxyWorld"},holder)
   originalLight={}
   for key,value in {ClockTime=0.1,Brightness=.72,Ambient=Color3.fromRGB(38,24,72),
    OutdoorAmbient=Color3.fromRGB(38,39,82),ExposureCompensation=-.24} do
    pcall(function()
     local old=lighting[key]
     lighting[key]=value
     originalLight[key]={previous=old,applied=lighting[key]}
    end)
   end
   table.insert(postEffects,new("ColorCorrectionEffect",{Name="BLY_GalaxyGrade",TintColor=Color3.fromRGB(204,192,255),
    Saturation=-.29,Contrast=.14,Brightness=-.11},lighting))
   table.insert(postEffects,new("BloomEffect",{Name="BLY_GalaxyBloom",Intensity=.49,Size=32,Threshold=.81},lighting))
   for i=1,116 do
    local spread=i*.754877666
    local band=i%4==0
    local angle=spread*2*math.pi
    local y=band and .08+.28*math.sin(i*.88) or -.12+(i*.618033989%1)*1.08
    local direction=Vector3.new(math.cos(angle),y,math.sin(angle)).Unit
    local color=i%5==0 and pearl or (i%2==0 and violet or blue)
    local point=spark(sky,color,band and .94 or .45+(i%7)*.08)
    local mist
    if i<=9 then
     mist=new("BillboardGui",{Size=UDim2.fromScale(34+(i%3)*12,23+(i%4)*8),LightInfluence=0,
      MaxDistance=650,AlwaysOnTop=false},point)
     local glow=new("ImageLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
      Image="rbxasset://textures/particles/smoke_main.dds",ImageColor3=color,ImageTransparency=.69},mist)
     lanterns[i]={point=point,direction=direction,glow=glow}
    else
     lanterns[i]={point=point,direction=direction}
    end
   end
   feedback.Text="دخلت المجرة · اضغط Q للرجوع"
  end
  local function openPortal()
   if UIS:GetFocusedTextBox() or not isCurrent() then return end
   if galaxyOn then exitSky() feedback.Text="رجعت للسافانا · Q يفتح البوابة" return end
   if portal then closePortal() feedback.Text="البوابة مقفلة · Q يفتحها" return end
   local facing=head~=root and head.Position-root.Position or root.CFrame.LookVector
   facing=Vector3.new(facing.X,0,facing.Z)
   if facing.Magnitude<=.2 then facing=root.CFrame.LookVector*Vector3.new(1,0,1) end
   facing=facing.Magnitude>.05 and facing.Unit or -Vector3.zAxis
   local center=root.Position+facing*(5.3*scale)+Vector3.yAxis*(1.45*scale)
   local frame=CFrame.lookAt(center,center-facing)
   local folder=new("Folder",{Name="BLY_GalaxyPortal"},holder)
   local radius=2.27*scale
   local rim=orbit(folder,radius,radius*1.06,.105*scale,blue)
   local inner=orbit(folder,radius*.88,radius*.94,.061*scale,violet)
   local plane=node(folder,"BLY_PortalMist",Enum.Material.SmoothPlastic,indigo,Vector3.one*.1,1)
   local smoke=new("Attachment",{},plane)
   new("ParticleEmitter",{Texture="rbxasset://textures/particles/smoke_main.dds",Rate=19,LightEmission=.7,
    LightInfluence=0,Speed=NumberRange.new(.28*scale,1.2*scale),Lifetime=NumberRange.new(.8,1.6),
    SpreadAngle=Vector2.new(180,180),RotSpeed=NumberRange.new(-105,130),
    Color=ColorSequence.new(indigo,violet),Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.6*scale),
     NumberSequenceKeypoint.new(.48,2.25*scale),NumberSequenceKeypoint.new(1,2.9*scale)}),
    Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.72),NumberSequenceKeypoint.new(.34,.46),
     NumberSequenceKeypoint.new(1,1)})},smoke)
   local stars={}
   for i=1,26 do stars[i]=spark(folder,i%3==0 and pearl or i%2==0 and blue or violet,(.043+i%4*.026)*scale) end
   portal={folder=folder,frame=frame,rim=rim,inner=inner,plane=plane,stars=stars,radius=radius,
    expires=os.clock()+26,previous=frame:PointToObjectSpace(root.Position)}
   enterHeight=root.Position.Y+math.clamp(.52*scale,.40,.92)
   feedback.Text="اقفز باتجاه وسط البوابة عشان تدخل المجرة"
  end
  local input=UIS.InputBegan:Connect(function(key,processed)
   if not processed and key.KeyCode==Enum.KeyCode.Q then openPortal() end
  end)
  local connection=Run.RenderStepped:Connect(function()
   if not isCurrent() then return end
   local now=os.clock()
   local headFrame=CFrame.new(head.Position+Vector3.yAxis*(head.Size.Y*.54+.36*scale))
   halo.CFrame=headFrame*CFrame.Angles(math.rad(69),0,now*.42)
   haloTrail.CFrame=halo.CFrame
   local arcFrame=headFrame*CFrame.new(.14*scale,.14*scale,0)*CFrame.Angles(math.rad(62),.16,-.23)
   violetArc.CFrame=arcFrame
   arcGlow.CFrame=arcFrame
   if not groundCheck or now-groundCheck>.10 then
    groundCheck=now
    local ground=workspace:Raycast(root.Position,-Vector3.yAxis*(5.2*scale),floorParams)
    floorHeight=ground and ground.Position.Y+.21*scale
   end
   local grounded=floorHeight~=nil and root.Position.Y-floorHeight<2.65*scale
   floorMist.Enabled=grounded
   floorLight.Enabled=grounded
   if grounded then
    footGlow.Position=Vector3.new(root.Position.X,floorHeight,root.Position.Z)
    floorLight.Brightness=1.24+.25*(.5+.5*math.sin(now*2.2))
   end
   local dt=lastStarUpdate and math.clamp(now-lastStarUpdate,0,.10) or 0
   lastStarUpdate=now
   local position=root.Position
   for band=1,3 do
    local previous=starOrigins[band]
    starOrigins[band]=previous and (previous-position).Magnitude<12*scale
     and previous:Lerp(position,1-math.exp(-dt*(7-band*1.35))) or position
   end
   for i,star in dust do
    local band=(i-1)%3+1
    local a=i*2.39996+now*(band==2 and -.57 or .44)
    local r=(.94+i%6*.22)*scale
    local y=(band==1 and .82 or band==2 and .08 or -.64)+.24*math.sin(now*1.6+i)
    local offset=root.CFrame:VectorToWorldSpace(Vector3.new(math.cos(a)*r,y*scale,math.sin(a)*r*1.45))
    local goal=starOrigins[band]+offset
    if floorHeight and goal.Y<floorHeight+.09*scale then
     goal=Vector3.new(goal.X,floorHeight+.09*scale,goal.Z)
    end
    star.Position=goal
    star.Transparency=.08+.48*(.5+.5*math.sin(now*3+i))
   end
   if portal then
    local p=portal
    local f=p.frame
    p.rim.CFrame=f*CFrame.Angles(.025*math.sin(now*2),0,now*.53)
    p.inner.CFrame=f*CFrame.Angles(0,.08,-now*.91)
    p.plane.CFrame=f
    for i,star in p.stars do
     local a=i*2.39996+now*(.8+i%4*.29)
     local r=p.radius*(.17+.81*((i*.271+now*.27)%1))
     star.Position=f:PointToWorldSpace(Vector3.new(r*math.cos(a),r*math.sin(a),.25*scale*math.sin(a*2)))
     star.Transparency=.12+.39*(.5+.5*math.sin(a*2))
    end
    local point=f:PointToObjectSpace(root.Position)
    local previous=p.previous
    local planePoint=point
    if previous.Z*point.Z<0 then planePoint=previous:Lerp(point,previous.Z/(previous.Z-point.Z)) end
    p.previous=point
    if (math.abs(point.Z)<.68*scale or previous.Z*point.Z<0)
     and math.max(root.Position.Y,f:PointToWorldSpace(planePoint).Y)>=enterHeight
     and (planePoint.X/p.radius)^2+(planePoint.Y/(p.radius*1.06))^2<.78 then
     enterSky()
    elseif now>p.expires then
     closePortal() feedback.Text="انقفلت البوابة · اضغط Q لفتحها مرة ثانية"
    end
   end
   local camera=workspace.CurrentCamera
   if camera then
    for i,item in lanterns do
     local direction=CFrame.Angles(0,now*.018,0):VectorToWorldSpace(item.direction)
     item.point.Position=camera.CFrame.Position+direction*(218+i%11*7)
     item.point.Transparency=.13+.53*(.5+.5*math.sin(now*1.3+i))
     if item.glow then item.glow.Rotation=(i*48+now*(i%2==0 and 3 or -2))%360 end
    end
   end
  end)
  table.insert(restoreFur,function()
   input:Disconnect() connection:Disconnect()
   closePortal() exitSky()
  end)
  local painted=0
  local mapCache,converted={},{}
  local parts=model:GetDescendants()
  local function tint(part,color)
   local surface=part:FindFirstChildOfClass("SurfaceAppearance") or part
   local original=surface.Color
   surface.Color=color
   table.insert(restoreFur,function()
    if surface.Parent and surface.Color==color then surface.Color=original end
   end)
  end
  for _,part in parts do
   if not isCurrent() then return end
   if not part:IsA("BasePart") or part.Transparency>=.95 then continue end
   local name=part.Name:lower()
   if name:find("teeth",1,true) or name:find("tongue",1,true) or name:find("claw",1,true) then continue end
   local eye=(name:find("eye",1,true) or name:find("iris",1,true) or name:find("pupil",1,true))
    and not name:find("lid",1,true) and not name:find("brow",1,true)
    and not name:find("lash",1,true) and not name:find("socket",1,true)
   local applied=false
   if part:IsA("MeshPart") and (eye or painted<15) then
    local ok,value=pcall(function()
     local surface=part:FindFirstChildOfClass("SurfaceAppearance")
     local source=readTexture(part,surface)
     local key=source and source.Uri or nil
     if key=="" then key=nil end
     if not source then key="plain" end
     if key and eye then key..="#iris" end
     local pair=key and converted[key]
     if not pair then
      local original
      if source then
       local loaded,image=pcall(function() return assets:CreateEditableImageAsync(source) end)
       if loaded then original=image end
      end
      if original and isCurrent() then table.insert(furImages,original)
      elseif original then original:Destroy() end
      if not isCurrent() then return false end
      local side=eye and 96 or 256
      local size=Vector2.new(side,side)
      local color=assets:CreateEditableImage({Size=size})
      if not color then return false end
      table.insert(furImages,color)
      local glow=assets:CreateEditableImage({Size=size})
      if glow then table.insert(furImages,glow) end
      local sample=original and original:ReadPixelsBuffer(Vector2.zero,original.Size)
      local width,height=original and original.Size.X or 1,original and original.Size.Y or 1
      local pixels,emission=buffer.create(side*side*4),buffer.create(side*side*4)
      for y=0,side-1 do
       if y%48==0 then task.wait() if not isCurrent() then return false end end
       for x=0,side-1 do
        local u,v=(x+.5)/side,(y+.5)/side
        local src=(math.floor(v*height)*width+math.floor(u*width))*4
        local r,g,b,e
        local fur=1
        local dst=(y*side+x)*4
        if eye then
         r,g,b,e=255,255,255,255
        else
         r,g,b,e=galaxyPixel(u,v)
         if sample then
          local red,green,blue=buffer.readu8(sample,src),buffer.readu8(sample,src+1),buffer.readu8(sample,src+2)
          local luminance=.21*red+.72*green+.07*blue
          fur=.92+luminance*.11/255
         end
        end
        local alpha=sample and buffer.readu8(sample,src+3) or 255
        buffer.writeu32(pixels,dst,alpha*16777216+math.floor(b*fur)*65536+math.floor(g*fur)*256+math.floor(r*fur))
        e=math.floor(e)
        buffer.writeu32(emission,dst,4278190080+65793*e)
       end
      end
      color:WritePixelsBuffer(Vector2.zero,size,pixels)
      if glow then glow:WritePixelsBuffer(Vector2.zero,size,emission) end
      pair={color=color,glow=glow}
      if key then converted[key]=pair end
     end
     return installFur(part,surface,pair.color,assets,isCurrent,pair.glow,not not eye,mapCache,eye and whiteEye or Color3.fromRGB(196,174,255))
    end)
    applied=ok and value
    if applied then painted+=1 end
   end
   if isCurrent() then
    if not applied then pcall(tint,part,eye and whiteEye or Color3.fromRGB(58,49,114)) end
    if eye then
     if not applied and not part:FindFirstChildOfClass("SurfaceAppearance") then
      local original=part.Material
      part.Material=Enum.Material.Neon
      table.insert(restoreFur,function()
       if part.Parent and part.Material==Enum.Material.Neon then part.Material=original end
      end)
     end
     if not name:find("pupil",1,true) then
      new("PointLight",{Color=whiteEye,Brightness=.30,Range=math.clamp(part.Size.Magnitude*2.1,.58,1.30),Shadows=false},attachment(part,CFrame.identity))
     end
    end
   end
  end
  return painted
 end
 local function makeSpinoDetails(model,root,isCurrent)
  local head=findAnimalHead(model)
  local parts,body,sail={},nil,nil
  for _,p in model:GetDescendants() do
   if p:IsA("BasePart") and p.Transparency<.95 and not p.Name:lower():find("eye",1,true) then
    table.insert(parts,p)
    local n=p.Name:lower()
    if n:find("body",1,true) or n:find("torso",1,true) then body=p end
    if n:find("sail",1,true) or n=="fin" or n=="spine" then sail=p end
   end
  end
  body=body or root
  local forward=head and head.Position-root.Position or root.CFrame.LookVector
  forward=Vector3.new(forward.X,0,forward.Z)
  forward=forward.Magnitude>.1 and forward.Unit or root.CFrame.LookVector
  local right=forward:Cross(Vector3.yAxis).Unit
  local params=RaycastParams.new()
  params.FilterType=Enum.RaycastFilterType.Include
  params.FilterDescendantsInstances=parts
  params.RespectCanCollide=false
  local build=createDecorationBuilder(model,game:GetService("AssetService"),isCurrent)
  local silver=Color3.fromRGB(218,225,234)
  local batches={}
  local function band(anchor,path,width,side)
   local size=anchor.Size
   local span=math.max(size.X,size.Z)
   local height=size.Y
   local radius=size.Magnitude+2
   local function sample(u,v)
    local origin=anchor.Position+forward*(u*span)+Vector3.yAxis*(v*height)+right*(side*radius)
    local hit=workspace:Raycast(origin,-right*(side*radius*2),params)
    if hit then return hit.Instance,hit.Position+hit.Normal*.018 end
   end
   for i=1,#path-1 do
    if not isCurrent() then return end
    local a,b=path[i],path[i+1]
    local du,dv=(b[1]-a[1])*span,(b[2]-a[2])*height
    local len=math.max(math.sqrt(du*du+dv*dv),.001)
    local u,v=-dv/len*width/span,du/len*width/height
    local p1,x1=sample(a[1]+u,a[2]+v)
    local p2,x2=sample(a[1]-u,a[2]-v)
    local p3,x3=sample(b[1]+u,b[2]+v)
    local p4,x4=sample(b[1]-u,b[2]-v)
    if p1 and p1~=head and p1==p2 and p1==p3 and p1==p4 then
     local batch=batches[p1] or {vertices={},faces={}}
     batches[p1]=batch
     local n=#batch.vertices
     for _,point in {x1,x2,x3,x4} do table.insert(batch.vertices,{p1.CFrame:PointToObjectSpace(point),silver}) end
     for _,f in {{1,2,3},{2,4,3},{3,2,1},{3,4,2}} do table.insert(batch.faces,{n+f[1],n+f[2],n+f[3]}) end
    end
   end
  end
  for _,side in {-1,1} do
   for i=-1,1 do
    local u=i*.22
    band(body,{{u-.13,.25},{u-.04,.21},{u,.08},{u+.07,-.02}},math.max(body.Size.Y*.012,.025),side)
    band(body,{{u-.04,.21},{u+.04,.26}},math.max(body.Size.Y*.008,.018),side)
   end
   if sail then
    local ring={}
    for i=0,24 do local a=i*math.pi/12 table.insert(ring,{math.cos(a)*.12,math.sin(a)*.18}) end
    local w=math.max(sail.Size.Y*.012,.025)
    band(sail,ring,w,side)
    band(sail,{{0,-.34},{0,.34}},w,side)
    band(sail,{{-.22,-.06},{0,.14},{.22,-.06}},w,side)
   end
  end
  local count=0
  for part,batch in batches do
   if isCurrent() and #batch.faces>0 then
    if build(part,batch.vertices,batch.faces,"BLY_SpinoSilverDetail",function(p)return p.CFrame end,Enum.Material.Metal) then count+=1 end
   end
  end
  return count
 end
 local function makeSpectralSpino(model,root)
  local eyes=0
  local function tint(part,color)
   local surface=part:FindFirstChildOfClass("SurfaceAppearance") or part
   local old=surface.Color
   surface.Color=color
   table.insert(restoreFur,function() if surface.Parent and surface.Color==color then surface.Color=old end end)
  end
  for _,part in model:GetDescendants() do
   if not part:IsA("BasePart") or part.Transparency>=.95 then continue end
   local name=part.Name:lower()
   local eye=(name:find("eye",1,true) or name:find("iris",1,true) or name:find("pupil",1,true))
    and not name:find("lid",1,true) and not name:find("brow",1,true) and not name:find("lash",1,true)
   if eye then
    tint(part,Color3.fromRGB(255,255,255))
    local glow=new("Highlight",{Name="BLY_SpinoEye",Adornee=part,FillColor=Color3.new(1,1,1),FillTransparency=.08,OutlineTransparency=1,DepthMode=Enum.HighlightDepthMode.Occluded},part)
    table.insert(effects,glow)
    local node=attachment(part,CFrame.identity)
    new("PointLight",{Color=Color3.new(1,1,1),Brightness=.65,Range=math.clamp(part.Size.Magnitude*3,1.5,4),Shadows=false},node)
    eyes+=1
   else
    local bone=name:find("tooth",1,true) or name:find("teeth",1,true) or name:find("claw",1,true) or name:find("skull",1,true)
    tint(part,bone and Color3.fromRGB(205,211,219) or Color3.fromRGB(35,38,43))
   end
  end
  return eyes
 end
 applyFur=function(model,epoch,look)
  local function isCurrent()
   return alive and unlocked and enabled and furEpoch==epoch and boundModel==model and player.Character==model
  end
  if look=="spino" then
   local ok,eyes=pcall(makeSpectralSpino,model,boundRoot)
   if not isCurrent() then return end
   if not ok then
    Brain.clearSilverLion() renderGallery()
    warn("BLY Spino appearance: "..tostring(eyes))
    feedback.Text="تعذّر تركيب مظهر السباينو؛ رجع المظهر الأصلي"
   else
    local decorated,count=pcall(makeSpinoDetails,model,boundRoot,isCurrent)
    if not isCurrent() then return end
    if not decorated then warn("BLY Spino details: "..tostring(count)) end
    feedback.Text=decorated and count>0 and "الزخارف الفضية جاهزة · المظهر عندك فقط" or "تعذّر تثبيت الزخارف؛ أرسل فحص الخامة"
    if eyes==0 then feedback.Text=feedback.Text.." · لم أجد أجزاء العيون" end
   end
   return
  end
  local lava=look=="crocodile"
  local mirage=look=="elephant"
  local aurora=look=="rhinoceros"
  local emerald=look=="leopard"
  local pink=look=="pinkelephant"
  local royal=look=="royal"
  local assets=game:GetService("AssetService")
  if look=="galaxy" then
   local ok,painted=pcall(makeGalaxyLion,model,boundRoot,assets,isCurrent)
   if not isCurrent() then return end
   if ok and painted~=nil then
    feedback.Text=painted>0 and "أسد المجرة جاهز · اضغط Q لفتح البوابة"
     or "التوهج والبوابة جاهزان · خامة الجسم غير متاحة على هذا الجهاز"
   else
    warn("BLY Galaxy appearance: "..tostring(painted))
    Brain.clearSilverLion()
    renderGallery()
    feedback.Text="تعذّر تركيب أسد المجرة على هذا الجهاز"
   end
   return
  end
  if look=="skydragon" then
   local ok,wingCount=pcall(makeSkyDragon,model,boundRoot,assets,isCurrent)
   if not isCurrent() then return end
   if ok and wingCount~=nil then
    if selectedKey==look then
     feedback.Text=wingCount==2 and "الجناحان مربوطان بحركة الطائر · اضغط E مطولًا"
      or "حركة جناح احتياطية · اضغط E مطولًا لنفث النار"
    end
   else
    if not ok then warn("BLY Dragon appearance: "..tostring(wingCount)) end
    Brain.clearSilverLion()
    renderGallery()
    if selectedKey==look then feedback.Text="تعذّر تركيب التنين على هذا الجهاز؛ رجع مظهر الطائر" end
   end
   return
  end
  if mirage then
   local ok,result=pcall(makeMirageElephant,model,boundRoot,assets,isCurrent)
   if not ok and isCurrent() then warn("BLY Mirage elephant geometry: "..tostring(result)) end
   if not isCurrent() then return end
  end
  if aurora then
   local ok,result=pcall(makeAuroraRhino,model,boundRoot,assets,isCurrent)
   if not ok and isCurrent() then warn("BLY Aurora rhino geometry: "..tostring(result)) end
   if not isCurrent() then return end
  end
  if emerald then
   local ok,result=pcall(makeEmeraldLeopard,model,boundRoot,isCurrent)
   if not ok and isCurrent() then warn("BLY Emerald leopard geometry: "..tostring(result)) end
   if not isCurrent() then return end
  end
  if pink then
   local ok,result=pcall(makePinkElephant,model,boundRoot,assets,isCurrent)
   if not ok and isCurrent() then warn("BLY Pink elephant effects: "..tostring(result)) end
   if not isCurrent() then return end
  end
  local royalMask=false
  if royal then
   local ok,result=pcall(makeRoyalLion,model,boundRoot,assets,isCurrent)
   if ok then royalMask=result elseif isCurrent() then warn("BLY Royal mask: "..tostring(result)) end
   if not isCurrent() then return end
  end
  local wingCount,halo=0,false
  if mirage or aurora or emerald or pink then
  elseif not lava and not royal then
   local ok,first,second=pcall(makeInfernoLion,model,boundRoot,assets,isCurrent)
   if ok then wingCount,halo=first,second elseif isCurrent() then warn("BLY Inferno geometry: "..tostring(first)) end
   if not isCurrent() then return end
  else
   local lightOk,lightError=pcall(addLavaLight,boundRoot)
   if not lightOk then warn("BLY Lava light: "..tostring(lightError)) end
   local ok,problem=pcall(startBreath,model,boundRoot,isCurrent)
   if not ok then warn("BLY Lava breath: "..tostring(problem)) end
  end
  local meshes={}
  local eyeTint=lava and Color3.fromRGB(255,160,39) or mirage and Color3.fromRGB(76,246,232) or aurora and Color3.fromRGB(200,154,255) or emerald and Color3.fromRGB(172,255,164) or pink and Color3.fromRGB(255,95,116) or royal and Color3.fromRGB(255,205,70) or Color3.fromRGB(255,18,24)
  local furTint=lava and Color3.fromRGB(149,68,54) or mirage and Color3.fromRGB(18,39,58) or aurora and Color3.fromRGB(49,28,72) or emerald and Color3.fromRGB(14,35,25) or pink and Color3.fromRGB(255,197,223) or royal and Color3.fromRGB(112,78,38) or Color3.fromRGB(48,9,17)
  local eyes=0
  local function tintExisting(part,tint,muteEmission)
   local surface=part:FindFirstChildOfClass("SurfaceAppearance") or part
   local original=surface.Color
   local emission=muteEmission and surface:IsA("SurfaceAppearance") and surface.EmissiveStrength
   surface.Color=tint
   if emission then surface.EmissiveStrength=0 end
   table.insert(restoreFur,function()
    if surface.Color==tint then surface.Color=original end
    if emission and surface.EmissiveStrength==0 then surface.EmissiveStrength=emission end
   end)
  end
  local function eyeLight(part)
   if lava or not part:IsDescendantOf(model) then return end
   local size=part.Size.Magnitude
   local node=attachment(part,CFrame.identity)
   new("PointLight",{Color=eyeTint,Brightness=.52,Range=math.clamp(size*3,1.3,3.7),Shadows=false},node)
   if not part:FindFirstChildOfClass("SurfaceAppearance") then
    local original=part.Material
    part.Material=Enum.Material.Neon
    table.insert(restoreFur,function()
     if part.Material==Enum.Material.Neon then part.Material=original end
    end)
   end
  end
  for _,object in model:GetDescendants() do
   if not object:IsA("BasePart") or object.Transparency>=.95 then continue end
   local name=object.Name:lower()
   local pupil=name:find("pupil",1,true)
   local eye=(name:find("eye",1,true) or name:find("iris",1,true))
    and not pupil and not name:find("lid",1,true) and not name:find("brow",1,true) and not name:find("lash",1,true)
   local protected=pupil or name:find("teeth",1,true) or name:find("tongue",1,true) or name:find("claw",1,true)
   if protected then continue end
   if eye and not object:IsA("MeshPart") then
    if pcall(tintExisting,object,eyeTint) then eyes+=1 eyeLight(object) end
   elseif object:IsA("MeshPart") and (lava or not name:find("nose",1,true)) then
    table.insert(meshes,{mesh=object,isEye=not not eye,isHorn=not not name:find("horn",1,true)})
   elseif not lava and not name:find("nose",1,true) then
    pcall(tintExisting,object,aurora and name:find("horn",1,true) and Color3.fromRGB(156,141,228) or furTint,true)
   end
  end
  table.sort(meshes,function(a,b)
   if not lava and a.isEye~=b.isEye then return a.isEye end
   if aurora and a.isHorn~=b.isHorn then return a.isHorn end
   return texturePriority(a.mesh)<texturePriority(b.mesh)
  end)
  local converted,mapCache={},{}
  local changed,tinted,attempted=0,0,0
  for _,entry in meshes do
   if not isCurrent() or attempted>=16 then break end
   local mesh=entry.mesh
   local ok,result=pcall(function()
    local appearance=mesh:FindFirstChildOfClass("SurfaceAppearance")
    local content=readTexture(mesh,appearance)
    if not content then return false end
    attempted+=1
    local uriOk,uri=pcall(function() return content.Uri end)
    local cacheKey=uriOk and typeof(uri)=="string" and uri~="" and (uri..(entry.isEye and "#eye" or entry.isHorn and "#horn" or "")) or nil
    local pair=cacheKey and converted[cacheKey]
    if not pair then
     local image=assets:CreateEditableImageAsync(content)
     if not image then return false end
     if not isCurrent() then image:Destroy() return false end
     table.insert(furImages,image)
     local glow
     if lava or mirage or aurora or emerald or pink or entry.isEye then
      local made,value=pcall(function() return assets:CreateEditableImage({Size=image.Size}) end)
      if made and value then glow=value table.insert(furImages,glow) end
     end
     local width,height=image.Size.X,image.Size.Y
     local rowsPerBatch=math.max(1,math.floor((lava and 8192 or 16384)/width))
     for y=0,height-1,rowsPerBatch do
      if not isCurrent() then return false end
      local origin=Vector2.new(0,y)
      local size=Vector2.new(width,math.min(rowsPerBatch,height-y))
      local pixels=image:ReadPixelsBuffer(origin,size)
      local glowPixels=glow and buffer.create(buffer.len(pixels))
      if lava then lavaPixels(pixels,width,y,height,entry.isEye,glowPixels)
      elseif mirage then miragePixels(pixels,width,y,height,entry.isEye,glowPixels)
      elseif aurora then auroraPixels(pixels,width,y,height,entry.isEye,glowPixels,entry.isHorn)
      elseif emerald then emeraldPixels(pixels,width,y,height,entry.isEye,glowPixels)
      elseif pink then pinkPixels(pixels,width,y,height,entry.isEye,glowPixels)
      else infernoPixels(pixels,width,y,height,entry.isEye,glowPixels,royal) end
      if glow then glow:WritePixelsBuffer(origin,size,glowPixels) end
      image:WritePixelsBuffer(origin,size,pixels)
      task.wait()
     end
     pair={image=image,glow=glow}
     if cacheKey then converted[cacheKey]=pair end
    end
    if not mesh:IsDescendantOf(model) or not isCurrent() then return false end
    return installFur(mesh,appearance,pair.image,assets,isCurrent,pair.glow,entry.isEye,mapCache,
     entry.isEye and eyeTint or (mirage and Color3.fromRGB(65,245,224) or aurora and Color3.fromRGB(195,112,255) or emerald and Color3.fromRGB(80,255,142) or pink and Color3.fromRGB(255,95,116) or nil),not lava and not entry.isEye)
   end)
   if ok and result then
    changed+=1
    if entry.isEye then eyes+=1 eyeLight(mesh) end
   elseif isCurrent() then
    if not ok then warn("BLY Appearance • "..mesh.Name..": "..tostring(result)) end
    if (not lava or not entry.isEye) and mesh:IsDescendantOf(model) then
     if pcall(tintExisting,mesh,entry.isEye and eyeTint or aurora and entry.isHorn and Color3.fromRGB(156,141,228) or furTint,not lava and not entry.isEye) then
      tinted+=1
      if entry.isEye then eyes+=1 eyeLight(mesh) end
     end
    end
   end
  end
  if not isCurrent() then return end
  local wings,horns,tail=false,false,false
  if lava then
   local ok,first,second,third=pcall(makeDragonMeshes,model,boundRoot,assets,isCurrent)
   if ok then wings,horns,tail=first,second,third elseif isCurrent() then warn("BLY Lava geometry: "..tostring(first)) end
  end
  if not isCurrent() or (not royal and selectedKey~=look and not (pink and selectedKey=="elephant")) then return end
  if lava then
   feedback.Text=string.format("حراشف: %d خامة · %d تلوين\nعين %s · أجنحة %s · قرون %s · تفاصيل الظهر والذيل %s",
    changed,tinted,eyes>0 and "✓" or "—",wings and "✓" or "—",horns and "✓" or "—",tail and "✓" or "—")
  elseif mirage then
   feedback.Text=string.format("فيل روح السراب · خامات مضيئة %d · عروق الأذنين %s · عيون تركواز %d",
    changed+tinted,eyes>0 and "جاهزة" or "تظهر من الخامة",eyes)
  elseif aurora then
   feedback.Text=string.format("حارس الكريستال الشفقي · خامات بلورية %d · قرون مضيئة · عيون بنفسجية %d",
    changed+tinted,eyes)
  elseif emerald then
   feedback.Text=string.format("فهد العقيق الأخضر · خامات زمردية %d · عيون خضراء %d",changed+tinted,eyes)
  elseif pink then
   feedback.Text=string.format("الفيل الوردي · خامات %d · عيون حمراء ولمعات وردية",changed+tinted)
  elseif royal then
   feedback.Text=string.format("أسد الذهب الملكي · القناع %s · الفرو %d · العيون الذهبية %d · ذرات ذهبية حوله",
    royalMask and "ثابت على الرأس" or "غير متاح على هذا الجهاز",changed+tinted,eyes)
  else
   feedback.Text=string.format("فرو جمري %d جزء · عيون %d · أجنحة %d/2\nالهالة %s",
    changed+tinted,eyes,wingCount,halo and "جاهزة" or "غير متاحة")
  end
 end
 local function checkTextures(model)
  local meshes={}
  for _,object in model:GetDescendants() do
   if object:IsA("MeshPart") and object.Transparency<.95 then table.insert(meshes,object) end
  end
  table.sort(meshes,function(a,b) return texturePriority(a)<texturePriority(b) end)
  local assets=game:GetService("AssetService")
  local details={"BLY Appearance • "..#meshes.." visible mesh parts"}
  local results={}
  for _,mesh in meshes do
   if #results>=3 or not alive or model~=player.Character then break end
   local appearance=mesh:FindFirstChildOfClass("SurfaceAppearance")
   local content=readTexture(mesh,appearance)
   if content then
    local ok,image=pcall(function() return assets:CreateEditableImageAsync(content) end)
    if ok and image then
     image:Destroy()
     table.insert(results,mesh.Name.." • قابلة للتعديل")
     table.insert(details,mesh.Name..": EDITABLE")
    else
     table.insert(results,mesh.Name.." • التعديل غير متاح")
     table.insert(details,mesh.Name..": BLOCKED ("..tostring(image or "image unavailable")..")")
    end
   elseif appearance then
    table.insert(results,mesh.Name.." • تعذّرت قراءة الخامة")
    table.insert(details,mesh.Name..": COLOR MAP UNREADABLE")
   end
  end
  if #results==0 then
   table.insert(results,"ما ظهرت خامات قابلة للقراءة")
   table.insert(details,"No readable mesh texture found.")
  end
  return table.concat(results,"\n"),table.concat(details,"\n")
 end
 local checking=false
 checkButton=button(right,"فحص الخامة",19,189,372,function()
  if checking then return end
  local requestedLook=selectedKey
  local model=currentAnimal(requestedLook)
  if not model then
   feedback.Text="العب بالحيوان المختار أولًا، ثم اضغط فحص الخامة"
   return
  end
  checking=true
  checkButton.Text="جارٍ فحص الخامة…"
  feedback.Text="أفحص خامات الحيوان الحالي"
  task.spawn(function()
   local ok,summary,report=pcall(checkTextures,model)
   checking=false
   if not alive then return end
   checkButton.Text="فحص الخامة"
   if not ok then
    report="BLY Silver Lion: "..tostring(summary)
    summary="تعذّر إكمال فحص الخامة"
   end
   print(report)
   local copied=false
   if typeof(setclipboard)=="function" then copied=pcall(setclipboard,report) end
   if selectedKey==requestedLook then
    feedback.Text=summary..(copied and "\nنُسخت النتيجة" or "")
   end
  end)
 end)
 checkButton.Size=UDim2.fromOffset(372,30)
 checkButton.Visible=false
 function Brain.refreshAppearanceRoster()
  local entries=Brain.appearanceRoster()
  local present={}
  for index,entry in entries do
   present[entry.key]=true
   local item=rosterButtons[entry.key]
   if not item then
    item={key=entry.key,name=entry.name}
    item.button=button(list,entry.name,0,0,209,function()
     selectedKey,selectedName=item.key,item.name
     for _,row in rosterButtons do Brain.selectButton(row.button,row.key==selectedKey) end
     feedback.Text="المظاهر تظهر عندك داخل اللعبة"
     renderGallery()
    end)
    item.button.Size=UDim2.fromOffset(209,34)
    item.button.TextSize=13
    rosterButtons[entry.key]=item
   end
   item.name=entry.name
   item.button.Text=entry.name
   item.button.LayoutOrder=index
   item.button.Visible=true
  end
  if not selectedKey or not present[selectedKey] then
   selectedKey=entries[1] and entries[1].key
   selectedName=entries[1] and entries[1].name
  end
  for key,item in rosterButtons do
   item.button.Visible=present[key]==true
   Brain.selectButton(item.button,key==selectedKey)
  end
  feedback.Text=#entries==0 and "ما ظهرت بيانات الحيوانات المملوكة. افتح قائمة الحفظ ثم اضغط تحديث." or "المظاهر تظهر عندك داخل اللعبة"
  renderGallery()
 end
 local reload=button(left,"تحديث القائمة",10,268,218,Brain.refreshAppearanceRoster)
 reload.Size=UDim2.fromOffset(218,32)
end
Brain.license={base="https://bly-victory-script.mistybraid.chatgpt.site",busy=false,status="pending"}
do
 local Http=game:GetService("HttpService")
 local file="BLY_Activation_"..player.UserId..".json"
 local secret
 pcall(function()
  local env=(typeof(getgenv)=="function" and getgenv()) or _G
  local cached=env.__BLY_LICENSE
  if cached and cached.userId==player.UserId and typeof(cached.secret)=="string" and #cached.secret==72 then secret=cached.secret end
 end)
 if not secret and typeof(readfile)=="function" then
  pcall(function() local data=Http:JSONDecode(readfile(file)) if data.userId==player.UserId and typeof(data.secret)=="string" and #data.secret==72 then secret=data.secret end end)
 end
 if not secret then
  secret=string.lower(Http:GenerateGUID(false)..Http:GenerateGUID(false))
  if typeof(writefile)=="function" then pcall(writefile,file,Http:JSONEncode({userId=player.UserId,secret=secret})) end
 end
 Brain.license.secret=secret
 function Brain.licenseCall(path,body)
  local requestFn=Brain.requestFunction()
  if typeof(requestFn)~="function" then return nil,"المشغّل ما يدعم طلب التفعيل عبر الإنترنت" end
  if Brain.license.inflight then return nil,"أنتظر اتصال التفعيل السابق" end
  local job={done=false,cancelled=false} Brain.license.inflight=job
  job.thread=task.spawn(function()
   local ok,r=pcall(requestFn,{Url=Brain.license.base..path,Method="POST",Headers={["Content-Type"]="application/json"},Body=Http:JSONEncode(body),Timeout=10})
   if not job.cancelled and ok and typeof(r)=="table" and tonumber(r.StatusCode) and r.StatusCode>=200 and r.StatusCode<300 then
    local decoded,value=pcall(function() return Http:JSONDecode(r.Body) end)
    if decoded then job.result=value end
   end
   job.done=true
   if Brain.license.inflight==job then Brain.license.inflight=nil end
  end)
  local deadline=os.clock()+12
  while alive and not job.done and os.clock()<deadline do task.wait(.1) end
  if not job.done then
   job.cancelled=true
   if Brain.license.inflight==job then Brain.license.inflight=nil end
   if job.thread and typeof(task.cancel)=="function" then pcall(task.cancel,job.thread) end
  end
  return job.result,job.result and nil or "تعذر الاتصال بالتفعيل؛ ما فتحت التحكم"
 end
 function Brain.applyLicense(result,message)
  local status=result and result.status
  if status then Brain.license.registered=true end
  Brain.license.status=status or "offline"
  if status=="approved" then
   Brain.licenseExpires=os.clock()+100
   unlocked=true login.Visible=false dashboard.Visible=true
   activationLabel.Text="تم التفعيل • @"..player.Name
   if not Brain.license.wasApproved then state("تم تفعيلك؛ اختر الوضع اللي تبيه") end
   Brain.license.wasApproved=true
  elseif status then
   unlocked=false Brain.licenseExpires=0
   if running then stop("التفعيل غير متاح") end
   login.Visible=true dashboard.Visible=false
   local labels={pending="بانتظار تفعيل الإدارة",rejected="طلبك مرفوض؛ تواصل مع الإدارة",revoked="ألغت الإدارة التفعيل"}
   activationLabel.Text=(labels[status] or "بانتظار التفعيل").."\n@"..player.Name
   state(activationLabel.Text)
  else
   if not Brain.licenseExpires or os.clock()>=Brain.licenseExpires then
    unlocked=false if running then stop("انقطع التحقق من التفعيل؛ أنتظر رجوع الاتصال",true) end
    login.Visible=true dashboard.Visible=false
   end
   activationLabel.Text=message or "تعذر الاتصال"
  end
 end
 function Brain.refreshLicense()
  if Brain.license.busy then return end
  Brain.license.busy=true
  local ok,err=pcall(function()
   local path=Brain.license.registered and "/api/license/status" or "/api/license/request"
   local result,message=Brain.licenseCall(path,{userId=player.UserId,username=player.Name,displayName=player.DisplayName,secret=secret})
   Brain.applyLicense(result,message)
  end)
  Brain.license.busy=false
  if not ok then Brain.license.lastError=tostring(err) end
 end
 function Brain.activateLicense()
  activationLabel.Text="أتحقق من التفعيل • @"..player.Name
  Brain.refreshLicense()
 end
 button(login,"تحديث طلب التفعيل",20,184,290,Brain.activateLicense)
 task.spawn(function()
  while alive do task.wait(20) if alive then Brain.refreshLicense() end end
 end)
end
Brain.growth={active=false,sequence=0,selected=nil,completed=0,status="دورة نمو تلقائية · أقرب موارد · اسم عشوائي من اللعبة",ownedEvidence={},completedModels=setmetatable({},{__mode="k"})}
do
 local catalog={"Bush Elephant","Impala","Zebra","Giraffe","African Buffalo","Wildebeest","Hippopotamus","Rhinoceros","Warthog"}
 local function canonical(name)
  local value=string.lower(tostring(name or "")):gsub("[^%a]","")
  value=value:gsub("^mammals",""):gsub("^birds",""):gsub("^reptiles","")
  if value=="elephant" or value=="africanelephant" or value=="africanbushelephant" then return "bushelephant" end
  if value=="buffalo" or value=="capebuffalo" then return "africanbuffalo" end
  if value=="hippo" then return "hippopotamus" end
  if value=="rhino" then return "rhinoceros" end
  return value
 end
 local function safeNodes()
  local nodes={}
  for _,name in {"SavedCharactersScreenGui","MainMenuScreenGui","AnimalStatsScreenGui"}do
   local screen=pg:FindFirstChild(name)
   if screen then for _,node in Brain.groupNodes(screen,6000)do table.insert(nodes,node)end end
  end
  return #nodes>0 and nodes or Brain.groupNodes(pg,1800)
 end
 function Brain.growthAnimal(model)
  if not model then return end
  for _,key in {"AnimalName","AnimalType","Species","Animal","SpeciesName"} do
   local value=model:GetAttribute(key)
   if typeof(value)=="string" and value~="" then
    for _,name in catalog do if canonical(value)==canonical(name) then return name end end
   end
  end
  for _,name in catalog do if canonical(model.Name)==canonical(name)then return name end end
 end
 local function savedSpecies(node)
  if not node:IsA("TextLabel") or node:IsDescendantOf(gui) then return end
  local label=node.Text:gsub("<[^>]->","")
  local species=label:match("^[Mm]ale%s+(.+)$") or label:match("^[Ff]emale%s+(.+)$")
  if not species then return end
  local ancestor=node.Parent
  for _=1,5 do
   if not ancestor or ancestor==pg then break end
   local name=ancestor.Name:lower()
   if name:find("character",1,true) or name:find("save",1,true) or name:find("slot",1,true) then
    for _,child in Brain.groupNodes(node.Parent,40) do
     if child:IsA("TextLabel") and child.Text:lower():match("%d+%%%s*growth") then return species end
    end
   end
   ancestor=ancestor.Parent
  end
 end
 local function appearanceKey(name)
  local raw=tostring(name or ""):gsub("%s+",""):gsub("أ","ا"):gsub("إ","ا"):gsub("ـ","")
  if raw=="سبينوصورالارض" or raw=="سبينوصورالارضي" or raw=="سبينوصور" or raw=="سباينو" or raw=="سبينوصورالمائي" or raw=="سباينومائي" then return "spino" end
  local key=canonical(name)
  if key=="spino" or key=="spinosaurus" or key=="aquaticspino" or key=="aquaticspinosaurus" or key=="spinoaqua" or key=="landspinosaurus" or key=="spinosaurusland" or key=="terrestrialspinosaurus" or key=="spinosaurusterrestrial" then return "spino" end
  if key=="africanlion" or key=="lioness" or key=="africanlioness" or key=="whitelion" then return "lion" end
  if key=="elephant" or key=="africanelephant" or key=="bushelephant" or key=="africanbushelephant" then return "elephant" end
  if key=="rhino" or key=="blackrhino" or key=="whiterhino" or key=="rhinoceros" or key=="blackrhinoceros" or key=="whiterhinoceros" then return "rhinoceros" end
  if key=="leopard" or key=="africanleopard" or key=="blackleopard" or key=="cheetah" or key=="africancheetah" then return "leopard" end
  if key=="nilecrocodile" or key=="nilecroc" or key=="croc" then return "crocodile" end
  if key=="skydragon" or key=="falcon" or key=="eagle" or key=="baldeagle" or key=="vulture"
   or key:find("vulture",1,true) or key:match("falcon$")
   or key=="whitebackedvulture" or key=="africanfisheagle" or key=="صقر" or key=="الصقر"
   or key=="نسر" or key=="النسر" then return "skydragon" end
  return key
 end
 function Brain.appearanceAnimal(model)
  if not model then return end
  if appearanceKey(model.Name)=="spino" then return "spino",model.Name end
  for _,key in {"AnimalName","AnimalType","Species","Animal","DinosaurName","Dinosaur","CreatureName","SpeciesName"} do
   local value=model:GetAttribute(key)
   local node=model:FindFirstChild(key)
   if typeof(value)~="string" and node and node:IsA("StringValue") then value=node.Value end
   if typeof(value)=="string" and appearanceKey(value)=="spino" then return "spino",value end
  end
  for _,attribute in {"AnimalName","AnimalType","Species","Animal"} do
   local name=model:GetAttribute(attribute)
   if typeof(name)=="string" and appearanceKey(name)~="" then return appearanceKey(name),name end
  end
  local modelKey=appearanceKey(model.Name)
  if modelKey=="lion" then return "lion","Lion" end
  if modelKey=="elephant" then return "elephant","Bush Elephant" end
  if modelKey=="rhinoceros" then return "rhinoceros","Rhinoceros" end
  if modelKey=="leopard" then return "leopard","Leopard" end
  if modelKey=="crocodile" then return "crocodile","Crocodile" end
  if modelKey=="skydragon" then return "skydragon",model.Name end
 end
 function Brain.appearanceRoster()
  local animals={}
  local seen={}
  local function add(name)
   if typeof(name)~="string" or #name>64 then return end
   local key=appearanceKey(name)
   if key=="" or seen[key] then return end
   seen[key]=true
   table.insert(animals,{key=key,name=key=="lion" and "الأسد · Lion" or (key=="crocodile" and "التمساح · Crocodile" or name)})
  end
  local active,activeName=Brain.appearanceAnimal(player.Character)
  add(activeName)
  for _,folderName in {"OwnedAnimals","UnlockedAnimals","PurchasedAnimals"} do
   local folder=player:FindFirstChild(folderName)
   if folder then
    for _,item in folder:GetChildren() do
     if (item:IsA("BoolValue") and item.Value==true) or item:GetAttribute("Owned")==true or item:GetAttribute("Unlocked")==true then
      add(item:GetAttribute("AnimalName") or item.Name)
     end
    end
   end
  end
  for _,name in catalog do
   if Brain.growth.ownedEvidence[canonical(name)] then add(name) end
  end
  for _,node in safeNodes() do
   if not node:IsDescendantOf(gui) then
    if node:GetAttribute("Owned")==true or node:GetAttribute("Unlocked")==true or node:GetAttribute("Purchased")==true then
     add(node:GetAttribute("AnimalName"))
    end
    add(savedSpecies(node))
   end
  end
  table.sort(animals,function(a,b)
   if (a.key==active)~=(b.key==active) then return a.key==active end
   return a.key<b.key
  end)
  return animals
 end
 local function owns(name)
  local wanted=canonical(name)
  local model=player.Character
  if model and canonical(Brain.growthAnimal(model))==wanted and string.lower(tostring(model:GetAttribute("FoodType")))=="grass" then return true end
  if (Brain.growth.ownedEvidence or {})[wanted] then return true end
  for _,folderName in {"OwnedAnimals","UnlockedAnimals","PurchasedAnimals"} do
   local folder=player:FindFirstChild(folderName)
   if folder then for _,item in folder:GetChildren() do
    if canonical(item.Name)==wanted and ((item:IsA("BoolValue") and item.Value==true) or item:GetAttribute("Owned")==true or item:GetAttribute("Unlocked")==true) then return true end
   end end
  end
  for _,node in safeNodes() do
   if canonical(node.Name)==wanted or canonical(node:GetAttribute("AnimalName"))==wanted then
    if node:GetAttribute("Owned")==true or node:GetAttribute("Unlocked")==true or node:GetAttribute("Purchased")==true then return true end
   end
  end
  for _,node in safeNodes() do
   local species=savedSpecies(node)
   if species and canonical(species)==wanted then return true end
  end
  return false
 end
 function Brain.growthOwnership(name)
  if owns(name) then return "confirmed" end
  local wanted=canonical(name)
  for _,node in safeNodes() do
   local raw=canonical(node.Name):gsub("imagebutton$",""):gsub("button$","")
   if canonical(raw)==wanted or canonical(node:GetAttribute("AnimalName"))==wanted then
    if node:GetAttribute("Locked")==true or node:GetAttribute("Owned")==false or node:GetAttribute("Unlocked")==false then return "locked" end
   end
  end
  return "unknown"
 end
 local function blocked(node)
  for _=1,5 do
   if not node or node==pg then break end
   if node:GetAttribute("Locked")==true or node:GetAttribute("Owned")==false or node:GetAttribute("Unlocked")==false then return true end
   if node:IsA("TextButton") and (node.Text:lower():find("buy",1,true) or node.Text:lower():find("purchase",1,true)) then return true end
   node=node.Parent
  end
  return false
 end
 local navigation=game:GetService("GuiService")
 local function findButton(action,requireVisible)
  if action=="new"then
   local screen=pg:FindFirstChild("SavedCharactersScreenGui")
   local characters=screen and screen:FindFirstChild("CharactersFrame")
   local scroll=characters and characters:FindFirstChild("ScrollingFrame")
   local native=scroll and scroll:FindFirstChild("NewCharacterButton")
   if native and native:IsA("GuiButton")and not blocked(native)and(not requireVisible or visible(native))then return native end
  end
  local candidates={}
  for _,node in safeNodes() do
   if node:IsA("GuiButton") and not node:IsDescendantOf(gui) and not blocked(node) then
    local wanted=canonical(action)
    local title=canonical(node.Name)
    local rawTitle=title:gsub("imagebutton$",""):gsub("textbutton$",""):gsub("button$","")
    local labels={}
    if node:IsA("TextButton") then table.insert(labels,canonical(node.Text:gsub("<[^>]->",""))) end
    for _,child in Brain.groupNodes(node,20) do
     if child:IsA("TextLabel") then table.insert(labels,canonical(child.Text:gsub("<[^>]->",""))) end
    end
    local match=false
    for _,label in labels do
     if (action=="new" and label=="newcharacter") or label==wanted then match=true end
    end
    if action=="new" then match=match or title=="newcharacterbutton" or title=="newcharacter"
    else match=match or canonical(rawTitle)==wanted or canonical(node:GetAttribute("AnimalName"))==wanted
     if action~="play" and action~="create" and node.Parent then match=match or canonical(node.Parent.Name)==wanted end
    end
    if match and (not requireVisible or visible(node)) then
     if not requireVisible then return node end
     table.insert(candidates,node)
    end
   end
  end
  if #candidates==1 then return candidates[1] end
 end
 local function reveal(node)
  local parent=node.Parent
  while parent and parent~=pg do
   if parent:IsA("ScrollingFrame")then
    local p=node.AbsolutePosition-parent.AbsolutePosition local size=node.AbsoluteSize
    local view=parent.AbsoluteWindowSize local canvas=parent.CanvasPosition
    local dx=p.X<2 and p.X-2 or math.max(0,p.X+size.X-view.X+2)
    local dy=p.Y<2 and p.Y-2 or math.max(0,p.Y+size.Y-view.Y+2)
    parent.CanvasPosition=Vector2.new(math.clamp(canvas.X+dx,0,math.max(0,parent.AbsoluteCanvasSize.X-view.X)),math.clamp(canvas.Y+dy,0,math.max(0,parent.AbsoluteCanvasSize.Y-view.Y)))
    task.wait(.15)
   end
   parent=parent.Parent
  end
 end
 local function click(node)
  if not node or not visible(node) or blocked(node) or not Brain.focused or not unlocked or not Brain.growth.active then return false end
  if node.AbsoluteSize.X<2 then return false end
  reveal(node)
  if UIS.TouchEnabled then
   for attempt=1,3 do
    if not visible(node)or not Brain.focused or not unlocked or not Brain.growth.active then return false end
    if not Brain.touchButtonPress(node)then return false end
    local receipt=Brain.compat.buttonReceipt
    Brain.growth.uiReport={button=node:GetFullName(),input="touch",at=os.clock(),attempt=attempt}
    task.wait(.12)
    local released=Brain.compatPointer(0,false,0,0)
    local untilAt=os.clock()+.8
    repeat
     if receipt and receipt.ack then Brain.clearButtonReceipt()return released end
     if not node.Parent or not visible(node)then Brain.clearButtonReceipt()return released end
     task.wait(.05)
    until os.clock()>=untilAt or not Brain.growth.active or not Brain.focused
    Brain.rejectButtonTransport()Brain.clearButtonReceipt()
    if not released then return false end
   end
   return false
  end
  local selectable=node.Selectable
  local ok,sent=pcall(function()
   navigation.GuiNavigationEnabled=true node.Selectable=true navigation.SelectedObject=node
   task.wait(.15)
   if navigation.SelectedObject~=node or not visible(node)or not Brain.focused or not Brain.growth.active then return false end
   Brain.growth.uiReport={button=node:GetFullName(),input="keyboard",at=os.clock()}
   local pressed=Brain.pulse(Enum.KeyCode.Return,.12)task.wait(.2)return pressed
  end)
  pcall(function()node.Selectable=selectable end)
  return ok and sent==true
 end
 local function live(seq) return alive and unlocked and Brain.growth.active and Brain.growth.sequence==seq end
 local function waitButton(action,seq,seconds)
  local deadline=os.clock()+seconds
  repeat
   if not live(seq) then return end
   local b=findButton(action,true)
   if b then return b end
   task.wait(.25)
  until os.clock()>=deadline
 end
 local function advance(action,nextAction,seq,seconds)
  local deadline=os.clock()+seconds local retry=0
  repeat
   if not live(seq)then return end
   local nextButton=findButton(nextAction,true)if nextButton then return nextButton end
   if not Brain.focused then deadline=os.clock()+seconds
   elseif os.clock()>=retry then local button=findButton(action,true)if button then click(button)retry=os.clock()+1.5 end end
   task.wait(.2)
  until os.clock()>=deadline
 end
 local function status(message) Brain.growth.status=message state(message) end
 function Brain.growthValue(model)
  if not model or model~=player.Character then return end
  local g=Brain.growth
  if g.scaleModel~=model then g.scaleModel=model g.scale=nil end
  local values={}
  for _,key in {"GrowthPercent","GrowthPercentage","AgePercent","Growth","MaxGrowth","GrowthMax","GrowthScale"}do values[key]=model:GetAttribute(key)end
  local report={attributes=values,ui={},identity={model=model.Name,foodType=model:GetAttribute("FoodType"),animal=model:GetAttribute("AnimalName")or model:GetAttribute("AnimalType")or model:GetAttribute("Species")}} g.reading=report
  local function result(value,source)report.percent=value report.source=source return value end
  local observed,conflict
  for _,node in safeNodes()do
   if (node:IsA("TextLabel")or node:IsA("TextButton"))and not node:IsDescendantOf(gui)then
    local path=node:GetFullName():lower()
    local raw=node.Text:gsub("<[^>]->",""):lower()
    local native=path:find("animalstatsscreengui.mainframe",1,true)and (path:find("growth",1,true)or raw:match("^%s*growth%s*:"))
    if native then
     local value=tonumber(raw:match("^%s*growth%s*:?%s*(%d+%.?%d*)%s*%%%s*$")or raw:match("^%s*(%d+%.?%d*)%s*%%%s*$"))
     if #report.ui<6 then table.insert(report.ui,{path=path,text=raw})end
     if value and value>=0 and value<=100 then
      if observed and math.abs(observed-value)>.1 then conflict=true end
      observed=value
     end
    end
   end
  end
  if observed and not conflict then return result(observed,"current_hud")end
  local value,key
  for _,name in {"GrowthPercent","GrowthPercentage","AgePercent","Growth"}do
   local n=values[name]
   if typeof(n)=="number"and n==n and n>=0 and n<=100 then value=n key=name break end
  end
  if not value then return end
  local maximum=values.MaxGrowth or values.GrowthMax
  if values.GrowthScale=="percent"or key=="AgePercent"then return result(value,"percent_attribute")end
  if values.GrowthScale=="unit"then return result(math.clamp(value*100,0,100),"unit_attribute")end
  if game.PlaceId==18214855317 and value<=1 then return result(value*100,"place_unit_growth")end
  if key=="Growth"and typeof(maximum)=="number"and maximum>0 then return result(math.clamp(value/maximum*100,0,100),"growth_maximum")end
  if key~="Growth"or value>1 then g.scale="percent"return result(value,"percent_attribute")end
  if g.scale=="percent"then return result(value,"known_percent_scale")end
 end
 local function randomName(seq)
  local box,direct
  local screen=pg:FindFirstChild("SavedCharactersScreenGui")
  local frame=screen and screen:FindFirstChild("CreateCustomizeFrame")
  local names=frame and frame:FindFirstChild("NameFrame",true)
  if names then
   box=names:IsA("TextBox")and names or names:FindFirstChildWhichIsA("TextBox",true)
   direct=names:FindFirstChild("RandomizeButton",true)
   if not box or not visible(box)then box=nil direct=nil end
  end
  if not box then
   for _,node in safeNodes()do
    if node:IsA("TextBox")and not node:IsDescendantOf(gui)and visible(node)then
     local name=canonical(node.Name)local hint=tostring(node.PlaceholderText):lower()
     if name=="characternametextbox"or hint:find("choose name",1,true)or(node.Parent and node.Parent.Name=="NameFrame")then box=node break end
    end
   end
  end
  if not box then status("لم تظهر خانة اسم النسخة؛ أنتظر واجهة الإنشاء")return false end
  local named,adjacent={},{}
  for _,node in safeNodes()do
   if node:IsA("GuiButton")and not node:IsDescendantOf(gui)and visible(node)and not blocked(node)then
    local name=canonical(node.Name)
    if (name=="randomizebutton"and(node.Parent==box.Parent or node.Parent==box))or name:find("randomname",1,true)or name:find("randomizename",1,true)or name:find("generatename",1,true)or name:find("shufflename",1,true)then table.insert(named,node)end
    local dx=node.AbsolutePosition.X-(box.AbsolutePosition.X+box.AbsoluteSize.X)
    local dy=math.abs(node.AbsolutePosition.Y+node.AbsoluteSize.Y*.5-box.AbsolutePosition.Y-box.AbsoluteSize.Y*.5)
    if node.Parent==box.Parent and dx>=-4 and dx<=80 and dy<=box.AbsoluteSize.Y*.5 then table.insert(adjacent,node)end
   end
  end
  local button=direct and direct:IsA("GuiButton")and visible(direct)and not blocked(direct)and direct or(#named==1 and named[1]or(#adjacent==1 and adjacent[1]))
  if not button then status("زر اسم اللعبة العشوائي غير واضح؛ لم أكتب اسمًا بدلًا منه")return false end
  for _=1,3 do
   if not live(seq)then return false end
   local before=box.Text
   if not click(button)then return false end
   local deadline=os.clock()+2
   repeat
    if not live(seq)then return false end
    local value=box.Text:match("^%s*(.-)%s*$")
    if value~=""and value~=before then Brain.growth.generatedName=value return true end
    task.wait(.15)
   until os.clock()>=deadline
  end
  status("لم أتأكد أن اللعبة ولّدت اسمًا جديدًا؛ لم أضغط إنشاء")return false
 end
 local function createCore(seq)
  if not vim or not Brain.focused then status("ارجع لنافذة اللعبة وتأكد من دعم إرسال الأزرار قبل التكبير") return false end
  local focused=UIS:GetFocusedTextBox() if focused then focused:ReleaseFocus() end
  local selected=Brain.growth.selected
  if not selected or Brain.growthOwnership(selected)=="locked" then status("الحيوان مقفول أو غير مختار؛ لن أضغط شراء") return false end
  local old=player.Character
  stop("تجهيز نسخة جديدة من "..selected)
  local lease=Brain.suspendQuestPanel() Brain.growth.currentLease=lease
  status("إعادة ضبط ثم إنشاء نسخة من الحيوان المشتَرى")
  local alreadyCreate=findButton("create",true)
  local alreadyNew=findButton("new",true)
  local alreadyPlay=findButton("play",true)
  if not alreadyCreate and not alreadyNew and not alreadyPlay then
   Brain.pulse(Enum.KeyCode.K)
   local resetWait=os.clock()+5
   repeat task.wait(.2)if not live(seq)then return false end until os.clock()>=resetWait
  end
  if not live(seq) then if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) return false end
  while live(seq)and not Brain.focused do task.wait(.2)end
  if not live(seq)then return false end
  if not UIS.TouchEnabled and not navigation.SelectedObject then Brain.pulse(Enum.KeyCode.BackSlash)task.wait(.25)end
  local play
  if not alreadyCreate then
  if not alreadyNew then
   if not advance("play","new",seq,45)then status("لم يظهر Play بعد إعادة الضبط؛ توقفت الدورة")return false end
  end
  status("أفتح New Character وأنتظر شاشة اختيار الحيوان")
  if not advance("new",selected,seq,20)then
   if lease then lease.generation=generation end Brain.restoreQuestPanel(lease)
   status("لم تفتح شاشة الحيوان بعد New Character؛ تأكد من مساحة الحفظ")return false
  end
  end
  local animal=waitButton(selected,seq,8)
  if not animal or blocked(animal) or not click(animal) then if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) status("الحيوان غير ظاهر أو مقفول؛ ما ضغطت شراء") return false end
  local selectionDeadline=os.clock()+5 local selectedConfirmed=false
  repeat
   if not live(seq) then return false end
   for _,node in safeNodes() do
    if node:IsA("TextLabel") and not node:IsDescendantOf(gui) and visible(node) and canonical(node.Text)==canonical(selected) then
     local parent=node.Parent local inButton=false
     for _=1,3 do if not parent or parent==pg then break end if parent:IsA("GuiButton") then inButton=true break end parent=parent.Parent end
     if not inButton then selectedConfirmed=true break end
    end
   end
   if not selectedConfirmed then task.wait(.2) end
  until selectedConfirmed or os.clock()>=selectionDeadline
  if not selectedConfirmed then if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) status("ما تأكد اسم الحيوان المختار؛ ما أنشأت شخصية مختلفة") return false end
  if not randomName(seq)then return false end
  task.wait(.3)
  local create=waitButton("create",seq,5)
  if not create or blocked(create) or not click(create) then if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) status("إنشاء الحيوان غير متاح؛ تأكد أنه مشتَرى") return false end
  task.wait(1)
  play=waitButton("play",seq,10)
  if not play or not click(play) then if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) status("انتهى الإنشاء؛ تعذر تأكيد زر الدخول") return false end
  local deadline=os.clock()+40
  repeat
   if not live(seq) then if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) return false end
   if os.clock()>=(Brain.growth.nextPlay or 0)then
    local retry=findButton("play",true)if retry then click(retry)end Brain.growth.nextPlay=os.clock()+1.5
   end
   local model,root,h=rig()
   if model and model~=old and root and h and h.Health>0 then
    local actual=Brain.growthAnimal(model)local diet=model:GetAttribute("FoodType")
    if actual and canonical(actual)~=canonical(selected)then status("تغير الحيوان أثناء التكبير؛ أوقفت الدورة قبل إعادة الضبط")return false end
    if diet~=nil and string.lower(tostring(diet))~="grass"then status("الحيوان ليس عاشبًا؛ أوقفت التكبير")return false end
    local age=Brain.growthValue(model)
    if not actual and (not age or age>=99.99)then task.wait(.2)continue end
    if lease then lease.generation=generation end Brain.restoreQuestPanel(lease)
    Brain.growth.ownedEvidence[canonical(selected)]=true
    Brain.growth.awaitingYoung=model
    status("ظهرت النسخة الجديدة؛ أبحث عن أقرب ماء لرعايتها")
    return true
   end
   task.wait(.5)
  until os.clock()>=deadline
  if lease then lease.generation=generation end Brain.restoreQuestPanel(lease) status("ما تأكد ظهور الحيوان الجديد") return false
 end
 function Brain.growthCreate(seq)
  Brain.growth.transitioning=true
  local wasVisible=window.Visible window.Visible=false
  local oldNavigation=navigation.GuiNavigationEnabled local oldSelection=navigation.SelectedObject
  local ok,result=pcall(createCore,seq)
  if alive and window.Parent then window.Visible=wasVisible end
  pcall(function()navigation.SelectedObject=oldSelection navigation.GuiNavigationEnabled=oldNavigation end)
  Brain.growth.transitioning=false
  local lease=Brain.growth.currentLease Brain.growth.currentLease=nil
  if lease then lease.generation=generation Brain.restoreQuestPanel(lease) end
  if not ok then error(result) end
  return result
 end
 function Brain.growthRun(seq)
  local nextStart=0
  while live(seq) do
   local model,root,h=rig()
   if model and root and h and h.Health>0 then
    local diet=model:GetAttribute("FoodType")
    if diet~=nil and string.lower(tostring(diet))~="grass" then status("النسخة الحالية ليست عاشبة؛ اختر نسخة عاشبة من اللعبة") return end
    local actual=Brain.growthAnimal(model)
    if actual and Brain.growth.selected and canonical(actual)~=canonical(Brain.growth.selected)then status("تغير الحيوان أثناء التكبير؛ أوقفت الدورة قبل إعادة الضبط")return end
    if not Brain.growth.selected and actual then Brain.growth.selected=actual end
    local age=Brain.growthValue(model)
    if Brain.growth.awaitingYoung==model then
     if age and age<99.99 then Brain.growth.awaitingYoung=nil else age=nil end
    end
    if age and age>=100-.0001 then
     if not Brain.focused then status("ارجع لنافذة اللعبة وتأكد من دعم إرسال الأزرار قبل التكبير")task.wait(.5)continue end
     status("اكتمل النمو؛ أتحقق قبل إنشاء النسخة التالية")
     local stable=os.clock()+1
     repeat task.wait(.5) if not live(seq) then return end until os.clock()>=stable
     local current=player.Character local confirmed=Brain.growthValue(model)
     if current==model and confirmed and confirmed>=100-.0001 then
      if not Brain.growth.selected then status("اكتملت النسخة؛ اختر اسم الحيوان للنسخة التالية") return end
      if not Brain.growth.completedModels[model] then Brain.growth.completedModels[model]=true Brain.growth.completed+=1 end
      if not Brain.growthCreate(seq) then return end
      nextStart=0
     end
    else
     if (not running or Brain.mode~="Growth") and os.clock()>=nextStart then
      nextStart=os.clock()+5
      Brain.growth.driving=true
      local ok,err=pcall(Brain.start,"Growth",true)
      Brain.growth.driving=false
      if not ok then status("أعيد محاولة رعاية النسخة؛ "..tostring(err)) end
     end
     local direction=Brain.resourceGoals.Water and "رعاية مستقلة · وجهة ماء مثبتة"or "رعاية مستقلة"
     status((age and ("النمو "..string.format("%.1f%%",age)) or "أنتظر قراءة نمو مؤكدة").." • "..direction.." • المكتمل "..Brain.growth.completed)
     task.wait(1)
    end
   else
    local menu=findButton("new",true) or findButton("play",true) or findButton("create",true)
    if menu and Brain.growth.selected then
     if not Brain.growthCreate(seq) then return end
     nextStart=0
    else status("أنتظر الشخصية أو لوحة الإنشاء؛ التكبير ما زال مفعّلًا") task.wait(1) end
   end
  end
 end
 function Brain.beginGrowth()
  if Brain.taqshee and (Brain.taqshee.busy or Brain.taqshee.pending) then state("أكمل أو ألغِ التقشيع أولًا") return end
  if Brain.chatTyping then status("أكمل كتابة رسالتك لاستكمال التكبير") return end
  if Brain.growth.active then Brain.growth.active=false Brain.growth.sequence+=1 stop("أوقفت تكبير الحيوانات") return end
  if not unlocked then status("بانتظار التفعيل") return end
  local model=player.Character
  local actual=Brain.growthAnimal(model)
  if actual then Brain.growth.selected=actual end
  if running then Brain.growth.driving=true stop("أجهّز دورة التكبير")Brain.growth.driving=false end
  Brain.growth.waterModel=nil
  if not Brain.growth.selected then status("اختر الحيوان من القائمة أولًا") return end
  if Brain.growthOwnership(Brain.growth.selected)=="locked" then status("الحيوان مقفول؛ ما راح أشتريه") return end
  Brain.growth.active=true Brain.growth.sequence+=1 local seq=Brain.growth.sequence
  task.spawn(function()
   local ok,err=pcall(Brain.growthRun,seq)
   if Brain.growth.sequence==seq then
    Brain.growth.active=false
    if running and Brain.mode=="Growth"then stop("توقفت دورة التكبير")end
    if not ok then status("تعذر التكبير: "..tostring(err)) end
   end
  end)
 end
 local growthTitle=text(pages.growth,"تكبير الحيوانات",0,42,660,34,26)
 growthTitle.TextColor3=Color3.fromRGB(226,232,236)
 do
  local maintenance=text(pages.growth,"دورة تلقائية",489,4,150,29,15)
  maintenance.TextColor3=Color3.fromRGB(255,224,167)
  maintenance.BackgroundColor3=Color3.fromRGB(48,35,19)
  maintenance.BackgroundTransparency=.14
  round(maintenance,9)
  new("UIStroke",{Color=Color3.fromRGB(237,173,79),Thickness=1,Transparency=.32},maintenance)
 end
 local emblem=new("Frame",{Position=UDim2.fromOffset(310,0),Size=UDim2.fromOffset(40,36),BackgroundColor3=Color3.fromRGB(3,43,50),BackgroundTransparency=.12,BorderSizePixel=0},pages.growth)
 round(emblem,11) new("UIStroke",{Color=Color3.fromRGB(143,245,255),Thickness=1.6,Transparency=.12},emblem)
 for _,pad in {{12,17,17,12},{7,8,6,8},{16,4,7,9},{25,8,6,8}} do
  local mark=new("Frame",{Position=UDim2.fromOffset(pad[1],pad[2]),Size=UDim2.fromOffset(pad[3],pad[4]),BackgroundColor3=Color3.fromRGB(217,223,227),BorderSizePixel=0},emblem) round(mark,9)
 end
 for _,x in {182,382} do
  local line=new("Frame",{Position=UDim2.fromOffset(x,18),Size=UDim2.fromOffset(96,2),BackgroundColor3=Color3.fromRGB(93,103,113),BorderSizePixel=0},pages.growth)
  new("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.1),NumberSequenceKeypoint.new(1,1)})},line)
 end
 local note=text(pages.growth,"يكمل الحالية إلى 100% ثم ينشئ التالية. للعواشب فقط؛ يبحث عن موارد حول الشخصية.",0,78,660,30,14)
 note.TextWrapped=true
 local selection
 local list=new("ScrollingFrame",{Position=UDim2.fromOffset(54,156),Size=UDim2.fromOffset(552,136),CanvasSize=UDim2.fromOffset(0,#catalog*38+8),BackgroundColor3=Color3.fromRGB(11,13,16),BackgroundTransparency=.06,BorderSizePixel=0,ScrollBarThickness=4,Visible=false,Active=true,ZIndex=55},pages.growth)
 round(list,14) new("UIStroke",{Color=white,Transparency=.6,Thickness=1},list)
 local function refresh()
  if not Brain.growth.selected then Brain.growth.selected=Brain.growthAnimal(player.Character) end
  selection.Text=Brain.growth.selected and ("⌄     "..Brain.growth.selected.."     •") or "اختر الحيوان  ▾"
  for _,child in list:GetChildren() do if child:IsA("TextButton") then child:Destroy() end end
  for i,name in catalog do
   local evidence=Brain.growthOwnership(name)
   local label=evidence=="confirmed" and "مؤكد من اللعبة" or (evidence=="locked" and "مقفل" or "الملكية غير مقروءة")
   local item=button(list,name.."  •  "..label,8,4+(i-1)*38,536,function()
    if Brain.growth.active then return end
    Brain.growth.selected=name list.Visible=false refresh()
   end)
   item.Size=UDim2.fromOffset(536,34) item.ZIndex=56 item.TextSize=14
  end
 end
 selection=button(pages.growth,"اختر الحيوان  ▾",62,116,366,function()
  if Brain.growth.active then status("أوقف التكبير قبل تغيير الحيوان") return end
  refresh() list.Visible=not list.Visible
 end)
 button(pages.growth,"تحديث الملكية  ↻",446,116,152,refresh)
 local growthStatus=text(pages.growth,Brain.growth.status,36,173,588,38,16) growthStatus.TextWrapped=true
 growthStatus.BackgroundColor3=Color3.fromRGB(8,41,48) growthStatus.BackgroundTransparency=.24
 round(growthStatus,10) new("UIStroke",{Color=Color3.fromRGB(102,112,122),Transparency=.45,Thickness=1},growthStatus)
 local growthToggle=Brain.primaryButton(button(pages.growth,"تشغيل التكبير",30,228,600,function() list.Visible=false refresh() Brain.beginGrowth() end))
 growthToggle.Size=UDim2.fromOffset(600,46) growthToggle.TextSize=20
 refresh()
 task.spawn(function() while alive do growthStatus.Text=Brain.growth.status growthToggle.Text=Brain.growth.active and "إيقاف التكبير"or "تشغيل التكبير"growthToggle.TextColor3=Brain.growth.active and Color3.fromRGB(255,189,177)or Color3.fromRGB(183,255,216)task.wait(.2)end end)
end
local foodText=text(pages.survival,"الشبع  —",0,10,315,28,17)
local waterText=text(pages.survival,"الارتواء  —",335,10,315,28,17)
local fills={}
for i,x in {0,335} do
	local track=new("Frame",{Position=UDim2.fromOffset(x,47),Size=UDim2.fromOffset(315,7),BackgroundColor3=Color3.fromRGB(24,26,29),BorderSizePixel=0},pages.survival)
	fills[i]=new("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=Color3.fromRGB(110,236,248),BorderSizePixel=0},track)
 round(track,5) round(fills[i],5)
 new("UIStroke",{Color=Color3.fromRGB(132,198,211),Transparency=.65,Thickness=1},track)
end
mainToggle=button(pages.survival,"تشغيل البقاء",0,60,660,function()
 start("Survival")
end)
Brain.primaryButton(mainToggle)
mainToggle.Position=UDim2.fromOffset(30,76) mainToggle.Size=UDim2.fromOffset(600,56) mainToggle.TextSize=25 mainToggle.Font=Enum.Font.ArialBold mainToggle.BackgroundTransparency=.35
mainToggle:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,26)
local decisionText=text(pages.survival,"جاهز عندما تحتاجه",0,172,660,32,21) decisionText.Font=Enum.Font.ArialBold
text(pages.survival,"أقرب ماء وعشب حولك • يبدأ تحت 70% ويكمل إلى 100%",0,205,660,28,16)
text(pages.survival,"الشرب عند وجود ماء متاح  •  وجبة تلقائية عند وصول الجوع  •  بدون الرجوع للاختيار اليدوي",0,234,660,24,12)
for _,x in {176,374} do
 local line=new("Frame",{Position=UDim2.fromOffset(x,156),Size=UDim2.fromOffset(108,1),BackgroundColor3=white,BackgroundTransparency=.45,BorderSizePixel=0},pages.survival)
 new("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})},line)
end
local crown=new("Frame",{Position=UDim2.fromOffset(317,144),Size=UDim2.fromOffset(26,22),BackgroundTransparency=1},pages.survival)
for _,l in {{2,6,12,1,47},{8,6,12,1,-47},{16,6,12,1,-47},{13,6,10,1,47},{5,18,17,1,0}} do
 new("Frame",{Position=UDim2.fromOffset(l[1],l[2]),Size=UDim2.fromOffset(l[3],l[4]),Rotation=l[5],BackgroundColor3=white,BackgroundTransparency=.25,BorderSizePixel=0},crown)
end
local play=new("Frame",{Position=UDim2.fromOffset(190,18),Size=UDim2.fromOffset(20,22),BackgroundTransparency=1},mainToggle)
for _,l in {{2,2,2,18,0},{3,2,19,2,30},{3,19,19,2,-30}} do
 new("Frame",{Position=UDim2.fromOffset(l[1],l[2]),Size=UDim2.fromOffset(l[3],l[4]),Rotation=l[5],BackgroundColor3=Color3.fromRGB(132,243,251),BorderSizePixel=0,ZIndex=4},play)
end
on(mainToggle:GetPropertyChangedSignal("Text"),function() play.Visible=not mainToggle.Text:find("إيقاف",1,true) end)
do
 local http=game:GetService("HttpService")
 local file="BLY_Anywhere_PC_Settings_"..tostring(player.UserId)..".json"
 local function applyPreferences(data)
  if typeof(data)~="table" or data.version~=1 or data.userId~=player.UserId then return end
  if data.runMode=="Hold" or data.runMode=="Toggle" or data.runMode=="Off" then
   CFG.RunMode=data.runMode
   CFG.AutoRun=data.runMode~="Off"
  end
  if data.boost==1 or data.boost==1.1 or data.boost==1.2 or data.boost==1.35 then CFG.BoostFactor=data.boost end
  if typeof(data.background)=="boolean" then CFG.Background=data.background end
  if typeof(data.antiAFK)=="boolean" then CFG.AntiAFK=data.antiAFK end
  if typeof(data.markers)=="boolean" then Atlas.visible=data.markers end
  if typeof(data.foodMarkers)=="boolean" then CFG.CarcassMarkers=data.foodMarkers end
  if typeof(data.autoClaim)=="boolean" then CFG.AutoClaim=data.autoClaim end
 end
 if typeof(readfile)=="function" then
  pcall(function()
   local raw=readfile(file)
   if typeof(raw)=="string" and #raw<=2048 then applyPreferences(http:JSONDecode(raw)) end
  end)
 end
 Brain.saveSettingsButton=button(pages.settings,"حفظ الإعدادات",24,271,612,function()
  if typeof(writefile)~="function" or typeof(readfile)~="function" then
   state("المشغّل ما يدعم حفظ الإعدادات على الجهاز")
   return
  end
  local ok=pcall(function()
   local raw=http:JSONEncode({
    version=1,userId=player.UserId,runMode=CFG.RunMode,boost=CFG.BoostFactor,
    background=CFG.Background,antiAFK=CFG.AntiAFK,markers=Atlas.visible,autoClaim=CFG.AutoClaim,foodMarkers=CFG.CarcassMarkers==true,
   })
   writefile(file,raw)
   assert(readfile(file)==raw)
  end)
  state(ok and "تم حفظ إعداداتك على هذا الجهاز" or "تعذر حفظ الإعدادات على الجهاز")
 end)
end
do
 local emblem=new("Frame",{Position=UDim2.fromOffset(309,1),Size=UDim2.fromOffset(42,40),BackgroundColor3=Color3.fromRGB(5,39,46),BorderSizePixel=0},pages.settings)
 round(emblem,10)
 new("UIStroke",{Color=Color3.fromRGB(131,249,255),Thickness=1.5,Transparency=.11},emblem)
 local glyph=text(emblem,"⚙",0,0,42,40,28)
 glyph.TextColor3=Color3.fromRGB(157,249,255)
 local title=text(pages.settings,"S7M × BLY",0,42,660,28,21)
 title.Font=Enum.Font.Bodoni
end
local speedButton
speedButton=button(pages.settings,"الركض: "..(CFG.RunMode=="Hold" and "Shift مستمر" or CFG.RunMode=="Toggle" and "Shift تبديل مرة" or "إيقاف"),24,73,612,function()
	if running then stop("أوقفت البقاء لتغيير وضع الركض") end
	if CFG.RunMode=="Hold" then CFG.RunMode="Toggle" CFG.AutoRun=true
	elseif CFG.RunMode=="Toggle" then CFG.RunMode="Off" CFG.AutoRun=false
	else CFG.RunMode="Hold" CFG.AutoRun=true end
	speedButton.Text="الركض: "..(CFG.RunMode=="Hold" and "Shift مستمر" or CFG.RunMode=="Toggle" and "Shift تبديل مرة" or "إيقاف")
end)
local backgroundButton
backgroundButton=button(pages.settings,"المتابعة بالخلفية: "..(CFG.Background and "تشغيل تجريبي" or "إيقاف"),24,108,612,function()
	CFG.Background=not CFG.Background
	backgroundButton.Text="المتابعة بالخلفية: "..(CFG.Background and "تشغيل تجريبي" or "إيقاف")
	if running and not Brain.focused and not CFG.Background then stop("متابعة الخلفية مغلقة") end
end)
local imageNote=text(pages.settings,imageState,24,178,612,20,12)
local boostButton
boostButton=button(pages.settings,"زيادة سرعة تجريبية: "..(CFG.BoostFactor==1 and "إيقاف" or tostring(CFG.BoostFactor).."×"),24,143,612,function()
	if running then stop("أوقفت البقاء لتغيير زيادة السرعة") end
	if CFG.BoostFactor==1 then CFG.BoostFactor=1.1
	elseif CFG.BoostFactor==1.1 then CFG.BoostFactor=1.2
	elseif CFG.BoostFactor==1.2 then CFG.BoostFactor=1.35
	else CFG.BoostFactor=1 end
	Brain.boostBase=nil
	boostButton.Text="زيادة سرعة تجريبية: "..(CFG.BoostFactor==1 and "إيقاف" or tostring(CFG.BoostFactor).."×")
end)
local markerButton
markerButton=button(pages.settings,"علامات ذاكرة الموارد: "..(Atlas.visible and "تشغيل" or "إيقاف"),24,201,612,function()
	Atlas.visible=not Atlas.visible Atlas.lastDraw=0
	if not Atlas.visible and Atlas.folder then Atlas.folder:ClearAllChildren() end
	markerButton.Text="علامات ذاكرة الموارد: "..(Atlas.visible and "تشغيل" or "إيقاف")
end)
local afkButton
afkButton=button(pages.settings,"منع الخمول: "..(CFG.AntiAFK and "تشغيل" or "إيقاف"),24,236,612,function()
 CFG.AntiAFK=not CFG.AntiAFK
 afkButton.Text="منع الخمول: "..(CFG.AntiAFK and "تشغيل" or "إيقاف")
end)
do
 for _,child in pages.settings:GetChildren() do
  if child:IsA("TextButton") then
   child.Size=UDim2.fromOffset(612,30)
   child.TextSize=15
   local kind=child==speedButton and "survival" or child==backgroundButton and "diagnostics"
    or child==boostButton and "settings" or child==markerButton and "looks" or child==afkButton and "about" or "quests"
   Brain.tabIcon(child,kind)
  end
 end
end
debugText=new("TextBox",{Position=UDim2.fromOffset(22,11),Size=UDim2.fromOffset(616,205),BackgroundColor3=Color3.fromRGB(11,13,16),BackgroundTransparency=.15,
	Text="جارٍ قراءة الماب…",TextColor3=white,TextSize=12,Font=Enum.Font.Gotham,TextWrapped=true,MultiLine=true,TextEditable=false,ClearTextOnFocus=false,
	TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},pages.diagnostics)
debugText.Visible=false
local diagnosticCard=new("Frame",{Size=UDim2.fromOffset(660,215),BackgroundTransparency=1,BorderSizePixel=0},pages.diagnostics)
text(diagnosticCard,"⌕",0,4,660,37,34).TextColor3=Color3.fromRGB(150,249,255)
text(diagnosticCard,"حالة البوت",18,40,624,33,23)
local calmState=text(diagnosticCard,"جاهز",18,74,624,29,15)
local calmNeeds=text(diagnosticCard,"الشبع  —",334,111,125,35,15)
Brain.diagnosticWater=text(diagnosticCard,"الارتواء  —",201,111,125,35,15)
for _,chip in {calmNeeds,Brain.diagnosticWater} do
 chip.BackgroundColor3=Color3.fromRGB(5,43,51)
 chip.BackgroundTransparency=.18
 chip.TextColor3=Color3.fromRGB(166,250,255)
 round(chip,11)
 new("UIStroke",{Color=Color3.fromRGB(106,209,224),Transparency=.21,Thickness=1},chip)
end
local calmGoal=text(diagnosticCard,"",18,152,624,31,14)
round(debugText,12)
new("UIStroke",{Color=white,Transparency=.86,Thickness=1},debugText)
button(pages.diagnostics,"نسخ سجل الحركة",25,226,194,function()
	local copy=setclipboard or toclipboard
	local ok=typeof(copy)=="function" and pcall(function() copy(Brain.exportTrace()) end)
	state(ok and "تم نسخ السجل؛ الصقه في المحادثة" or "تعذر نسخ السجل في هذا المشغّل")
end)
button(pages.diagnostics,"حفظ موقع الشرب",233,226,194,function()
	if not unlocked then state("بانتظار تفعيل الإدارة") return end
	if running then stop("أوقفت الحركة لحفظ نقطة الشرب") end
	local model,root=rig()
	if not model or not root or not prompt("Water") then state("الحفظ يتطلب ظهور رسالة الشرب الحقيقية عند هذه النقطة") return end
	rememberWater(model,root)
	state(knownShore and "حفظت نقطة الشرب وأقرب يابسة مؤكدة لهذه الجلسة" or "رصدت خيار الشرب؛ لم أجد يابسة مجاورة أستطيع تأكيدها")
end)
button(pages.diagnostics,"التفاصيل",441,226,194,function()
	debugText.Visible=not debugText.Visible diagnosticCard.Visible=not debugText.Visible
end)
local questText=new("Frame",{Size=UDim2.fromOffset(660,315),BackgroundColor3=Color3.fromRGB(10,12,15),BorderSizePixel=0,Visible=false,Active=true,ZIndex=30},pages.quests)
round(questText,18)
local detailsTitle=text(questText,"مهامك",18,9,440,34,22) detailsTitle.ZIndex=32
local questScroll=new("ScrollingFrame",{Position=UDim2.fromOffset(8,54),Size=UDim2.new(1,-16,1,-64),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=4,ScrollBarImageColor3=Color3.fromRGB(188,194,198),ZIndex=31},questText)
new("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder},questScroll)
new("UIPadding",{PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,10),PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)},questScroll)
Brain.questDetailSignature=nil
function Brain.renderQuestDetails()
 if not questText.Visible then return end
 local rows={}
 for _,q in Brain.readQuests() do if q.kind then table.insert(rows,q) end end
 local signature={Brain.groupStatus or ""}
 for _,q in rows do table.insert(signature,q.key..":"..q.current.."/"..q.target) end
 local joined=table.concat(signature,"|")
 if joined==Brain.questDetailSignature then return end
 Brain.questDetailSignature=joined
 for _,child in questScroll:GetChildren() do if child:IsA("Frame") then child:Destroy() end end
 local function card(title,value,hint,ratio,index,active)
  local frame=new("Frame",{Size=UDim2.new(1,-8,0,112),BackgroundColor3=Color3.fromRGB(17,19,22),BackgroundTransparency=.12,BorderSizePixel=0,LayoutOrder=index,ZIndex=32},questScroll)
  round(frame,14) new("UIStroke",{Color=Color3.fromRGB(194,200,204),Transparency=active and .25 or .76,Thickness=1},frame)
  local heading=text(frame,title,14,8,430,29,18) heading.Font=Enum.Font.ArialBold heading.ZIndex=33 heading.TextXAlignment=Enum.TextXAlignment.Right
  local count=text(frame,value,460,10,140,26,16) count.ZIndex=33
  local track=new("Frame",{Position=UDim2.fromOffset(14,45),Size=UDim2.new(1,-28,0,5),BackgroundColor3=Color3.fromRGB(29,31,34),BorderSizePixel=0,ZIndex=33},frame) round(track,3)
  local fill=new("Frame",{Size=UDim2.fromScale(math.clamp(ratio,0,1),1),BackgroundColor3=Color3.fromRGB(192,198,202),BorderSizePixel=0,ZIndex=34},track) round(fill,3)
  local info=text(frame,hint,14,60,586,43,16) info.Font=Enum.Font.Arial info.ZIndex=33 info.TextXAlignment=Enum.TextXAlignment.Right info.TextYAlignment=Enum.TextYAlignment.Top
 end
 if #rows==0 then card("ما قرأت المهمات للحين","","شغّل المهمات أو حدّث القائمة، وتأكد أن لوحة اللعبة تفتح.",0,1,false) end
 for index,q in rows do
  if index>24 then break end
  local tier=q.title:match("%s([IV]+)$") or ""
  card((Brain.questLabels[q.kind] or q.title)..(tier~="" and " • "..tier or ""),q.current.." / "..q.target,Brain.questHint(q),q.current/q.target,index,q.key==Brain.activeQuest)
 end
end
local detailsBack=button(questText,"رجوع",530,12,110,function() questText.Visible=false end) detailsBack.ZIndex=35
local questCard=new("Frame",{Size=UDim2.fromOffset(660,190),BackgroundTransparency=1,BorderSizePixel=0},pages.quests)
text(questCard,"مهمتك الحالية",28,10,180,22,13)
do
 local maintenance=text(questCard,"تنفيذ تلقائي",255,7,150,29,15)
 maintenance.TextColor3=Color3.fromRGB(255,224,167)
 maintenance.BackgroundColor3=Color3.fromRGB(48,35,19)
 maintenance.BackgroundTransparency=.14
 round(maintenance,9)
 new("UIStroke",{Color=Color3.fromRGB(237,173,79),Thickness=1,Transparency=.32},maintenance)
end
local questType=text(questCard,"جاهز",470,10,170,22,11)
local calmQuestTitle=text(questCard,"اختر تشغيل المهمات",18,43,624,34,21)
local calmQuestProgress=text(questCard,"فعّل المدير لبدء التنفيذ",18,78,624,25,15)
local progressTrack=new("Frame",{Position=UDim2.fromOffset(24,117),Size=UDim2.fromOffset(612,3),BackgroundColor3=Color3.fromRGB(17,67,76),BorderSizePixel=0},questCard)
round(progressTrack,2)
local calmQuestFill=new("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=Color3.fromRGB(131,245,255),BorderSizePixel=0},progressTrack)
round(calmQuestFill,2)
local calmQuestHint=text(questCard,"القائمة الكاملة والتفاصيل من زر ⋯",24,142,610,38,13)
calmQuestHint.BackgroundColor3=Color3.fromRGB(5,38,43)
calmQuestHint.BackgroundTransparency=.22
round(calmQuestHint,12)
local questDetails=button(pages.quests,"⋯",590,148,34,function()
	questText.Visible=not questText.Visible
 if questText.Visible then Brain.questDetailSignature=nil Brain.renderQuestDetails() end
end)
questDetails.Size=UDim2.fromOffset(30,26) questDetails.ZIndex=20
round(questText,12)
new("UIStroke",{Color=white,Transparency=.86,Thickness=1},questText)
questToggle=button(pages.quests,"تشغيل المهمات",22,195,616,function()
 start("Quests")
end)
Brain.primaryButton(questToggle)
local claimToggle
claimToggle=button(pages.quests,"استلام المكتمل: "..(CFG.AutoClaim and "تشغيل" or "إيقاف"),22,244,302,function()
	CFG.AutoClaim=not CFG.AutoClaim Brain.nextQuestScan=0
	claimToggle.Text="استلام المكتمل: "..(CFG.AutoClaim and "تشغيل" or "إيقاف")
end)
button(pages.quests,"تحديث المهمات",336,244,302,function()
	Brain.nextQuestScan=0
	state("القراءة عند تشغيل مدير المهمات وعودة التركيز للعبة")
end)
text(pages.quests,"المهام: قروب • سباحة • بقاء • وقت لعب • مشي • شخصية • مناطق",0,296,660,18,10)
Brain.timing={enabled=false,circles={},actions=setmetatable({},{__mode="k"}),samples=setmetatable({},{__mode="k"}),fired=setmetatable({},{__mode="k"}),nextScan=0,active=false}
function Brain.policy.ringHit(previous,current,target,dt,minimum)
 if type(previous)~="number"or type(current)~="number"or type(target)~="number"or target<(minimum or 24)or dt<=0 or dt>.25 then return false end
 local step=current-previous if math.abs(step)/dt<=.5 then return false end
 local gap=current-target local tolerance=math.max(1.5,target*.025)
 if math.abs(gap)<=tolerance then return true end
 local lead=math.min(math.abs(step)*.5,tolerance)
 return gap*step<0 and math.abs(gap)<=tolerance+lead
end
function Brain.escapePromptKind(value)
 local text=string.lower(tostring(value or ""))
 if text:find("space",1,true)then return "key"end
 if text:find("tap",1,true)or text:find("touch",1,true)or text:find("click",1,true)or text:find("انقر",1,true)or text:find("المس",1,true)then return "pointer"end
 if text:find("اضغط",1,true)then return "key"end
end
function Brain.escapeScreen(name)
 local name=string.lower(tostring(name or ""))
 return name:find("minigame",1,true)or name:find("struggle",1,true)or name:find("grab",1,true)or name:find("pounce",1,true)or name:find("pinned",1,true)or name:find("qte",1,true)
end
function Brain.timingScan()
 local timing=Brain.timing if timing.scanning then return end timing.scanning=true
 local ok,result,actions=pcall(function()
  local queue={}local delayed={}local prompts={}local explicit={}
  for _,screen in pg:GetChildren()do
   if screen~=gui and not screen:IsDescendantOf(gui)then
    if Brain.escapeScreen(screen.Name)then table.insert(queue,screen)explicit[screen]=true else table.insert(delayed,screen)end
   end
  end
  for _,screen in delayed do table.insert(queue,screen)end
  local index=1
  while index<=#queue and index<=900 and alive and timing.enabled do
   local node=queue[index]index+=1
   if node~=gui and not node:IsDescendantOf(gui)then
    if node:IsA("GuiObject")and visible(node)then
     local value
     if node:IsA("TextLabel")or node:IsA("TextButton")then value=node.Text
     elseif node:IsA("ImageLabel")or node:IsA("ImageButton")then value=node.Name end
     local kind=value and(Brain.escapePromptKind(value)or Brain.escapePromptKind(node.Name))
     if kind then table.insert(prompts,{node=node,kind=kind})end
    end
    for _,child in node:GetChildren()do table.insert(queue,child)end
   end
   if index%100==0 then task.wait()end
  end
  for screen in explicit do if(screen:IsA("ScreenGui")and screen.Enabled)or(screen:IsA("GuiObject")and visible(screen))then table.insert(prompts,{node=screen,kind=(UIS.TouchEnabled and not UIS.KeyboardEnabled)and "pointer"or "key",context=true})end end
  local circles={}local seen={}local actions={}
  for _,prompt in prompts do
   local node=prompt.node local center if not prompt.context then center=node.AbsolutePosition+node.AbsoluteSize/2 end
   local button=node
   for _=1,4 do if not button or button==pg or button:IsA("GuiButton")then break end button=button.Parent end
   if not button or button==pg or not button:IsA("GuiButton")then button=nil end
   local ancestor=prompt.context and node or node.Parent
   for _=1,7 do
    if not ancestor or ancestor==pg then break end
    local items={ancestor}local at=1 local found={}
    while at<=#items and at<=160 do
     local item=items[at]at+=1
     if item:IsA("GuiObject")and visible(item)then
      local size=item.AbsoluteSize local name=string.lower(item.Name)local corner=item:FindFirstChildOfClass("UICorner")
      local round=(corner and corner.CornerRadius.Scale>=.4)or name:find("circle",1,true)or name:find("ring",1,true)or name:find("target",1,true)or item:IsA("ImageLabel")
      local middle=item.AbsolutePosition+size/2
      local near=prompt.context or(math.abs(middle.X-center.X)<240 and middle.Y<=center.Y+60 and middle.Y>=center.Y-440)
      if round and near and size.X>=12 and size.X<=500 and math.abs(size.X-size.Y)<=size.X*.12 then table.insert(found,item)end
     end
     for _,child in item:GetChildren()do table.insert(items,child)end
    end
    if #found>=2 then
     for _,item in found do
      if not seen[item]and #circles<16 then seen[item]=true table.insert(circles,item)end
      local candidate=button
      if not candidate then local parent=item for _=1,4 do if not parent or parent==pg then break end if parent:IsA("GuiButton")then candidate=parent break end parent=parent.Parent end end
      if not actions[item]or(candidate and not actions[item].button)then actions[item]={kind=prompt.kind,button=candidate,target=candidate or item,minimum=12}end
     end
     break
    end
    ancestor=ancestor.Parent
   end
  end
  return circles,actions
 end)
 if ok then timing.circles=result timing.actions=actions timing.status=#result>=2 and("رصد "..#result.." دوائر")or "لم أتعرف على الدائرة"
 else timing.status="تعذر فحص الواجهة"timing.lastError=tostring(result)end
 timing.scanning=false
end
function Brain.escapeInput(action)
 if not alive or not unlocked or not Brain.focused or Brain.chatTyping or UIS:GetFocusedTextBox()or not inputOwnerValid()then return false end
 local button=action and(action.button or action.target)
 if button and(action.kind=="pointer"or(UIS.TouchEnabled and not UIS.KeyboardEnabled))and button.Parent and visible(button)and button:IsA("GuiObject")then
  local center=button.AbsolutePosition+button.AbsoluteSize/2
  local ok,hits=pcall(function()return pg:GetGuiObjectsAtPosition(center.X,center.Y)end)local target=false
  if ok then
   for _,hit in hits do
    if hit==button or hit:IsDescendantOf(button)then target=true break end
    if not button:IsDescendantOf(hit)then break end
   end
  end
  if target and Brain.compatPointer(0,true,center.X,center.Y)then
   local pinned=Brain.compat.heldPointers[0]
   task.delay(.02,function()if Brain.compat.heldPointers[0]==pinned then Brain.compatPointer(0,false,center.X,center.Y)end end)
   Brain.timing.lastTransport="pointer"return true
  end
 end
 local ok,pressed=pcall(Brain.pulse,Enum.KeyCode.Space,.02)
 if ok and pressed then Brain.timing.lastTransport="Space"return true end
 if not ok then Brain.timing.lastError=tostring(pressed)end
 return false
end
function Brain.timingTick()
 local timing=Brain.timing
 if not timing.enabled or not unlocked or not Brain.focused or UIS:GetFocusedTextBox()then timing.active=false timing.status="بانتظار التركيز والتفعيل"return end
 local now=os.clock()if now>=timing.nextScan then timing.nextScan=now+.12 task.spawn(Brain.timingScan)end
 local sizes={}
 for _,circle in timing.circles do
  if circle.Parent and visible(circle)then local size=circle.AbsoluteSize sizes[circle]={size=size.X,center=circle.AbsolutePosition+size/2}end
 end
 local engaged=false
 for circle in timing.samples do if not sizes[circle]then timing.samples[circle]=nil timing.fired[circle]=nil end end
 for moving,value in sizes do
  local before=timing.samples[moving]
  if before then
   local delta=value.size-before.size local dt=now-before.at
   local resetting=delta>math.max(4,value.size*.15)
   if resetting then timing.fired[moving]=nil end
   if not resetting and math.abs(delta)>.05 and dt>0 and dt<=.25 then
    local targetSize
    for other,otherValue in sizes do
     local previous=timing.samples[other]
     if other~=moving and previous and math.abs(previous.size-otherValue.size)<.5 and(value.center-otherValue.center).Magnitude<math.max(5,otherValue.size*.08)then
      if otherValue.size>=value.size*.4 and otherValue.size<=value.size*2.5 and(not targetSize or math.abs(value.size-otherValue.size)<math.abs(value.size-targetSize))then targetSize=otherValue.size end
     end
    end
    if targetSize then
     if not timing.fired[moving]then engaged=true end
     timing.status="متابعة تطابق الحلقة"
     local action=timing.actions and timing.actions[moving]
     if not timing.fired[moving]and timing.lastPress~=now and Brain.policy.ringHit(before.size,value.size,targetSize,dt,action and action.minimum)then
      timing.lastTry=now
      if Brain.escapeInput(action)then timing.fired[moving]=true timing.lastPress=now engaged=false timing.status="أُرسلت محاولة الفك"
      else timing.status="تعذر إرسال محاولة الفك"end
     end
    end
   end
  end
 end
 for circle,value in sizes do timing.samples[circle]={size=value.size,at=now}end timing.active=engaged
end
on(Run.RenderStepped,function()
 if Brain.timing.enabled then local ok,err=pcall(Brain.timingTick)if not ok then Brain.timing.active=false Brain.timing.status="تعذر قراءة الدائرة"Brain.timing.lastError=tostring(err)end end
end)
Brain.war={enabled=false,rows={},target=nil,counts={deaths=0,respawns=0,unconfirmed=0,leaves=0,returns=0}}
function Brain.warRecord(event)
 local war=Brain.war local counts=war.counts
 if event=="death" then counts.deaths+=1
 elseif event=="respawn" then counts.respawns+=1
 elseif event=="unconfirmed" then counts.unconfirmed+=1
 elseif event=="leave" then counts.leaves+=1
 elseif event=="return" then counts.returns+=1 end
end
function Brain.warClearVisual(row)
 if row.label then row.label:Destroy() row.label=nil end
 if row.highlight then row.highlight:Destroy() row.highlight=nil end
 row.visualRoot=nil
end
function Brain.warBindCharacter(row,character)
 if row.character==character then return end
 if row.character and row.player.UserId==Brain.war.target then
  Brain.warRecord("respawn")
  if not row.died then Brain.warRecord("unconfirmed") end
 end
 if row.deathConnection then row.deathConnection:Disconnect() row.deathConnection=nil end
 Brain.warClearVisual(row) row.character=character row.humanoid=nil row.died=false row.seenAlive=false
end
function Brain.warAttach(person)
 if person==player then return end
 local war=Brain.war
 local old=war.rows[person.UserId]
 if old then return end
 local row={player=person} war.rows[person.UserId]=row
 row.character=person.Character row.died=false
 row.spawnConnection=person.CharacterAdded:Connect(function(character)
  if alive and war.rows[person.UserId]==row then Brain.warBindCharacter(row,character) end
 end)
 if war.target==person.UserId and war.targetLeft then war.targetLeft=false Brain.warRecord("return") end
 if (war.enabled or war.target==person.UserId) and Brain.warTick then pcall(Brain.warTick) end
end
function Brain.warDetach(person)
 local war=Brain.war local row=war.rows[person.UserId]
 if not row or row.player~=person then return end
 if war.target==person.UserId then war.targetLeft=true Brain.warRecord("leave") end
 if row.spawnConnection then row.spawnConnection:Disconnect() end
 if row.deathConnection then row.deathConnection:Disconnect() end
 Brain.warClearVisual(row) war.rows[person.UserId]=nil
end
function Brain.warSelect(name)
 local wanted=string.lower(tostring(name or "")):gsub("^%s+",""):gsub("%s+$",""):gsub("^@","")
 if wanted=="" then return nil,"اكتب اسم حساب Roblox" end
 local matches={} local exact
 for _,person in Players:GetPlayers() do
  if person~=player then
   if string.lower(person.Name)==wanted or tostring(person.UserId)==wanted then exact=person break end
   if string.lower(person.Name):sub(1,#wanted)==wanted or string.lower(person.DisplayName or "")==wanted then table.insert(matches,person) end
  end
 end
 local chosen=exact or (#matches==1 and matches[1])
 if not chosen then return nil,#matches>1 and "الاسم يطابق أكثر من لاعب؛ اكتب اليوزر كامل" or "اللاعب غير موجود في هذا السيرفر" end
 local war=Brain.war
 war.target=chosen.UserId war.targetName=chosen.Name war.targetLeft=false war.started=os.clock()
 war.counts={deaths=0,respawns=0,unconfirmed=0,leaves=0,returns=0}
 return chosen
end
function Brain.warTick()
 local war=Brain.war local _,ownRoot=rig()
 local ordered={} local occupied={}
 for id,row in war.rows do
  local model=row.player.Character local root=model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
  local distance=root and ownRoot and (root.Position-ownRoot.Position).Magnitude or math.huge
  table.insert(ordered,{id=id,row=row,distance=distance})
 end
 table.sort(ordered,function(a,b)
  if (a.id==war.target)~=(b.id==war.target) then return a.id==war.target end
  if a.distance==b.distance then return a.id<b.id end
  return a.distance<b.distance
 end)
 for _,item in ordered do
  local id,row=item.id,item.row
  local character=row.player.Character
  if character and character~=row.character then Brain.warBindCharacter(row,character) end
  local model=row.character local h=model and model:FindFirstChildOfClass("Humanoid")
  if h and row.humanoid~=h then
   if row.deathConnection then row.deathConnection:Disconnect() end
   row.humanoid=h
   row.deathConnection=h.Died:Connect(function()
    if alive and war.rows[id]==row and row.humanoid==h and not row.died then
     row.died=true
     if war.target==id then Brain.warRecord("death") end
    end
   end)
  end
  if h and typeof(h.Health)=="number" then
   if h.Health>0 then row.seenAlive=true
   elseif row.seenAlive and not row.died then
    row.died=true
    if war.target==id then Brain.warRecord("death") end
   end
  end
  local root=model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
  if war.enabled and root and model.Parent then
   if row.visualRoot~=root then
    Brain.warClearVisual(row) row.visualRoot=root
    row.highlight=new("Highlight",{Adornee=model,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,FillTransparency=.9,FillColor=Color3.fromRGB(65,75,85),OutlineTransparency=.05,OutlineColor=Color3.fromRGB(90,100,110)},gui)
    row.label=new("BillboardGui",{Adornee=root,Size=UDim2.fromOffset(148,22),StudsOffsetWorldSpace=Vector3.new(0,3.5,0),AlwaysOnTop=true,MaxDistance=10000},gui)
    row.text=new("TextLabel",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(8,10,13),BackgroundTransparency=1,TextColor3=Color3.fromRGB(207,213,217),TextStrokeColor3=Color3.fromRGB(5,7,10),TextStrokeTransparency=.1,TextSize=11,Font=Enum.Font.GothamBold,TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd},row.label)
    round(row.text,10)
   end
   local distance=ownRoot and (root.Position-ownRoot.Position).Magnitude
   row.text.Text="@"..row.player.Name..(distance and " • "..string.format("%.0f",distance).." studs" or "")
   local camera=workspace.CurrentCamera local show=true
   if camera then
    local screen,onScreen=camera:WorldToViewportPoint(root.Position+Vector3.new(0,3.5,0))
    show=onScreen
    if show and id~=war.target then
     for _,taken in occupied do if math.abs(screen.X-taken.X)<150 and math.abs(screen.Y-taken.Y)<24 then show=false break end end
    end
    if show then table.insert(occupied,screen) end
   end
   row.label.Enabled=show
   row.highlight.OutlineColor=id==war.target and Color3.fromRGB(255,218,135) or Color3.fromRGB(90,100,110)
  else Brain.warClearVisual(row) end
 end
end
for _,person in Players:GetPlayers() do Brain.warAttach(person) end
on(Players.PlayerAdded,Brain.warAttach) on(Players.PlayerRemoving,Brain.warDetach)
function Brain.createWarUI()
 local function warCard(x,y,width,height)
  local card=new("Frame",{
   Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,height),
   BackgroundColor3=Color3.fromRGB(3,28,34),BackgroundTransparency=.16,BorderSizePixel=0,
  },pages.war)
  round(card,13)
  new("UIStroke",{Color=Color3.fromRGB(85,208,227),Thickness=1.1,Transparency=.42},card)
  return card
 end
 local aimCard=warCard(0,0,212,117)
 text(aimCard,"قفل التصويب",6,7,200,21,16).TextColor3=Color3.fromRGB(163,231,245)
 text(aimCard,"ثبّت الكاميرا على هدفك المختار",6,30,200,17,11)
 local aimStatus=text(aimCard,"القفل متوقف",6,92,200,18,11)
 local aimButton
 local aimBinding="BLY_WAR_AIM_LOCK"
 local aimEnabled=false
 local aimMarker=new("BillboardGui",{
  Name="BLY_AimMarker",Size=UDim2.fromOffset(114,28),StudsOffsetWorldSpace=Vector3.new(0,4.6,0),
  AlwaysOnTop=false,Enabled=false,MaxDistance=10000,
 },gui)
 local aimBadge=text(aimMarker,"◉  قفل التصويب",0,0,114,28,13)
 aimBadge.BackgroundColor3=Color3.fromRGB(6,24,34)
 aimBadge.BackgroundTransparency=.17
 aimBadge.TextColor3=Color3.fromRGB(153,235,255)
 round(aimBadge,9)
 new("UIStroke",{Color=aimBadge.TextColor3,Thickness=1,Transparency=.35},aimBadge)
 local function clearAimMarker(message)
  aimMarker.Enabled=false
  aimMarker.Adornee=nil
  aimStatus.Text=message
 end
 local function updateAim()
  if not unlocked or not Brain.focused or running or UIS:GetFocusedTextBox() then
   clearAimMarker("القفل معلّق مؤقتًا")
   return
  end
  local row=Brain.war.rows[Brain.war.target]
  local character=row and row.player.Character
  local humanoid=character and character:FindFirstChildOfClass("Humanoid")
  local target=character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
  local camera=workspace.CurrentCamera
  if not target or not target:IsA("BasePart") or not target:IsDescendantOf(workspace) or (humanoid and humanoid.Health<=0) then
   clearAimMarker("بانتظار ظهور الهدف")
   return
  end
  if not camera or camera.CameraType==Enum.CameraType.Scriptable or (camera.CFrame.Position-target.Position).Magnitude<.1 then
   clearAimMarker("الكاميرا غير متاحة")
   return
  end
  camera.CFrame=CFrame.lookAt(camera.CFrame.Position,target.Position)
  aimMarker.Adornee=target
  aimMarker.Enabled=true
  aimStatus.Text="القفل نشط • @"..row.player.Name
 end
 function Brain.warReleaseAim()
  if not aimEnabled then return end
  aimEnabled=false
  Run:UnbindFromRenderStep(aimBinding)
  clearAimMarker("القفل متوقف")
  aimButton.Text="تشغيل القفل"
  Brain.selectButton(aimButton,false)
 end
 aimButton=button(aimCard,"تشغيل القفل",8,52,196,function()
  if aimEnabled then
   Brain.warReleaseAim()
   return
  end
  if not Brain.war.target then
   aimStatus.Text="اختر اللاعب من خانة التتبع"
   return
  end
  aimEnabled=true
  aimButton.Text="فك قفل التصويب"
  Brain.selectButton(aimButton,true)
  Run:BindToRenderStep(aimBinding,Enum.RenderPriority.Camera.Value+2,updateAim)
 end)
 aimButton.Size=UDim2.fromOffset(196,32)
 local timingCard=warCard(224,0,212,117)
 text(timingCard,"فك التشبث",6,7,200,21,16).TextColor3=Color3.fromRGB(163,231,245)
 text(timingCard,"ضغط تلقائي عند تطابق الحلقتين",6,30,200,17,11)
 local timingStatus=text(timingCard,"المساعدة متوقفة",6,92,200,18,11)
 local timingButton
 timingButton=button(timingCard,"تشغيل مساعد الفك",8,52,196,function()
  local timing=Brain.timing
  timing.enabled=not timing.enabled
  timing.active=false
  timing.circles={}
  timing.samples=setmetatable({},{__mode="k"})
  timing.fired=setmetatable({},{__mode="k"})
  timing.nextScan=0
  timing.lastPress=nil
  timing.status="أبحث عن الحلقتين"
  timingButton.Text=timing.enabled and "إيقاف مساعد الفك" or "تشغيل مساعد الفك"
  timingStatus.Text=timing.enabled and timing.status or "المساعدة متوقفة"
  Brain.selectButton(timingButton,timing.enabled)
 end)
 timingButton.Size=UDim2.fromOffset(196,32)
 do
  local rangeCard=warCard(448,0,212,117)
  text(rangeCard,"معاينة المدى · تجريبي",6,5,200,21,15).TextColor3=Color3.fromRGB(163,231,245)
  text(rangeCard,"صندوق بصري أمام الشخصية",6,27,200,16,11)
  local amountLabel=text(rangeCard,"+0.5 ستد",57,47,98,28,15)
  amountLabel.TextColor3=Color3.fromRGB(163,231,245)
  local bonusTenths=5
  local showing=false
  local preview=new("BoxHandleAdornment",{
   Name="BLY_RangePreview",Color3=Color3.fromRGB(100,227,253),
   Transparency=.72,AlwaysOnTop=true,ZIndex=1,Visible=false,
  },gui)
  function Brain.refreshRangePreview()
   if not showing then return end
   local _,root=rig()
   if not unlocked or not root then
    preview.Visible=false
    preview.Adornee=nil
    return
   end
   local depth=3+bonusTenths/10
   preview.Size=Vector3.new(root.Size.X+1,root.Size.Y,depth)
   preview.CFrame=CFrame.new(0,0,-(root.Size.Z+depth)/2)
   preview.Adornee=root
   preview.Visible=true
  end
  local function adjustBonus(delta)
   bonusTenths=math.clamp(bonusTenths+delta,0,10)
   amountLabel.Text=string.format("+%.1f ستد",bonusTenths/10)
   Brain.refreshRangePreview()
  end
  local minus=button(rangeCard,"−",8,46,43,function() adjustBonus(-1) end)
  local plus=button(rangeCard,"+",161,46,43,function() adjustBonus(1) end)
  minus.Size=UDim2.fromOffset(43,28)
  plus.Size=UDim2.fromOffset(43,28)
  local toggle
  toggle=button(rangeCard,"إظهار الصندوق",8,81,196,function()
   showing=not showing
   toggle.Text=showing and "إخفاء الصندوق" or "إظهار الصندوق"
   Brain.selectButton(toggle,showing)
   if showing then
    Brain.refreshRangePreview()
   else
    preview.Visible=false
    preview.Adornee=nil
   end
  end)
  toggle.Size=UDim2.fromOffset(196,28)
 end
 local warOverlay
 warOverlay=button(pages.war,"عرض اللاعبين: إيقاف",0,129,197,function()
  Brain.war.enabled=not Brain.war.enabled
  warOverlay.Text="عرض اللاعبين: "..(Brain.war.enabled and "تشغيل" or "إيقاف")
  Brain.selectButton(warOverlay,Brain.war.enabled)
  if not Brain.war.enabled then
   for _,row in Brain.war.rows do Brain.warClearVisual(row) end
  else
   pcall(Brain.warTick)
  end
 end)
 warOverlay.Size=UDim2.fromOffset(197,34)
 local targetInput=new("TextBox",{
  Position=UDim2.fromOffset(209,129),Size=UDim2.fromOffset(288,34),
  BackgroundColor3=Color3.fromRGB(13,27,36),BackgroundTransparency=.22,Text="",
  PlaceholderText="Roblox username",TextColor3=white,PlaceholderColor3=Color3.fromRGB(149,181,194),
  TextSize=14,ClearTextOnFocus=false,Font=Enum.Font.Gotham,
 },pages.war)
 round(targetInput,10)
 new("UIStroke",{Color=white,Transparency=.77,Thickness=1},targetInput)
 local warTargetText=text(pages.war,"اكتب اسم اللاعب واضغط اختيار الهدف",4,169,652,24,14)
 local trackButton=button(pages.war,"اختيار الهدف",509,129,151,function()
  local chosen,message=Brain.warSelect(targetInput.Text)
  warTargetText.Text=chosen and ("@"..chosen.Name) or message
 end)
 trackButton.Size=UDim2.fromOffset(151,34)
 Brain.warCards={}
 for i,spec in {{"deaths","الموت"},{"respawns","إعادة الظهور"},{"leaves","خروج"},{"returns","رجوع"}} do
  local card=warCard((i-1)*167,205,159,62)
  text(card,spec[2],4,5,151,18,12)
  local counter=text(card,"—",4,24,151,29,23)
  counter.TextColor3=Color3.fromRGB(163,231,245)
  Brain.warCards[spec[1]]=counter
 end
 local stopTrack=button(pages.war,"إيقاف التتبع",0,279,150,function()
  Brain.warReleaseAim()
  Brain.war.target=nil
  Brain.war.targetName=nil
  Brain.war.targetLeft=nil
  warTargetText.Text="التتبع متوقف"
  for _,label in Brain.warCards do label.Text="—" end
 end)
 stopTrack.Size=UDim2.fromOffset(150,33)
 text(pages.war,"العد يبدأ عند اختيار الهدف • السيرفر الحالي",161,280,499,32,11)
 task.spawn(function()
  while alive do
   if Brain.timing.enabled then
    local timing=Brain.timing
    local display=timing.lastPress and os.clock()-timing.lastPress<1 and "أُرسلت محاولة الفك" or (timing.status or "أبحث عن الدائرة")
    timingStatus.Text=display
   end
   Brain.refreshRangePreview()
   if Brain.war.enabled or Brain.war.target then
    local ok,err=pcall(Brain.warTick)
    if not ok then Brain.war.lastError=tostring(err) end
    local war=Brain.war local id=war.target
    if id then
     local row=war.rows[id] local root=row and row.character and row.character:FindFirstChild("HumanoidRootPart")
     local location=root and string.format("X %.0f • Z %.0f",root.Position.X,root.Position.Z) or (row and "الموقع غير محمل من السيرفر" or "خارج السيرفر")
     warTargetText.Text="@"..war.targetName.." • "..location
     for key,label in Brain.warCards do label.Text=tostring(war.counts[key]) end
    end
   end
   task.wait(.1)
  end
 end)
end
Brain.createWarUI()
Brain.createSilverLion()
local statusCard=new("Frame",{Position=UDim2.fromOffset(20,377),Size=UDim2.fromOffset(660,40),BackgroundColor3=Color3.fromRGB(2,26,30),BackgroundTransparency=.18,BorderSizePixel=0},content)
round(statusCard,17)
new("UIStroke",{Color=Color3.fromRGB(83,208,228),Transparency=.51,Thickness=1},statusCard)
status=text(statusCard,currentState,12,0,636,34,13) status.TextColor3=Color3.fromRGB(225,231,235)
for name,page in pages do
 page.BackgroundColor3=Color3.new(1,1,1) page.BackgroundTransparency=name=="looks" and 1 or .02 page.BorderSizePixel=0
 round(page,23)
 if name~="looks" then
  new("UIStroke",{Color=Color3.fromRGB(112,231,241),Transparency=.14,Thickness=1.45},page)
  new("UIGradient",{Rotation=90,Color=ColorSequence.new({
   ColorSequenceKeypoint.new(0,Color3.fromRGB(6,37,44)),
   ColorSequenceKeypoint.new(.47,Color3.fromRGB(3,18,22)),
   ColorSequenceKeypoint.new(1,Color3.fromRGB(4,32,38)),
  })},page)
 end
 local body=new("Frame",{Name="BLY_PageBody",Position=UDim2.fromOffset(16,8),Size=UDim2.fromOffset(660,315),BackgroundTransparency=1},page)
 for _,child in page:GetChildren() do if child~=body and child:IsA("GuiObject") then child.Parent=body end end
 new("UIScale",{Scale=.95},body)
end
Brain.uiDecorTweens={}
for i,point in {{8,108},{690,174},{10,286},{687,363},{345,99},{686,41},{16,452},{342,494}} do
 local dot=new("Frame",{Position=UDim2.fromOffset(point[1],point[2]),Size=UDim2.fromOffset(i%3==0 and 3 or 2,i%3==0 and 3 or 2),BackgroundColor3=white,BackgroundTransparency=.45,BorderSizePixel=0,Active=false},window)
 round(dot,4)
 if i%3==0 then
  for _,g in {{-3,1,9,1},{1,-3,1,9}} do
   local ray=new("Frame",{Position=UDim2.fromOffset(g[1],g[2]),Size=UDim2.fromOffset(g[3],g[4]),BackgroundColor3=Color3.fromRGB(220,234,243),BackgroundTransparency=.58,BorderSizePixel=0,Active=false},dot)
   new("UIGradient",{Rotation=g[3]==1 and 90 or 0,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.15),NumberSequenceKeypoint.new(1,1)})},ray)
  end
 end
 local pulse=TweenService:Create(dot,TweenInfo.new(2.8+i*.3,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{BackgroundTransparency=.85})
 table.insert(Brain.uiDecorTweens,pulse) pulse:Play()
end
function Brain.fetchPicture(name)
 local url="https://bly-victory-script.mistybraid.chatgpt.site/assets/"..name
 local bytes
 local fn=Brain.requestFunction()
 local function valid(value)
  return typeof(value)=="string" and #value<=10*1024*1024 and value:sub(1,8)=="\137PNG\r\n\26\n"
 end
 if typeof(fn)=="function" then
  local ok,result=pcall(fn,{Url=url,Method="GET"})
  if ok and typeof(result)=="table" and tonumber(result.StatusCode or result.Status)==200 then bytes=result.Body end
 end
 if not valid(bytes) then
  local ok,result=pcall(function() return game:HttpGet(url) end)
  if ok then bytes=result end
 end
 if valid(bytes) then return bytes end
end
local function decode64(value)
	local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local lookup={} for i=1,#alphabet do lookup[string.byte(alphabet,i)]=i-1 end
	local out={}
	for i=1,#value,4 do
		local a,b,c,d=string.byte(value,i,i+3)
		local number=lookup[a]*262144+lookup[b]*4096+(lookup[c] or 0)*64+(lookup[d] or 0)
		local chunk=string.char(math.floor(number/65536)%256)
		if c~=61 then chunk..=string.char(math.floor(number/256)%256) end
		if d~=61 then chunk..=string.char(number%256) end
		table.insert(out,chunk)
		if i%16384==1 then task.wait() if not alive then return end end
	end
	return table.concat(out)
end
task.spawn(function()
 local assetFunction=getcustomasset or getsynasset
 if typeof(writefile)=="function" and typeof(assetFunction)=="function" then
  pcall(function()
   local bytes=Brain.fetchPicture("clouds.png")
   if not bytes or not alive then return end
   writefile("BLY_Button_Clouds_v1.png",bytes)
   Brain.buttonTexture=assetFunction("BLY_Button_Clouds_v1.png")
   for b,skin in Brain.buttonSkins do if b.Parent then skin.image.Image=Brain.buttonTexture end end
  end)
 end
 BUTTON_PNG_BASE64=""
end)
Brain.referenceCrops={}
function Brain.referenceCrop(parent,name,x,y,w,h,position,size,alpha)
 local clip=parent:FindFirstChild(name)
 if not clip then
  clip=new("Frame",{Name=name,Position=position,Size=size,BackgroundTransparency=1,ClipsDescendants=true,BorderSizePixel=0,Active=false,ZIndex=0},parent)
  local picture=new("ImageLabel",{Name="Artwork",Position=UDim2.fromScale(-x/w,-y/h),Size=UDim2.fromScale(1218/w,678/h),BackgroundTransparency=1,BorderSizePixel=0,Active=false,ZIndex=0,ScaleType=Enum.ScaleType.Stretch,ImageTransparency=alpha or 0},clip)
  table.insert(Brain.referenceCrops,picture)
 end
 clip.Artwork.Image=Brain.referenceAsset or ""
 return clip
end
do
 local function scene(parent,name,asset,rect,x,y,w,h,alpha,fade)
  local image=new("ImageLabel",{
   Name=name,Image=asset,ImageRectOffset=Vector2.new(rect[1],rect[2]),ImageRectSize=Vector2.new(rect[3],rect[4]),
   Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
   ImageTransparency=alpha,ScaleType=Enum.ScaleType.Stretch,ZIndex=0,Active=false,
  },parent)
  round(image,18)
  if fade then
   new("UIGradient",{Rotation=fade,Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.58,.16),NumberSequenceKeypoint.new(1,1),
   })},image)
  end
 end
 local function loadArtwork(name)
  local custom=getcustomasset or getsynasset
  if typeof(custom)~="function" or typeof(writefile)~="function" then return end
  local data=Brain.fetchPicture(name)
  if not data or not alive then return end
  local ok,asset=pcall(function()
   writefile(name,data)
   return custom(name)
  end)
  if ok and typeof(asset)=="string" and asset~="" then return asset end
 end
 task.spawn(function()
  local landscape=loadArtwork("bly-cyan-landscape-al.png")
  if not landscape or not alive or not window.Parent then return end
  scene(window,"BLY_HeaderLion",landscape,{319,15,139,72},264,7,147,63,.05,nil)
  scene(statusCard,"BLY_CloudLeft",landscape,{48,462,186,29},4,5,224,32,.08,0)
  scene(statusCard,"BLY_CloudRight",landscape,{570,461,193,30},433,5,223,32,.08,180)
  for _,name in {"settings","diagnostics","quests","growth","war"} do
   local page=pages[name]
   local banner=name=="settings"
   local low=name=="war"
   local y=low and 231 or 5
   local height=banner and 72 or low and 82 or 180
   local alpha=low and .53 or name=="diagnostics" and .09 or .24
   scene(page,"BLY_Savanna",landscape,{56,154,191,173},5,y,banner and 193 or 226,height,alpha,0)
   scene(page,"BLY_MoonlitHills",landscape,{559,150,202,177},banner and 464 or 432,y,banner and 191 or 223,height,alpha,180)
  end
 end)
 task.spawn(function()
  local waves=loadArtwork("bly-cyan-waves-al.png")
  local panels=Brain.looksArtPanels
  if not waves or not panels or not alive or not window.Parent then return end
  scene(panels[1],"BLY_RosterWaves",waves,{136,310,152,80},4,161,224,116,.37,270)
  scene(panels[2],"BLY_AppearanceWaves",waves,{323,231,309,95},4,62,404,141,.10,90)
 end)
end
function Brain.applyReference()
 if not Brain.referenceAsset then return end
 for _,target in {headerPortrait} do
  if target then
   local clip=Brain.referenceCrop(target,"BLY_ReferenceIcon",302,120,60,59,UDim2.fromScale(0,0),UDim2.fromScale(1,1),0)
   clip.ZIndex=target.ZIndex clip.Artwork.ZIndex=target.ZIndex
   for _,child in target:GetChildren() do if child:IsA("Frame") and child.Name=="Frame" then child.Visible=false end end
  end
 end
end
function Brain.applyIconAsset(asset)
 if Brain.chat and Brain.chat.portrait then Brain.chat.portrait.Image=asset end
 for _,target in {headerPortrait} do
  if target then
   local old=target:FindFirstChild("BLY_LionPortrait") if old then old:Destroy() end
   target.Image=asset target.ImageRectOffset=Vector2.zero target.ImageRectSize=Vector2.zero target.ScaleType=Enum.ScaleType.Fit
  end
 end
 if Brain.referenceAsset then Brain.applyReference() end
end
function Brain.setSurvivalArtwork(asset)
 local page=pages.survival
 if not page or not page.Parent then return end
 local scene=page:FindFirstChild("BLY_SurvivalArtwork")
 if not scene then
  scene=new("ImageLabel",{
   Name="BLY_SurvivalArtwork",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
   Size=UDim2.fromScale(.76,1),BackgroundTransparency=1,ImageTransparency=.23,
   BorderSizePixel=0,Active=false,ZIndex=0,ScaleType=Enum.ScaleType.Fit,
  },page)
  round(scene,23)
  new("UIGradient",{Transparency=NumberSequence.new({
   NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.14,.50),
   NumberSequenceKeypoint.new(.36,.03),NumberSequenceKeypoint.new(.64,.03),
   NumberSequenceKeypoint.new(.86,.50),NumberSequenceKeypoint.new(1,1),
  })},scene)
 end
 scene.Image=asset
end
task.spawn(function()
 local assetFunction=getcustomasset or getsynasset
 if CFG.LionAsset~="" then Brain.artAsset=CFG.LionAsset
 elseif typeof(writefile)=="function" and typeof(assetFunction)=="function" then
  local ok=pcall(function()
   local bytes=Brain.fetchPicture("bly-violet.png?v=ZD-obsidian")
   if not bytes or not alive then return end
   writefile("BLY_Obsidian_Artwork_ZD.png",bytes)
   Brain.artAsset=assetFunction("BLY_Obsidian_Artwork_ZD.png")
  end)
  if not ok then imageState="تعذر تحميل الصورة المحلية" end
 end
 if Brain.artAsset and alive then
  background.Image=Brain.artAsset
  Brain.setSurvivalArtwork(Brain.artAsset)
  imageState="هوية BLY السوداء جاهزة"
 else imageState="الصورة تحتاج دعم الصور المحلية من المشغّل" end
 LION_PNG_BASE64=""
end)
task.spawn(function()
 local fn=getcustomasset or getsynasset
 if typeof(writefile)=="function" and typeof(fn)=="function" then
  pcall(function()
   local bytes=Brain.fetchPicture("bly-square-icon.png?v=ZD-obsidian")
   if not bytes or not alive then return end
   writefile("BLY_Icon_ZD.png",bytes) Brain.iconAsset=fn("BLY_Icon_ZD.png")
  end)
 end
  if alive and Brain.iconAsset then Brain.applyIconAsset(Brain.iconAsset) end
end)
task.spawn(function()
 local fn=getcustomasset or getsynasset
 if typeof(writefile)~="function" or typeof(fn)~="function" then return end
 pcall(function()
  local bytes=Brain.fetchPicture("bly-ui-reference.png?v=ZE")
  if not bytes or not alive then return end
  writefile("BLY_UI_Reference_ZE.png",bytes) Brain.referenceAsset=fn("BLY_UI_Reference_ZE.png")
 end)
 if not Brain.referenceAsset then return end
 if alive then Brain.applyReference() end
end)
on(Run.Heartbeat,function()
	if Brain.resourcePromptStopsWalk()then releaseW("prompt_guard") end
end)
local dragging,origin,windowOrigin
local function clampWindow(center)
	local camera=workspace.CurrentCamera
	if not camera then return end
	local viewport=camera.ViewportSize
	local half=Vector2.new(window.Size.X.Offset,window.Size.Y.Offset)*scale.Scale/2
	local minX,maxX=half.X+12,math.max(half.X+12,viewport.X-half.X-12)
	local minY,maxY=half.Y+64,math.max(half.Y+64,viewport.Y-half.Y-48)
	window.Position=UDim2.fromOffset(math.clamp(center.X,minX,maxX),math.clamp(center.Y,minY,maxY))
end
local function centerWindow()
	local camera=workspace.CurrentCamera
	if camera then clampWindow(Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y/2+8)) end
end
local dragHandle=new("TextButton",{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-4),Size=UDim2.fromOffset(104,24),BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=12},window)
local dragPill=new("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(64,3),BackgroundColor3=white,BackgroundTransparency=.08,BorderSizePixel=0,ZIndex=13},dragHandle)
round(dragPill,2)
round(dragHandle,9)
local recover=button(gui,"",0,0,32,centerWindow)
recover.AnchorPoint=Vector2.new(1,1) recover.Position=UDim2.new(1,-12,1,-10)
recover.Size=UDim2.fromOffset(32,30) recover.ZIndex=30 recover.Visible=false
local centerGlyph=new("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(13,13),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=31},recover)
round(centerGlyph,4)
new("UIStroke",{Color=white,Thickness=1,Transparency=.25},centerGlyph)
new("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(3,3),BackgroundColor3=white,BorderSizePixel=0,ZIndex=31},centerGlyph)
launcher=new("ImageButton",{
 Name="BLY_VictoryLauncher",AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,12,.5,0),
 Size=UDim2.fromOffset(52,52),BackgroundColor3=Color3.fromRGB(8,18,24),
 Image="",ScaleType=Enum.ScaleType.Fit,BorderSizePixel=0,AutoButtonColor=true,ZIndex=40,
},gui)
round(launcher,13)
new("UIGradient",{Rotation=105,Color=ColorSequence.new({
 ColorSequenceKeypoint.new(0,Color3.fromRGB(60,85,96)),
 ColorSequenceKeypoint.new(.53,Color3.fromRGB(16,33,40)),
 ColorSequenceKeypoint.new(1,Color3.fromRGB(6,11,15)),
})},launcher)
new("UIStroke",{Color=Color3.fromRGB(123,181,192),Thickness=1.1,Transparency=.22},launcher)
local launcherRim=new("Frame",{
 Position=UDim2.fromOffset(4,4),Size=UDim2.new(1,-8,1,-8),BackgroundTransparency=1,
 BorderSizePixel=0,ZIndex=41,
},launcher)
round(launcherRim,10)
new("UIStroke",{Color=white,Thickness=1,Transparency=.82},launcherRim)
local monogram=text(launcher,"BLY",0,6,52,34,19)
monogram.Font=Enum.Font.GothamBold monogram.TextColor3=Color3.fromRGB(225,246,248) monogram.ZIndex=42
local mark=new("Frame",{
 Position=UDim2.fromOffset(21,39),Size=UDim2.fromOffset(10,2),BackgroundColor3=Color3.fromRGB(100,223,232),
 BorderSizePixel=0,ZIndex=42,
},launcher)
round(mark,2)
do
 local portrait=new("ImageLabel",{
  Name="BLY_LauncherPortrait",Position=UDim2.fromOffset(2,2),Size=UDim2.new(1,-4,1,-4),
  BackgroundTransparency=1,BorderSizePixel=0,Active=false,ScaleType=Enum.ScaleType.Fit,ZIndex=41,
 },launcher)
 round(portrait,11)
 local embedded
 local function showPortrait()
  local ready=embedded~=nil or portrait.IsLoaded
  monogram.Visible=not ready
  mark.Visible=not ready
 end
 on(portrait:GetPropertyChangedSignal("IsLoaded"),showPortrait)
 task.spawn(function()
  local image
  local ok=pcall(function()
   local data=decode64("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AAAgAGIIBBmiECEAIAAgAKIQwxBhCCAAAAAAAGEIRSEkIWEIBCEEGSAAQQBBCMMQQQBBCAAAIACiEIIIAABBAAAAAAAgAIIQAAAAAEEAgghBACAAIACiEMMQBCHjGGEIIAAAAAAAIAAgAAAAIACjEOMYIABhCAAAYQjDEEUhwxBBCAAAAACCEKYxwxCiECUhQQhBCGEIoxAgACAAAAAgAIIIZinDEEEAIQAAAAAAQQggAAAAAACCCCAAIACCEOQYZikEGUEIAAAAAAAAAAAgACEAAAAAACAA5BhhCIIQYQgAACAAwxiGKeQYQQgAAAAAohAEGWII4xhBCEEIoxBhCAAAAAAAAAAAIACiEAQZwxBhCAAAAABBAAAAAAAAAEEAAACCCMMQRSHDEAAAAAAAAAAAAABBCEEIQQgAAAAAAABBCKMQQQjjGEEAAAAAAMMQRSmiEAAAAAAgAMMQggiCECEAYQiCEAAAAAAAAAAAAAAAAAAAQQiiEMMYQQAAACAAAAAAAAAAAABhCKMQghDDGAAAAAAAACAAIACiEOMYggghAAAAAAAAAAAAYQggAIIQ5BghAAAAAACiEMMQQQAAACAAohCCCEEIIABhCCAAAAAAACAAYQhBCAAAAAAAACAAgghiCAAAAAAAAAAAAAAAAGIIIACCEEEAAAAAAEEIQQijEGYpwxBBCAAAAAAgAAAAAAAgACAAAADDGKMQIAAAAEEIohAhAAAAQQiiEGEIAABBCEEIAAAAAAAAIABhCOQYwxgAAAAAAAAAAEEIAAAAAAAAAAAAAAAAIAAAAGEIAAAAACAAYgiCCEUhwxAAAAAAAAAgAEEIIAAAACAAIAAAAAAAwxBhCAAAIABiCCAAIACiEGEIIAAAAGEIIAAAACAAQQhhCCAAQQglIcMQAAAgAAAAIAAAAAAAAAAAAAAAAAAAAAAAQQAAAAAAYghiCIII4xgAAAAAAABBCKIQggggACAAIAAAACAAAABBCIIQAABBAGEIAACCCIIIAAAAACAAYgggACAAIACCEOQYgggAACAAoxAhACAAAAAgAAAAAAAAAAAAAAAAAAAAAAAgAAAAAACCCCAAYghBAAAAIABBCOMY4xhBCAAAQQgAACAAQQgAAAAAYgggAGEIIABBCIIIAAAAAAAAYQhhCCAAQQgAAGEIJSHkGEEIAAAgAEEIAAAAAAAAAAAAAAAAAAA=")
   if not alive or not launcher.Parent or not data then return end
   local size=Vector2.new(52,52)
   image=game:GetService("AssetService"):CreateEditableImage({Size=size})
   if not image then return end
   local input=buffer.fromstring(data)
   local rgba=buffer.create(52*52*4)
   for i=0,52*52-1 do
    local packed=buffer.readu16(input,i*2)
    local r=bit32.rshift(packed,11)
    local g=bit32.band(bit32.rshift(packed,5),63)
    local b=bit32.band(packed,31)
    buffer.writeu32(rgba,i*4,4278190080+math.floor(b*255/31)*65536+math.floor(g*255/63)*256+math.floor(r*255/31))
   end
   image:WritePixelsBuffer(Vector2.zero,size,rgba)
   portrait.ImageContent=Content.fromObject(image)
   embedded=image
  end)
  if image and not embedded then image:Destroy() end
  if ok and embedded then
   showPortrait()
   Brain.launcherEditable=image
   return
  end
  local custom=getcustomasset or getsynasset
  if typeof(writefile)~="function" or typeof(custom)~="function" then return end
  local bytes=Brain.fetchPicture("bly-lion-launcher-as.png")
  if not bytes or not alive or not launcher.Parent then return end
  local loaded,asset=pcall(function()
   local file="BLY_LionLauncher_AS.png"
   writefile(file,bytes)
   return custom(file)
  end)
  if loaded and typeof(asset)=="string" and asset~="" and alive and launcher.Parent then
   portrait.Image=asset
   showPortrait()
  end
 end)
end
local iconScale=new("UIScale",{Scale=1},launcher)
Brain.iconPulse=TweenService:Create(iconScale,TweenInfo.new(2.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Scale=1.045})
Brain.iconPulse:Play()
on(launcher.Activated,function()
	local wanted=not Brain.uiWanted
	if wanted then centerWindow() end
	setWindowShown(wanted)
end)
on(window:GetPropertyChangedSignal("Visible"),function() recover.Visible=window.Visible end)
local function beginDrag(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
		local camera=workspace.CurrentCamera if not camera then return end
		dragging=input origin=Vector2.new(input.Position.X,input.Position.Y)
		windowOrigin=Vector2.new(window.Position.X.Scale*camera.ViewportSize.X+window.Position.X.Offset,window.Position.Y.Scale*camera.ViewportSize.Y+window.Position.Y.Offset)
	end
end
on(header.InputBegan,beginDrag) on(dragHandle.InputBegan,beginDrag)
on(UIS.InputChanged,function(input)
	if dragging and (input==dragging or (dragging.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)) then
		clampWindow(windowOrigin+Vector2.new(input.Position.X,input.Position.Y)-origin)
	end
	if running and input.KeyCode==Enum.KeyCode.Thumbstick1 and input.Position.Magnitude>.2 then stop("تدخل يدوي؛ متوقف") end
end)
on(UIS.InputEnded,function(input) if input==dragging then dragging=nil end end)
on(UIS.InputBegan,function(input,processed)
	if running and not processed and (input.KeyCode==Enum.KeyCode.S or input.KeyCode==Enum.KeyCode.A or input.KeyCode==Enum.KeyCode.D or input.KeyCode==Enum.KeyCode.Escape) then stop("تدخل يدوي؛ متوقف") end
end)
on(UIS.WindowFocusReleased,function()
	Brain.motionTrace("focus_lost","")
	Brain.focused=false dragging=nil release()
	if running and not CFG.Background then stop("توقفت الحركة لأن متابعة الخلفية مغلقة") end
end)
on(UIS.WindowFocused,function()
	Brain.focused=true Brain.motionTrace("focus_returned","")
	if running then releaseW("focus_returned") end
end)
Brain.needConnections={}
function Brain.bindNeeds(character)
 for _,connection in Brain.needConnections do connection:Disconnect() end
 Brain.needConnections={}
 if not character then return end
 for _,name in {"Food","Water"} do
  table.insert(Brain.needConnections,character:GetAttributeChangedSignal(name):Connect(function()
   if not running or (Brain.mode~="Survival"and Brain.mode~="Growth")or player.Character~=character then return end
   local food,water=stats() local amount=name=="Food" and food or water
   if amount and amount<CFG.Threshold then
    Brain.fillNeeds[name]=true Brain.wakeAt=os.clock()
   end
  end))
 end
end
Brain.bindNeeds(player.Character)
on(player.CharacterAdded,Brain.bindNeeds)
on(player.CharacterRemoving,function() stop("أنتظر الشخصية الجديدة ثم أبحث عن موارد قريبة",true) end)
local viewportConnection
local function resize()
 if Brain.chat and Brain.chat.fit then Brain.chat.fit() end
	local camera=workspace.CurrentCamera
	if camera then
		scale.Scale=math.clamp(math.min((camera.ViewportSize.X-24)/700,(camera.ViewportSize.Y-120)/500),.25,1)
		local p=window.Position
		clampWindow(Vector2.new(p.X.Scale*camera.ViewportSize.X+p.X.Offset,p.Y.Scale*camera.ViewportSize.Y+p.Y.Offset))
	end
end
local function bindCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	if workspace.CurrentCamera then viewportConnection=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
	if running then
  local mode=Brain.mode
  stop("تغيّرت الكاميرا؛ أعيد تهيئة التحكم",true)
  local resumeToken=generation
  task.delay(2,function() if alive and unlocked and not running and generation==resumeToken and Brain.start then Brain.start(mode,true) end end)
 end
	resize()
end
on(workspace:GetPropertyChangedSignal("CurrentCamera"),bindCamera) bindCamera()
function Brain.installTaqshee()
 local clean={ownerId=nil,busy=false,pending=false,serial=0,seen={},cursor=0,startedAt=os.time()}
 Brain.taqshee=clean
 local function normalize(s) return tostring(s or ""):gsub("<[^>]*>",""):lower():gsub("%s+","") end
 function Brain.taqsheeParse(raw)
  if type(raw)~="string" then return end
  local words={} for word in raw:gmatch("%S+") do table.insert(words,word) end
  if words[1]~="/تقشيع" and words[1]~="تقشيع" then return end
  local mode,target
  if #words==2 then mode="all" target=words[2]
  elseif #words==3 and words[2]=="واحدة" then mode="one" target=words[3] end
  if not target or #target<3 or #target>20 or not target:match("^[A-Za-z0-9_]+$") then return end
  return mode,target:lower()
 end
 function Brain.taqsheeAuthorized(sender,target)
  return clean.ownerId~=nil and sender==clean.ownerId and target==player.Name:lower()
 end
 local function visible(n)
  if not n or not n.Parent then return false end
  local p=n
  while p and p~=pg do
   if p:IsA("GuiObject") and not p.Visible then return false end
   if p:IsA("LayerCollector") and not p.Enabled then return false end
   p=p.Parent
  end
  return p==pg and n:IsA("GuiObject") and n.AbsoluteSize.X>2 and n.AbsoluteSize.Y>2
 end
 local function label(n)
  if n:IsA("TextLabel") or n:IsA("TextButton") then return n.Text end
  return ""
 end
 local function matches(n,wanted)
  local name=normalize(n.Name):gsub("button$",""):gsub("^button",""):gsub("^btn",""):gsub("btn$","")
  return normalize(label(n))==wanted or name==wanted
 end
 local function has(root,wanted)
  if matches(root,wanted) then return true end
  for _,n in root:GetDescendants() do if visible(n) and matches(n,wanted) then return true end end
  return false
 end
 local function nativeNodes(root)
  local nodes={}
  for _,n in (root or pg):GetDescendants() do
   if not n:IsDescendantOf(gui) and visible(n) then table.insert(nodes,n) end
  end
  return nodes
 end
 local function button(root,wanted)
  local found={}
  for _,n in nativeNodes(root) do
   if n:IsA("GuiButton") and n.Active and has(n,wanted) then
    local waiting=normalize(label(n)):match("^wait")~=nil
    if wanted=="delete" then
     for _,c in n:GetDescendants() do if visible(c) and normalize(label(c)):match("^wait") then waiting=true end end
    end
    if not waiting then table.insert(found,n) end
   end
  end
  local leaves={}
  for _,n in found do
   local wraps=false
   for _,other in found do if other~=n and other:IsDescendantOf(n) then wraps=true break end end
   if not wraps then table.insert(leaves,n) end
  end
  if #leaves==1 then return leaves[1] end
 end
 local function click(n)
  if not unlocked or not Brain.focused or not vim or not visible(n) or not n:IsA("GuiButton") or not n.Active then return false end
  local p=n.AbsolutePosition+n.AbsoluteSize/2
  local hits=pg:GetGuiObjectsAtPosition(p.X,p.Y)
  for _,hit in hits do
   if hit==n or hit:IsDescendantOf(n) then
    vim:SendMouseButtonEvent(p.X,p.Y,0,true,game,0)
    vim:SendMouseButtonEvent(p.X,p.Y,0,false,game,0)
    return true
   end
   if not n:IsDescendantOf(hit) then return false end
  end
  return false
 end
 local function live(id) return alive and unlocked and clean.busy and clean.serial==id and Brain.focused end
 local function pause(id,seconds)
  local untilTime=os.clock()+seconds
  repeat if not live(id) then error("أُلغي التنظيف أو خرجت من نافذة اللعبة",0) end task.wait(.1) until os.clock()>=untilTime
 end
 local function waitFor(id,seconds,fn,step)
  if step then clean.step=step clean.status="التقشيع: "..step state(clean.status) end
  local untilTime=os.clock()+seconds
  repeat
   if not live(id) then error("توقف التنظيف",0) end
   local result=fn() if result then return result end
   task.wait(.15)
  until os.clock()>=untilTime
  error("توقف التقشيع عند "..(clean.step or "واجهة الحذف").."؛ لم أتأكد من الزر المطلوب",0)
 end
 local function report(message) clean.status=message state(message) end
 local function charactersPanel()
  local found
  for _,n in nativeNodes() do
   if matches(n,"characters") then
    local p=n.Parent
    for _=1,5 do
     if not p or p==pg or p:IsA("LayerCollector") then break end
     if has(p,"newcharacter") or has(p,"characterlimit(40)") then
      if found and found~=p then return end
      found=p break
     end
     p=p.Parent
    end
   end
  end
  return found
 end
 local function slots(panel)
  local rows={}
  for _,n in nativeNodes(panel) do
   if n:IsA("GuiButton") and n:IsDescendantOf(panel) then
    local growth,species=false,false
    for _,child in n:GetDescendants() do
     local s=normalize(label(child))
     if s:match("^%d+%%growth$") or s:match("^growth:?%d+%%$") then growth=true end
     if s:match("^male[a-z]") or s:match("^female[a-z]") then species=true end
    end
    if growth and species then table.insert(rows,n) end
   end
  end
  for _,a in rows do for _,b in rows do if a~=b and a:IsDescendantOf(b) then error("قائمة الشخصيات غير واضحة؛ لم أحذف شيئًا",0) end end end
  table.sort(rows,function(a,b) return a.AbsolutePosition.Y<b.AbsolutePosition.Y end)
  return rows
 end
 local function signature(row)
  local labels={}
  for _,n in row:GetDescendants() do local s=normalize(label(n)) if s~="" then table.insert(labels,s) end end
  table.sort(labels) return table.concat(labels,"|")
 end
 local function dialog()
  local found
  for _,n in nativeNodes() do
   if normalize(label(n))=="deletecharacter" then
    local p=n.Parent
    for _=1,4 do
     if not p or p==pg or p:IsA("LayerCollector") then break end
     if button(p,"cancel") then if found and found~=p then return end found=p break end
     p=p.Parent
    end
   end
  end
  return found
 end
 local function cancelNative()
  local d=dialog() local cancel=d and button(d,"cancel") if cancel then pcall(click,cancel) end
 end
 local function removeSelected(id,panel,expected)
  if dialog() then error("يوجد طلب حذف مفتوح من قبل؛ أغلقه أولًا",0) end
  local del=button(panel,"delete")
  if not del or not click(del) then error("ما قدرت أتأكد من زر حذف الشخصية",0) end
  local d=waitFor(id,5,dialog)
  if expected then
   for _,value in expected do if not has(d,value) then cancelNative() error("الشخصية في تأكيد الحذف تختلف عن المختارة؛ ألغيت العملية",0) end end
  end
  pause(id,3)
  local confirm=waitFor(id,8,function() return dialog()==d and button(d,"delete") end)
  if not click(confirm) then cancelNative() error("توقف الحذف قبل التأكيد",0) end
  waitFor(id,8,function() return not dialog() end)
 end
 local function run(mode)
  clean.pending=false clean.busy=true clean.serial+=1 local id=clean.serial
  if Brain.growth then Brain.growth.active=false Brain.growth.sequence+=1 end
  if Brain.chat then Brain.chat.resume=nil Brain.chat.growthResume=nil end
  if Brain.timing then Brain.timing.enabled=false end
  if Brain.warReleaseAim then pcall(Brain.warReleaseAim) end
  if Brain.war then Brain.war.enabled=false end
  stop("وصل أمر التقشيع؛ أوقفت البقاء والمهام والتكبير")
  task.spawn(function()
   local lease
   local ok,err=pcall(function()
    if Brain.suspendQuestPanel then lease=Brain.suspendQuestPanel() end
    if UIS:GetFocusedTextBox() then UIS:GetFocusedTextBox():ReleaseFocus() end
    if not charactersPanel() then
     if not Brain.pulse(Enum.KeyCode.K) then error("إرسال K غير متاح",0) end
     report("التقشيع: انتظار 10 ثواني بعد K") pause(id,10)
     local nextStep=waitFor(id,35,function()
      local panel=charactersPanel() if panel then return {panel=panel} end
      local play=button(pg,"play") if play then return {play=play} end
     end,"فتح القائمة الرئيسية وزر PLAY")
     if nextStep.play then
      local clicked=waitFor(id,5,function() return click(nextStep.play) end,"الضغط على PLAY")
      if not clicked then error("ما تأكد ضغط PLAY",0) end
     end
    end
    local panel=waitFor(id,25,charactersPanel,"ظهور قائمة الشخصيات بعد PLAY")
    if mode=="one" then
     removeSelected(id,panel,nil)
     report("انتهى التقشيع: حُذفت الشخصية المحددة فقط")
    else
     local removed=0
     for _=1,100 do
      panel=waitFor(id,5,charactersPanel)
      local rows=slots(panel)
      if #rows==0 then
       if has(panel,"newcharacter") and not button(panel,"delete") then report("انتهى التقشيع: حُذفت "..removed.." شخصية") return end
       error("ما تأكدت من عدد الشخصيات المتبقية؛ توقفت بعد "..removed,0)
      end
      local selected=rows[1] local beforeCount=#rows local before=signature(selected)
      local scroll=selected.Parent
      while scroll and scroll~=panel do
       if scroll:IsA("ScrollingFrame") then scroll.CanvasPosition=Vector2.new(0,0) pause(id,.2) break end
       scroll=scroll.Parent
      end
      local expected={}
      for _,n in selected:GetDescendants() do
       local s=normalize(label(n))
       if s~="" and (s:match("^male[a-z]") or s:match("^female[a-z]")) then table.insert(expected,s) end
      end
      if #expected~=1 then error("نوع الشخصية غير واضح؛ توقفت",0) end
      if not click(selected) then error("تعذر اختيار الشخصية؛ توقفت",0) end
      pause(id,.4)
      removeSelected(id,panel,expected)
      removed+=1 report("التقشيع: حُذفت "..removed.." شخصية")
      pause(id,.5)
      local after=slots(panel)
      if #after>=beforeCount and (#after==0 or signature(after[1])==before) then error("لم أتأكد من تحديث القائمة بعد الحذف؛ أوقفت التكرار",0) end
     end
     error("وصل التنظيف للحد الأقصى؛ توقف",0)
    end
   end)
   if lease and Brain.restoreQuestPanel then Brain.restoreQuestPanel(lease) end
   if clean.serial==id then
    clean.busy=false clean.pending=false
    if not ok then cancelNative() report(tostring(err)) end
   end
  end)
 end
 function Brain.taqsheeReceive(sender,raw,key)
  local mode,target=Brain.taqsheeParse(raw)
  if not mode or not Brain.taqsheeAuthorized(sender,target) or not alive or not unlocked then return end
  if clean.busy or clean.pending then return end
  local now=os.clock() if clean.last and now-clean.last<10 then return end
  if key and clean.seen[key] then return end
  if key then clean.seen[key]=true end clean.last=now
  run(mode)
 end
 function Brain.taqsheeSubmit(raw)
  local mode,target=Brain.taqsheeParse(raw)
  if not mode then return false end
  if not clean.ownerId then report("التقشيع: أنتظر التحقق من حساب الإدارة؛ أعد الأمر بعد ثواني") return true end
  if player.UserId~=clean.ownerId then report("أمر التقشيع مخصص لحساب cofc2pp فقط") return true end
  if not Brain.chatAccess("server") then report("التقشيع: التفعيل أو اتصال BLY غير جاهز") return true end
  local person
  for _,p in Players:GetPlayers() do if p.Name:lower()==target then person=p break end end
  if not person then report("التقشيع: الحساب @"..target.." غير موجود في نفس السيرفر") return true end
  local now=os.clock()
  if clean.sending or (clean.sentRaw==raw and clean.sentAt and now-clean.sentAt<5) then return true end
  clean.sending=true clean.sentRaw=raw clean.sentAt=now
  task.spawn(function()
   local text="/تقشيع "..(mode=="one" and "واحدة " or "")..person.Name
   local ok,result,err=pcall(Brain.chatHTTP,"/api/chat/send",{text=text,room=Brain.chatRoom("server"),clientId=game:GetService("HttpService"):GenerateGUID(false)})
   clean.sending=false
   if not alive then return end
   if ok and result and result.ok then report("أُرسل أمر التقشيع إلى @"..person.Name.."؛ ينتظر وصوله لسكربته المحدّث")
   else clean.sentAt=nil report("تعذر إرسال التقشيع: "..tostring(ok and err or result)) end
  end)
  return true
 end
 function Brain.taqsheePoll()
  if clean.polling or not clean.ownerId or not Brain.chatAccess("server") then return end
  clean.polling=true
  local ok,result=pcall(Brain.chatHTTP,"/api/chat/read",{after=clean.cursor,room=Brain.chatRoom("server")})
  clean.polling=false
  if not alive or not ok or not result then return end
  for _,message in result.messages or {} do
   clean.cursor=math.max(clean.cursor,tonumber(message.id) or 0)
   local stamp=tonumber(message.createdAt)
   if stamp and stamp>=clean.startedAt and stamp<=os.time()+5 and os.time()-stamp<=15 and message.room==Brain.chatRoom("server") then
    if Brain.vipReceive then Brain.vipReceive(tonumber(message.userId),message.text)end
    Brain.taqsheeReceive(tonumber(message.userId),message.text,"bly:"..tostring(message.id))
   end
  end
 end
 task.spawn(function()
  while alive and not clean.ownerId do
   for _,p in Players:GetPlayers() do if p.Name:lower()=="cofc2pp" then clean.ownerId=p.UserId break end end
   if not clean.ownerId then
    local ok,id=pcall(function() return Players:GetUserIdFromNameAsync("cofc2pp") end)
    if alive and ok and type(id)=="number" and id>0 then clean.ownerId=id end
   end
   if not clean.ownerId then task.wait(10) end
  end
 end)
 local function bind(person)
  on(person.Chatted,function(raw)
   if person==player then Brain.taqsheeSubmit(raw)if Brain.vipSubmit then Brain.vipSubmit(raw)end end
   Brain.taqsheeReceive(person.UserId,raw,nil)
  end)
 end
 for _,person in Players:GetPlayers() do bind(person) end
 on(Players.PlayerAdded,bind)
 pcall(function()
  local service=game:GetService("TextChatService")
  on(service.MessageReceived,function(message)
   if message.TextSource and message.TextSource.UserId==player.UserId then Brain.taqsheeSubmit(message.Text)if Brain.vipSubmit then Brain.vipSubmit(message.Text)end end
   if message.TextSource then Brain.taqsheeReceive(message.TextSource.UserId,message.Text,message.MessageId) end
  end)
  local previous=service:FindFirstChild("BLY_TaqsheeCommand") if previous then previous:Destroy() end
  local command=Instance.new("TextChatCommand")
  command.Name="BLY_TaqsheeCommand" command.PrimaryAlias="/تقشيع" command.Parent=service
  clean.command=command
  on(command.Triggered,function(source,raw)
   if source and source.UserId==player.UserId then Brain.taqsheeSubmit(raw) end
  end)
  on(gui.Destroying,function() command:Destroy() end)
 end)
 task.spawn(function() while alive do pcall(Brain.taqsheePoll) task.wait(2) end end)
end
Brain.installTaqshee()
function Brain.installVipStamina()
 local vip={granted=false,enabled=false,layout=false,sending=false}
 Brain.vipStamina=vip
 local function ownerId()return Brain.taqshee and Brain.taqshee.ownerId end
 function Brain.vipOwner()return ownerId()~=nil and player.UserId==ownerId()end
 function Brain.vipStaminaAllowed()
  return alive and unlocked and (not Brain.licenseExpires or os.clock()<Brain.licenseExpires)and (Brain.vipOwner()or vip.granted)
 end
 function Brain.vipParse(raw)
  if type(raw)~="string"then return end
  local words={}for w in raw:gmatch("%S+")do table.insert(words,w:lower())end
  if words[1]~="/vip"and words[1]~="vip"then return end
  local action,target="on",nil
  if #words==2 then target=words[2]
  elseif #words==3 and (words[2]=="stamina"or words[2]=="on"or words[2]=="off")then
   action=words[2]=="off"and "off"or "on"target=words[3]
  end
  if not target or #target<3 or #target>20 or not target:match("^[a-z0-9_]+$")then return end
  return action,target
 end
 function Brain.vipReceive(sender,raw)
  local action,target=Brain.vipParse(raw)
  if not action or not alive or not unlocked or not ownerId()or sender~=ownerId()or target~=player.Name:lower()then return end
  local enabled=action=="on"
  if vip.granted==enabled and vip.enabled==enabled then return end
  vip.granted=enabled vip.enabled=enabled
  state(enabled and "وصلتك طاقة VIP لهذه الجلسة · التعديل محلي"or "سُحبت طاقة VIP وتوقف تعديل الطاقة")
 end
 function Brain.vipSubmit(raw)
  local action,target=Brain.vipParse(raw)if not action then return false end
  if not Brain.vipOwner()then state("أوامر VIP لحساب cofc2pp فقط")return true end
  if not Brain.chatAccess("server")then state("اتصال شات BLY غير جاهز لإرسال VIP")return true end
  local person
  for _,p in Players:GetPlayers()do if p.Name:lower()==target then person=p break end end
  if not person then state("حساب VIP غير موجود في نفس السيرفر")return true end
  if vip.sending or (vip.sentRaw==raw and os.clock()-(vip.sentAt or 0)<3)then return true end
  vip.sending=true vip.sentRaw=raw vip.sentAt=os.clock()
  task.spawn(function()
   local text="/vip "..(action=="off"and "off"or "stamina").." "..person.Name
   local ok,result=pcall(Brain.chatHTTP,"/api/chat/send",{text=text,room=Brain.chatRoom("server"),clientId=game:GetService("HttpService"):GenerateGUID(false)})
   vip.sending=false
   if not alive then return end
   if ok and result and result.ok then
    Brain.vipReceive(player.UserId,text)
    state("أُرسل أمر VIP إلى @"..person.Name.." · يحتاج السكربت المحدّث")
   else state("تعذر إرسال أمر VIP؛ أعد المحاولة")end
  end)
  return true
 end
 local function number(n)return type(n)=="number"and n==n and n>-math.huge and n<math.huge end
 local function eligible(name)
  local s=name:lower()
  for _,word in {"max","regen","drain","rate","cost","threshold","recovery"}do if s:find(word,1,true)then return false end end
  for _,word in {"stamina","energy","sprint","endurance","vigor","stam"}do if s:find(word,1,true)then return true end end
  return false
 end
 function Brain.vipStaminaTick()
  if not vip.enabled or not Brain.vipStaminaAllowed()then return end
  for _,object in {player.Character,player}do
   if object then
    local function refill(key,value,setter,explicitMax)
     if not eligible(key)or not number(value)or value<0 then return end
     local cap=key:sub(1,1):upper()..key:sub(2)
     local maximum=explicitMax or object:GetAttribute("Max"..cap)or object:GetAttribute(cap.."Max")or 100
     if number(maximum)and maximum>0 and value<=maximum*.30 then pcall(setter,maximum)end
    end
    for k,v in object:GetAttributes()do refill(k,v,function(n)object:SetAttribute(k,n)end)end
    for _,child in object:GetChildren()do
     if child:IsA("NumberValue")or child:IsA("IntValue")then refill(child.Name,child.Value,function(n)child.Value=n end,child:GetAttribute("MaxValue"))end
    end
   end
  end
 end
 local vipButton
 vipButton=button(pages.settings,"طاقة VIP المحلية: إيقاف",24,166,612,function()
  if not Brain.vipOwner()then return end
  vip.enabled=not vip.enabled
  state("طاقة VIP تعدّل القيمة محليًا؛ لا تضمن اعتماد السيرفر")
 end)
 vipButton.Size=UDim2.fromOffset(612,27)vipButton.TextSize=15 vipButton.Visible=false vip.button=vipButton
 local function refresh()
  local owner=Brain.vipOwner()vipButton.Visible=owner
  vipButton.Text=vip.enabled and "طاقة VIP المحلية: تشغيل · 30٪ إلى 100٪"or "طاقة VIP المحلية: إيقاف"
  if Brain.layoutSettings then Brain.layoutSettings()end
 end
 pcall(function()
  local service=game:GetService("TextChatService")
  local previous=service:FindFirstChild("BLY_VipCommand")if previous then previous:Destroy()end
  local command=Instance.new("TextChatCommand")command.Name="BLY_VipCommand"command.PrimaryAlias="/vip"command.Parent=service
  on(command.Triggered,function(source,raw)if source and source.UserId==player.UserId then Brain.vipSubmit(raw)end end)
  on(gui.Destroying,function()command:Destroy()end)
 end)
 task.spawn(function()while alive do refresh()pcall(Brain.vipStaminaTick)task.wait(1.35)end end)
end
Brain.installVipStamina()
function Brain.installCarcassMarkers()
 local collection=game:GetService("CollectionService")
 local tags={"Carcass","Corpse","DeadAnimal","AnimalCorpse"}
 local marks={active=false,tracked={},watched={},queue={},queued={},links={},epoch=0,report={}}
 Brain.carcassMarkers=marks
 local folder=new("Folder",{Name="BLY_CarcassMarkers"},workspace)
 local function connected(signal,callback)table.insert(marks.links,signal:Connect(callback))end
 function Brain.isCarcassObject(node)
  if not node or not(node:IsA("Model")or node:IsA("BasePart"))or not node:IsDescendantOf(workspace)then return false end
  if player.Character and (node==player.Character or node:IsDescendantOf(player.Character))then return false end
  for _,key in {"MeatRemaining","FoodRemaining","RemainingMeat"}do
   local value=node:GetAttribute(key)if typeof(value)=="number"and value<=0 then return false end
  end
  local humanoid=node:IsA("Model")and node:FindFirstChildOfClass("Humanoid")
  local health=node:GetAttribute("Health")
  if humanoid and humanoid.Health>0 then return false end
  local movement=tostring(node:GetAttribute("MovementState")or ""):lower()
  if node:GetAttribute("IsDead")==true or node:GetAttribute("Dead")==true or node:GetAttribute("IsCorpse")==true or node:GetAttribute("IsCarcass")==true or movement=="dead"or movement=="deceased"then return true end
  if humanoid and humanoid.Health<=0 then return true end
  if typeof(health)=="number"and health<=0 and (node:GetAttribute("AnimalName")or node:GetAttribute("Species"))then return true end
  local name=node.Name:lower():gsub("[%s_%-]","")
  if name:find("carcass",1,true)or name:find("corpse",1,true)or name:find("deadanimal",1,true)then return true end
  for _,tag in tags do if collection:HasTag(node,tag)then return true end end
  return false
 end
 local function queue(node)
  if not marks.active then return end
  local item=node
  for _=1,5 do
   if not item or item==workspace then break end
   if (item:IsA("Model")or (item:IsA("BasePart")and Brain.isCarcassObject(item)))and not marks.queued[item]then marks.queued[item]=true table.insert(marks.queue,item)end
   item=item.Parent
  end
 end
 local function remove(node)
  local row=marks.tracked[node]if not row then return end
  row.glow:Destroy()row.label:Destroy()marks.tracked[node]=nil
 end
 local function anchor(node)
  if node:IsA("BasePart")then return node.Transparency<1 and node or nil end
  if node.PrimaryPart and node.PrimaryPart:IsDescendantOf(node)then return node.PrimaryPart end
  for _,part in node:GetDescendants()do if part:IsA("BasePart")and part.Transparency<1 then return part end end
 end
 local function reconcile(node)
  if not Brain.isCarcassObject(node)then remove(node)return end
  local ancestor=node.Parent
  for _=1,4 do
   if not ancestor or ancestor==workspace then break end
   if Brain.isCarcassObject(ancestor)then remove(node)queue(ancestor)return end
   ancestor=ancestor.Parent
  end
  local part=anchor(node)if not part then return end
  local row=marks.tracked[node]
  if row and row.part==part and row.label.Parent then return end
  remove(node)
  for other in marks.tracked do if other:IsDescendantOf(node)then remove(other)end end
  local glow=new("Highlight",{Name="BLY_FoodOutline",Adornee=node,FillColor=Color3.fromRGB(255,216,0),FillTransparency=.82,OutlineColor=Color3.fromRGB(255,230,0),OutlineTransparency=0,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop},folder)
  local label=new("BillboardGui",{Name="BLY_FoodLabel",Adornee=part,AlwaysOnTop=true,Size=UDim2.fromOffset(128,40),StudsOffsetWorldSpace=Vector3.new(0,part.Size.Y*.5+2.5,0)},folder)
  local caption=new("TextLabel",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(12,17,21),BackgroundTransparency=.12,BorderSizePixel=0,Text="أكل",TextColor3=Color3.fromRGB(255,235,91),TextStrokeColor3=Color3.new(0,0,0),TextStrokeTransparency=.35,TextSize=24,Font=Enum.Font.ArialBold},label)
  new("UICorner",{CornerRadius=UDim.new(0,8)},caption)
  new("UIStroke",{Color=Color3.fromRGB(255,214,38),Thickness=1.2,Transparency=.22,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},caption)
  marks.tracked[node]={part=part,label=label,glow=glow}
 end
 local function watch(node)
  if not node:IsA("Model")then return end
  local humanoid=node:FindFirstChildOfClass("Humanoid")
  if not humanoid and not node:GetAttribute("AnimalName")and not node:GetAttribute("Species")and not Brain.isCarcassObject(node)then return end
  if not marks.watched[node]then
  marks.watched[node]={}
  connected(node.AttributeChanged,function(key)
   if key=="IsDead"or key=="Dead"or key=="IsCorpse"or key=="IsCarcass"or key=="MovementState"or key=="Health"or key=="MeatRemaining"or key=="FoodRemaining"or key=="RemainingMeat"then queue(node)end
  end)
  connected(node:GetPropertyChangedSignal("Name"),function()queue(node)end)
  end
  if humanoid and marks.watched[node].humanoid~=humanoid then
   marks.watched[node].humanoid=humanoid
   connected(humanoid.HealthChanged,function()queue(node)end)
  end
 end
 local function clear()
  marks.epoch+=1
  for _,link in marks.links do link:Disconnect()end
  table.clear(marks.links)table.clear(marks.queue)table.clear(marks.queued)table.clear(marks.watched)
  for node in marks.tracked do remove(node)end
 end
 function Brain.setCarcassMarkers(value)
  value=value==true and CFG.CarcassMarkers==true and unlocked and alive
  if marks.active==value then return end
  marks.active=value clear()
  if not value then return end
  local epoch=marks.epoch
  connected(workspace.DescendantAdded,queue)
  connected(workspace.DescendantRemoving,function(node)remove(node)marks.watched[node]=nil end)
  for _,tag in tags do
   connected(collection:GetInstanceAddedSignal(tag),queue)
   connected(collection:GetInstanceRemovedSignal(tag),queue)
  end
  task.spawn(function()
   local nodes=workspace:GetDescendants()
   for i,node in nodes do
    if not alive or not marks.active or marks.epoch~=epoch then return end
    queue(node)
    if i%180==0 then task.wait()end
   end
  end)
 end
 local foodButton=button(pages.settings,"علامات الجثث: إيقاف",24,201,612,function()
  CFG.CarcassMarkers=not CFG.CarcassMarkers
  if not CFG.CarcassMarkers then Brain.setCarcassMarkers(false)end
  state(CFG.CarcassMarkers and "علامات الجثث جاهزة؛ اضغط T للإظهار والإخفاء"or "أوقفت علامات الجثث")
 end)
 foodButton.TextSize=14
 local layoutOwner
 function Brain.layoutSettings()
  local owner=Brain.vipOwner and Brain.vipOwner()or false
  if layoutOwner==owner then return end layoutOwner=owner
  local buttons={speedButton,backgroundButton,boostButton}
  if owner and Brain.vipStamina and Brain.vipStamina.button then table.insert(buttons,Brain.vipStamina.button)end
  for _,b in {foodButton,markerButton,afkButton,Brain.saveSettingsButton}do table.insert(buttons,b)end
  for i,b in buttons do b.Position=UDim2.fromOffset(24,73+(i-1)*28)b.Size=UDim2.fromOffset(612,25)end
  imageNote.Position=UDim2.fromOffset(24,73+#buttons*28)imageNote.Size=UDim2.fromOffset(612,15)imageNote.TextSize=10
 end
 Brain.layoutSettings()
 on(UIS.InputBegan,function(input,processed)
  if processed or UIS:GetFocusedTextBox()or input.KeyCode~=Enum.KeyCode.T or not CFG.CarcassMarkers then return end
  Brain.setCarcassMarkers(not marks.active)
 end)
 on(gui.Destroying,function()marks.active=false clear()folder:Destroy()end)
 task.spawn(function()
  local lastCheck=0
  while alive do
   if marks.active and (not unlocked or not CFG.CarcassMarkers or (Brain.licenseExpires and os.clock()>=Brain.licenseExpires))then Brain.setCarcassMarkers(false)end
   if marks.active then
    for _=1,100 do
     local node=table.remove(marks.queue)
     if not node then break end
     marks.queued[node]=nil
     if node:IsDescendantOf(workspace)then watch(node)reconcile(node)end
    end
    if os.clock()-lastCheck>1 then
     lastCheck=os.clock()
     for node,row in marks.tracked do
      if not node:IsDescendantOf(workspace)or not row.part:IsDescendantOf(workspace)or not Brain.isCarcassObject(node)then remove(node)end
     end
    end
   end
   local count=0 for _ in marks.tracked do count+=1 end
   marks.report={enabled=CFG.CarcassMarkers==true,active=marks.active,count=count,pending=#marks.queue}
   foodButton.Text=not CFG.CarcassMarkers and "علامات الجثث: إيقاف"or marks.active and "علامات الجثث: ظاهرة · T"or "علامات الجثث: جاهزة · T"
   task.wait(.1)
  end
  clear()folder:Destroy()
 end)
end
Brain.installCarcassMarkers()
local function cleanup()
	if not alive then return end stop() alive=false
 Brain.warReleaseAim()
 Brain.clearSilverLion()
 Brain.restoreNativeChat()
 if Brain.iconPulse then Brain.iconPulse:Cancel() end
 if Brain.launcherEditable then Brain.launcherEditable:Destroy() Brain.launcherEditable=nil end
 if Brain.uiDecorTweens then for _,tween in Brain.uiDecorTweens do tween:Cancel() end end
 if Brain.war then
  for _,row in Brain.war.rows do
   if row.spawnConnection then row.spawnConnection:Disconnect() end
   if row.deathConnection then row.deathConnection:Disconnect() end
   Brain.warClearVisual(row)
  end
  Brain.war.rows={}
 end
	for _,connection in Brain.needConnections do connection:Disconnect() end
	if viewportConnection then viewportConnection:Disconnect() end
	if Atlas.folder then Atlas.folder:Destroy() end
	uiSequence+=1
	for object,tween in uiTweens do tween:Cancel() uiTweens[object]=nil end
	for _,c in links do c:Disconnect() end
end
on(shutdown.Event,cleanup) on(gui.Destroying,cleanup)
task.spawn(function()
	while alive do
		Brain.refreshSilverLion()
		local f,w=stats()
		local _,atlasRoot=rig() Atlas.draw(atlasRoot)
		foodText.Text="الشبع  "..(f and string.format("%.0f%%",f) or "—")
		waterText.Text="الارتواء  "..(w and string.format("%.0f%%",w) or "—")
		fills[1].Size=UDim2.fromScale(f and f/100 or 0,1) fills[2].Size=UDim2.fromScale(w and w/100 or 0,1)
		imageNote.Text="السرعة المقاسة: "..string.format("%.1f",Brain.measuredSpeed or 0).." • الهدف: "..(Brain.boostTarget and string.format("%.1f",Brain.boostTarget) or "—").." studs/s"
		decisionText.Text=running and (Brain.mode=="Quests" and "وضع المهمات يعمل" or "البقاء التلقائي يعمل") or "جاهز عندما تحتاجه"
		local phase="يراقب الاحتياج"
		if not running then phase="متوقف"
		elseif heldW then phase="ماشي للوجهة"
		elseif f and w and math.min(f,w)<CFG.Threshold then phase="عندي احتياج؛ أجهز له طريق آمن"
		elseif currentState:find("تعبئة",1,true) then phase="يعبئ المورد"
		elseif currentState:find("أبحث",1,true) or currentState:find("أفحص",1,true) then phase="يفحص الطريق" end
		calmState.Text=phase
		calmNeeds.Text="الشبع  "..(f and string.format("%.0f%%",f) or "—")
		Brain.diagnosticWater.Text="الارتواء  "..(w and string.format("%.0f%%",w) or "—")
		local goal=activeKind and Brain.resourceGoals[activeKind]
		calmGoal.Text=goal and (goal.exploration and "الوجهة: نطاق بحث ثابت" or (activeKind=="Water" and "الوجهة: ضفة ماء محددة" or "الوجهة: رقعة عشب محددة")) or "تُحدّد الوجهة عند الحاجة"
		local selected
		for _,q in Brain.readQuests() do if q.key==Brain.activeQuest then selected=q break end end
		if CFG.QuestsEnabled and selected then
			questType.Text=Brain.questLabels[selected.kind] or "مهمة"
			calmQuestTitle.Text=selected.title
			calmQuestProgress.Text=string.format("%d / %d",selected.current,selected.target)
			calmQuestFill.Size=UDim2.fromScale(math.clamp(selected.current/selected.target,0,1),1)
			calmQuestHint.Text=Brain.questHint(selected)
		else
			questType.Text=CFG.QuestsEnabled and "يقرأ القائمة" or "متوقف"
			calmQuestTitle.Text=CFG.QuestsEnabled and "أراجع مهامك المتاحة" or "جاهز لمهمتك الجاية"
			calmQuestProgress.Text=CFG.QuestsEnabled and "المهمات مستقلة عن وضع البقاء" or "فعّل المدير لبدء التنفيذ"
			calmQuestFill.Size=UDim2.fromScale(0,1)
			calmQuestHint.Text="القائمة الكاملة والتفاصيل من زر ⋯"
		end
		Brain.renderQuestDetails()
		local eat,drink=prompt("Food"),prompt("Water")
		if drink and not running and os.clock()-observedDrinkAt>10 then
			observedDrinkAt=os.clock()
			local model,root=rig()
			if model and root then
				local worker=coroutine.running() queryScopes[worker]=generation
				pcall(rememberWater,model,root,false)
				queryScopes[worker]=nil
			end
		end
		if UIS:GetFocusedTextBox()~=debugText then
			debugText.Text="Victory-STRICT-20261121-R17\nFood="..tostring(player.Character and player.Character:GetAttribute("Food")).." / Water="..tostring(player.Character and player.Character:GetAttribute("Water")).."\n"..
				"مصدر الأكل الخام: "..rawSource().."\n"..
				"أكل ظاهر: "..(eat and eat.Text or "لا").." / شرب ظاهر: "..(drink and drink.Text or "لا").."\n"..
				"عينات MainWaterPart/Terrain: "..(waterScanDone and tostring(waterSamples) or "لم يبدأ الفحص").." / نقطة شرب محفوظة: "..tostring(knownShore~=nil).."\n"..
				"الركض: "..Brain.speedInfo.." / Sprint="..tostring(player.Character and player.Character:GetAttribute("SprintToggledOn")).."\n"..
				"تسجيل E: "..inputSummary().."\n"..
				"Lite: حد الأشعة/الإطار="..CFG.QueriesPerFrame.." / أعلى دفعة="..perf.peak.." / تقدير Heartbeat="..math.floor(1/math.max(.001,perf.frameSeconds)).."\n"..
				"آخر اختبار E: "..lastE.."\n"..
				"نتيجة الحركة: "..tostring(Brain.lastWalkResult or "لم تنته الرحلة").."\n"..
				"المسار: "..tostring(Brain.routeReason or "لم يبدأ").." / الموقع: "..tostring(atlasRoot and atlasRoot.Position).."\n"..
				"الحالة: "..currentState
		end
		task.wait(.8)
	end
end)
 task.spawn(function() task.wait(.5) Brain.activateLicense() end)
centerWindow()
setWindowShown(true)
