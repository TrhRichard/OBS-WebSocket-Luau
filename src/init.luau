--[[
Zune library that allows you to interact to OBS
]]
local OBSWebSocket = {}

local EventTypes = require("./types/events")
local Types = require("./types")
local Enums = require("./enums")
local websocket = require("./websocket")

export type OBSWebSocket = websocket.OBSWebSocket

OBSWebSocket.new = websocket.new
OBSWebSocket.Enums = Enums

export type MonitorType = Enums.ObsMonitorType
export type ObsMediaInputAction = Enums.ObsMediaInputAction
export type ObsOutputState = Enums.ObsOutputState
export type VendorEvent = EventTypes.VendorEvent
export type CustomEvent = EventTypes.CustomEvent
export type CurrentSceneCollectionChanging = EventTypes.CurrentSceneCollectionChanging
export type CurrentSceneCollectionChanged = EventTypes.CurrentSceneCollectionChanged
export type SceneCollectionListChanged = EventTypes.SceneCollectionListChanged
export type CurrentProfileChanging = EventTypes.CurrentProfileChanging
export type CurrentProfileChanged = EventTypes.CurrentProfileChanged
export type ProfileListChanged = EventTypes.ProfileListChanged
export type SceneCreated = EventTypes.SceneCreated
export type SceneRemoved = EventTypes.SceneRemoved
export type SceneNameChanged = EventTypes.SceneNameChanged
export type CurrentProgramSceneChanged = EventTypes.CurrentProgramSceneChanged
export type CurrentPreviewSceneChanged = EventTypes.CurrentPreviewSceneChanged
export type SceneListChanged = EventTypes.SceneListChanged
export type InputCreated = EventTypes.InputCreated
export type InputRemoved = EventTypes.InputRemoved
export type InputNameChanged = EventTypes.InputNameChanged
export type InputSettingsChanged = EventTypes.InputSettingsChanged
export type InputActiveStateChanged = EventTypes.InputActiveStateChanged
export type InputShowStateChanged = EventTypes.InputShowStateChanged
export type InputMuteStateChanged = EventTypes.InputMuteStateChanged
export type InputVolumeChanged = EventTypes.InputVolumeChanged
export type InputAudioBalanceChanged = EventTypes.InputAudioBalanceChanged
export type InputAudioSyncOffsetChanged = EventTypes.InputAudioSyncOffsetChanged
export type InputAudioTracksChanged = EventTypes.InputAudioTracksChanged
export type InputAudioMonitorTypeChanged = EventTypes.InputAudioMonitorTypeChanged
export type InputVolumeMeters = EventTypes.InputVolumeMeters
export type CurrentSceneTransitionChanged = EventTypes.CurrentSceneTransitionChanged
export type CurrentSceneTransitionDurationChanged = EventTypes.CurrentSceneTransitionDurationChanged
export type SceneTransitionStarted = EventTypes.SceneTransitionStarted
export type SceneTransitionEnded = EventTypes.SceneTransitionEnded
export type SceneTransitionVideoEnded = EventTypes.SceneTransitionVideoEnded
export type SourceFilterListReindexed = EventTypes.SourceFilterListReindexed
export type SourceFilterCreated = EventTypes.SourceFilterCreated
export type SourceFilterRemoved = EventTypes.SourceFilterRemoved
export type SourceFilterNameChanged = EventTypes.SourceFilterNameChanged
export type SourceFilterSettingsChanged = EventTypes.SourceFilterSettingsChanged
export type SourceFilterEnableStateChanged = EventTypes.SourceFilterEnableStateChanged
export type SceneItemCreated = EventTypes.SceneItemCreated
export type SceneItemRemoved = EventTypes.SceneItemRemoved
export type SceneItemListReindexed = EventTypes.SceneItemListReindexed
export type SceneItemEnableStateChanged = EventTypes.SceneItemEnableStateChanged
export type SceneItemLockStateChanged = EventTypes.SceneItemLockStateChanged
export type SceneItemSelected = EventTypes.SceneItemSelected
export type SceneItemTransformChanged = EventTypes.SceneItemTransformChanged
export type StreamStateChanged = EventTypes.StreamStateChanged
export type RecordStateChanged = EventTypes.RecordStateChanged
export type RecordFileChanged = EventTypes.RecordFileChanged
export type ReplayBufferStateChanged = EventTypes.ReplayBufferStateChanged
export type VirtualcamStateChanged = EventTypes.VirtualcamStateChanged
export type ReplayBufferSaved = EventTypes.ReplayBufferSaved
export type MediaInputPlaybackStarted = EventTypes.MediaInputPlaybackStarted
export type MediaInputPlaybackEnded = EventTypes.MediaInputPlaybackEnded
export type MediaInputActionTriggered = EventTypes.MediaInputActionTriggered
export type StudioModeStateChanged = EventTypes.StudioModeStateChanged
export type ScreenshotSaved = EventTypes.ScreenshotSaved

return OBSWebSocket
