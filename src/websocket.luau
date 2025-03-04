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

local OBSWebSocket = {}
OBSWebSocket.__index = OBSWebSocket

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
	OBSWebSocket
))

function OBSWebSocket.new(): OBSWebSocket
	local self: OBSWebSocket = setmetatable({}, OBSWebSocket) :: any

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
function OBSWebSocket.connect(self: OBSWebSocket, password: string?, url: string?, identifyParams: IdentifyParams?)
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

function OBSWebSocket.on(self: OBSWebSocket, eventType: Types.RequestType, handler: (eventData: Types.Object) -> ())
	if not self._handlers[eventType] then
		self._handlers[eventType] = {}
	end
	table.insert(self._handlers[eventType], handler :: any)
end

function OBSWebSocket.reidentify(self: OBSWebSocket, newEventSubscriptions: number?)
	self._socket:send(serde.json.encode({
		op = 3,
		d = {
			eventSubscriptions = newEventSubscriptions,
		},
	} :: Types.ReidentifyOpCode))
end

function OBSWebSocket.request(
	self: OBSWebSocket,
	requestType: Types.RequestType,
	requestData: Types.Object?
): Types.Object
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

type Request = {
	requestType: Types.RequestType,
	requestId: string?,
	requestData: Types.Object?,
}
function OBSWebSocket.batchRequest(
	self: OBSWebSocket,
	requests: { Request },
	haltOnFailure: boolean?,
	executionType: number?
): { Types.Object }
	local generatedUuid = uuid()

	self._socket:send(serde.json.encode({
		op = Enums.WebSocketOpCode.RequestBatch,
		d = {
			requestId = generatedUuid,
			haltOnFailure = haltOnFailure,
			executionType = executionType,
			requests = requests,
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
function OBSWebSocket.getVersion(self: OBSWebSocket): GetVersionResponse
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
function OBSWebSocket.getStats(self: OBSWebSocket): GetStatsResponse
	local response = self:request("GetStats")
	return response :: any
end

function OBSWebSocket.broadcastCustomEvent(self: OBSWebSocket, eventData: Types.Object)
	self:request("BroadcastCustomEvent", eventData)
end

type CallVendorRequestResponse = {
	vendorName: string,
	requestType: string,
	responseData: Types.Object,
}
function OBSWebSocket.callVendorRequest(
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

function OBSWebSocket.getHotkeyList(self: OBSWebSocket): { string }
	local response = self:request("GetHotkeyList")
	return response.hotkeys :: any
end

function OBSWebSocket.triggerHotkeyByName(self: OBSWebSocket, hotkeyName: string, contextName: string?)
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
function OBSWebSocket.triggerHotkeyByKeySequence(self: OBSWebSocket, keyId: string, keyModifiers: KeyModifiers)
	self:request("TriggerHotkeyByKeySequence", {
		keyId = keyId,
		keyModifiers = keyModifiers,
	})
end

-- ### Config Requests ###

function OBSWebSocket.getPersistentData(self: OBSWebSocket, realm: Enums.ObsRealmType, slotName: string): any?
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

function OBSWebSocket.setPersistentData(self: OBSWebSocket, realm: Enums.ObsRealmType, slotName: string, slotValue: any)
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
function OBSWebSocket.getSceneCollectionList(self: OBSWebSocket): GetSceneCollectionListResponse
	local response = self:request("GetSceneCollectionList")
	return response :: any
end

function OBSWebSocket.setCurrentSceneCollection(self: OBSWebSocket, sceneCollectionName: string)
	self:request("SetCurrentSceneCollection", {
		sceneCollectionName = sceneCollectionName,
	})
end

function OBSWebSocket.createSceneCollection(self: OBSWebSocket, sceneCollectionName: string)
	self:request("CreateSceneCollection", {
		sceneCollectionName = sceneCollectionName,
	})
end

type GetProfileListResponse = {
	currentProfileName: string,
	profiles: { string },
}
function OBSWebSocket.getProfileList(self: OBSWebSocket): GetProfileListResponse
	local response = self:request("GetProfileList")
	return response :: any
end

function OBSWebSocket.setCurrentProfile(self: OBSWebSocket, profileName: string)
	self:request("SetCurrentProfile", {
		profileName = profileName,
	})
end

function OBSWebSocket.createProfile(self: OBSWebSocket, profileName: string)
	self:request("CreateProfile", {
		profileName = profileName,
	})
end

function OBSWebSocket.removeProfile(self: OBSWebSocket, profileName: string)
	self:request("RemoveProfile", {
		profileName = profileName,
	})
end

function OBSWebSocket.getProfileParameter(
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

function OBSWebSocket.setProfileParameter(
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
function OBSWebSocket.getVideoSettings(self: OBSWebSocket): GetVideoSettingsResponse
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
function OBSWebSocket.setVideoSettings(self: OBSWebSocket, newSettings: NewVideoSettings)
	self:request("SetVideoSettings", newSettings)
end

type GetStreamServiceSettingsResponse = {
	streamServiceType: string,
	streamServiceSettings: Types.Object,
}
function OBSWebSocket.getStreamServiceSettings(self: OBSWebSocket): GetStreamServiceSettingsResponse
	local response = self:request("GetStreamServiceSettings")

	return response :: any
end

type NewStreamServiceSettings = {
	streamServiceType: string,
	streamServiceSettings: Types.Object,
}
function OBSWebSocket.setStreamServiceSettings(self: OBSWebSocket, newSettings: NewStreamServiceSettings)
	self:request("SetStreamServiceSettings", newSettings)
end

function OBSWebSocket.getRecordDirectory(self: OBSWebSocket): string
	local response = self:request("GetRecordDirectory")

	return response.recordDirectory :: any
end

function OBSWebSocket.setRecordDirectory(self: OBSWebSocket, recordDirectory: string)
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
function OBSWebSocket.getSourceActive(self: OBSWebSocket, options: GetSourceActiveOptions?): GetSourceActiveResponse
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
function OBSWebSocket.getSourceScreenshot(self: OBSWebSocket, options: GetSourceActiveOptions): string
	local response = self:request("GetSourceScreenshot", options)

	return response.imageData :: any
end

type SaveSourceScreenshotOptions = GetSourceScreenshotOptions & {
	imageFilePath: string,
}
function OBSWebSocket.saveSourceScreenshot(self: OBSWebSocket, options: SaveSourceScreenshotOptions)
	self:request("SaveSourceScreenshot", options)
end

-- ### Scenes Requests ###

-- ### Inputs Requests ###

-- ### Transitions Requests ###

-- ### Filters Requests ###

-- ### Scene Items Requests ###

-- ### Outputs Requests ###

function OBSWebSocket.getVirtualCamStatus(self: OBSWebSocket): boolean
	local response = self:request("GetVirtualCamStatus")

	return response.outputActive :: any
end

function OBSWebSocket.toggleVirtualCam(self: OBSWebSocket): boolean
	local response = self:request("ToggleVirtualCam")

	return response.outputActive :: any
end

function OBSWebSocket.startVirtualCam(self: OBSWebSocket)
	self:request("StartVirtualCam")
end

function OBSWebSocket.stopVirtualCam(self: OBSWebSocket)
	self:request("StopVirtualCam")
end

function OBSWebSocket.getReplayBufferStatus(self: OBSWebSocket): boolean
	local response = self:request("GetReplayBufferStatus")

	return response.outputActive :: any
end

function OBSWebSocket.toggleReplayBuffer(self: OBSWebSocket): boolean
	local response = self:request("ToggleReplayBuffer")

	return response.outputActive :: any
end

function OBSWebSocket.startReplayBuffer(self: OBSWebSocket)
	self:request("StartReplayBuffer")
end

function OBSWebSocket.stopReplayBuffer(self: OBSWebSocket)
	self:request("StopReplayBuffer")
end

function OBSWebSocket.saveReplayBuffer(self: OBSWebSocket)
	self:request("SaveReplayBuffer")
end

function OBSWebSocket.getLastReplayBufferReplay(self: OBSWebSocket): string
	local response = self:request("GetLastReplayBufferReplay")

	return response.savedReplayPath :: any
end

function OBSWebSocket.getOutputList(self: OBSWebSocket): { Types.Object }
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
function OBSWebSocket.getOutputStatus(self: OBSWebSocket, outputName: string): GetOutputStatusResponse
	local response = self:request("GetOutputStatus", { outputName = outputName })

	return response :: any
end

function OBSWebSocket.toggleOutput(self: OBSWebSocket, outputName: string): boolean
	local response = self:request("ToggleOutput", { outputName = outputName })

	return response.outputActive :: any
end

function OBSWebSocket.startOutput(self: OBSWebSocket, outputName: string)
	self:request("StartOutput", { outputName = outputName })
end

function OBSWebSocket.stopOutput(self: OBSWebSocket, outputName: string)
	self:request("StopOutput", { outputName = outputName })
end

function OBSWebSocket.getOutputSettings(self: OBSWebSocket, outputName: string): Types.Object
	local response = self:request("GetOutputSettings", { outputName = outputName })

	return response.outputSettings :: any
end

function OBSWebSocket.setOutputSettings(self: OBSWebSocket, outputName: string, outputSettings: Types.Object)
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
function OBSWebSocket.getStreamStatus(self: OBSWebSocket): GetStreamStatusResponse
	local response = self:request("GetStreamStatus")

	return response :: any
end

function OBSWebSocket.toggleStream(self: OBSWebSocket): boolean
	local response = self:request("ToggleStream")

	return response.outputActive :: any
end

function OBSWebSocket.startStream(self: OBSWebSocket)
	self:request("StartStream")
end

function OBSWebSocket.stopStream(self: OBSWebSocket)
	self:request("StopStream")
end

function OBSWebSocket.sendStreamCaption(self: OBSWebSocket, captionText: string)
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
function OBSWebSocket.getRecordStatus(self: OBSWebSocket): GetRecordStatusResponse
	local response = self:request("GetRecordStatus")

	return response :: any
end

function OBSWebSocket.toggleRecord(self: OBSWebSocket): boolean
	local response = self:request("ToggleRecord")

	return response.outputActive :: any
end

function OBSWebSocket.startRecord(self: OBSWebSocket)
	self:request("StartRecord")
end

function OBSWebSocket.stopRecord(self: OBSWebSocket)
	self:request("StopRecord")
end

function OBSWebSocket.toggleRecordPause(self: OBSWebSocket)
	self:request("ToggleRecordPause")
end

function OBSWebSocket.pauseRecord(self: OBSWebSocket)
	self:request("PauseRecord")
end

function OBSWebSocket.resumeRecord(self: OBSWebSocket)
	self:request("ResumeRecord")
end

function OBSWebSocket.splitRecordFile(self: OBSWebSocket)
	self:request("SplitRecordFile")
end

function OBSWebSocket.createRecordChapter(self: OBSWebSocket, chapterName: string?)
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
function OBSWebSocket.getMediaInputStatus(
	self: OBSWebSocket,
	options: GetMediaInputStatusOptions
): GetMediaInputStatusResponse
	local response = self:request("GetMediaInputStatus")

	return response :: any
end

type SetMediaInputCursorOptions = GetMediaInputStatusOptions & {
	mediaCursor: number,
}
function OBSWebSocket.setMediaInputCursor(self: OBSWebSocket, options: SetMediaInputCursorOptions)
	self:request("SetMediaInputCursor", options)
end

type OffsetMediaInputCursorOptions = GetMediaInputStatusOptions & {
	mediaCursorOffset: number,
}
function OBSWebSocket.offsetMediaInputCursor(self: OBSWebSocket, options: OffsetMediaInputCursorOptions)
	self:request("OffsetMediaInputCursor", options)
end

type TriggerMediaInputActionOptions = GetMediaInputStatusOptions & {
	mediaAction: string,
}
function OBSWebSocket.triggerMediaInputAction(self: OBSWebSocket, options: TriggerMediaInputActionOptions)
	self:request("TriggerMediaInputAction", options)
end

-- ### Ui Requests Requests ###

function OBSWebSocket.getStudioModeEnabled(self: OBSWebSocket): boolean
	local response = self:request("GetStudioModeEnabled")

	return response.studioModeEnabled :: any
end

function OBSWebSocket.setStudioModeEnabled(self: OBSWebSocket, newState: boolean)
	self:request("TriggerMediaInputAction", { studioModeEnabled = newState })
end

type OpenInputPropertiesDialogOptions = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.openInputPropertiesDialog(self: OBSWebSocket, options: OpenInputPropertiesDialogOptions)
	self:request("OpenInputPropertiesDialog", options)
end

function OBSWebSocket.openInputFiltersDialog(self: OBSWebSocket, options: OpenInputPropertiesDialogOptions)
	self:request("OpenInputFiltersDialog", options)
end

function OBSWebSocket.openInputInteractDialog(self: OBSWebSocket, options: OpenInputPropertiesDialogOptions)
	self:request("OpenInputInteractDialog", options)
end

function OBSWebSocket.getMonitorList(self: OBSWebSocket): { Types.Object }
	local response = self:request("GetMonitorList")

	return response.monitors :: any
end

function OBSWebSocket.openVideoMixProjector(
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
function OBSWebSocket.openSourceProjector(self: OBSWebSocket, options: OpenSourceProjectorOptions)
	self:request("OpenSourceProjector", options)
end

return OBSWebSocket
