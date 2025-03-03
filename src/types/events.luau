type Object<K = string, V = any> = { [K]: V }

local Enums = require("../enums")

export type VendorEvent = {
	vendorName: string,
	eventType: string,
	eventData: {} | Object,
}

export type CustomEvent = {
	eventData: Object,
}

export type CurrentSceneCollectionChanging = {
	sceneCollectionName: string,
}

export type CurrentSceneCollectionChanged = {
	sceneCollectionName: string,
}

export type SceneCollectionListChanged = {
	sceneCollections: { string },
}

export type CurrentProfileChanging = {
	profileName: string,
}

export type CurrentProfileChanged = {
	profileName: string,
}

export type ProfileListChanged = {
	profiles: { string },
}

export type SceneCreated = {
	sceneName: string,
	sceneUuid: string,
	isGroup: boolean,
}

export type SceneRemoved = {
	sceneName: string,
	sceneUuid: string,
	isGroup: boolean,
}

export type SceneNameChanged = {
	sceneUuid: string,
	oldSceneName: string,
	sceneName: string,
}

export type CurrentProgramSceneChanged = {
	sceneName: string,
	sceneUuid: string,
}

export type CurrentPreviewSceneChanged = {
	sceneName: string,
	sceneUuid: string,
}

export type SceneListChanged = {
	scenes: { Object },
}

export type InputCreated = {
	inputName: string,
	inputUuid: string,
	inputKind: string,
	unversionedInputKind: string,
	inputKindCaps: number,
	inputSettings: Object,
	defaultInputSettings: Object,
}

export type InputRemoved = {
	inputName: string,
	inputUuid: string,
}

export type InputNameChanged = {
	inputUuid: string,
	oldInputName: string,
	inputName: string,
}

export type InputSettingsChanged = {
	inputName: string,
	inputUuid: string,
	inputSettings: Object,
}

export type InputActiveStateChanged = {
	inputName: string,
	inputUuid: string,
	videoActive: boolean,
}

export type InputShowStateChanged = {
	inputName: string,
	inputUuid: string,
	videoShowing: boolean,
}

export type InputMuteStateChanged = {
	inputName: string,
	inputUuid: string,
	inputMuted: boolean,
}

export type InputVolumeChanged = {
	inputName: string,
	inputUuid: string,
	inputVolumeMul: number,
	inputVolumeDb: number,
}

export type InputAudioBalanceChanged = {
	inputName: string,
	inputUuid: string,
	inputAudioBalance: number,
}

export type InputAudioSyncOffsetChanged = {
	inputName: string,
	inputUuid: string,
	inputAudioSyncOffset: number,
}

export type InputAudioTracksChanged = {
	inputName: string,
	inputUuid: string,
	inputAudioTracks: Object,
}

export type InputAudioMonitorTypeChanged = {
	inputName: string,
	inputUuid: string,
	monitorType: Enums.ObsMonitorType,
}

export type InputVolumeMeters = {
	inputs: { Object },
}

export type CurrentSceneTransitionChanged = {
	transitionName: string,
	transitionUuid: string,
}

export type CurrentSceneTransitionDurationChanged = {
	transitionDuration: number,
}

export type SceneTransitionStarted = {
	transitionName: string,
	transitionUuid: string,
}

export type SceneTransitionEnded = {
	transitionName: string,
	transitionUuid: string,
}

export type SceneTransitionVideoEnded = {
	transitionName: string,
	transitionUuid: string,
}

export type SourceFilterListReindexed = {
	sourceName: string,
	filters: { Object },
}

export type SourceFilterCreated = {
	sourceName: string,
	filterName: string,
	filterKind: string,
	filterIndex: number,
	filterSettings: Object,
	defaultFilterSettings: Object,
}

export type SourceFilterRemoved = {
	sourceName: string,
	filterName: string,
}

export type SourceFilterNameChanged = {
	sourceName: string,
	oldFilterName: string,
	filterName: string,
}

export type SourceFilterSettingsChanged = {
	sourceName: string,
	filterName: string,
	filterSettings: Object,
}

export type SourceFilterEnableStateChanged = {
	sourceName: string,
	filterName: string,
	filterEnabled: boolean,
}

