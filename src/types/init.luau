local Events = require("./events")

export type JSONType = string | number | boolean | { any } | { [string]: any }
export type Object = { [string]: JSONType }

-- OpCode

export type BaseOpCode<D = { [string]: JSONType }> = {
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
	requestType: string,
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
			requestType: string,
			requestId: string?,
			requestData: Object?,
		}
	},
}>

export type RequestBatchResponseOpCode = BaseOpCode<{
	requestId: string,
	results: { Object },
}>

-- Events

export type OnEventHandle<S> = Events.OnEventHandle<S>

return {}
