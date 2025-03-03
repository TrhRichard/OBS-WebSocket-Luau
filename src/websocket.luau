local net = zune.net
local serde = zune.serde
local task = zune.task
local crypto = zune.crypto

local Types = require("./types")
local Enums = require("./enums")

local LemonSignal = require("./libs/LemonSignal")
local match = require("./libs/match")
local uuid = require("./libs/uuid")

local function getTableIndex<T, V>(table: { [T]: V }, value: V): T?
	for i: any, v: any in table do
		if value == v then
			return i
		end
	end
	return nil
end

local webSocket = {}
local meta = {}
local methods = {}
meta.__index = methods

export type OBSWebSocket = typeof(setmetatable(
	{} :: {
		-- Private
		_socket: NetWebSocket,
		_handlers: { [string]: { ({}) -> () } },
		_onOpCode: LemonSignal.Signal<Types.BaseOpCode>,

		-- Public
		connected: boolean,
		closeCode: number?,
		closeName: string?,

		-- Core Signals
		onReady: LemonSignal.Signal<>,
		onSocketClosed: LemonSignal.Signal<number?, string?>,
	},
	meta
))

webSocket.new = function(): OBSWebSocket
	local self: OBSWebSocket = setmetatable({}, meta) :: any

	self._onOpCode = LemonSignal.new() :: any
	self._handlers = {}

	self.connected = false
	self.onSocketClosed = LemonSignal.new() :: any
	self.onReady = LemonSignal.new() :: any

	return self
end

type IdentifyParams = {
	rpcVersion: number,
	eventSubscriptions: number?,
}
methods.connect = function(self: OBSWebSocket, password: string?, url: string?, identifyParams: IdentifyParams?)
	assert(not self.connected, "Already connected to OBS")

	local connectUrl = url or "ws://localhost:4455"
	local identifyParams: IdentifyParams = identifyParams or {
		rpcVersion = 1,
	}

	self._socket = net.http.websocket(connectUrl, {
		open = function(ws) end,
		message = function(ws, message)
			local json: Types.BaseOpCode = serde.json.decode(message, { preserveNull = true })
			self._onOpCode:Fire(json)
			match(json.op)({
				[Enums.WebSocketOpCode.Hello] = function()
					local json: Types.HelloOpCode = json :: any
					local data = json.d
					assert(
						data.rpcVersion == identifyParams.rpcVersion,
						`Server would like to use {data.rpcVersion} while client gave {identifyParams.rpcVersion}`
					)

					assert(
						data.authentication and password ~= nil,
						"Server requires password while client did not give one"
					)

					local authString: string = nil
					if data.authentication then -- generating authString
						local hash = crypto.createHash("sha256")
						local saltedPassword = password .. data.authentication.salt
						hash:update(saltedPassword)
						local base64Secret = serde.base64.encode(buffer.tostring(hash:digest("binary")))
						local base64SecretChallenge = base64Secret .. data.authentication.challenge
						hash:update(base64SecretChallenge)
						authString = serde.base64.encode(buffer.tostring(hash:digest("binary")))
					end

					ws:send(serde.json.encode({
						op = Enums.WebSocketOpCode.Identify,
						d = {
							rpcVersion = identifyParams.rpcVersion,
							authentication = authString,
							eventSubscriptions = identifyParams.eventSubscriptions or Enums.EventSubscription.All,
						},
					} :: Types.IdentifyOpCode))
				end,
				[Enums.WebSocketOpCode.Identified] = function()
					local json: Types.IdentifiedOpCode = json :: any
					local data = json.d

					self.connected = true
					self.onReady:Fire()
				end,
				[Enums.WebSocketOpCode.Event] = function()
					local json: Types.EventOpCode = json :: any
					local data = json.d
					if self._handlers[data.eventType] then
						for _, handler in self._handlers[data.eventType] do
							task.spawn(handler, data.eventData :: any)
						end
					end
				end,
			})
		end,
		close = function(ws, closeCode)
			self.connected = false
			if closeCode then
				self.closeCode = closeCode
				self.closeName = getTableIndex(Enums.WebSocketCloseCode, closeCode)
			end

			self.onSocketClosed:Fire(self.closeCode, self.closeName)
		end,
	})
