--[[

TODO: 
	* implement batch requests
	* add the remaining requests:
		- General Requests: DONE
		- Config Requests: DONE
		- Sources Requests:
		- Scenes Requests:
		- Inputs Requests:
		- Transitions Requests:
		- Filters Requests: 
		- Scene Items Requests:
		- Outputs Requests:
		- Stream Requests:
		- Record Requests:
		- Media Inputs Requests:
		- Ui Requsts:

	Follow this format:
		For requests that have multiple keys, return the object (for example: getStats)
		For requests that have one key, return the value of the key (for example: getPersistentData)
		For requests that have two keys and have same type, return a tuple of both (for example: getProfileParameter)
]]

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
	--- Version number that the client would like the obs-websocket server to use
	rpcVersion: number,
	--- Bitmask of ``EventSubscriptions`` enum. By default, all event categories are subscribed, except for events marked as high volume
	eventSubscriptions: number?,
}
--- Connect to the OBS WebSocket server
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

--- Connects to a OBS WebSocket event
methods.on = (
	function(self: OBSWebSocket, eventType: string, handler: (data: {}) -> ())
		if not self._handlers[eventType] then
			self._handlers[eventType] = {}
		end
		table.insert(self._handlers[eventType], handler :: any)
	end :: any
) :: Types.OnEventHandle<OBSWebSocket>

methods._makeRequest = function(
	self: OBSWebSocket,
	requestType: string,
	requestData: {}?
): Types.RequestResponseOpCode<Types.Object>
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

	return finalJson :: any
end

-- ### General Requests ###

type GetVersionResponse = {
	--- Current OBS Studio version
	obsVersion: string,
	--- Current obs-websocket version
	obsWebSocketVersion: string,
	--- Current latest obs-websocket RPC version
	rpcVersion: number,
	--- Array of available RPC requests for the currently negotiated RPC version
	availableRequests: { string },
	--- Image formats available in ``getSourceScreenshot`` and ``saveSourceScreenshot`` requests
	supportedImageFormats: { string },
	--- Name of the platform. Usually ``windows``, ``macos``, or ``ubuntu`` (linux flavor). Not guaranteed to be any of those
	platform: string,
	--- Description of the platform, like ``Windows 10 (10.0)``
	platformDescription: string,
}
--- Gets data about the current plugin and RPC version
methods.getVersion = function(self: OBSWebSocket): GetVersionResponse
	local response = self:_makeRequest("GetVersion")
	return response.d.responseData :: any
end

type GetStatsResponse = {
	--- Current CPU usage in percent
	cpuUsage: number,
	--- Amount of memory in MB currently being used by OBS
	memoryUsage: number,
	--- Available disk space on the device being used for recording storage
	availableDiskSpace: number,
	--- Current FPS being rendered
	activeFps: number,
	--- Average time in milliseconds that OBS is taking to render a frame
	averageFrameRenderTime: number,
	--- Number of frames skipped by OBS in the render thread
	renderSkippedFrames: number,
	--- Total number of frames outputted by the render thread
	renderTotalFrames: number,
	--- Number of frames skipped by OBS in the output thread
	outputSkippedFrames: number,
	--- Total number of frames outputted by the output thread
	outputTotalFrames: number,
	--- Total number of messages received by obs-websocket from the client
	webSocketSessionIncomingMessages: number,
	--- Total number of messages sent by obs-websocket to the client
	webSocketSessionOutgoingMessages: number,
}
--- Gets statistics about OBS, obs-websocket, and the current session
methods.getStats = function(self: OBSWebSocket): GetStatsResponse
	local response = self:_makeRequest("GetStats")
	return response.d.responseData :: any
end

--- Broadcasts a ``CustomEvent`` to all WebSocket clients. Receivers are clients which are identified and subscribed
methods.broadcastCustomEvent = function(self: OBSWebSocket, eventData: Types.Object)
	local response = self:_makeRequest("BroadcastCustomEvent", eventData)
end

type CallVendorRequestResponse = {
	--- Name of the vendor to use
	vendorName: string,
	--- The request type to call
	requestType: string,
	--- Object containing appropriate request data
	responseData: Types.Object,
}
--- Call a request registered to a vendor.
---
--- A vendor is a unique name registered by a third-party plugin or script, which allows for custom requests and events to be added to obs-websocket.
--- If a plugin or script implements vendor requests or events, documentation is expected to be provided with them.
methods.callVendorRequest = function(
	self: OBSWebSocket,
	vendorName: string,
	requestType: string,
	requestData: { [string]: any }?
)
	local response = self:_makeRequest("CallVendorRequest", {
		vendorName = vendorName,
		requestType = requestType,
		requestData = requestData,
	})
	return response.d.responseData :: any
end

