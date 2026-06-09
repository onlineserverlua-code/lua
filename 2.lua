local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}

BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

local ENetRole = import("ENetRole")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
local WH_ESP_Active = false

local function WH_ApplyChamsColor(localPlayer, enemy, pc)
    if not WH_ESP_Active then return end
    if not slua.isValid(enemy) then return end
    
    local meshes = {}
    pcall(function()
        if slua.isValid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
        local SkelClass = import("SkeletalMeshComponent")
        if SkelClass then
            local childs = enemy:GetComponentsByClass(SkelClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for c = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(c-1) or childs[c]
                    if slua.isValid(comp) and comp ~= enemy.Mesh then table.insert(meshes, comp) end
                end
            end
        end
    end)
    
    pcall(function()
        for _, comp in ipairs(meshes) do
            if slua.isValid(comp) then
                local s, matInterface = pcall(function() return comp:GetMaterial(0) end)
                if s and slua.isValid(matInterface) then
                    local s2, baseMat = pcall(function() return matInterface:GetBaseMaterial() end)
                    if s2 and slua.isValid(baseMat) then
                        if baseMat.bDisableDepthTest ~= true then baseMat.bDisableDepthTest = true end
                        if baseMat.BlendMode ~= 2 then baseMat.BlendMode = 2 end
                    end
                end
                comp.UseScopeDistanceCulling = false 
                comp.PrimitiveShadingStrategy = 1
                comp.ShadingRate = 6
            end
        end

        local isVisible = false
        if slua.isValid(pc) and slua.isValid(enemy) and type(pc.LineOfSightTo) == "function" then 
            pcall(function() isVisible = pc:LineOfSightTo(enemy) end) 
        end
        
        -- Colors: Hidden = Purple/Red, Visible = Cyan
        local hiddenColor  = { R = 25.0, G = 0.0,  B = 25.0, A = 1.0 }
        local visibleColor = { R = 0.0,  G = 25.0, B = 25.0, A = 1.0 }
        local finalColor = isVisible and visibleColor or hiddenColor
        local scale = { R = 3.0, G = 3.0, B = 0.0, A = 0.0 }
        
        enemy.WH_MIDs = enemy.WH_MIDs or {}
        local stateChanged = (enemy.WH_LastColorR ~= finalColor.R)
        
        for _, comp in ipairs(meshes) do
            if slua.isValid(comp) then
                local compKey = tostring(comp)
                enemy.WH_MIDs[compKey] = enemy.WH_MIDs[compKey] or {}
                for i = 0, 10 do 
                    local s, matInterface = pcall(function() return comp:GetMaterial(i) end)
                    if not s or not slua.isValid(matInterface) then break end
                    local isNewMID = false
                    local needCacheUpdate = false
                    local currentCached = enemy.WH_MIDs[compKey][i]
                    if not slua.isValid(currentCached) then
                        local s2, newMid = pcall(function() return comp:CreateAndSetMaterialInstanceDynamic(i) end)
                        if s2 and slua.isValid(newMid) then 
                            enemy.WH_MIDs[compKey][i] = newMid
                            currentCached = newMid
                            isNewMID = true
                            needCacheUpdate = true 
                        end
                    else
                        if matInterface ~= currentCached then 
                            pcall(function() comp:SetMaterial(i, currentCached) end)
                            needCacheUpdate = true 
                        end
                    end
                    if slua.isValid(currentCached) and (stateChanged or isNewMID or needCacheUpdate) then
                        pcall(function()
                            local colorParams = {"颜色", "Extra Light Color", "Para_Color", "Para_ColorTint", 
                                                "Para_Color_1", "Tint", "Color", "BaseColor", "BodyColor", 
                                                "MainColor", "DiffuseColor", "EmissiveColor"}
                            for _, param in ipairs(colorParams) do
                                currentCached:SetVectorParameterValue(param, finalColor)
                            end
                            currentCached:SetVectorParameterValue("ParaScaleOffset", scale)
                        end)
                    end
                end
            end
        end
        if stateChanged then enemy.WH_LastColorR = finalColor.R end
    end)
end

local function WH_RunChams()
    pcall(function()
        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) then return end
        
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not slua.isValid(pc) then return end
        
        local myTeamId = localPlayer.TeamID or 0
        local allPawns = Game:GetAllPlayerPawns() or {}
        
        for _, target in pairs(allPawns) do
            if slua.isValid(target) and target ~= localPlayer and target.TeamID ~= myTeamId then
                local isAlive = false
                pcall(function() isAlive = target:IsAlive() end)
                if isAlive then
                    WH_ApplyChamsColor(localPlayer, target, pc)
                end
            end
        end
    end)