export type SceneItemCreated = {
	sceneName: string,
	sceneUuid: string,
	sourceName: string,
	sourceUuid: string,
	sceneItemId: number,
	sceneItemIndex: number,
}

export type SceneItemRemoved = {
	sceneName: string,
	sceneUuid: string,
	sourceName: string,
	sourceUuid: string,
	sceneItemId: number,
}

export type SceneItemListReindexed = {
	sceneName: string,
	sceneUuid: string,
	sceneItems: { Object },
}

export type SceneItemEnableStateChanged = {
	sceneName: string,
	sceneUuid: string,
	sceneItemId: number,
	sceneItemEnabled: boolean,
}

export type SceneItemLockStateChanged = {
	sceneName: string,
	sceneUuid: string,
	sceneItemId: number,
	sceneItemLocked: boolean,
}

export type SceneItemSelected = {
	sceneName: string,
	sceneUuid: string,
	sceneItemId: number,
}

export type SceneItemTransformChanged = {
	sceneName: string,
	sceneUuid: string,
	sceneItemId: number,
	sceneItemTransform: Object,
}

export type StreamStateChanged = {
	outputActive: boolean,
	outputState: Enums.ObsOutputState,
}

export type RecordStateChanged = {
	outputActive: boolean,
	outputState: Enums.ObsOutputState,
	outputPath: string | any,
}

export type RecordFileChanged = {
	newOutputPath: string,
}

export type ReplayBufferStateChanged = {
	outputActive: boolean,
	outputState: Enums.ObsOutputState,
}

export type VirtualcamStateChanged = {
	outputActive: boolean,
	outputState: Enums.ObsOutputState,
}

export type ReplayBufferSaved = {
	savedReplayPath: string,
}

export type MediaInputPlaybackStarted = {
	inputName: string,
	inputUuid: string,
}

export type MediaInputPlaybackEnded = {
	inputName: string,
	inputUuid: string,
}

export type MediaInputActionTriggered = {
	inputName: string,
	inputUuid: string,
	mediaActon: Enums.ObsMediaInputAction,
}

export type StudioModeStateChanged = {
	studioModeEnabled: boolean,
}

export type ScreenshotSaved = {
	savedScreenshotPath: string,
}

-- stylua: ignore
export type EventType = "VendorEvent" | "CustomEvent" | 
"CurrentSceneCollectionChanging" | "CurrentSceneCollectionChanged" | 
"SceneCollectionListChanged" | "CurrentProfileChanging" | 
"CurrentProfileChanged" | "ProfileListChanged" | "SceneCreated" | 
"SceneRemoved" | "SceneNameChanged" | "CurrentProgramSceneChanged" | 
"CurrentPreviewSceneChanged" | "SceneListChanged" | "InputCreated" | 
"InputRemoved" | "InputNameChanged" | "InputSettingsChanged" | 
"InputActiveStateChanged" | "InputShowStateChanged" | 
"InputMuteStateChanged" | "InputVolumeChanged" | 
"InputAudioBalanceChanged" | "InputAudioSyncOffsetChanged" | 
"InputAudioTracksChanged" | "InputAudioMonitorTypeChanged" | 
"InputVolumeMeters" | "CurrentSceneTransitionChanged" | 
"CurrentSceneTransitionDurationChanged" | "SceneTransitionStarted" | 
"SceneTransitionEnded" | "SceneTransitionVideoEnded" | 
"SourceFilterListReindexed" | "SourceFilterCreated" | 
"SourceFilterRemoved" | "SourceFilterNameChanged" | 
"SourceFilterSettingsChanged" | "SourceFilterEnableStateChanged" | 
"SceneItemCreated" | "SceneItemRemoved" | "SceneItemListReindexed" | 
"SceneItemEnableStateChanged" | "SceneItemLockStateChanged" | 
"SceneItemSelected" | "SceneItemTransformChanged" | "StreamStateChanged" | 
"RecordStateChanged" | "RecordFileChanged" | "ReplayBufferStateChanged" | 
"VirtualcamStateChanged" | "ReplayBufferSaved" | "MediaInputPlaybackStarted" | 
"MediaInputPlaybackEnded" | "MediaInputActionTriggered" | 
"StudioModeStateChanged" | "ScreenshotSaved"

export type OnEventHandle<S> = (S, type: EventType, handler: (...any) -> ()) -> ()

return {}