--- Gets an array of all hotkey names in OBS
---
--- Note: Hotkey functionality in obs-websocket comes as-is, and we do not guarantee support if things are broken.
--- In 9/10 usages of hotkey requests, there exists a better, more reliable method via other requests
methods.getHotkeyList = function(self: OBSWebSocket): { string }
	local response = self:_makeRequest("GetHotkeyList")
	return response.d.responseData.hotkeys :: any
end

--- Triggers a hotkey using its name. See ``getHotkeyList``
---
--- Note: Hotkey functionality in obs-websocket comes as-is, and we do not guarantee support if things are broken.
--- In 9/10 usages of hotkey requests, there exists a better, more reliable method via other requests
methods.triggerHotkeyByName = function(self: OBSWebSocket, hotkeyName: string, contextName: string?)
	local response = self:_makeRequest("TriggerHotkeyByName", {
		hotkeyName = hotkeyName,
		contextName = contextName,
	})
end

type KeyModifiers = {
	--- Press Shift
	shift: boolean?,
	--- Press CTRL
	control: boolean?,
	--- Press ALT
	alt: boolean?,
	--- Press CMD (Mac)
	command: boolean?,
}
--- Triggers a hotkey using a sequence of keys
---
--- Note: Hotkey functionality in obs-websocket comes as-is, and we do not guarantee support if things are broken.
--- In 9/10 usages of hotkey requests, there exists a better, more reliable method via other requests
methods.triggerHotkeyByKeySequence = function(self: OBSWebSocket, keyId: string, keyModifiers: KeyModifiers)
	local response = self:_makeRequest("TriggerHotkeyByKeySequence", {
		keyId = keyId,
		keyModifiers = keyModifiers,
	})
end

-- ### Config Requests ###

type RealmType = "OBS_WEBSOCKET_DATA_REALM_GLOBAL" | "OBS_WEBSOCKET_DATA_REALM_PROFILE"
--- Gets the value of a "slot" from the selected persistent data realm
methods.getPersistentData = function(self: OBSWebSocket, realm: RealmType, slotName: string): Types.JSONType?
	local response = self:_makeRequest("GetPersistentData", {
		realm = realm,
		slotName = slotName,
	})

	local slotValue: any = (response.d.responseData :: any).slotValue
	if slotValue == serde.json.Values.Null then
		slotValue = nil
	end

	return slotValue :: any
end

--- Sets the value of a "slot" from the selected persistent data realm
methods.setPersistentData = function(self: OBSWebSocket, realm: RealmType, slotName: string, slotValue: Types.JSONType)
	local response = self:_makeRequest("SetPersistentData", {
		realm = realm,
		slotName = slotName,
		slotValue = slotValue,
	})
end

type GetSceneCollectionListResponse = {
	--- The name of the current scene collection
	currentSceneCollectionName: string,
	--- Array of all available scene collections
	sceneCollections: { string },
}
--- Gets an array of all scene collections
methods.getSceneCollectionList = function(self: OBSWebSocket): GetSceneCollectionListResponse
	local response = self:_makeRequest("GetSceneCollectionList")
	return response.d.responseData :: any
end

--- Switches to a scene collection
---
--- Note: This will block until the collection has finished changing
methods.setCurrentSceneCollection = function(self: OBSWebSocket, sceneCollectionName: string)
	local response = self:_makeRequest("SetCurrentSceneCollection", {
		sceneCollectionName = sceneCollectionName,
	})
end

--- Creates a new scene collection, switching to it in the process
---
--- Note: This will block until the collection has finished changing
methods.createSceneCollection = function(self: OBSWebSocket, sceneCollectionName: string)
	local response = self:_makeRequest("CreateSceneCollection", {
		sceneCollectionName = sceneCollectionName,
	})
end

type GetProfileListResponse = {
	--- The name of the current profile
	currentProfileName: string,
	--- Array of all available profiles
	profiles: { string },
}
--- Gets an array of all profiles
methods.getProfileList = function(self: OBSWebSocket): GetProfileListResponse
	local response = self:_makeRequest("GetProfileList")
	return response.d.responseData :: any
end

--- Switches to a profile
methods.setCurrentProfile = function(self: OBSWebSocket, profileName: string)
	local response = self:_makeRequest("SetCurrentProfile", {
		profileName = profileName,
	})
end

--- Creates a new profile, switching to it in the process
methods.createProfile = function(self: OBSWebSocket, profileName: string)
	local response = self:_makeRequest("CreateProfile", {
		profileName = profileName,
	})
end

--- Removes a profile. If the current profile is chosen, it will change to a different profile first
methods.removeProfile = function(self: OBSWebSocket, profileName: string)
	local response = self:_makeRequest("RemoveProfile", {
		profileName = profileName,
	})
end

