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

type GetSourceActiveRequest = {
	sourceName: string?,
	sourceUuid: string?,
}
function OBSWebSocket.getSourceActive(self: OBSWebSocket, options: GetSourceActiveRequest?): (boolean, boolean)
	local response = self:request("GetSourceActive", options)

	return response.videoActive, response.videoShowing
end

type GetSourceScreenshotRequest = {
	sourceName: string?,
	sourceUuid: string?,
	imageFormat: string,
	imageWidth: number?,
	imageHeight: number?,
	imageCompressionQuality: number?,
}
function OBSWebSocket.getSourceScreenshot(self: OBSWebSocket, options: GetSourceActiveRequest): string
	local response = self:request("GetSourceScreenshot", options)

	return response.imageData :: any
end

type SaveSourceScreenshotRequest = GetSourceScreenshotRequest & {
	imageFilePath: string,
}
function OBSWebSocket.saveSourceScreenshot(self: OBSWebSocket, options: SaveSourceScreenshotRequest)
	self:request("SaveSourceScreenshot", options)
end

-- ### Scenes Requests ###

type GetSceneListResponse = {
	currentProgramSceneName: string,
	currentProgramSceneUuid: string,
	currentPreviewSceneName: string,
	currentPreviewSceneUuid: string,
	scenes: { Types.Object },
}
function OBSWebSocket.getSceneList(self: OBSWebSocket): GetSceneListResponse
	local response = self:request("GetSceneList")

	return response :: any
end

function OBSWebSocket.getGroupList(self: OBSWebSocket): { Types.Object }
	local response = self:request("GetGroupList")

	return response.groups :: any
end

type GetCurrentProgramSceneResponse = {
	sceneName: string,
	sceneUuid: string,
}
function OBSWebSocket.getCurrentProgramScene(self: OBSWebSocket): string
	local response = self:request("GetCurrentProgramScene")

	return response :: any
end

