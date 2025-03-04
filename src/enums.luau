export type ObsMonitorType =
	"OBS_MONITORING_TYPE_NONE"
	| "OBS_MONITORING_TYPE_MONITOR_ONLY"
	| "OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT"

export type ObsMediaInputAction =
	"OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NONE"
	| "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY"
	| "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_STOP"
	| "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"
	| "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NEXT"
	| "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PREVIOUS"

export type ObsOutputState =
	"OBS_WEBSOCKET_OUTPUT_UNKNOWN"
	| "OBS_WEBSOCKET_OUTPUT_STARTING"
	| "OBS_WEBSOCKET_OUTPUT_STARTED"
	| "OBS_WEBSOCKET_OUTPUT_STOPPING"
	| "OBS_WEBSOCKET_OUTPUT_STOPPED"
	| "OBS_WEBSOCKET_OUTPUT_RECONNECTING"
	| "OBS_WEBSOCKET_OUTPUT_RECONNECTED"
	| "OBS_WEBSOCKET_OUTPUT_PAUSED"
	| "OBS_WEBSOCKET_OUTPUT_RESUMED"

export type ObsMediaState =
	"OBS_MEDIA_STATE_NONE"
	| "OBS_MEDIA_STATE_PLAYING"
	| "OBS_MEDIA_STATE_OPENING"
	| "OBS_MEDIA_STATE_BUFFERING"
	| "OBS_MEDIA_STATE_PAUSED"
	| "OBS_MEDIA_STATE_STOPPED"
	| "OBS_MEDIA_STATE_ENDED"
	| "OBS_MEDIA_STATE_ERROR"

export type ObsVideoMixType =
	"OBS_WEBSOCKET_VIDEO_MIX_TYPE_PREVIEW"
	| "OBS_WEBSOCKET_VIDEO_MIX_TYPE_PROGRAM"
	| "OBS_WEBSOCKET_VIDEO_MIX_TYPE_MULTIVIEW"

export type ObsRealmType = "OBS_WEBSOCKET_DATA_REALM_GLOBAL" | "OBS_WEBSOCKET_DATA_REALM_PROFILE"

export type ObsBlendMode =
	"OBS_BLEND_NORMAL"
	| "OBS_BLEND_ADDITIVE"
	| "OBS_BLEND_SUBTRACT"
	| "OBS_BLEND_SCREEN"
	| "OBS_BLEND_MULTIPLY"
	| "OBS_BLEND_LIGHTEN"
	| "OBS_BLEND_DARKEN"

export type ObsDeinterlaceMode =
	"OBS_DEINTERLACE_MODE_DISABLE"
	| "OBS_DEINTERLACE_MODE_DISCARD"
	| "OBS_DEINTERLACE_MODE_RETRO"
	| "OBS_DEINTERLACE_MODE_BLEND"
	| "OBS_DEINTERLACE_MODE_BLEND_2X"
	| "OBS_DEINTERLACE_MODE_LINEAR"
	| "OBS_DEINTERLACE_MODE_LINEAR_2X"
	| "OBS_DEINTERLACE_MODE_YADIF"
	| "OBS_DEINTERLACE_MODE_YADIF_2X"

export type ObsDeinterlaceFieldOrder = "OBS_DEINTERLACE_FIELD_ORDER_TOP" | "OBS_DEINTERLACE_FIELD_ORDER_BOTTOM"

