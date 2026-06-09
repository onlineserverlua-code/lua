-- @rjbayue 
-- @rjbayue

local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
    self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleOnAttachedToVehicle, self)
    self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleOnDetachedFromVehicle, self)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle)
  if not slua.isValid(uVehicle) then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:HandleOnAttachedToVehicle", Game:GetObjName(uVehicle)))
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
    self.nUpdatePlayerAttachToVehicleTimer = self:AddGameTimer(5, true, function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:UpdatePlayerAttachToVehicle(uVehicle)
      end
    end)
    self.nFixMeshContainerTimer = self:AddGameTimer(3, true, function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:FixMeshContainerOffsetIfNeeded(uVehicle)
      end
    end)
  end
end

function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle)
  if not slua.isValid(uLastVehicle) then
    return
  end
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnDetachedFromVehicle", uLastVehicle)
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:UpdatePlayerAttachToVehicle(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not (slua.isValid(self.CapsuleComponent) and slua.isValid(self.Mesh)) or not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  if not self.nUpdatePlayerAttachToVehicleCount then
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  local ESTEPoseState = import("ESTEPoseState")
  local bStand = self.PoseState == ESTEPoseState.Stand
  local uActorRelativeLocation = self.CapsuleComponent:GetRelativeTransform():GetLocation()
  local uMeshRelativeLocation = self.Mesh:GetRelativeTransform():GetLocation()
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  local nCapsuleRadius = self.CapsuleComponent:GetScaledCapsuleRadius()
  local nCapsuleHalfHeight = self.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local nExpectedCapsuleRadius = self.StandRadius
  local nExpectedCapsuleHalfHeight = self.StandHalfHeight
  local uMeshExpectedRL = FVector(0, 0, 0)
  local uActorExpectedRL = FVector(0, 0, self.StandHalfHeight)
  local nTolerance = 1.0
  local bCapsuleRLCorrect = uActorRelativeLocation:Equals(uActorExpectedRL, nTolerance)
  local bMeshRLCorrect = uMeshRelativeLocation:Equals(uMeshExpectedRL, nTolerance)
  local bMeshContainerRLCorrect = nTolerance > math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ)
  local bCapsuleRadiusCorrect = nTolerance > math.abs(nCapsuleRadius - nExpectedCapsuleRadius)
  local bCapsuleHalfHeightCorrect = nTolerance > math.abs(nCapsuleHalfHeight - nExpectedCapsuleHalfHeight)
  local bAllCorrect = bStand and bCapsuleRLCorrect and bMeshRLCorrect and bMeshContainerRLCorrect and bCapsuleRadiusCorrect and bCapsuleHalfHeightCorrect
  if not bAllCorrect then
    self.nUpdatePlayerAttachToVehicleCount = self.nUpdatePlayerAttachToVehicleCount + 1
  else
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:UpdatePlayerAttachToVehicle PlayerKey:%s. bAllCorrect=%s Check Result:%d %d %d %d %d %d, Count:%d", tostring(self.PlayerKey), tostring(bAllCorrect), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, self.nUpdatePlayerAttachToVehicleCount))
  if self.nUpdatePlayerAttachToVehicleCount >= 3 and not bAllCorrect then
    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
    local uPlayerController = GameplayData.GetPlayerController()
    if uPlayerController.ReportCrashKitFeature and uPlayerController.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException then
      local sReportInfo = string.format("VehicleShapeType:%s PlayerKey:%s. Check Result:%d %d %d %d %d %d. Capsule.RelativeLoc:%s Capsule.Radius:%s Capsule.HalfHeight:%s Mesh.RelativeLoc:%s MeshContainer.RelativeLocZ:%s", tostring(uVehicle.VehicleShapeType), tostring(self.PlayerKey), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, uActorRelativeLocation:ToString(), tostring(nCapsuleRadius), tostring(nCapsuleHalfHeight), uMeshRelativeLocation:ToString(), tostring(uMeshContainerRelativeLocationZ))
      uPlayerController.ReportCrashKitFeature:ReportCharacterAttachedOnVehicleException(sReportInfo)
    end
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  local nTolerance = 1.0
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  if nTolerance <= math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ) then
    print(bWriteLog and string.format("BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded PlayerKey:%s. SetMeshContainerOffsetZ from:%s to:%s", tostring(self.PlayerKey), tostring(uMeshContainerRelativeLocationZ), tostring(uMeshContainerExpectedZ)))
    self:SetMeshContainerOffsetZ(uMeshContainerExpectedZ)
  end
end

function BRPlayerCharacterBase:ClearAttachToVehicleTimer()
  if self.nUpdatePlayerAttachToVehicleTimer then
    self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
    self.nUpdatePlayerAttachToVehicleTimer = nil
  end
  if self.nFixMeshContainerTimer then
    self:RemoveGameTimer(self.nFixMeshContainerTimer)
    self.nFixMeshContainerTimer = nil
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  local EPawnState = import("EPawnState")
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfig then
    self.STCharacterMovement:SetDynamicSimpleQueryConfig(false)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local EGameModeType = import("EGameModeType")
    local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  local EParachuteState = import("EParachuteState")
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local GameplayData = require("GameLua.GameCore.Data.GameplayData")
  local uGameState = GameplayData:GetGameState()
  local STExtraGameStateBase = import("STExtraGameStateBase")
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    local EGameModeType = import("EGameModeType")
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  local EMovementMode = import("EMovementMode")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local UKismetSystemLibrary = import("KismetSystemLibrary")
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.UInt32,
    UEnums.EPropertyClass.UInt32
  }
}

function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(Type, Param)
  print(bWriteLog and string.format("BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment Type = %d, Param = %s", Type, Param))
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      local EStateType = import("EStateType")
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        local ESTEPoseState = import("ESTEPoseState")
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  local loadLater = function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end


-- MOD CODE --

local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
    self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleOnAttachedToVehicle, self)
    self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleOnDetachedFromVehicle, self)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle)
  if not slua.isValid(uVehicle) then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:HandleOnAttachedToVehicle", Game:GetObjName(uVehicle)))
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
    self.nUpdatePlayerAttachToVehicleTimer = self:AddGameTimer(5, true, function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:UpdatePlayerAttachToVehicle(uVehicle)
      end
    end)
    self.nFixMeshContainerTimer = self:AddGameTimer(3, true, function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:FixMeshContainerOffsetIfNeeded(uVehicle)
      end
    end)
  end
end

function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle)
  if not slua.isValid(uLastVehicle) then
    return
  end
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnDetachedFromVehicle", uLastVehicle)
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:UpdatePlayerAttachToVehicle(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not (slua.isValid(self.CapsuleComponent) and slua.isValid(self.Mesh)) or not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  if not self.nUpdatePlayerAttachToVehicleCount then
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  local ESTEPoseState = import("ESTEPoseState")
  local bStand = self.PoseState == ESTEPoseState.Stand
  local uActorRelativeLocation = self.CapsuleComponent:GetRelativeTransform():GetLocation()
  local uMeshRelativeLocation = self.Mesh:GetRelativeTransform():GetLocation()
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  local nCapsuleRadius = self.CapsuleComponent:GetScaledCapsuleRadius()
  local nCapsuleHalfHeight = self.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local nExpectedCapsuleRadius = self.StandRadius
  local nExpectedCapsuleHalfHeight = self.StandHalfHeight
  local uMeshExpectedRL = FVector(0, 0, 0)
  local uActorExpectedRL = FVector(0, 0, self.StandHalfHeight)
  local nTolerance = 1.0
  local bCapsuleRLCorrect = uActorRelativeLocation:Equals(uActorExpectedRL, nTolerance)
  local bMeshRLCorrect = uMeshRelativeLocation:Equals(uMeshExpectedRL, nTolerance)
  local bMeshContainerRLCorrect = nTolerance > math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ)
  local bCapsuleRadiusCorrect = nTolerance > math.abs(nCapsuleRadius - nExpectedCapsuleRadius)
  local bCapsuleHalfHeightCorrect = nTolerance > math.abs(nCapsuleHalfHeight - nExpectedCapsuleHalfHeight)
  local bAllCorrect = bStand and bCapsuleRLCorrect and bMeshRLCorrect and bMeshContainerRLCorrect and bCapsuleRadiusCorrect and bCapsuleHalfHeightCorrect
  if not bAllCorrect then
    self.nUpdatePlayerAttachToVehicleCount = self.nUpdatePlayerAttachToVehicleCount + 1
  else
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:UpdatePlayerAttachToVehicle PlayerKey:%s. bAllCorrect=%s Check Result:%d %d %d %d %d %d, Count:%d", tostring(self.PlayerKey), tostring(bAllCorrect), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, self.nUpdatePlayerAttachToVehicleCount))
  if self.nUpdatePlayerAttachToVehicleCount >= 3 and not bAllCorrect then
    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
    local uPlayerController = GameplayData.GetPlayerController()
    if uPlayerController.ReportCrashKitFeature and uPlayerController.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException then
      local sReportInfo = string.format("VehicleShapeType:%s PlayerKey:%s. Check Result:%d %d %d %d %d %d. Capsule.RelativeLoc:%s Capsule.Radius:%s Capsule.HalfHeight:%s Mesh.RelativeLoc:%s MeshContainer.RelativeLocZ:%s", tostring(uVehicle.VehicleShapeType), tostring(self.PlayerKey), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, uActorRelativeLocation:ToString(), tostring(nCapsuleRadius), tostring(nCapsuleHalfHeight), uMeshRelativeLocation:ToString(), tostring(uMeshContainerRelativeLocationZ))
      uPlayerController.ReportCrashKitFeature:ReportCharacterAttachedOnVehicleException(sReportInfo)
    end
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  local nTolerance = 1.0
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  if nTolerance <= math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ) then
    print(bWriteLog and string.format("BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded PlayerKey:%s. SetMeshContainerOffsetZ from:%s to:%s", tostring(self.PlayerKey), tostring(uMeshContainerRelativeLocationZ), tostring(uMeshContainerExpectedZ)))
    self:SetMeshContainerOffsetZ(uMeshContainerExpectedZ)
  end
end

function BRPlayerCharacterBase:ClearAttachToVehicleTimer()
  if self.nUpdatePlayerAttachToVehicleTimer then
    self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
    self.nUpdatePlayerAttachToVehicleTimer = nil
  end
  if self.nFixMeshContainerTimer then
    self:RemoveGameTimer(self.nFixMeshContainerTimer)
    self.nFixMeshContainerTimer = nil
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  local EPawnState = import("EPawnState")
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfig then
    self.STCharacterMovement:SetDynamicSimpleQueryConfig(false)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local EGameModeType = import("EGameModeType")
    local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  local EParachuteState = import("EParachuteState")
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local GameplayData = require("GameLua.GameCore.Data.GameplayData")
  local uGameState = GameplayData:GetGameState()
  local STExtraGameStateBase = import("STExtraGameStateBase")
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    local EGameModeType = import("EGameModeType")
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  local EMovementMode = import("EMovementMode")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local UKismetSystemLibrary = import("KismetSystemLibrary")
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.UInt32,
    UEnums.EPropertyClass.UInt32
  }
}

function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(Type, Param)
  print(bWriteLog and string.format("BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment Type = %d, Param = %s", Type, Param))
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      local EStateType = import("EStateType")
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        local ESTEPoseState = import("ESTEPoseState")
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  local loadLater = function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end


-- MOD CODE --

-- Per-match guard: allow re-init when the player controller changes (new match)
do
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if _G._AKMODVIP_LOADED and _G._AKMODVIP_PC == pc then return end
    _G._AKMODVIP_LOADED = true
    _G._AKMODVIP_PC = pc
end

local lIIl1Il1IIII1 = {
    ServerRPC = {},
    ClientRPC = {},
    MulticastRPC = {}
}

lIIl1Il1IIII1.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
lIIl1Il1IIII1.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
lIIl1Il1IIII1.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
lIIl1Il1IIII1.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
lIIl1Il1IIII1.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }
lIIl1Il1IIII1.ClientRPC.ClientRPC_TriggerHighlightMoment = { Reliable = true, Params = { UEnums.EPropertyClass.UInt32, UEnums.EPropertyClass.UInt32 } }

local lllIII11Il111 = import("ENetRole")
local lI1lIlI1I1II1 = import("EPawnState")
local lII11lIllllII = require("GameLua.GameCore.Data.GameplayData")
local llll1ll1IIlll = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local lIllllll11IIl = import("KismetMathLibrary")
local lll1I1l1l11I1 = import("GameplayStatics")
local lIlllIIll1I11 = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")

local l11l1Ill1Ill1 = os.time(os.date("!*t"))
local l1Il11lIlIlI1 = os.time({ year = 2028, month = 5, day = 15, hour = 6, min = 45, sec = 0 })





if l11l1Ill1Ill1 <= l1Il11lIlIlI1 then
    local lII1l1I11I1I1 = package.loaded["client.slua.logic.setting.logic_setting_graphics"] or require("client.slua.logic.setting.logic_setting_graphics")
    local lI11III1I1II1 = package.loaded["client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS"] or require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
    local l1Il11lIllI11 = package.loaded["client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT"] or require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
    local lllllIIl1I1lI = package.loaded["client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB"] or require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")

    if lII1l1I11I1I1 then
        local lIlIIl1I1II1I = lII1l1I11I1I1.SetFPS
        function lII1l1I11I1I1.SetFPS(gameInstance, FPSLevel)
            if FPSLevel == 8 and lllllIIl1I1lI then
                local lIlIlIIl1Il1l = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneSwitch)
                if not lIlIlIIl1Il1l then 
                    lllllIIl1I1lI:UpdateUIData(lllllIIl1I1lI.FPSFineTuneSwitch, true) 
                end
            end
            if lIlIIl1I1II1I then 
                lIlIIl1I1II1I(gameInstance, FPSLevel) 
            end
            if FPSLevel == 8 and lllllIIl1I1lI then
                lllllIIl1I1lI:UpdateUIData(lllllIIl1I1lI.FPSFineTuneNum, 165)
                gameInstance:ExecuteCMD("t.MaxFPS", "165")
                gameInstance:ExecuteCMD("r.FrameRateLimit", "165")
            end
        end
    end

    if lI11III1I1II1 and lI11III1I1II1.__inner_impl then
        local ll1IlIlllI1ll = lI11III1I1II1.__inner_impl
        function ll1IlIlllI1ll:GetMaxFPSLevel() return 8, 8 end
        function ll1IlIlllI1ll:CanChangeQualityAndFPSPreCheck() return true end
        function ll1IlIlllI1ll:InitRealSupportFPS()
            local lI1lIllll11I1 = {}
            for i = 1, 8 do lI1lIllll11I1[i] = {true, true} end
            if lllllIIl1I1lI then lllllIIl1I1lI:UpdateUIData(lllllIIl1I1lI.RealSupportFPS, lI1lIllll11I1, false) end
            return lI1lIllll11I1
        end
        function ll1IlIlllI1ll:SetFPSAndQualityEnable(bEnable)
            if self.UIRoot and self.UIRoot.Image_Mask then self:SetWidgetVisible(self.UIRoot.Image_Mask, false) end
        end
        function ll1IlIlllI1ll:UpdateSelectedFPSState(selectedLevel)
            local lIlll1I1lIIll = { [2]="NodeFps20", [3]="NodeFps25", [4]="NodeFps30", [5]="NodeFps40", [6]="NodeFps60", [7]="NodeFps90", [8]="NodeFps120" }
            if not self.UIRoot then return end
            for level, name in pairs(lIlll1I1lIIll) do
                if self.UIRoot[name] then
                    self:WidgetSelfHit(self.UIRoot[name])
                    self.UIRoot[name]:SetIsEnabled(true)
                    local lII1II11lIIl1 = self.UIRoot["WidgetSwitcher_" .. level]
                    if lII1II11lIIl1 then lII1II11lIIl1:SetActiveWidgetIndex(level == selectedLevel and 0 or 1) end
                end
            end
        end
        local l11I1ll1lI11l = ll1IlIlllI1ll.UpdateUI
        function ll1IlIlllI1ll:UpdateUI()
            if l11I1ll1lI11l then pcall(l11I1ll1lI11l, self) end
            self:SelfHitTestInvisible()
            self:InitRealSupportFPS()
            self:SetFPSAndQualityEnable(true)
            local ll1IIIIl1lllI = 8
            if lllllIIl1I1lI then
                if lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.CustomTab) == 2 then
                    ll1IIIIl1lllI = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.LobbyFPS) or 8
                else
                    ll1IIIIl1lllI = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.SelectedFPS) or 8
                end
            end
            self:UpdateSelectedFPSState(ll1IIIIl1lllI)
        end
        function ll1IlIlllI1ll:DoClickFPS(FPSLevel)
            if slua.isValid(self.UIRoot) then
                if lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.CustomTab) == 2 then
                    lllllIIl1I1lI:UpdateUIData(lllllIIl1I1lI.LobbyFPS, FPSLevel)
                else
                    lllllIIl1I1lI:UpdateSelectedFPS(FPSLevel)
                end
                self:UpdateSelectedFPSState(FPSLevel)
                if self:GetParentUI() then 
                    self:GetParentUI():SaveQualityAndFPS()
                    self:GetParentUI():SetDirty(true) 
                end
            end
        end
    end

    if l1Il11lIllI11 and l1Il11lIllI11.__inner_impl then
        local lI111IlI111l1 = l1Il11lIllI11.__inner_impl
        local lIl1l1Ill11Il, l1lI11I1ll1Il = 90, 5
        local function lI1IIl1lllIII(val, min, max) return val < min and min or (val > max and max or val) end
        function lI111IlI111l1:ShowOrHide() 
            self:SelfHitTestInvisible() 
            if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end 
        end
        function lI111IlI111l1:InitFPSFTSwitch()
            local sw = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneSwitch)
            if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(sw, true) end
            if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, sw) end
            if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
            if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
        end
        function lI111IlI111l1:InitFPSFTValue165()
            local lIl1IIlI1ll1l = self.UIRoot
            local sw = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneSwitch)
            local lIIIlII1IlI1l = sw and lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneNum) or 165
            lIl1IIlI1ll1l.Slider_screen3:SetLocked(not sw)
            lIl1IIlI1ll1l.ProgressBar_screen3:SetFillColorAndOpacity(sw and FLinearColor(1,1,1,1) or FLinearColor(1,0.625,0.6,1))
            local l1I1Il11Ill1l = (lIIIlII1IlI1l - lIl1l1Ill11Il) / (165 - lIl1l1Ill11Il)
            lIl1IIlI1ll1l.Veihclescreen3:SetText(LocUtil.LocalizeResFormat(10567, lIIIlII1IlI1l))
            lIl1IIlI1ll1l.Slider_screen3:SetValue(l1I1Il11Ill1l)
            lIl1IIlI1ll1l.ProgressBar_screen3:SetPercent(l1I1Il11Ill1l)
        end
        function lI111IlI111l1:OnFPSFTValueChange3(lIIIlII1IlI1l)
            lllllIIl1I1lI:UpdateUIData(lllllIIl1I1lI.FPSFineTuneNum, lIIIlII1IlI1l)
            self:InitFPSFTValue165()
            if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
            local lII11ll111IIl = lllllIIl1I1lI.GetGameInstance and lllllIIl1I1lI.GetGameInstance()
            if lII11ll111IIl then 
                lII11ll111IIl:ExecuteCMD("t.MaxFPS", tostring(lIIIlII1IlI1l))
                lII11ll111IIl:ExecuteCMD("r.FrameRateLimit", tostring(lIIIlII1IlI1l)) 
            end
        end
        function lI111IlI111l1:OnFPSFTSliderValueChange3(lIl1lI1Il1lIl)
            if lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneSwitch) then
                local lIIIlII1IlI1l = lIllllll11IIl.FCeil(lIl1lI1Il1lIl * (165 - lIl1l1Ill11Il) / l1lI11I1ll1Il) * l1lI11I1ll1Il + lIl1l1Ill11Il
                self:OnFPSFTValueChange3(lI1IIl1lllIII(lIIIlII1IlI1l, lIl1l1Ill11Il, 165))
            end
        end
        function lI111IlI111l1:OnFPSFTAdd3()
            local lIIIlII1IlI1l = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneNum)
            if lIIIlII1IlI1l then self:OnFPSFTValueChange3(math.min(165, lIIIlII1IlI1l + l1lI11I1ll1Il)) end
        end
        function lI111IlI111l1:OnFPSFTMinus3()
            local lIIIlII1IlI1l = lllllIIl1I1lI:GetUIData(lllllIIl1I1lI.FPSFineTuneNum)
            if lIIIlII1IlI1l then self:OnFPSFTValueChange3(math.max(lIl1l1Ill11Il, lIIIlII1IlI1l - l1lI11I1ll1Il)) end
        end
        lI111IlI111l1.OnFPSFTAdd = lI111IlI111l1.OnFPSFTAdd3 
        lI111IlI111l1.OnFPSFTMinus = lI111IlI111l1.OnFPSFTMinus3
        lI111IlI111l1.OnFPSFTSliderValueChange = lI111IlI111l1.OnFPSFTSliderValueChange3
    end
end