type SetCurrentProgramSceneRequest = {
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.setCurrentProgramScene(self: OBSWebSocket, options: SetCurrentProgramSceneRequest)
	self:request("SetCurrentProgramScene", options)
end

type GetCurrentPreviewSceneResponse = {
	sceneName: string,
	sceneUuid: string,
	currentPreviewSceneName: string,
	currentPreviewSceneUuid: string,
}
function OBSWebSocket.getCurrentPreviewScene(self: OBSWebSocket): GetCurrentPreviewSceneResponse
	local response = self:request("GetCurrentPreviewScene")

	return response :: any
end

type SetCurrentPreviewSceneRequest = {
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.setCurrentPreviewScene(self: OBSWebSocket, options: SetCurrentPreviewSceneRequest)
	self:request("SetCurrentPreviewScene", options)
end

function OBSWebSocket.createScene(self: OBSWebSocket, sceneName: string): string
	local response = self:request("CreateScene", { sceneName = sceneName })

	return response.sceneUuid :: any
end

type RemoveSceneRequest = {
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.removeScene(self: OBSWebSocket, options: RemoveSceneRequest)
	self:request("RemoveScene", options)
end

type SetSceneNameRequest = {
	newSceneName: string,
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.setSceneName(self: OBSWebSocket, options: SetSceneNameRequest)
	self:request("SetSceneName", options)
end

type GetSceneSceneTransitionOverrideRequest = {
	sceneName: string?,
	sceneUuid: string?,
}
type GetSceneSceneTransitionOverrideResponse = {
	transitionName: string,
	transitionDuration: number,
}
function OBSWebSocket.getSceneSceneTransitionOverride(
	self: OBSWebSocket,
	options: GetSceneSceneTransitionOverrideRequest
): GetSceneSceneTransitionOverrideResponse
	local response = self:request("GetSceneSceneTransitionOverride", options)

	return response :: any
end

type SetSceneSceneTransitionOverrideRequest = {
	transitionName: string,
	transitionDuration: number,
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.setSceneSceneTransitionOverride(
	self: OBSWebSocket,
	options: SetSceneSceneTransitionOverrideRequest
)
	self:request("SetSceneSceneTransitionOverride", options)
end

-- ### Inputs Requests ###

function OBSWebSocket.getInputList(self: OBSWebSocket, inputKind: string?): { Types.Object }
	local response = self:request("GetInputList", { inputKind = inputKind })

	return response.inputs :: any
end

function OBSWebSocket.getInputKindList(self: OBSWebSocket, unversioned: boolean?): { string }
	local response = self:request("GetInputKindList", { unversioned = unversioned })

	return response.inputKinds :: any
end

type GetSpecialInputsResponse = {
	desktop1: string,
	desktop2: string,
	mic1: string,
	mic2: string,
	mic3: string,
	mic4: string,
}
function OBSWebSocket.getSpecialInputs(self: OBSWebSocket): GetSpecialInputsResponse
	local response = self:request("GetSpecialInputs")

	return response :: any
end

type CreateInputRequest = {
	sceneName: string?,
	sceneUuid: string?,
	inputName: string,
	inputKind: string,
	inputSettings: Types.Object?,
	sceneItemEnabled: boolean?,
}
type CreateInputResponse = {
	inputUuid: string,
	sceneItemId: number,
}
function OBSWebSocket.createInput(self: OBSWebSocket, options: CreateInputRequest): CreateInputResponse
	local response = self:request("CreateInput", options)

	return response :: any
end

type RemoveInputRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.removeInput(self: OBSWebSocket, options: RemoveInputRequest)
	self:request("RemoveInput", options)
end

type SetInputNameRequest = {
	inputName: string?,
	inputUuid: string?,
	newInputName: string,
}
function OBSWebSocket.setInputName(self: OBSWebSocket, options: SetInputNameRequest)
	self:request("SetInputName", options)
end

function OBSWebSocket.getInputDefaultSettings(self: OBSWebSocket, inputKind: string): Types.Object
	local response = self:request("GetInputDefaultSettings", { inputKind = inputKind })

	return response.defaultInputSettings :: any
end

type GetInputSettingsRequest = {
	inputName: string?,
	inputUuid: string?,
}
type GetInputSettingsResponse = {
	inputSettings: Types.Object,
	inputKind: string,
}
function OBSWebSocket.getInputSettings(self: OBSWebSocket, options: GetInputSettingsRequest): GetInputSettingsResponse
	local response = self:request("GetInputSettings", options)

	return response :: any
end

type SetInputSettingsRequest = {
	inputName: string?,
	inputUuid: string?,
	inputSettings: Types.Object,
	overlay: boolean?,
}
function OBSWebSocket.setInputSettings(self: OBSWebSocket, options: SetInputSettingsRequest)
	self:request("SetInputSettings", options)
end

type GetInputMuteRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputMute(self: OBSWebSocket, options: GetInputMuteRequest): boolean
	local response = self:request("GetInputMute", options)

	return response.inputMuted :: any
end

type SetInputMuteRequest = {
	inputName: string?,
	inputUuid: string?,
	inputMuted: boolean,
}
function OBSWebSocket.setInputMute(self: OBSWebSocket, options: SetInputMuteRequest)
	self:request("SetInputMute", options)
end

type ToggleInputMuteRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.toggleInputMute(self: OBSWebSocket, options: ToggleInputMuteRequest)
	self:request("ToggleInputMute", options)
end

type GetInputVolumeRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputVolume(self: OBSWebSocket, options: GetInputVolumeRequest): number
	local response = self:request("GetInputVolume", options)

	return response.inputVolume :: any
end

type SetInputVolumeRequest = {
	inputName: string?,
	inputUuid: string?,
	inputVolumeMul: number?,
	inputVolumeDb: number?,
}
function OBSWebSocket.setInputVolume(self: OBSWebSocket, options: SetInputVolumeRequest)
	self:request("SetInputVolume", options)
end

type GetInputAudioBalanceRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputAudioBalance(self: OBSWebSocket, options: GetInputAudioBalanceRequest): number
	local response = self:request("GetInputAudioBalance", options)

	return response.inputAudioBalance :: any
end

type SetInputAudioBalanceRequest = {
	inputName: string?,
	inputUuid: string?,
	inputAudioBalance: number,
}
function OBSWebSocket.setInputAudioBalance(self: OBSWebSocket, options: SetInputAudioBalanceRequest)
	self:request("SetInputAudioBalance", options)
end

type GetInputAudioSyncOffsetRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputAudioSyncOffset(self: OBSWebSocket, options: GetInputAudioSyncOffsetRequest): number
	local response = self:request("GetInputAudioSyncOffset", options)

	return response.inputAudioSyncOffset :: any
end

type SetInputAudioSyncOffsetRequest = {
	inputName: string?,
	inputUuid: string?,
	inputAudioSyncOffset: number,
}
function OBSWebSocket.setInputAudioSyncOffset(self: OBSWebSocket, options: SetInputAudioSyncOffsetRequest)
	self:request("SetInputAudioSyncOffset", options)
end

type GetInputAudioMonitorTypeRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputAudioMonitorType(
	self: OBSWebSocket,
	options: GetInputAudioMonitorTypeRequest
): Enums.ObsMonitorType
	local response = self:request("GetInputAudioMonitorType", options)

	return response.monitorType :: any
end

type SetInputAudioMonitorTypeRequest = {
	inputName: string?,
	inputUuid: string?,
	monitorType: Enums.ObsMonitorType,
}
function OBSWebSocket.setInputAudioMonitorType(self: OBSWebSocket, options: SetInputAudioMonitorTypeRequest)
	self:request("SetInputAudioMonitorType", options)
end

type GetInputAudioTracksRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputAudioTracks(self: OBSWebSocket, options: GetInputAudioTracksRequest): { Types.Object }
	local response = self:request("GetInputAudioTracks", options)

	return response.inputAudioTracks :: any
end

type SetInputAudioTracksRequest = {
	inputName: string?,
	inputUuid: string?,
	inputAudioTracks: { Types.Object },
}
function OBSWebSocket.setInputAudioTracks(self: OBSWebSocket, options: SetInputAudioTracksRequest)
	self:request("SetInputAudioTracks", options)
end

type GetInputDeinterlaceModeRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputDeinterlaceMode(
	self: OBSWebSocket,
	options: GetInputDeinterlaceModeRequest
): Enums.ObsDeinterlaceMode
	local response = self:request("GetInputDeinterlaceMode", options)

	return response.inputDeinterlaceMode :: any
end

type SetInputDeinterlaceModeRequest = {
	inputName: string?,
	inputUuid: string?,
	inputDeinterlaceMode: Enums.ObsDeinterlaceMode,
}
function OBSWebSocket.setInputDeinterlaceMode(self: OBSWebSocket, options: SetInputDeinterlaceModeRequest)
	self:request("SetInputDeinterlaceMode", options)
end

type GetInputDeinterlaceFieldOrderRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.getInputDeinterlaceFieldOrder(
	self: OBSWebSocket,
	options: GetInputDeinterlaceFieldOrderRequest
): Enums.ObsDeinterlaceFieldOrder
	local response = self:request("GetInputDeinterlaceFieldOrder", options)

	return response.inputDeinterlaceFieldOrder :: any
end

type SetInputDeinterlaceFieldOrderRequest = {
	inputName: string?,
	inputUuid: string?,
	inputDeinterlaceFieldOrder: Enums.ObsDeinterlaceFieldOrder,
}
function OBSWebSocket.setInputDeinterlaceFieldOrder(self: OBSWebSocket, options: SetInputDeinterlaceFieldOrderRequest)
	self:request("SetInputDeinterlaceFieldOrder", options)
end

type GetInputPropertiesListPropertyItemsRequest = {
	inputName: string?,
	inputUuid: string?,
	propertyName: string,
}
function OBSWebSocket.getInputPropertiesListPropertyItems(
	self: OBSWebSocket,
	options: GetInputPropertiesListPropertyItemsRequest
): { Types.Object }
	local response = self:request("GetInputPropertiesListPropertyItems", options)

	return response.propertyItems :: any
end

type PressInputPropertiesButtonRequest = {
	inputName: string?,
	inputUuid: string?,
	propertyName: Types.ButtonPropertyName,
}
function OBSWebSocket.pressInputPropertiesButton(self: OBSWebSocket, options: PressInputPropertiesButtonRequest)
	self:request("PressInputPropertiesButton", options)
end

-- ### Transitions Requests ###

function OBSWebSocket.getTransitionKindList(self: OBSWebSocket): { string }
	local response = self:request("GetTransitionKindList")

	return response.transitionKinds :: any
end

type GetSceneTransitionListResponse = {
	currentTransitionName: string,
	currentTransitionUuid: string,
	currentTransitionDuration: number,
	transitions: { Types.Object },
}
function OBSWebSocket.getSceneTransitionList(self: OBSWebSocket): GetSceneTransitionListResponse
	local response = self:request("GetSceneTransitionList")

	return response :: any
end

type GetCurrentSceneTransitionResponse = {
	transitionName: string,
	transitionUuid: string,
	transitionKind: string,
	transitionFixed: boolean,
	transitionDuration: number?,
	transitionConfigurable: boolean,
	transitionSettings: Types.Object?,
}
function OBSWebSocket.getCurrentSceneTransition(self: OBSWebSocket): GetCurrentSceneTransitionResponse
	local response = self:request("GetCurrentSceneTransition")

	return response :: any
end

function OBSWebSocket.setCurrentSceneTransition(self: OBSWebSocket, transitionName: string)
	self:request("SetCurrentSceneTransition", { transitionName = transitionName })
end

function OBSWebSocket.setCurrentSceneTransitionDuration(self: OBSWebSocket, transitionDuration: number)
	self:request("SetCurrentSceneTransitionDuration", { transitionDuration = transitionDuration })
end

function OBSWebSocket.setCurrentSceneTransitionSettings(
	self: OBSWebSocket,
	transitionSettings: Types.Object,
	overlay: boolean?
)
	self:request("SetCurrentSceneTransitionSettings", { transitionSettings = transitionSettings, overlay = overlay })
end

function OBSWebSocket.getCurrentSceneTransitionCursor(self: OBSWebSocket): number
	local response = self:request("GetCurrentSceneTransitionCursor")

	return response.transitionCursor :: any
end

function OBSWebSocket.triggerStudioModeTransition(self: OBSWebSocket)
	self:request("TriggerStudioModeTransition")
end

--- @deprecated
function OBSWebSocket.setTBarPosition(self: OBSWebSocket, position: number, release: boolean?)
	self:request("SetTBarPosition", { position = position, release = release })
end

-- ### Filters Requests ###

function OBSWebSocket.getSourceFilterKindList(self: OBSWebSocket): { string }
	local response = self:request("GetSourceFilterKindList")

	return response.sourceFilterKinds :: any
end

type GetSourceFilterListRequest = {
	sourceName: string?,
	sourceUuid: string?,
}
function OBSWebSocket.getSourceFilterList(self: OBSWebSocket, options: GetSourceFilterListRequest): { Types.Object }
	local response = self:request("GetSourceFilterList", options)

	return response.filters :: any
end

function OBSWebSocket.getSourceFilterDefaultSettings(self: OBSWebSocket, filterKind: string): Types.Object
	local response = self:request("GetSourceFilterDefaultSettings", { filterKind = filterKind })

	return response.defaultFilterSettings :: any
end

type CreateSourceFilterRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
	filterType: string,
	filterSettings: Types.Object?,
}
function OBSWebSocket.createSourceFilter(self: OBSWebSocket, options: CreateSourceFilterRequest): string
	local response = self:request("CreateSourceFilter", options)

	return response.filterName :: any
end

type RemoveSourceFilterRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
}
function OBSWebSocket.removeSourceFilter(self: OBSWebSocket, options: RemoveSourceFilterRequest)
	self:request("RemoveSourceFilter", options)
end

type SetSourceFilterNameRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
	newFilterName: string,
}
function OBSWebSocket.setSourceFilterName(self: OBSWebSocket, options: SetSourceFilterNameRequest)
	self:request("SetSourceFilterName", options)
end

type GetSourceFilterRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
}
type GetSourceFilterResponse = {
	filterEnabled: boolean,
	filterIndex: number,
	filterKind: string,
	filterSettings: Types.Object,
}
function OBSWebSocket.getSourceFilter(self: OBSWebSocket, options: GetSourceFilterRequest): GetSourceFilterResponse
	local response = self:request("GetSourceFilter", options)

	return response :: any
end

type SetSourceFilterIndexRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
	filterIndex: number,
}
function OBSWebSocket.setSourceFilterIndex(self: OBSWebSocket, options: SetSourceFilterIndexRequest)
	self:request("SetSourceFilterIndex", options)
