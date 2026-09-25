--!strict

local OmniStore = require(script.OmniStore)
local Record = require(script.Record)
local ClientMirror = require(script.replication.ClientMirror)
local ServerReplicator = require(script.replication.ServerReplicator)
local Store = require(script.Store)
local TransactionDraft = require(script.internal.TransactionDraft)
local Types = require(script.Types)

export type OmniStore = OmniStore.OmniStore
export type Store = Store.Store
export type Record = Record.Record
export type Path = Types.Path
export type Result<T> = Types.Result<T>
export type OmniError = Types.OmniError
export type ErrorCategory = Types.ErrorCategory
export type DiagnosticEvent = Types.DiagnosticEvent
export type MetricEvent = Types.MetricEvent
export type OmniStoreConfig = Types.OmniStoreConfig
export type StoreConfig = Types.StoreConfig
export type LoadOptions = Types.LoadOptions
export type LoadMode = Types.LoadMode
export type StaleLeasePolicy = Types.StaleLeasePolicy
export type SessionIdentity = Types.SessionIdentity
export type Schema = Types.Schema
export type Codec = Types.Codec
export type CodecRegistry = Types.CodecRegistry
export type ModelDefinition = Types.ModelDefinition
export type TransactionDraft = TransactionDraft.TransactionDraft
export type ReplicationClient = ClientMirror.ClientMirror
export type ReplicationClientConfig = ClientMirror.Config
export type ReplicationStatus = ClientMirror.Status
export type ReplicationServer = ServerReplicator.ServerReplicator
export type ReplicationServerConfig = ServerReplicator.Config

return {
	new = OmniStore.new,
	Schema = require(script.Schema),
	CodecRegistry = require(script.CodecRegistry),
	Model = require(script.Model),
	Codecs = {
		Roblox = require(script.codecs.Roblox),
	},
	Adapters = {
		DataStore = require(script.adapters.DataStoreAdapter),
		Memory = require(script.adapters.MemoryAdapter),
	},
	Replication = {
		Server = ServerReplicator,
		Client = ClientMirror,
	},
}