end

local function WH_StartChams()
    if WH_ESP_Active then return end
    WH_ESP_Active = true
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) and pc.AddGameTimer then
            pc:AddGameTimer(0.08, true, WH_RunChams)
        end
    end)
end

local function ApplyAimbotToWeapon(weapon)
    if not slua.isValid(weapon) then return false end
    
    local entity = weapon.ShootWeaponEntityComp
    if not slua.isValid(entity) then
        entity = weapon.STExtraShootWeaponComponent
    end
    if not slua.isValid(entity) then return false end
    
    pcall(function()
        -- No Recoil
        if entity.GameDeviationAccuracy then entity.GameDeviationAccuracy = 0.0 end
        if entity.GameDeviationFactor then entity.GameDeviationFactor = 0.0 end
        if entity.RecoilKickADS then entity.RecoilKickADS = 0.1 end
        
        -- Auto Aim Config
        if entity.AutoAimingConfig then
            for _, range in ipairs({"OuterRange", "InnerRange"}) do
                local cfg = entity.AutoAimingConfig[range]
                if cfg then
                    cfg.Speed = 3.5
                    cfg.RangeRate = 3.5
                    cfg.SpeedRate = 3.5
                    cfg.RangeRateSight = 3.5
                    cfg.SpeedRateSight = 3.5
                    cfg.CrouchRate = 3.5
                    cfg.ProneRate = 3.5
                    cfg.DyingRate = 0
                end
            end
        end
    end)
    
    return true
end

local function InitAimbot(self)
    if self._aimbotApplied then return end
    
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not slua.isValid(pc) then return end
        
        local pawn = pc:GetPlayerCharacterSafety()
        if not slua.isValid(pawn) then return end
        
        -- Apply to current weapon
        local wm = pawn.WeaponManagerComponent
        if slua.isValid(wm) then
            local weapon = wm.CurrentWeaponReplicated
            ApplyAimbotToWeapon(weapon)
            
            -- Weapon switch par bhi apply hoga
            local oldOnRep = wm.OnRep_CurrentWeaponReplicated
            wm.OnRep_CurrentWeaponReplicated = function(...)
                if oldOnRep then oldOnRep(...) end
                local newWeapon = wm.CurrentWeaponReplicated
                ApplyAimbotToWeapon(newWeapon)
            end
        end
        
        self._aimbotApplied = true
        print("[Aimbot] Applied successfully")
    end)
end

local function EmptyFunction() end