end

type SetSourceFilterSettingsRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
	filterSettings: Types.Object,
	overlay: boolean?,
}
function OBSWebSocket.setSourceFilterSettings(self: OBSWebSocket, options: SetSourceFilterSettingsRequest)
	self:request("SetSourceFilterSettings", options)
end

type SetSourceFilterEnabledRequest = {
	sourceName: string?,
	sourceUuid: string?,
	filterName: string,
	filterEnabled: boolean,
}
function OBSWebSocket.setSourceFilterEnabled(self: OBSWebSocket, options: SetSourceFilterEnabledRequest)
	self:request("SetSourceFilterEnabled", options)
end

-- ### Scene Items Requests ###

type GetSceneItemListRequest = {
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.getSceneItemList(self: OBSWebSocket, options: GetSceneItemListRequest): { Types.Object }
	local response = self:request("GetSceneItemList", options)

	return response.sceneItems :: any
end

type GetGroupSceneItemListRequest = {
	sceneName: string?,
	sceneUuid: string?,
}
function OBSWebSocket.getGroupSceneItemList(self: OBSWebSocket, options: GetGroupSceneItemListRequest): { Types.Object }
	local response = self:request("GetGroupSceneItemList", options)

	return response.sceneItems :: any
end

type GetSceneItemIdRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sourceName: string,
	searchOffset: number?,
}
function OBSWebSocket.getSceneItemId(self: OBSWebSocket, options: GetSceneItemIdRequest): number
	local response = self:request("GetSceneItemId", options)

	return response.sceneItemId :: any