end

methods.on = (
	function(self: OBSWebSocket, eventType: string, handler: (data: {}) -> ())
		if not self._handlers[eventType] then
			self._handlers[eventType] = {}
		end
		table.insert(self._handlers[eventType], handler :: any)
	end :: any
) :: Types.OnEventHandle<OBSWebSocket>

methods.reidentify = function(self: OBSWebSocket, newEventSubscriptions: number?)
	self._socket:send(serde.json.encode({
		op = 3,
		d = {
			eventSubscriptions = newEventSubscriptions,
		},
	} :: Types.ReidentifyOpCode))
end

methods.request = function(self: OBSWebSocket, requestType: Types.RequestType, requestData: {}?): Types.Object
	local generatedUuid = uuid()

	self._socket:send(serde.json.encode({
		op = Enums.WebSocketOpCode.Request,
		d = {
			requestId = generatedUuid,
			requestType = requestType,
			requestData = requestData,
		},
	} :: Types.RequestOpCode))

	local finalJson: Types.RequestResponseOpCode
	while true do
		local json: Types.BaseOpCode = self._onOpCode:Wait()
		if json.op == Enums.WebSocketOpCode.RequestResponse then
			local json: Types.RequestResponseOpCode = json :: any
			if json.d.requestId == generatedUuid then
				finalJson = json
				break
			end
		end
	end

	local requestStatus = finalJson.d.requestStatus
	assert(
		requestStatus.result,
		if not requestStatus.comment
			then tostring(getTableIndex(Enums.RequestStatus, requestStatus.code))
			else requestStatus.comment
	)

	return finalJson.d.responseData :: any
end

type BatchRequestParams = {
	haltOnFailure: boolean?,
	executionType: number?,
	requests: {
		{
			requestType: Types.RequestType,
			requestId: string?,
			requestData: Types.Object?,
		}
	},
}
methods.batchRequest = function(self: OBSWebSocket, params: BatchRequestParams): { Types.Object }
	local generatedUuid = uuid()

	self._socket:send(serde.json.encode({
		op = Enums.WebSocketOpCode.RequestBatch,
		d = {
			requestId = generatedUuid,
			haltOnFailure = params.haltOnFailure,
			executionType = params.executionType,
			requests = params.requests,
		},
	} :: Types.RequestBatchOpCode))

	local finalJson: Types.RequestBatchResponseOpCode
	while true do
		local json: Types.BaseOpCode = self._onOpCode:Wait()
		if json.op == Enums.WebSocketOpCode.RequestBatchResponse then
			local json: Types.RequestBatchResponseOpCode = json :: any
			if json.d.requestId == generatedUuid then
				finalJson = json
				break
			end
		end
	end

	return finalJson.d.results :: any
end

-- ### General Requests ###

type GetVersionResponse = {
	obsVersion: string,
	obsWebSocketVersion: string,
	rpcVersion: number,
	availableRequests: { string },
	supportedImageFormats: { string },
	platform: string,
	platformDescription: string,
}
methods.getVersion = function(self: OBSWebSocket): GetVersionResponse
	local response = self:request("GetVersion")
	return response :: any
end

type GetStatsResponse = {
	cpuUsage: number,
	memoryUsage: number,
	availableDiskSpace: number,
	activeFps: number,
	averageFrameRenderTime: number,
	renderSkippedFrames: number,
	renderTotalFrames: number,
	outputSkippedFrames: number,
	outputTotalFrames: number,
	webSocketSessionIncomingMessages: number,
	webSocketSessionOutgoingMessages: number,
}
methods.getStats = function(self: OBSWebSocket): GetStatsResponse
	local response = self:request("GetStats")
	return response :: any
end