_G.ConfigFilePath = '/storage/emulated/0/Android/data/com.pubg.imobile/files/AKMOD_MENU.ini'

_G.BaseSkinIDs = {
    Weapons = { 101004, 101001, 101003, 103001, 102002, 103002, 103003, 101008, 102003, 105010, 102004, 105002, 105001, 101006, 104004 },
    Outfits = { Suit = 403003, Bag = 501001, Helmet = 502001, Parachut = 703001, Pet = 50000 }
}
_G.OutfitSkins = { 
    Suit = {_G.BaseSkinIDs.Outfits.Suit}, 
    Bag = {_G.BaseSkinIDs.Outfits.Bag}, 
    Helmet = {_G.BaseSkinIDs.Outfits.Helmet}, 
    Parachut = {_G.BaseSkinIDs.Outfits.Parachut}, 
    Pet = {_G.BaseSkinIDs.Outfits.Pet} 
}

_G.skinIdMappings = {}
for _, id in ipairs(_G.BaseSkinIDs.Weapons) do 
    _G.skinIdMappings[id] = {id} 
end


_G.VehicleMapDict = {
    UAZ = 1908001,
    Dacia = 1903001,
    Buggy = 1907001,
    Motor = 1901001,
    CoupeRB = 1961001
}

_G.VehicleSkinsList = {}
_G.VehicleSkinIndex = {}

_G.CustSlotType = { ClothesEquipemtSlot=5, BackpackEquipemtSlot=8, HelmetEquipemtSlot=9, ParachuteEquipemtSlot=11, GlideEquipemtSlot=15 }
_G.WeaponSkinIndex = _G.WeaponSkinIndex or {}
_G.SuitSkin, _G.BagSkin, _G.HelmetSkin, _G.ParachuteSkin, _G.GliderSkin, _G.PetSkin = 0, 0, 0, 0, 0, 0
_G.LastBackApplyValue, _G.LastHelmetApplyValue = 0, 0
_G.skinIdCache, _G.skinIdCache2 = {}, {}
local lIlI1l1Il1111 = {}

local function ll11I1I1llIIl(id)
    local l1IIlIl1I11I1 = require('client.slua.logic.download.puffer.puffer_manager')
    local l1Il11llIIlII = require('client.slua.logic.download.puffer_const')
    if l1IIlIl1I11I1 and l1Il11llIIlII and l1IIlIl1I11I1.GetState(l1Il11llIIlII.ENUM_DownloadType.ODPAK, {id}) ~= l1Il11llIIlII.ENUM_DownloadState.Done then
        l1IIlIl1I11I1.Download(l1Il11llIIlII.ENUM_DownloadType.ODPAK, {id})
    end
end
_G.download_item = ll11I1I1llIIl

_G.get_skin_id = function(weaponID)
    if not weaponID then return nil end
    local l1IIl111lIIl1 = (_G.WeaponSkinIndex[weaponID]) or 1
    local lI1I11Il1IllI = _G.skinIdMappings[weaponID]
    if not lI1I11Il1IllI or not lI1I11Il1IllI[l1IIl111lIIl1] then return weaponID end
    
    local l1IIIIll11llI = lI1I11Il1IllI[l1IIl111lIIl1]
    if not _G.skinIdCache2[l1IIIIll11llI] then 
        pcall(_G.download_item, l1IIIIll11llI)
        _G.skinIdCache2[l1IIIIll11llI] = true 
    end
    return l1IIIIll11llI
end

_G.get_vehicle_skin_id = function(vehicleID)
    if not vehicleID or vehicleID == 0 then return vehicleID end
    
    local ll1I11I1l1llI = tostring(vehicleID)
    local l11Il1Il1Il1I = string.sub(ll1I11I1l1llI, 1, 4)
    local ll1Il1lIl1IlI = tonumber(l11Il1Il1Il1I .. "001")
    
    local l1IlI1111l1l1 = _G.VehicleSkinsList[ll1Il1lIl1IlI]
    if l1IlI1111l1l1 then
        local l1lIlIll1I11I = _G.VehicleSkinIndex[ll1Il1lIl1IlI] or 1
        if l1lIlIll1I11I < 1 then l1lIlIll1I11I = 1 end
        if l1lIlIll1I11I > #l1IlI1111l1l1 then l1lIlIll1I11I = #l1IlI1111l1l1 end
        
        local lll1lIIIl1lII = l1IlI1111l1l1[l1lIlIll1I11I]
        if lll1lIIIl1lII and lll1lIIIl1lII > 0 then
            if not _G.skinIdCache2[lll1lIIIl1lII] then 
                if _G.download_item then pcall(_G.download_item, lll1lIIIl1lII) end
                _G.skinIdCache2[lll1lIIIl1lII] = true 
            end
            return lll1lIIIl1lII
        end
    end
    return vehicleID
end

_G.LoadSkinDataFromINI = function()
    local l11l1IIll11lI = io.open(_G.ConfigFilePath, 'r')
    if not l11l1IIll11lI then return end
    
    local ll11I11IIlIIl = false
    for line in l11l1IIll11lI:lines() do
        if line:match('%[SKIN_LIST%]') then 
            ll11I11IIlIIl = true 
        elseif line:match('%[SELECTED%]') then 
            ll11I11IIlIIl = false 
        end
        
        if ll11I11IIlIIl and not line:match('^%s*%[') and not line:match('^%s*[#]') then
            local llII1llllIl1I, llI11Il11IlIl = line:match('([^=]+)=(.+)')
            if llII1llllIl1I and llI11Il11IlIl then
                llII1llllIl1I = llII1llllIl1I:match("^%s*(.-)%s*$")
                local llI1llIl1IIll = {}
                for val in llI11Il11IlIl:gmatch('([^,]+)') do
                    local l11I1IlI1l11l = tonumber(val:match("^%s*(.-)%s*$"))
                    if l11I1IlI1l11l then table.insert(llI1llIl1IIll, l11I1IlI1l11l) end
                end
                
                if #llI1llIl1IIll > 0 then
                    if _G.OutfitSkins[llII1llllIl1I] ~= nil then 
                        _G.OutfitSkins[llII1llllIl1I] = llI1llIl1IIll
                    elseif _G.VehicleMapDict[llII1llllIl1I] ~= nil then 
                        local l111lIlIllIII = _G.VehicleMapDict[llII1llllIl1I]
                        _G.VehicleSkinsList[l111lIlIllIII] = llI1llIl1IIll
                    elseif tonumber(llII1llllIl1I) then 
                        _G.skinIdMappings[tonumber(llII1llllIl1I)] = llI1llIl1IIll 
                    end
                end
            end
        end
    end
    l11l1IIll11lI:close()
    
    _G.SuitSkinsMap = _G.OutfitSkins.Suit
    _G.BagSkinsMap = _G.OutfitSkins.Bag
    _G.HelmetSkinsMap = _G.OutfitSkins.Helmet
    _G.ParachutSkinsMap = _G.OutfitSkins.Parachut
    _G.PetSkinsMap = _G.OutfitSkins.Pet
end
pcall(_G.LoadSkinDataFromINI)

_G.ReadConfigFile = function()
    local l11l1IIll11lI = io.open(_G.ConfigFilePath, 'r')
    if not l11l1IIll11lI then return end
    
    local l11Il11lIlIl1 = {}
    for line in l11l1IIll11lI:lines() do
        if line:match('%[SKIN_LIST%]') then break end 
        if not line:match('^%s*%[') and not line:match('^%s*[#]') then
            local llII1llllIl1I, lIl1lI1Il1lIl = line:match('([%w_]+)%s*=%s*(%d+)')
            if llII1llllIl1I and lIl1lI1Il1lIl and not line:match(',') then 
                l11Il11lIlIl1[llII1llllIl1I] = tonumber(lIl1lI1Il1lIl) 
            end
        end
    end
    l11l1IIll11lI:close()
    
    local function lI111lllI111I(llII1llllIl1I, map, globalVarName)
        if l11Il11lIlIl1[llII1llllIl1I] and l11Il11lIlIl1[llII1llllIl1I] ~= lIlI1l1Il1111[llII1llllIl1I] then 
            _G[globalVarName] = map and map[l11Il11lIlIl1[llII1llllIl1I] + 1] or 0
            lIlI1l1Il1111[llII1llllIl1I] = l11Il11lIlIl1[llII1llllIl1I] 
        end
    end
    
    lI111lllI111I('Suit', _G.SuitSkinsMap, 'SuitSkin')
    lI111lllI111I('Bag', _G.BagSkinsMap, 'BagSkin')
    lI111lllI111I('Helmet', _G.HelmetSkinsMap, 'HelmetSkin')
    lI111lllI111I('Parachute', _G.ParachutSkinsMap, 'ParachuteSkin')
    lI111lllI111I('Pet', _G.PetSkinsMap, 'PetSkin')
    
    local function l1Il1IlIllIll(llII1llllIl1I, id)
        if l11Il11lIlIl1[llII1llllIl1I] and l11Il11lIlIl1[llII1llllIl1I] ~= lIlI1l1Il1111[llII1llllIl1I] then 
            _G.WeaponSkinIndex[id] = l11Il11lIlIl1[llII1llllIl1I] + 1
            lIlI1l1Il1111[llII1llllIl1I] = l11Il11lIlIl1[llII1llllIl1I] 
        end
    end
    
    l1Il1IlIllIll('M416', 101004)
    l1Il1IlIllIll('AKM', 101001)
    l1Il1IlIllIll('UMP', 102002)
    l1Il1IlIllIll('SCAR', 101003)
    l1Il1IlIllIll('M762', 101008)
    l1Il1IlIllIll('AUG', 101006)
    l1Il1IlIllIll('Vector', 102003)
    l1Il1IlIllIll('UZI', 102004)
    l1Il1IlIllIll('Kar98k', 103001)
    l1Il1IlIllIll('M24', 103002)
    l1Il1IlIllIll('AWM', 103003)
    l1Il1IlIllIll('DP28', 105002)
    l1Il1IlIllIll('M249', 105001)
    l1Il1IlIllIll('MG3', 105010)
    l1Il1IlIllIll('Shotgun', 104004)

    local function lI1ll1llI11lI(llII1llllIl1I)
        local l111lIlIllIII = _G.VehicleMapDict[llII1llllIl1I]
        if l111lIlIllIII and l11Il11lIlIl1[llII1llllIl1I] and l11Il11lIlIl1[llII1llllIl1I] ~= lIlI1l1Il1111[llII1llllIl1I] then 
            _G.VehicleSkinIndex[l111lIlIllIII] = l11Il11lIlIl1[llII1llllIl1I] + 1
            lIlI1l1Il1111[llII1llllIl1I] = l11Il11lIlIl1[llII1llllIl1I] 
        end
    end
    
    lI1ll1llI11lI('UAZ')
    lI1ll1llI11lI('Dacia')
    lI1ll1llI11lI('Buggy')
    lI1ll1llI11lI('Motor')
    lI1ll1llI11lI('CoupeRB')
end

_G.BaseAttachToIndex = {
    [201010]=1, [201005]=1, [201004]=1, 
    [201009]=2, [201003]=2, [201002]=2, 
    [201011]=3, [201007]=3, [201006]=3, 
    [204012]=4, [204005]=4, [204008]=4, 
    [204011]=5, [204004]=5, [204007]=5, 
    [204013]=6, [204006]=6, [204009]=6, 
    [203001]=7, [203002]=8, [203003]=9, [203014]=10, [203004]=11, [203015]=12, [203005]=13, 
    [202002]=14, [202001]=15, [202004]=16, [202005]=17, [202007]=18, [202006]=19, 
    [205002]=20, [205003]=20, [205001]=20, 
    [203018]=21, [204014]=22 
}

_G.VIP_Attachments = {}
_G.VipAttachToIndex = {} 

_G.LoadAttachmentsFromINI = function()
    local l11l1IIll11lI = io.open(_G.ConfigFilePath, 'r')
    if not l11l1IIll11lI then return end
    
    _G.VIP_Attachments = {}
    _G.VipAttachToIndex = {}
    
    local lI1I1Il1l1ll1 = false
    for line in l11l1IIll11lI:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line == '[ATTACHMENTS]' then 
            lI1I1Il1l1ll1 = true 
        elseif line:match('^%[') then 
            lI1I1Il1l1ll1 = false 
        end
        
        if lI1I1Il1l1ll1 and not line:match('^%[') and line ~= '' and not line:match('^#') then
            local l1II1I1ll1IlI, llI11Il11IlIl = line:match('^(%d+)=(.+)$')
            if l1II1I1ll1IlI and llI11Il11IlIl then
                local l1IIIIll11llI = tonumber(l1II1I1ll1IlI)
                local lI1I111II1lII = {}
                local l1IIl111lIIl1 = 1
                for val in llI11Il11IlIl:gmatch('([^,]+)') do
                    local lIIIlII1IlI1l = tonumber(val) or 0
                    table.insert(lI1I111II1lII, lIIIlII1IlI1l)
                    if lIIIlII1IlI1l > 0 then _G.VipAttachToIndex[lIIIlII1IlI1l] = l1IIl111lIIl1 end
                    l1IIl111lIIl1 = l1IIl111lIIl1 + 1
                end
                _G.VIP_Attachments[l1IIIIll11llI] = lI1I111II1lII
            end
        end
    end
    l11l1IIll11lI:close()
end
pcall(_G.LoadAttachmentsFromINI)

_G.equip_character_avatar = function(llIl111lII11l)
    if not llIl111lII11l or not slua.isValid(llIl111lII11l) or not llIl111lII11l.AvatarComponent2 then return end
    local llIIII111llI1 = import("BackpackUtils")
    local lII111IIII1lI = llIl111lII11l.AvatarComponent2.NetAvatarData and llIl111lII11l.AvatarComponent2.NetAvatarData.SlotSyncData
    if not lII111IIII1lI or not slua.isValid(lII111IIII1lI) or not llIIII111llI1 then return end
    
    local function lIlIIII1l1Il1(ApplyDataIdx, itemId, ApplyEquipSlot, isLevelDependent, levelFunc, globalCacheVal)
        if itemId == 0 then return end
        local lIlIllIl1Il11 = lII111IIII1lI:Get(ApplyDataIdx)
        if lIlIllIl1Il11 and lIlIllIl1Il11.SlotID == ApplyEquipSlot then
            local l1l1II11l1l1l = itemId
            if isLevelDependent then
                local lllI1I1IlllIl = levelFunc(lIlIllIl1Il11.AdditionalItemID) or 1
                l1l1II11l1l1l = itemId + (lllI1I1IlllIl - 1) * 1000
                if l1l1II11l1l1l == lIlIllIl1Il11.ItemId and _G[globalCacheVal] == itemId then return end
                _G[globalCacheVal] = itemId
            elseif lIlIllIl1Il11.ItemId == itemId then 
                return 
            end

            if not _G.skinIdCache[l1l1II11l1l1l] then 
                _G.download_item(l1l1II11l1l1l)
                _G.skinIdCache[l1l1II11l1l1l] = true 
            end
            
            lIlIllIl1Il11.ItemId = l1l1II11l1l1l
            lII111IIII1lI:Set(ApplyDataIdx, lIlIllIl1Il11)
            llIl111lII11l.AvatarComponent2:OnRep_BodySlotStateChanged()
        end
    end

    local l1lllIllII1I1 = false
    for i = 0, lII111IIII1lI:Num() - 1 do
        local lIlIllIl1Il11 = lII111IIII1lI:Get(i)
        if lIlIllIl1Il11 and lIlIllIl1Il11.SlotID == _G.CustSlotType.GlideEquipemtSlot then 
            l1lllIllII1I1 = true
            break 
        end
    end
    if not l1lllIllII1I1 then 
        lII111IIII1lI:Add({ SlotID = _G.CustSlotType.GlideEquipemtSlot, ItemId = 0 }) 
    end

    for i = 0, lII111IIII1lI:Num() - 1 do
        lIlIIII1l1Il1(i, _G.SuitSkin, _G.CustSlotType.ClothesEquipemtSlot, false)
        lIlIIII1l1Il1(i, _G.BagSkin, _G.CustSlotType.BackpackEquipemtSlot, true, llIIII111llI1.GetEquipmentBagLevel, 'LastBackApplyValue')
        lIlIIII1l1Il1(i, _G.HelmetSkin, _G.CustSlotType.HelmetEquipemtSlot, true, llIIII111llI1.GetEquipmentHelmetLevel, 'LastHelmetApplyValue')
        lIlIIII1l1Il1(i, _G.GliderSkin, _G.CustSlotType.GlideEquipemtSlot, false)
        lIlIIII1l1Il1(i, _G.ParachuteSkin, _G.CustSlotType.ParachuteEquipemtSlot, false)
    end
end

_G.ApplyWeaponSkins = function(lII1lllIIlI1I)
    pcall(function()
        local l1lI1Il11l1l1 = lII1lllIIlI1I:GetWeaponManager()
        if not slua.isValid(l1lI1Il11l1l1) then return end
        
        for slot = 1, 3 do
            local llI11lIIl1lll = l1lI1Il11l1l1:GetInventoryWeaponByPropSlot(slot)
            if slua.isValid(llI11lIIl1lll) and slua.isValid(llI11lIIl1lll.synData) then
                local llIIlIlIlII1I = llI11lIIl1lll:GetWeaponID()
                local lllI1lII11l11 = _G.get_skin_id(llIIlIlIlII1I) or llIIlIlIlII1I
                local l1II1ll1lIIlI = false
                
                local lllII1111Il1I = llI11lIIl1lll.synData:Get(7) 
                if lllII1111Il1I and lllII1111Il1I.defineID and lllII1111Il1I.defineID.TypeSpecificID ~= lllI1lII11l11 then
                    lllII1111Il1I.defineID.TypeSpecificID = lllI1lII11l11
                    llI11lIIl1lll.synData:Set(7, lllII1111Il1I)
                    if llI11lIIl1lll.SetWeaponAvatarID then pcall(function() llI11lIIl1lll:SetWeaponAvatarID(lllI1lII11l11) end) end
                    if not _G.skinIdCache[lllI1lII11l11] then 
                        _G.download_item(lllI1lII11l11)
                        _G.skinIdCache[lllI1lII11l11] = true 
                    end
                    l1II1ll1lIIlI = true
                end
                
                if lllI1lII11l11 >= 10000000 and _G.VIP_Attachments and _G.VIP_Attachments[lllI1lII11l11] then
                    for AttachIdx = 0, 5 do 
                        local lll1II1II11ll = llI11lIIl1lll.synData:Get(AttachIdx)
                        if lll1II1II11ll then
                            local l111l1ll1I11I = slua.IndexReference(lll1II1II11ll, "defineID")
                            if l111l1ll1I11I then
                                local l1Illll111II1 = l111l1ll1I11I.TypeSpecificID
                                if l1Illll111II1 and l1Illll111II1 > 0 then
                                    local l1IIl111lIIl1 = _G.BaseAttachToIndex[l1Illll111II1] or _G.VipAttachToIndex[l1Illll111II1]
                                    if l1IIl111lIIl1 and _G.VIP_Attachments[lllI1lII11l11][l1IIl111lIIl1] and _G.VIP_Attachments[lllI1lII11l11][l1IIl111lIIl1] > 0 then
                                        local lllI1Il1l1lll = _G.VIP_Attachments[lllI1lII11l11][l1IIl111lIIl1]
                                        if lllI1Il1l1lll ~= l1Illll111II1 then
                                            lll1II1II11ll.defineID.TypeSpecificID = lllI1Il1l1lll
                                            llI11lIIl1lll.synData:Set(AttachIdx, lll1II1II11ll)
                                            if not _G.skinIdCache2[lllI1Il1l1lll] then 
                                                if _G.download_item then pcall(_G.download_item, lllI1Il1l1lll) end
                                                _G.skinIdCache2[lllI1Il1l1lll] = true 
                                            end
                                            l1II1ll1lIIlI = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                if l1II1ll1lIIlI then
                    if llI11lIIl1lll.DelayHandleAvatarMeshChanged then pcall(function() llI11lIIl1lll:DelayHandleAvatarMeshChanged() end) end
                    if llI11lIIl1lll.OnRep_synData then pcall(function() llI11lIIl1lll:OnRep_synData() end) end
                end
            end
        end
    end)
end




