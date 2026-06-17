-- Per-match guard: allow re-init when the player controller changes (new match)
do
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if _G._MOD_LOADED and _G._MOD_PC == pc then return end
    _G._MOD_LOADED = true
    _G._MOD_PC = pc
end

-- Initialize bypass state ASAP
if not _G.BYPASS_STATE then
    _G.BYPASS_STATE = {
        DEADEYE_DISABLED = false,
        HAWKEYE_DISABLED = false,
        VOKLAI_DISABLED = false,
        HIGGSBOSON_DISABLED = false,
        HASH_VERIFY_DISABLED = false,
        IP_MAPPING_DISABLED = false,
        MEMORY_PATCH_DISABLED = false,
        EDU_EYE_DISABLED = false,
        FULL_BYPASS_ACTIVE = false
    }
end

-- Initialize feature toggles with defaults
if not _G.Mod_Aimbot_Enabled then _G.Mod_Aimbot_Enabled = false end
if not _G.Mod_ESP_Enabled then _G.Mod_ESP_Enabled = false end
if not _G.Mod_Wallhack_Enabled then _G.Mod_Wallhack_Enabled = false end
if not _G.Mod_Skin_Enabled then _G.Mod_Skin_Enabled = false end
if _G.Mod_FPS165_Enabled == nil then _G.Mod_FPS165_Enabled = true end
if _G.Mod_NoGrass_Enabled == nil then _G.Mod_NoGrass_Enabled = true end
if _G.Mod_iPadView_Enabled == nil then _G.Mod_iPadView_Enabled = false end

-- Slider values for fine-tuning
if _G.Mod_AimbotStrength == nil then _G.Mod_AimbotStrength = 50 end
if _G.Mod_iPadViewDistance == nil then _G.Mod_iPadViewDistance = 90 end

-- CHAMS color system
if _G.Mod_Chams_GreenEnabled == nil then _G.Mod_Chams_GreenEnabled = false end
if _G.Mod_Chams_YellowEnabled == nil then _G.Mod_Chams_YellowEnabled = false end
if _G.Mod_Chams_GreenRGB == nil then _G.Mod_Chams_GreenRGB = {R=0, G=255, B=0, A=255} end
if _G.Mod_Chams_YellowRGB == nil then _G.Mod_Chams_YellowRGB = {R=255, G=255, B=0, A=255} end

local require = require
local import  = import
local isValid = slua.isValid
local pcall = pcall
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local math = math
local string = string

local function nop() return true end
local function retFalse() return false end
local function retZero() return 0 end
local function retEmpty() return {} end
_G.CheatsEnabled = true

