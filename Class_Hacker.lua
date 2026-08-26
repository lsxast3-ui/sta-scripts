-- CLASS HACKER  |  by logicself / lsxast
-- PlaceId: 116139828947259

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")
local TweenService     = game:GetService("TweenService")

local lp  = Players.LocalPlayer

local CFG = {
    MAX_RANGE        = 400,
    INFILTRATE_RANGE = 100,
    SHOOT_RATE       = 0.09,
    TARGET_UPD_RATE  = 0.5,
    HEAD_EXP_SIZE    = 5,
    HEAD_EXP_ALPHA   = 0.65,
}

local STATE = {
    autoInfiltrate   = false,
    autoShoot        = false,
    autoUpdateTarget = false,
    headExpander     = false,
}

local lastShot        = 0
local lastTargetUpd   = 0
local lastInfiltrate  = 0
local lastInfiltrateUse = 0
local infiltrateRunning = false
local shotCounter     = 1
local lastWeapon      = nil
local expandedHeads   = {}
local INFILTRATE_CD   = 15

-- ── WHITELIST ─────────────────────────────────────────────
local SURVIVOR_NAMES = {
    Survivor=true, Fighter=true, Medic=true, Soldier=true,
    Scavenger=true, Assassin=true, Policeman=true,
    ["Necromancer"]=true, Merchant=true, Trader=true, Vendor=true, NPC=true,
}

local ENEMY_NAMES = {
    Zombie=true, Crawler=true, Runner=true, Bloater=true, Spitter=true,
    Riot=true, Phaser=true, Hazmat=true, Screamer=true, Muscle=true,
    Elemental=true, Electrified=true, Brute=true, ["Night Hunter"]=true,
    Bandit=true, Rebel=true, Gunner=true, Sniper=true,
    ["Heavy Rebel"]=true, Butcher=true, Harbinger=true, Cyborg=true,
    ["Armored Zombie"]=true, ["Enforcer Riot"]=true, ["Acidic Bloater"]=true,
    ["Blitzer Runner"]=true, ["Blighted Spitter"]=true, ["Tank Muscle"]=true,
    ["Nuclear Hazmat"]=true, ["Aberrant Screamer"]=true, ["Rotted Zombie"]=true,
    ["Specter Phaser"]=true, ["Frost Elemental"]=true, ["Infested Zombie"]=true,
    ["Infested Runner"]=true, ["Infested Crawler"]=true, ["Infested Bloater"]=true,
    ["Infested Riot"]=true, ["Infested Screamer"]=true, ["Infested Muscle"]=true,
    ["Infested Brute"]=true, Skeleton=true, ["Skeleton King"]=true,
    ["Electrified Muscle"]=true, ["Shadow Muscle"]=true,
}

local function isAllyZombie(model)
    if model:FindFirstChild("AllyHighlight")  then return true end
    if model:FindFirstChild("FriendlyTag")    then return true end
    if model:FindFirstChild("Friendly")       then return true end
    if model:FindFirstChild("AllyTag")        then return true end
    if model:FindFirstChild("NecroMinion")    then return true end
    if model:FindFirstChild("SummonTag")      then return true end
    if model:FindFirstChild("AlliedZombie")   then return true end
    for _, v in pairs(model:GetChildren()) do
        if v:IsA("StringValue") or v:IsA("BoolValue") then
            local n = v.Name:lower()
            if n:find("ally") or n:find("friend") or n:find("necro") or n:find("summon") then
                return true
            end
        end
    end
    return false
end

local function isValidEnemy(model)
    if not ENEMY_NAMES[model.Name]   then return false end
    if SURVIVOR_NAMES[model.Name]    then return false end
    if isAllyZombie(model)           then return false end
    return true
end

-- ── UTILITY ───────────────────────────────────────────────
local function getNilPart(name, zombie)
    local d = zombie:FindFirstChild(name, true)
    if d then return d end
    if getnilinstances then
        for _, v in next, getnilinstances() do
            if v.ClassName == "Part" and v.Name == name then
                local p = v.Parent
                while p do
                    if p == zombie then return v end
                    p = p.Parent
                end
            end
        end
    end
    return nil
end

local function getNilInst(name, class)
    if not getnilinstances then return nil end
    for _, v in next, getnilinstances() do
        if v.ClassName == class and v.Name == name then return v end
    end
    return nil
end

local function hasVirus(zombie)
    return zombie:FindFirstChild("VirusHighlight",      true) ~= nil
        or zombie:FindFirstChild("HackerVirusParticle", true) ~= nil
        or zombie:FindFirstChild("InfestedHighlight",   true) ~= nil
        or zombie:FindFirstChild("VirusEffect",         true) ~= nil
end