function _InitBypass()
    if _G._BypassDone then return end
    _G._BypassDone = true
    
    pcall(function()
        local gc = _G.GameplayCallbacks or _G.GC
        if gc then
            gc.SendTssSdkAntiDataToLobby = EmptyFunction
            gc.SendDSErrorLogToLobby = EmptyFunction
            gc.SendDSHawkEyePatrolLogToLobby = EmptyFunction
            gc.SendSecTLog = EmptyFunction
            gc.SendDataMiningTLog = EmptyFunction
            gc.SendActivityTLog = EmptyFunction
        end
        
        local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subMgr then
            local hawkEye = subMgr:Get("DSHawkEyePatrolSubsystem")
            if hawkEye then hawkEye.MarkSuspiciousPlayer = EmptyFunction end
        end
        
        local clientReport = require("GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem")
        if clientReport then
            clientReport.OnInit = EmptyFunction
            clientReport._OnPlayerKilledOtherPlayer = EmptyFunction
            clientReport._RecordFatalDamager = EmptyFunction
            clientReport._OnBattleResult = EmptyFunction
        end
        
        local dsReport = require("GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem")
        if dsReport then
            dsReport.OnInit = EmptyFunction
            dsReport._OnCharacterDied = EmptyFunction
            dsReport._RecordFatalDamager = EmptyFunction
        end
        
        pcall(function()
            local higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if higgs then
                local funcs = {"ControlMHActive","Tick","OnTick","ReceiveTick","MHActiveLogic","TriggerAvatarCheck","StartAvatarCheck","ReportItemID","OnReportItemID","ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert","StaticShowSecurityAlertInDev"}
                for _,f in ipairs(funcs) do if higgs[f] then higgs[f]=EmptyFunction end end
                higgs.GetNetAvatarItemIDs = function() return {} end
                higgs.GetCurWeaponSkinID = function() return 0 end
            end
            if _G.AvatarCheckCallback then
                _G.AvatarCheckCallback.StartAvatarCheck = EmptyFunction
                _G.AvatarCheckCallback.OnReportItemID = EmptyFunction
                _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(pc)
                    if slua.isValid(pc) and pc.HiggsBosonComponent then
                        pcall(function() pc.HiggsBosonComponent:ControlMHActive(0); pc.HiggsBosonComponent.bMHActive=false end)
                    end
                end
            end
        end)
        
        if gc then
            local orig = gc.OnDSPlayerStateChanged
            gc.OnDSPlayerStateChanged = function(self, sn, ...)
                local blocked = {cheatdetected=true, connectionlost=true, connectiontimeout=true, netdrivererror=true}
                if blocked[tostring(sn):lower()] then return end
                if orig then pcall(orig, self, sn, ...) end
            end
            gc.OnPlayerRPCValidateFailed = EmptyFunction
            gc.OnPlayerActorChannelError = EmptyFunction
            gc.OnPlayerSpectateException = EmptyFunction
            gc.OnShutdownAfterError = EmptyFunction
            gc.OnPlayerNetConnectionClosed = EmptyFunction
        end
    end)
end

_InitBypass()

local EXPIRY_DATE = "2026-06-30"

function BRPlayerCharacterBase:ctor()
self.ActiveForceMark = nil
self.LastMarkUpdate = 0
self._chamsStarted = false
self._aimbotApplied = false  -- Aimbot ke liye
self._aimbotRetryTimer = nil  -- Retry timer ke liye
end

function BRPlayerCharacterBase:ReceiveTick(deltaTime)
    _UpdateMapMark(self)
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddGameTimer(1.0, false, function()
        if not slua.isValid(self.Object) then return end
        WH_StartChams()
    end)
  self:AddGameTimer(1.0, false, function()
        if not slua.isValid(self.Object) then return end
        InitAimbot(self)
    end)
  self:AddGameTimer(1.0, false, function()
        if not slua.isValid(self.Object) then return end
        _ShowWelcomePopup()
    end)
    
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  
  if Client then
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if self.ActiveForceMark then
        if InGameMarkTools then InGameMarkTools.HideMapMark(self.ActiveForceMark) end
        self.ActiveForceMark = nil
    end
  if self._aimbotRetryTimer then
        self:RemoveGameTimer(self._aimbotRetryTimer)
        self._aimbotRetryTimer = nil
    end
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle) end
function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle) end
function BRPlayerCharacterBase:ClearAttachToVehicleTimer() end