methods.broadcastCustomEvent = function(self: OBSWebSocket, eventData: Types.Object)
	self:request("BroadcastCustomEvent", eventData)
end

type CallVendorRequestResponse = {
	vendorName: string,
	requestType: string,
	responseData: Types.Object,
}
methods.callVendorRequest = function(
	self: OBSWebSocket,
	vendorName: string,
	requestType: string,
	requestData: { [string]: any }?
)
	local response = self:request("CallVendorRequest", {
		vendorName = vendorName,
		requestType = requestType,
		requestData = requestData,
	})
	return response :: any
end

methods.getHotkeyList = function(self: OBSWebSocket): { string }
	local response = self:request("GetHotkeyList")
	return response.hotkeys :: any
end

methods.triggerHotkeyByName = function(self: OBSWebSocket, hotkeyName: string, contextName: string?)
	self:request("TriggerHotkeyByName", {
		hotkeyName = hotkeyName,
		contextName = contextName,
	})
end

type KeyModifiers = {
	shift: boolean?,
	control: boolean?,
	alt: boolean?,
	command: boolean?,
}
methods.triggerHotkeyByKeySequence = function(self: OBSWebSocket, keyId: string, keyModifiers: KeyModifiers)
	self:request("TriggerHotkeyByKeySequence", {
		keyId = keyId,
		keyModifiers = keyModifiers,
	})
end

-- ### Config Requests ###

methods.getPersistentData = function(self: OBSWebSocket, realm: Enums.ObsRealmType, slotName: string): any?
	local response = self:request("GetPersistentData", {
		realm = realm,
		slotName = slotName,
	})

	local slotValue: any = response.slotValue
	if slotValue == serde.json.Values.Null then
		slotValue = nil
	end

	return slotValue :: any
end

methods.setPersistentData = function(self: OBSWebSocket, realm: Enums.ObsRealmType, slotName: string, slotValue: any)
	local response = self:request("SetPersistentData", {
		realm = realm,
		slotName = slotName,
		slotValue = slotValue,
	})
end

type GetSceneCollectionListResponse = {
	currentSceneCollectionName: string,
	sceneCollections: { string },
}
methods.getSceneCollectionList = function(self: OBSWebSocket): GetSceneCollectionListResponse
	local response = self:request("GetSceneCollectionList")
	return response :: any
end

methods.setCurrentSceneCollection = function(self: OBSWebSocket, sceneCollectionName: string)
	self:request("SetCurrentSceneCollection", {
		sceneCollectionName = sceneCollectionName,
	})
end

methods.createSceneCollection = function(self: OBSWebSocket, sceneCollectionName: string)
	self:request("CreateSceneCollection", {
		sceneCollectionName = sceneCollectionName,
	})
end

type GetProfileListResponse = {
	currentProfileName: string,
	profiles: { string },
}
methods.getProfileList = function(self: OBSWebSocket): GetProfileListResponse
	local response = self:request("GetProfileList")
	return response :: any
end

methods.setCurrentProfile = function(self: OBSWebSocket, profileName: string)
	self:request("SetCurrentProfile", {
		profileName = profileName,
	})
end

methods.createProfile = function(self: OBSWebSocket, profileName: string)
	self:request("CreateProfile", {
		profileName = profileName,
	})
end

methods.removeProfile = function(self: OBSWebSocket, profileName: string)
	self:request("RemoveProfile", {
		profileName = profileName,
	})
end

methods.getProfileParameter = function(
	self: OBSWebSocket,
	parameterCategory: string,
	parameterName: string
): (string?, string?)
	local response = self:request("GetProfileParameter", {
		parameterCategory = parameterCategory,
		parameterName = parameterName,
	})

	local parameterValue: string? = response.parameterValue :: any
	local defaultParameterValue: string? = response.defaultParameterValue :: any
	if parameterValue == serde.json.Values.Null then
		parameterValue = nil
	end
	if defaultParameterValue == serde.json.Values.Null then
		defaultParameterValue = nil
	end
	return parameterValue, defaultParameterValue