_G.ApplyVehicleSkins = function(lII1lllIIlI1I)
    pcall(function()
        local l11I11I11ll1I = lII1lllIIlI1I:GetCurrentVehicle()
        if not slua.isValid(l11I11I11ll1I) then 
            _G.LastVehicleEntity = nil
            return 
        end
        
        
        if not Game:IsDriver(lII1lllIIlI1I.Object) then return end

        local lIlI1IIllI1Il = l11I11I11ll1I.VehicleAvatarComponent_BP or l11I11I11ll1I:GetAvatarComponent()
        if not slua.isValid(lIlI1IIllI1Il) then return end

        
        local ll1IlIll1IIll = 0
        if l11I11I11ll1I.AvatarDefaultCfg then
            ll1IlIll1IIll = l11I11I11ll1I.AvatarDefaultCfg.TypeSpecificID
        end
        if ll1IlIll1IIll == 0 and lIlI1IIllI1Il.VehicleNetAvatarData and lIlI1IIllI1Il.VehicleNetAvatarData.ItemDefineID then
            ll1IlIll1IIll = lIlI1IIllI1Il.VehicleNetAvatarData.ItemDefineID.TypeSpecificID
        end
        if ll1IlIll1IIll == 0 then return end

        local lI1l1Il11lIlI = _G.get_vehicle_skin_id(ll1IlIll1IIll)
        local lllll111IIllI = lIlI1IIllI1Il:GetCurItemAvatarID()

        
        if lI1l1Il11lIlI and lI1l1Il11lIlI ~= 0 and lllll111IIllI ~= lI1l1Il11lIlI then
            if not _G.skinIdCache[lI1l1Il11lIlI] then 
                if _G.download_item then pcall(_G.download_item, lI1l1Il11lIlI) end
                _G.skinIdCache[lI1l1Il11lIlI] = true 
            end

            
            if lIlI1IIllI1Il.VehicleNetAvatarData and lIlI1IIllI1Il.VehicleNetAvatarData.ItemDefineID then
                lIlI1IIllI1Il.VehicleNetAvatarData.ItemDefineID.TypeSpecificID = lI1l1Il11lIlI
                lIlI1IIllI1Il.VehicleNetAvatarData.SkinOwnerUID = lII1lllIIlI1I.PlayerUID
            end
            
            
            if _G.LastVehicleEntity ~= l11I11I11ll1I or _G.CurrentEquipVehicleID ~= lI1l1Il11lIlI then
                _G.LastVehicleEntity = l11I11I11ll1I
                _G.CurrentEquipVehicleID = lI1l1Il11lIlI

                pcall(function()
                    
                    lIlI1IIllI1Il.lastEquipedAvatarId = lllll111IIllI
                    
                    
                    if lIlI1IIllI1Il.ShowVehicleSwitchEffect then 
                        lIlI1IIllI1Il:ShowVehicleSwitchEffect() 
                    end
                    
                    
                    lIlI1IIllI1Il.ClientUsedAvatarID = lI1l1Il11lIlI
                    l11I11I11ll1I.ClientUsedAvatarID = lI1l1Il11lIlI
                    if lIlI1IIllI1Il.ChangeItemAvatar then 
                        lIlI1IIllI1Il:ChangeItemAvatar(lI1l1Il11lIlI, false) 
                    end
                end)
            else
                
                if lIlI1IIllI1Il.ChangeItemAvatar then lIlI1IIllI1Il:ChangeItemAvatar(lI1l1Il11lIlI, false) end
            end

            
            if lIlI1IIllI1Il.EnableHighTireLight then
                lIlI1IIllI1Il:EnableHighTireLight(true, lI1l1Il11lIlI)
            end
            
            
            if l11I11I11ll1I.UpdateParticle then pcall(function() l11I11I11ll1I:UpdateParticle(lI1l1Il11lIlI) end) end
            if l11I11I11ll1I.ChangeParticles then pcall(function() l11I11I11ll1I:ChangeParticles(lI1l1Il11lIlI) end) end
            if l11I11I11ll1I.ReActivateExhaustParticle then pcall(function() l11I11I11ll1I:ReActivateExhaustParticle() end) end
            
            
            local l1Il1lIIIIlll = import("VehicleLicenseNumberComponent")
            local l1I111I1l1lIl = l11I11I11ll1I:GetComponentByClass(l1Il1lIIIIlll)
            if slua.isValid(l1I111I1l1lIl) then
                if l1I111I1l1lIl.LicensePlate then
                    l1I111I1l1lIl.LicensePlate.ItemID = lI1l1Il11lIlI
                    l1I111I1l1lIl.LicensePlate.ChassisLightId = lI1l1Il11lIlI + 1000
                end
                if l1I111I1l1lIl.PreChangeEffect then l1I111I1l1lIl:PreChangeEffect() end
                if l1I111I1l1lIl.PreChangeChassisLight then l1I111I1l1lIl:PreChangeChassisLight() end
            end
            
            
            if l11I11I11ll1I.SetVehicleMusicPlayState then l11I11I11ll1I:SetVehicleMusicPlayState(true) end
        end
    end)
end

_G.HandlePetLogic = function()
    pcall(function()
        if not _G.PetSkin or _G.PetSkin == 0 or _G.PetSkin == 50000 or _G.PetSkin == _G.LastAppliedPet then return end
        if not _G.skinIdCache[_G.PetSkin] then _G.download_item(_G.PetSkin); _G.skinIdCache[_G.PetSkin] = true end
        
        local l1II1111I1Il1 = require("client.module_framework.ModuleManager")
        if l1II1111I1Il1 then
            local lIll1111II11I = l1II1111I1Il1.GetModule(l1II1111I1Il1.CommonModuleConfig.logic_pet)
            if lIll1111II11I then
                if lIll1111II11I.SetCurPetID then lIll1111II11I:SetCurPetID(_G.PetSkin) end
                if lIll1111II11I.EquipPet then lIll1111II11I:EquipPet(_G.PetSkin) end
            end
        end
        _G.LastAppliedPet = _G.PetSkin
    end)
end

_G.DeadBoxSkins = _G.DeadBoxSkins or {}
_G.AlreadyChangedSet = _G.AlreadyChangedSet or {}

local function llIllIIlll1II(t, element)
    if not t then return false end
    for _, lIl1lI1Il1lIl in ipairs(t) do
        if lIl1lI1Il1lIl == element then return true end
    end
    return false
end

local function llllI1lIl1l11(loc1, loc2, tolerance)
    local dx = loc1.X - loc2.X
    local dy = loc1.Y - loc2.Y
    local dz = loc1.Z - loc2.Z
    return dx * dx + dy * dy + dz * dz < tolerance * tolerance
end

_G.DeadBox_TemperRequest = function(lI11lIlIlI1II)
    local llIl111lII11l = lI11lIlIlI1II:GetPlayerCharacterSafety()
    if not llIl111lII11l then return end
    
    local lll1I1l1l11I1 = import("GameplayStatics")
    if lll1I1l1l11I1 then
        local l1l111IIl1I1l = import("Actor")
        local lII1I1111I1ll = require("client.common.ui_util")
        if lII1I1111I1ll then
            local lII1II1l111Il = lII1I1111I1ll.GetGameInstance()
            if lII1II1l111Il then
                local l1IIl111ll11I = import("PlayerTombBox")
                local llIIII1l11l1I = lll1I1l1l11I1.GetAllActorsOfClass(lII1II1l111Il, l1IIl111ll11I, slua.Array(UEnums.EPropertyClass.Object, l1l111IIl1I1l))
                
                for _, lIlIl111lIl1l in pairs(llIIII1l11l1I) do
                    if slua.isValid(lIlIl111lIl1l) then
                        local llIlll1lI1IlI = lIlIl111lIl1l.DamageCauser
                        if llIlll1lI1IlI and llIlll1lI1IlI.Playerkey == lI11lIlIlI1II.Playerkey then
                            local ll1IllIllI1ll = lIlIl111lIl1l.DeadBoxAvatarComponent_BP
                            if ll1IllIllI1ll and not llIllIIlll1II(_G.AlreadyChangedSet, lIlIl111lIl1l) then
                                local l11III1lllI1l = lIlIl111lIl1l:K2_GetActorLocation()
                                local lIl111IlI11ll = false
                                
                                for _, entry in pairs(_G.DeadBoxSkins) do
                                    if llllI1lIl1l11(entry.location, l11III1lllI1l, 1.0) then
                                        ll1IllIllI1ll:ResetItemAvatar()
                                        ll1IllIllI1ll:PreChangeItemAvatar(entry.SkinID)
                                        ll1IllIllI1ll:SyncChangeItemAvatar(entry.SkinID)
                                        table.insert(_G.AlreadyChangedSet, lIlIl111lIl1l)
                                        lIl111IlI11ll = true
                                        break
                                    end
                                end
                                
                                if not lIl111IlI11ll then
                                    local llIlIIlI111II = 0
                                    local lI11IlI1IIl1I = llIl111lII11l.CurrentVehicle
                                    if lI11IlI1IIl1I and _G.CurrentEquipVehicleID and _G.CurrentEquipVehicleID ~= 0 then
                                        llIlIIlI111II = tonumber(tostring(_G.CurrentEquipVehicleID) .. "1") or 0
                                    else
                                        local lI1l1llI1I1Il = llIl111lII11l:GetCurrentWeapon()
                                        if lI1l1llI1I1Il then
                                            local lllII1111Il1I = lI1l1llI1I1Il.synData and lI1l1llI1I1Il.synData:Get(7)
                                            if lllII1111Il1I and lllII1111Il1I.defineID then
                                                llIlIIlI111II = lllII1111Il1I.defineID.TypeSpecificID
                                            end
                                        end
                                    end
                                    
                                    if llIlIIlI111II ~= 0 then
                                        ll1IllIllI1ll:ResetItemAvatar()
                                        ll1IllIllI1ll:PreChangeItemAvatar(llIlIIlI111II)
                                        ll1IllIllI1ll:SyncChangeItemAvatar(llIlIIlI111II)
                                        table.insert(_G.DeadBoxSkins, { location = l11III1lllI1l, SkinID = llIlIIlI111II })
                                        table.insert(_G.AlreadyChangedSet, lIlIl111lIl1l)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

_G.AKFakeKillCounts = _G.AKFakeKillCounts or {}

_G.ForceEnableKillCounterUI = function()
    pcall(function()
        local l1lllllIlIII1 = package.loaded["GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem"] or require("GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem")
        if l1lllllIlIII1 and l1lllllIlIII1.__inner_impl and not _G.KCUISystemHacked2 then
            local lIII1II11II1I = l1lllllIlIII1.__inner_impl
            lIII1II11II1I.CheckSupportKCUI = function() return true end
            
            lIII1II11II1I.CheckNeedMainKillCounterUI = function(self, lII1Il1111lI1, PlayerID)
                if slua.isValid(lII1Il1111lI1) then
                    local llIIlIlIlII1I = lII1Il1111lI1:GetWeaponID()
                    self:UpdateMainKillCounterUI(true, llIIlIlIlII1I, _G.get_skin_id(llIIlIlIlII1I) or llIIlIlIlII1I)
                else 
                    self:UpdateMainKillCounterUI(false) 
                end
            end
            
            local lI1III1I1lIl1 = lIII1II11II1I.UpdateMainKillCounterUI
            lIII1II11II1I.UpdateMainKillCounterUI = function(self, bShow, ll1111II1lI11, AvatarID)
                if bShow then AvatarID = _G.get_skin_id(ll1111II1lI11) or AvatarID end
                if lI1III1I1lIl1 then lI1III1I1lIl1(self, bShow, ll1111II1lI11, AvatarID) end
            end
            _G.KCUISystemHacked2 = true
        end

        local l1II1111I1Il1 = require("client.module_framework.ModuleManager")
        if l1II1111I1Il1 then
            local lIIlll1IIll1I = l1II1111I1Il1.GetModule(l1II1111I1Il1.CommonModuleConfig.LogicKillCounter)
            if lIIlll1IIll1I and not _G.KCLogicHacked2 then
                lIIlll1IIll1I.CheckSupportKC = function() return true end
                lIIlll1IIll1I.CheckSupportKillCounterAvatar = function() return true end
                lIIlll1IIll1I.CheckHasWeaponKillCounter = function() return true end
                lIIlll1IIll1I.GetBaseKillCounterIdByWeaponId = function() return 2100004 end
                lIIlll1IIll1I.GetEquipedKillCounterId = function() return 2100004 end
                lIIlll1IIll1I.GetMyEquipedKillCounterId = function() return 2100004 end
                lIIlll1IIll1I.GetOneWeaponKillCountInBattle = function(self, uid, weaponId) return _G.AKFakeKillCounts[weaponId] or 0 end
                lIIlll1IIll1I.GetWeaponKillCountByUid = function(self, uid, weaponId) return _G.AKFakeKillCounts[weaponId] or 0 end
                _G.KCLogicHacked2 = true
            end
        end

        local ll1l11I11llI1 = "GameLua.Mod.BaseMod.Client.KillInfoTips.KillInfo"
        local llIIIIlll1Il1 = package.loaded[ll1l11I11llI1] or require(ll1l11I11llI1)
        if llIIIIlll1Il1 and llIIIIlll1Il1.__inner_impl and not _G.KillInfoCounterHacked then
            local l1lIll1I1ll1l = llIIIIlll1Il1.__inner_impl.FileItem
            llIIIIlll1Il1.__inner_impl.FileItem = function(self, DamageRecordData)
                pcall(function()
                    local l1lI11IIIllII = require("GameLua.GameCore.Data.GameplayData").GetPlayerCharacter()
                    if slua.isValid(l1lI11IIIllII) and DamageRecordData.Causer == l1lI11IIIllII:GetPlayerNameSafety() then 
                        local l11IlIl1II11I = l1lI11IIIllII:GetCurrentWeapon()
                        if slua.isValid(l11IlIl1II11I) then
                            local l1II1l1lIlI11 = l11IlIl1II11I:GetWeaponID()
                            local ll11IIIIIIl11 = _G.get_skin_id(l1II1l1lIlI11)
                            if ll11IIIIIIl11 then DamageRecordData.CauserWeaponAvatarID = ll11IIIIIIl11 end
                            if _G.SuitSkin ~= 0 then DamageRecordData.CauserClothAvatarID = _G.SuitSkin end
                            
                            DamageRecordData.IsUseColor, DamageRecordData.UseColor = true, import("LinearColor")(1.0, 0.8, 0.0, 1.0) 
                            
                            if DamageRecordData.ResultHealthStatus == 2 then
                                _G.AKFakeKillCounts[l1II1l1lIlI11] = (_G.AKFakeKillCounts[l1II1l1lIlI11] or 0) + 1
                                local lI11IIIlIIlIl = require("client.slua_ui_framework.manager")
                                local lIlIIIII1Il1l = lI11IIIlIIlIl.GetUI(lI11IIIlIIlIl.UI_Config_InGame.MainKillCounter)
                                if lIlIIIII1Il1l and lIlIIIII1Il1l.UpdateWeaponID then
                                    local ll1Il1llllI1l = ll11IIIIIIl11 or l11IlIl1II11I:GetWeaponMainAvatarID()
                                    lIlIIIII1Il1l:UpdateWeaponID(l1II1l1lIlI11, ll1Il1llllI1l)
                                    local llll1lI111lIl = l1II1111I1Il1.GetModule(l1II1111I1Il1.CommonModuleConfig.LogicKillCounter)
                                    local llI11lI11I1II = llll1lI111lIl:GetEquipedKillCounterId(0, ll1Il1llllI1l)
                                    lIlIIIII1Il1l:SetKillCounterItemShowWithNum(llI11lI11I1II, _G.AKFakeKillCounts[l1II1l1lIlI11], ll1Il1llllI1l)
                                end
                            end
                        end
                    end
                end)
                if l1lIll1I1ll1l then return l1lIll1I1ll1l(self, DamageRecordData) end
            end
            _G.KillInfoCounterHacked = true
        end

        local lllllIllllIlI = package.loaded["GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2"] or require("GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2")
        if lllllIllllIlI and lllllIllllIlI.__inner_impl and not _G.SlotBaseHacked then
            lllllIllllIlI.__inner_impl.CheckShowKCIcon = function(self)
                if self.KillCounterImg and slua.isValid(self.KillCounterImg) then 
                    self.KillCounterImg:SetVisibility(import("ESlateVisibility").SelfHitTestInvisible) 
                end
            end
            _G.SlotBaseHacked = true
        end
    end)
end