local function hasLineOfSight(zombie)
    local char = lp.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local zHRP = zombie:FindFirstChild("HumanoidRootPart")
              or zombie:FindFirstChild("UpperTorso")
              or zombie:FindFirstChild("Torso")
    if not zHRP then return false end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { char, zombie }
    local result = workspace:Raycast(hrp.Position, zHRP.Position - hrp.Position, rp)
    if result then
        local p = result.Instance
        while p do
            if p == zombie then return true end
            p = p.Parent
        end
        return false
    end
    return true
end

local function isEnemy(zombie)
    local hum = zombie:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character == zombie then return false end
    end
    return isValidEnemy(zombie)
end

local function getZombieRoot(zombie)
    return zombie:FindFirstChild("HumanoidRootPart")
        or zombie:FindFirstChild("Torso")
        or zombie:FindFirstChild("UpperTorso")
end

-- ── REMOTES ───────────────────────────────────────────────
local function findToolRemote(toolName, remoteName)
    local function s(parent)
        if not parent then return nil end
        local t = parent:FindFirstChild(toolName)
        return t and t:FindFirstChild(remoteName) or nil
    end
    return s(lp:FindFirstChild("Backpack")) or s(lp.Character)
end

local function getInfiltrateRemote()     return findToolRemote("Infiltrate",      "Use") end
local function getSystemOverrideRemote() return findToolRemote("System Override", "Use") end

local function getAutoTargetRemote()
    local char = lp.Character
    if not char then return nil end
    local atc = char:FindFirstChild("AutoTargetClient")
    return atc and atc:FindFirstChild("UpdateNearbyTargets")
end

local function getWeaponShootRemote()
    local char = lp.Character
    if not char then return nil, nil end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            local s = tool:FindFirstChild("Shoot")
            if s and s:IsA("RemoteEvent") then return tool, s end
        end
    end
    return nil, nil
end

-- ── TARGET SELECTION ─────────────────────────────────────
local function getBestTarget(virusPriority)
    local char = lp.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local myPos = hrp.Position
    local chars = workspace:FindFirstChild("Characters")
    if not chars then return nil end
    local bestInf, bestNor
    local dInf, dNor = math.huge, math.huge
    for _, z in pairs(chars:GetChildren()) do
        if not isEnemy(z) then continue end
        local root = getZombieRoot(z)
        if not root then continue end
        local dist = (root.Position - myPos).Magnitude
        if dist > CFG.MAX_RANGE then continue end
        if not hasLineOfSight(z) then continue end
        if hasVirus(z) then
            if dist < dInf then dInf = dist; bestInf = z end
        else
            if dist < dNor then dNor = dist; bestNor = z end
        end
    end
    if virusPriority then
        -- untuk auto shoot: HANYA kembalikan yang sudah terinfeksi
        return bestInf
    end
    return bestNor
end

local function getBestInfiltrateTarget()
    local char = lp.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local myPos = hrp.Position

    -- Filter berdasarkan arah kamera jika tersedia
    local camCF      = nil
    local camPos     = nil
    local camForward = nil
    local ok = pcall(function()
        local c = game:GetService("Workspace").CurrentCamera
        if c then
            camCF      = c.CFrame
            camPos     = camCF.Position
            camForward = camCF.LookVector
        end
    end)

    local chars = workspace:FindFirstChild("Characters")
    if not chars then return nil end
    local best, bd = nil, math.huge
    for _, z in pairs(chars:GetChildren()) do
        if not isEnemy(z) then continue end
        if hasVirus(z) then continue end
        local root = getZombieRoot(z)
        if not root then continue end

        local dist = (root.Position - myPos).Magnitude
        if dist > CFG.INFILTRATE_RANGE then continue end

        -- Filter 180 derajat depan karakter
        -- LookVector karakter dot arah ke zombie > 0 = di depan
        local toZombie = (root.Position - myPos).Unit
        if hrp.CFrame.LookVector:Dot(toZombie) <= 0 then continue end

        -- Filter arah kamera hanya jika berhasil didapat
        if camForward and camPos then
            local toZombie = (root.Position - camPos).Unit
            local dot = camForward:Dot(toZombie)
            if dot < 0.3 then continue end
        end

        if not hasLineOfSight(z) then continue end

        if dist < bd then bd = dist; best = z end
    end
    return best
end

-- ── SHOOT ARGS ────────────────────────────────────────────
local function buildShootArgs(zombie, counter)
    local char = lp.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local hitPart = getNilPart("Head", zombie)
    if not hitPart then return nil end
    local origin = hrp.Position
    local hitPos = hitPart.Position
    local root   = getZombieRoot(zombie)
    local targetPos = root and root.Position or hitPos
    return {
        [1] = origin,
        [2] = { [1] = {
            ["Target"]  = targetPos,
            ["HitData"] = { [1] = { ["HitChar"]=zombie, ["HitPos"]=hitPos, ["HitPart"]=hitPart }},
            ["EffectResults"] = { [1] = { ["Origin"]=origin, ["End"]=targetPos }},
        }},
        [3] = 0, [4] = counter,
    }
