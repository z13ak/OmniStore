--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Package = ReplicatedStorage.Packages.OmniStore
	local ClientMirror = require(Package.replication.ClientMirror)
	local Protocol = require(Package.replication.ReplicationProtocol)
	local ServerReplicator = require(Package.replication.ServerReplicator)
	local Signal = require(Package.internal.Signal)

	describe("replication protocol", function()
		it("uses segment boundaries for allowlists", function()
			expect(Protocol.isAllowed("Stats.Coins", { "Stats" })).to.equal(true)
			expect(Protocol.isAllowed("Statistic.Coins", { "Stats" })).to.equal(false)
			expect(Protocol.isAllowed({ "Inventory", 1 }, { "Inventory" })).to.equal(true)
		end)

		it("rejects root, invalid numeric, and oversized paths", function()
			expect(select(1, Protocol.validatePath("", 4))).to.equal(false)
			expect(select(1, Protocol.validatePath({ "Items", 0 }, 4))).to.equal(false)
			expect(select(1, Protocol.validatePath("A.B.C", 2))).to.equal(false)
		end)

		it("detects duplicate and ancestor path overlap", function()
			expect(Protocol.pathsOverlap("Stats", "Stats.Coins")).to.equal(true)
			expect(Protocol.pathsOverlap("Stats.Coins", { "Stats", "Coins" })).to.equal(true)
			expect(Protocol.pathsOverlap("Stats", "Inventory")).to.equal(false)
		end)

		it("copies assigned values", function()
			local source = { Count = 1 }
			local root = {}
			expect(Protocol.assign(root, "Nested.Value", source)).to.equal(true)
			source.Count = 2
			expect(root.Nested.Value.Count).to.equal(1)
		end)

		it("bounds payload size, depth, cycles, and unsupported types", function()
			local bytes = Protocol.measure({ Position = Vector3.new(1, 2, 3) }, 8, 1_000)
			expect(type(bytes)).to.equal("number")
			local large = Protocol.measure({ Text = string.rep("x", 100) }, 8, 20)
			expect((large :: number) > 20).to.equal(true)

			local cyclic: any = {}
			cyclic.self = cyclic
			expect(Protocol.measure(cyclic, 8, 1_000)).to.equal(nil)
			expect(Protocol.measure(Instance.new("Folder"), 8, 1_000)).to.equal(nil)
		end)
	end)

	describe("server replication boundaries", function()
		local function makeRecord(data: { [string]: unknown })
			return {
				Changed = Signal.new(),
				LifecycleChanged = Signal.new(),
				Get = function(_self, path)
					return { ok = true, value = data[path] }
				end,
			}
		end

		it("returns structured registration failures for overlapping paths", function()
			local parent = Instance.new("Folder")
			local replicator = ServerReplicator.new({ parent = parent })
			local result = replicator:Register(
				{} :: any,
				"Profile",
				makeRecord({ Stats = {}, ["Stats.Coins"] = 2 }) :: any,
				{ "Stats", "Stats.Coins" }
			)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("InvalidConfig")
			replicator:Destroy()
			parent:Destroy()
		end)

		it("rejects an oversized initial snapshot", function()
			local parent = Instance.new("Folder")
			local replicator = ServerReplicator.new({ parent = parent, maxSnapshotBytes = 32 })
			local result = replicator:Register(
				{} :: any,
				"Profile",
				makeRecord({ Blob = string.rep("x", 100) }) :: any,
				{ "Blob" }
			)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("InvalidData")
			replicator:Destroy()
			parent:Destroy()
		end)

		it("rate limits snapshot requests without exposing channel data", function()
			local parent = Instance.new("Folder")
			local now = 0
			local replicator = ServerReplicator.new({
				parent = parent,
				maxSnapshotRequests = 2,
				requestWindowSeconds = 10,
				clock = function()
					return now
				end,
			})
			local player = {} :: any
			expect(
				replicator:Register(
					player,
					"Profile",
					makeRecord({ Coins = 5 }) :: any,
					{ "Coins" }
				).ok
			).to.equal(true)
			local function invoke(targetPlayer, channel)
				return (replicator :: any):_handleSnapshot(targetPlayer, channel)
			end
			expect(invoke(player, "Profile").ok).to.equal(true)
			expect(invoke(player, "Missing").code).to.equal("Unavailable")
			expect(invoke(player, "Profile").code).to.equal("RateLimited")
			now = 11
			expect(invoke(player, "Profile").ok).to.equal(true)
			replicator:Destroy()
			parent:Destroy()
		end)

		it("cleans registrations when their record closes", function()
			local parent = Instance.new("Folder")
			local replicator = ServerReplicator.new({ parent = parent })
			local player = {} :: any
			local record = makeRecord({ Coins = 5 })
			expect(replicator:Register(player, "Profile", record :: any, { "Coins" }).ok).to.equal(
				true
			)
			record.LifecycleChanged:Fire("Closed", "Active")
			task.wait()
			expect((replicator :: any)._registrations[player]).to.equal(nil)
			replicator:Destroy()
			parent:Destroy()
		end)
	end)

	describe("client gap recovery", function()
		it("replaces stale state from a snapshot after a sequence gap", function()
			local mirror = setmetatable({
				Channel = "Profile",
				Changed = Signal.new(),
				Resynced = Signal.new(),
				StatusChanged = Signal.new(),
				_data = { Coins = 1 },
				_sequence = 0,
				_pending = {},
				_status = "Synchronized",
				_ready = true,
				_resyncing = false,
				_resyncScheduled = false,
				_lastResyncAt = -math.huge,
				_snapshotRemote = {
					InvokeServer = function()
						return { ok = true, data = { Coins = 3 }, sequence = 2 }
					end,
				},
				_config = {
					maxSnapshotBytes = 1_000,
					maxChangeBytes = 1_000,
					maxPayloadDepth = 8,
					maxPathSegments = 8,
					maxPendingChanges = 8,
					resyncCooldown = 0.01,
				},
			}, ClientMirror) :: any

			mirror:_receive("Profile", "Coins", 3, 2, "change")
			task.wait()
			expect(mirror:Get("Coins").value).to.equal(3)
			expect(mirror:GetRevision()).to.equal(2)
			expect(mirror:IsSynchronized()).to.equal(true)
		end)
	end)
end