end

methods.setProfileParameter = function(
	self: OBSWebSocket,
	parameterCategory: string,
	parameterName: string,
	parameterValue: string?
)
	self:request("SetProfileParameter", {
		parameterCategory = parameterCategory,
		parameterName = parameterName,
		parameterValue = parameterValue,
	})
end

type GetVideoSettingsResponse = {
	--- Numerator of the fractional FPS value
	fpsNumerator: number,
	--- Denominator of the fractional FPS value
	fpsDenominator: number,
	--- Width of the base (canvas) resolution in pixels
	baseWidth: number,
	--- Height of the base (canvas) resolution in pixels
	baseHeight: number,
	--- Width of the output resolution in pixels
	outputWidth: number,
	--- Height of the output resolution in pixels
	outputHeight: number,
}
methods.getVideoSettings = function(self: OBSWebSocket): GetVideoSettingsResponse
	local response = self:request("GetVideoSettings")

	return response :: any
end

type NewVideoSettings = {
	fpsNumerator: number?,
	fpsDenominator: number?,
	baseWidth: number?,
	baseHeight: number?,
	outputWidth: number?,
	outputHeight: number?,
}
methods.setVideoSettings = function(self: OBSWebSocket, newSettings: NewVideoSettings)
	self:request("SetVideoSettings", newSettings)
end

type GetStreamServiceSettingsResponse = {
	streamServiceType: string,
	streamServiceSettings: Types.Object,
}
methods.getStreamServiceSettings = function(self: OBSWebSocket): GetStreamServiceSettingsResponse
	local response = self:request("GetStreamServiceSettings")

	return response :: any
end

type NewStreamServiceSettings = {
	streamServiceType: string,
	streamServiceSettings: Types.Object,
}
methods.setStreamServiceSettings = function(self: OBSWebSocket, newSettings: NewStreamServiceSettings)
	self:request("SetStreamServiceSettings", newSettings)
end

methods.getRecordDirectory = function(self: OBSWebSocket): string
	local response = self:request("GetRecordDirectory")

	return response.recordDirectory :: any
end

methods.setRecordDirectory = function(self: OBSWebSocket, recordDirectory: string)
	self:request("SetRecordDirectory", { recordDirectory = recordDirectory })
end

-- ### Sources Requests ###

type GetSourceActiveResponse = {
	videoActive: boolean,
	videoShowing: boolean,
}
type GetSourceActiveOptions = {
	sourceName: string?,
	sourceUuid: string?,
}
methods.getSourceActive = function(self: OBSWebSocket, options: GetSourceActiveOptions?): GetSourceActiveResponse
	local response = self:request("GetSourceActive", options)

	return response :: any
end

type GetSourceScreenshotOptions = {
	sourceName: string?,
	sourceUuid: string?,
	imageFormat: string,
	imageWidth: number?,
	imageHeight: number?,
	imageCompressionQuality: number?,
}
methods.getSourceScreenshot = function(self: OBSWebSocket, options: GetSourceActiveOptions): string
	local response = self:request("GetSourceScreenshot", options)

	return response.imageData :: any
end

type SaveSourceScreenshotOptions = GetSourceScreenshotOptions & {
	imageFilePath: string,
}
methods.saveSourceScreenshot = function(self: OBSWebSocket, options: SaveSourceScreenshotOptions)
	self:request("SaveSourceScreenshot", options)
end

-- ### Scenes Requests ###

-- ### Inputs Requests ###

-- ### Transitions Requests ###

-- ### Filters Requests ###

-- ### Scene Items Requests ###

-- ### Outputs Requests ###

methods.getVirtualCamStatus = function(self: OBSWebSocket): boolean
	local response = self:request("GetVirtualCamStatus")

	return response.outputActive :: any
end

methods.toggleVirtualCam = function(self: OBSWebSocket): boolean
	local response = self:request("ToggleVirtualCam")

	return response.outputActive :: any
end