end

-- ── NEARBY LIST (UpdateNearbyTargets) ─────────────────────
local function getNearbyList()
    local char = lp.Character
    if not char then return {} end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return {} end
    local myPos = hrp.Position
    local all = {}
    local chars = workspace:FindFirstChild("Characters")
    if chars then
        for _, z in pairs(chars:GetChildren()) do
            if isEnemy(z) then table.insert(all, z) end
        end
    end
    table.sort(all, function(a, b)
        local ra = getZombieRoot(a); local rb = getZombieRoot(b)
        local da = ra and (ra.Position-myPos).Magnitude or math.huge
        local db = rb and (rb.Position-myPos).Magnitude or math.huge
        return da < db
    end)
    local r = {}
    for i = 1, math.min(12, #all) do r[i] = all[i] end
    return r
end

-- ── HEAD EXPANDER ─────────────────────────────────────────
local function expandHead(zombie)
    local head = zombie:FindFirstChild("Head", true)
    if not head or not head:IsA("BasePart") or expandedHeads[head] then return end
    expandedHeads[head] = { Size=head.Size, Transparency=head.Transparency }
    head.Size = Vector3.new(CFG.HEAD_EXP_SIZE, CFG.HEAD_EXP_SIZE, CFG.HEAD_EXP_SIZE)
    head.Transparency = CFG.HEAD_EXP_ALPHA
    head.CanCollide   = false
end

local function restoreHead(head)
    if not expandedHeads[head] then return end
    if head and head.Parent then
        head.Size         = expandedHeads[head].Size
        head.Transparency = expandedHeads[head].Transparency
    end
    expandedHeads[head] = nil
end

local function restoreAllHeads()
    for head in pairs(expandedHeads) do restoreHead(head) end
    expandedHeads = {}
end

local function updateHeadSizes()
    for head in pairs(expandedHeads) do
        if head and head.Parent then
            head.Size = Vector3.new(CFG.HEAD_EXP_SIZE, CFG.HEAD_EXP_SIZE, CFG.HEAD_EXP_SIZE)
        end
    end
end

RunService.Heartbeat:Connect(function()
    if not STATE.headExpander then
        if next(expandedHeads) then restoreAllHeads() end
        return
    end
    local chars = workspace:FindFirstChild("Characters")
    if not chars then return end
    for _, z in pairs(chars:GetChildren()) do
        local isP = false
        for _, p in pairs(Players:GetPlayers()) do
            if p.Character == z then isP = true; break end
        end
        if not isP then
            local head = z:FindFirstChild("Head", true)
            if head and head:IsA("BasePart") and not expandedHeads[head] then
                expandHead(z)
            end
        end
    end
    for head in pairs(expandedHeads) do
        if not head or not head.Parent then expandedHeads[head] = nil end
    end
end)

-- ── EQUIP HELPERS ────────────────────────────────────────
local function equipTool(tool)
    local char = lp.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum:EquipTool(tool)
end

local function unequipAll()
    local char = lp.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum:UnequipTools()
end

local function getCurrentWeapon()
    local char = lp.Character
    if not char then return nil end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") then return tool end
    end
    return nil
end

local function getOldTool(name)
    if not name then return nil end
    local bp   = lp:FindFirstChild("Backpack")
    local char = lp.Character
    if bp   and bp:FindFirstChild(name)   then return bp:FindFirstChild(name) end
    if char and char:FindFirstChild(name) then return char:FindFirstChild(name) end
    return nil
end

local function swapBack(prevWeaponName)
    if prevWeaponName then
        local old = getOldTool(prevWeaponName)
        if old then pcall(function() equipTool(old) end)
        else        pcall(function() unequipAll()   end) end
    else
        pcall(function() unequipAll() end)
    end
end

-- ── AUTO INFILTRATE ───────────────────────────────────────
-- Logika:
-- 1. Jika CD habis → auto equip Infiltrate ke tangan player
-- 2. Player pakai manual (klik kiri) → skill jalan
-- 3. Deteksi via hookfunction pada FireServer Infiltrate.Use
--    → saat player fire, script otomatis swap kembali ke senjata lama
-- ─────────────────────────────────────────────────────────

local infiltrateHook    = nil  -- menyimpan hook agar bisa di-unhook
local prevWeaponNameINF = nil  -- senjata sebelum equip Infiltrate
local infiltrateEquipped = false

local function unhookInfiltrate()
    if infiltrateHook then
        pcall(function() infiltrateHook() end)
        infiltrateHook = nil
    end
end

local function hookInfiltrateUse(remote)
    -- Hook FireServer pada remote Infiltrate.Use
    -- Saat player fire (pakai skill), deteksi dan swap balik
    local originalFireServer = remote.FireServer
    infiltrateHook = hookfunction(originalFireServer, function(self, ...)
        -- Panggil original dulu agar skill tetap jalan
        local result = {originalFireServer(self, ...)}
        -- Catat waktu penggunaan
        lastInfiltrateUse = tick()
        infiltrateRunning = false
        -- Unhook agar tidak trigger berkali-kali
        unhookInfiltrate()
        -- Swap kembali ke senjata lama setelah jeda singkat
        task.delay(0.5, function()
            swapBack(prevWeaponNameINF)
            infiltrateEquipped = false
        end)
        return table.unpack(result)
    end)
end

RunService.Heartbeat:Connect(function()
    if not STATE.autoInfiltrate then
        -- Kalau toggle dimatikan, unhook dan swap balik
        if infiltrateEquipped then
            unhookInfiltrate()
            swapBack(prevWeaponNameINF)
            infiltrateEquipped = false
        end
        return
    end

    local now = tick()
    if now - lastInfiltrate < 0.5 then return end
    lastInfiltrate = now

    -- CD belum habis — pastikan tidak auto equip
    if now - lastInfiltrateUse < INFILTRATE_CD then
        -- Kalau Infiltrate masih di tangan dan seharusnya sudah swap balik
        if infiltrateEquipped and not infiltrateRunning then
            unhookInfiltrate()
            swapBack(prevWeaponNameINF)
            infiltrateEquipped = false
        end
        return
    end

    -- CD habis — cek apakah Infiltrate sudah di tangan
    local char = lp.Character
    if not char then return end
    local alreadyHeld = char:FindFirstChild("Infiltrate") ~= nil

    if alreadyHeld and infiltrateEquipped then return end  -- sudah di tangan, tunggu player pakai

    -- WAJIB ada target valid dulu sebelum equip
    -- Kalau tidak ada zombie dalam range, jangan equip
    local target = getBestInfiltrateTarget()
    if not target then return end

    -- Cari tool Infiltrate
    local infiltrateTool = nil
    local bp = lp:FindFirstChild("Backpack")
    if bp then infiltrateTool = bp:FindFirstChild("Infiltrate") end
    if not infiltrateTool and not alreadyHeld then return end
    if alreadyHeld then
        local t = char:FindFirstChild("Infiltrate")
        if t then infiltrateTool = t end
    end
    if not infiltrateTool then return end

    -- Simpan senjata yang sedang dipegang (kalau bukan Infiltrate sendiri)
    local current = getCurrentWeapon()
    if current and current.Name == "Infiltrate" then
        -- Sudah pegang Infiltrate, setup hook saja jika belum
        if not infiltrateEquipped then
            infiltrateEquipped = true
            local remote = infiltrateTool:FindFirstChild("Use")
            if remote and not infiltrateHook then
                hookInfiltrateUse(remote)
            end
        end
        return
    end

    prevWeaponNameINF = current and current.Name or nil
    infiltrateEquipped = true
    infiltrateRunning  = true

    task.spawn(function()
        -- Equip Infiltrate
        pcall(function() equipTool(infiltrateTool) end)

        -- Tunggu ter-equip lalu pasang hook
        local equippedTool = nil
        for _ = 1, 20 do
            task.wait(0.05)
            local c = lp.Character
            if c then
                local t = c:FindFirstChild("Infiltrate")
                if t then equippedTool = t; break end
            end
        end

        if equippedTool then
            local remote = equippedTool:FindFirstChild("Use")
            if remote then
                hookInfiltrateUse(remote)
            end
        end

        -- Kalau player tidak pakai dalam 8 detik, swap balik otomatis
        task.delay(8, function()
            if infiltrateEquipped then
                unhookInfiltrate()
                swapBack(prevWeaponNameINF)
                infiltrateEquipped = false
                infiltrateRunning  = false
            end
        end)
    end)
end)

-- ── AUTO SHOOT — hanya zombie yang SUDAH terinfeksi ───────
RunService.Heartbeat:Connect(function()
    local weapon, _ = getWeaponShootRemote()
    if weapon ~= lastWeapon then
        lastWeapon  = weapon
        shotCounter = 1
    end
    if not STATE.autoShoot then return end
    local now = tick()
    if now - lastShot < CFG.SHOOT_RATE then return end
    lastShot = now
    -- hanya cari zombie yang sudah kena virus (virusPriority=true, non-virus diabaikan)
    local target = getBestTarget(true)
    if not target then return end
    -- double-check: skip kalau belum kena virus
    if not hasVirus(target) then return end
    local hum = target:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local _, remote = getWeaponShootRemote()
    if not remote then return end
    local args = buildShootArgs(target, shotCounter)
    if not args then return end
    local ok = pcall(function() remote:FireServer(unpack(args)) end)
    if ok then shotCounter = shotCounter + 1 end
end)

-- ── AUTO UPDATE TARGETS ───────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not STATE.autoUpdateTarget then return end
    local now = tick()
    if now - lastTargetUpd < CFG.TARGET_UPD_RATE then return end
    lastTargetUpd = now
    local remote = getAutoTargetRemote()
    if not remote then return end
    local list = getNearbyList()
    if #list == 0 then return end
    local args = { [1] = {} }
    for i, z in ipairs(list) do args[1][i] = z end
    pcall(function() remote:FireServer(unpack(args)) end)
end)