--- Gets a parameter from the current profile's configuration.
methods.getProfileParameter = function(
	self: OBSWebSocket,
	parameterCategory: string,
	parameterName: string
): (string?, string?)
	local response = self:_makeRequest("GetProfileParameter", {
		parameterCategory = parameterCategory,
		parameterName = parameterName,
	})

	local parameterValue: string? = (response.d.responseData :: any).parameterValue
	local defaultParameterValue: string? = (response.d.responseData :: any).defaultParameterValue
	if parameterValue == serde.json.Values.Null then
		parameterValue = nil
	end
	if defaultParameterValue == serde.json.Values.Null then
		defaultParameterValue = nil
	end
	return parameterValue, defaultParameterValue
end

--- Sets the value of a parameter in the current profile's configuration.
methods.setProfileParameter = function(
	self: OBSWebSocket,
	parameterCategory: string,
	parameterName: string,
	parameterValue: string?
)
	local response = self:_makeRequest("SetProfileParameter", {
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
--- Gets the current video settings
---
--- Note: To get the true FPS value, divide the FPS numerator by the FPS denominator. Example: ``60000/1001``
methods.getVideoSettings = function(self: OBSWebSocket): GetVideoSettingsResponse
	local response = self:_makeRequest("GetVideoSettings")

	return response.d.responseData :: any
end

type NewVideoSettings = {
	--- Numerator of the fractional FPS value
	fpsNumerator: number?,
	--- Denominator of the fractional FPS value
	fpsDenominator: number?,
	--- Width of the base (canvas) resolution in pixels
	baseWidth: number?,
	--- Height of the base (canvas) resolution in pixels
	baseHeight: number?,
	--- Width of the output resolution in pixels
	outputWidth: number?,
	--- Height of the output resolution in pixels
	outputHeight: number?,
}
--- Sets the current video settings
---
--- Note: Fields must be specified in pairs. For example, you cannot set only ``baseWidth`` without needing to specify ``baseHeight``
methods.setVideoSettings = function(self: OBSWebSocket, newSettings: NewVideoSettings)
	local response = self:_makeRequest("SetVideoSettings", newSettings)
end

type GetStreamServiceSettingsResponse = {
	--- Stream service type, like ``rtmp_custom`` or ``rtmp_common``
	streamServiceType: string,
	--- Stream service settings
	streamServiceSettings: Types.Object,
}
--- Gets the current stream service settings (stream destination)
methods.getStreamServiceSettings = function(self: OBSWebSocket): GetStreamServiceSettingsResponse
	local response = self:_makeRequest("GetStreamServiceSettings")

	return response.d.responseData :: any
end

type NewStreamServiceSettings = {
	--- Type of stream service to apply. Example: ``rtmp_common`` or ``rtmp_custom``
	streamServiceType: string,
	--- Settings to apply to the service
	streamServiceSettings: Types.Object,
}
--- Sets the current stream service settings (stream destination)
---
--- Note: Simple RTMP settings can be set with type ``rtmp_custom`` and the settings fields ``server`` and ``key``
methods.setStreamServiceSettings = function(self: OBSWebSocket, newSettings: NewStreamServiceSettings)
	self:_makeRequest("SetStreamServiceSettings", newSettings)
end

--- Gets the current directory that the record output is set to
methods.getRecordDirectory = function(self: OBSWebSocket): string
	local response = self:_makeRequest("GetRecordDirectory")

	return response.d.responseData.recordDirectory :: any
end

--- Sets the current directory that the record output writes files to
methods.setRecordDirectory = function(self: OBSWebSocket, recordDirectory: string)
	self:_makeRequest("SetRecordDirectory", { recordDirectory = recordDirectory })
end

-- ### Sources Requests ###

-- ### Scenes Requests ###

-- ### Inputs Requests ###

-- ### Transitions Requests ###

-- ### Filters Requests ###

-- ### Scene Items Requests ###

-- ### Outputs Requests ###

--- Gets the status of the virtualcam output
methods.getVirtualCamStatus = function(self: OBSWebSocket): boolean
	local response = self:_makeRequest("GetVirtualCamStatus")

	return response.d.responseData.outputActive :: any
end

--- Toggles the state of the virtualcam output
methods.toggleVirtualCam = function(self: OBSWebSocket): boolean
	local response = self:_makeRequest("ToggleVirtualCam")

	return response.d.responseData.outputActive :: any
end

--- Starts the virtualcam output
methods.startVirtualCam = function(self: OBSWebSocket)
	self:_makeRequest("StartVirtualCam")
end

--- Stops the virtualcam output
methods.stopVirtualCam = function(self: OBSWebSocket)
	self:_makeRequest("StopVirtualCam")
end

-- ### Stream Requests ###

-- ### Record Requests ###

-- ### Media Inputs Requests ###

-- ### Ui Requests Requests ###

return webSocket
