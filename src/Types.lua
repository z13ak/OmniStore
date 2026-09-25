--!strict

export type Path = string | { string | number }
export type ErrorCode =
	"AlreadyLoaded"
	| "Cancelled"
	| "Closed"
	| "Conflict"
	| "InvalidConfig"
	| "InvalidData"
	| "InvalidKey"
	| "LeaseLost"
	| "Locked"
	| "MigrationFailed"
	| "NotLoaded"
	| "NotFound"
	| "PersistenceFailed"
	| "ReadOnly"
	| "Timeout"
	| "TransactionFailed"
	| "ValidationFailed"

export type ErrorCategory = "Transient" | "Throttled" | "Permanent" | "Unknown"

export type OmniError = {
	code: ErrorCode,
	message: string,
	retryable: boolean,
	category: ErrorCategory?,
	cause: unknown?,
	context: { [string]: unknown }?,
}

export type Success<T> = { ok: true, value: T }
export type Failure = { ok: false, error: OmniError }
export type Result<T> = Success<T> | Failure

export type StoredLease = {
	owner: string,
	expiresAt: number,
	sessionId: string?,
	jobId: string?,
	placeId: number?,
	universeId: number?,
	acquiredAt: number?,
	renewedAt: number?,
}

export type SessionIdentity = {
	owner: string,
	sessionId: string,
	jobId: string,
	placeId: number,
	universeId: number,
}

export type StoredEnvelope = {
	data: unknown,
	metadata: { [string]: unknown },
	typeId: string?,
	schemaVersion: number,
	revision: number,
	updatedAt: number,
	lease: StoredLease?,
}

export type Adapter = {
	Read: (self: Adapter, key: string) -> Result<StoredEnvelope?>,
	Update: (
		self: Adapter,
		key: string,
		transform: (StoredEnvelope?) -> StoredEnvelope?
	) -> Result<StoredEnvelope?>,
	Remove: (self: Adapter, key: string) -> Result<nil>,
	GetBudget: (self: Adapter, requestType: string) -> number?,
}

export type Schema = {
	Validate: (self: Schema, value: unknown, path: string?) -> (boolean, string?),
}

export type Migration = {
	from: number,
	to: number,
	migrate: (data: unknown) -> unknown,
	schema: Schema?,
}

export type UnknownTypePolicy = "Reject" | "Preserve"

export type Codec = {
	typeId: string,
	isType: (value: unknown) -> boolean,
	encode: (value: unknown) -> unknown,
	decode: (payload: unknown) -> unknown,
}

export type CodecRegistry = {
	Encode: (self: CodecRegistry, value: unknown) -> Result<unknown>,
	Decode: (self: CodecRegistry, value: unknown) -> Result<unknown>,
}

export type ModelDefinition = {
	typeId: string,
	version: number,
	schema: Schema,
	template: unknown?,
	migrations: { Migration },
	codecs: CodecRegistry?,
	allowLegacy: boolean,
}

export type ModelOptions = {
	typeId: string,
	version: number,
	schema: Schema,
	template: unknown?,
	migrations: { Migration }?,
	codecs: CodecRegistry?,
	allowLegacy: boolean?,
}

export type RetryConfig = {
	maxAttempts: number,
	baseDelay: number,
	maxDelay: number,
	jitter: number,
}

export type DiagnosticLevel = "debug" | "info" | "warn" | "error"

export type DiagnosticEvent = {
	level: DiagnosticLevel,
	event: string,
	message: string,
	timestamp: number,
	context: { [string]: unknown }?,
}

export type MetricEvent = {
	name: string,
	value: number,
	tags: { [string]: string }?,
}

export type Logger = (event: DiagnosticEvent) -> ()
export type Metrics = (event: MetricEvent) -> ()

export type RetryOptions = {
	maxAttempts: number?,
	baseDelay: number?,
	maxDelay: number?,
	jitter: number?,
}

export type LeaseConfig = {
	enabled: boolean,
	duration: number,
	renewInterval: number,
	acquireTimeout: number,
	stealAfter: number,
	staleLeasePolicy: StaleLeasePolicy,
}

export type LoadMode = "Exclusive" | "ReadOnly"
export type StaleLeasePolicy = "Recover" | "Reject"

export type LoadOptions = {
	timeout: number?,
	mode: LoadMode?,
	staleLeasePolicy: StaleLeasePolicy?,
}

export type LeaseOptions = {
	enabled: boolean?,
	duration: number?,
	renewInterval: number?,
	acquireTimeout: number?,
	stealAfter: number?,
	staleLeasePolicy: StaleLeasePolicy?,
}

export type SerializationOptions = {
	maxDepth: number?,
	maxPayloadBytes: number?,
}

export type StoreConfig = {
	adapter: Adapter?,
	model: ModelDefinition?,
	schema: Schema?,
	codecs: CodecRegistry?,
	template: unknown?,
	validate: ((data: unknown) -> (boolean, string?))?,
	reconcile: boolean?,
	schemaVersion: number?,
	migrations: { Migration }?,
	autosaveInterval: number?,
	autosaveJitter: number?,
	maxConcurrentBackgroundTasks: number?,
	backgroundTick: number?,
	requestBudgetTimeout: number?,
	closeTimeout: number?,
	maxSerializationDepth: number?,
	maxPayloadBytes: number?,
	retry: RetryOptions?,
	lease: LeaseOptions?,
	metadata: { [string]: unknown }?,
	clock: (() -> number)?,
	monotonicClock: (() -> number)?,
	wait: ((seconds: number) -> ())?,
	random: Random?,
	logger: Logger?,
	metrics: Metrics?,
}

export type OmniStoreConfig = {
	namespace: string?,
	keyPrefix: string?,
	autoBindToClose: boolean?,
	closeTimeout: number?,
	defaultStoreConfig: StoreConfig?,
}

return {}