lp.CharacterAdded:Connect(function()
    shotCounter = 1; lastWeapon = nil
    restoreAllHeads()
end)

-- ═══════════════════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════════════════
if CoreGui:FindFirstChild("ClassHacker_UI") then
    CoreGui:FindFirstChild("ClassHacker_UI"):Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "ClassHacker_UI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = CoreGui

local C = {
    BG       = Color3.fromRGB( 8, 14,  8),
    HEADER   = Color3.fromRGB(10, 22, 10),
    BORDER   = Color3.fromRGB(30, 80, 30),
    ACCENT   = Color3.fromRGB(40,200, 60),
    TEXT     = Color3.fromRGB(180,240,180),
    TEXT_DIM = Color3.fromRGB( 80,130, 80),
    ON       = Color3.fromRGB( 50,220, 70),
    OFF      = Color3.fromRGB(150, 40, 40),
    ROW      = Color3.fromRGB( 14, 24, 14),
    SL_B     = Color3.fromRGB( 15, 35, 15),
    SL_F     = Color3.fromRGB( 40,200, 60),
    OVR      = Color3.fromRGB(200, 30, 30),
    OVR2     = Color3.fromRGB(255, 60, 60),
}
local PW=230; local HH=30; local RH=28; local PAD=8
local CR=UDim.new(0,8); local CS=UDim.new(0,5)