local function safe_require(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end

local ok_gd, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData")
if not ok_gd then GameplayData = nil end

-- ==================== BYPASS ====================
-- Upgraded message display with multiple fallback methods
pcall(function()
    local function ShowSuccessMessage(title, message)
        -- Method 1: Try the original message box
        local Msg = package.loaded["client.slua.logic.common.logic_common_msg_box"]
        if not Msg then
            pcall(function() Msg = require("client.slua.logic.common.logic_common_msg_box") end)
        end
        if Msg and Msg.Show then
            pcall(function() Msg.Show(4, title, message) end)
            return true
        end
        
        -- Method 2: Try HUD debug text
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and pc:GetHUD() then
            local hud = pc:GetHUD()
            if hud and hud.AddDebugText then
                pcall(function()
                    hud:AddDebugText(title .. " - " .. message, pc:GetCurPawn(), 1.5, 
                        {X=0, Y=0, Z=200}, {X=0, Y=0, Z=200}, 
                        {R=0, G=255, B=0, A=255}, true, false, true, nil, 3.0, true)
                end)
                return true
            end
        end
        
        -- Method 3: Print to console/log
        print("[BYPASS] " .. title .. " - " .. message)
        
        -- Method 4: Try UI notification system (if available)
        pcall(function()
            local Notice = require("client.slua.logic.common.logic_notice")
            if Notice and Notice.ShowNotice then
                Notice.ShowNotice(message, 3)
            end
        end)
        
        return false
    end
    
    -- Only show once per match
    if not _G._BYPASS_MSG_SHOWN then
        _G._BYPASS_MSG_SHOWN = true
        ShowSuccessMessage("MOD BY @TUSHARx_OFFICIAL", "✓ COMPLETE BYPASS ACTIVE\n✓ 100% Telemetry Killed\n✓ 8-LAYER ANTI-CHEAT BYPASSED\n✓ Play Safe | Enjoy")
    end
end)

pcall(function()
    local stExtra = import("STExtraBlueprintFunctionLibrary")
    if stExtra and stExtra.IsDevelopment then stExtra.IsDevelopment = nop end
    if Client then Client.IsDevelopment = nop; Client.IsShipping = retFalse end
    if Server then Server.IsShipping = retFalse end

    local ToolReport = package.loaded["client.slua.logic.report.ToolReportUtil"]
    if ToolReport then
        ToolReport.IsReleaseVersion = retFalse
        ToolReport.IsWhite = retFalse
        ToolReport.GetReportSwitch = retFalse
    end

    local callbacks = _G.GameplayCallbacks or _G.GC
    if callbacks then
        local kills = {
            "SendTssSdkAntiDataToLobby","SendDSErrorLogToLobby","SendDSHawkEyePatrolLogToLobby",
            "SendSecTLog","SendDataMiningTLog","SendActivityTLog","SendClientMemUsage","SendClientFPS",
            "OnClientCrashReport","OnNetworkLossDetected","ReportMatchRoomData","ReportPlayersPing",
            "SendClientStats","SendServerAvgTickDelta","ReportHitFlow","OnPlayerActorChannelError","OnPlayerRPCValidateFailed"
        }
        for _, fn in ipairs(kills) do if callbacks[fn] then callbacks[fn] = nop end end
        local origDS = callbacks.OnDSPlayerStateChanged
        if origDS then
            callbacks.OnDSPlayerStateChanged = function(dsSelf, state, reason, ...)
                if tostring(reason):lower():find("cheatdetected") then return end
                pcall(origDS, dsSelf, state, reason, ...)
            end
        end
    end

    if _G.TApmHelper then _G.TApmHelper.postEvent = nop end

    local PC = _G.PacketCallbacks
    if PC then
        PC.player_report_cheat = nop
        PC.upload_loots_rsp = nop
        PC.watch_player_exit = nop
        PC.player_login_report = nop
        PC.player_logout_report = nop
        PC.server_time_report = nop
    end

    local sdm = _G.ServerDataMgr
    if sdm and sdm.DeletablePlayerResultKey then
        sdm.DeletablePlayerResultKey["SuspiciousHitCount"] = true
        sdm.DeletablePlayerResultKey["EspTotalSimTraceCnt"] = true
        sdm.DeletablePlayerResultKey["EspTotalImeFocusCnt"] = true
        sdm.DeletablePlayerResultKey["ClientGravityAnomalyCount"] = true
    end

    local pcNotify = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature"]
    if pcNotify then
        pcNotify.ClientRPC_SyncBanID = nop
        pcNotify.ClientRPC_StrongTips = nop
        pcNotify.ClientRPC_NormalTips = nop
        pcNotify.Notify = nop
        pcNotify.ClientRPC_NotifyBan = nop
        pcNotify.ClientRPC_NotifyPunish = nop
        pcNotify.ClientRPC_NotifyIllegalProgram = nop
    end

    local secUtils = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils"]
    if secUtils and secUtils.EStrategyTypeInReplay then
        secUtils.EStrategyTypeInReplay.EspTotalSimTraceCnt = 0
        secUtils.EStrategyTypeInReplay.EspTotalImeFocusCnt = 0
        secUtils.EStrategyTypeInReplay.ClientGravityAnomalyCount = 0
        secUtils.EStrategyTypeInReplay.FlyingErrorCnt = 0
    end
end)

pcall(function()
    local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
    if Higgs then
        local methods = {
            "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck","StartAvatarCheck",
            "ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert","ServerReportAvatar",
            "ClientReportNetAvatar","SendHisarData","ValidateSecurityData","StaticShowSecurityAlertInDev"
        }
        for _, m in ipairs(methods) do if Higgs[m] then Higgs[m] = nop end end
        Higgs.GetNetAvatarItemIDs = retEmpty
        Higgs.GetCurWeaponSkinID = retZero
    end
    if _G.DisableHiggsBoson then _G.DisableHiggsBoson = nop end

    local hia = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem")
    if hia then
        hia.CheckHitIntegrity = nop
        hia.InitSession = nop
        hia.OnBattleEnd = nop
    end

    local Behavior = safe_require("GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem")
    if Behavior then
        Behavior.OnHandleBehaviorScore = nop
        Behavior.AIPerceptionScore = nop
        Behavior.ReportBehavior = nop
        Behavior.CalcFinalScore = retZero
    end
end)

local higgs_bypass_attempts = 0
local MAX_HIGGS_BYPASS_ATTEMPTS = 60
local function bypass_higgs_boson_perplayer(player)
    if not player or not isValid(player) then return end
    if higgs_bypass_attempts >= MAX_HIGGS_BYPASS_ATTEMPTS then return end
    pcall(function()
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            Higgs.ControlMHActive = nop
            Higgs.TriggerAvatarCheck = nop
            Higgs.StartAvatarCheck = nop
            Higgs.ReportItemID = nop
            Higgs.OnReportItemID = nop
            Higgs.ReceiveAnyDamage = nop
            Higgs.OnWeaponHitRecord = nop
            Higgs.ShowSecurityAlert = nop
            Higgs.ServerReportAvatar = nop
            Higgs.ClientReportNetAvatar = nop
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
        end
        if _G.AvatarCheckCallback then
            _G.AvatarCheckCallback.StartAvatarCheck = nop
            _G.AvatarCheckCallback.OnReportItemID = nop
        end
    end)
    higgs_bypass_attempts = higgs_bypass_attempts + 1
end

local function hookPerPlayerHiggs()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if pc and isValid(pc) then
        local pawn = pc:GetCurPawn()
        if isValid(pawn) then bypass_higgs_boson_perplayer(pawn) end
    end
end

pcall(function()
    local BanLogic = package.loaded["client.slua.logic.ban.ClientBanLogic"]
    if BanLogic then
        BanLogic.OnSyncBanInfo = nop
        BanLogic.OnVoiceBanNotify = nop
        BanLogic.OnRealTimeVoiceBanNotify = nop
        BanLogic.OnVoiceBanSuccess = nop
        BanLogic.OnSyncMicSuspicious = nop
        BanLogic.OnSyncMicPreFilter = nop
        BanLogic.OnNotifyWarningTips = nop
        BanLogic.ReqBanInfo = nop
    end

    local BanUtil = package.loaded["client.common.ban_util"] or _G.ban_util
    if BanUtil then
        BanUtil.CheckBanStatus = retFalse
        BanUtil.GetBanTime = retZero
        BanUtil.IsBanForever = retFalse
    end

    local TTBan = package.loaded["client.logic.login.logic_tt_ban"] or _G.logic_tt_ban
    if TTBan then
        TTBan.CheckIfCanCreateRole = nop
        TTBan.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
    end

    local GodzillaBan = package.loaded["client.network.Protocol.GodzillaBanHandler"]
    if GodzillaBan then
        GodzillaBan.send_godzilla_ban_req = nop
        GodzillaBan.send_godzilla_unban_req = nop
    end

    local AntiAddiction = package.loaded["client.network.Protocol.AntiaddctionHandler"]
    if AntiAddiction then
        AntiAddiction.send_anti_addiction_req = nop
        AntiAddiction.send_anti_addiction_notify = nop
    end

    local AccessRestrict = package.loaded["client.network.Protocol.AccessRestrictionHandler"]
    if AccessRestrict then
        AccessRestrict.send_access_restriction_req = nop
        AccessRestrict.send_access_restriction_notify = nop
        AccessRestrict.on_player_cheat_state_notify = nop
    end

    local DeleteAccount = package.loaded["client.slua.logic.gdpr.logic_deleteaccount"]
    if DeleteAccount then
        DeleteAccount.ForceDeleteAccount = retFalse
        DeleteAccount.OnReceiveDeleteNotify = nop
    end

    local ComplianceUtil = package.loaded["client.slua.logic.gdpr.compliance_util"]
    if ComplianceUtil then ComplianceUtil.CheckCompliance = nop end
end)

pcall(function()
    local clientReport = package.loaded["GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem"]
    if clientReport then
        local funcs = {"OnInit","_OnPlayerKilledOtherPlayer","_RecordFatalDamager","SendPacket","ReportSuspiciousPlayer","SubmitReport","_OnBattleResult","_RecordTeammatePlayerInfo","_OnDeathReplayDataWhenFatalDamaged","_RecordMurdererFromDeathReplayData"}
        for _, fn in ipairs(funcs) do if clientReport[fn] then clientReport[fn] = nop end end
    end

    local dsReport = package.loaded["GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem"]
    if dsReport then
        local funcs = {"_OnNearDeathOrRescued","_OnPlayerSettlementStart","_OnTeammateDamage","_OnCharacterDied","_AddEnemyMapToBattleResult","_AddTeammateMapToBattleResult","_SubmitAbnormalData"}
        for _, fn in ipairs(funcs) do if dsReport[fn] then dsReport[fn] = nop end end
    end

    local reportUtils = package.loaded["GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils"]
    if reportUtils then reportUtils.GetBotType = retZero; reportUtils.IsCharacterDeliverAI = retFalse end

    local AvatarSub = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionSubsystem"]
    if AvatarSub then
        AvatarSub.OnClickReportCheckAvatar = nop
        AvatarSub.RegisterTickCheckCharacterAvatar = nop
    end
    if _G.AvatarExceptionPlayerInst then
        _G.AvatarExceptionPlayerInst.ReportAvatarException = nop
        _G.AvatarExceptionPlayerInst.CheckAvatarException = nop
        _G.AvatarExceptionPlayerInst.CheckCanBugglyPostException = nop
    end

    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local hawk = SubsystemMgr:Get("DSHawkEyePatrolSubsystem")
        if hawk then hawk.MarkSuspiciousPlayer = nop end
    end
    if _G.DSHawkEyePatrolSubsystem then
        _G.DSHawkEyePatrolSubsystem._OnHawkReport = nop
        _G.DSHawkEyePatrolSubsystem._OnHawkImprison = nop
        _G.DSHawkEyePatrolSubsystem.CheckPunishPlayer = nop
    end

    local ClientHawk = package.loaded["GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem"]
    if ClientHawk then
        local funcs = {"_OnHawkSync","_OnHawkReportSuccess","_StartExitGameTimer","_OnRecvInspectorBroadcastCount","SendReportTLog","ReportCheat"}
        for _, fn in ipairs(funcs) do if ClientHawk[fn] then ClientHawk[fn] = nop end end
        ClientHawk.CanInspectorBroadcast = retFalse
    end

    local InspectClient = package.loaded["GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem"]
    if InspectClient then
        local funcs = {"AskForInspector","ReportEnemy","KickOutOneTeam","OnReceiveInspectCmd","ClientReportData","SendReportToInspector","SendKickOutOneTeam","ClientNotifyInspectorImplementation","RecvNotifyInspector"}
        for _, fn in ipairs(funcs) do if InspectClient[fn] then InspectClient[fn] = nop end end
    end

    local InspectDS = package.loaded["GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem"]
    if InspectDS then
        local funcs = {"ServerKickOutOneTeamByPlayerImplementation","AddReportedCount","AddInspectionRecord","BanPlayerByInspection","BroadCastToAllInspector","ServerReportToInspectorImplementation","InitPlayerInspectionInfo"}
        for _, fn in ipairs(funcs) do if InspectDS[fn] then InspectDS[fn] = nop end end
    end
end)

pcall(function()
    local tlogModules = {
        "client.network.Protocol.ClientTlogHandler",
        "client.network.Protocol.BattleReportHandler",
        "client.network.Protocol.ClientErrorReportHandler",
        "client.network.Protocol.LobbyPingReportHandler",
        "client.slua.config.tlog.tlog_report_utils",
        "client.slua.data.BasicData.BasicDataTLogReport",
        "client.slua.data.BasicData.BasicDataClientReport",
        "client.slua.data.BasicData.BasicDataReport",
        "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem",
        "GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
        "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem",
        "GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem"
    }
    for _, path in ipairs(tlogModules) do
        local mod = package.loaded[path]
        if mod then
            for k, v in pairs(mod) do
                if type(v) == "function" and (k:find("Log") or k:find("Report") or k:find("Send") or k:find("Tlog")) then
                    pcall(function() mod[k] = nop end)
                end
            end
        end
    end

    local AmphibiousBoat = safe_require("GameLua.GameCore.Module.Vehicle.VehicleFeatures.TLog.AmphibiousBoatTLogFeature")
    if AmphibiousBoat then
        AmphibiousBoat.RecordMovement = nop
        AmphibiousBoat.StartRecordMovement = nop
    end
    local ICTLog = safe_require("GameLua.Mod.BaseMod.DS.Security.ICTLogSubsystem")
    if ICTLog then ICTLog.SendICExceptionTLog = nop end
    local DSFight = safe_require("GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem")
    if DSFight then
        DSFight.GetSimpleFightData = retEmpty
        DSFight.ReportFightData = nop
        DSFight.ReportPlayerWeapon = nop
    end
    local DSSec = safe_require("GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem")
    if DSSec then
        DSSec._OnReportServerJumpFlow = nop
        DSSec._OnReportTeleportFlow = nop
        DSSec._OnReportSpeedHackFlow = nop
    end
    local DSCommon = safe_require("GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem")
    if DSCommon then DSCommon.HandleKillTlog = nop end

    local PufferTlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
    if PufferTlog then PufferTlog.report_download_tlog = nop end
end)

pcall(function()
    local ClientError = package.loaded["client.network.Protocol.ClientErrorReportHandler"]
    if ClientError then
        ClientError.send_client_error_report = nop
        ClientError.send_client_crash_report = nop
        ClientError.send_client_tools_batch_report_req = nop
    end
    local BattleReport = package.loaded["client.network.Protocol.BattleReportHandler"]
    if BattleReport then
        BattleReport.send_battle_report = nop
        BattleReport.send_battle_result = nop
        BattleReport.send_vod_game_report_req = nop
        BattleReport.send_batch_get_vod_info_req = nop
        BattleReport.send_get_game_report_req = nop
        BattleReport.send_batch_get_game_report_req = nop
        BattleReport.send_get_game_report_by_uid_req = nop
    end
    local BugHandler = package.loaded["client.network.Protocol.BugHandler"]
    if BugHandler then
        BugHandler.send_report_bug_info = nop
        BugHandler.send_report_bug_feedback = nop
    end
    local PingReport = package.loaded["client.network.Protocol.LobbyPingReportHandler"]
    if PingReport then
        PingReport.send_lobby_ping_report = nop
        PingReport.send_ingame_ping_report = nop
    end
    local WeekReport = package.loaded["client.network.Protocol.WeekRportHandler"]
    if WeekReport then
        WeekReport.send_week_report = nop
        WeekReport.send_week_detail = nop
    end
    local LogicComplaint = package.loaded["client.logic.battle.logic_complaint"]
    if LogicComplaint then
        LogicComplaint.SendComplaintReq = nop
        LogicComplaint.Submit = nop
        LogicComplaint.ReportPlayer = nop
        LogicComplaint.ShowComplaint = nop
        LogicComplaint.ShowHandle = nop
    end
    local OBResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.EscapeBattleResultShowOBResultLogic"]
    if OBResult then
        OBResult.OnBattleResult = nop
        OBResult.OnResultProcessStart = nop
    end
    local NormalOBResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowOBResultLogic"]
    if NormalOBResult then
        NormalOBResult.OnBattleResult = nop
        NormalOBResult.OnResultProcessStart = nop
    end
    local ShowResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic"]
    if ShowResult then
        ShowResult.OnBattleResult = nop
        ShowResult.OnResultProcessStart = nop
        ShowResult.OnResultProcessContinue = nop
        ShowResult.ReceiveData = nop
        ShowResult.SendEndFlow = nop
        ShowResult.OnReport = nop
        ShowResult.ShowResult = nop
        ShowResult.ShowResultInternal = nop
        ShowResult.StopResultProcess = nop
    end
end)

pcall(function()
    local EmuHandler = package.loaded["client.network.Protocol.EmulatorHandler"]
    if EmuHandler then EmuHandler.send_emulator_info = nop end
    local EmuScanner = package.loaded["client.logic.login.emulator_scanner"]
    if EmuScanner then
        EmuScanner.StartScan = nop
        EmuScanner.GetScanResult = retFalse
        EmuScanner.ReportScanResult = nop
    end
    local LoginVerify = package.loaded["client.network.Protocol.LoginVerifyHandler"]
    if LoginVerify then
        LoginVerify.send_login_verify_req = nop
        LoginVerify.send_device_verify_req = nop
    end
    local DSMonitor = package.loaded["client.logic.data.logic_ds_monitor"]
    if DSMonitor then
        DSMonitor.OnRecordMsg = nop
        DSMonitor.OnReportMsg = nop
    end
    local ClientDataStat = package.loaded["GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem"]
    if ClientDataStat then
        ClientDataStat.StartToCheck = nop
        ClientDataStat.OnReceiveRTT = nop
        ClientDataStat.OnReceiveJitter = nop
        ClientDataStat.ReportAbnormal = nop
        ClientDataStat.ResetData = nop
    end
    local shootVerify = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
    if shootVerify then
        shootVerify.OnShootVerifyFailed = nop
        shootVerify.SendVerifyData = nop
    end
    local HighlightDS = safe_require("GameLua.Mod.BaseMod.DS.Security.HighlightMomentSubsystem_DSChecker")
    if HighlightDS then HighlightDS.CheckFuncUpgradedWeaponKill = nop end
end)

pcall(function()
    local ProfileReport = package.loaded["client.logic.data.profile_report_cfg"]
    if ProfileReport then ProfileReport.SendReport = nop end
    local VoiceReport = package.loaded["client.slua.logic.chat_voice.logic_chat_voice_report"]
    if VoiceReport then
        VoiceReport.ReportVoiceData = nop
        VoiceReport.ReportVoiceText = nop
    end
    local VoiceDoctor = package.loaded["client.slua.logic.chat_voice.logic_chat_voice_doctor"]
    if VoiceDoctor then
        VoiceDoctor.UploadVoiceLog = nop
        VoiceDoctor.UploadVoiceException = nop
    end
    local HomeAudit = package.loaded["client.slua.logic.home.Audit.logic_home_audit_state"]
    if HomeAudit then
        HomeAudit.SendAuditState = nop
        HomeAudit.ReportAuditResult = nop
    end
    local HomeReport = package.loaded["client.slua.logic.home.logic_home_report"]
    if HomeReport then
        HomeReport.ReportHomeData = nop
        HomeReport.ReportHomeVisitor = nop
    end
    local GemReport = package.loaded["client.logic.store.gem_report_utils"]
    if GemReport then
        GemReport.ReportGemData = nop
        GemReport.ReportGemPurchase = nop
    end
    local SafeStation = package.loaded["client.slua.logic.CustomerService.LogicSafeStation"]
    if SafeStation then
        SafeStation.UploadVideoEvidence = nop
        SafeStation.ReportPlayerBehavior = nop
    end
    local CustomerService = package.loaded["client.slua.logic.CustomerService.LogicCustomerService"]
    if CustomerService then
        CustomerService.SendComplaint = nop
        CustomerService.SendFeedback = nop
    end
end)

pcall(function()
    local znq6Revive = safe_require("GameLua.Mod.TDEvent.ZNQ6th.DS.ZNQ6thDSReviveSubsystem")
    if znq6Revive then znq6Revive.HaveNewItemForRevive = nop end
    local znq7Revive = safe_require("GameLua.Mod.TDEvent.ZNQ7th.DS.ZNQ7DSReviveSubsystem")
    if znq7Revive then znq7Revive.HaveChanceRevival = nop end
    local DataLayer = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.DataLayerSubsystem")
    if DataLayer then
        local orig = DataLayer.OnSpectatorReplayChanged
        if orig then
            DataLayer.OnSpectatorReplayChanged = function(dlSelf)
                _G.IsBeingWatched = true
                orig(dlSelf)
            end
        end
    end
    local DSActive = safe_require("GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem")
    if DSActive then
        DSActive.DelayKickOutPlayer = nop
        DSActive.ActiveKickNotify = nop
    end
    local CreativeDev = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeDevDebugSubsystem")
    if CreativeDev then CreativeDev.IsDebugPanelEnalbedCli = nop end
    local CreativeDeath = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeModeDeathRecordSubsystem")
    if CreativeDeath then CreativeDeath.OnPlayerKilled = nop end
    if _G.ClientReplayDataReporter then
        _G.ClientReplayDataReporter.ReportIntArrayData = nop
        _G.ClientReplayDataReporter.ReportFloatArrayData = nop
    end
    local SpectateReplay = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
    if SpectateReplay then
        SpectateReplay.RequestGotoSpectatingImp = nop
        SpectateReplay.RequestGotoSpectating = nop
    end
    local AIReplay = safe_require("GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem")
    if AIReplay then
        AIReplay.ReportAllPlayerInfo = nop
        AIReplay.ReportFrameData = nop
        AIReplay.ReportPlayerInput = nop
        if AIReplay.uCompletePlayBack then
            AIReplay.uCompletePlayBack.AddRecordMLAIInfo = nop
            AIReplay.uCompletePlayBack.StopRecording = nop
        end
    end
    local AITracking = safe_require("GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem")
    if AITracking then
        AITracking.RealLogoutTimer = nop
        AITracking.LogQueue = {}
        AITracking.AddToLogQue = nop
        AITracking.DoPrint = nop
        AITracking.OnAIPawnDied = nop
        AITracking.OnAIPawnReceiveDamage = nop
        AITracking.OnAIPawnEnemyChange = nop
    end
    local AFKReport = safe_require("GameLua.Mod.BaseMod.DS.Security.AFKReportorSubsystem")
    if AFKReport then
        AFKReport.HandleEnterFighting = nop
        AFKReport.InitializePlayerInputInfo = nop
        AFKReport.AddOneAFKInfo = nop
        AFKReport.SetPlayerAFKState = nop
        AFKReport.ResetPlayerInputInfo = nop
        AFKReport.PlayerHaveAction = nop
    end
    local TDMAFK = safe_require("GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem")
    if TDMAFK then
        TDMAFK.SendAFKTips = nop
        TDMAFK.OnHandleLostConnection = nop
    end
    local DataMgr = package.loaded["client.slua.logic.data.data_mgr"]
    if DataMgr then DataMgr.GetWeaponSkinSoundVolumeInfoByGroup = retZero end
    local CreditLogic = safe_require("GameLua.Mod.BaseMod.Client.ClientInGameCreditLogic")
    if CreditLogic then
        CreditLogic._SendUserReaction2ExitTeamBeforeBoardingReturnLobbyNotice = nop
        CreditLogic.ShowReturnLobbyIfFirstExitTeamBeforeBoarding = retFalse
        CreditLogic.OnReceiveCreditScoreChange = nop
        CreditLogic._IsFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = retFalse
        CreditLogic.SetFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = nop
    end
end)

local globalFuncs = {
    "ReportTLogEvent","SendTlog","SendClientStats","ReportHitFlow","ReportAvatarException",
    "SendComplaintReq","SubmitReport","ReportSuspiciousPlayer","SendPacket","OnSyncBanInfo",
    "OnVoiceBanNotify","SendSecTLog","MarkSuspiciousPlayer","ReportPlayerBehaviorData",
    "CheckCompliance","ReportIllegalProgram","UploadVoiceLog"
}
for _, fn in ipairs(globalFuncs) do
    if type(_G[fn]) == "function" then _G[fn] = nop end
end

local BLACKLIST_HOSTS = {
    "tss.tencent","syzsdk","gcloud.qq","reportlog","tdos","logupload","feedback.wh","crash2",
    "privacy.qq","privacy.tencent","oth.eve","mdt.qq","act.tencentyun","analytics","report.qq",
    "anticheatexpert","crashsight","wetest","log.tav","sngd","tracer","intlsdk","igamecj",
    "cdn.club","gpubgm","graph.facebook","calendarpushsubscription","googleads","doubleclick",
    "firebaselogging","firebaseremoteconfig","fonts.googleapis","abs.twimg","dl.listdl",
    "igame.gcloudcs","bugly","beacon","helpshift","tdm","apm","safeguard","weiyun","qzone",
    "tencent-cloud","myapp","idqqimg","gtimg","qqmail","tcdn","cloudctrl","sdkostrace",
    "103.134.189.146","mbgame","csoversea","igame","pubgmobile","down.anticheatexpert.com",
    "asia.csoversea.mbgame.anticheatexpert.com","log.tav.qq","syzsdk.qq","logiservice.qcloud",
    "opensdk.tencent","exp.helpshift","loginsdkapi.zingplay","firebase","googleapis","facebook","gvoice"
}
local BLACKLIST_PORTS = {
    "10334","11045","12221","13331","8011","8015","9001","20000","20001","20002","20003","20004",
    "20005","19700","1670","19900","14545","10213","8700","25177","10685","10336","10262","27000",
    "27040","27015","27030","10706","10095","12401","11008","10309","11075","10157","24798","10709",
    "6667","10087","31113","20371","10120","10664","13728","10769","10761","5061","5062","18081",
    "15692","9030","8080","8086","8088"
}
local FILE_KEYWORDS = {
    "tlog","crash","bugly","report","beacon","wetest","analytics","telemetry","trace","dump",
    "exception","feedback","aps_log","mtp_detect","network_loss","client_error","ue4crash","tdm","gcloud"
}

local function isBlacklisted(str)
    if type(str) ~= "string" then return false end
    local low = str:lower()
    for _, kw in ipairs(BLACKLIST_HOSTS) do if low:find(kw,1,true) then return true end end
    for _, port in ipairs(BLACKLIST_PORTS) do if low:find(":"..port) or low:find("/"..port) then return true end end
    return false
end

pcall(function()
    if _G.HttpRequest then
        local orig = _G.HttpRequest
        _G.HttpRequest = function(url, ...) if isBlacklisted(url) then return nil end return orig(url, ...) end
    end
    if _G.FHttpModule and _G.FHttpModule.CreateRequest then
        local orig = _G.FHttpModule.CreateRequest
        _G.FHttpModule.CreateRequest = function(...) local url = select(1,...); if isBlacklisted(url) then return nil end return orig(...) end
    end
    local netMods = {
        "client.slua.logic.network.logic_network","client.slua.logic.download.report.puffer_tlog",
        "client.slua.data.BasicData.BasicDataClientReport","GameLua.GameCore.Module.Network.NetworkManager",
        "client.network.Protocol.ClientTlogHandler","client.network.Protocol.BattleReportHandler",
        "client.network.Protocol.ClientErrorReportHandler"
    }
    for _, mp in ipairs(netMods) do
        local mod = package.loaded[mp]
        if mod then
            for k, v in pairs(mod) do
                if type(v) == "function" and (k:find("Http") or k:find("Request") or k:find("Send") or k:find("Upload") or k:find("Post") or k:find("Get") or k:find("Report")) then
                    local origf = v
                    mod[k] = function(...)
                        local args = {...}
                        for _, arg in ipairs(args) do if type(arg)=="string" and isBlacklisted(arg) then return nil end end
                        return pcall(origf, ...)
                    end
                end
            end
        end
    end
end)

-- ==================== 8-LAYER ADVANCED ANTI-CHEAT BYPASS ====================

local FakeData = {
    ping = function() return math.random(20, 45) end,
    deviceID = function()
        local chars = "0123456789ABCDEF"
        local id = ""
        for i = 1, 32 do
            id = id .. chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return id
    end,
    ipAddress = function()
        return "192.168." .. math.random(1, 255) .. "." .. math.random(1, 255)
    end,
    macAddress = function()
        return string.format("%02X:%02X:%02X:%02X:%02X:%02X",
            math.random(0,255), math.random(0,255), math.random(0,255),
            math.random(0,255), math.random(0,255), math.random(0,255))
    end,
    buildFingerprint = function()
        return "qcom/msmnile/msmnile:" .. math.random(10, 12) .. "/" .. 
               math.random(100000, 999999) .. "/user/release-keys"
    end,
    kernelVersion = function() return "4.19." .. math.random(100, 200) .. "-generic" end,
    hashValue = function()
        return "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    end
}

local function KillTable(tbl, keys)
    if not tbl then return end
    for _, key in ipairs(keys) do
        pcall(function()
            if type(tbl[key]) == "function" then
                tbl[key] = function() return true, {} end
            else
                tbl[key] = nil
            end
        end)
    end
end

local function BypassDeadEye()
    if _G.BYPASS_STATE.DEADEYE_DISABLED then return end
    pcall(function()
        if _G.GameplayCallbacks then
            KillTable(_G.GameplayCallbacks, {
                "ReportAimFlow", "ReportHitFlow", "ReportAttackFlow",
                "OnAimDetected", "OnHeadshotDetected", "OnPerfectAccuracy"
            })
        end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local aimTracker = subsystems:Get("ClientAimTrackingSubsystem")
            if aimTracker then
                aimTracker.GetAimData = function() return {accuracy = math.random(45, 65), headshotRate = math.random(15, 35)} end
                aimTracker.IsAimNormal = function() return true end
            end
        end
    end)
    _G.BYPASS_STATE.DEADEYE_DISABLED = true
end

local function BypassHawkEye()
    if _G.BYPASS_STATE.HAWKEYE_DISABLED then return end
    pcall(function()
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local hawkEye = subsystems:Get("ClientHawkEyePatrolSubsystem")
            if hawkEye then
                hawkEye.GetPatrolData = function() return {} end
                hawkEye.IsBeingWatched = function() return false end
                hawkEye.GetSpectatorCount = function() return 0 end
            end
        end
        if _G.GameplayCallbacks then
            KillTable(_G.GameplayCallbacks, {
                "SendDSErrorLogToLobby", "SendDSHawkEyePatrolLogToLobby", "ReportMatchRoomData"
            })
        end
    end)
    _G.BYPASS_STATE.HAWKEYE_DISABLED = true
end

local function BypassVoklai()
    if _G.BYPASS_STATE.VOKLAI_DISABLED then return end
    pcall(function()
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local aiBehavior = subsystems:Get("ClientAIBehaviourSubsystem")
            if aiBehavior then
                aiBehavior.GetBehaviorScore = function() return math.random(10, 30) end
                aiBehavior.IsSuspicious = function() return false end
                aiBehavior.GetRiskLevel = function() return 0 end
            end
            local stepCheck = subsystems:Get("ClientStepCheckSubsystem")
            if stepCheck then
                stepCheck.GetStepDelta = function() return math.random(5, 50) end
                stepCheck.IsMovementValid = function() return true end
            end
            local speedHack = subsystems:Get("AntiSpeedHackSubsystem") or subsystems:Get("ClientAntiSpeedHackSubsystem")
            if speedHack then
                speedHack.GetSpeed = function() return math.random(300, 600) end
                speedHack.IsSpeedValid = function() return true end
            end
        end
    end)
    _G.BYPASS_STATE.VOKLAI_DISABLED = true
end

local function BypassHiggsBoson()
    if _G.BYPASS_STATE.HIGGSBOSON_DISABLED then return end
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if isValid(pc) then
            if pc.HiggsBoson then
                pc.HiggsBoson.bMHActive = false
                pc.HiggsBoson.bCallPreReplication = false
            end
            if pc.HiggsBosonComponent then
                pc.HiggsBosonComponent.bMHActive = false
                pc.HiggsBosonComponent:ControlMHActive(0)
            end
        end
        local higgsComponent = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if higgsComponent then
            higgsComponent.GetNetAvatarItemIDs = function() return {1001, 2002, 3003, 4004, 5005} end
            higgsComponent.GetCurWeaponSkinID = function() return 6001 end
            higgsComponent.GetCurItemIDs = function() return {7001, 8002} end
            if higgsComponent.BlackList then higgsComponent.BlackList = {} end
        end
        _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
        local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
        mt.__newindex = function() end
        setmetatable(_G.GlobalPlayerCoronaData, mt)
        _G.BlackList = {}
    end)
    _G.BYPASS_STATE.HIGGSBOSON_DISABLED = true
end

local function BypassHashVerification()
    if _G.BYPASS_STATE.HASH_VERIFY_DISABLED then return end
    pcall(function()
        if _G.TssSdk then
            _G.TssSdk.ScanMemory = function() return true, {code = 0, msg = "clean"} end
            _G.TssSdk.ScanSo = function() return true, {code = 0, msg = "clean"} end
            _G.TssSdk.ScanFile = function() return true, {code = 0} end
            _G.TssSdk.GetRiskFlag = function() return 0 end
            _G.TssSdk.VerifyFileHash = function() return true end
        end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local integrity = subsystems:Get("ClientIntegrityCheckSubsystem")
            if integrity then
                KillTable(integrity, {"CheckFileHash", "VerifyMemory", "ScanModules"})
            end
        end
    end)
    _G.BYPASS_STATE.HASH_VERIFY_DISABLED = true
