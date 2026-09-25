--!strict

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type InternalConnection = Connection & { _callback: (...any) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_connections = {} :: { InternalConnection },
		_destroyed = false,
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(callback: (...any) -> ()): Connection
	assert(not self._destroyed, "cannot connect to a destroyed signal")
	local signal = self
	local connection: InternalConnection
	connection = {
		Connected = true,
		_callback = callback,
		Disconnect = function(selfConnection: InternalConnection)
			if not selfConnection.Connected then
				return
			end
			selfConnection.Connected = false
			local index = table.find(signal._connections, selfConnection)
			if index then
				table.remove(signal._connections, index)
			end
		end,
	}
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(callback: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	if self._destroyed then
		return
	end
	local snapshot = table.clone(self._connections)
	for _, connection in snapshot do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in self._connections do
		connection.Connected = false
	end
	table.clear(self._connections)
end

return Signal