end

type GetSceneItemSourceRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.getSceneItemSource(self: OBSWebSocket, options: GetSceneItemSourceRequest): (string, string)
	local response = self:request("GetSceneItemSource", options)

	return response.sourceName, response.sourceUuid
end

type CreateSceneItemRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sourceName: string?,
	sourceUuid: string?,
	sceneItemEnabled: boolean,
}
function OBSWebSocket.createSceneItem(self: OBSWebSocket, options: CreateSceneItemRequest): number
	local response = self:request("CreateSceneItem", options)

	return response.sceneItemId :: any
end

type RemoveSceneItemRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.removeSceneItem(self: OBSWebSocket, options: RemoveSceneItemRequest)
	self:request("RemoveSceneItem", options)
end

type DuplicateSceneItemRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
	destinationSceneName: string?,
	destinationSceneUuid: string?,
}
function OBSWebSocket.duplicateSceneItem(self: OBSWebSocket, options: DuplicateSceneItemRequest): number
	local response = self:request("DuplicateSceneItem", options)

	return response.sceneItemId :: any
end

type GetSceneItemTransformRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.getSceneItemTransform(self: OBSWebSocket, options: GetSceneItemTransformRequest): Types.Object
	local response = self:request("GetSceneItemTransform", options)

	return response.sceneItemTransform :: any