methods.startVirtualCam = function(self: OBSWebSocket)
	self:request("StartVirtualCam")
end

methods.stopVirtualCam = function(self: OBSWebSocket)
	self:request("StopVirtualCam")
end

methods.getReplayBufferStatus = function(self: OBSWebSocket): boolean
	local response = self:request("GetReplayBufferStatus")

	return response.outputActive :: any
end

methods.toggleReplayBuffer = function(self: OBSWebSocket): boolean
	local response = self:request("ToggleReplayBuffer")

	return response.outputActive :: any
end

methods.startReplayBuffer = function(self: OBSWebSocket)
	self:request("StartReplayBuffer")
end

methods.stopReplayBuffer = function(self: OBSWebSocket)
	self:request("StopReplayBuffer")
end

methods.saveReplayBuffer = function(self: OBSWebSocket)
	self:request("SaveReplayBuffer")
end

methods.getLastReplayBufferReplay = function(self: OBSWebSocket): string
	local response = self:request("GetLastReplayBufferReplay")

	return response.savedReplayPath :: any
end

methods.getOutputList = function(self: OBSWebSocket): { Types.Object }
	local response = self:request("GetOutputList")

	return response.outputs :: any
end

type GetOutputStatusResponse = {
	outputActive: boolean,
	outputReconnecting: boolean,
	outputTimecode: string,
	outputDuration: number,
	outputCongestion: number,
	outputBytes: number,
	outputSkippedFrames: number,
	outputTotalFrames: number,
}
methods.getOutputStatus = function(self: OBSWebSocket, outputName: string): GetOutputStatusResponse
	local response = self:request("GetOutputStatus", { outputName = outputName })

	return response :: any
end

methods.toggleOutput = function(self: OBSWebSocket, outputName: string): boolean
	local response = self:request("ToggleOutput", { outputName = outputName })

	return response.outputActive :: any
end

methods.startOutput = function(self: OBSWebSocket, outputName: string)
	self:request("StartOutput", { outputName = outputName })
end

methods.stopOutput = function(self: OBSWebSocket, outputName: string)
	self:request("StopOutput", { outputName = outputName })
end

methods.getOutputSettings = function(self: OBSWebSocket, outputName: string): Types.Object
	local response = self:request("GetOutputSettings", { outputName = outputName })

	return response.outputSettings :: any
end

methods.setOutputSettings = function(self: OBSWebSocket, outputName: string, outputSettings: Types.Object)
	self:request("StopOutput", { outputName = outputName, outputSettings = outputSettings })
end

-- ### Stream Requests ###

type GetStreamStatusResponse = {
	outputActive: boolean,
	outputReconnecting: boolean,
	outputTimecode: string,
	outputDuration: number,
	outputCongestion: number,
	outputBytes: number,
	outputSkippedFrames: number,
	outputTotalFrames: number,
}
methods.getStreamStatus = function(self: OBSWebSocket): GetStreamStatusResponse
	local response = self:request("GetStreamStatus")

	return response :: any
end

methods.toggleStream = function(self: OBSWebSocket): boolean
	local response = self:request("ToggleStream")

	return response.outputActive :: any
end

methods.startStream = function(self: OBSWebSocket)
	self:request("StartStream")
end

methods.stopStream = function(self: OBSWebSocket)
	self:request("StopStream")
end

methods.sendStreamCaption = function(self: OBSWebSocket, captionText: string)
	self:request("SendStreamCaption", { captionText = captionText })
end

-- ### Record Requests ###

type GetRecordStatusResponse = {
	outputActive: boolean,
	outputPaused: boolean,
	outputTimecode: string,
	outputDuration: number,
	outputBytes: number,
}
methods.getRecordStatus = function(self: OBSWebSocket): GetRecordStatusResponse
	local response = self:request("GetRecordStatus")

	return response :: any
end

methods.toggleRecord = function(self: OBSWebSocket): boolean
	local response = self:request("ToggleRecord")

	return response.outputActive :: any
end

