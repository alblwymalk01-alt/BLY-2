-- BLY R46 PC dry-shore test loader. This updates only the downloaded R44 test copy in memory.
-- Never writes the original loader URL, existing repository files, or player data.
local base="https://raw.githubusercontent.com/alblwymalk01-alt/BLY-2/main/tests/BLY-Victory-PC-SmartSurvival-TEST-R44.luau"
local ok,source=pcall(function()return game:HttpGet(base)end)
assert(ok and type(source)=="string" and #source>100000,"BLY R46: تعذر تحميل نسخة R44 الأساسية")
local function replaceOnce(before,after,label)
 local a,b=source:find(before,1,true)
 assert(a,"BLY R46: تغير كود "..label)
 source=source:sub(1,a-1)..after..source:sub(b+1)
end
local function replaceBlock(first,last,replacement,label)
 local a,b=source:find(first,1,true)
 assert(a,"BLY R46: لم أجد بداية "..label)
 local c=source:find(last,b+1,true)
 assert(c,"BLY R46: لم أجد نهاية "..label)
 source=source:sub(1,a-1)..replacement..source:sub(c)
end

replaceOnce("local function walkable(position,model,allowShallow)",
[==[local function walkable(position,model,allowShallow)
 if activeKind=="Water" and not Brain.escapeReturn then allowShallow=false end]==],"dry_walkable")
replaceOnce("local function safeSegment(a,b,model,allowShallow)",
[==[local function safeSegment(a,b,model,allowShallow)
 if activeKind=="Water" and not Brain.escapeReturn then allowShallow=false end]==],"dry_segment")
replaceOnce("if goal.shoreFailures>=3 then", "if goal.shoreFailures>=2 then","shore_retries")
replaceOnce('avoided["Water"..cell(goal.position)]=os.clock()+25', 'avoided["Water"..cell(goal.position)]=os.clock()+90',"shore_cooldown")
replaceOnce("if (goal.approachAt and os.clock()-goal.approachAt>12) or (goal.shoreFailures or 0)>=3 then",
"if (goal.shoreFailures or 0)>0 or (goal.approachAt and os.clock()-goal.approachAt>12) then","shore_resume")

replaceBlock("local function approachShore(route,token,model,root)","function Brain.exitFloor(position,model)",[==[
-- R46: Look for a real Drink prompt by moving on dry land along the shoreline.
local function approachShore(route,token,model,root)
 if not route.water or not valid(token,model) then return false end
 releaseW("dry_shore_begin")
 local goal=Brain.resourceGoals.Water
 if goal and (not route.goalPosition or Brain.homeDistance(goal.position,route.goalPosition)>3) then goal=nil end
 if prompt("Water",true) then
  if goal then Brain.rememberShoreApproach(route,model,root,"drink_available") end
  return true
 end
 local origin=root.Position
 local delta=route.water-origin
 local flat=Vector3.new(delta.X,0,delta.Z)
 if flat.Magnitude<.25 then
  if goal then Brain.rememberShoreApproach(route,model,root,"no_shore_direction") end
  return false
 end
 local toward=flat.Unit
 local across=Vector3.new(-toward.Z,0,toward.X)
 local deadline=os.clock()+18
 local outcome="no_dry_drink_prompt"
 local attempts=0
 local tried=goal and (goal.shoreTried or {}) or {}
 if goal then goal.shoreTried=tried end
 for _,side in {0,3,-3,6,-6,10,-10,15,-15} do
  if not valid(token,model) or os.clock()>=deadline or attempts>=9 then break end
  for _,forward in {0,1.5,-1.5,3} do
   if not valid(token,model) or os.clock()>=deadline or attempts>=9 then break end
   if prompt("Water",true) then outcome="drink_available" break end
   local target=origin+across*side+toward*forward
   local land=cast(target,model)
   if dry(land) and (land.Position-route.water).Magnitude<=22
    and (not CFG.HomeOnly or Brain.mode=="Quests" or Brain.homeInside(land.Position)) then
    local key=math.floor(land.Position.X/2)..":"..math.floor(land.Position.Z/2)
    if not tried[key] and safeSegment(root.Position,land.Position,model,false) then
     tried[key]=true
     attempts+=1
     local travel=land.Position-root.Position
     if Vector3.new(travel.X,0,travel.Z).Magnitude>1.2 then
      local leg={position=land.Position,goalPosition=land.Position,
       points={{Position=root.Position},{Position=land.Position}}}
      state("أدور على زر الشرب بمحاذاة الضفة، بدون دخول المويه")
      local result=walk(leg,"Water",token,model,root)
      releaseW("dry_shore_leg_"..tostring(result))
      if not valid(token,model) then return false end
      local _,_,humanoid=rig()
      if Brain.waterThreat and Brain.waterThreat(model,root,humanoid) then
       outcome="water_danger" break end
      end
     end
     if prompt("Water",true) then outcome="drink_available" break end
    end
   end
  end
  if outcome=="drink_available" or outcome=="water_danger" then break end
 end
 releaseW("dry_shore_"..outcome)
 if valid(token,model) and goal then Brain.rememberShoreApproach(route,model,root,outcome) end
 Brain.motionTrace("dry_shore_survey",outcome.." / checked="..tostring(attempts))
 return outcome=="drink_available"
end
]==],"dry_approach")

replaceBlock("local function nudgeIntoWater(token,model,root)","local function inputSummary()",
"-- R46: removed deliberate water-entry nudges\n","remove_nudge")
replaceBlock("for attempt=1,4 do","if not valid(token,model) then return end",[==[
if kind=="Water" and not confirmed and consumeOutcome=="no_increase" then
 avoided["Water"..cell(root.Position)]=os.clock()+90
 local stale=Brain.resourceGoals.Water
 if stale then
  avoided["Water"..cell(stale.position)]=os.clock()+90
  Brain.clearResourceGoal("Water","ظهر زر الشرب لكن عداد Water لم يرتفع؛ أجرب ضفة ثانية")
 end
 Brain.motionTrace("water_no_increase","reject_station_no_nudge")
end
]==],"no_swim_retry")
replaceOnce("BLY-PC-SMART-NAV-TEST-R44-20261123","BLY-PC-DRY-SHORE-TEST-R46-20261124","version")
replaceOnce("BLY-PC-SMART-NAV-TEST-R44-20261123","BLY-PC-DRY-SHORE-TEST-R46-20261124","diagnostics_version")
assert(not source:find("nudgeIntoWater(",1,true),"BLY R46: بقيت محاولة دخول الماء")
local run,err=loadstring(source)
assert(run,"BLY R46: خطأ في تحميل النسخة: "..tostring(err))
return run()