end

type SetSceneItemTransformRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
	sceneItemTransform: Types.Object,
}
function OBSWebSocket.setSceneItemTransform(self: OBSWebSocket, options: SetSceneItemTransformRequest)
	self:request("SetSceneItemTransform", options)
end

type GetSceneItemEnabledRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.getSceneItemEnabled(self: OBSWebSocket, options: GetSceneItemEnabledRequest): boolean
	local response = self:request("GetSceneItemEnabled", options)

	return response.sceneItemEnabled :: any
end

type SetSceneItemEnabledRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
	sceneItemEnabled: boolean,
}
function OBSWebSocket.setSceneItemEnabled(self: OBSWebSocket, options: SetSceneItemEnabledRequest)
	self:request("SetSceneItemEnabled", options)
end

type GetSceneItemLockedRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.getSceneItemLocked(self: OBSWebSocket, options: GetSceneItemLockedRequest): boolean
	local response = self:request("GetSceneItemLocked", options)

	return response.sceneItemLocked :: any
end

type SetSceneItemLockedRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
	sceneItemLocked: boolean,
}
function OBSWebSocket.setSceneItemLocked(self: OBSWebSocket, options: SetSceneItemLockedRequest)
	self:request("SetSceneItemLocked", options)
end

type GetSceneItemIndexRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.getSceneItemIndex(self: OBSWebSocket, options: GetSceneItemIndexRequest): number
	local response = self:request("GetSceneItemIndex", options)

	return response.sceneItemIndex :: any