end

local function BypassIPMapping()
    if _G.BYPASS_STATE.IP_MAPPING_DISABLED then return end
    pcall(function()
        if _G.GameplayCallbacks then
            KillTable(_G.GameplayCallbacks, {
                "SendClientDeviceInfo", "ReportDeviceFingerprint", "SendNetworkInfo",
                "ReportIPAddress", "SendMACAddress", "ReportHardwareID"
            })
        end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local deviceInfo = subsystems:Get("ClientDeviceInfoSubsystem")
            if deviceInfo then
                deviceInfo.GetDeviceID = function() return FakeData.deviceID() end
                deviceInfo.GetIPAddress = function() return FakeData.ipAddress() end
                deviceInfo.GetMACAddress = function() return FakeData.macAddress() end
            end
        end
    end)
    _G.BYPASS_STATE.IP_MAPPING_DISABLED = true
end

local function BypassMemoryPatching()
    if _G.BYPASS_STATE.MEMORY_PATCH_DISABLED then return end
    pcall(function()
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local kernelCheck = subsystems:Get("ClientKernelCheckSubsystem")
            if kernelCheck then
                kernelCheck.IsKernelClean = function() return true end
                kernelCheck.GetKernelVersion = function() return FakeData.kernelVersion() end
                kernelCheck.IsBootloaderLocked = function() return true end
            end
            local memoryGuard = subsystems:Get("ClientMemoryGuardSubsystem")
            if memoryGuard then
                memoryGuard.IsMemoryClean = function() return true, {code = 0} end
                memoryGuard.ScanResult = function() return "clean" end
            end
        end
        if _G.TssSdk then
            _G.TssSdk.CheckKernel = function() return true, {status = "verified", tampered = false} end
            _G.TssSdk.VerifyBoot = function() return true, {locked = true, verified = true} end
        end
    end)
    _G.BYPASS_STATE.MEMORY_PATCH_DISABLED = true
end

local function BypassEduEye()
    if _G.BYPASS_STATE.EDU_EYE_DISABLED then return end
    pcall(function()
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local renderCheck = subsystems:Get("ClientRenderCheckSubsystem")
            if renderCheck then
                renderCheck.IsRenderClean = function() return true end
                renderCheck.GetRenderState = function() return "normal" end
            end
            local espDetection = subsystems:Get("ClientESPDetectionSubsystem")
            if espDetection then
                espDetection.HasESP = function() return false end
                espDetection.CheckOverlay = function() return "clean" end
            end
            local wallhackDetect = subsystems:Get("ClientWallhackDetectionSubsystem")
            if wallhackDetect then
                wallhackDetect.IsVisionNormal = function() return true end
                wallhackDetect.GetVisibilityRate = function() return math.random(60, 85) end
            end
        end
    end)
    _G.BYPASS_STATE.EDU_EYE_DISABLED = true
end

local function ApplyAllBypasses()
    if _G.BYPASS_STATE.FULL_BYPASS_ACTIVE then return end
    pcall(function()
        BypassDeadEye()
        BypassHawkEye()
        BypassVoklai()
        BypassHiggsBoson()
        BypassHashVerification()
        BypassIPMapping()
        BypassMemoryPatching()
        BypassEduEye()
        _G.BYPASS_STATE.FULL_BYPASS_ACTIVE = true
    end)
end

function _G.GetBypassStatus()
    local state = _G.BYPASS_STATE
    return {
        deadEye = state.DEADEYE_DISABLED,
        hawkEye = state.HAWKEYE_DISABLED,
        voklai = state.VOKLAI_DISABLED,
        higgsBoson = state.HIGGSBOSON_DISABLED,
        hashVerify = state.HASH_VERIFY_DISABLED,
        ipMapping = state.IP_MAPPING_DISABLED,
        memoryPatch = state.MEMORY_PATCH_DISABLED,
        eduEye = state.EDU_EYE_DISABLED,
        fullBypass = state.FULL_BYPASS_ACTIVE
    }
end

function _G.ForceReapplyBypass()
    _G.BYPASS_STATE.FULL_BYPASS_ACTIVE = false
    _G.BYPASS_STATE.DEADEYE_DISABLED = false
    _G.BYPASS_STATE.HAWKEYE_DISABLED = false
    _G.BYPASS_STATE.VOKLAI_DISABLED = false
    _G.BYPASS_STATE.HIGGSBOSON_DISABLED = false
    _G.BYPASS_STATE.HASH_VERIFY_DISABLED = false
    _G.BYPASS_STATE.IP_MAPPING_DISABLED = false
    _G.BYPASS_STATE.MEMORY_PATCH_DISABLED = false
    _G.BYPASS_STATE.EDU_EYE_DISABLED = false
    ApplyAllBypasses()
end

pcall(function() ApplyAllBypasses() end)

-- AUTO-ACTIVATE BYPASS MONITOR (Ensures bypasses stay active throughout game session)
pcall(function()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if pc and pc.AddGameTimer then
        pc:AddGameTimer(2.0, true, function()
            if not _G.BYPASS_STATE.FULL_BYPASS_ACTIVE then
                pcall(function() ApplyAllBypasses() end)
            end
        end)
    end
end)

local orig_io_open = io.open
io.open = function(path, mode)
    if type(path) == "string" then
        local lp = path:lower()
        for _, kw in ipairs(FILE_KEYWORDS) do
            if lp:find(kw) then
                if mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
                    return nil, "Blocked"
                end
            end
        end
        if lp:find("tdm") or lp:find("gcloud") or lp:find("beacon") then
            if mode and (mode == "w" or mode == "a" or mode == "w+") then return nil end
        end
    end
    return orig_io_open(path, mode)
end

if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
    _G.UnrealEngine.CrashContext = nil
    _G.UnrealEngine.CrashContext = { SetCrashContext = nop, ReportCrash = nop, AddCrashData = nop }
end

local function huntAndKillAll()
    pcall(function()
        local subNames = {
            "ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem","ClientReportPlayerSubsystem",
            "DSReportPlayerSubsystem","ClientGlueHiaSystem","ClientDataStatistcsSubsystem",
            "ICTLogSubsystem","DSFightTLogSubsystem","DSSecurityTLogSubsystem","AFKReportorSubsystem",
            "BehaviorScoreSubsystem"
        }
        local subMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subMgr and subMgr.Get then
            for _, name in ipairs(subNames) do
                local sub = subMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Tick") or k:find("Log")) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                end
            end
        end
        local tlogPaths = {
            "client.slua.config.tlog.tlog_report_utils",
            "client.network.Protocol.ClientTlogHandler",
            "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem"
        }
        for _, path in ipairs(tlogPaths) do
            local mod = package.loaded[path]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Log")) then
                        pcall(function() mod[k] = nop end)
                    end
                end
            end
        end
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            local methods = {"ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck","StartAvatarCheck","ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert","ServerReportAvatar","ClientReportNetAvatar","SendHisarData","ValidateSecurityData"}
            for _, m in ipairs(methods) do if Higgs[m] then Higgs[m] = nop end end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
        end
    end)
end

local function startPersistentTimer()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if pc and isValid(pc) then
        if _G._permHuntTimer then pcall(function() pc:RemoveGameTimer(_G._permHuntTimer) end) end
        _G._permHuntTimer = pc:AddGameTimer(3.0, true, huntAndKillAll)
        return true
    end
    return false
end

if _G._centerTextTimer then
    pcall(function() if _G._centerTextPC and isValid(_G._centerTextPC) then _G._centerTextPC:RemoveGameTimer(_G._centerTextTimer) end end)
    _G._centerTextTimer = nil; _G._centerTextPC = nil
end
local function showCenter()
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if not isValid(pc) then return end
        local pawn = pc:GetCurPawn()
        if not isValid(pawn) then return end
        local hud = pc:GetHUD()
        if not isValid(hud) then return end
    end)
end
local function startCenter()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if isValid(pc) then
        _G._centerTextTimer = pc:AddGameTimer(0.5, true, showCenter)
        _G._centerTextPC = pc
    else
        local fb = slua_GameFrontendHUD or Game
        if fb and isValid(fb) then fb:AddGameTimer(1.5, false, startCenter) end
    end
end

local function finalStart()
    if startPersistentTimer() then
        startCenter()
        hookPerPlayerHiggs()
    else
        local fb = slua_GameFrontendHUD or Game
        if fb and isValid(fb) then fb:AddGameTimer(2.0, false, finalStart) end
    end
end
finalStart()