function _G.InitializeSkinModSystem()
    pcall(function()
        local lIIllIl1I1l1l = package.loaded["client.logic.avatar.LobbyAvatar"] or require("client.logic.avatar.LobbyAvatar")
        if lIIllIl1I1l1l and not _G.LobbyBypassHacked then
            local lI1IIl111Il1I = lIIllIl1I1l1l.PutonEquipment
            lIIllIl1I1l1l.PutonEquipment = function(self, itemID, tAvatarCustom, tExtraData)
                local l1IIl111lIIl1 = _G.BaseAttachToIndex and _G.BaseAttachToIndex[itemID]
                if l1IIl111lIIl1 then
                    local lllI11l1l1I11 = self.GetCurHoldingWeaponSkinID and self:GetCurHoldingWeaponSkinID()
                    if lllI11l1l1I11 and lllI11l1l1I11 >= 10000000 and _G.VIP_Attachments and _G.VIP_Attachments[lllI11l1l1I11] then
                        local l1lIIllI11I1I = _G.VIP_Attachments[lllI11l1l1I11][l1IIl111lIIl1]
                        if l1lIIllI11I1I and l1lIIllI11I1I > 0 then
                            if self.HandleDownload then self:HandleDownload(l1lIIllI11I1I, nil, nil, false) end
                            itemID = l1lIIllI11I1I
                        end
                    end
                end
                if lI1IIl111Il1I then
                    return lI1IIl111Il1I(self, itemID, tAvatarCustom, tExtraData)
                end
            end

            local lIl1IIIIl1Ill = lIIllIl1I1l1l.CharEquipWeaponByResId
            lIIllIl1I1l1l.CharEquipWeaponByResId = function(self, resID, isUse, isAsync, SocketName)
                local lll1III111lll
                if lIl1IIIIl1Ill then
                    lll1III111lll = lIl1IIIIl1Ill(self, resID, isUse, isAsync, SocketName)
                end
                if isUse and self.GetEquipments then
                    local l11lll1lI11lI = self:GetEquipments()
                    for _, equip in ipairs(l11lll1lI11lI) do
                        if _G.BaseAttachToIndex and _G.BaseAttachToIndex[equip.itemID] then
                            self:PutonEquipment(equip.itemID, equip.CustomInfo, {bIsUse = false})
                        end
                    end
                end
                return lll1III111lll
            end
            _G.LobbyBypassHacked = true
        end
    end)

    pcall(function()
        local lIllII1l1Illl = package.loaded["client.slua.component.item.ItemChildren.Common_Items_UIBP"] or require("client.slua.component.item.ItemChildren.Common_Items_UIBP")
        if lIllII1l1Illl and not _G.IconBaloHacked then
            local l1I1Il11I111I = lIllII1l1Illl.InitView
            lIllII1l1Illl.InitView = function(self, nItemId, nCount, nValidTime, tExtraData)
                tExtraData = tExtraData or {}
                local lIlI1llIl1l11 = nil
                
                if _G.get_skin_id then
                    local lIIIll11l1I1I = _G.get_skin_id(nItemId)
                    if lIIIll11l1I1I and lIIIll11l1I1I ~= nItemId then
                        lIlI1llIl1l11 = lIIIll11l1I1I
                    end
                end
                
                local l1IIl111lIIl1 = _G.BaseAttachToIndex and _G.BaseAttachToIndex[nItemId]
                if not lIlI1llIl1l11 and l1IIl111lIIl1 then
                    local lII11lIllllII = require("GameLua.GameCore.Data.GameplayData")
                    if lII11lIllllII then
                        local lII1lllIIlI1I = lII11lIllllII.GetPlayerCharacter()
                        if lII1lllIIlI1I and slua.isValid(lII1lllIIlI1I) then
                            local l1IIIlI1IIlI1 = lII1lllIIlI1I:GetCurrentWeapon()
                            if slua.isValid(l1IIIlI1IIlI1) then
                                local llIIlIlIlII1I = l1IIIlI1IIlI1:GetWeaponID()
                                local lII1lll1II1lI = _G.get_skin_id(llIIlIlIlII1I) or llIIlIlIlII1I
                                if lII1lll1II1lI >= 10000000 and _G.VIP_Attachments and _G.VIP_Attachments[lII1lll1II1lI] then
                                    local l111I1lI1llIl = _G.VIP_Attachments[lII1lll1II1lI][l1IIl111lIIl1]
                                    if l111I1lI1llIl and l111I1lI1llIl > 0 then
                                        lIlI1llIl1l11 = l111I1lI1llIl
                                    end
                                end
                            end
                        end
                    end
                end
                
                if lIlI1llIl1l11 then
                    tExtraData.displayResId = lIlI1llIl1l11
                    if not _G.skinIdCache2[lIlI1llIl1l11] then
                        if _G.download_item then pcall(_G.download_item, lIlI1llIl1l11) end
                        _G.skinIdCache2[lIlI1llIl1l11] = true
                    end
                end
                
                if l1I1Il11I111I then
                    return l1I1Il11I111I(self, nItemId, nCount, nValidTime, tExtraData)
                end
            end
            _G.IconBaloHacked = true
        end
    end)

    pcall(function()
        local lI1l1ll1I111I = "GameLua.Activity.Commercialize.GamePlay.Vehicle.VehiclePlateLicenseUtil"
        local lIlI1l11l1I11 = package.loaded[lI1l1ll1I111I] or require(lI1l1ll1I111I)
        
        if lIlI1l11l1I11 and not _G.VehicleEffectHacked then
            lIlI1l11l1I11.CheckIsBetterVehicle = function() return true end
            lIlI1l11l1I11.CheckHasUnLockFeature = function() return true end
            lIlI1l11l1I11.NeedOpenHighTire = function() return true end
            
            local l1l11IIIlI1ll = lIlI1l11l1I11.GetUpgradeEffectList
            lIlI1l11l1I11.GetUpgradeEffectList = function(UID)
                local lII1lllIIlI1I = require("GameLua.GameCore.Data.GameplayData").GetPlayerCharacter()
                if slua.isValid(lII1lllIIlI1I) and lII1lllIIlI1I:GetCurrentVehicle() then
                    local l11I11I11ll1I = lII1lllIIlI1I:GetCurrentVehicle()
                    local lIlI1IIllI1Il = l11I11I11ll1I.VehicleAvatarComponent_BP or l11I11I11ll1I:GetAvatarComponent()
                    if slua.isValid(lIlI1IIllI1Il) then
                        local lll1lIIIl1lII = lIlI1IIllI1Il.VehicleNetAvatarData and lIlI1IIllI1Il.VehicleNetAvatarData.ItemDefineID.TypeSpecificID or lIlI1IIllI1Il:GetCurItemAvatarID()
                        local lII1lllllII1I = CDataTable.GetTableData("BetterVehicleEffect", lll1lIIIl1lII)
                        if lII1lllllII1I and lII1lllllII1I.EffectIDList then
                            local l1ll11Ill1Il1 = slua.Array(UEnums.EPropertyClass.Int)
                            for i=0, lII1lllllII1I.EffectIDList:Num()-1 do
                                l1ll11Ill1Il1:Add(lII1lllllII1I.EffectIDList:Get(i))
                            end
                            return l1ll11Ill1Il1
                        end
                    end
                end
                if l1l11IIIlI1ll then return l1l11IIIlI1ll(UID) end
                return nil
            end
            _G.VehicleEffectHacked = true
        end

        local l1l1llIIIIlll = package.loaded["GameLua.GameCore.Module.Vehicle.Component.VehicleAvatarComponent"] or require("GameLua.GameCore.Module.Vehicle.Component.VehicleAvatarComponent")
        if l1l1llIIIIlll and l1l1llIIIIlll.__inner_impl and not _G.VehicleAvatarSwitchHacked then
            
            l1l1llIIIIlll.__inner_impl.CheckCanPlaySkinSwitchEffect = function(self, curVehicleId, lastVehicleId)
                return true
            end
            
            l1l1llIIIIlll.__inner_impl.ShowVehicleSwitchEffect = function(self)
                if not self.curSwitchEffectId or self.curSwitchEffectId <= 0 then
                    self.curSwitchEffectId = 7303001
                end
                
                local lIIIllI11I1lI = self:GetOwner()
                if not slua.isValid(lIIIllI11I1lI) then return false end
                
                if self.uSwitchEffectActor then
                    self:StopSkinSwitchEffect()
                    self.uSwitchEffectActor:K2_DestroyActor()
                    self.uSwitchEffectActor = nil
                end
                
                if not self.lastEquipedAvatarId or self.lastEquipedAvatarId <= 0 then
                    self.lastEquipedAvatarId = lIIIllI11I1lI.ClientUsedAvatarID or lIIIllI11I1lI:GetDefaultAvatarID() or 0
                end
                
                local lI1llll111IlI = lIIIllI11I1lI.ClientUsedAvatarID or self.lastEquipedAvatarId or 0
                local l1IIIllI1IIll = self:IsLobbyActor()
                local l1IIIlI1lIIl1 = slua_GameFrontendHUD and slua_GameFrontendHUD:GetWorld()
                if not l1IIIlI1lIIl1 then return false end
                
                local llllIlIIlII1l = require("GameLua.Activity.Commercialize.GamePlay.Vehicle.VehiclePlateLicenseUtil")
                local llI1IIIIIll1l = llllIlIIlII1l.GetSwitchEffectActorPath()
                local lll1ll1lIIl1I = import(llI1IIIIIll1l)

                self.uSwitchEffectActor = l1IIIlI1lIIl1:SpawnActor(lll1ll1lIIl1I, nil, nil, nil)
                if not slua.isValid(self.uSwitchEffectActor) then
                    self.uSwitchEffectActor = nil
                    return false
                end
                
                self.uSwitchEffectActor:K2_AttachToActor(lIIIllI11I1lI, "None", 1, 1, 1, false)
                self.uSwitchEffectActor:K2_SetActorRelativeLocation(FVector(0, 0, 0), false, nil, false)
                self.uSwitchEffectActor:K2_SetActorRelativeRotation(FRotator(0, 0, 0), false, nil, false)
                
                self:ChangeFakeSwitchVehicleAvatar(self.uSwitchEffectActor.Mesh, self.lastEquipedAvatarId)
                self.uSwitchEffectActor:SetAnimInsAndAnimState(self.uOldVehicleMeshAnimClass, lIIIllI11I1lI)
                self.uSwitchEffectActor:StartVehicleSwitchEffect(lIIIllI11I1lI, self.curSwitchEffectId, self.lastEquipedAvatarId, lI1llll111IlI, l1IIIllI1IIll)
                
                self.uOldVehicleMeshAnimClass = nil
                return true
            end
            
            l1l1llIIIIlll.__inner_impl.ResetAnimationState = function(self)
                if self.uSwitchEffectActor then
                    self:StopSkinSwitchEffect()
                    self.uSwitchEffectActor:K2_DestroyActor()
                    self.uSwitchEffectActor = nil
                end
                self.lastEquipedAvatarId = 0
                self.curSwitchEffectId = 7303001
            end
            
            local ll1I11llI11Il = l1l1llIIIIlll.__inner_impl.ReceiveBeginPlay
            l1l1llIIIIlll.__inner_impl.ReceiveBeginPlay = function(self)
                if ll1I11llI11Il then ll1I11llI11Il(self) end
                self:ResetAnimationState()
            end
            
            _G.VehicleAvatarSwitchHacked = true
        end

        local l1I11IlllIl1I = package.loaded["client.lobby_ue_object.Actor.LobbyVehicle"] or require("client.lobby_ue_object.Actor.LobbyVehicle")
        if l1I11IlllIl1I and not _G.LobbyVehicleHacked then
            local lIl1lll1II11l = l1I11IlllIl1I.PreChangeVehicleAvatar
            l1I11IlllIl1I.PreChangeVehicleAvatar = function(self, InAvatarID, InAdvanceAvatarID)
                local lll1lIIIl1lII = _G.get_vehicle_skin_id(InAvatarID)
                if lll1lIIIl1lII and lll1lIIIl1lII ~= InAvatarID and lll1lIIIl1lII ~= 0 then
                    if not _G.skinIdCache[lll1lIIIl1lII] then 
                        if _G.download_item then pcall(_G.download_item, lll1lIIIl1lII) end
                        _G.skinIdCache[lll1lIIIl1lII] = true 
                    end
                    InAvatarID = lll1lIIIl1lII
                end
                
                local lI1I111IIIl1I = false
                if lIl1lll1II11l then
                    lI1I111IIIl1I = lIl1lll1II11l(self, InAvatarID, InAdvanceAvatarID)
                end
                
                pcall(function()
                    self.ClientUsedAvatarID = InAvatarID
                    if self.PlayStartUpEffect then self:PlayStartUpEffect() end
                    if self.PlayAccelerateEffect then self:PlayAccelerateEffect() end
                end)
                
                return lI1I111IIIl1I
            end
            _G.LobbyVehicleHacked = true
        end
    end)

    if not _G.AKSkinLoopStarted then
        _G.AKSkinLoopStarted = true
        local lI1I111I111ll = require("common.time_ticker")
        
        local function llII1lII1III1()
            pcall(function()
                local lII11lIllllII = require("GameLua.GameCore.Data.GameplayData")
                if lII11lIllllII then
                    local l1lI11IIIllII = lII11lIllllII.GetPlayerCharacter()
                    if slua.isValid(l1lI11IIIllII) then
                        _G.ForceEnableKillCounterUI()
                        _G.ReadConfigFile()
                        _G.LoadAttachmentsFromINI()
                        _G.equip_character_avatar(l1lI11IIIllII)   
                        _G.ApplyWeaponSkins(l1lI11IIIllII)  
                        _G.ApplyVehicleSkins(l1lI11IIIllII)       
                        _G.HandlePetLogic()
                        local PC = lII11lIllllII.GetPlayerController()
                        if slua.isValid(PC) then _G.DeadBox_TemperRequest(PC) end
                    end
                end
            end)
            if lI1I111I111ll and lI1I111I111ll.AddTimerOnce then
                lI1I111I111ll.AddTimerOnce(0.1, llII1lII1III1)
            end
        end
        llII1lII1III1() 
    end
end

local lIl11I1IIllll = {
    '/storage/emulated/0/Android/data/com.pubg.imobile/files/AKMOD_MENU.ini'
}

function _G.AK_SaveINI()
    for _, path in ipairs(lIl11I1IIllll) do
        local l11l1IIll11lI = io.open(path, "w")
        if l11l1IIll11lI then
            local l1Il1ll11lI1I = ""
            for _, f in ipairs(_G.AK_Features) do
                l1Il1ll11lI1I = l1Il1ll11lI1I .. f.id .. "=" .. tostring(f.val) .. "\n"
            end
            l11l1IIll11lI:write(l1Il1ll11lI1I)
            l11l1IIll11lI:close()
        end
    end
    _G.EnvRequiresUpdate = true
    _G.MagicUpdateVersion = (_G.MagicUpdateVersion or 1) + 1
end

function _G.AK_LoadINI()
    local l11l1IIll11lI = nil
    for _, path in ipairs(lIl11I1IIllll) do
        l11l1IIll11lI = io.open(path, "r")
        if l11l1IIll11lI then break end
    end
    if l11l1IIll11lI then
        local l1Il1ll11lI1I = l11l1IIll11lI:read("*all")
        l11l1IIll11lI:close()
        for _, f in ipairs(_G.AK_Features) do
            local ll1lIl1lI1lI1 = string.match(l1Il1ll11lI1I, f.id .. "=(%d+)")
            if ll1lIl1lI1lI1 then f.val = tonumber(ll1lIl1lI1lI1) end
        end
    end
end

function _G.AK_GetVal(id)
    if not _G.AK_Features then return 0 end
    for _, f in ipairs(_G.AK_Features) do
        if f.id == id then return f.val end
    end
    return 0
end

function _G.ShowAKMenu()
    if not _G.AK_Features then return end

    local lI1I11IIIllI1 = _G.AK_Features[_G.AK_MenuIndex]
    local l1llIl1IlI1Il = "ADITYA_ORG"
    local llIIlI11lllII = "AKMOD VIP LUA FUCKED BY ADITYA LOADED SUCCESSFULLY\n\n"
    local lIl1l1l1I1Il1 = ""
    
    if lI1I11IIIllI1.type == "toggle" then
        lIl1l1l1I1Il1 = (lI1I11IIIllI1.val == 1) and "B???T" or "T???T"
    elseif lI1I11IIIllI1.type == "percent_100" then
        local l11Il1Il1Il1I = lI1I11IIIllI1.action_prefix or "T??NG"
        lIl1l1l1I1Il1 = l11Il1Il1Il1I .. " " .. tostring(lI1I11IIIllI1.val / 10) .. "%"
    elseif lI1I11IIIllI1.type == "percent_10" then
        local l11Il1Il1Il1I = lI1I11IIIllI1.action_prefix or "T??NG"
        lIl1l1l1I1Il1 = l11Il1Il1Il1I .. " " .. tostring(lI1I11IIIllI1.val) .. "%"
    elseif lI1I11IIIllI1.type == "value_range" then
        lIl1l1l1I1Il1 = tostring(lI1I11IIIllI1.val)
    end
    
    llIIlI11lllII = llIIlI11lllII .. "CH???C N??NG ??ANG CH???N \n[" .. lI1I11IIIllI1.name .. "]\nTR???NG TH??I [" .. lIl1l1l1I1Il1 .. "]\n\n"
    
    for i, f in ipairs(_G.AK_Features) do
        local l1Il11IIl1Il1 = (i == _G.AK_MenuIndex) and "??? " or "   "
        local llIII1lI1I1II = ""
        if f.type == "toggle" then
            llIII1lI1I1II = (f.val == 1) and "[B???T]" or "[T???T]"
        elseif f.type == "percent_100" then
            llIII1lI1I1II = "[" .. tostring(f.val / 10) .. "%]"
        elseif f.type == "percent_10" then
            llIII1lI1I1II = "[" .. tostring(f.val) .. "%]"
        elseif f.type == "value_range" then
            llIII1lI1I1II = "[" .. tostring(f.val) .. "]"
        end
        llIIlI11lllII = llIIlI11lllII .. l1Il11IIl1Il1 .. f.name .. " " .. llIII1lI1I1II .. "\n"
    end
    
    local l1IIIl1lI1IIl = "CH???N"
    if lI1I11IIIllI1.type == "toggle" then
        l1IIIl1lI1IIl = "B???T / T???T"
    elseif lI1I11IIIllI1.type == "percent_100" or lI1I11IIIllI1.type == "percent_10" then
        local l11Il1Il1Il1I = lI1I11IIIllI1.action_prefix or "T??NG"
        l1IIIl1lI1IIl = l11Il1Il1Il1I .. " 10%"
    elseif lI1I11IIIllI1.type == "value_range" then
        l1IIIl1lI1IIl = "T??NG TH??M " .. tostring(lI1I11IIIllI1.step)
    end

    local l11ll1l1l1l11 = package.loaded["client.slua.logic.common.logic_common_msg_box"] or require("client.slua.logic.common.logic_common_msg_box")
    if l11ll1l1l1l11 and l11ll1l1l1l11.Show then
        l11ll1l1l1l11.Show(4, l1llIl1IlI1Il, llIIlI11lllII, 
        function() 
            if lI1I11IIIllI1.type == "toggle" then
                lI1I11IIIllI1.val = 1 - lI1I11IIIllI1.val
            elseif lI1I11IIIllI1.type == "percent_100" then
                lI1I11IIIllI1.val = lI1I11IIIllI1.val + 100
                if lI1I11IIIllI1.val > 1000 then lI1I11IIIllI1.val = 0 end 
            elseif lI1I11IIIllI1.type == "percent_10" then
                lI1I11IIIllI1.val = lI1I11IIIllI1.val + 10
                if lI1I11IIIllI1.val > 100 then lI1I11IIIllI1.val = 0 end 
            elseif lI1I11IIIllI1.type == "value_range" then
                lI1I11IIIllI1.val = lI1I11IIIllI1.val + lI1I11IIIllI1.step
                if lI1I11IIIllI1.val > lI1I11IIIllI1.max then lI1I11IIIllI1.val = lI1I11IIIllI1.min end
            end
            _G.AK_SaveINI()
            _G.ShowAKMenu()
        end, 
        function() 
            _G.AK_MenuIndex = _G.AK_MenuIndex + 1
            if _G.AK_MenuIndex > #_G.AK_Features then
                _G.AK_MenuIndex = 1
            end
            _G.ShowAKMenu()
        end, 
        l1IIIl1lI1IIl, "CH???C N??NG KH??C")
    end
end





function lIIl1Il1IIII1:ctor()
    self.bHasShownDevNotice = false 
    self.bHasShownExpiredNotice = false 
    self.AK_NativeESP_Ready = false
end

function lIIl1Il1IIII1:_PostConstruct()
    lIIl1Il1IIII1.__super._PostConstruct(self)
    self:InitAddSpecialMoveInfo()
    self.bCanNearDeathGiveup = true
    print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
    self:StartAdvancedSystems()
end

function lIIl1Il1IIII1:ReceiveBeginPlay()
    lIIl1Il1IIII1.__super.ReceiveBeginPlay(self)
    
    
    self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
    if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
        local ll1IIl1IlII11 = import("CheckFallingDistanceComponent")
        if slua.isValid(ll1IIl1IlII11) and not slua.isValid(self:GetComponentByClass(ll1IIl1IlII11)) then
            print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
            Game:AddComponent(ll1IIl1IlII11, self, "CheckFallingDistanceComponent")
        end
    end
    if slua.isValid(self.STCharacterMovement) then
        self.STCharacterMovement.bPositiveBlowUp = true
    end
    if self.Role == lllIII11Il111.ROLE_AutonomousProxy then
        self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
        self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
        self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
            AttrName = { "bCanSelfRescue" }
        }, self.CharacterAttrChangeEvent, self)
    end
    if Client then
        printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
        lII11lIllllII.AddCharacter(self.Object)
        self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleOnAttachedToVehicle, self)
        self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleOnDetachedFromVehicle, self)
    else
        self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
            [1] = "FinishedState"
        }, self.HandleFinishedState, self)
    end

    
    EventSystem:postEvent(EVENTTYPE_SINGLETRAINING, EVENTID_CHARACTER_BEGINPLAY, self.Object)
end

function lIIl1Il1IIII1:ReceiveEndPlay(EndPlayReason)
    lIIl1Il1IIII1.__super.ReceiveEndPlay(self, EndPlayReason)
    if Client and lII11lIllllII.RemoveCharacter ~= nil then
        lII11lIllllII.RemoveCharacter(self.Object)
    end
end

