--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.internal.Config)
local DataStoreAdapter = require(script.Parent.adapters.DataStoreAdapter)
local Result = require(script.Parent.internal.Result)
local Store = require(script.Parent.Store)
local Types = require(script.Parent.Types)

local OmniStore = {}
OmniStore.__index = OmniStore

export type OmniStore = typeof(setmetatable(
	{} :: {
		Namespace: string,
		_config: Types.OmniStoreConfig,
		_stores: { [string]: Store.Store },
		_owner: string,
		_session: Types.SessionIdentity,
		_closed: boolean,
	},
	OmniStore
))

function OmniStore.new(config: Types.OmniStoreConfig?): OmniStore
	local value = config or {}
	local namespace = value.namespace or "OmniStore"
	assert(
		namespace ~= "" and not string.find(namespace, "[%c]"),
		"namespace cannot be empty or contain control characters"
	)
	assert(value.closeTimeout == nil or value.closeTimeout >= 0, "closeTimeout cannot be negative")
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	local sessionId = HttpService:GenerateGUID(false)
	local owner = `{jobId}:{sessionId}`
	local session: Types.SessionIdentity = {
		owner = owner,
		sessionId = sessionId,
		jobId = jobId,
		placeId = game.PlaceId,
		universeId = game.GameId,
	}
	local self = setmetatable({
		Namespace = namespace,
		_config = value,
		_stores = {},
		_owner = owner,
		_session = session,
		_closed = false,
	}, OmniStore)

	if value.autoBindToClose ~= false and RunService:IsServer() then
		game:BindToClose(function()
			self:CloseAsync()
		end)
	end
	return self
end

function OmniStore:GetStore(name: string, storeConfig: Types.StoreConfig?): Store.Store
	assert(not self._closed, "OmniStore is closed")
	assert(
		name ~= "" and #name <= 50 and not string.find(name, "[%c]"),
		"store name must be 1-50 bytes and contain no control characters"
	)
	local existing = self._stores[name]
	if existing then
		assert(
			storeConfig == nil,
			"store is already configured; omit config on later GetStore calls"
		)
		return existing
	end

	local combined = Config.store(self._config.defaultStoreConfig, storeConfig)
	if not combined.adapter then
		local dataStoreName = `{self.Namespace}_{name}`
		assert(
			#dataStoreName <= 50,
			"namespace and store name exceed Roblox's 50-byte DataStore name limit"
		)
		combined.adapter = DataStoreAdapter.new(dataStoreName)
	end
	local valid, message = Config.validateStore(combined)
	assert(valid, message)
	local store = Store.new(name, combined, self._config.keyPrefix or "", self._session)
	self._stores[name] = store
	return store
end

function OmniStore:GetSessionInfo(): Types.SessionIdentity
	return table.clone(self._session)
end

function OmniStore:CloseAsync(timeout: number?): Types.Result<nil>
	if self._closed then
		return Result.ok(nil)
	end
	local deadline = os.clock() + math.max(0, timeout or self._config.closeTimeout or 25)
	local firstFailure: Types.Failure? = nil
	for _, store in self._stores do
		local result = store:CloseAsync(math.max(0, deadline - os.clock()))
		if not result.ok and not firstFailure then
			firstFailure = result
		end
	end
	if firstFailure then
		return firstFailure
	end
	self._closed = true
	return Result.ok(nil)
end

return OmniStore