local panel = Instance.new("Frame")
panel.Name="Panel"; panel.Size=UDim2.new(0,PW,0,440)
panel.Position=UDim2.new(1,-(PW+16),0.5,-220)
panel.BackgroundColor3=C.BG; panel.BorderSizePixel=0
panel.Active=true; panel.Draggable=true; panel.ClipsDescendants=true
panel.Parent=ScreenGui
Instance.new("UICorner",panel).CornerRadius=CR
local ps=Instance.new("UIStroke",panel); ps.Color=C.BORDER; ps.Thickness=1.5

local scan=Instance.new("Frame",panel)
scan.Size=UDim2.new(1,0,0,1); scan.BackgroundColor3=C.ACCENT
scan.BackgroundTransparency=0.6; scan.BorderSizePixel=0
scan.ZIndex=10; scan.Position=UDim2.new(0,0,0,HH)
task.spawn(function()
    while true do
        TweenService:Create(scan,TweenInfo.new(3,Enum.EasingStyle.Linear),{Position=UDim2.new(0,0,1,-2)}):Play()
        task.wait(3)
        TweenService:Create(scan,TweenInfo.new(0),{Position=UDim2.new(0,0,0,HH)}):Play()
        task.wait(0.08)
    end
end)

local header=Instance.new("Frame",panel)
header.Size=UDim2.new(1,0,0,HH); header.BackgroundColor3=C.HEADER
header.BorderSizePixel=0; header.ZIndex=5
local hg=Instance.new("UIGradient",header)
hg.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(10,45,10)),
    ColorSequenceKeypoint.new(1,Color3.fromRGB(5,20,5)),
})

-- Logo LSxAS
local logoLbl=Instance.new("TextLabel",header)
logoLbl.Size=UDim2.new(0,50,0,20); logoLbl.Position=UDim2.new(0,6,0.5,-10)
logoLbl.BackgroundColor3=C.ACCENT; logoLbl.Text="LSxAS"
logoLbl.TextColor3=C.BG; logoLbl.TextSize=9; logoLbl.Font=Enum.Font.GothamBold
logoLbl.ZIndex=6
Instance.new("UICorner",logoLbl).CornerRadius=CS

local titleLbl=Instance.new("TextLabel",header)
titleLbl.Size=UDim2.new(1,-90,1,0); titleLbl.Position=UDim2.new(0,62,0,0)
titleLbl.BackgroundTransparency=1; titleLbl.Text="CLASS HACKER"
titleLbl.TextColor3=C.ACCENT; titleLbl.TextSize=12; titleLbl.Font=Enum.Font.GothamBold
titleLbl.TextXAlignment=Enum.TextXAlignment.Left; titleLbl.ZIndex=6