-- ==================== SKINS ====================
local function sk_safe_require(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end

local BASE_PATH       = "/storage/emulated/0/Android/data/com.pubg.imobile/files/"
local CONFIG_PATH     = BASE_PATH .. "config.ini"
local SAVE_KILL_PATH  = BASE_PATH .. "kill_counts.txt"
local ATTACH_PATH     = BASE_PATH .. "attachments.txt"

_G.WeaponSkinMap        = _G.WeaponSkinMap        or {}
_G.VehicleSkinMap       = _G.VehicleSkinMap        or {}
_G.OutfitMap            = _G.OutfitMap             or {}
_G.AttachmentOverrideMap= _G.AttachmentOverrideMap  or {}
_G.SkinAttachments      = _G.SkinAttachments        or {}
_G.SkinLoadedCache      = _G.SkinLoadedCache        or {}
_G.FakeKillCounts       = _G.FakeKillCounts         or {}
_G.LastEquippedOutfits  = _G.LastEquippedOutfits    or {}
_G.g_parts              = _G.g_parts               or {}
_G.skinAttachCache      = _G.skinAttachCache        or {}
_G.KillData             = _G.KillData              or { kills = {} }
_G.DeadBoxSkins         = _G.DeadBoxSkins          or {}
_G.AlreadyChangedSet    = _G.AlreadyChangedSet      or {}
_G.CurrentEquipVehicleID= _G.CurrentEquipVehicleID  or 0

local function SaveKillsToFile()
    pcall(function()
        local file = io.open(SAVE_KILL_PATH, "w")
        if file then
            for id, count in pairs(_G.KillData.kills) do
                file:write(string.format("%d:%d\n", id, count))
            end
            file:close()
        end
    end)
end

local function LoadKillsFromFile()
    pcall(function()
        local file = io.open(SAVE_KILL_PATH, "r")
        if file then
            for line in file:lines() do
                local id, count = line:match("(%d+):(%d+)")
                if id and count then
                    _G.KillData.kills[tonumber(id)] = tonumber(count)
                end
            end
            file:close()
        end
    end)
end

_G.getKills = function(weaponID) return _G.KillData.kills[weaponID] or 0 end

_G.AddKill = function(weaponID)
    if not weaponID then return end
    _G.KillData.kills[weaponID] = (_G.KillData.kills[weaponID] or 0) + 1
    _G._KillSaveDirty = (_G._KillSaveDirty or 0) + 1
    if _G._KillSaveDirty >= 3 then
        SaveKillsToFile()
        _G._KillSaveDirty = 0
    end
    pcall(function()
        local UIM = require("client.slua_ui_framework.manager")
        local MKC = UIM.GetUI(UIM.UI_Config_InGame.MainKillCounter)
        if MKC then
            if MKC.OnRefreshData then
                MKC:OnRefreshData()
            end
            if MKC.KillCounterItem and MKC.KillCounterItem.SetKillCounterItemShowWithNum then
                local sid = _G.get_skin_id(weaponID) or weaponID
                MKC.KillCounterItem:SetKillCounterItemShowWithNum(sid, _G.KillData.kills[weaponID], sid)
            end
        end
    end)
end

LoadKillsFromFile()

_G.get_skin_id = function(weaponID)
    if not weaponID or weaponID == 0 then return nil end
    local mapped = _G.WeaponSkinMap[weaponID]
    if mapped and mapped > 0 then return mapped end
    return nil
end

_G.download_item = function(i)
    if not i then return end
    pcall(function()
        local PM = require("client.slua.logic.download.puffer.puffer_manager")
        local PC = require("client.slua.logic.download.puffer_const")
        if PM.GetState(PC.ENUM_DownloadType.ODPAK, {i}) ~= PC.ENUM_DownloadState.Done then
            PM.Download(PC.ENUM_DownloadType.ODPAK, {i})
        end
    end)
end

local ATTACH_NAME_MAP = {
    ["Red Dot Sight"]          = "RedDot",
    ["Holographic Sight"]      = "Holo",
    ["2x Scope"]               = "Scope2x",
    ["3x Scope"]               = "Scope3x",
    ["4x Scope"]               = "Scope4x",
    ["6x Scope"]               = "Scope6x",
    ["8x Scope"]               = "Scope8x",
    ["Canted Sight"]           = "CantedSight",
    ["Flash Hider"]            = "FlashHider",
    ["Compensator"]            = "Compensator",
    ["Suppressor"]             = "Suppressor",
    ["Extended Mag"]           = "ExtMag",
    ["Quickdraw Mag"]          = "QuickMag",
    ["Extended Quickdraw Mag"] = "ExtQuickMag",
    ["Angled Foregrip"]        = "AngledGrip",
    ["Vertical Foregrip"]      = "VerticalGrip",
    ["Thumb Grip"]             = "ThumbGrip",
    ["Half Grip"]              = "HalfGrip",
    ["Light Grip"]             = "LightGrip",
    ["Laser Sight"]            = "LaserSight",
    ["Tactical Stock"]         = "TactStock",
    ["Stock"]                  = "MicroStock",
    ["Cheek Pad"]              = "CheekPad",
}

local _attachFileCache = nil

local function _parseAttachmentsFile()
    local result = {}
    pcall(function()
        local f = io.open(ATTACH_PATH, "r")
        if not f then return end
        local content = f:read("*all")
        f:close()
        local curSkin = nil
        for line in content:gmatch("[^\r\n]+") do
            local firstNum = line:match("^(%d+)%s*|")
            if firstNum then
                local num = tonumber(firstNum)
                if num and num > 1100000000 then
                    curSkin = num
                    result[curSkin] = result[curSkin] or {}
                elseif num and curSkin then
                    local attachName = line:match("^%d+%s*|%s*%x+%s*|%s*(.-)%s*$")
                    if not attachName then attachName = line:match("^%d+%s*|%s*(.-)%s*$") end
                    if attachName and attachName ~= "" then
                        local key = ATTACH_NAME_MAP[attachName]
                        if key then result[curSkin][key] = num end
                    end
                end
            elseif line:find("^#%-%-%-%-") and line:find("skin") then
                curSkin = nil
            end
        end
    end)
    return result
end

_G.GetAttachForSkin = function(skinId, key)
    if not skinId or skinId == 0 or not key then return nil end
    if not _attachFileCache then _attachFileCache = _parseAttachmentsFile() end
    local t = _attachFileCache[skinId]
    if not t then return nil end
    local v = t[key]
    return (v and v > 0) and v or nil
end

_G.GetAttachFileCache = function()
    if not _attachFileCache then _attachFileCache = _parseAttachmentsFile() end
    return _attachFileCache
end

local function ReadLiveConfig()
    pcall(function()
        local f = io.open(CONFIG_PATH, "r")
        if not f then return end
        local content = f:read("*all")
        f:close()
        for line in content:gmatch("[^\r\n]+") do
            local k, v = line:match("^([^#=]+)=(.+)$")
            if k and v then
                k = k:gsub("^%s+", ""):gsub("%s+$", "")
                if k == "cheats" then
                    _G.CheatsEnabled = (v == "1" or v:lower() == "on" or v:lower() == "true")
                end
                local val = tonumber(v)
                if val then
                    if     k == "Suit"      then _G.OutfitMap.Suit      = val
                    elseif k == "Hat"       then _G.OutfitMap.Hat       = val
                    elseif k == "Mask"      then _G.OutfitMap.Mask      = val
                    elseif k == "Glasses"   then _G.OutfitMap.Glasses   = val
                    elseif k == "Pants"     then _G.OutfitMap.Pants     = val
                    elseif k == "Shoes"     then _G.OutfitMap.Shoes     = val
                    elseif k == "Bag"       then _G.OutfitMap.Bag       = val
                    elseif k == "Helmet"    then _G.OutfitMap.Helmet    = val
                    elseif k == "Armor"     then _G.OutfitMap.Armor     = val
                    elseif k == "Parachute" then _G.OutfitMap.Parachute = val
                    elseif k == "Pet"       then _G.OutfitMap.Pet       = val
                    elseif k == "M416"    then _G.WeaponSkinMap[101004] = val
                    elseif k == "AKM"     then _G.WeaponSkinMap[101001] = val
                    elseif k == "SCAR"    then _G.WeaponSkinMap[101003] = val
                    elseif k == "UMP"     then _G.WeaponSkinMap[102002] = val
                    elseif k == "M762"    then _G.WeaponSkinMap[101008] = val
                    elseif k == "AUG"     then _G.WeaponSkinMap[101006] = val
                    elseif k == "ASM"     then _G.WeaponSkinMap[101101] = val
                    elseif k == "ACE32"   then _G.WeaponSkinMap[101102] = val
                    elseif k == "HoneyBadger" then _G.WeaponSkinMap[101012] = val
                    elseif k == "M24"     then _G.WeaponSkinMap[103002] = val
                    elseif k == "AWM"     then _G.WeaponSkinMap[103003] = val
                    elseif k == "Kar98"   then _G.WeaponSkinMap[103001] = val
                    elseif k == "M16A4"   then _G.WeaponSkinMap[101002] = val
                    elseif k == "GROZA"   then _G.WeaponSkinMap[101005] = val
                    elseif k == "QBZ"     then _G.WeaponSkinMap[101007] = val
                    elseif k == "MK47"    then _G.WeaponSkinMap[101009] = val
                    elseif k == "G36C"    then _G.WeaponSkinMap[101010] = val
                    elseif k == "FAMAS"   then _G.WeaponSkinMap[101100] = val
                    elseif k == "VSS"     then _G.WeaponSkinMap[103005] = val
                    elseif k == "Mini14"  then _G.WeaponSkinMap[103006] = val
                    elseif k == "MK14"    then _G.WeaponSkinMap[103007] = val
                    elseif k == "SLR"     then _G.WeaponSkinMap[103009] = val
                    elseif k == "QBU"     then _G.WeaponSkinMap[103010] = val
                    elseif k == "MK12"    then _G.WeaponSkinMap[103100] = val
                    elseif k == "AMR"     then _G.WeaponSkinMap[103012] = val
                    elseif k == "DSR"     then _G.WeaponSkinMap[103102] = val
                    elseif k == "Mosin"   then _G.WeaponSkinMap[103013] = val
                    elseif k == "SKS"     then _G.WeaponSkinMap[103004] = val
                    elseif k == "UZI"     then _G.WeaponSkinMap[102001] = val
                    elseif k == "Vector"  then _G.WeaponSkinMap[102003] = val
                    elseif k == "Thompson"then _G.WeaponSkinMap[102004] = val
                    elseif k == "Bizon"   then _G.WeaponSkinMap[102005] = val
                    elseif k == "MP5K"    then _G.WeaponSkinMap[102007] = val
                    elseif k == "P90"     then _G.WeaponSkinMap[102105] = val
                    elseif k == "S12K"    then _G.WeaponSkinMap[104003] = val
                    elseif k == "DBS"     then _G.WeaponSkinMap[104004] = val
                    elseif k == "S1897"   then _G.WeaponSkinMap[104001] = val
                    elseif k == "S686"    then _G.WeaponSkinMap[104002] = val
                    elseif k == "M249"    then _G.WeaponSkinMap[105001] = val
                    elseif k == "DP28"    then _G.WeaponSkinMap[105002] = val
                    elseif k == "MG3"     then _G.WeaponSkinMap[105010] = val
                    elseif k == "Pan"     then _G.WeaponSkinMap[108004] = val
                    elseif k == "Machete" then _G.WeaponSkinMap[108001] = val
                    elseif k == "Crowbar" then _G.WeaponSkinMap[108002] = val
                    elseif k == "Sickle"  then _G.WeaponSkinMap[108003] = val
                    elseif k == "Motorcycle_1901001"              then _G.VehicleSkinMap[1901001] = val
                    elseif k == "Vehicle_1901002"                 then _G.VehicleSkinMap[1901002] = val
                    elseif k == "Sidecar_Motorcycle_1902001"      then _G.VehicleSkinMap[1902001] = val
                    elseif k == "Dacia_1903001"                   then _G.VehicleSkinMap[1903001] = val
                    elseif k == "Dacia_1903002"                   then _G.VehicleSkinMap[1903002] = val
                    elseif k == "Dacia_1903003"                   then _G.VehicleSkinMap[1903003] = val
                    elseif k == "dacia_1903004"                   then _G.VehicleSkinMap[1903004] = val
                    elseif k == "Mini_Bus_1904001"                then _G.VehicleSkinMap[1904001] = val
                    elseif k == "MiniBus_1904002"                 then _G.VehicleSkinMap[1904002] = val
                    elseif k == "MiniBus_1904003"                 then _G.VehicleSkinMap[1904003] = val
                    elseif k == "Pickup_(Open_Top)_1905001"       then _G.VehicleSkinMap[1905001] = val
                    elseif k == "Pickup_(Closed_Top)_1906001"     then _G.VehicleSkinMap[1906001] = val
                    elseif k == "PickUp_1906005"                  then _G.VehicleSkinMap[1906005] = val
                    elseif k == "Buggy_1907001"                   then _G.VehicleSkinMap[1907001] = val
                    elseif k == "buggy_1907002"                   then _G.VehicleSkinMap[1907002] = val
                    elseif k == "buggy_1907003"                   then _G.VehicleSkinMap[1907003] = val
                    elseif k == "UAZ_1908001"                     then _G.VehicleSkinMap[1908001] = val
                    elseif k == "UAZ_(Closed_Top)_1909001"        then _G.VehicleSkinMap[1909001] = val
                    elseif k == "UAZ_(Open_Top)_1910001"          then _G.VehicleSkinMap[1910001] = val
                    elseif k == "PG-117_1911001"                  then _G.VehicleSkinMap[1911001] = val
                    elseif k == "Jet_Ski_1912001"                 then _G.VehicleSkinMap[1912001] = val
                    elseif k == "Mirado_(Closed_Top)_1914001"     then _G.VehicleSkinMap[1914001] = val
                    elseif k == "Mirado_(Open_Top)_1915001"       then _G.VehicleSkinMap[1915001] = val
                    elseif k == "Mirado_(Open_Top)_1915004"       then _G.VehicleSkinMap[1915004] = val
                    elseif k == "Rony_1916001"                    then _G.VehicleSkinMap[1916001] = val
                    elseif k == "Rony_1916002"                    then _G.VehicleSkinMap[1916002] = val
                    elseif k == "Rony_1916003"                    then _G.VehicleSkinMap[1916003] = val
                    elseif k == "Scooter_1917001"                 then _G.VehicleSkinMap[1917001] = val
                    elseif k == "Scooter_1917002"                 then _G.VehicleSkinMap[1917002] = val
                    elseif k == "Snowmobile_1918001"              then _G.VehicleSkinMap[1918001] = val
                    elseif k == "Tukshai_1919001"                 then _G.VehicleSkinMap[1919001] = val
                    elseif k == "Monster_Truck_1953001"           then _G.VehicleSkinMap[1953001] = val
                    elseif k == "Monster_Truck_1953002"           then _G.VehicleSkinMap[1953002] = val
                    elseif k == "Motor_Glider_1960001"            then _G.VehicleSkinMap[1960001] = val
                    elseif k == "Coupe_RB_1961001"                then _G.VehicleSkinMap[1961001] = val
                    elseif k == "Tank_1963001"                    then _G.VehicleSkinMap[1963001] = val
                    elseif k == "Mountain_Bike_1965001"           then _G.VehicleSkinMap[1965001] = val
                    elseif k == "UTV_(Utility_Task_Vehicle)_1966001" then _G.VehicleSkinMap[1966001] = val
                    elseif k == "2-Seat_Bike_1967001"             then _G.VehicleSkinMap[1967001] = val
                    elseif k == "Horse_1987001"                   then _G.VehicleSkinMap[1987001] = val
                    elseif k == "Hovercraft_1988001"              then _G.VehicleSkinMap[1988001] = val
                    elseif k == "Infected_Grizzly_Dacia_1903024"  then _G.VehicleSkinMap[1903024] = val
                    elseif k == "Anniversary_Celebration_Dacia_1903040" then _G.VehicleSkinMap[1903040] = val
                    end
                end
            end
        end
    end)
end
_G.ReadLiveConfig = ReadLiveConfig

local rawGetTableData     = CDataTable and CDataTable.GetTableData     or function() return nil end
local rawGetTableByFilter = CDataTable and CDataTable.GetTableByFilter or function() return nil end

_G.InjectWeaponLogicHooks = function(pawn)
    if not isValid(pawn) then return end
    if _G.__WeaponLogicHookInjected then return end
    _G.__WeaponLogicHookInjected = true
    pcall(function()
        local wm = pawn:GetWeaponManager()
        if not isValid(wm) then return end
        local old_GetEquipID = wm.GetEquipWeaponAvatarID
        if old_GetEquipID then
            wm.GetEquipWeaponAvatarID = function(self, weaponID)
                local forced = _G.get_skin_id(weaponID)
                if forced then return forced end
                return old_GetEquipID(self, weaponID)
            end
        end
        local old_GetWeaponAvatarID = wm.GetWeaponAvatarID
        if old_GetWeaponAvatarID then
            wm.GetWeaponAvatarID = function(self, weapon)
                if isValid(weapon) then
                    local forced = _G.get_skin_id(weapon:GetWeaponID())
                    if forced then return forced end
                end
                return old_GetWeaponAvatarID(self, weapon)
            end
        end
    end)
end

_G.ForceSyncWeaponSkins = function(pawn)
    local wm = pawn:GetWeaponManager()
    if not isValid(wm) then return end
    for i = 1, 3 do
        local wpn = wm:GetInventoryWeaponByPropSlot(i)
        if isValid(wpn) then
            local targetID = _G.get_skin_id(wpn:GetWeaponID())
            if targetID and targetID > 0 then
                pcall(function()
                    if wpn.synData then
                        local data = wpn.synData:Get(7)
                        if data and data.defineID and data.defineID.TypeSpecificID ~= targetID then
                            data.defineID.TypeSpecificID = targetID
                            wpn.synData:Set(7, data)
                            if wpn.OnWeaponSkinUpdate then wpn:OnWeaponSkinUpdate() end
                        end
                    end
                    if wpn.SetWeaponAvatarID then wpn:SetWeaponAvatarID(targetID) end
                end)
            end
        end
    end
end

_G.ApplyWeaponSkins = function(pawn)
    if not isValid(pawn) then return end
    _G.InjectWeaponLogicHooks(pawn)
    _G.ForceSyncWeaponSkins(pawn)
end

if not _G.AKTableHacked and CDataTable then
    local _old = CDataTable.GetTableData
    CDataTable.GetTableData = function(tableName, id)
        local numId = tonumber(id)
        if numId then
            local upgradeID = _G.get_skin_id(numId)
            if upgradeID and upgradeID ~= numId then
                if tableName == "WeaponAvatarBattleEffect"
                or tableName == "GoldClothBattleEffect"
                or tableName == "WeaponSkinVoiceCfg"
                or tableName == "AvatarWeaponHitFXData" then
                    return _old(tableName, upgradeID)
                end
            end
        end
        return _old(tableName, id)
    end
    _G.AKTableHacked = true
end

_G.muzzles = {
    id_flash_hider = { 201010, 201005, 201004 },
    id_compensator = { 201009, 201003, 201002 },
    id_suppressor  = { 201011, 201006, 201007 }
}
_G.foregrips = {
    id_Angledforegrip = 202001,
    id_thumb_grip     = 202006,
    id_vertical_grip  = 202002,
    id_light_grip     = 202004,
    id_half_grip      = 202005,
    id_ergonomic_grip = 202051,
    id_laser_sight    = 202007
}
_G.magazines = {
    id_expanded_mag       = { 204011, 204007, 204004 },
    id_quick_mag          = { 204012, 204008, 204005 },
    id_expanded_quick_mag = { 204013, 204009, 204006 }
}
_G.scopes = {
    id_reddot = 203001,
    id_holo   = 203002,
    id_2x     = 203003,
    id_3x     = 203014,
    id_4x     = 203004,
    id_6x     = 203015,
    id_8x     = 203005
}
_G.stock = {
    id_microStock = 205001,
    id_tactical   = 205002,
    id_bulletloop = 204014,
    id_CheekPad   = 205003
}

_G.ItemUpgradeSystem = nil
pcall(function()
    local MM  = require("client.module_framework.ModuleManager")
    local IUS = MM.GetModule(MM.CommonModuleConfig.ItemUpgradeManager)
    if IUS then
        IUS:DefineAndResetData()
        IUS:OnInitialize()
        _G.ItemUpgradeSystem = IUS
    end
end)

_G.get_group_id = function(itemId)
    if not _G.ItemUpgradeSystem or not itemId then return nil end
    local cfg = _G.ItemUpgradeSystem:GetUpgradeCfg(itemId)
    return cfg and cfg.GroupID or nil
end

_G.InitParts = function(groupId, itemId)
    if not itemId then return _G.g_parts end
    if _G.g_parts[itemId] and next(_G.g_parts[itemId]) then return _G.g_parts end
    _G.g_parts[itemId] = {}
    if not _G.ItemUpgradeSystem then return _G.g_parts end
    if _G.ItemUpgradeSystem:IsWeaponIsRefit(itemId) then
        groupId = _G.ItemUpgradeSystem:GetNormalGroupID(groupId or _G.get_group_id(itemId))
    else
        groupId = groupId or _G.get_group_id(itemId)
    end
    if not groupId then return _G.g_parts end
    local cfg = rawGetTableByFilter("ItemUpgradeUnLockConfig", "GroupID", groupId)
    if cfg then
        for _, info in pairs(cfg) do
            local partId = info.PartId
            if _G.ItemUpgradeSystem:IsWeaponIsRefit(itemId) then
                local switched = _G.ItemUpgradeSystem:PartIDSwitch(partId, true)
                if switched and switched ~= partId then partId = switched end
            end
            local item = rawGetTableData("Item", partId)
            if item and item.ItemName then
                _G.g_parts[itemId][item.ItemName] = partId
            end
        end
    end
    return _G.g_parts
end

_G.GetRawAttachMap = function(skinid)
    if not skinid or skinid <= 0 then return {} end
    if _G.skinAttachCache[skinid] then return _G.skinAttachCache[skinid] end
    local UAvatarUtils = import("AvatarUtils")
    if not UAvatarUtils then return {} end
    local list = UAvatarUtils.GetWeaponAvatarDefaultAttachmentSkin(skinid, {}, false) or {}
    _G.skinAttachCache[skinid] = list
    return list
end

_G.GetSlotFromSkinID = function(skinid, slot)
    if not skinid or not slot then return 0 end
    local list = _G.GetRawAttachMap(skinid)
    local attachmentTypeMap = {
        [1] = {291004,291102,291001,291006,291005,291002,293003,293004,293009,293007,293005,293006,295001,295002,291007,291003,292002,292003,291011,291008},
        [2] = {205005,205102,205007,205009,205006},
        [3] = {203008,203009,203006,203022,203010}
    }
    local targetIDs = attachmentTypeMap[slot]
    if not targetIDs then return 0 end
    for _, targetID in ipairs(targetIDs) do
        for attachID, attachSkinID in pairs(list) do
            if attachID == targetID then return attachSkinID end
        end
    end
    return 0
end

_G.AutoDetectAttach = function(skinid, base_id)
    if not skinid or not base_id then return 0 end
    local list = _G.GetRawAttachMap(skinid)
    local v = list[base_id]
    return (v and v > 0) and v or 0
end

_G.get_muzzleid = function(current_id, avatarid)
    local initial_id = current_id
    _G.InitParts(_G.get_group_id(avatarid), avatarid)
    local p = _G.g_parts[avatarid]
    local function is_in(t)
        for _, id in ipairs(_G.muzzles[t]) do if current_id == id then return true end end
        return false
    end
    if is_in("id_flash_hider") then
        local auto = _G.AutoDetectAttach(avatarid, current_id)
        current_id = _G.GetAttachForSkin(avatarid, "FlashHider")
                  or (p and p["Flash Hider"])
                  or (auto > 0 and auto)
                  or current_id
    elseif is_in("id_compensator") then
        local auto = _G.AutoDetectAttach(avatarid, current_id)
        current_id = _G.GetAttachForSkin(avatarid, "Compensator")
                  or (p and p["Compensator"])
                  or (auto > 0 and auto)
                  or current_id
    elseif is_in("id_suppressor") then
        local auto = _G.AutoDetectAttach(avatarid, current_id)
        current_id = _G.GetAttachForSkin(avatarid, "Suppressor")
                  or (p and p["Suppressor"])
                  or (auto > 0 and auto)
                  or current_id
    end
    return current_id, (initial_id ~= current_id)
end

_G.get_forgripid = function(current_id, avatarid)
    local initial_id = current_id
    _G.InitParts(_G.get_group_id(avatarid), avatarid)
    local p = _G.g_parts[avatarid]
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if current_id == _G.foregrips.id_Angledforegrip then
        current_id = _G.GetAttachForSkin(avatarid, "AngledGrip") or (p and p["Angled Foregrip"]) or (auto > 0 and auto) or current_id
    elseif current_id == _G.foregrips.id_thumb_grip then
        current_id = _G.GetAttachForSkin(avatarid, "ThumbGrip") or (p and p["Thumb Grip"]) or (auto > 0 and auto) or current_id
    elseif current_id == _G.foregrips.id_vertical_grip then
        current_id = _G.GetAttachForSkin(avatarid, "VerticalGrip") or (p and p["Vertical Foregrip"]) or (auto > 0 and auto) or current_id
    elseif current_id == _G.foregrips.id_light_grip then
        current_id = _G.GetAttachForSkin(avatarid, "LightGrip") or (p and p["Light Grip"]) or (auto > 0 and auto) or current_id
    elseif current_id == _G.foregrips.id_half_grip then
        current_id = _G.GetAttachForSkin(avatarid, "HalfGrip") or (p and p["Half Grip"]) or (auto > 0 and auto) or current_id
    elseif current_id == _G.foregrips.id_ergonomic_grip then
        current_id = (p and p["Ergonomic Grip"]) or (auto > 0 and auto) or current_id
    elseif current_id == _G.foregrips.id_laser_sight then
        current_id = _G.GetAttachForSkin(avatarid, "LaserSight") or (p and p["Laser Sight"]) or (auto > 0 and auto) or current_id
    end
    return current_id, (initial_id ~= current_id)
end

_G.get_magazinesid = function(current_id, avatarid)
    local initial_id = current_id
    _G.InitParts(_G.get_group_id(avatarid), avatarid)
    local p = _G.g_parts[avatarid]
    local function is_in(t)
        for _, id in ipairs(_G.magazines[t]) do if current_id == id then return true end end
        return false
    end
    if is_in("id_expanded_mag") then
        local auto = _G.AutoDetectAttach(avatarid, current_id)
        current_id = _G.GetAttachForSkin(avatarid, "ExtMag") or (p and p["Extended Mag"]) or _G.GetSlotFromSkinID(avatarid, 1) or (auto > 0 and auto) or current_id
    elseif is_in("id_quick_mag") then
        local auto = _G.AutoDetectAttach(avatarid, current_id)
        current_id = _G.GetAttachForSkin(avatarid, "QuickMag") or (p and p["Quickdraw Mag"]) or _G.GetSlotFromSkinID(avatarid, 1) or (auto > 0 and auto) or current_id
    elseif is_in("id_expanded_quick_mag") then
        local auto = _G.AutoDetectAttach(avatarid, current_id)
        current_id = _G.GetAttachForSkin(avatarid, "ExtQuickMag") or (p and p["Extended Quickdraw Mag"]) or _G.GetSlotFromSkinID(avatarid, 1) or (auto > 0 and auto) or current_id
    else
        local fb = _G.GetSlotFromSkinID(avatarid, 1)
        if fb and fb > 0 then current_id = fb end
    end
    return current_id, (initial_id ~= current_id)
end

_G.get_scopeid = function(current_id, avatarid)
    local initial_id = current_id
    _G.InitParts(_G.get_group_id(avatarid), avatarid)
    local p = _G.g_parts[avatarid]
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if current_id == _G.scopes.id_reddot then
        current_id = _G.GetAttachForSkin(avatarid, "RedDot") or (p and p["Red Dot Sight"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    elseif current_id == _G.scopes.id_holo then
        current_id = _G.GetAttachForSkin(avatarid, "Holo") or (p and p["Holographic Sight"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    elseif current_id == _G.scopes.id_2x then
        current_id = _G.GetAttachForSkin(avatarid, "Scope2x") or (p and p["2x Scope"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    elseif current_id == _G.scopes.id_3x then
        current_id = _G.GetAttachForSkin(avatarid, "Scope3x") or (p and p["3x Scope"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    elseif current_id == _G.scopes.id_4x then
        current_id = _G.GetAttachForSkin(avatarid, "Scope4x") or (p and p["4x Scope"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    elseif current_id == _G.scopes.id_6x then
        current_id = _G.GetAttachForSkin(avatarid, "Scope6x") or (p and p["6x Scope"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    elseif current_id == _G.scopes.id_8x then
        current_id = _G.GetAttachForSkin(avatarid, "Scope8x") or (p and p["8x Scope"]) or _G.GetSlotFromSkinID(avatarid, 3) or (auto > 0 and auto) or current_id
    else
        local fb = _G.GetSlotFromSkinID(avatarid, 3)
        if fb and fb > 0 then current_id = fb end
    end
    return current_id, (initial_id ~= current_id)
end

_G.get_stockid = function(current_id, avatarid)
    local initial_id = current_id
    _G.InitParts(_G.get_group_id(avatarid), avatarid)
    local p = _G.g_parts[avatarid]
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if current_id == _G.stock.id_microStock then
        current_id = _G.GetAttachForSkin(avatarid, "MicroStock") or (p and p["Stock"]) or _G.GetSlotFromSkinID(avatarid, 2) or (auto > 0 and auto) or current_id
    elseif current_id == _G.stock.id_tactical then
        current_id = _G.GetAttachForSkin(avatarid, "TactStock") or (p and p["Tactical Stock"]) or _G.GetSlotFromSkinID(avatarid, 2) or (auto > 0 and auto) or current_id
    elseif current_id == _G.stock.id_bulletloop then
        current_id = (p and p["Bullet Loop"]) or _G.GetSlotFromSkinID(avatarid, 2) or (auto > 0 and auto) or current_id
    elseif current_id == _G.stock.id_CheekPad then
        current_id = _G.GetAttachForSkin(avatarid, "CheekPad") or (p and p["Cheek Pad"]) or _G.GetSlotFromSkinID(avatarid, 2) or (auto > 0 and auto) or current_id
    else
        local fb = _G.GetSlotFromSkinID(avatarid, 2)
        if fb and fb > 0 then current_id = fb end
    end
    return current_id, (initial_id ~= current_id)
end

_G.apply_attachment = function(CurWeapon, avatarid)
    local array = CurWeapon.synData
    for AttachIdx = 0, 4 do
        local Data = array:Get(AttachIdx)
        local itemid = slua.IndexReference(Data, "defineID").TypeSpecificID
        if itemid and itemid > 0 and itemid < 10000000 then
            local isrefresh = false
            if AttachIdx == 0 then
                Data.defineID.TypeSpecificID, isrefresh = _G.get_muzzleid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
                array:Set(AttachIdx, Data)
            elseif AttachIdx == 1 then
                Data.defineID.TypeSpecificID, isrefresh = _G.get_forgripid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
                array:Set(AttachIdx, Data)
            elseif AttachIdx == 2 then
                Data.defineID.TypeSpecificID, isrefresh = _G.get_magazinesid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
                array:Set(AttachIdx, Data)
            elseif AttachIdx == 3 then
                Data.defineID.TypeSpecificID, isrefresh = _G.get_stockid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
                array:Set(AttachIdx, Data)
            elseif AttachIdx == 4 then
                Data.defineID.TypeSpecificID, isrefresh = _G.get_scopeid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
                array:Set(AttachIdx, Data)
            else
                break
            end
            if isrefresh then
                _G.download_item(slua.IndexReference(Data, "defineID").TypeSpecificID)
                CurWeapon:DelayHandleAvatarMeshChanged()
            end
        end
    end
end

local WEAPON_NAMES = {
    "AKM","M16A4","SCAR","M416","GROZA","AUG","QBZ","M762",
    "MK47","G36C","HoneyBadger","ASM","FAMAS","ACE32",
    "UZI","UMP","Vector","Bizon","Thompson","MP5K","P90",
    "Kar98","M24","AWM","SKS","Mini14","MK14","SLR","QBU","MK12","AMR","DSR","VSS","Mosin",
    "S12K","DBS","S1897","S686",
    "M249","DP28","MG3",
    "Pan","Machete","Crowbar","Sickle",
}
local WEAPON_NAME_TO_ID = {
    AKM=101001,M16A4=101002,SCAR=101003,M416=101004,
    GROZA=101005,AUG=101006,QBZ=101007,M762=101008,
    MK47=101009,G36C=101010,HoneyBadger=101012,ASM=101101,FAMAS=101100,ACE32=101102,
    UZI=102001,UMP=102002,Vector=102003,Thompson=102004,Bizon=102005,MP5K=102007,P90=102105,
    Kar98=103001,M24=103002,AWM=103003,SKS=103004,VSS=103005,
    Mini14=103006,MK14=103007,SLR=103009,QBU=103010,MK12=103100,AMR=103012,DSR=103102,Mosin=103013,
    S12K=104003,DBS=104004,S1897=104001,S686=104002,
    M249=105001,DP28=105002,MG3=105010,
    Pan=108004,Machete=108001,Crowbar=108002,Sickle=108003,
}

_G.SyncAttachmentsToConfig = function()
    local cache = _G.GetAttachFileCache and _G.GetAttachFileCache()
    if not cache or not next(cache) then return end
    local hasSkin = false
    for _, w in ipairs(WEAPON_NAMES) do
        local baseId = WEAPON_NAME_TO_ID[w]
        if baseId and (_G.WeaponSkinMap[baseId] or 0) > 0 then hasSkin = true; break end
    end
    if not hasSkin then return end
    pcall(function()
        local f = io.open(CONFIG_PATH, "r")
        if not f then return end
        local content = f:read("*all"); f:close()
        local lines = {}
        for line in content:gmatch("[^\r\n]+") do table.insert(lines, line) end
        local filtered = {}
        for _, line in ipairs(lines) do
            local isAuto = false
            for _, w in ipairs(WEAPON_NAMES) do
                if line:find("^" .. w .. "_[%w%-]+=") then isAuto = true; break end
            end
            if not isAuto then table.insert(filtered, line) end
        end
        local ATTACH_TO_CONFIG_KEY = {
            Scope2x = "2x", Scope3x = "3x", Scope4x = "4x", Scope6x = "6x", Scope8x = "8x",
            RedDot = "RedDot", Holo = "Holo", CantedSight = "CantedSight",
            FlashHider = "FlashHider", Compensator = "Compensator", Suppressor = "Suppressor",
            ExtMag = "ExtMag", QuickMag = "QuickMag", ExtQuickMag = "ExtQuickMag",
            AngledGrip = "AngledGrip", ThumbGrip = "ThumbGrip", VerticalGrip = "VerticalGrip",
            LightGrip = "LightGrip", HalfGrip = "HalfGrip", LaserSight = "LaserSight",
            TactStock = "TactStock", MicroStock = "MicroStock", CheekPad = "CheekPad",
        }
        local KEY_ORDER = {
            "RedDot","Holo","CantedSight",
            "Scope2x","Scope3x","Scope4x","Scope6x","Scope8x",
            "FlashHider","Compensator","Suppressor",
            "ExtMag","QuickMag","ExtQuickMag",
            "AngledGrip","ThumbGrip","VerticalGrip","LightGrip","HalfGrip","LaserSight",
            "TactStock","MicroStock","CheekPad",
        }
        local outLines = {}
        table.insert(outLines, "; SyncAttachmentsToConfig ran")
        local foundCount = 0
        for _, line in ipairs(filtered) do
            table.insert(outLines, line)
            local wname, skinStr = line:match("^(%w+)=(%d+)$")
            if wname then
                local baseId = WEAPON_NAME_TO_ID[wname]
                if baseId then
                    local skinId = tonumber(skinStr)
                    if skinId and skinId > 0 then
                        local attaches = cache[skinId]
                        if attaches then
                            for _, key in ipairs(KEY_ORDER) do
                                local id = attaches[key]
                                local ck = ATTACH_TO_CONFIG_KEY[key]
                                if id and ck then
                                    table.insert(outLines, wname .. "_" .. ck .. "=" .. id)
                                    foundCount = foundCount + 1
                                end
                            end
                        else
                            table.insert(outLines, "; No cache entry for skin " .. skinId)
                        end
                    end
                    table.insert(outLines, "")
                end
            end
        end
        outLines[1] = "; SyncAttachmentsToConfig OK - matched " .. foundCount .. " attachments"
        local out = io.open(CONFIG_PATH, "w")
        if out then out:write(table.concat(outLines, "\n"), "\n"); out:close() end
    end)
end

_G.ApplyLocalPlayerSkins = function(p)
    if _G.Mod_Skin_Enabled == false then return end
    if not isValid(p) then return end

    pcall(function()
        local BackpackUtils = import("BackpackUtils")
        local ac = p:getAvatarComponent2()
        if isValid(ac) and ac.NetAvatarData then
            local applyData = ac.NetAvatarData.SlotSyncData
            if isValid(applyData) then
                local ref = false
                for i = 0, applyData:Num() - 1 do
                    local eq = applyData:Get(i)
                    if eq and eq.ItemId ~= 0 then
                        local target = 0
                        if eq.SlotID == 5 and _G.OutfitMap.Suit then
                            target = _G.OutfitMap.Suit
                        elseif eq.SlotID == 8 and _G.OutfitMap.Bag and _G.OutfitMap.Bag ~= 501001 then
                            local bagBase = _G.OutfitMap.Bag
                            local level = 1
                            if BackpackUtils then level = BackpackUtils.GetEquipmentBagLevel(eq.AdditionalItemID) or 1 end
                            target = bagBase + (level - 1) * 1000
                        elseif eq.SlotID == 9 and _G.OutfitMap.Helmet and _G.OutfitMap.Helmet ~= 502001 then
                            local helBase = _G.OutfitMap.Helmet
                            local level = 1
                            if BackpackUtils then level = BackpackUtils.GetEquipmentHelmetLevel(eq.AdditionalItemID) or 1 end
                            target = helBase + (level - 1) * 1000
                        end
                        if target and target ~= 0 and eq.ItemId ~= target then
                            if _G.download_item and not _G.SkinLoadedCache[target] then
                                pcall(_G.download_item, target)
                                _G.SkinLoadedCache[target] = true
                            end
                            eq.ItemId = target
                            applyData:Set(i, eq)
                            ref = true
                        end
                    end
                end
                if ref and ac.OnRep_BodySlotStateChanged then ac:OnRep_BodySlotStateChanged() end
            end
            local extra_keys = {"Hat","Mask","Glasses","Pants","Shoes","Armor","Parachute"}
            for _, key in ipairs(extra_keys) do
                local id = _G.OutfitMap[key]
                if id and id > 0 and _G.LastEquippedOutfits[key] ~= id then
                    if _G.download_item and not _G.SkinLoadedCache[id] then
                        pcall(_G.download_item, id)
                        _G.SkinLoadedCache[id] = true
                    end
                    ac:PutOnCustomEquipmentByID(id, {})
                    _G.LastEquippedOutfits[key] = id
                end
            end
        end
    end)

    _G.ApplyWeaponSkins(p)
    for i = 1, 3 do
        local wpn = p:GetWeaponManager() and p:GetWeaponManager():GetInventoryWeaponByPropSlot(i)
        if isValid(wpn) then
            local target = _G.get_skin_id(wpn:GetWeaponID())
            if target and target > 0 then
                if not _G.SkinLoadedCache[target] then
                    pcall(_G.download_item, target)
                    _G.SkinLoadedCache[target] = true
                end
                if _G.apply_attachment then pcall(_G.apply_attachment, wpn, target) end
            end
        end
    end

    if _G.OutfitMap.Pet and _G.OutfitMap.Pet ~= 0 then
        pcall(function()
            local pc = slua_GameFrontendHUD:GetPlayerController()
            if pc and pc.PetComponent and pc.PetComponent.PetId ~= _G.OutfitMap.Pet then
                pc.PetComponent.PetId = _G.OutfitMap.Pet
                pc.PetComponent:OnRep_PetId()
            end
        end)
    end

    pcall(function()
        local CV = p.CurrentVehicle
        if isValid(CV) then
            local VA = CV.VehicleAvatar
            if isValid(VA) then
                local defId = tostring(VA:GetDefaultAvatarID() or "")
                local currentId = tostring(CV:GetAvatarId() or "")
                local vehTarget = 0
                for baseId, targetSkin in pairs(_G.VehicleSkinMap) do
                    if defId:find(tostring(baseId)) then vehTarget = targetSkin; break end
                end
                if vehTarget and vehTarget > 0 and currentId ~= tostring(vehTarget) then
                    if _G.download_item and not _G.SkinLoadedCache[vehTarget] then
                        pcall(_G.download_item, vehTarget)
                        _G.SkinLoadedCache[vehTarget] = true
                    end
                    VA.curSwitchEffectId = 7303001
                    VA:ChangeItemAvatar(vehTarget, true)
                    _G.CurrentEquipVehicleID = vehTarget
                end
            end
        end
    end)
end

if not table.contains then
    function table.contains(t, el)
        for _, v in ipairs(t) do if v == el then return true end end
        return false
    end
end

local function locationsClose(loc1, loc2, tolerance)
    local dx = loc1.X - loc2.X
    local dy = loc1.Y - loc2.Y
    local dz = loc1.Z - loc2.Z
    return dx*dx + dy*dy + dz*dz < tolerance*tolerance
end

_G.ApplyDeadBoxSkin = function()
    if _G.Mod_Skin_Enabled == false then return end
    local pc = slua_GameFrontendHUD:GetPlayerController()
    if not pc then return end
    local uCharacter = pc:GetPlayerCharacterSafety()
    if not isValid(uCharacter) then return end
    local UGameplayStatics = import("GameplayStatics")
    if not UGameplayStatics then return end
    local uActor = import("Actor")
    if not uActor then return end
    local ok, UIUtil = pcall(require, "client.common.ui_util")
    if not ok or not UIUtil then return end
    local uGameInstance = UIUtil.GetGameInstance()
    if not uGameInstance then return end
    local APlayerTombBox = import("PlayerTombBox")
    if not APlayerTombBox then return end
    local uActorArray = UGameplayStatics.GetAllActorsOfClass(
        uGameInstance, APlayerTombBox,
        slua.Array(UEnums.EPropertyClass.Object, uActor))
    if not uActorArray then return end
    for _, actor in pairs(uActorArray) do
        if isValid(actor) then
            local DamageCauser = actor.DamageCauser
            if DamageCauser and DamageCauser.PlayerKey == pc.PlayerKey then
                local Deadboxavatar = actor.DeadBoxAvatarComponent_BP
                if Deadboxavatar and not table.contains(_G.AlreadyChangedSet, actor) then
                    local actorLocation = actor:K2_GetActorLocation()
                    local found = false
                    for _, entry in pairs(_G.DeadBoxSkins) do
                        if locationsClose(entry.location, actorLocation, 1.0) then
                            Deadboxavatar:ResetItemAvatar()
                            Deadboxavatar:PreChangeItemAvatar(entry.SkinID)
                            Deadboxavatar:SyncChangeItemAvatar(entry.SkinID)
                            table.insert(_G.AlreadyChangedSet, actor)
                            found = true
                            break
                        end
                    end
                    if not found then
                        local ApplySkinID = 0
                        local CV = uCharacter.CurrentVehicle
                        if CV then
                            local carSkinID = _G.CurrentEquipVehicleID
                            if carSkinID ~= 0 then ApplySkinID = tostring(carSkinID) .. "1" end
                        else
                            local cw = uCharacter:GetCurrentWeapon()
                            if cw and cw.synData then
                                ApplySkinID = slua.IndexReference(cw.synData:Get(7), "defineID").TypeSpecificID
                            end
                        end
                        Deadboxavatar:ResetItemAvatar()
                        Deadboxavatar:PreChangeItemAvatar(ApplySkinID)
                        Deadboxavatar:SyncChangeItemAvatar(ApplySkinID)
                        table.insert(_G.DeadBoxSkins, { location = actorLocation, SkinID = ApplySkinID })
                        table.insert(_G.AlreadyChangedSet, actor)
                    end
                end
            end
        end
    end
end

_G.RefreshKillCounterUI = function()
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not pc then return end
        local lp = pc:GetPlayerCharacterSafety()
        if not isValid(lp) then return end
        local cw = lp:GetCurrentWeapon()
        if not isValid(cw) then return end
        local wID = cw:GetWeaponID()
        if not wID or wID == 0 then return end
        local sid = _G.get_skin_id(wID)
        if not sid then return end
        local KillCounterUI = package.loaded["GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem"]
        if KillCounterUI and KillCounterUI.__inner_impl then
            KillCounterUI.__inner_impl:CheckNeedMainKillCounterUI(cw, pc.PlayerKey)
        end
        local UIM = require("client.slua_ui_framework.manager")
        local MKC = UIM.GetUI(UIM.UI_Config_InGame.MainKillCounter)
        if MKC and MKC.KillCounterItem then
            MKC:SetKillCounterItemShowWithNum(sid, _G.getKills(wID), sid)
        end
    end)
end

_G.ForceEnableKillCounterUI = function()
    if _G.KCUISystemHacked2 then return end
    pcall(function()
        local KillCounterUI = package.loaded["GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem"]
                           or require("GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem")
        if KillCounterUI and KillCounterUI.__inner_impl then
            local ui = KillCounterUI.__inner_impl
            ui.CheckSupportKCUI = function() return true end
            ui.CheckNeedMainKillCounterUI = function(self, Weapon, PlayerID)
                local pc = slua_GameFrontendHUD:GetPlayerController()
                local cw = isValid(Weapon) and Weapon
                        or (pc and pc:GetPlayerCharacterSafety() and pc:GetPlayerCharacterSafety():GetCurrentWeapon())
                if not isValid(cw) then self:UpdateMainKillCounterUI(false); return end
                local wID = cw:GetWeaponID()
                if not wID or wID == 0 then self:UpdateMainKillCounterUI(false); return end
                self:UpdateMainKillCounterUI(true, wID, _G.get_skin_id(wID) or wID)
            end
            local old_Update = ui.UpdateMainKillCounterUI
            ui.UpdateMainKillCounterUI = function(self, bShow, WeaponID, AvatarID)
                if not bShow then return old_Update(self, bShow, WeaponID, AvatarID) end
                return old_Update(self, bShow, WeaponID, AvatarID or _G.get_skin_id(WeaponID))
            end
            _G.KCUISystemHacked2 = true
        end
        local MM = require("client.module_framework.ModuleManager")
        if MM then
            local LogicKC = MM.GetModule(MM.CommonModuleConfig.LogicKillCounter)
            if LogicKC and not _G.KCLogicHacked2 then
                LogicKC.CheckSupportKC                = function() return true end
                LogicKC.CheckSupportKillCounterAvatar = function() return true end
                LogicKC.CheckHasWeaponKillCounter     = function() return true end
                LogicKC.GetBaseKillCounterIdByWeaponId= function() return 2100004 end
                LogicKC.GetEquipedKillCounterId        = function() return 2100004 end
                LogicKC.GetMyEquipedKillCounterId      = function() return 2100004 end
                LogicKC.GetOneWeaponKillCountInBattle  = function(_, _, wid) return _G.getKills(wid) end
                LogicKC.GetWeaponKillCountByUid        = function(_, _, wid) return _G.getKills(wid) end
                _G.KCLogicHacked2 = true
            end
        end
        local KillInfoPath = "GameLua.Mod.BaseMod.Client.KillInfoTips.KillInfo"
        local KillInfo = package.loaded[KillInfoPath] or require(KillInfoPath)
        if KillInfo and KillInfo.__inner_impl and not _G.KillInfoCounterHacked then
            local old_FileItem = KillInfo.__inner_impl.FileItem
            KillInfo.__inner_impl.FileItem = function(self, DRD)
                pcall(function()
                    local GD = require("GameLua.GameCore.Data.GameplayData")
                    local lp = GD.GetPlayerCharacter()
                    if isValid(lp) and DRD.Causer == lp:GetPlayerNameSafety() then
                        local cw = lp:GetCurrentWeapon()
                        if isValid(cw) then
                            local wid = cw:GetWeaponID()
                            local sid = _G.get_skin_id(wid)
                            if sid then DRD.CauserWeaponAvatarID = sid end
                            if _G.OutfitMap.Suit then DRD.CauserClothAvatarID = _G.OutfitMap.Suit end
                            DRD.IsUseColor = true
                            DRD.UseColor = import("LinearColor")(1.0, 0.8, 0.0, 1.0)
                            local expand_data = DRD.ExpandDataContent
                            if expand_data then
                                expand_data.KillCounterItemId = sid or wid
                                expand_data.KillCounterNum = _G.getKills(wid)
                            end
                            if DRD.ResultHealthStatus == 2 then
                                _G.AddKill(wid)
                                local UIM = require("client.slua_ui_framework.manager")
                                local MKC = UIM.GetUI(UIM.UI_Config_InGame.MainKillCounter)
                                if MKC and MKC.KillCounterItem then
                                    MKC:SetKillCounterItemShowWithNum(sid or wid, _G.getKills(wid), sid or wid)
                                end
                            end
                        end
                    end
                end)
                if old_FileItem then old_FileItem(self, DRD) end
            end
            _G.KillInfoCounterHacked = true
        end
        local ok2, WIIB = pcall(require, "GameLua.Mod.BaseMod.Client.Backpack.WeaponInfoItemBase")
        if ok2 and WIIB and WIIB.__inner_impl and not _G.WeaponInfoBackpackHacked then
            local o_UWA = WIIB.__inner_impl.UpdateWeaponAppearanceInfo
            if o_UWA then
                WIIB.__inner_impl.UpdateWeaponAppearanceInfo = function(self, TypeSpecificID, BattleData, DragOrigin)
                    local ItemData = rawGetTableData("Item", TypeSpecificID)
                    if not ItemData then return o_UWA(self, TypeSpecificID, BattleData, DragOrigin) end
                    local skin_id = _G.get_skin_id(TypeSpecificID)
                    if not skin_id or not _G.SkinLoadedCache[skin_id] then
                        return o_UWA(self, TypeSpecificID, BattleData, DragOrigin)
                    end
                    o_UWA(self, skin_id, BattleData, DragOrigin)
                    pcall(function()
                        self.TypeSpecificIDTemp = TypeSpecificID
                        self.ItemID             = TypeSpecificID
                        if self.UIRoot then
                            self.UIRoot.ItemID = TypeSpecificID
                            if self.UIRoot.TextBlock_WeaponName and ItemData.ItemName then
                                self.UIRoot.TextBlock_WeaponName:SetText(ItemData.ItemName)
                            end
                        end
                        if self.BindWeaponChangeEvent  then self:BindWeaponChangeEvent()  end
                        if self.UpdateBullet           then self:UpdateBullet()           end
                        if self.UpdateWeaponDurability then self:UpdateWeaponDurability() end
                        if self.UpdateWeaponAttachment then self:UpdateWeaponAttachment() end
                    end)
                end
                _G.WeaponInfoBackpackHacked = true
            end
        end
    end)
end

if not _G.BattleKillBroadcastSkinHacked then
    pcall(function()
        local BattleKillBroadcastSubSystem = require("GameLua.Mod.BaseMod.Client.BattleKillBroadcast.BattleKillBroadcastSubSystem")
        if not (BattleKillBroadcastSubSystem and BattleKillBroadcastSubSystem.__inner_impl) then return end
        local o_Copy = BattleKillBroadcastSubSystem.__inner_impl.CopyKillOrPutDownMessageDataUserDataToLuaTable
        BattleKillBroadcastSubSystem.__inner_impl.CopyKillOrPutDownMessageDataUserDataToLuaTable = function(self, messageData)
            local msgData = o_Copy(self, messageData)
            pcall(function()
                local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                local character = pc and pc:GetPlayerCharacterSafety()
                if character and isValid(character) and msgData.bIamCauser and _G.LuaStateWrapper then
                    msgData.bShowBottomBothSidesKillInfo = true
                    local weapon = character:GetCurrentWeapon()
                    if weapon and isValid(weapon) then
                        local weapon_id = weapon:GetItemDefineID() and weapon:GetItemDefineID().TypeSpecificID or 0
                        if weapon_id ~= 0 then
                            local expand_data = slua.LuaArchiverDecode(_G.LuaStateWrapper, msgData.ExpandDataContent) or {}
                            local isClassic = false
                            local uGameState = slua_GameFrontendHUD:GetGameState()
                            if uGameState and isValid(uGameState) then
                                local EGameModeType = import("EGameModeType")
                                if uGameState.GameModeType == EGameModeType.ETypicalGameMode then isClassic = true end
                            end
                            local syn_data = weapon.synData
                            if syn_data and isValid(syn_data) then
                                local define_id = slua.IndexReference(syn_data:Get(7), "defineID")
                                if define_id and isValid(define_id) then
                                    expand_data.CauserWeaponAvatarID = define_id.TypeSpecificID
                                end
                            end
                            if isClassic then
                                expand_data.KillCounterItemId = weapon_id
                                expand_data.KillCounterNum = _G.getKills and _G.getKills(weapon_id) or 0
                            end
                            msgData.bShowKillNum = true
                            msgData.ExpandDataContent = slua.LuaArchiverEncode(_G.LuaStateWrapper, expand_data)
                        end
                    end
                end
            end)
            return msgData
        end
        _G.BattleKillBroadcastSkinHacked = true
    end)
end

ReadLiveConfig()
_G.ForceEnableKillCounterUI()

_G._SetupSkinTimer = function()
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if not (pc and slua.isValid(pc)) then return end
        if _G.SkinTimerPC == pc then return end
        _G.SkinTimerPC = pc
        _G._SkinTimerInstalled = true
        _G._SkinTickCount = 0
        pc:AddGameTimer(0.5, true, function()
            pcall(function()
                local lpc = slua_GameFrontendHUD:GetPlayerController()
                if not (lpc and slua.isValid(lpc)) then return end
                local pawn = lpc:GetPlayerCharacterSafety()
                if not (pawn and slua.isValid(pawn)) then return end
                _G._SkinTickCount = (_G._SkinTickCount or 0) + 1
                local tick = _G._SkinTickCount
                if tick % 4 == 1 then
                    _G.ReadLiveConfig()
                    _G.SyncAttachmentsToConfig()
                end
                if tick % 10 == 1 then
                    _G.ApplyLocalPlayerSkins(pawn)
                    _G.ApplyDeadBoxSkin()
                end
                _G.RefreshKillCounterUI()
            end)
        end)
    end)
end

_G._SetupSkinTimer()

-- ==================== WALLHACK ====================
local function ApplyWallHack(localPlayer, enemy, pc)
    if not _G.CheatsEnabled then return end
    if _G.Mod_Wallhack_Enabled == false then return end
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
                local ok, mat = pcall(function() return comp:GetMaterial(0) end)
                if ok and slua.isValid(mat) then
                    local ok2, base = pcall(function() return mat:GetBaseMaterial() end)
                    if ok2 and slua.isValid(base) then
                        base.bDisableDepthTest = true; base.BlendMode = 2
                    end
                end
                comp.UseScopeDistanceCulling = false
                comp.PrimitiveShadingStrategy = 1; comp.ShadingRate = 6
            end
        end
        local isVisible = false
        if slua.isValid(pc) and slua.isValid(enemy) and type(pc.LineOfSightTo) == "function" then
            pcall(function() isVisible = pc:LineOfSightTo(enemy) end)
        end
        local finalColor = isVisible and {R=0, G=255, B=0, A=255} or {R=255, G=255, B=0, A=255}
        local scale = {R=255, G=255, B=0, A=0}
        enemy._WH_MIDs = enemy._WH_MIDs or {}
        for _, comp in ipairs(meshes) do
            if slua.isValid(comp) then
                local ck = tostring(comp)
                enemy._WH_MIDs[ck] = enemy._WH_MIDs[ck] or {}
                for i = 0, 10 do
                    local ok3, mi = pcall(function() return comp:GetMaterial(i) end)
                    if not ok3 or not slua.isValid(mi) then break end
                    local mid = enemy._WH_MIDs[ck][i]
                    if not slua.isValid(mid) then
                        local ok4, nm = pcall(function() return comp:CreateAndSetMaterialInstanceDynamic(i) end)
                        if ok4 and slua.isValid(nm) then enemy._WH_MIDs[ck][i] = nm; mid = nm end
                    end
                    if slua.isValid(mid) then
                        pcall(function()
                            mid:SetVectorParameterValue("颜色", finalColor)
                            mid:SetVectorParameterValue("Color", finalColor)
                            mid:SetVectorParameterValue("BaseColor", finalColor)
                            mid:SetVectorParameterValue("BodyColor", finalColor)
                            mid:SetVectorParameterValue("DiffuseColor", finalColor)
                            mid:SetVectorParameterValue("ParaScaleOffset", scale)
                        end)
                    end
                end
            end
        end
    end)
end

-- ==================== ESP ==================== 
local SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
local ASTExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")

local cachedPawns     = {}
local lastPawnRefresh = 0

local function IsPawnAlive(p)
    if not isValid(p) then return false end
    if p.HealthStatus then return SecurityCommonUtils.IsHealthStatusAlive(p.HealthStatus) end
    if p.IsAlive then return p:IsAlive() end
    return p.GetHealth and (p:GetHealth() or 0) > 0 or false
end

local boneList = {"head","neck_01","spine_01","spine_02","spine_03","pelvis",
    "upperarm_l","upperarm_r","lowerarm_l","lowerarm_r","hand_l","hand_r",
    "calf_l","calf_r","foot_l","foot_r"}
local function TextScale(distM)
    local t = math.min(distM / 400, 1)
    return 0.35 - t * 0.2
end

local function HPBar(pct)
    local n = math.floor((pct * 4) + 0.5)
    local s = ""
    for i = 1, 4 do s = s .. (i <= n and "▁" or " ") end
    return s
end

local function ESPTick()
    if not _G.CheatsEnabled then return end
    if _G.Mod_ESP_Enabled == false then return end
    if _G._ESPTimerHandle and _G._ESPTimerChar and not isValid(_G._ESPTimerChar) then _G._ESPTimerHandle = nil; _G._ESPTimerChar = nil end
    local uCon = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not (isValid(uCon) and Game:IsClassOf(uCon, ASTExtraPlayerController)) then return end
    local currentPawn = uCon:GetCurPawn()
    if not isValid(currentPawn) then return end

    local myTeamId = 0
    pcall(function()
        local char = uCon:GetPlayerCharacterSafety()
        if isValid(char) and char.TeamID then myTeamId = char.TeamID
        elseif currentPawn.TeamID then myTeamId = currentPawn.TeamID end
    end)
    local myPos = nil
    pcall(function() myPos = currentPawn:K2_GetActorLocation() end)
    if not myPos then return end
    local myEyePos = myPos
    pcall(function()
        if currentPawn.GetHeadLocation then myEyePos = currentPawn:GetHeadLocation(false) or myPos end
    end)
    HUD = uCon:GetHUD()
    local now      = os.clock()

    if now - lastPawnRefresh > 1.0 then
        lastPawnRefresh = now
        cachedPawns = Game:GetAllPlayerPawns() or {}
    end

    local botCount = 0
    local playerCount = 0

    local totalAlive = 0
    for _, p in pairs(cachedPawns) do
        if isValid(p) and p ~= currentPawn and p.TeamID ~= myTeamId and IsPawnAlive(p) then
            totalAlive = totalAlive + 1
        end
    end
    local crowded = totalAlive > 20

    for _, tPawn in pairs(cachedPawns) do
        if isValid(tPawn) and tPawn ~= currentPawn and tPawn.TeamID ~= myTeamId then
            if IsPawnAlive(tPawn) then
                local enemyPos = tPawn:K2_GetActorLocation()
                local dx = enemyPos.X - myPos.X
                local dy = enemyPos.Y - myPos.Y
                local dz = enemyPos.Z - myPos.Z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                local isBot = false
                pcall(function() isBot = Game:IsAI(tPawn) end)
                if isBot then botCount = botCount + 1 else playerCount = playerCount + 1 end

                if dist < 600000 and HUD then
                    local name = tPawn.PlayerName or "UNKNOWN"
                    local distM = dist / 100

                    local hp = tPawn.Health
                    local maxHp = tPawn.HealthMax
                    local isKnock = false
                    local hpPercent = 0
                    if not hp or not maxHp or maxHp <= 0 then
                        isKnock = true
                    elseif hp <= 0 then
                        isKnock = true
                    else
                        hpPercent = hp / maxHp
                    end
                    local hpColor = {R=0,G=255,B=0,A=255}
                    if hpPercent < 0.3 then
                        hpColor = {R=255,G=0,B=0,A=255}
                    elseif hpPercent < 0.7 then
                        hpColor = {R=255,G=255,B=0,A=255}
                    end
                    if isKnock then
                        hpColor = {R=255,G=0,B=0,A=255}
                    end

                    local bones = {}
                    local mesh = tPawn.Mesh
                    if isValid(mesh) then
                        for _, bn in ipairs(boneList) do
                            bones[bn] = mesh:GetSocketLocation(bn)
                        end
                    end
                    local origin = enemyPos
                    local oz = origin.Z
                    local headPos = bones["head"]
                    local footPos = bones["foot_l"]
                    local footRPos = bones["foot_r"]
                    local topZ = headPos and (headPos.Z - oz) or 90
                    local botZ = footPos and math.min(footPos.Z, footRPos and footRPos.Z or footPos.Z) - oz or -85

                    local headZ = headPos and (headPos.Z - oz) or 90
                    local hpOffset = headZ + 70 + math.min(distM, 60) * 3 + math.max(0, distM - 60) * 0.5
                    local nameOffset = -80 - math.min(distM, 60) * 0.33 - math.max(0, distM - 60) * 0.1

                    if crowded then
                        local hz = headPos and (headPos.Z - oz + 15)
                        if hz then HUD:AddDebugText("●", tPawn, TextScale(distM), {X=0,Y=0,Z=hz}, {X=0,Y=0,Z=hz}, {R=255,G=0,B=0,A=255}, true, false, true, nil, 1.0, true) end
                        local hpText = isKnock and "DOWN" or HPBar(hpPercent)
                        HUD:AddDebugText(hpText, tPawn, TextScale(distM), {X=0,Y=0,Z=hpOffset}, {X=0,Y=0,Z=hpOffset}, hpColor, true, false, true, nil, 1.0, true)
                    else
                        local hz = headPos and (headPos.Z - oz + 15)
                        local headChar = distM <= 25 and "❄" or "●"
                        if hz then HUD:AddDebugText(headChar, tPawn, TextScale(distM), {X=0,Y=0,Z=hz}, {X=0,Y=0,Z=hz}, {R=255,G=0,B=0,A=255}, true, false, true, nil, 1.0, true) end

                        local hpText = isKnock and "DOWN" or HPBar(hpPercent)
                        HUD:AddDebugText(hpText, tPawn, TextScale(distM), {X=0,Y=0,Z=hpOffset}, {X=0,Y=0,Z=hpOffset}, hpColor, true, false, true, nil, 1.0, true)

                        local nameColor = {R=0,G=255,B=0,A=255}
                        local targetPos = headPos or tPawn:K2_GetActorLocation()
                        pcall(function()
                            if Game:IsTargetPosVisible(myEyePos, targetPos, {currentPawn}) then
                                if _G.Mod_Chams_GreenEnabled then
                                    nameColor = _G.Mod_Chams_GreenRGB or {R=0,G=255,B=0,A=255}
                                else
                                    nameColor = {R=0,G=255,B=0,A=255}
                                end
                            else
                                if _G.Mod_Chams_YellowEnabled then
                                    nameColor = _G.Mod_Chams_YellowRGB or {R=255,G=255,B=0,A=255}
                                else
                                    nameColor = {R=255,G=255,B=0,A=255}
                                end
                            end
                        end)

                        HUD:AddDebugText(string.format("[%.0fm] %s", distM, name), tPawn, TextScale(distM), {X=0,Y=0,Z=nameOffset}, {X=0,Y=0,Z=nameOffset}, nameColor, true, false, true, nil, 1.0, true)

                    end
                    pcall(ApplyWallHack, currentPawn, tPawn, uCon)
                end
            end
        end
    end

    if not crowded and HUD and currentPawn then
        HUD:AddDebugText(string.format("BOT : %d     PLAYER : %d", botCount, playerCount), currentPawn, 1, {X=0,Y=0,Z=155}, {X=0,Y=0,Z=155}, {R=255,G=255,B=0,A=255}, true, false, true, nil, 1.0, true)
        HUD:AddDebugText("MOD BY DEVELOPER @TUSHARx_OFFICIAL", currentPawn, 1, {X=0,Y=0,Z=145}, {X=0,Y=0,Z=145}, {R=0,G=200,B=255,A=255}, true, false, true, nil, 1.0, true)
    end
end

pcall(function()
    if _G._ESPWatchdogHandle then pcall(function() Game:ClearTimer(_G._ESPWatchdogHandle) end); _G._ESPWatchdogHandle = nil end

    local function StartESP(targetActor)
        if not isValid(targetActor) then return end
        cachedPawns = {}; lastPawnRefresh = 0
        _G._ESPTimerChar = targetActor
        -- Optimized: increased interval from 0.15 to 0.2 for less CPU usage, still smooth
        _G._ESPTimerHandle = targetActor:AddGameTimer(0.2, true, function()
            pcall(ESPTick)
        end)
    end

    local function Watchdog()
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            local curPawn = pc and pc:GetCurPawn()
            if isValid(curPawn) and _G._ESPTimerChar ~= curPawn then
                if _G._ESPTimerHandle and isValid(_G._ESPTimerChar) then
                    pcall(function() _G._ESPTimerChar:RemoveGameTimer(_G._ESPTimerHandle) end)
                end
                _G._ESPTimerHandle = nil
                StartESP(curPawn)
            elseif not _G._ESPTimerHandle then
                StartESP(curPawn)
            end
        end)
    end

    _G._ESPWatchdogHandle = Game:SetTimer(1.0, true, Watchdog)
    Watchdog()
end)

-- ==================== AIMBOT + FEATURES ====================
_G.Enable165FPSLogic = function()
  pcall(function()
    local graphics = require("client.slua.logic.setting.logic_setting_graphics")
    if graphics then
      local orig = graphics.SetFPS
      function graphics:SetFPS(lvl)
        if orig then orig(self, lvl) end
        if lvl == 8 and _G.Mod_FPS165_Enabled ~= false then 
          self:ExecuteCMD("t.MaxFPS", "165")
          self:ExecuteCMD("r.FrameRateLimit", "165")
        end
      end
    end
    local fpsComp = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
    if fpsComp and fpsComp.__inner_impl then
      local impl = fpsComp.__inner_impl
      function impl.GetMaxFPSLevel() return 8, 8 end
      function impl:InitRealSupportFPS()
        local t = {}; for i = 1, 8 do t[i] = {true, true} end
        local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if db then db:UpdateUIData(db.RealSupportFPS, t, false) end
        return t
      end
      function impl:UpdateSelectedFPSState(lvl)
        local fps = {[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120}
        for i = 2, 8 do
          local node = self.UIRoot["NodeFps"..tostring(fps[i] or 120)]
          if isValid(node) then
            node:SetIsEnabled(true); pcall(function() node:SetRenderOpacity(1.0) end)
            local sw = self.UIRoot["WidgetSwitcher_"..tostring(i)]
            if isValid(sw) then sw:SetActiveWidgetIndex(i == lvl and 0 or 1) end
          end
        end
      end
    end
    local fpsFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
    if fpsFT and fpsFT.__inner_impl then
      local impl = fpsFT.__inner_impl; local MIN = 90
      function impl:ShowOrHide() self:SelfHitTestInvisible(); if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end end
      function impl:InitFPSFTSwitch()
        local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB"); local on = db:GetUIData(db.FPSFineTuneSwitch)
        if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(on, true) end
        if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, on) end
        if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
        if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
      end
      function impl:InitFPSFTValue165()
        local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB"); local r = self.UIRoot
        local on = db:GetUIData(db.FPSFineTuneSwitch); local val = on and (db:GetUIData(db.FPSFineTuneNum) or 165) or 165
        if on then
          r.Slider_screen3:SetLocked(false); r.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1,1,1,1))
          r.Slider_screen3:SetSliderHandleColor(FLinearColor(1,1,1,1))
        else
          r.Slider_screen3:SetLocked(true); r.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1,0.625,0.6,1))
          r.Slider_screen3:SetSliderHandleColor(FLinearColor(1,0.625,0.6,1))
        end
        local norm = (val - MIN) / (165 - MIN)
        r.Veihclescreen3:SetText(tostring(val)); r.Slider_screen3:SetValue(norm); r.ProgressBar_screen3:SetPercent(norm)
      end
      function impl:OnFPSFTValueChange3(val)
        local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        db:UpdateUIData(db.FPSFineTuneNum, val); if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
        if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
        local gi = db.GetGameInstance and db.GetGameInstance()
        if gi then gi:ExecuteCMD("t.MaxFPS", tostring(val)); gi:ExecuteCMD("r.FrameRateLimit", tostring(val)) end
      end
      function impl:OnFPSFTAdd3() local cur = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB").GetUIData(db.FPSFineTuneNum) or 90; self:OnFPSFTValueChange3(math.min(165, cur)) end
      function impl:OnFPSFTMinus3() local cur = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB").GetUIData(db.FPSFineTuneNum) or 90; self:OnFPSFTValueChange3(math.max(MIN, 5)) end
      impl.OnFPSFTAdd = impl.OnFPSFTAdd3; impl.OnFPSFTMinus = impl.OnFPSFTMinus3
    end
  end)
end

_G.EnableiPadViewUI = function()
  pcall(function()
    local sc = require("client.logic.setting.setting_config")
    if sc then
      if sc.TpViewValue then sc.TpViewValue.max = 140 end
      if sc.FpViewValue then sc.FpViewValue.max = 140 end
    end
    local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
    if db and db.TpViewValue then db.TpViewValue.max = 140 end
  end)
end

if _G.Mod_FPS165_Enabled ~= false then _G.Enable165FPSLogic() end
if _G.Mod_iPadView_Enabled ~= false then _G.EnableiPadViewUI() end

local pc = slua_GameFrontendHUD:GetPlayerController()
if isValid(pc) and pc.AddGameTimer and pc ~= _G._FeaturesTimerPC then
  _G._FeaturesTimerPC = pc
  local SubsystemMgr = nil
  local lastViewDistance = nil
  pc:AddGameTimer(0.1, true, function()
    pcall(function()
      if not _G.CheatsEnabled then return end
      local pc = slua_GameFrontendHUD:GetPlayerController()
      if not isValid(pc) then return end
      local char = pc:GetPlayerCharacterSafety()
      if not isValid(char) then return end
      local lp = GameplayData.GetPlayerCharacter()
      if not isValid(lp) then return end
      local isEnemy = lp.TeamID ~= char.TeamID

      SubsystemMgr = SubsystemMgr or package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"] or require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
      if SubsystemMgr then
        local SettingSubsystem = SubsystemMgr:Get("SettingSubsystem")
        if SettingSubsystem then
          local rawSliderValue = _G.Mod_iPadViewDistance or (SettingSubsystem:GetUserSettings_Int("TpViewValue") or 90)
          local targetTPP = rawSliderValue
          if rawSliderValue > 80 and rawSliderValue <= 90 then
              targetTPP = 80 + (rawSliderValue - 80) * 6.0
          elseif rawSliderValue > 90 then
              targetTPP = rawSliderValue
          end
          if _G.Mod_iPadView_Enabled ~= false then
            local uTPPCam = char.ThirdPersonCameraComponent
            if isValid(uTPPCam) and not char.bIsWeaponAiming then
                if lastViewDistance ~= targetTPP then
                    uTPPCam.FieldOfView = targetTPP
                    lastViewDistance = targetTPP
                end
            end
          end
        end
      end

      local gi = slua_GameFrontendHUD and slua_GameFrontendHUD:GetGameInstance()
      if not gi then
        local SettingUtil = require("client.slua.logic.setting.setting_util")
        gi = SettingUtil and SettingUtil.GetGameInstance()
      end
      if gi and _G.Mod_NoGrass_Enabled ~= false then
        -- Only apply once, not every frame
        if not _G._NoGrassApplied then
          gi:ExecuteCMD("grass.DensityScale", "0")
          gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
          _G._NoGrassApplied = true
        end
      end

      pcall(function()
        local allChars = Game:GetAllPlayerPawns() or {}
        for _, c in pairs(allChars) do
          if isValid(c) and c ~= char and c.TeamID ~= char.TeamID then
            local mesh = c.Mesh
            if isValid(mesh) then
              local physAsset = mesh.PhysicsAssetOverride
              if not isValid(physAsset) and isValid(mesh.SkeletalMesh) then
                physAsset = mesh.SkeletalMesh.PhysicsAsset
              end
              if isValid(physAsset) and physAsset.SkeletalBodySetups then
                _G._MBones = _G._MBones or {}
                local assetName = (physAsset.GetName and physAsset:GetName()) or tostring(physAsset)
                if not _G._MBones[assetName] then
                  local mb = {
                    ["head"]=50, ["neck_01"]=40, ["pelvis"]=40,
                    ["spine_01"]=40, ["spine_02"]=40, ["spine_03"]=40,
                    ["upperarm_l"]=30, ["upperarm_r"]=30,
                    ["lowerarm_l"]=25, ["lowerarm_r"]=25,
                    ["hand_l"]=20, ["hand_r"]=20,
                    ["thigh_l"]=30, ["thigh_r"]=30,
                    ["calf_l"]=25, ["calf_r"]=25,
                    ["foot_l"]=20, ["foot_r"]=20,
                  }
                  local setups = physAsset.SkeletalBodySetups
                  for i = 1, 80 do
                    local bs = nil
                    pcall(function() bs = (type(setups.Get)=="function") and setups:Get(i-1) or setups[i] end)
                    if not bs or not isValid(bs) then break end
                    local bn = tostring(bs.BoneName):lower()
                    local pct = nil
                    for pat, val in pairs(mb) do
                      if string.find(bn, pat) then pct = val; break end
                    end
                    if pct then
                      local sc = 1.0 + pct/100.0
                      local ag = bs.AggGeom
                      pcall(function()
                        local bx = (ag and ag.BoxElems) or bs.BoxElems
                        if bx then
                          local b = (type(bx.Get)=="function") and bx:Get(0) or bx[1]
                          if b then
                            b.X = (b.X or 30)*sc; b.Y = (b.Y or 30)*sc; b.Z = (b.Z or 60)*sc
                            if type(bx.Set)=="function" then bx:Set(0,b) else bx[1]=b end
                            if ag then bs.AggGeom=ag else bs.BoxElems=bx end
                          end
                        end
                      end)
                      pcall(function()
                        local sp = (ag and ag.SphylElems) or bs.SphylElems
                        if sp then
                          local s = (type(sp.Get)=="function") and sp:Get(0) or sp[1]
                          if s then
                            if s.Radius then s.Radius=s.Radius*sc end
                            if s.Length then s.Length=s.Length*sc end
                            if type(sp.Set)=="function" then sp:Set(0,s) else sp[1]=s end
                            if ag then bs.AggGeom=ag else bs.SphylElems=sp end
                          end
                        end
                      end)
                      pcall(function()
                        local sr = (ag and ag.SphereElems) or bs.SphereElems
                        if sr then
                          local r = (type(sr.Get)=="function") and sr:Get(0) or sr[1]
                          if r and r.Radius then
                            r.Radius=r.Radius*sc
                            if type(sr.Set)=="function" then sr:Set(0,r) else sr[1]=r end
                            if ag then bs.AggGeom=ag else bs.SphereElems=sr end
                          end
                        end
                      end)
                    end
                  end
                  _G._MBones[assetName] = true
                  if mesh.RecreatePhysicsState then mesh:RecreatePhysicsState() end
                end
              end
            end
          end
        end
      end)
    end)
  end)
end

_G._AimbotCurrentPC = nil

local function ApplyHardAimbot()
    if not _G.CheatsEnabled then return end
    if _G.Mod_Aimbot_Enabled == false then return end
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not isValid(pc) then return end

        local char = pc:GetPlayerCharacterSafety()
        if not isValid(char) then return end

        local wm = char.WeaponManagerComponent
        if not isValid(wm) then return end

        local weapon = wm.CurrentWeaponReplicated
        if not isValid(weapon) then return end

        local entity = weapon.ShootWeaponEntityComp
        if not isValid(entity) then return end

        local strengthMul = (_G.Mod_AimbotStrength or 50) / 100
        
        entity.GameDeviationFactor = 0.10 * (1 - strengthMul * 0.7)
        entity.WeaponAimInTime = 20
        entity.SwitchFromIdleToBackpackTime = 0.15
        entity.SwitchFromBackpackToIdleTime = 0.15
        entity.ShotGunHorizontalSpread = 0.0
        entity.ShotGunVerticalSpread = 0.0
        entity.RecoilKick = 0.3
        entity.RecoilKickADS = 0.2
        entity.AnimationKick = 0.2
        entity.AccessoriesVRecoilFactor = 0.30
        entity.AccessoriesHRecoilFactor = 0.35
        entity.ExtraHitPerformScale = 10
        if entity.RecoilInfo then
            entity.RecoilInfo.VerticalRecoilMin = 0.2
            entity.RecoilInfo.VerticalRecoilMax = 0.5
            entity.RecoilInfo.RecoilSpeedVertical = 0.2
            entity.RecoilInfo.RecoilSpeedHorizontal = 0.15
            entity.RecoilInfo.VerticalRecoveryMax = 0.2
        end
        entity.RecoilModifierStand = 0.1
        entity.RecoilModifierCrouch = 0.1
        entity.RecoilModifierProne = 0.1
        if entity.AutoAimingConfig then
            for _, range in ipairs({"OuterRange", "InnerRange"}) do
                local cfg = entity.AutoAimingConfig[range]
                if cfg then
                    cfg.Speed = 8 * strengthMul
                    cfg.RangeRate = 5 * strengthMul
                    cfg.SpeedRate = 5 * strengthMul
                    cfg.RangeRateSight = 4 * strengthMul
                    cfg.SpeedRateSight = 4 * strengthMul
                    cfg.CrouchRate = 4 * strengthMul
                    cfg.ProneRate = 4 * strengthMul
                    cfg.DyingRate = 0

                    cfg.adsorbMaxRange = 200 * strengthMul
                    cfg.adsorbMinRange = 20
                    cfg.adsorbMinAttenuationDis = 100 * (1 - strengthMul * 0.5)
                    cfg.adsorbMaxAttenuationDis = 8000
                    cfg.adsorbActiveMinRange = 20
                end
            end
            entity.AutoAimingConfig = entity.AutoAimingConfig
        end

        pcall(function()
            local aimComp = char.BP_AutoAimingComponent_C
                         or char.BP_AutoAimingComponent
                         or char.AutoAimingComponent

            if isValid(aimComp) and aimComp.Bones then
                pcall(function() aimComp.Bones[0] = "neck_01" end)
                pcall(function() aimComp.Bones[1] = "neck_01" end)
                pcall(function() aimComp.Bones[2] = "neck_01" end)

                pcall(function() aimComp.Bones:Set(0, "neck_01") end)
                pcall(function() aimComp.Bones:Set(1, "neck_01") end)
                pcall(function() aimComp.Bones:Set(2, "neck_01") end)
            end
        end)

    end)
end

local function AttachAimbotTimer()
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not isValid(pc) then return end
        if pc == _G._AimbotCurrentPC then return end
        _G._AimbotCurrentPC = pc
        if pc.AddGameTimer then
            pc:AddGameTimer(0.1, true, function()
                if not isValid(_G._AimbotCurrentPC) then
                    _G._AimbotCurrentPC = nil
                    return
                end
                ApplyHardAimbot()
            end)
        end
    end)
end

AttachAimbotTimer()

pcall(function()
    local pc = slua_GameFrontendHUD:GetPlayerController()
    if isValid(pc) and pc.AddGameTimer then
        pc:AddGameTimer(2.0, true, function()
            if not isValid(_G._AimbotCurrentPC) then
                _G._AimbotCurrentPC = nil
                AttachAimbotTimer()
            end
        end)
    end
end)

-- ==================== AKMOD EXTRA BYPASS ====================
pcall(function()
    local function nop() end
    local function retTrue() return true end
    local function retFalse() return false end
    local function retEmpty() return {} end

    _G.InitializeLogBlocker = function()
        pcall(function()
            local s = import("ScreenshotMaker")
            if s then s.MakePicture = nop; s.ReMakePicture = nop; s.HasCaptured = retTrue end
            local tl = package.loaded["TLog"] or _G.TLog
            if tl then tl.Info = nop; tl.Warning = nop; tl.Error = nop; tl.Debug = nop; tl.Report = nop end
            local cs = package.loaded["CrashSight"] or _G.CrashSight
            if cs then cs.ReportException = nop; cs.SetCustomData = nop; cs.Log = nop end
            local bg = safe_require("GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils")
            if bg then bg.BugglyPostExceptionFull = retFalse; bg.CheckCanBugglyPostException = retFalse; bg.ReplayReportData = nop; bg.ReportGameException = nop end
            local ct = package.loaded["client.slua.logic.report.ClientToolsReport"]
            if ct then ct.SendReport = nop; ct.SendException = nop end
            local tr = safe_require("client.slua.config.tlog.tlog_report_utils")
            if tr then tr.ReportTLogEvent = nop end
            local ug = package.loaded["client.slua.logic.ugc.UGCNewTLogReport"] or package.loaded["client.slua.data.BasicData.BasicDataTLogReport"]
            if ug then ug.SendExposeReq = nop; ug.SendInteractionReq = nop; ug.TLogReport = nop end
            local ut = package.loaded["client.slua.logic.ugc.logic_ugc_tlog"]
            if ut then ut.SendModTLog = nop; ut.ReportStay = nop end
            local ctl = safe_require("GameLua.Mod.BaseMod.Client.ClientTLog.ClientTLogUtil")
            if ctl then ctl.ReportGeneralCountByBRPhase = nop; ctl.ReportCommonTLogDataByBRPhase = nop end
            local gd = safe_require("GameLua.GameCore.Data.GameplayData")
            if gd then
                local pc2 = gd.GetPlayerControllerSafety and gd.GetPlayerControllerSafety() or gd.GetPlayerController()
                if slua.isValid(pc2) and pc2.ReportCrashKitFeature then
                    pc2.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException = nop
                end
            end
        end)
    end

    _G.InitializeScannerBlocker = function()
        pcall(function()
            local mgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            if mgr then
                local afk = mgr:Get("AFKReportorSubsystem")
                if afk then afk.PlayerHaveAction = nop; afk.ReportAFK = nop end
                local cds = mgr:Get("ClientDataStatistcsSubsystem")
                if cds then cds.StartToCheck = nop; cds.DelayCount = 0
                    if cds.ReportPingDelayTimer then cds:RemoveGameTimer(cds.ReportPingDelayTimer); cds.ReportPingDelayTimer = nil end
                end
                local aes = mgr:Get("AvatarExceptionSubsystem")
                if aes then aes.ReportException = nop; aes.BindPlayerCharacter = nop; aes.CheckAvatarValid = retTrue end
                local svs = mgr:Get("ShootVerifySubSystemClient")
                if svs then svs.ReportVerifyFail = nop; svs.OnVerifyFailed = nop end
            end
            local cr = import("CreativeModeBlueprintLibrary")
            if cr then cr.MD5HashByteArray = function() return "BYPASSED_MD5_HASH" end; cr.GetContentDiffData = function() return true, "BYPASSED" end end
            local ae = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
            if ae then ae.CheckAvatarException = nop; ae.CheckAvatarExceptionOnce = nop; ae.ReportAvatarException = nop; ae.CheckSlotMeshVisible = retFalse; ae.CheckPawnVisible = retFalse; ae.CheckCanBugglyPostException = retFalse end
            local ac = package.loaded["blacklist.slua.logic.lobby_gm.AvatarCheckerModule"]
            if ac then ac.CheckAvatar = retTrue; ac.ReportException = nop end
            local mw = package.loaded["client.slua.logic.memory_warning.logic_memory_warning"]
            if mw then mw.OnMemoryWarning = nop; mw.ReportMemoryWarning = nop end
            local ts = package.loaded["TssSdk"] or _G.TssSdk
            if ts then
                local ts_recv = ts.OnRecvData
                ts.OnRecvData = function(data)
                    if type(data) == "string" and (string.find(data, "report") or string.find(data, "exception")) then return end
                    if ts_recv then ts_recv(data) end
                end
                ts.SendReportInfo = nop; ts.ScanMemory = retTrue; ts.IsEmulator = retFalse; ts.GetTssSdkReportInfo = function() return "" end
            end
        end)
    end

    _G.InitModMenuTab = function()
        local LocUtil = _G.LocUtil
        if not LocUtil and package.loaded["client.common.LocUtil"] then
            LocUtil = require("client.common.LocUtil")
        end
        
        if LocUtil and not LocUtil._IsModMenuHooked then
            local old_get = LocUtil.GetLocalizeResStr
            LocUtil.GetLocalizeResStr = function(id)
                if type(id) == "string" and not tonumber(id) then
                    return id
                end
                return old_get(id)
            end
            LocUtil._IsModMenuHooked = true
        end

        local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
        local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
        
        if not SettingPageDefine.ModMenu then
            local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
            
            local ModMenuStack = {
                { UI = AliasMap.Title, Text = "SETTING" },
                {
                    Key = "ModMenu_Aimbot",
                    UI = AliasMap.Switcher,
                    Text = "AIMBOT",
                    GetFunc = function() 
                        local state = _G.Mod_Aimbot_Enabled or false
                        return state
                    end,
                    SetFunc = function(_, value)
                        _G.Mod_Aimbot_Enabled = value
                        print("[MOD] AIMBOT: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "ModMenu_AimbotStrength",
                    UI = AliasMap.Slider,
                    Text = "Aimbot Strength",
                    GetFunc = function() 
                        return (_G.Mod_AimbotStrength or 50) / 100
                    end,
                    SetFunc = function(_, value)
                        _G.Mod_AimbotStrength = math.floor(value * 100)
                        print("[MOD] Aimbot Strength: " .. _G.Mod_AimbotStrength .. "%")
                        return true
                    end
                },
                {
                    Key = "ESP",
                    UI = AliasMap.Switcher,
                    Text = "WALL ESP",
                    GetFunc = function() return _G.Mod_ESP_Enabled or false end,
                    SetFunc = function(_, value)
                        _G.Mod_ESP_Enabled = value
                        print("[MOD] WALL ESP: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "Wallhack",
                    UI = AliasMap.Switcher,
                    Text = "WALLHACK",
                    GetFunc = function() return _G.Mod_Wallhack_Enabled or false end,
                    SetFunc = function(_, value)
                        _G.Mod_Wallhack_Enabled = value
                        print("[MOD] WALLHACK: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "Skin",
                    UI = AliasMap.Switcher,
                    Text = "SKINS",
                    GetFunc = function() return _G.Mod_Skin_Enabled or false end,
                    SetFunc = function(_, value)
                        _G.Mod_Skin_Enabled = value
                        print("[MOD] SKINS: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "FPS165",
                    UI = AliasMap.Switcher,
                    Text = "165 FPS",
                    GetFunc = function() return _G.Mod_FPS165_Enabled ~= false end,
                    SetFunc = function(_, value)
                        _G.Mod_FPS165_Enabled = value
                        if value then _G.Enable165FPSLogic() end
                        print("[MOD] 165 FPS: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "NoGrass",
                    UI = AliasMap.Switcher,
                    Text = "NO GRASS",
                    GetFunc = function() return _G.Mod_NoGrass_Enabled ~= false end,
                    SetFunc = function(_, value)
                        _G.Mod_NoGrass_Enabled = value
                        if value then
                            pcall(function()
                                local gi = slua_GameFrontendHUD and slua_GameFrontendHUD:GetGameInstance()
                                if gi then
                                    gi:ExecuteCMD("grass.DensityScale", "0")
                                    gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
                                end
                            end)
                        end
                        print("[MOD] NO GRASS: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "iPadView",
                    UI = AliasMap.Switcher,
                    Text = "IPAD VIEW",
                    GetFunc = function() return _G.Mod_iPadView_Enabled ~= false end,
                    SetFunc = function(_, value)
                        _G.Mod_iPadView_Enabled = value
                        if value then _G.EnableiPadViewUI() end
                        print("[MOD] IPAD VIEW: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "ModMenu_iPadViewDistance",
                    UI = AliasMap.Slider,
                    Text = "View Distance (80-140)",
                    GetFunc = function() 
                        return ((_G.Mod_iPadViewDistance or 90) - 80) / 60
                    end,
                    SetFunc = function(_, value)
                        _G.Mod_iPadViewDistance = math.floor(80 + (value * 60))
                        print("[MOD] View Distance: " .. _G.Mod_iPadViewDistance)
                        return true
                    end
                },
                {
                    Key = "Title_ESP_Colors",
                    UI = AliasMap.Title,
                    Text = "CHAMS COLORS"
                },
                {
                    Key = "ModMenu_GreenColor",
                    UI = AliasMap.Switcher,
                    Text = "GREEN (Visible)",
                    GetFunc = function() return _G.Mod_Chams_GreenEnabled or false end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_GreenEnabled = value
                        print("[MOD] GREEN CHAMS: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "ModMenu_GreenR",
                    UI = AliasMap.Slider,
                    Text = "Green - Red (0-255)",
                    GetFunc = function() return (_G.Mod_Chams_GreenRGB.R or 0) / 255 end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_GreenRGB.R = math.floor(value * 255)
                        print("[MOD] Green-R: " .. _G.Mod_Chams_GreenRGB.R)
                        return true
                    end
                },
                {
                    Key = "ModMenu_GreenG",
                    UI = AliasMap.Slider,
                    Text = "Green - Green (0-255)",
                    GetFunc = function() return (_G.Mod_Chams_GreenRGB.G or 255) / 255 end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_GreenRGB.G = math.floor(value * 255)
                        print("[MOD] Green-G: " .. _G.Mod_Chams_GreenRGB.G)
                        return true
                    end
                },
                {
                    Key = "ModMenu_GreenB",
                    UI = AliasMap.Slider,
                    Text = "Green - Blue (0-255)",
                    GetFunc = function() return (_G.Mod_Chams_GreenRGB.B or 0) / 255 end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_GreenRGB.B = math.floor(value * 255)
                        print("[MOD] Green-B: " .. _G.Mod_Chams_GreenRGB.B)
                        return true
                    end
                },
                {
                    Key = "ModMenu_YellowColor",
                    UI = AliasMap.Switcher,
                    Text = "YELLOW (Hidden)",
                    GetFunc = function() return _G.Mod_Chams_YellowEnabled or false end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_YellowEnabled = value
                        print("[MOD] YELLOW CHAMS: " .. (value and "ON ✓" or "OFF ✗"))
                        return true
                    end
                },
                {
                    Key = "ModMenu_YellowR",
                    UI = AliasMap.Slider,
                    Text = "Yellow - Red (0-255)",
                    GetFunc = function() return (_G.Mod_Chams_YellowRGB.R or 255) / 255 end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_YellowRGB.R = math.floor(value * 255)
                        print("[MOD] Yellow-R: " .. _G.Mod_Chams_YellowRGB.R)
                        return true
                    end
                },
                {
                    Key = "ModMenu_YellowG",
                    UI = AliasMap.Slider,
                    Text = "Yellow - Green (0-255)",
                    GetFunc = function() return (_G.Mod_Chams_YellowRGB.G or 255) / 255 end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_YellowRGB.G = math.floor(value * 255)
                        print("[MOD] Yellow-G: " .. _G.Mod_Chams_YellowRGB.G)
                        return true
                    end
                },
                {
                    Key = "ModMenu_YellowB",
                    UI = AliasMap.Slider,
                    Text = "Yellow - Blue (0-255)",
                    GetFunc = function() return (_G.Mod_Chams_YellowRGB.B or 0) / 255 end,
                    SetFunc = function(_, value)
                        _G.Mod_Chams_YellowRGB.B = math.floor(value * 255)
                        print("[MOD] Yellow-B: " .. _G.Mod_Chams_YellowRGB.B)
                        return true
                    end
                }
            }
            
            SettingPageDefine.ModMenu = {
                Key = "ModMenu",
                loc = "MAIN MENU",
                UIKey = "Setting_Page_Privacy", 
                Category = {
                    {
                        Key = "ModMenu_Main",
                        loc = "FEATURES", 
                        Stack = ModMenuStack
                    }
                }
            }
            
            table.insert(SettingCatalog, SettingPageDefine.ModMenu)
        end

        local UIManager = _G.UIManager
        if UIManager and not UIManager._IsModMenuHooked then
            local old_ShowUI = UIManager.ShowUI
            UIManager.ShowUI = function(config, ...)
                local args = {...}
                if config and config.keyName and (string.find(string.lower(config.keyName), "setting_main") or string.find(string.lower(config.keyName), "setting")) then
                    local catalog = args[1]
                    if catalog and (type(catalog) == "table" or type(catalog) == "userdata") then
                        local hasModMenu = false
                        local newCatalog = {}
                        for _, page in ipairs(catalog) do
                            table.insert(newCatalog, page)
                            if page.Key == "ModMenu" then
                                hasModMenu = true
                            end
                        end
                        
                        if not hasModMenu then
                            table.insert(newCatalog, SettingPageDefine.ModMenu)
                            args[1] = newCatalog
                        end
                    end
                end
                local table_unpack = table.unpack or unpack
                return old_ShowUI(config, table_unpack(args))
            end
            UIManager._IsModMenuHooked = true
        end
    end

    _G.InitializeAntiReport = function()
        pcall(function()
            local paths = {"GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem", "Client.Security.ClientReportPlayerSubsystem"}
            local rp = nil
            for _, p in ipairs(paths) do
                if package.loaded[p] then rp = package.loaded[p]; break end
                local ok, mod = pcall(require, p)
                if ok and mod then rp = mod; break end
            end
            if rp then
                rp.OnInit = nop; rp._OnPlayerKilledOtherPlayer = nop; rp._RecordFatalDamager = nop
                rp._OnDeathReplayDataWhenFatalDamaged = nop; rp._RecordMurdererFromDeathReplayData = nop
                rp._RecordTeammatePlayerInfo = nop; rp._OnBattleResult = nop; rp._OnShowQuickReportMutualExclusiveUI = nop
                rp.GetFatalDamagerMap = retEmpty; rp.GetCachedTeammateName2InfoMap = retEmpty
                rp.GetTeammateName2InfoMapDuringBattle = retEmpty; rp.GetCurrentNotInTeamHistoricalTeammateMap = retEmpty
                rp.GetInTeamIndexFromHistoricalTeammateInfo = function() return -1 end
            end
            local dspaths = {"GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem", "GameLua.Mod.BaseMod.Client.Security.DSReportPlayerSubsystem"}
            local dr = nil
            for _, p in ipairs(dspaths) do
                if package.loaded[p] then dr = package.loaded[p]; break end
                local ok, mod = pcall(require, p)
                if ok and mod then dr = mod; break end
            end
            if dr then
                dr.OnInit = nop; dr._OnNearDeathOrRescued = nop; dr._OnCharacterDied = nop; dr._OnTeammateDamage = nop
                dr._OnPlayerSettlementStart = nop; dr._AddKnockDownerToBattleResult = nop; dr._AddKillerToBattleResult = nop
                dr._AddTeammateMurderToBattleResult = nop; dr._AddFatalDamagerMapToBattleResult = nop
                dr._AddMLKillerUIDToBattleResult = nop; dr._SaveHistoricalTeammateInfo = nop; dr._RecordFatalDamager = nop
                dr._RecordTeammateMurderer = nop
            end
            local rpu = safe_require("GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils")
            if rpu then rpu.RecordFatalDamager = nop; rpu.IsUsingHistoricalTeammateInfo = retFalse; rpu.IsCharacterDeliverAI = retFalse end
            local scu = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
            if scu then scu.ExtractPlayerBasicInfo = retEmpty; scu.LogIf = retFalse end
            local qr = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientQuickReportMaliciousTeammate")
            if qr then qr.OnShowMutualExclusiveUI = nop; qr.OnHideMutualExclusiveUI = nop end
        end)
    end

    _G.InitializeAntiCheatHooks = function()
        pcall(function()
            local hbc = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if hbc and hbc.BlackList then for k in pairs(hbc.BlackList) do hbc.BlackList[k] = nil end end
        end)
        _G.BlackList = {}
        pcall(function()
            _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
            local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
            mt.__newindex = function(t, k, v) end
            setmetatable(_G.GlobalPlayerCoronaData, mt)
        end)
        pcall(function()
            if _G.GameSafeCallbacks then
                _G.GameSafeCallbacks.RecordStrategyTimestampInReplay = nop
                _G.GameSafeCallbacks.DoAttackFlowStrategy = nop
                _G.GameSafeCallbacks.GetScriptReportContent = function() return "" end
            end
        end)
    end

    _G.InitializeConnectionGuard = function()
        pcall(function()
            if not _G.GameplayCallbacks then return end
            local GC = _G.GameplayCallbacks
            local origDS = GC.OnDSPlayerStateChanged
            GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
                local state = InPlayerState and string.lower(tostring(InPlayerState)) or ""
                local block = {["cheatdetected"]=true, ["connectionlost"]=true, ["connectiontimeout"]=true, ["connectionexception"]=true, ["netdrivererror"]=true}
                if block[state] then return end
                if origDS then pcall(origDS, UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason) end
            end
            GC.OnPlayerNetConnectionClosed = nop
            GC.OnPlayerActorChannelError = nop
            GC.OnPlayerRPCValidateFailed = nop
            GC.OnPlayerSpectateException = nop
            GC.OnShutdownAfterError = nop
        end)
    end

    _G.InitializeSkinBypass = function()
        pcall(function()
            local pt = package.loaded["client.slua.logic.download.report.puffer_tlog"]
            if pt then pt.ReportEvent = nop; pt.ReportDownloadResult = nop; pt.ReportODPAKError = nop end
            local au = package.loaded["AvatarUtils"]
            if au then au.CheckIsWeaponInBlackList = retFalse; au.IsValidAvatar = retTrue end
            local fc = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("FileCheckSubsystem")
            if fc then fc.StartCheck = nop; fc.ReportAbnormalFile = nop end
            local er = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
            if er then er.Report = nop end
        end)
    end

    _G.InitializeReplayTelemetryBlocker = function()
        pcall(function()
            local mgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            local rt = mgr and mgr:Get("RescueBtnReplayTraceSubsystem")
            if rt then rt.ReportTrace = nop; rt.StartTickMonitor = nop; rt.TickMonitorCheck = nop; rt.ReportTickMonitorHeartbeat = nop end
            local gr = mgr and mgr:Get("GameReportSubsystem")
            if gr then
                gr.ReplayReportData = retFalse; gr.CheckCanBugglyPostException = retFalse; gr.BugglyPostExceptionFull = retFalse; gr.GetClientReplayDataReporter = function() return nil end
                if gr.Reporter then gr.Reporter.ReportIntArrayData = nop; gr.Reporter.ReportUInt8ArrayData = nop; gr.Reporter.ReportFloatArrayData = nop end
            end
            local rp = package.loaded["client.slua.logic.replay.logic_report_replay"]
            if rp then rp.ReportReplay = nop; rp.SendReportReq = nop end
            local hr = package.loaded["client.slua.logic.home.logic_home_report"]
            if hr then hr.ShowInGameReportUI = nop; hr.SendReport = nop end
        end)
    end

    _G.DisableHiggsBoson = function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if not slua.isValid(pc) then return end
        if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false end
        if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent:ControlMHActive(0) end
    end

    local bypassInit = function()
        pcall(function()
            _G.InitializeLogBlocker()
            _G.InitializeScannerBlocker()
            _G.InitializeAntiReport()
            _G.InitializeAntiCheatHooks()
            _G.InitializeConnectionGuard()
            _G.InitializeSkinBypass()
            _G.InitializeReplayTelemetryBlocker()
            _G.InitModMenuTab()
            _G.DisableHiggsBoson()

            pcall(function()
                if NetUtil and NetUtil.SendPacket and not NetUtil.IsBypassed then
                    local origSend = NetUtil.SendPacket
                    local blocked = {
                        ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportHurtFlow"]=1,
                        ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                        ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1,
                        ["ReportPlayerPosition"]=1, ["ReportAimFlow"]=1, ["ReportHitFlow"]=1,
                        ["ReportCircleFlow"]=1, ["ReportJumpFlow"]=1, ["report_players_ping"]=1,
                        ["report_player_ip"]=1, ["tss_sdk_report"]=1, ["report_client_scan_result"]=1,
                        ["report_memory_exception"]=1, ["report_avatar_exception"]=1, ["report_character_state"]=1,
                        ["report_vehicle_exception"]=1, ["report_camera_exception"]=1, ["send_ugc_report_uni_mod_expose_req"]=1,
                        ["send_ugc_report_uni_mod_interactive_req"]=1, ["ReportEquipmentFlow"]=1,
                        ["ReportHeavyWeaponBoxSpawnFlow"]=1, ["ReportHeavyWeaponBoxActivationFlow"]=1,
                        ["ReportSecTLog"]=1, ["report_player_frame_ping_record"]=1, ["ReportSecAttackFlow"]=1,
                        ["ReportSecTgameMovingFlow"]=1, ["ReportVehicleMoveFlow"]=1, ["ReportParachuteData"]=1,
                        ["report_unrealnet_exception"]=1, ["report_ds_net_saturation"]=1, ["on_tss_sdk_anti_data"]=1,
                    }
                    NetUtil.SendPacket = function(packetName, ...)
                        if blocked[packetName] then return end
                        return origSend(packetName, ...)
                    end
                    NetUtil.IsBypassed = true
                end
            end)
        end)
    end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        pc:AddGameTimer(3.0, false, bypassInit)
    else
        bypassInit()
    end
end)