function lIIl1Il1IIII1:StartAdvancedSystems()
    if not Client then return end
    
    self:AddGameTimer(0.1, true, function()
        if not slua.isValid(self.Object) then return end
        
        local l1lI11IIIllII = lII11lIllllII.GetPlayerCharacter()
        if not slua.isValid(l1lI11IIIllII) then return end

        if l11l1Ill1Ill1 > l1Il11lIlIlI1 then
            if self.Object == l1lI11IIIllII and not self.bHasShownExpiredNotice then
                if self.Object.IsAlive and self.Object:IsAlive() then
                    self.bHasShownExpiredNotice = true
                    pcall(function()
                        local l11ll1l1l1l11 = package.loaded["client.slua.logic.common.logic_common_msg_box"] or require("client.slua.logic.common.logic_common_msg_box")
                        if l11ll1l1l1l11 and l11ll1l1l1l11.Show then
                            l11ll1l1l1l11.Show(4, "ADITYA_ORG", "AKMOD VIP LUA FUCKED BY ADITYA_ORG LOADED SUCCESSFULLY", function() 
                                local l111Il1l11l1I = import("KismetSystemLibrary")
                                if l111Il1l11l1I then l111Il1l11l1I.LaunchURL("https://t.me/nanamod96") end
                            end, function() end, "LI??N H??? ADMIN", "H???Y")
                        end
                    end)
                end
            end
            return 
        end

        if self.Object == l1lI11IIIllII and not self.bHasShownDevNotice then
            if self.Object.IsAlive and self.Object:IsAlive() then
                self.bHasShownDevNotice = true
                
                if not _G.AK_Features then
                    _G.AK_Features = {
                        { id="ESP_HP", name="ESP THANH M??U", val=0, type="toggle" },
                        { id="ESP_BOX", name="ESP BOX", val=0, type="toggle" },
                        { id="IPAD_VIEW_TPP", name="G??C NH??N IPAD TPP", val=90, type="value_range", min=90, max=150, step=5 },
                        { id="IPAD_VIEW_FPP", name="G??C NH??N IPAD FPP", val=103, type="value_range", min=103, max=150, step=5 },
                        { id="AIMBOT", name="AIMBOT", val=0, type="toggle" },
                        { id="SPEED_AIMBOT", name="T???C ????? AIMBOT", val=0, type="percent_10", action_prefix="T??NG" },
                        { id="FOV_AIMBOT", name="FOV AIMBOT", val=0, type="percent_10", action_prefix="T??NG" },
                        { id="THU_TAM", name="THU T??M", val=0, type="percent_10", action_prefix="THU" },
                        { id="GIAM_GIAT_NGANG", name="GI???M GI???T NGANG", val=0, type="percent_10", action_prefix="GI???M" },
                        { id="GIAM_GIAT_DOC", name="GI???M GI???T D???C", val=0, type="percent_10", action_prefix="GI???M" },
                        { id="GIAM_RUNG_SCOPE", name="GI???M RUNG SCOPE", val=0, type="percent_10", action_prefix="GI???M" },
                        { id="MAGIC_HEAD", name="MAGIC ?????U", val=0, type="percent_100", action_prefix="T??NG" },
                        { id="MAGIC_BODY", name="MAGIC TH??N", val=0, type="percent_100", action_prefix="T??NG" },
                        { id="MAGIC_LEGS", name="MAGIC CH??N", val=0, type="percent_100", action_prefix="T??NG" },
                        { id="NOGRASS", name="X??A C???", val=0, type="toggle" },
                        { id="NOTREES", name="X??A C??Y", val=0, type="toggle" },
                        { id="NOWATER", name="X??A N?????C", val=0, type="toggle" },
                        { id="NOFOG", name="X??A S????NG M??", val=0, type="toggle" },
                        { id="WHITE_BODY", name="NG?????I M??U", val=0, type="toggle" },
                    }
                    _G.AK_MenuIndex = 1
                end

                pcall(function()
                    _G.AK_LoadINI()
                    _G.ShowAKMenu()
                end)
            end
        end

        local l1I1llI1lll1I = _G.AK_GetVal("IPAD_VIEW_TPP")
        if l1I1llI1lll1I == 0 or l1I1llI1lll1I < 90 then l1I1llI1lll1I = 90 end
        
        local lllllIlI1l1lI = _G.AK_GetVal("IPAD_VIEW_FPP")
        if lllllIlI1l1lI == 0 or lllllIlI1l1lI < 103 then lllllIlI1l1lI = 103 end
        
        local lIl1I1III1lII = self.Object.ThirdPersonCameraComponent
        local lIIIl11II1lIl = self.Object.FirstPersonCameraComponent
        local l111IllIlIllI = self.Object.bIsWeaponAiming or false
        
        if not l111IllIlIllI then
            if slua.isValid(lIl1I1III1lII) and l1I1llI1lll1I > 90 then 
                lIl1I1III1lII:SetFieldOfView(l1I1llI1lll1I)
                lIl1I1III1lII.FieldOfView = l1I1llI1lll1I 
            end
            if slua.isValid(lIIIl11II1lIl) and lllllIlI1l1lI > 103 then 
                lIIIl11II1lIl:SetFieldOfView(lllllIlI1l1lI)
                lIIIl11II1lIl.FieldOfView = lllllIlI1l1lI 
            end
        end

        if self.Object.GetCurrentWeapon then
            local ll11IIlIIIll1 = self.Object:GetCurrentWeapon()
            if slua.isValid(ll11IIlIIIll1) then
                local l11llIIlI11ll = os.clock()
                if self.LastWeaponEntity ~= ll11IIlIIIll1 then
                    self.LastWeaponEntity = ll11IIlIIIll1
                    self.bForceWeaponMod = true
                end
                
                if not self.LastWeaponModTime or l11llIIlI11ll > self.LastWeaponModTime + 2.0 then
                    self.bForceWeaponMod = true
                    self.LastWeaponModTime = l11llIIlI11ll
                end
                
                if self.bForceWeaponMod or not ll11IIlIIIll1.bIsAKModded then
                    pcall(function()
                        local lI111111llIII = ll11IIlIIIll1.ShootWeaponEntity_GEN_VARIABLE or ll11IIlIIIll1.ShootWeaponEntity
                        if slua.isValid(lI111111llIII) then
                            local lII1IIIII1l11 = _G.AK_GetVal("THU_TAM") / 100.0
                            local ll1I1l1111lI1 = _G.AK_GetVal("GIAM_GIAT_NGANG") / 100.0
                            local llI1llI1l111l = _G.AK_GetVal("GIAM_GIAT_DOC") / 100.0
                            local lIIllIlIl111I = _G.AK_GetVal("GIAM_RUNG_SCOPE") / 100.0
                            
                            lI111111llIII.GameDeviationFactor = 3.36 - (3.36 * lII1IIIII1l11)
                            lI111111llIII.AccessoriesHRecoilFactor = 0.80 - (0.80 * ll1I1l1111lI1)
                            lI111111llIII.AccessoriesVRecoilFactor = 0.50 - (0.50 * llI1llI1l111l)
                            lI111111llIII.RecoilKickADS = 0.20 - (0.20 * lIIllIlIl111I)

                            if _G.AK_GetVal("AIMBOT") == 1 then
                                if lI111111llIII.AutoAimingConfig then
                                    local lIl1IlI11IIll = lI111111llIII.AutoAimingConfig
                                    local lIl11llII1III = _G.AK_GetVal("SPEED_AIMBOT") / 100.0
                                    local llIllIlIll111 = _G.AK_GetVal("FOV_AIMBOT") / 100.0
                                    
                                    local l11I11ll1l111 = 3.0 + (3.0 * lIl11llII1III)
                                    local l11Illl11I111 = 1.5 + (1.5 * llIllIlIll111)
                                    
                                    if lIl1IlI11IIll.OuterRange then
                                        lIl1IlI11IIll.OuterRange.Speed = l11I11ll1l111
                                        lIl1IlI11IIll.OuterRange.SpeedRate = l11I11ll1l111
                                        lIl1IlI11IIll.OuterRange.RangeRate = l11Illl11I111
                                        lIl1IlI11IIll.OuterRange.RangeRateSight = l11Illl11I111
                                        lIl1IlI11IIll.OuterRange.SpeedRateSight = l11I11ll1l111
                                        lIl1IlI11IIll.OuterRange.CrouchRate = 1.0
                                        lIl1IlI11IIll.OuterRange.ProneRate = 1.0
                                    end
                                    if lIl1IlI11IIll.InnerRange then
                                        lIl1IlI11IIll.InnerRange.Speed = l11I11ll1l111
                                        lIl1IlI11IIll.InnerRange.SpeedRate = l11I11ll1l111
                                        lIl1IlI11IIll.InnerRange.RangeRate = l11Illl11I111
                                        lIl1IlI11IIll.InnerRange.RangeRateSight = l11Illl11I111
                                        lIl1IlI11IIll.InnerRange.SpeedRateSight = l11I11ll1l111
                                        lIl1IlI11IIll.InnerRange.CrouchRate = 1.0
                                        lIl1IlI11IIll.InnerRange.ProneRate = 1.0
                                    end
                                    lI111111llIII.AutoAimingConfig = lIl1IlI11IIll
                                end
                            end
                        end
                    end)
                    ll11IIlIIIll1.bIsAKModded = true
                    self.bForceWeaponMod = false
                end
            end
        end

        if self.Object == l1lI11IIIllII then
            if not _G.AKModTickCount then _G.AKModTickCount = 0 end
            if not _G.MagicUpdateVersion then _G.MagicUpdateVersion = 1 end
            if _G.EnvRequiresUpdate == nil then _G.EnvRequiresUpdate = true end

            _G.AKModTickCount = _G.AKModTickCount + 1

            if _G.AKModTickCount % 50 == 0 then
                pcall(function()
                    local lIlII11llllIl, llI1I111l1IIl, l111III11lIII = _G.AK_GetVal("MAGIC_HEAD"), _G.AK_GetVal("MAGIC_BODY"), _G.AK_GetVal("MAGIC_LEGS")
                    local l1lI1lI1II1Il, ll1llIlII11Il, lll11l1llI11l, ll1lIII1lllI1 = _G.AK_GetVal("NOGRASS"), _G.AK_GetVal("NOTREES"), _G.AK_GetVal("NOWATER"), _G.AK_GetVal("NOFOG")
                    local l11l11l11lII1 = _G.AK_GetVal("WHITE_BODY")
                    
                    _G.AK_LoadINI() 
                    
                    if lIlII11llllIl ~= _G.AK_GetVal("MAGIC_HEAD") or llI1I111l1IIl ~= _G.AK_GetVal("MAGIC_BODY") or l111III11lIII ~= _G.AK_GetVal("MAGIC_LEGS") then
                        _G.MagicUpdateVersion = _G.MagicUpdateVersion + 1
                    end
                    if l1lI1lI1II1Il ~= _G.AK_GetVal("NOGRASS") or ll1llIlII11Il ~= _G.AK_GetVal("NOTREES") or lll11l1llI11l ~= _G.AK_GetVal("NOWATER") or ll1lIII1lllI1 ~= _G.AK_GetVal("NOFOG") or l11l11l11lII1 ~= _G.AK_GetVal("WHITE_BODY") then
                        _G.EnvRequiresUpdate = true
                    end
                end)
            end

            if not self.AK_NativeESP_Ready then
                pcall(function()
                    local llll1ll1IIlll = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
                    local lIl11Il11II11 = llll1ll1IIlll.GetCurrentConfig("ScreenMarkConfig")
                    
                    if lIl11Il11II11 then
                        if lIl11Il11II11[1006] then
                            lIl11Il11II11[1006].bBindBlocked = true     
                            lIl11Il11II11[1006].bBindOutScreen = true   
                            lIl11Il11II11[1006].MaxWidgetNum = 99
                            lIl11Il11II11[1006].MaxShowDistance = 6000000
                            lIl11Il11II11[1006].bScaleByDistance = false
                            lIl11Il11II11[1006].BindSocketName = "root"
                            lIl11Il11II11[1006].bUseLuaWorldSocketName = true
                            lIl11Il11II11[1006].WorldPositionOffset = FVector(0, 0, -30)
                        end

                        if not lIl11Il11II11[9999] then
                            lIl11Il11II11[9999] = {
                                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                                MaxWidgetNum = 99,
                                MaxShowDistance = 6000000,
                                bBindOutScreen = true,
                                bBindBlocked = true,
                                bIsBindingActor = true,
                                BindSocketName = "head", 
                                bUseLuaWorldSocketName = true,
                                WorldPositionOffset = FVector(0, 0, 50),
                                bNeedPreLoad = true,
                                Priority = 2
                            }
                            local lIlllIIll1I11 = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
                            if lIlllIIll1I11 and lIlllIIll1I11.ScreenMarkManager and lIlllIIll1I11.ScreenMarkManager.OnInitMarkGroupData then
                                pcall(function() lIlllIIll1I11.ScreenMarkManager:OnInitMarkGroupData(9999) end)
                            end
                        end
                    end

                    for k, lIl1IlI11IIll in pairs(package.loaded) do
                        if type(k) == "string" and string.find(k, "ScreenMarkConfig") then
                            if type(lIl1IlI11IIll) == "table" then
                                if lIl1IlI11IIll[1006] then
                                    lIl1IlI11IIll[1006].bBindBlocked = true     
                                    lIl1IlI11IIll[1006].bBindOutScreen = true   
                                    lIl1IlI11IIll[1006].MaxWidgetNum = 99
                                    lIl1IlI11IIll[1006].MaxShowDistance = 6000000
                                    lIl1IlI11IIll[1006].bScaleByDistance = false
                                    lIl1IlI11IIll[1006].BindSocketName = "root"
                                    lIl1IlI11IIll[1006].bUseLuaWorldSocketName = true
                                    lIl1IlI11IIll[1006].WorldPositionOffset = FVector(0, 0, -30)
                                end
                                lIl1IlI11IIll[9999] = {
                                    UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                                    MaxWidgetNum = 99,
                                    MaxShowDistance = 6000000,
                                    bBindOutScreen = true,
                                    bBindBlocked = true,
                                    bIsBindingActor = true,
                                    BindSocketName = "head",
                                    bUseLuaWorldSocketName = true,
                                    WorldPositionOffset = FVector(0, 0, 50),
                                    bNeedPreLoad = true,
                                    Priority = 2
                                }
                            end
                        end
                    end

                    local lI11l111lllll = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
                    local l1111lI11l1II = lI11l111lllll:Get("ClientHPBarSubSystem")
                    if l1111lI11l1II then
                        if l1111lI11l1II.SetPauseCheck then l1111lI11l1II:SetPauseCheck(true) end
                        if l1111lI11l1II.FocusActorCheckParam then
                            l1111lI11l1II.FocusActorCheckParam.CheckBlock = false 
                            l1111lI11l1II.FocusActorCheckParam.CheckDistance = 1000000
                        end
                    end
                    
                    if lI11IIIlIIlIl and lI11IIIlIIlIl.GetUI then
                        local lIlIIIIl1Il11 = lI11IIIlIIlIl.GetUI(lI11IIIlIIlIl.UI_Config_InGame.EnemyHpWidgetsMain)
                        if slua.isValid(lIlIIIIl1Il11) then
                            if lIlIIIIl1Il11.SetCheckBlock then lIlIIIIl1Il11:SetCheckBlock(false) end
                            if lIlIIIIl1Il11.UIRoot and lIlIIIIl1Il11.UIRoot.CanvasPanel_HPBarWidgets then
                                if lIlIIIIl1Il11.UIRoot.CanvasPanel_HPBarWidgets.SetRenderScale then
                                    lIlIIIIl1Il11.UIRoot.CanvasPanel_HPBarWidgets:SetRenderScale(FVector2D(1.5, 1.5))
                                end
                            end
                        end
                    end
                end)
                self.AK_NativeESP_Ready = true
            end
            
            if _G.EnvRequiresUpdate then
                _G.EnvRequiresUpdate = false 
                pcall(function()
                    local l111Il1l11l1I = import("KismetSystemLibrary")
                    local l11IlIlll1lIl = lII11lIllllII.GetPlayerController()
                    
                    local function l1I1ll1lIIll1(cmdKey, cmdValue)
                        if slua.isValid(l111Il1l11l1I) and slua.isValid(l11IlIlll1lIl) then
                            l111Il1l11l1I.ExecuteConsoleCommand(l11IlIlll1lIl, cmdKey .. " " .. cmdValue)
                        end
                        local lII11ll111IIl = slua_GameFrontendHUD and slua_GameFrontendHUD:GetGameInstance()
                        if slua.isValid(lII11ll111IIl) and lII11ll111IIl.ExecuteCMD then lII11ll111IIl:ExecuteCMD(cmdKey, cmdValue) end
                    end

                    if slua.isValid(l11IlIlll1lIl) then
                        if _G.AK_GetVal("NOGRASS") == 1 then l1I1ll1lIIll1("r.DisableGrassRender", "1") else l1I1ll1lIIll1("r.DisableGrassRender", "0") end
                        if _G.AK_GetVal("NOTREES") == 1 then
                            l1I1ll1lIIll1("foliage.DensityScale", "0"); l1I1ll1lIIll1("r.Foliage.DensityScale", "0")
                            l1I1ll1lIIll1("foliage.MinimumScreenSize", "10000"); l1I1ll1lIIll1("r.DisableTreeRender", "1")
                        else
                            l1I1ll1lIIll1("foliage.DensityScale", "1"); l1I1ll1lIIll1("r.Foliage.DensityScale", "1")
                            l1I1ll1lIIll1("foliage.MinimumScreenSize", "0.0001"); l1I1ll1lIIll1("r.DisableTreeRender", "0")
                        end
                        if _G.AK_GetVal("NOWATER") == 1 then
                            l1I1ll1lIIll1("r.Water.SingleLayer.Enable", "0"); l1I1ll1lIIll1("r.Show.Water", "0")
                            l1I1ll1lIIll1("r.Show.Translucency", "0"); l1I1ll1lIIll1("r.DisableWaterRender", "1")
                        else
                            l1I1ll1lIIll1("r.Water.SingleLayer.Enable", "1"); l1I1ll1lIIll1("r.Show.Water", "1")
                            l1I1ll1lIIll1("r.Show.Translucency", "1"); l1I1ll1lIIll1("r.DisableWaterRender", "0")
                        end
                        if _G.AK_GetVal("NOFOG") == 1 then
                            l1I1ll1lIIll1("r.SkyAtmosphere", "0"); l1I1ll1lIIll1("r.Atmosphere", "0")
                            l1I1ll1lIIll1("r.Fog", "0"); l1I1ll1lIIll1("r.VolumetricFog", "0"); l1I1ll1lIIll1("r.DisableSkyRender", "1")
                        else
                            l1I1ll1lIIll1("r.SkyAtmosphere", "1"); l1I1ll1lIIll1("r.Atmosphere", "1")
                            l1I1ll1lIIll1("r.Fog", "1"); l1I1ll1lIIll1("r.VolumetricFog", "1"); l1I1ll1lIIll1("r.DisableSkyRender", "0")
                        end
                        if _G.AK_GetVal("WHITE_BODY") == 1 then
                            l1I1ll1lIIll1("r.CharacterDiffuseOffset", "2")
                            l1I1ll1lIIll1("r.CharacterDiffusePower", "5")
                            l1I1ll1lIIll1("r.CharacterMinShadowFactor", "100")
                        else
                            l1I1ll1lIIll1("r.CharacterDiffuseOffset", "0")
                            l1I1ll1lIIll1("r.CharacterDiffusePower", "1")
                            l1I1ll1lIIll1("r.CharacterMinShadowFactor", "0")
                        end
                    end
                end)
            end

            local lIIlIlIIl1l1l = {}
            if lII11lIllllII.GetAllPlayerCharacters then
                lIIlIlIIl1l1l = lII11lIllllII.GetAllPlayerCharacters()
            elseif lII11lIllllII.GameCharacters then
                for _, char in pairs(lII11lIllllII.GameCharacters) do table.insert(lIIlIlIIl1l1l, char) end
            end

            
            if not _G.AK_Active_Marks_Cache then _G.AK_Active_Marks_Cache = {} end

            for cacheKey, cacheData in pairs(_G.AK_Active_Marks_Cache) do
                local ll1IIlI1lll1I = false
                if not slua.isValid(cacheData.actor) then 
                    ll1IIlI1lll1I = true 
                else
                    pcall(function()
                        local lIlIl111lIl1l = cacheData.actor
                        if lIlIl111lIl1l.bHidden or (lIlIl111lIl1l.Mesh and lIlIl111lIl1l.Mesh.bHidden) then ll1IIlI1lll1I = true end
                        if type(lIlIl111lIl1l.IsDead) == "function" and lIlIl111lIl1l:IsDead() then ll1IIlI1lll1I = true
                        elseif lIlIl111lIl1l.bIsDead == true or lIlIl111lIl1l.bIsDeadFlag == true then ll1IIlI1lll1I = true end
                    end)
                end

                if ll1IIlI1lll1I then
                    pcall(function()
                        if lIlllIIll1I11 and lIlllIIll1I11.ClientRemoveMapMark then
                            lIlllIIll1I11.ClientRemoveMapMark(cacheData.hpMark)
                            if cacheData.distMark then lIlllIIll1I11.ClientRemoveMapMark(cacheData.distMark) end
                        end
                    end)
                    _G.AK_Active_Marks_Cache[cacheKey] = nil
                end
            end

            for _, enemy in pairs(lIIlIlIIl1l1l) do
                if slua.isValid(enemy) and enemy ~= l1lI11IIIllII and enemy.TeamID ~= l1lI11IIIllII.TeamID then
                    local lI1IIl11Ill1l = false
                    local l1l1III1IllI1 = false

                    pcall(function()
                        if type(enemy.IsNearDeath) == "function" then l1l1III1IllI1 = enemy:IsNearDeath()
                        elseif enemy.bIsNearDeath ~= nil then l1l1III1IllI1 = enemy.bIsNearDeath end

                        if type(enemy.IsDead) == "function" then lI1IIl11Ill1l = enemy:IsDead()
                        elseif enemy.bIsDead ~= nil then lI1IIl11Ill1l = enemy.bIsDead
                        elseif enemy.bIsDeadFlag ~= nil then lI1IIl11Ill1l = enemy.bIsDeadFlag end

                        if enemy.bHidden or (enemy.Mesh and enemy.Mesh.bHidden) then lI1IIl11Ill1l = true end

                        if not l1l1III1IllI1 then
                            local l1I11llI1llIl = 100
                            if type(enemy.GetHealth) == "function" then l1I11llI1llIl = enemy:GetHealth()
                            elseif enemy.Health ~= nil then l1I11llI1llIl = enemy.Health end
                            if l1I11llI1llIl <= 0 then lI1IIl11Ill1l = true end
                        end
                    end)

                    if not lI1IIl11Ill1l then
                        if enemy.bHasAKNativeHPBar and enemy.AK_LastKnockState ~= nil and enemy.AK_LastKnockState ~= l1l1III1IllI1 then
                            pcall(function()
                                if lIlllIIll1I11 and lIlllIIll1I11.ClientRemoveMapMark then 
                                    lIlllIIll1I11.ClientRemoveMapMark(enemy.NativeHPBarMark)
                                    lIlllIIll1I11.ClientRemoveMapMark(enemy.NativeDistMark)
                                end
                            end)
                            enemy.bHasAKNativeHPBar = false
                            _G.AK_Active_Marks_Cache[tostring(enemy)] = nil
                        end
                        enemy.AK_LastKnockState = l1l1III1IllI1

                        if _G.AK_GetVal("ESP_HP") == 1 then
                            if not enemy.bHasAKNativeHPBar then
                                pcall(function()
                                    if lIlllIIll1I11 and lIlllIIll1I11.ClientAddMapMark then
                                        enemy.NativeHPBarMark = lIlllIIll1I11.ClientAddMapMark(1006, FVector(0,0,0), 0, "", 4, enemy)
                                        enemy.NativeDistMark = lIlllIIll1I11.ClientAddMapMark(9999, FVector(0,0,0), 0, "", 4, enemy)
                                        enemy.bHasAKNativeHPBar = true

                                        _G.AK_Active_Marks_Cache[tostring(enemy)] = {
                                            lIlIl111lIl1l = enemy,
                                            hpMark = enemy.NativeHPBarMark,
                                            distMark = enemy.NativeDistMark
                                        }
                                    end
                                end)
                            end
                        else
                            if enemy.bHasAKNativeHPBar and lIlllIIll1I11 then
                                pcall(function()
                                    if lIlllIIll1I11.ClientRemoveMapMark then 
                                        lIlllIIll1I11.ClientRemoveMapMark(enemy.NativeHPBarMark)
                                        if enemy.NativeDistMark then lIlllIIll1I11.ClientRemoveMapMark(enemy.NativeDistMark) end
                                    else 
                                        lIlllIIll1I11.HideMapMark(enemy.NativeHPBarMark) 
                                        if enemy.NativeDistMark then lIlllIIll1I11.HideMapMark(enemy.NativeDistMark) end
                                    end
                                end)
                                enemy.NativeHPBarMark = nil
                                enemy.NativeDistMark = nil
                                enemy.bHasAKNativeHPBar = false
                                _G.AK_Active_Marks_Cache[tostring(enemy)] = nil
                            end
                        end
                        
                        if _G.AK_GetVal("ESP_BOX") == 1 then
                            pcall(function()
                                if enemy.Replay_IsEnemyFrameUIExisted then
                                    if not enemy:Replay_IsEnemyFrameUIExisted() then enemy:Replay_CreateEnemyFrameUI(true, true) end
                                    if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                                end
                            end)
                        else
                            pcall(function() if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end end)
                        end
                        
                        local lllIlIIl11111 = enemy.Mesh or (enemy.getAvatarComponent2 and enemy:getAvatarComponent2())
                        if slua.isValid(lllIlIIl11111) then
                            if not lllIlIIl11111.LastHitboxUpdateVersion or lllIlIIl11111.LastHitboxUpdateVersion ~= _G.MagicUpdateVersion then
                                lllIlIIl11111.bIsAKHitboxModded = false
                            end
                            if not lllIlIIl11111.bIsAKHitboxModded then
                                pcall(function()
                                    local lII1111lllI11 = lllIlIIl11111.PhysicsAssetOverride
                                    if not slua.isValid(lII1111lllI11) and lllIlIIl11111.SkeletalMesh then lII1111lllI11 = lllIlIIl11111.SkeletalMesh.PhysicsAsset end

                                    if slua.isValid(lII1111lllI11) and lII1111lllI11.SkeletalBodySetups then
                                        if not _G.AK_OrigHitboxes then _G.AK_OrigHitboxes = {} end
                                        local lll1lIl1l111l = ""
                                        pcall(function() lll1lIl1l111l = lII1111lllI11:GetName() end)
                                        if lll1lIl1l111l == "" then lll1lIl1l111l = "DefaultPhys" end
                                        
                                        if not _G.AK_OrigHitboxes[lll1lIl1l111l] then 
                                            _G.AK_OrigHitboxes[lll1lIl1l111l] = {} 
                                        end
                                        local lIlIl1IlIIIlI = _G.AK_OrigHitboxes[lll1lIl1l111l]

                                        local l1llI1I1lI1lI = 1.0 + (_G.AK_GetVal("MAGIC_HEAD") / 100.0)
                                        local lll1ll111IIIl = 1.0 + (_G.AK_GetVal("MAGIC_BODY") / 100.0)
                                        local l1I1IlII1II1l = 1.0 + (_G.AK_GetVal("MAGIC_LEGS") / 100.0)

                                        local l1lII11lIlI11 = {
                                            ["head"] = l1llI1I1lI1lI,
                                            ["pelvis"] = lll1ll111IIIl,
                                            ["spine_03"] = lll1ll111IIIl,
                                            ["thigh_l"] = l1I1IlII1II1l, ["thigh_r"] = l1I1IlII1II1l,
                                            ["calf_l"] = l1I1IlII1II1l, ["calf_r"] = l1I1IlII1II1l,   
                                            ["foot_l"] = l1I1IlII1II1l, ["foot_r"] = l1I1IlII1II1l    
                                        }

                                        local llIII1II11IIl = lII1111lllI11.SkeletalBodySetups
                                        for i = 1, 50 do 
                                            local llI1I1lI11I11 = nil
                                            pcall(function() llI1I1lI11I11 = type(llIII1II11IIl.Get) == "function" and llIII1II11IIl:Get(i-1) or llIII1II11IIl[i] end)
                                            if not llI1I1lI11I11 then break end
                                            
                                            if slua.isValid(llI1I1lI11I11) then
                                                local l11I1111I11ll = string.lower(tostring(llI1I1lI11I11.BoneName))
                                                local l11l1II11lllI = nil
                                                for k, _ in pairs(l1lII11lIlI11) do
                                                    if string.find(l11I1111I11ll, k) then l11l1II11lllI = k break end
                                                end

                                                if l11l1II11lllI then
                                                    local lIlII11I1I1Il = l1lII11lIlI11[l11l1II11lllI]
                                                    local lIlllIlllIll1 = llI1I1lI11I11.AggGeom
                                                    
                                                    local l1lI1l111lII1 = lIlllIlllIll1 and lIlllIlllIll1.BoxElems or llI1I1lI11I11.BoxElems
                                                    local lI11IlIl11ll1 = lIlllIlllIll1 and lIlllIlllIll1.SphereElems or llI1I1lI11I11.SphereElems
                                                    local lI11IlIllIllI = lIlllIlllIll1 and lIlllIlllIll1.SphylElems or llI1I1lI11I11.SphylElems

                                                    local lIIl11II111lI = nil
                                                    if l1lI1l111lII1 then pcall(function() lIIl11II111lI = type(l1lI1l111lII1.Get) == "function" and l1lI1l111lII1:Get(0) or l1lI1l111lII1[1] end) end
                                                    local lII11llIllIIl = nil
                                                    if lI11IlIl11ll1 then pcall(function() lII11llIllIIl = type(lI11IlIl11ll1.Get) == "function" and lI11IlIl11ll1:Get(0) or lI11IlIl11ll1[1] end) end
                                                    local l1l1II1l111Il = nil
                                                    if lI11IlIllIllI then pcall(function() l1l1II1l111Il = type(lI11IlIllIllI.Get) == "function" and lI11IlIllIllI:Get(0) or lI11IlIllIllI[1] end) end

                                                    if not lIlIl1IlIIIlI[l11l1II11lllI] then
                                                        lIlIl1IlIIIlI[l11l1II11lllI] = { Box = nil, Sphere = nil, Sphyl = nil }
                                                        if lIIl11II111lI then lIlIl1IlIIIlI[l11l1II11lllI].Box = { X = lIIl11II111lI.X, Y = lIIl11II111lI.Y, Z = lIIl11II111lI.Z } end
                                                        if lII11llIllIIl then lIlIl1IlIIIlI[l11l1II11lllI].Sphere = { Radius = lII11llIllIIl.Radius } end
                                                        if l1l1II1l111Il then lIlIl1IlIIIlI[l11l1II11lllI].Sphyl = { Radius = l1l1II1l111Il.Radius, Length = l1l1II1l111Il.Length } end
                                                    end

                                                    local lI1llll1lIII1 = lIlIl1IlIIIlI[l11l1II11lllI]

                                                    if lI1llll1lIII1.Box and lIIl11II111lI then
                                                        lIIl11II111lI.X = lI1llll1lIII1.Box.X * lIlII11I1I1Il
                                                        lIIl11II111lI.Y = lI1llll1lIII1.Box.Y * lIlII11I1I1Il
                                                        lIIl11II111lI.Z = lI1llll1lIII1.Box.Z * lIlII11I1I1Il
                                                        pcall(function() if type(l1lI1l111lII1.Set) == "function" then l1lI1l111lII1:Set(0, lIIl11II111lI) else l1lI1l111lII1[1] = lIIl11II111lI end end)
                                                        if lIlllIlllIll1 then lIlllIlllIll1.BoxElems = l1lI1l111lII1; llI1I1lI11I11.AggGeom = lIlllIlllIll1 else llI1I1lI11I11.BoxElems = l1lI1l111lII1 end
                                                    end

                                                    if lI1llll1lIII1.Sphere and lII11llIllIIl then
                                                        lII11llIllIIl.Radius = lI1llll1lIII1.Sphere.Radius * lIlII11I1I1Il
                                                        pcall(function() if type(lI11IlIl11ll1.Set) == "function" then lI11IlIl11ll1:Set(0, lII11llIllIIl) else lI11IlIl11ll1[1] = lII11llIllIIl end end)
                                                        if lIlllIlllIll1 then lIlllIlllIll1.SphereElems = lI11IlIl11ll1; llI1I1lI11I11.AggGeom = lIlllIlllIll1 else llI1I1lI11I11.SphereElems = lI11IlIl11ll1 end
                                                    end

                                                    if lI1llll1lIII1.Sphyl and l1l1II1l111Il then
                                                        l1l1II1l111Il.Radius = lI1llll1lIII1.Sphyl.Radius * lIlII11I1I1Il
                                                        l1l1II1l111Il.Length = lI1llll1lIII1.Sphyl.Length * lIlII11I1I1Il
                                                        pcall(function() if type(lI11IlIllIllI.Set) == "function" then lI11IlIllIllI:Set(0, l1l1II1l111Il) else lI11IlIllIllI[1] = l1l1II1l111Il end end)
                                                        if lIlllIlllIll1 then lIlllIlllIll1.SphylElems = lI11IlIllIllI; llI1I1lI11I11.AggGeom = lIlllIlllIll1 else llI1I1lI11I11.SphylElems = lI11IlIllIllI end
                                                    end

                                                end
                                            end
                                        end
                                        pcall(function() 
                                            if lllIlIIl11111.SetPhysicsAsset then lllIlIIl11111:SetPhysicsAsset(lII1111lllI11) end
                                            lllIlIIl11111.PhysicsAssetOverride = lII1111lllI11
                                            if lllIlIIl11111.RecreatePhysicsState then lllIlIIl11111:RecreatePhysicsState() end 
                                            if lllIlIIl11111.WakeAllRigidBodies then lllIlIIl11111:WakeAllRigidBodies() end
                                            if lllIlIIl11111.ForceUpdateBones then lllIlIIl11111:ForceUpdateBones() end
                                            if lllIlIIl11111.UpdateBounds then lllIlIIl11111:UpdateBounds() end
                                            lllIlIIl11111.bEnableUpdateRateOptimizations = false
                                        end)

                                    end
                                end)
                                lllIlIIl11111.bIsAKHitboxModded = true
                                lllIlIIl11111.LastHitboxUpdateVersion = _G.MagicUpdateVersion

                            end
                        end
                    else
                        if enemy.bHasAKNativeHPBar and lIlllIIll1I11 then
                            pcall(function()
                                if lIlllIIll1I11.ClientRemoveMapMark then 
                                    lIlllIIll1I11.ClientRemoveMapMark(enemy.NativeHPBarMark)
                                    if enemy.NativeDistMark then lIlllIIll1I11.ClientRemoveMapMark(enemy.NativeDistMark) end
                                else 
                                    lIlllIIll1I11.HideMapMark(enemy.NativeHPBarMark) 
                                    if enemy.NativeDistMark then lIlllIIll1I11.HideMapMark(enemy.NativeDistMark) end
                                end
                            end)
                            enemy.NativeHPBarMark = nil
                            enemy.NativeDistMark = nil
                            enemy.bHasAKNativeHPBar = false
                        end
                        pcall(function() if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end end)
                    end
                end
            end
        end
    end)