local minBtn=Instance.new("TextButton",header)
minBtn.Size=UDim2.new(0,18,0,16); minBtn.Position=UDim2.new(1,-22,0.5,-8)
minBtn.BackgroundColor3=Color3.fromRGB(30,70,30); minBtn.BorderSizePixel=0
minBtn.Text="−"; minBtn.TextColor3=C.TEXT; minBtn.TextSize=13
minBtn.Font=Enum.Font.GothamBold; minBtn.ZIndex=7
Instance.new("UICorner",minBtn).CornerRadius=CS

local scroll=Instance.new("ScrollingFrame",panel)
scroll.Size=UDim2.new(1,0,1,-HH); scroll.Position=UDim2.new(0,0,0,HH)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=C.ACCENT
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
local sL=Instance.new("UIListLayout",scroll)
sL.SortOrder=Enum.SortOrder.LayoutOrder; sL.Padding=UDim.new(0,3)
local sP=Instance.new("UIPadding",scroll)
sP.PaddingTop=UDim.new(0,6); sP.PaddingBottom=UDim.new(0,8)
sP.PaddingLeft=UDim.new(0,PAD); sP.PaddingRight=UDim.new(0,PAD)

local FH=440; local isMin=false
minBtn.MouseButton1Click:Connect(function()
    isMin=not isMin
    TweenService:Create(panel,TweenInfo.new(0.2,Enum.EasingStyle.Quad),
        {Size=UDim2.new(0,PW,0,isMin and HH or FH)}):Play()
    minBtn.Text=isMin and "+" or "−"; scroll.Visible=not isMin
end)

-- helpers
local function sec(text,order)
    local l=Instance.new("TextLabel",scroll)
    l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1
    l.Text=text; l.TextColor3=C.ACCENT; l.TextSize=9
    l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left
    l.LayoutOrder=order; return l
end

local function div(order)
    local d=Instance.new("Frame",scroll)
    d.Size=UDim2.new(1,0,0,1); d.BackgroundColor3=C.BORDER
    d.BorderSizePixel=0; d.LayoutOrder=order
end