end

type SetSceneItemIndexRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
	sceneItemIndex: number,
}
function OBSWebSocket.setSceneItemIndex(self: OBSWebSocket, options: SetSceneItemIndexRequest)
	self:request("SetSceneItemIndex", options)
end

type GetSceneItemBlendModeRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
}
function OBSWebSocket.getSceneItemBlendMode(
	self: OBSWebSocket,
	options: GetSceneItemBlendModeRequest
): Enums.ObsBlendMode
	local response = self:request("GetSceneItemBlendMode", options)

	return response.sceneItemBlendMode :: any
end

type SetSceneItemBlendModeRequest = {
	sceneName: string?,
	sceneUuid: string?,
	sceneItemId: number,
	sceneItemBlendMode: Enums.ObsBlendMode,
}
function OBSWebSocket.setSceneItemBlendMode(self: OBSWebSocket, options: SetSceneItemBlendModeRequest)
	self:request("SetSceneItemBlendMode", options)
end

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

type GetMediaInputStatusRequest = {
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
	options: GetMediaInputStatusRequest
): GetMediaInputStatusResponse
	local response = self:request("GetMediaInputStatus")

	return response :: any
end

type SetMediaInputCursorRequest = GetMediaInputStatusRequest & {
	mediaCursor: number,
}
function OBSWebSocket.setMediaInputCursor(self: OBSWebSocket, options: SetMediaInputCursorRequest)
	self:request("SetMediaInputCursor", options)
end

type OffsetMediaInputCursorRequest = GetMediaInputStatusRequest & {
	mediaCursorOffset: number,
}
function OBSWebSocket.offsetMediaInputCursor(self: OBSWebSocket, options: OffsetMediaInputCursorRequest)
	self:request("OffsetMediaInputCursor", options)
end

type TriggerMediaInputActionRequest = GetMediaInputStatusRequest & {
	mediaAction: string,
}
function OBSWebSocket.triggerMediaInputAction(self: OBSWebSocket, options: TriggerMediaInputActionRequest)
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

type OpenInputPropertiesDialogRequest = {
	inputName: string?,
	inputUuid: string?,
}
function OBSWebSocket.openInputPropertiesDialog(self: OBSWebSocket, options: OpenInputPropertiesDialogRequest)
	self:request("OpenInputPropertiesDialog", options)
end

function OBSWebSocket.openInputFiltersDialog(self: OBSWebSocket, options: OpenInputPropertiesDialogRequest)
	self:request("OpenInputFiltersDialog", options)
end

function OBSWebSocket.openInputInteractDialog(self: OBSWebSocket, options: OpenInputPropertiesDialogRequest)
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

type OpenSourceProjectorRequest = {
	sourceName: string,
	sourceUuid: string,
	monitorIndex: number,
	projectorGeometry: string,
}
function OBSWebSocket.openSourceProjector(self: OBSWebSocket, options: OpenSourceProjectorRequest)
	self:request("OpenSourceProjector", options)
end

return OBSWebSocket