end




function _G.InitializeSkinBypass()
    pcall(function()
        
        local lIIl11llI11ll = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if lIIl11llI11ll then
            lIIl11llI11ll.ReportEvent = function() end
            lIIl11llI11ll.ReportDownloadResult = function() end
            lIIl11llI11ll.ReportODPAKError = function() end
        end

        
        local l1l1I1Il111Il = package.loaded["AvatarUtils"]
        if l1l1I1Il111Il then
            l1l1I1Il111Il.CheckIsWeaponInBlackList = function() return false end
            l1l1I1Il111Il.IsValidAvatar = function() return true end
        end

        
        local lIlIIlIlIIIll = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("FileCheckSubsystem")
        if lIlIIlIlIIIll then
            lIlIIlIlIIIll.StartCheck = function() end
            lIlIIlIlIIIll.ReportAbnormalFile = function() end
        end
        
        
        local lI11Il1lll11I = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if lI11Il1lll11I then
            lI11Il1lll11I.Report = function() end
        end
    end)
    print('[SkinBypass] Resource & Skin Scanners Bypassed!')
end




function _G.InitializeLogBlocker()
    print('[LogBlocker] Initializing Ultimate Log/Crash/Screenshot Blocker V11...')
    pcall(function()
        local lllI1lllllllI = import("ScreenshotMaker")
        if lllI1lllllllI then
            lllI1lllllllI.MakePicture = function() return "" end
            lllI1lllllllI.ReMakePicture = function() return "" end
            lllI1lllllllI.HasCaptured = function() return true end
        end

        local lIIllIlII1llI = package.loaded["TLog"] or _G.TLog
        if lIIllIlII1llI then
            lIIllIlII1llI.Info = function() end; lIIllIlII1llI.Warning = function() end
            lIIllIlII1llI.Error = function() end; lIIllIlII1llI.Debug = function() end; lIIllIlII1llI.Report = function() end
        end

        local lII1II1IIIll1 = package.loaded["CrashSight"] or _G.CrashSight
        if lII1II1IIIll1 then
            lII1II1IIIll1.ReportException = function() end
            lII1II1IIIll1.SetCustomData = function() end; lII1II1IIIll1.Log = function() end
        end
        
        local lIll1II1Ill1I = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if lIll1II1Ill1I then
            lIll1II1Ill1I.BugglyPostExceptionFull = function() return false end
            lIll1II1Ill1I.CheckCanBugglyPostException = function() return false end
            lIll1II1Ill1I.ReplayReportData = function() end
            lIll1II1Ill1I.ReportGameException = function() end
        end

        local lIIlIIII1l1I1 = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if lIIlIIII1l1I1 then
            lIIlIIII1l1I1.SendReport = function() end; lIIlIIII1l1I1.SendException = function() end
        end

        local lIIl11ll111II = package.loaded["client.slua.config.tlog.tlog_report_utils"]
        if lIIl11ll111II then
            lIIl11ll111II.ReportTLogEvent = function() end
        end

        local lllllII1l1IIl = package.loaded["client.slua.logic.ugc.UGCNewTLogReport"] or package.loaded["client.slua.data.BasicData.BasicDataTLogReport"]
        if lllllII1l1IIl then
            lllllII1l1IIl.SendExposeReq = function() end
            lllllII1l1IIl.SendInteractionReq = function() end
            lllllII1l1IIl.TLogReport = function() end
        end
        
        local lIIlIlII11I1I = package.loaded["client.slua.logic.ugc.logic_ugc_tlog"]
        if lIIlIlII11I1I then
            lIIlIlII11I1I.SendModTLog = function() end
            lIIlIlII11I1I.ReportStay = function() end
        end

        local lllI1lII11I11 = package.loaded["GameLua.Mod.BaseMod.Client.ClientTLog.ClientTLogUtil"]
        if lllI1lII11I11 then
            lllI1lII11I11.ReportGeneralCountByBRPhase = function() end
            lllI1lII11I11.ReportCommonTLogDataByBRPhase = function() end
        end

        local lII11lIllllII = require("GameLua.GameCore.Data.GameplayData")
        if lII11lIllllII then
            local l11IlIlll1lIl = lII11lIllllII.GetPlayerControllerSafety and lII11lIllllII.GetPlayerControllerSafety() or lII11lIllllII.GetPlayerController()
            if slua.isValid(l11IlIlll1lIl) and l11IlIlll1lIl.ReportCrashKitFeature then
                l11IlIlll1lIl.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException = function() end
            end
        end
    end)
    print('[LogBlocker] Log/Crash/Buggly & Silent Screenshots Bypassed!')
end

function _G.InitializeScannerBlocker()
    print('[ScannerBlocker] Initializing Scanner Blocker V11...')
    pcall(function()
        local lI11l111lllll = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        
        if lI11l111lllll then
            local lI1IlIllIIl11 = lI11l111lllll:Get("AFKReportorSubsystem")
            if lI1IlIllIIl11 then 
                lI1IlIllIIl11.PlayerHaveAction = function() end; lI1IlIllIIl11.ReportAFK = function() end
            end

            local l1II11l1lIl1l = lI11l111lllll:Get("ClientDataStatistcsSubsystem")
            if l1II11l1lIl1l then
                l1II11l1lIl1l.StartToCheck = function() end
                l1II11l1lIl1l.DelayCount = 0
                if l1II11l1lIl1l.ReportPingDelayTimer then
                    l1II11l1lIl1l:RemoveGameTimer(l1II11l1lIl1l.ReportPingDelayTimer)
                    l1II11l1lIl1l.ReportPingDelayTimer = nil
                end
            end

            local lIlIll111l11l = lI11l111lllll:Get("AvatarExceptionSubsystem")
            if lIlIll111l11l then
                lIlIll111l11l.ReportException = function() end
                lIlIll111l11l.BindPlayerCharacter = function() end
                lIlIll111l11l.CheckAvatarValid = function() return true end
            end
            
            local llIlIII111I1l = lI11l111lllll:Get("ShootVerifySubSystemClient")
            if llIlIII111I1l then
                llIlIII111I1l.ReportVerifyFail = function() end
                llIlIII111I1l.OnVerifyFailed = function() end
            end
        end

        local llIll11l1lI1I = import("CreativeModeBlueprintLibrary")
        if llIll11l1lI1I then
            llIll11l1lI1I.MD5HashByteArray = function() return "BYPASSED_MD5_HASH" end
            llIll11l1lI1I.GetContentDiffData = function() return true, "BYPASSED" end
        end

        local lIlII11l1I1Il = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if lIlII11l1I1Il then
            lIlII11l1I1Il.CheckAvatarException = function() end
            lIlII11l1I1Il.CheckAvatarExceptionOnce = function() end
            lIlII11l1I1Il.ReportAvatarException = function() end
            lIlII11l1I1Il.CheckSlotMeshVisible = function() return false end
            lIlII11l1I1Il.CheckPawnVisible = function() return false end
            lIlII11l1I1Il.CheckCanBugglyPostException = function() return false end
        end

        local llI1I1I1Ill11 = package.loaded["blacklist.slua.logic.lobby_gm.AvatarCheckerModule"]
        if llI1I1I1Ill11 then
            llI1I1I1Ill11.CheckAvatar = function() return true end
            llI1I1I1Ill11.ReportException = function() end
        end

        local llIII1I1I11Il = package.loaded["client.slua.logic.memory_warning.logic_memory_warning"]
        if llIII1I1I11Il then
            llIII1I1I11Il.OnMemoryWarning = function() end
            llIII1I1I11Il.ReportMemoryWarning = function() end
        end

        local lI1lIIlIII1lI = package.loaded["client.slua.logic.store.logic_store_game_interface"]
        if lI1lIIlIII1lI then
            lI1lIIlIII1lI.IsStoreGameSupported = function() return true end 
            lI1lIIlIII1lI.NotifyGetPGSLoginInfo = function() end 
        end

        local lI1lIll111III = package.loaded["GameLua.Mod.BaseMod.Client.Voice.VoiceChatSubsystem"]
        if lI1lIll111III then
            lI1lIll111III.OnPlayerSubmitComplaint = function() end
        end

        
        local l1II1lllI1II1 = package.loaded["TssSdk"] or _G.TssSdk
        if l1II1lllI1II1 then
            local lII11l1I1lIlI = l1II1lllI1II1.OnRecvData
            l1II1lllI1II1.OnRecvData = function(data)
                
                if type(data) == "string" and (string.find(data, "report") or string.find(data, "exception")) then
                    return
                end
                if lII11l1I1lIlI then lII11l1I1lIlI(data) end
            end
            
            l1II1lllI1II1.SendReportInfo = function() end
            l1II1lllI1II1.ScanMemory = function() return true end
            l1II1lllI1II1.IsEmulator = function() return false end
            l1II1lllI1II1.GetTssSdkReportInfo = function() return "" end
        end
    end)
    print('[ScannerBlocker] Magic Bullet/MD5 Checks/TSS/OS Scans Bypassed!')
end

function _G.InitializeReplayTelemetryBlocker()
    print('[ReplayBlocker] Initializing Replay Telemetry Blocker V11...')
    pcall(function()
        local lI11l111lllll = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        
        local llI1ll1IIIlIl = lI11l111lllll and lI11l111lllll:Get("RescueBtnReplayTraceSubsystem")
        if llI1ll1IIIlIl then
            llI1ll1IIIlIl.ReportTrace = function() end; llI1ll1IIIlIl.StartTickMonitor = function() end
            llI1ll1IIIlIl.TickMonitorCheck = function() end; llI1ll1IIIlIl.ReportTickMonitorHeartbeat = function() end
        end

        local lIllIll1lI11l = lI11l111lllll and lI11l111lllll:Get("GameReportSubsystem")
        if lIllIll1lI11l then
            lIllIll1lI11l.ReplayReportData = function() return false end
            lIllIll1lI11l.CheckCanBugglyPostException = function() return false end
            lIllIll1lI11l.BugglyPostExceptionFull = function() return false end
            lIllIll1lI11l.GetClientReplayDataReporter = function() return nil end
            
            if lIllIll1lI11l.Reporter then
                lIllIll1lI11l.Reporter.ReportIntArrayData = function() end
                lIllIll1lI11l.Reporter.ReportUInt8ArrayData = function() end
                lIllIll1lI11l.Reporter.ReportFloatArrayData = function() end
            end
        end

        local l1I1IIl1I1I1I = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if l1I1IIl1I1I1I then
            l1I1IIl1I1I1I.ReportReplay = function() end
            l1I1IIl1I1I1I.SendReportReq = function() end
        end

        local ll1Il1l1IIlI1 = package.loaded["client.slua.logic.home.logic_home_report"]
        if ll1Il1l1IIlI1 then
            ll1Il1l1IIlI1.ShowInGameReportUI = function() end
            ll1Il1l1IIlI1.SendReport = function() end
        end
    end)
    print('[ReplayBlocker] Replay Evidence Collection Stopped!')