local function tog(label,desc,order)
    local row=Instance.new("Frame",scroll)
    row.Size=UDim2.new(1,0,0,RH+(desc and 14 or 0))
    row.BackgroundColor3=C.ROW; row.BorderSizePixel=0; row.LayoutOrder=order
    Instance.new("UICorner",row).CornerRadius=CS

    local dot=Instance.new("Frame",row)
    dot.Size=UDim2.new(0,8,0,8); dot.Position=UDim2.new(0,8,0,10)
    dot.BackgroundColor3=C.OFF; dot.BorderSizePixel=0
    Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)

    local lbl=Instance.new("TextLabel",row)
    lbl.Size=UDim2.new(1,-60,0,18); lbl.Position=UDim2.new(0,22,0,5)
    lbl.BackgroundTransparency=1; lbl.Text=label
    lbl.TextColor3=C.TEXT; lbl.TextSize=11; lbl.Font=Enum.Font.GothamBold
    lbl.TextXAlignment=Enum.TextXAlignment.Left

    if desc then
        local dl=Instance.new("TextLabel",row)
        dl.Size=UDim2.new(1,-22,0,12); dl.Position=UDim2.new(0,22,0,20)
        dl.BackgroundTransparency=1; dl.Text=desc
        dl.TextColor3=C.TEXT_DIM; dl.TextSize=8; dl.Font=Enum.Font.Gotham
        dl.TextXAlignment=Enum.TextXAlignment.Left
    end

    local sw=Instance.new("Frame",row)
    sw.Size=UDim2.new(0,36,0,18); sw.Position=UDim2.new(1,-44,0.5,-9)
    sw.BackgroundColor3=Color3.fromRGB(30,50,30); sw.BorderSizePixel=0
    Instance.new("UICorner",sw).CornerRadius=UDim.new(1,0)

    local knob=Instance.new("Frame",sw)
    knob.Size=UDim2.new(0,14,0,14); knob.Position=UDim2.new(0,2,0.5,-7)
    knob.BackgroundColor3=Color3.fromRGB(120,140,120); knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)

    local btn=Instance.new("TextButton",row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""

    local function setOn(v)
        local ti=TweenInfo.new(0.15)
        if v then
            TweenService:Create(dot,ti,{BackgroundColor3=C.ON}):Play()
            TweenService:Create(sw,ti,{BackgroundColor3=C.ON}):Play()
            TweenService:Create(knob,ti,{Position=UDim2.new(1,-16,0.5,-7),BackgroundColor3=Color3.fromRGB(255,255,255)}):Play()
        else
            TweenService:Create(dot,ti,{BackgroundColor3=C.OFF}):Play()
            TweenService:Create(sw,ti,{BackgroundColor3=Color3.fromRGB(30,50,30)}):Play()
            TweenService:Create(knob,ti,{Position=UDim2.new(0,2,0.5,-7),BackgroundColor3=Color3.fromRGB(120,140,120)}):Play()
        end
    end
    return btn, setOn
end

local function sld(label,minV,maxV,initV,order,fn)
    local c=Instance.new("Frame",scroll)
    c.Size=UDim2.new(1,0,0,38); c.BackgroundColor3=C.ROW
    c.BorderSizePixel=0; c.LayoutOrder=order
    Instance.new("UICorner",c).CornerRadius=CS

    local kl=Instance.new("TextLabel",c)
    kl.Size=UDim2.new(0,110,0,16); kl.Position=UDim2.new(0,8,0,4)
    kl.BackgroundTransparency=1; kl.Text=label
    kl.TextColor3=C.TEXT_DIM; kl.TextSize=9; kl.Font=Enum.Font.Gotham
    kl.TextXAlignment=Enum.TextXAlignment.Left

    local vl=Instance.new("TextLabel",c)
    vl.Size=UDim2.new(0,36,0,16); vl.Position=UDim2.new(1,-40,0,4)
    vl.BackgroundTransparency=1; vl.Text=tostring(initV)
    vl.TextColor3=C.ACCENT; vl.TextSize=10; vl.Font=Enum.Font.GothamBold
    vl.TextXAlignment=Enum.TextXAlignment.Right

    local track=Instance.new("Frame",c)
    track.Size=UDim2.new(1,-18,0,4); track.Position=UDim2.new(0,9,0,28)
    track.BackgroundColor3=C.SL_B; track.BorderSizePixel=0
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

    local fill=Instance.new("Frame",track)
    fill.Size=UDim2.new((initV-minV)/(maxV-minV),0,1,0)
    fill.BackgroundColor3=C.SL_F; fill.BorderSizePixel=0
    Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)

    local knob=Instance.new("Frame",track)
    knob.Size=UDim2.new(0,12,0,12); knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=UDim2.new((initV-minV)/(maxV-minV),0,0.5,0)
    knob.BackgroundColor3=C.TEXT; knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)

    local kb=Instance.new("TextButton",knob)
    kb.Size=UDim2.new(1,0,1,0); kb.BackgroundTransparency=1; kb.Text=""; kb.ZIndex=4

    local drag=false; local cur=initV
    kb.MouseButton1Down:Connect(function() drag=true end)
    track.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
    RunService.RenderStepped:Connect(function()
        if not drag then return end
        local mx=UserInputService:GetMouseLocation().X
        local r=math.clamp((mx-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
        local nv=math.floor(minV+r*(maxV-minV)+0.5)
        if nv~=cur then
            cur=nv; vl.Text=tostring(cur)
            fill.Size=UDim2.new(r,0,1,0); knob.Position=UDim2.new(r,0,0.5,0)
            if fn then fn(cur) end
        end
    end)
end

local function bigBtn(text,col,col2,order)
    local btn=Instance.new("TextButton",scroll)
    btn.Size=UDim2.new(1,0,0,36); btn.BackgroundColor3=col
    btn.BorderSizePixel=0; btn.Text=text; btn.TextColor3=Color3.fromRGB(255,255,255)
    btn.TextSize=12; btn.Font=Enum.Font.GothamBold; btn.LayoutOrder=order
    Instance.new("UICorner",btn).CornerRadius=CS
    local st=Instance.new("UIStroke",btn); st.Color=col2; st.Thickness=1.5
    btn.MouseEnter:Connect(function() TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=col2}):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=col}):Play() end)
    return btn
end

local function statusBar(order)
    local bar=Instance.new("Frame",scroll)
    bar.Size=UDim2.new(1,0,0,46); bar.BackgroundColor3=C.ROW
    bar.BorderSizePixel=0; bar.LayoutOrder=order
    Instance.new("UICorner",bar).CornerRadius=CS
    local lbl=Instance.new("TextLabel",bar)
    lbl.Size=UDim2.new(1,-12,1,-8); lbl.Position=UDim2.new(0,6,0,4)
    lbl.BackgroundTransparency=1; lbl.Text="..."
    lbl.TextColor3=C.TEXT; lbl.TextSize=9; lbl.Font=Enum.Font.Gotham
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.TextYAlignment=Enum.TextYAlignment.Top
    lbl.TextWrapped=true; return lbl