function _UpdateMapMark(self)
    if not Client then return end
    if not slua.isValid(self.Object) then return end
    
    local localPlayer = GameplayData.GetPlayerCharacter()
    if not slua.isValid(localPlayer) then return end
    
    if localPlayer.TeamID ~= self.TeamID then
        if self.Object.IsAlive and self.Object:IsAlive() then
            local t = os.clock()
            if t - self.LastMarkUpdate > 0.7 then
                self.LastMarkUpdate = t
                local headPos = self:GetHeadLocation(false)
                if not headPos then headPos = self:GetFuzzyPosition(FVector(0,0,0)) end
                if headPos then
                    if self.ActiveForceMark and InGameMarkTools then
                        InGameMarkTools.HideMapMark(self.ActiveForceMark)
                    end
                    self.ActiveForceMark = InGameMarkTools.ClientAddMapMark(1003, headPos, 0, "", 4, nil)
                end
            end
        end
    else
        if self.ActiveForceMark then
            if InGameMarkTools then InGameMarkTools.HideMapMark(self.ActiveForceMark) end
            self.ActiveForceMark = nil
        end
    end
end

local function IsExpired()
    local cd = os.date("*t")
    local ep = {}
    EXPIRY_DATE:gsub("(%d+)", function(n) table.insert(ep, tonumber(n)) end)
    local ed = {year=ep[1], month=ep[2], day=ep[3]}
    if cd.year>ed.year or (cd.year==ed.year and cd.month>ed.month) or (cd.year==ed.year and cd.month==ed.month and cd.day>ed.day) then
        _G.MOD_EXPIRED=true; return true
    end
    _G.MOD_EXPIRED=false; return false
end

local function GetDaysRemaining()
    local cd = os.date("*t")
    local ep = {}
    EXPIRY_DATE:gsub("(%d+)", function(n) table.insert(ep, tonumber(n)) end)
    local ed = {year=ep[1], month=ep[2], day=ep[3], hour=23, min=59, sec=59}
    return math.ceil((os.time(ed) - os.time(cd)) / 86400)
end

local function ShowExpiredPopup()
    pcall(function()
        local m = require("client.slua.logic.common.logic_common_msg_box")
        local w = require("client.slua.logic.url.logic_webview_sdk")
        m.Show(4, "MOD EXPIRED", "YOUR MOD HAS EXPIRED!\n\nContact: @ROCKYBHAI711l\nAll mod features are disabled", function()
            if w then w.OpenURL(" https://t.me/+lMSm5CMlGvEzZDY9") end
        end)
    end)
end

local function ShowDaysRemaining()
    if _G.DaysRemainingShown then return end
    _G.DaysRemainingShown = true
    pcall(function()
        local m = require("client.slua.logic.common.logic_common_msg_box")
        local d = GetDaysRemaining()
        m.Show(4, "MODDED BY : @ROCKYBHAI711", string.format("MOD ACTIVE - %d DAYS REMAINING\nEXPIRES: %s\nContact @ROCKYBHAI711", d, EXPIRY_DATE), function()
            local w = require("client.slua.logic.url.logic_webview_sdk")
            if w then w.OpenURL("https://t.me/+lMSm5CMlGvEzZDY9") end
        end)
    end)
end

function _ShowWelcomePopup()
    if _G.WelcomeShown then return end
    _G.WelcomeShown = true
    if IsExpired() then ShowExpiredPopup(); return end
    pcall(function()
        ShowDaysRemaining()
        local m = require("client.slua.logic.common.logic_common_msg_box")
        local w = require("client.slua.logic.url.logic_webview_sdk")
        m.Show(4, "NOTIFICATION FROM KINGXOP", "WELCOME TO VIP LUA \nPLAY CAREFULLY AND ENJOY\nADMIN: @ROCKYBHAI711l\nJOIN TELEGRAM FOR MORE UPDATES", function()
            if w then w.OpenURL("https://t.me/ROCKYBHAI711") end
            local u = require("GameLua.Util.UIUtils")
            if u and u.ShowNotice then u.ShowNotice("[TELEGRAM @ROCKYBHAI711] ACTIVE") end
        end)
    end)
end

local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)

return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" }
}, "BRPlayerCharacterBase")