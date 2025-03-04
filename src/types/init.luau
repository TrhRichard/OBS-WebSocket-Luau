local Events = require("./events")

export type Object = { [string]: any }

export type BaseOpCode<D = { [string]: any }> = {
	op: number,
	d: D,
}

export type HelloOpCode = BaseOpCode<{
	obsStudioVersion: string,
	obsWebSocketVersion: string,
	rpcVersion: number,
	authentication: {
		challenge: string,
		salt: string,
	}?,
}>

export type IdentifyOpCode = BaseOpCode<{
	rpcVersion: number,
	authentication: string?,
	eventSubscriptions: number?,
}>

export type IdentifiedOpCode = BaseOpCode<{
	negotiatedRpcVersion: number,
}>

export type ReidentifyOpCode = BaseOpCode<{
	eventSubscriptions: number?,
}>

export type EventOpCode<D = Object?> = BaseOpCode<{
	eventType: string,
	eventIntent: number,
	eventData: D,
}>

export type RequestOpCode<D = Object?> = BaseOpCode<{
	requestType: string,
	requestId: string,
	requestData: D,
}>

export type RequestStatus = {
	result: boolean,
	code: number,
	comment: string?,
}

export type RequestResponseOpCode<D = Object?> = BaseOpCode<{
	requestType: RequestType,
	requestId: string,
	requestStatus: RequestStatus,
	responseData: D,
}>

export type RequestBatchOpCode = BaseOpCode<{
	requestId: string,
	haltOnFailure: boolean?,
	executionType: number?,
	requests: {
		{
			requestType: RequestType,
			requestId: string?,
			requestData: Object?,
		}
	},
}>

export type RequestBatchResponseOpCode = BaseOpCode<{
	requestId: string,
	results: { Object },
}>

-- stylua: ignore
export type RequestType =
    "GetPersistentData" | "SetPersistentData" | "GetSceneCollectionList" | "SetCurrentSceneCollection" | "CreateSceneCollection" |
    "GetProfileList" | "SetCurrentProfile" | "CreateProfile" | "RemoveProfile" | "GetProfileParameter" | "SetProfileParameter" |
    "GetVideoSettings" | "SetVideoSettings" | "GetStreamServiceSettings" | "SetStreamServiceSettings" | "GetRecordDirectory" |
    "SetRecordDirectory" | "GetSourceFilterKindList" | "GetSourceFilterList" | "GetSourceFilterDefaultSettings" | "CreateSourceFilter" |
    "RemoveSourceFilter" | "SetSourceFilterName" | "GetSourceFilter" | "SetSourceFilterIndex" | "SetSourceFilterSettings" |
    "SetSourceFilterEnabled" | "GetVersion" | "GetStats" | "BroadcastCustomEvent" | "CallVendorRequest" | "GetHotkeyList" |
    "TriggerHotkeyByName" | "TriggerHotkeyByKeySequence" | "Sleep" | "GetInputList" | "GetInputKindList" | "GetSpecialInputs" |
    "CreateInput" | "RemoveInput" | "SetInputName" | "GetInputDefaultSettings" | "GetInputSettings" | "SetInputSettings" |
    "GetInputMute" | "SetInputMute" | "ToggleInputMute" | "GetInputVolume" | "SetInputVolume" | "GetInputAudioBalance" |
    "SetInputAudioBalance" | "GetInputAudioSyncOffset" | "SetInputAudioSyncOffset" | "GetInputAudioMonitorType" |
    "SetInputAudioMonitorType" | "GetInputAudioTracks" | "SetInputAudioTracks" | "GetInputDeinterlaceMode" |
    "SetInputDeinterlaceMode" | "GetInputDeinterlaceFieldOrder" | "SetInputDeinterlaceFieldOrder" |
    "GetInputPropertiesListPropertyItems" | "PressInputPropertiesButton" | "GetMediaInputStatus" | "SetMediaInputCursor" |
    "OffsetMediaInputCursor" | "TriggerMediaInputAction" | "GetVirtualCamStatus" | "ToggleVirtualCam" | "StartVirtualCam" |
    "StopVirtualCam" | "GetReplayBufferStatus" | "ToggleReplayBuffer" | "StartReplayBuffer" | "StopReplayBuffer" |
    "SaveReplayBuffer" | "GetLastReplayBufferReplay" | "GetOutputList" | "GetOutputStatus" | "ToggleOutput" | "StartOutput" |
    "StopOutput" | "GetOutputSettings" | "SetOutputSettings" | "GetRecordStatus" | "ToggleRecord" | "StartRecord" |
    "StopRecord" | "ToggleRecordPause" | "PauseRecord" | "ResumeRecord" | "SplitRecordFile" | "CreateRecordChapter" |
    "GetSceneItemList" | "GetGroupSceneItemList" | "GetSceneItemId" | "GetSceneItemSource" | "CreateSceneItem" |
    "RemoveSceneItem" | "DuplicateSceneItem" | "GetSceneItemTransform" | "SetSceneItemTransform" | "GetSceneItemEnabled" |
    "SetSceneItemEnabled" | "GetSceneItemLocked" | "SetSceneItemLocked" | "GetSceneItemIndex" | "SetSceneItemIndex" |
    "GetSceneItemBlendMode" | "SetSceneItemBlendMode" | "GetSceneList" | "GetGroupList" | "GetCurrentProgramScene" |
    "SetCurrentProgramScene" | "GetCurrentPreviewScene" | "SetCurrentPreviewScene" | "CreateScene" | "RemoveScene" |
    "SetSceneName" | "GetSceneSceneTransitionOverride" | "SetSceneSceneTransitionOverride" | "GetSourceActive" |
    "GetSourceScreenshot" | "SaveSourceScreenshot" | "GetStreamStatus" | "ToggleStream" | "StartStream" | "StopStream" |
    "SendStreamCaption" | "GetTransitionKindList" | "GetSceneTransitionList" | "GetCurrentSceneTransition" |
    "SetCurrentSceneTransition" | "SetCurrentSceneTransitionDuration" | "SetCurrentSceneTransitionSettings" |
    "GetCurrentSceneTransitionCursor" | "TriggerStudioModeTransition" | "SetTBarPosition" | "GetStudioModeEnabled" |
    "SetStudioModeEnabled" | "OpenInputPropertiesDialog" | "OpenInputFiltersDialog" | "OpenInputInteractDialog" |
    "GetMonitorList" | "OpenVideoMixProjector" | "OpenSourceProjector"

return {}