return {
	WebSocketOpCode = {
		Hello = 0,
		Identify = 1,
		Identified = 2,
		Reidentify = 3,
		Event = 5,
		Request = 6,
		RequestResponse = 7,
		RequestBatch = 8,
		RequestBatchResponse = 9,
	},
	WebSocketCloseCode = {
		DontClose = 0,
		UnknownReason = 4000,
		MessageDecodeError = 4002,
		MissingDataField = 4003,
		InvalidDataFieldType = 4004,
		InvalidDataFieldValue = 4005,
		UnknownOpCode = 4006,
		NotIdentified = 4007,
		AlreadyIdentified = 4008,
		AuthenticationFailed = 4009,
		UnsupportedRpcVersion = 4010,
		SessionInvalidated = 4011,
		UnsupportedFeature = 4012,
	},
	RequestBatchExecutionType = {
		None = -1,
		SerialRealtime = 0,
		SerialFrame = 1,
		Parallel = 2,
	},
	RequestStatus = {
		Unknown = 0,
		NoError = 10,
		Success = 100,
		MissingRequestType = 203,
		UnknownRequestType = 204,
		GenericError = 205,
		UnsupportedRequestBatchExecutionType = 206,
		NotReady = 207,
		MissingRequestField = 300,
		MissingRequestData = 301,
		InvalidRequestField = 400,
		InvalidRequestFieldType = 401,
		RequestFieldOutOfRange = 402,
		RequestFieldEmpty = 403,
		TooManyRequestFields = 404,
		OutputRunning = 500,
		OutputNotRunning = 501,
		OutputPaused = 502,
		OutputNotPaused = 503,
		OutputDisabled = 504,
		StudioModeActive = 505,
		StudioModeNotActive = 506,
		ResourceNotFound = 600,
		ResourceAlreadyExists = 601,
		InvalidResourceType = 602,
		NotEnoughResources = 603,
		InvalidResourceState = 604,
		InvalidInputKind = 605,
		ResourceNotConfigurable = 606,
		InvalidFilterKind = 607,
		ResourceCreationFailed = 700,
		ResourceActionFailed = 701,
		RequestProcessingFailed = 702,
		CannotAct = 703,
	},
	EventSubscription = {
		None = 0,
		General = bit32.lshift(1, 0),
		Config = bit32.lshift(1, 1),
		Scenes = bit32.lshift(1, 2),
		Inputs = bit32.lshift(1, 3),
		Transitions = bit32.lshift(1, 4),
		Filters = bit32.lshift(1, 5),
		Outputs = bit32.lshift(1, 6),
		SceneItems = bit32.lshift(1, 7),
		MediaInputs = bit32.lshift(1, 8),
		Vendors = bit32.lshift(1, 9),
		Ui = bit32.lshift(1, 10),
		All = 2047, -- pain if i do all the bit32 again
		InputVolumeMeters = bit32.lshift(1, 16),
		InputActiveStateChanged = bit32.lshift(1, 17),
		InputShowStateChanged = bit32.lshift(1, 18),
		SceneItemTransformChanged = bit32.lshift(1, 19),
	},
	ObsMediaInputAction = {
		OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NONE = "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NONE",
		OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY = "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY",
		OBS_WEBSOCKET_MEDIA_INPUT_ACTION_STOP = "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_STOP",
		OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART = "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART",
		OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NEXT = "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NEXT",
		OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PREVIOUS = "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PREVIOUS",
	},
	ObsOutputState = {
		OBS_WEBSOCKET_OUTPUT_UNKNOWN = "OBS_WEBSOCKET_OUTPUT_UNKNOWN",
		OBS_WEBSOCKET_OUTPUT_STARTING = "OBS_WEBSOCKET_OUTPUT_STARTING",
		OBS_WEBSOCKET_OUTPUT_STARTED = "OBS_WEBSOCKET_OUTPUT_STARTED",
		OBS_WEBSOCKET_OUTPUT_STOPPING = "OBS_WEBSOCKET_OUTPUT_STOPPING",
		OBS_WEBSOCKET_OUTPUT_STOPPED = "OBS_WEBSOCKET_OUTPUT_STOPPED",
		OBS_WEBSOCKET_OUTPUT_RECONNECTING = "OBS_WEBSOCKET_OUTPUT_RECONNECTING",
		OBS_WEBSOCKET_OUTPUT_RECONNECTED = "OBS_WEBSOCKET_OUTPUT_RECONNECTED",
		OBS_WEBSOCKET_OUTPUT_PAUSED = "OBS_WEBSOCKET_OUTPUT_PAUSED",
		OBS_WEBSOCKET_OUTPUT_RESUMED = "OBS_WEBSOCKET_OUTPUT_RESUMED",
	},
}
