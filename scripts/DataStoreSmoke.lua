--!strict
-- Manual Studio-only smoke gate. Never loaded by the TestEZ runner or the library.

local Smoke = {}

function Smoke.run(OmniStore: any, expectedUniverseId: number)
	local RunService = game:GetService("RunService")
	assert(RunService:IsStudio() and RunService:IsServer(), "run smoke checks on a Studio server")
	assert(
		expectedUniverseId > 0 and game.GameId == expectedUniverseId,
		"test universe does not match"
	)
	local HttpService = game:GetService("HttpService")
	local namespace = "OmniSmoke_" .. HttpService:GenerateGUID(false):gsub("%-", ""):sub(1, 20)
	local checks = {}
	local managers = {}
	local keys = { "profile", "stale", "migration", "shutdown-1", "shutdown-2", "shutdown-3" }
	local codecs = OmniStore.CodecRegistry.new()
	OmniStore.Codecs.Roblox.registerAll(codecs)
	local model = OmniStore.Model.define({
		typeId = "smoke.Profile/v1",
		version = 2,
		template = { Coins = 0, Position = Vector3.zero },
		schema = OmniStore.Schema.object({
			Coins = OmniStore.Schema.number(),
			Position = OmniStore.Schema.custom(function(value)
				return typeof(value) == "Vector3"
			end),
		}),
		codecs = codecs,
		migrations = {
			{
				from = 1,
				to = 2,
				migrate = function(data)
					data.Coins = data.Money
					data.Money = nil
					return data
				end,
			},
		},
	})
	local adapter = OmniStore.Adapters.DataStore.new(namespace .. "_Profiles")
	local function makeStore()
		local manager = OmniStore.new({ namespace = namespace, autoBindToClose = false })
		table.insert(managers, manager)
		local store = manager:GetStore("Profiles", {
			adapter = adapter,
			model = model,
			autosaveInterval = 0,
			lease = { duration = 3600, renewInterval = 1800, acquireTimeout = 0 },
		})
		return store, manager
	end
	local function value(result)
		assert(
			result.ok,
			if result.error
				then result.error.code .. ": " .. result.error.message
				else "operation failed"
		)
		return result.value
	end
	local function failure(result, code)
		assert(not result.ok and result.error.code == code, "expected " .. code)
	end
	local first, manager = makeStore()
	local second = makeStore()
	local reader = makeStore()
	local ok, cause = xpcall(function()
		local record = value(first:LoadAsync("profile", 15))
		assert(value(record:Get("Coins")) == 0, "new record did not use its template")
		value(record:Set("Coins", 12))
		local position = Vector3.new(1, 2, 3)
		value(record:Set("Position", position))
		value(record:SaveAsync(15))
		table.insert(checks, "create/save")
		failure(second:LoadAsync("profile", 15), "Locked")
		failure(second:DeleteAsync("profile", 15), "Locked")
		table.insert(checks, "live-lock/delete rejection")
		local snapshot = value(reader:LoadAsync("profile", { mode = "ReadOnly", timeout = 15 }))
		assert(value(snapshot:Get("Coins")) == 12, "read-only coins differ")
		assert(value(snapshot:Get("Position")) == position, "codec round trip differs")
		value(snapshot:CloseAsync(15))
		table.insert(checks, "read-only/codec round trip")
		value(record:CloseAsync(15))
		local reloaded = value(second:LoadAsync("profile", 15))
		assert(value(reloaded:Get("Coins")) == 12, "reloaded coins differ")
		value(reloaded:CloseAsync(15))
		value(second:DeleteAsync("profile", 15))
		failure(reader:LoadAsync("profile", { mode = "ReadOnly", timeout = 15 }), "NotFound")
		local recreated = value(first:LoadAsync("profile", 15))
		assert(value(recreated:Get("Coins")) == 0, "recreated record retained deleted data")
		value(recreated:CloseAsync(15))
		table.insert(checks, "close/reload/tombstone/recreate")

		local old = value(first:LoadAsync("stale", 15))
		-- Alter only this run's disposable key to exercise expiry without a wall-clock sleep.
		value(adapter:Update("stale", function(current)
			assert(current and current.lease, "missing smoke lease")
			current.lease.expiresAt = os.time() - 1
			return current
		end))
		local recovered = value(second:LoadAsync("stale", 15))
		failure(old:SaveAsync(15), "LeaseLost")
		failure(old:CloseAsync(15), "LeaseLost")
		value(recovered:CloseAsync(15))
		table.insert(checks, "expired lease recovery/old-owner fencing")

		value(adapter:Update("migration", function(current)
			assert(current == nil, "smoke namespace collision")
			return {
				data = { Money = 8, Position = value(codecs:Encode(position)) },
				metadata = {},
				typeId = model.typeId,
				schemaVersion = 1,
				revision = 1,
				updatedAt = os.time(),
			}
		end))
		local migrated = value(first:LoadAsync("migration", 15))
		assert(value(migrated:Get("Coins")) == 8, "model migration differs")
		assert(value(migrated:Get("Position")) == position, "migrated codec differs")
		value(migrated:CloseAsync(15))
		table.insert(checks, "model migration")
		for index = 1, 3 do
			local dirty = value(first:LoadAsync("shutdown-" .. index, 15))
			value(dirty:Set("Coins", index))
		end
		value(manager:CloseAsync(25))
		for index = 1, 3 do
			local saved =
				value(reader:LoadAsync("shutdown-" .. index, { mode = "ReadOnly", timeout = 15 }))
			assert(value(saved:Get("Coins")) == index, "shutdown did not persist a record")
			value(saved:CloseAsync(15))
		end
		table.insert(checks, "manager shutdown persistence")
		for _, key in keys do
			value(second:DeleteAsync(key, 15))
		end
		table.insert(checks, "exact-key logical cleanup")
	end, debug.traceback)
	local closeErrors = {}
	for _, database in managers do
		local closeOk, result = pcall(database.CloseAsync, database, 15)
		if not closeOk or not result.ok then
			table.insert(closeErrors, tostring(result))
		end
	end
	return {
		ok = ok and #closeErrors == 0,
		namespace = namespace,
		universeId = game.GameId,
		checks = checks,
		error = if ok then nil else tostring(cause),
		closeErrors = closeErrors,
	}
end

return Smoke