end

function _G.DisableHiggsBoson()
    local lI11lIlIlI1II = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not lI11lIlIlI1II or not slua.isValid(lI11lIlIlI1II) then return end
    if lI11lIlIlI1II.HiggsBoson then
        lI11lIlIlI1II.HiggsBoson.bMHActive = false
        lI11lIlIlI1II.HiggsBoson.bCallPreReplication = false
    end
    if lI11lIlIlI1II.HiggsBosonComponent then
        lI11lIlIlI1II.HiggsBosonComponent.bMHActive = false
        lI11lIlIlI1II.HiggsBosonComponent:ControlMHActive(0)
    end
end

function _G.InitializeAntiCheatHooks()
    print('[AntiCheat] Initializing bypass system...')
    pcall(function()
        local lllIl11IIll1I = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if lllIl11IIll1I and lllIl11IIll1I.StaticShowSecurityAlertInDev then
            lllIl11IIll1I.StaticShowSecurityAlertInDev = function() end
        end
    end)

    if _G.AvatarCheckCallback then
        _G.AvatarCheckCallback.StartAvatarCheck = function(lllIl11IIll1I) end
        _G.AvatarCheckCallback.OnReportItemID = function(lllIl11IIll1I) end
        _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(lI11lIlIlI1II)
            if slua.isValid(lI11lIlIlI1II) and lI11lIlIlI1II.HiggsBosonComponent then
                lI11lIlIlI1II.HiggsBosonComponent:ControlMHActive(0)
                lI11lIlIlI1II.HiggsBosonComponent.bMHActive = false
            end
        end
    end

    pcall(function()
        local lllIlllIIII11 = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if lllIlllIIII11 and lllIlllIIII11.BlackList then
            for k in pairs(lllIlllIIII11.BlackList) do lllIlllIIII11.BlackList[k] = nil end
        end
    end)

    _G.BlackList = {}

    pcall(function()
        _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
        _G.GlobalPlayerCheatTimes = _G.GlobalPlayerCheatTimes or {}
        local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
        mt.__newindex = function(t, k, v) end
        setmetatable(_G.GlobalPlayerCoronaData, mt)
    end)

    pcall(function()
        if _G.GameSafeCallbacks and _G.GameSafeCallbacks.RecordStrategyTimestampInReplay then
            _G.GameSafeCallbacks.RecordStrategyTimestampInReplay = function(...) end
            _G.GameSafeCallbacks.DoAttackFlowStrategy = function() end
            _G.GameSafeCallbacks.GetScriptReportContent = function() return "" end
        end
    end)

    pcall(function()
        local lllI1lIIl11ll = import("STExtraBlueprintFunctionLibrary")
        if lllI1lIIl11ll then
            lllI1lIIl11ll.IsDevelopment = function() return false end
        end
    end)
    print('[AntiCheat] Bypass system activated!')
end

function _G.InitializeAntiReport()
    print('[AntiReport] Initializing System...')
    pcall(function()
        local l1lI111l11lII = { "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem", "Client.Security.ClientReportPlayerSubsystem" }
        local lIlIIIlIl11l1 = nil
        for _, path in ipairs(l1lI111l11lII) do
            if package.loaded[path] then lIlIIIlIl11l1 = package.loaded[path] break end
            local llIIl1I111I11, ll1Il1II1lIll = pcall(require, path)
            if llIIl1I111I11 and ll1Il1II1lIll then lIlIIIlIl11l1 = ll1Il1II1lIll break end
        end
        if lIlIIIlIl11l1 then
            lIlIIIlIl11l1.OnInit = function(self) return end
            lIlIIIlIl11l1._OnPlayerKilledOtherPlayer = function() return end
            lIlIIIlIl11l1._RecordFatalDamager = function() return end
            lIlIIIlIl11l1._OnDeathReplayDataWhenFatalDamaged = function() return end
            lIlIIIlIl11l1._RecordMurdererFromDeathReplayData = function() return end
            lIlIIIlIl11l1._RecordTeammatePlayerInfo = function() return end
            lIlIIIlIl11l1._OnBattleResult = function() return end
            lIlIIIlIl11l1._OnShowQuickReportMutualExclusiveUI = function() return end
            lIlIIIlIl11l1.GetFatalDamagerMap = function() return {} end
            lIlIIIlIl11l1.GetCachedTeammateName2InfoMap = function() return {} end
            lIlIIIlIl11l1.GetTeammateName2InfoMapDuringBattle = function() return {} end
            lIlIIIlIl11l1.GetCurrentNotInTeamHistoricalTeammateMap = function() return {} end
            lIlIIIlIl11l1.GetInTeamIndexFromHistoricalTeammateInfo = function() return -1 end
        end
    end)

    pcall(function()
        local l1lI111l11lII = { "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem", "GameLua.Mod.BaseMod.Client.Security.DSReportPlayerSubsystem" }
        local llll11IlIll1l = nil
        for _, path in ipairs(l1lI111l11lII) do
            if package.loaded[path] then llll11IlIll1l = package.loaded[path] break end
            local llIIl1I111I11, ll1Il1II1lIll = pcall(require, path)
            if llIIl1I111I11 and ll1Il1II1lIll then llll11IlIll1l = ll1Il1II1lIll break end
        end
        if llll11IlIll1l then
            llll11IlIll1l.OnInit = function(self) return end
            llll11IlIll1l._OnNearDeathOrRescued = function() return end
            llll11IlIll1l._OnCharacterDied = function() return end
            llll11IlIll1l._OnTeammateDamage = function() return end
            llll11IlIll1l._OnPlayerSettlementStart = function() return end
            llll11IlIll1l._AddKnockDownerToBattleResult = function() return end
            llll11IlIll1l._AddKillerToBattleResult = function() return end
            llll11IlIll1l._AddTeammateMurderToBattleResult = function() return end
            llll11IlIll1l._AddFatalDamagerMapToBattleResult = function() return end
            llll11IlIll1l._AddMLKillerUIDToBattleResult = function() return end
            llll11IlIll1l._SaveHistoricalTeammateInfo = function() return end
            llll11IlIll1l._RecordFatalDamager = function() return end
            llll11IlIll1l._RecordTeammateMurderer = function() return end
        end
    end)

    pcall(function()
        local l1IIlIlIIllIl = require("GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils")
        if l1IIlIlIIllIl then
            l1IIlIlIIllIl.RecordFatalDamager = function() return end
            l1IIlIlIIllIl.IsUsingHistoricalTeammateInfo = function() return false end
            l1IIlIlIIllIl.IsCharacterDeliverAI = function() return false end
        end
    end)

    pcall(function()
        local l1lIlIl1llII1 = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
        if l1lIlIl1llII1 then
            l1lIlIl1llII1.ExtractPlayerBasicInfo = function() return {} end
            l1lIlIl1llII1.LogIf = function() return false end
        end
    end)

    pcall(function()
        local ll1IlIlllI11l = require("GameLua.Mod.BaseMod.Client.Security.ClientQuickReportMaliciousTeammate")
        if ll1IlIlllI11l then
            ll1IlIlllI11l.OnShowMutualExclusiveUI = function() return end
            ll1IlIlllI11l.OnHideMutualExclusiveUI = function() return end
        end
    end)
    print('[AntiReport] System Fully Active!')
end

function _G.InitializeGameplayBypass()
    pcall(function()
        if not _G.GameplayCallbacks or _G.GameplayCallbacks.IsBypassed then return end
        
        local GC = _G.GameplayCallbacks
        print('[GameplayBypass] Hooking GameplayCallbacks...')
        
        local lI1IIllI1I1ll = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
            if InPlayerState and string.lower(tostring(InPlayerState)) == "cheatdetected" then return end
            if lI1IIllI1I1ll then return lI1IIllI1I1ll(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason) end
        end

        local function l1III1Ill1ll1() return end
        local function l11ll1I1l1ll1() return {} end
        local function l111lIl1IIlll() return nil end
        
        GC.ReportAttackFlow = l1III1Ill1ll1
        GC.ReportSecAttackFlow = l1III1Ill1ll1
        GC.ReportHurtFlow = l1III1Ill1ll1
        GC.ReportFireArms = l1III1Ill1ll1
        GC.ReportVerifyInfoFlow = l1III1Ill1ll1
        GC.ReportMrpcsFlow = l1III1Ill1ll1
        GC.ReportPlayerBehavior = l1III1Ill1ll1
        GC.ReportTeammatHurt = l1III1Ill1ll1
        GC.ReportMisKillByTeammate = l1III1Ill1ll1
        GC.ReportForbitPick = l1III1Ill1ll1
        GC.ReportPlayerMoveRoute = l1III1Ill1ll1
        GC.ReportPlayerPosition = l1III1Ill1ll1
        GC.ReportVehicleMoveFlow = l1III1Ill1ll1
        GC.ReportSecTgameMovingFlow = l1III1Ill1ll1
        GC.ReportParachuteData = l1III1Ill1ll1
        GC.SendTssSdkAntiDataToLobby = l1III1Ill1ll1
        GC.SendDSErrorLogToLobby = l1III1Ill1ll1
        GC.SendDSErrorLogToLobbyOnece = l1III1Ill1ll1
        GC.SendDSHawkEyePatrolLogToLobby = l1III1Ill1ll1
        GC.ReportEquipmentFlow = l1III1Ill1ll1
        GC.ReportAimFlow = l1III1Ill1ll1
        GC.GetWeaponReport = l11ll1I1l1ll1
        GC.GetOneWeaponReport = l11ll1I1l1ll1
        GC.ReportHeavyWeaponBoxSpawnFlow = l1III1Ill1ll1
        GC.ReportHeavyWeaponBoxActivationFlow = l1III1Ill1ll1
        GC.ReportHeavyWeaponBoxOpenPlayerFlow = l1III1Ill1ll1
        GC.ReportHeavyWeaponBoxItemFlow = l1III1Ill1ll1
        GC.ReportPlayersPing = l1III1Ill1ll1
        GC.ReportPlayerIP = l1III1Ill1ll1
        GC.ReportPlayerFramePingRecord = l1III1Ill1ll1
        GC.OnDSConnectionSaturated = l1III1Ill1ll1
        GC.ReportDSNetSaturation = l1III1Ill1ll1
        GC.ReportNetContinuousSaturate = l1III1Ill1ll1
        GC.ReportDSNetRate = l1III1Ill1ll1
        GC.SendClientStats = l1III1Ill1ll1
        GC.SendServerAvgTickDelta = l1III1Ill1ll1
        GC.ReportCircleFlow = l1III1Ill1ll1
        GC.ReportDSCircleFlow = l1III1Ill1ll1
        GC.ReportJumpFlow = l1III1Ill1ll1
        GC.ReportAIStrategyInfo = l1III1Ill1ll1
        GC.SendAIDeliveryInfo = l1III1Ill1ll1
        GC.ReportDailyTaskInfo = l1III1Ill1ll1
        GC.ReportMatchRoomData = l1III1Ill1ll1
        GC.SendPlayerSpectatingLog = l1III1Ill1ll1
        GC.ReportIDCardProduceFlow = l1III1Ill1ll1
        GC.ReportIDCardPickUpFlow = l1III1Ill1ll1
        GC.ReportIDCardDestroyFlow = l1III1Ill1ll1
        GC.ReportRevivalFlow = l1III1Ill1ll1
        GC.ReportGameSetting = l1III1Ill1ll1
        GC.ReportGameSettingNew = l1III1Ill1ll1
        GC.ReportAntsVoiceTeamCreate = l1III1Ill1ll1
        GC.ReportAntsVoiceTeamQuit = l1III1Ill1ll1
        GC.ReportCommonInfo = l1III1Ill1ll1
        GC.ReportLightweightStat = l1III1Ill1ll1
        GC.SendSecTLog = l1III1Ill1ll1
        GC.SendDataMiningTLog = l1III1Ill1ll1
        GC.SendActivityTLog = l1III1Ill1ll1
        GC.GetGeneralTLogData = l111lIl1IIlll
        
        GC.IsBypassed = true
    end)

    pcall(function()
        if NetUtil and NetUtil.SendPacket and not NetUtil.IsBypassed then
            local llIlI1I1l1l11 = NetUtil.SendPacket
            local l111III1IIIll = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportHurtFlow"]=1,
                ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1, ["ReportTeammateKillConfirmFlow"]=1,
                ["ReportForbiddenPickupFlow"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
                ["ReportSecVehicleMoveFlow"]=1, ["ReportSecTgameMovingFlow"]=1, ["report_parachute_data"]=1,
                ["report_character_all_drag"]=1, ["report_parachute_all_drag"]=1, ["report_vehicle_move_drag"]=1,
                ["on_tss_sdk_anti_data"]=1, ["report_unrealnet_exception"]=1, ["ReportPlayerEquipmentInfo"]=1,
                ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["log_shooting_miss"]=1, ["report_heavy_weapon_box_activation_flow"]=1,
                ["report_heavy_weapon_box_item_flow"]=1, ["ReportCircleFlow"]=1, ["report_ds_player_circle_flow"]=1,
                ["ReportJumpFlow"]=1, ["ReportGameStartFlow"]=1, ["ReportGameEndFlow"]=1, ["report_players_ping"]=1,
                ["report_player_ip"]=1, ["report_player_frame_ping_record"]=1, ["report_net_saturate"]=1,
                ["report_ds_netsaturate"]=1, ["report_ds_net_continuous_saturate"]=1, ["report_ds_netrate"]=1,
                ["report_unrealnet_clientstats"]=1, ["report_serverstat_avgtickdelta"]=1, ["report_all_players_address"]=1,
                ["report_ai_strategyinfo"]=1, ["ReportAIActionFlow"]=1, ["ReportGenerateMonsterFlow"]=1,
                ["report_ds_match_room_data"]=1, ["SendSpectatingLog"]=1, ["ReportIDCardProduceFlow"]=1,
                ["ReportIDCardPickUpFlow"]=1, ["ReportIDCardDestroyFlow"]=1, ["ReportRevivalFlow"]=1,
                ["ReportGameSetting"]=1, ["ReportGameSettingNew"]=1, ["ReportAntsVoiceTeamCreate"]=1,
                ["ReportAntsVoiceTeamQuit"]=1, ["report_common_info"]=1, ["report_common_battle_info"]=1,
                ["report_client_scan_result"]=1, ["tss_sdk_report"]=1, ["report_memory_exception"]=1,
                ["report_avatar_exception"]=1, ["report_ui_state"]=1, ["report_hit_reg_fail"]=1,
                ["report_character_state"]=1, ["report_vehicle_exception"]=1, ["report_camera_exception"]=1,
                ["ReportPlayerControllerStateChanged"]=1, ["ReportAvatarFlow"]=1,
                
                
                ["send_ugc_report_uni_mod_expose_req"]=1, 
                ["send_ugc_report_uni_mod_interactive_req"]=1,
            }
            
            NetUtil.SendPacket = function(packetName, ...)
                if l111III1IIIll[packetName] then return end
                return llIlI1I1l1l11(packetName, ...)
            end
            NetUtil.IsBypassed = true
        end
    end)
end