end

-- ── BUILD UI ─────────────────────────────────────────────
local lo=0

lo=lo+1; sec("── STATUS ─────────────────────────",lo)
lo=lo+1; local statusLbl=statusBar(lo)
lo=lo+1; div(lo)

lo=lo+1; sec("── COMBAT ─────────────────────────",lo)

lo=lo+1
local b1,s1=tog("Auto Infiltrate","Spray virus ke zombie terdekat (CD 15s)",lo)
s1(false); b1.MouseButton1Click:Connect(function()
    STATE.autoInfiltrate=not STATE.autoInfiltrate; s1(STATE.autoInfiltrate) end)

lo=lo+1
local b2,s2=tog("Auto Shoot","Headshot — prioritas zombie ber-virus",lo)
s2(false); b2.MouseButton1Click:Connect(function()
    STATE.autoShoot=not STATE.autoShoot
    if STATE.autoShoot then shotCounter=1 end; s2(STATE.autoShoot) end)

lo=lo+1
local b3,s3=tog("Auto Update Targets","Update list target server",lo)
s3(false); b3.MouseButton1Click:Connect(function()
    STATE.autoUpdateTarget=not STATE.autoUpdateTarget; s3(STATE.autoUpdateTarget) end)

lo=lo+1; div(lo)
lo=lo+1; sec("── HEAD EXPANDER ───────────────────",lo)

lo=lo+1
local b4,s4=tog("Head Expander","Perbesar hitbox kepala zombie",lo)
s4(false); b4.MouseButton1Click:Connect(function()
    STATE.headExpander=not STATE.headExpander
    if not STATE.headExpander then restoreAllHeads() end; s4(STATE.headExpander) end)

lo=lo+1; sld("Head Size (1-20)",1,20,CFG.HEAD_EXP_SIZE,lo,function(v)
    CFG.HEAD_EXP_SIZE=v; updateHeadSizes() end)

lo=lo+1; div(lo)
lo=lo+1; sec("── ULTIMATE ────────────────────────",lo)

lo=lo+1
local overBtn=bigBtn("⚡  SYSTEM OVERRIDE",C.OVR,C.OVR2,lo)
overBtn.MouseButton1Click:Connect(function()
    local remote=getSystemOverrideRemote()
    if not remote then statusLbl.Text="⚠ Override tidak ditemukan!"; return end
    pcall(function() remote:FireServer() end)
    TweenService:Create(overBtn,TweenInfo.new(0.08),{BackgroundColor3=Color3.fromRGB(255,100,100)}):Play()
    task.delay(0.2,function()
        TweenService:Create(overBtn,TweenInfo.new(0.2),{BackgroundColor3=C.OVR}):Play()
    end)
    statusLbl.Text="✓ System Override!"
end)

lo=lo+1; div(lo)
lo=lo+1; sec("── SETTINGS ────────────────────────",lo)

lo=lo+1; sld("Max Range",50,800,CFG.MAX_RANGE,lo,function(v) CFG.MAX_RANGE=v end)
lo=lo+1; sld("Infiltrate Range",10,200,CFG.INFILTRATE_RANGE,lo,function(v) CFG.INFILTRATE_RANGE=v end)
lo=lo+1; sld("Shoot Rate (ms)",30,300,math.floor(CFG.SHOOT_RATE*1000),lo,function(v) CFG.SHOOT_RATE=v/1000 end)

-- ── STATUS UPDATER ────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(0.5)
        local chars=workspace:FindFirstChild("Characters")
        local nearbyZ,virusZ=0,0
        local char=lp.Character
        local hrp=char and char:FindFirstChild("HumanoidRootPart")
        if chars then
            for _,z in pairs(chars:GetChildren()) do
                if isEnemy(z) then
                    if hrp then
                        local r=getZombieRoot(z)
                        if r and (r.Position-hrp.Position).Magnitude<=CFG.MAX_RANGE then
                            nearbyZ=nearbyZ+1
                        end
                    end
                    if hasVirus(z) then virusZ=virusZ+1 end
                end
            end
        end
        local w,_=getWeaponShootRemote()
        local wName=w and w.Name or "—"
        local cdLeft=INFILTRATE_CD-(tick()-lastInfiltrateUse)
        local cdStr=cdLeft<=0 and "READY" or string.format("%.1fs",cdLeft)
        local soOk=getSystemOverrideRemote()~=nil and "✓" or "✗"
        statusLbl.Text=string.format(
            "Range:%d  Z:%d  Virus:%d\nWeapon: %s\nInfiltrate:%s  Override:%s",
            CFG.MAX_RANGE,nearbyZ,virusZ,wName,cdStr,soOk
        )
    end
end)

print("[Class Hacker] Ready | lsxast")