methods.startRecord = function(self: OBSWebSocket)
	self:request("StartRecord")
end

methods.stopRecord = function(self: OBSWebSocket)
	self:request("StopRecord")
end

methods.toggleRecordPause = function(self: OBSWebSocket)
	self:request("ToggleRecordPause")
end

methods.pauseRecord = function(self: OBSWebSocket)
	self:request("PauseRecord")
end

methods.resumeRecord = function(self: OBSWebSocket)
	self:request("ResumeRecord")
end

methods.splitRecordFile = function(self: OBSWebSocket)
	self:request("SplitRecordFile")
end

methods.createRecordChapter = function(self: OBSWebSocket, chapterName: string?)
	self:request("CreateRecordChapter", { chapterName = chapterName })
end

-- ### Media Inputs Requests ###

type GetMediaInputStatusOptions = {
	inputName: string?,
	inputUuid: string?,
}
type GetMediaInputStatusResponse = {
	mediaState: Enums.ObsMediaState,
	mediaDuration: number?,
	mediaCursor: number?,
}
methods.getMediaInputStatus = function(
	self: OBSWebSocket,
	options: GetMediaInputStatusOptions
): GetMediaInputStatusResponse
	local response = self:request("GetMediaInputStatus")

	return response :: any
end

type SetMediaInputCursorOptions = GetMediaInputStatusOptions & {
	mediaCursor: number,
}
methods.setMediaInputCursor = function(self: OBSWebSocket, options: SetMediaInputCursorOptions)
	self:request("SetMediaInputCursor", options)
end

type OffsetMediaInputCursorOptions = GetMediaInputStatusOptions & {
	mediaCursorOffset: number,
}
methods.offsetMediaInputCursor = function(self: OBSWebSocket, options: OffsetMediaInputCursorOptions)
	self:request("OffsetMediaInputCursor", options)
end

type TriggerMediaInputActionOptions = GetMediaInputStatusOptions & {
	mediaAction: string,
}
methods.triggerMediaInputAction = function(self: OBSWebSocket, options: TriggerMediaInputActionOptions)
	self:request("TriggerMediaInputAction", options)
end

-- ### Ui Requests Requests ###

methods.getStudioModeEnabled = function(self: OBSWebSocket): boolean
	local response = self:request("GetStudioModeEnabled")

	return response.studioModeEnabled :: any
end

methods.setStudioModeEnabled = function(self: OBSWebSocket, newState: boolean)
	self:request("TriggerMediaInputAction", { studioModeEnabled = newState })
end

type OpenInputPropertiesDialogOptions = {
	inputName: string?,
	inputUuid: string?,
}
methods.openInputPropertiesDialog = function(self: OBSWebSocket, options: OpenInputPropertiesDialogOptions)
	self:request("OpenInputPropertiesDialog", options)
end

methods.openInputFiltersDialog = function(self: OBSWebSocket, options: OpenInputPropertiesDialogOptions)
	self:request("OpenInputFiltersDialog", options)
end

methods.openInputInteractDialog = function(self: OBSWebSocket, options: OpenInputPropertiesDialogOptions)
	self:request("OpenInputInteractDialog", options)
end

methods.getMonitorList = function(self: OBSWebSocket): { Types.Object }
	local response = self:request("GetMonitorList")

	return response.monitors :: any
end

methods.openVideoMixProjector = function(
	self: OBSWebSocket,
	videoMixType: Enums.ObsVideoMixType,
	monitorIndex: number?,
	projectorGeometry: string?
)
	self:request("OpenVideoMixProjector", {
		videoMixType = videoMixType,
		monitorIndex = monitorIndex,
		projectorGeometry = projectorGeometry,
	})
end

type OpenSourceProjectorOptions = {
	sourceName: string,
	sourceUuid: string,
	monitorIndex: number,
	projectorGeometry: string,
}
methods.openSourceProjector = function(self: OBSWebSocket, options: OpenSourceProjectorOptions)
	self:request("OpenSourceProjector", options)
end

return webSocket
