local process = zune.process

local OBSWebSocket = require("../src/")

local obs = OBSWebSocket.new()

obs.onReady:Connect(function()
	print("Connected to OBS!")
	local results = obs:batchRequest({
		{
			requestType = "Sleep",
			requestData = {
				sleepMillis = 1000,
			},
		},
		{
			requestType = "GetStats",
		},
	})
	print(results)
	--print(obs:request("GetInputSettings", { inputName = "thing" }))
end)

obs.onSocketClosed:Once(function(code, name)
	if code then
		print(`Connection to OBS closed: {name} ({name})`)
	else
		print("Connection to OBS closed")
	end
end)

--[[
obs:on("StudioModeStateChanged", function(d: OBSWebSocket.StudioModeStateChanged)
	local vCamEnabled = obs:getVirtualCamStatus()
	if d.studioModeEnabled == true then
		if vCamEnabled then
			obs:stopVirtualCam()
		end
	else
		if not vCamEnabled then
			obs:startVirtualCam()
		end
	end
end)
]]

obs:connect(process.env["OBS_WEBSOCKET_PASSWORD"])
