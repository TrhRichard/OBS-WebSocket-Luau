local process = zune.process

local OBSWebSocket = require("../src/")

local obs = OBSWebSocket.new()

obs.onReady:Connect(function()
	print("Connected to OBS!")
end)

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

obs:connect(process.env["OBS_WEBSOCKET_PASSWORD"])