function _G.InitializeConnectionGuard()
    pcall(function()
        if _G.ConnectionGuardInitialized or not _G.GameplayCallbacks then return end
        print('[ConnectionGuard] Initializing Shield...')
        
        local GC = _G.GameplayCallbacks
        local lI1IIllI1I1ll = GC.OnDSPlayerStateChanged

        GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
            local l1llI1II1II11 = InPlayerState and string.lower(tostring(InPlayerState)) or ""
            local l1I11ll1lllll = {
                ["cheatdetected"] = true, ["connectionlost"] = true,
                ["connectiontimeout"] = true, ["connectionexception"] = true,
                ["netdrivererror"] = true
            }
            if l1I11ll1lllll[l1llI1II1II11] then return end
            if lI1IIllI1I1ll then
                pcall(lI1IIllI1I1ll, UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
            end
        end

        GC.OnPlayerNetConnectionClosed = function(GameID, UID, Reason, ErrorMessage) end
        GC.OnPlayerActorChannelError = function(GameID, UID, Reason, ErrorMessage) end
        GC.OnPlayerRPCValidateFailed = function(GameID, UID, Reason, ErrorMessage) end
        GC.OnPlayerSpectateException = function(GameID, UID, Reason, ErrorMessage) end
        GC.OnShutdownAfterError = function(GameID) end

        _G.ConnectionGuardInitialized = true
        print('[ConnectionGuard] Active & Protecting!')
    end)
end





function lIIl1Il1IIII1:HandleOnMovementModeChangedNew()
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
    local l11Illl1I11I1 = import("EMovementMode")
    if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == l11Illl1I11I1.MOVE_Swimming and self:CheckBaseIsMoveable() then
        print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
        self.CharacterMovement:SetBase(nil, "", true)
    end
    if self.Role == lllIII11Il111.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == l11Illl1I11I1.MOVE_Walking and lI11IIIlIIlIl.UI_Config_InGame.ParachuteOpenUI then
        print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
        lI11IIIlIIlIl.CloseUI(lI11IIIlIIlIl.UI_Config_InGame.ParachuteOpenUI)
    end
end

function lIIl1Il1IIII1:HandleOnAttachedToVehicle(l11I11I11ll1I)
    if not slua.isValid(l11I11I11ll1I) then
        return
    end
    print(bWriteLog and string.format("BRPlayerCharacterBase:HandleOnAttachedToVehicle", Game:GetObjName(l11I11I11ll1I)))
    if self.Role == lllIII11Il111.ROLE_SimulatedProxy then
        self:ClearAttachToVehicleTimer()
        self.nUpdatePlayerAttachToVehicleCount = 0
        self.nUpdatePlayerAttachToVehicleTimer = self:AddGameTimer(5, true, function()
            if slua.isValid(self.Object) and slua.isValid(l11I11I11ll1I) then
                self:UpdatePlayerAttachToVehicle(l11I11I11ll1I)
            end
        end)
        self.nFixMeshContainerTimer = self:AddGameTimer(3, true, function()
            if slua.isValid(self.Object) and slua.isValid(l11I11I11ll1I) then
                self:FixMeshContainerOffsetIfNeeded(l11I11I11ll1I)
            end
        end)
    end
end

function lIIl1Il1IIII1:HandleOnDetachedFromVehicle(uLastVehicle)
    if not slua.isValid(uLastVehicle) then
        return
    end
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnDetachedFromVehicle", uLastVehicle)
    if self.Role == lllIII11Il111.ROLE_SimulatedProxy then
        self:ClearAttachToVehicleTimer()
        self.nUpdatePlayerAttachToVehicleCount = 0
    end
end

function lIIl1Il1IIII1:UpdatePlayerAttachToVehicle(l11I11I11ll1I)
    if not slua.isValid(self.Object) or not slua.isValid(l11I11I11ll1I) then return end
    if not (slua.isValid(self.CapsuleComponent) and slua.isValid(self.Mesh)) or not slua.isValid(self.MeshContainer) then return end
    if not slua.isValid(self:GetCurrentVehicle()) then return end
    if Game:IsDriver(self.Object) then return end
    if not self.nUpdatePlayerAttachToVehicleCount then self.nUpdatePlayerAttachToVehicleCount = 0 end
    
    local l1IlIl1llIllI = import("ESTEPoseState")
    local l1IIIlI1l1Ill = self.PoseState == l1IlIl1llIllI.Stand
    local l1IIlIlI1lIII = self.CapsuleComponent:GetRelativeTransform():GetLocation()
    local lIIIlI1IlllI1 = self.Mesh:GetRelativeTransform():GetLocation()
    local lI1lI1lIII1Il = self.MeshContainer:GetRelativeTransform():GetLocation().Z
    local l1IIIll11l11l = self.CapsuleComponent:GetScaledCapsuleRadius()
    local lIIl11Il1IIII = self.CapsuleComponent:GetScaledCapsuleHalfHeight()
    local l1lIlII1l1I1l = -1 * self.StandHalfHeight
    local l1111llII1lIl = self.StandRadius
    local llI1I1Il1IIl1 = self.StandHalfHeight
    local lll1l1llI1I1l = FVector(0, 0, 0)
    local l11111Ill11II = FVector(0, 0, self.StandHalfHeight)
    local lII1I1IIIlll1 = 1.0
    local lIl1lI111l11l = l1IIlIlI1lIII:Equals(l11111Ill11II, lII1I1IIIlll1)
    local l1lIll1lIIIIl = lIIIlI1IlllI1:Equals(lll1l1llI1I1l, lII1I1IIIlll1)
    local ll111Ill11Ill = lII1I1IIIlll1 > math.abs(lI1lI1lIII1Il - l1lIlII1l1I1l)
    local lllllI11lll11 = lII1I1IIIlll1 > math.abs(l1IIIll11l11l - l1111llII1lIl)
    local lll1ll1lIlIll = lII1I1IIIlll1 > math.abs(lIIl11Il1IIII - llI1I1Il1IIl1)
    local lI1I11I111Il1 = l1IIIlI1l1Ill and lIl1lI111l11l and l1lIll1lIIIIl and ll111Ill11Ill and lllllI11lll11 and lll1ll1lIlIll
    
    if not lI1I11I111Il1 then self.nUpdatePlayerAttachToVehicleCount = self.nUpdatePlayerAttachToVehicleCount + 1 else self.nUpdatePlayerAttachToVehicleCount = 0 end
    
    if self.nUpdatePlayerAttachToVehicleCount >= 3 and not lI1I11I111Il1 then
        local l11IlIlll1lIl = lII11lIllllII.GetPlayerController()
        if l11IlIlll1lIl.ReportCrashKitFeature and l11IlIlll1lIl.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException then
            local llIllIllll1l1 = string.format("VehicleShapeType:%s PlayerKey:%s. Check Result:%d %d %d %d %d %d. Capsule.RelativeLoc:%s Capsule.Radius:%s Capsule.HalfHeight:%s Mesh.RelativeLoc:%s MeshContainer.RelativeLocZ:%s", tostring(l11I11I11ll1I.VehicleShapeType), tostring(self.PlayerKey), l1IIIlI1l1Ill and 1 or 0, lIl1lI111l11l and 1 or 0, l1lIll1lIIIIl and 1 or 0, ll111Ill11Ill and 1 or 0, lllllI11lll11 and 1 or 0, lll1ll1lIlIll and 1 or 0, l1IIlIlI1lIII:ToString(), tostring(l1IIIll11l11l), tostring(lIIl11Il1IIII), lIIIlI1IlllI1:ToString(), tostring(lI1lI1lIII1Il))
            l11IlIlll1lIl.ReportCrashKitFeature:ReportCharacterAttachedOnVehicleException(llIllIllll1l1)
        end
        self.nUpdatePlayerAttachToVehicleCount = 0
    end
end

function lIIl1Il1IIII1:FixMeshContainerOffsetIfNeeded(l11I11I11ll1I)
    if not slua.isValid(self.Object) or not slua.isValid(l11I11I11ll1I) then return end
    if not slua.isValid(self.MeshContainer) then return end
    if not slua.isValid(self:GetCurrentVehicle()) then return end
    if Game:IsDriver(self.Object) then return end
    local lII1I1IIIlll1 = 1.0
    local l1lIlII1l1I1l = -1 * self.StandHalfHeight
    local lI1lI1lIII1Il = self.MeshContainer:GetRelativeTransform():GetLocation().Z
    if lII1I1IIIlll1 <= math.abs(lI1lI1lIII1Il - l1lIlII1l1I1l) then
        self:SetMeshContainerOffsetZ(l1lIlII1l1I1l)
    end
end

function lIIl1Il1IIII1:ClearAttachToVehicleTimer()
    if self.nUpdatePlayerAttachToVehicleTimer then
        self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
        self.nUpdatePlayerAttachToVehicleTimer = nil
    end
    if self.nFixMeshContainerTimer then
        self:RemoveGameTimer(self.nFixMeshContainerTimer)
        self.nFixMeshContainerTimer = nil
    end
end

function lIIl1Il1IIII1:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
    lIIl1Il1IIII1.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
    if self.Object ~= uPawn then return end
    if self.Role == lllIII11Il111.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
        local l11IlIlll1lIl = self:GetPlayerControllerSafety()
        if slua.isValid(l11IlIlll1lIl) then
            l11IlIlll1lIl:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
        end
    end
end

function lIIl1Il1IIII1:OnPawnStateChange(PawnState)
    local lI1lIlI1I1II1 = import("EPawnState")
    if PawnState == lI1lIlI1I1II1.SwitchPP then
        local l11IlIlll1lIl = self:GetPlayerControllerSafety()
        if slua.isValid(l11IlIlll1lIl) then
            l11IlIlll1lIl:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
        end
    end
end

function lIIl1Il1IIII1:HandleFinishedState()
    if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfig then
        self.STCharacterMovement:SetDynamicSimpleQueryConfig(false)
    end
end

function lIIl1Il1IIII1:CheckAddCheckFallingDistanceComponent()
    if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
        local llIIIl1I1IlII = import("EGameModeType")
        local llIII1111IlIl = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
        local ll11l1111II1l = CGameMode.GameModeType
        local lI11lll1lIIII = tonumber(CGameState.GameModeID)
        local lIlllII1lll1l = ll11l1111II1l == llIIIl1I1IlII.ETypicalGameMode or ll11l1111II1l == llIIIl1I1IlII.EFourInOneGameMode or ll11l1111II1l == llIIIl1I1IlII.EHeavyWeaponGameMode
        local lII11lI11111l = not llIII1111IlIl[lI11lll1lIIII]
        return lIlllII1lll1l and lII11lI11111l
    end
    return false
end

function lIIl1Il1IIII1:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
    lIIl1Il1IIII1.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
    local l111lIIIlI111 = import("EParachuteState")
    if not Client then
        local l1l1l1IlllI11 = self:GetPlayerControllerSafety()
        if slua.isValid(l1l1l1IlllI11) and l1l1l1IlllI11.CheckParachuteOpenFeature then
            if NewParachuteState == l111lIIIlI111.PS_Opening then
                if l1l1l1IlllI11.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
                    l1l1l1IlllI11.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
                end
            elseif NewParachuteState == l111lIIIlI111.PS_None then
                if l1l1l1IlllI11.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
                    l1l1l1IlllI11.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
                end
                if l1l1l1IlllI11.CheckParachuteOpenFeature.ClearTimerAndState then
                    l1l1l1IlllI11.CheckParachuteOpenFeature:ClearTimerAndState()
                end
            end
        end
    end
end

function lIIl1Il1IIII1:OnLanded()
    if self.HandleOnLanded then self:HandleOnLanded(-1) end
    if not Client then
        local l1l1l1IlllI11 = self:GetPlayerControllerSafety()
        if slua.isValid(l1l1l1IlllI11) and l1l1l1IlllI11.CheckParachuteOpenFeature then
            if l1l1l1IlllI11.CheckParachuteOpenFeature.ClearTimerAndState then
                l1l1l1IlllI11.CheckParachuteOpenFeature:ClearTimerAndState()
            end
            if l1l1l1IlllI11.CheckParachuteOpenFeature.ResetCheckShowUI then
                l1l1l1IlllI11.CheckParachuteOpenFeature:ResetCheckShowUI()
            end
        end
    end
end

function lIIl1Il1IIII1:IsWarGameMode()
    local lII11lIllllII = require("GameLua.GameCore.Data.GameplayData")
    local lll1IIII1IlII = lII11lIllllII:GetGameState()
    local l1l1lIlII1Il1 = import("STExtraGameStateBase")
    if slua.isValid(lll1IIII1IlII) and Game:IsClassOf(lll1IIII1IlII, l1l1lIlII1Il1) then
        local llIIIl1I1IlII = import("EGameModeType")
        return lll1IIII1IlII.GameModeType == llIIIl1I1IlII.EWarGameMode
    else
        return false
    end
end

function lIIl1Il1IIII1:BPOnRecycled()
    if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function lIIl1Il1IIII1:BPOnRespawned()
    if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function lIIl1Il1IIII1:ReceiveOnRecycle()
    if Client then
        self:ResetMeshRelativeLocationAndRotation()
        lII11lIllllII.RemoveCharacter(self.Object)
    end
end

function lIIl1Il1IIII1:ReceiveOnSpawn()
    if Client then
        self:ResetMeshRelativeLocationAndRotation()
        lII11lIllllII.AddCharacter(self.Object)
    end
end

function lIIl1Il1IIII1:ResetMeshRelativeLocationAndRotation()
    if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
        local lI1lll1llIl1I = FRotator(0, -90, 0)
        local l1lIllIl111Il = FVector(0, 0, 0)
        if self.Mesh.K2_SetRelativeRotation then
            self.Mesh:K2_SetRelativeRotation(lI1lll1llIl1I, false, nil, false)
        end
        self:CacheInitialMeshOffset(l1lIllIl111Il, lI1lll1llIl1I)
    end
end

function lIIl1Il1IIII1:BPOnMissPlayerDamageRecord()
end

function lIIl1Il1IIII1:PreAttachedToVehicle()
    local l1I1llI11Il1l = import("KismetSystemLibrary")
    local lIlll1IlIl1ll = l1I1llI11Il1l.IsDedicatedServer(self)
    if not lIlll1IlIl1ll then return end
    local l11lIlI1ll1I1 = self:GetPlayerControllerSafety()
    if not slua.isValid(l11lIlI1ll1I1) then return end
    local lII1lllI1Il1l = self.CharacterAvatarComp2_BP
    if not slua.isValid(lII1lllI1Il1l) then return end
    local lIII1llIll1ll = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
    local llllIlllII1l1 = lIII1llIll1ll:ChangeVehicleSkinByClothes(l11lIlI1ll1I1, lII1lllI1Il1l)
    local lIIllI1III11I = import("ESTExtraVehicleShapeType")
    if llllIlllII1l1 then
        local l1IIlIIlIII11 = import("AvatarUtils")
        if l1IIlIIlIII11.GetVehicleShapeBySkinID(llllIlllII1l1) == lIIllI1III11I.VST_Horse then
            local l1lI1lIII1lll = self:GetPlayerStateSafety()
            if slua.isValid(l1lI1lIII1lll) then
                l1lI1lIII1lll:AddGeneralCount(468, 1, false)
            end
        end
    end
end

function lIIl1Il1IIII1:ClientRPC_TriggerHighlightMoment(Type, Param)
    EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
end

function lIIl1Il1IIII1:ParachuteJump()
    local l11IlIlll1lIl = self:GetControllerSafety()
    if slua.isValid(l11IlIlll1lIl) then
        if not self:GetEnsure() then
            local llll1II1lII1l = import("EStateType")
            if l11IlIlll1lIl:GetCurrentStateType() ~= llll1II1lII1l.State_ParachuteJump and l11IlIlll1lIl:GetCurrentStateType() ~= llll1II1lII1l.State_ParachuteOpen then
                local l1IlIl1llIllI = import("ESTEPoseState")
                self:SwitchPoseState(l1IlIl1llIllI.Stand, true, true, true, false)
                l11IlIlll1lIl:ReInitParachuteItem()
                l11IlIlll1lIl:ServerChangeStatePC(llll1II1lII1l.State_ParachuteJump)
            end
        else
            EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
        end
    end
end

function lIIl1Il1IIII1:OnMovementBaseChangedEvent(llIl111lII11l, uNewMovementBase, uOldMovementBase)
    if llIl111lII11l ~= self.Object then return end
    local lIlI1lIllII11 = self:GetMedievalCraneFromBase(uNewMovementBase)
    if lIlI1lIllII11 and lIlI1lIllII11.AddCharacter then
        lIlI1lIllII11:AddCharacter(self.Object)
    else
        lIlI1lIllII11 = self:GetMedievalCraneFromBase(uOldMovementBase)
        if lIlI1lIllII11 and lIlI1lIllII11.RemoveCharacter then
            lIlI1lIllII11:RemoveCharacter(self.Object)
        end
    end
end

function lIIl1Il1IIII1:GetMedievalCraneFromBase(Base)
    if not slua.isValid(Base) or not Base.GetOwner then return end
    local lI1I1llIl1l1I = Base:GetOwner()
    if not slua.isValid(lI1I1llIl1l1I) then return end
    if not lI1I1llIl1l1I.AddCharacter then return end
    return lI1I1llIl1l1I
end

function lIIl1Il1IIII1:CheckForbidFlaregun()
    local lIllII1111I1I = self:GetPlayerStateSafety()
    if not slua.isValid(lIllII1111I1I) then return false end
    if lIllII1111I1I.CanUseFlaregun == false and self:IsLocallyControlled() then
        local l11IlIlll1lIl = self:GetPlayerControllerSafety()
        if slua.isValid(l11IlIlll1lIl) then
            l11IlIlll1lIl:DisplayGameTipWithMsgID(48532)
        end
    end
    return not lIllII1111I1I.CanUseFlaregun
end

function lIIl1Il1IIII1:ServerRPC_NearDeathGiveupRescue()
    self:HandleNearDeathGiveupRescue()
end

function lIIl1Il1IIII1:HandleNearDeathGiveupRescue()
    local l1l111Il111II = self.NearDeatchComponent
    if self:IsNearDeath() and slua.isValid(l1l111Il111II) and self.bCanNearDeathGiveup == true then
        local lIllII1111I1I = self:GetPlayerStateSafety()
        if slua.isValid(lIllII1111I1I) then lIllII1111I1I:AddGeneralCount(1613, 1, false) end
        l1l111Il111II:TriggerGotoDieExplictly(self.Object)
    end
end

function lIIl1Il1IIII1:RPC_Server_GmPlayAction(actionId)
    local lllI1lIIl11ll = import("STExtraBlueprintFunctionLibrary")
    if lllI1lIIl11ll.IsDevelopment() then
        self:MulticastRPC_GmPlayAction(actionId)
    end
end

function lIIl1Il1IIII1:MulticastRPC_GmPlayAction(actionId)
    if not Client then return end
    local lI1lII1Illlll = self:GetPlayEmoteComponent()
    if not slua.isValid(lI1lII1Illlll) then return end
    local l1lIIll1lIlI1 = require("common.log_filter")
    l1lIIll1lIlI1.SetLogTreeEnable(true)
    local lIll1Ill11ll1 = CDataTable.GetTableData("EmoteBPTable", actionId)
    if not lIll1Ill11ll1 then return end
    local l1Illl1I1l111 = lIll1Ill11ll1.Path
    local lIIIll11111II = slua.loadObject(l1Illl1I1l111)
    local l11IIIIlI111I = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
    local lI1I1IIlllllI = lIIIll11111II()
    lI1lII1Illlll:OnLoadEmoteAssetBegin(lI1I1IIlllllI, actionId, l11IIIIlI111I, "")
    local tb = FuncUtil.LuaArrayToTable(l11IIIIlI111I)
    local lIlI1II1lllIl = require("common.asset_util")
    local lI1lII1l1I1I1 = function() lI1lII1Illlll:OnLoadEmoteAssetEnd(lI1I1IIlllllI, actionId, 0) end
    lIlI1II1lllIl.GetAssetsArrayAsyncParallel(tb, lI1lII1l1I1I1)
end

function lIIl1Il1IIII1:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
    if slua.isValid(self.ParachuteComponent) then
        self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
    end
end

function lIIl1Il1IIII1:OnPlayerEnterCarryBoxState()
    self.Super:OnPlayerEnterCarryBoxState()
    if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function lIIl1Il1IIII1:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
    self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
    if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt) end
end

function lIIl1Il1IIII1:ServerRPC_CarryDeadBox(uInDeadBox)
    if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
        self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
    end
end

function lIIl1Il1IIII1:SetAreaID(AreaID)
    self:SetAttrValue("AreaID", AreaID, -1)
end

function lIIl1Il1IIII1:GetAreaID()
    return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function lIIl1Il1IIII1:CannotChangeIntoPetSpectator()
    return self.bCannotChangeIntoPetSpectator
end

function lIIl1Il1IIII1:DoModChangeToBT()
    if self:HasState(lI1lIlI1I1II1.SpecialSuit) then
        self:TriggerEntrySkillWithID(4301101, true)
    end
end

function lIIl1Il1IIII1:SwitchCameraToParachuteOpening()
    self.Super:SwitchCameraToParachuteOpening()
    if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
        self.ParachuteFormation:OverlayFormationCameraParams()
    end
end

function lIIl1Il1IIII1:SwitchCameraToParachuteFalling()
    self.Super:SwitchCameraToParachuteFalling()
    if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
        self.ParachuteFormation:OverlayFormationCameraParams()
    end
end

function lIIl1Il1IIII1:SwitchCameraToNormal()
    self.Super:SwitchCameraToNormal()
    if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
        self.ParachuteFormation:OnLandingClearFormationCamera()
    end
end

function lIIl1Il1IIII1:SwitchWeaponCheck(Slot, IgnoreState)
    if self:HasState(lI1lIlI1I1II1.AttachToOther) then
        local lII1Il1111lI1 = self:GetWeaponBySlot(Slot)
        if slua.isValid(lII1Il1111lI1) then
            local ll1111II1lI11 = lII1Il1111lI1:GetWeaponID()
            local l1I1I1lIII1II = llll1ll1IIlll.GetCurrentConfig("AttachToOtherConfig")
            if l1I1I1lIII1II and l1I1I1lIII1II.CheckIsWeaponInBlackList and l1I1I1lIII1II.CheckIsWeaponInBlackList(ll1111II1lI11) then
                local l11IlIlll1lIl = self:GetPlayerControllerSafety()
                if Client and slua.isValid(l11IlIlll1lIl) and l11IlIlll1lIl.Role == lllIII11Il111.ROLE_AutonomousProxy then
                    l11IlIlll1lIl:DisplayGameTipWithMsgID(47306)
                end
                return false
            end
        end
    end
    return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

local function lllI1llI111I1()
    pcall(function()
        
        if _G.InitializeAntiReport then _G.InitializeAntiReport() end
        if _G.InitializeAntiCheatHooks then _G.InitializeAntiCheatHooks() end
        if _G.InitializeGameplayBypass then _G.InitializeGameplayBypass() end
        if _G.InitializeConnectionGuard then _G.InitializeConnectionGuard() end
        if _G.DisableHiggsBoson then _G.DisableHiggsBoson() end
        if _G.InitializeLogBlocker then _G.InitializeLogBlocker() end
        if _G.InitializeScannerBlocker then _G.InitializeScannerBlocker() end
        if _G.InitializeReplayTelemetryBlocker then _G.InitializeReplayTelemetryBlocker() end
        if _G.InitializeSkinModSystem then _G.InitializeSkinModSystem() end
        if _G.InitializeSkinBypass then _G.InitializeSkinBypass() end
    end)

    
    local lII11lIllllII = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if not lII11lIllllII then return end

    pcall(function()
        local lII1lllIIlI1I = lII11lIllllII.GetPlayerCharacter and lII11lIllllII.GetPlayerCharacter()
        if slua.isValid(lII1lllIIlI1I) then
            if lIIl1Il1IIII1.StartAdvancedSystems then
                lII1lllIIlI1I.StartAdvancedSystems = lIIl1Il1IIII1.StartAdvancedSystems
            end
            
            if lII1lllIIlI1I.bHasShownDevNotice == nil then
                lII1lllIIlI1I.bHasShownDevNotice = false 
                lII1lllIIlI1I.bHasShownExpiredNotice = false 
                lII1lllIIlI1I.bIsDeadFlag = false
                lII1lllIIlI1I.bForceWeaponMod = true
                lII1lllIIlI1I.AK_NativeESP_Ready = false
            end
            
            if type(lII1lllIIlI1I.StartAdvancedSystems) == "function" then
                pcall(function() 
                    lII1lllIIlI1I:StartAdvancedSystems() 
                end)
            end
            
            pcall(function()
                local Msg = package.loaded["client.slua.logic.common.logic_common_msg_box"] or require("client.slua.logic.common.logic_common_msg_box")
                local Web = package.loaded["client.slua.logic.url.logic_webview_sdk"] or require("client.slua.logic.url.logic_webview_sdk")
                if Msg and Msg.Show then
                    Msg.Show(4, "ADITYA_ORG", "AKMOD VIP LUA FUCKED BY ADITYA_ORG LOADED SUCCESSFULLY", function()
                        if Web then Web:OpenURL("https://t.me/ADITYA_ORG") end
                    end, nil, "OK")
                end
            end)
            _G._AKMOD_INIT_DONE = true
        end
    end)
end

pcall(function()
    _G._AKMOD_INIT_DONE = false
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        pc:AddGameTimer(1.0, true, function()
            if not _G._AKMOD_INIT_DONE then
                lllI1llI111I1()
            end
        end)
    else
        require("common.time_ticker").AddTimerOnce(1.5, lllI1llI111I1)
    end
end)

-- Display credit text
pcall(function()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        pc:AddGameTimer(0.1, true, function()
            local player = GameplayData.GetPlayerCharacter()
            if slua.isValid(player) then
                local hud = pc:GetHUD()
                if slua.isValid(hud) and hud.AddDebugText then
                    hud:AddDebugText("MOD BY @ADITYA_ORG", player, 1, {X=0,Y=0,Z=145}, {X=0,Y=0,Z=145}, {R=255,G=200,B=0,A=255}, true, false, true, nil, 1.0, true)
                end
            end
        end)
    end
end)

-- Patch global BRPlayerCharacterBase with missing original functions dynamically
do
    local target = _G.BRPlayerCharacterBase
    if not target then
        -- Search the engine's loaded modules for the registered class
        for k, v in pairs(package.loaded) do
            if type(k) == "string" and string.find(k, "BRPlayerCharacterBase") and type(v) == "table" and v.ReceiveBeginPlay then
                target = v
                break
            end
        end
    end
    
    if target then
        for k, v in pairs(BRPlayerCharacterBase) do
            if type(v) == "function" and target[k] == nil then
                target[k] = v
            end
        end
    end
end
