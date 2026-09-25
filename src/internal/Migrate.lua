--!strict

local DeepCopy = require(script.Parent.DeepCopy)
local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Types)

local Migrate = {}

function Migrate.run(
	data: unknown,
	fromVersion: number,
	targetVersion: number,
	migrations: { Types.Migration },
	validateStep: ((data: unknown, migration: Types.Migration) -> Types.Failure?)?
): Types.Result<unknown>
	local currentData = DeepCopy(data)
	local currentVersion = fromVersion
	while currentVersion < targetVersion do
		local selected: Types.Migration? = nil
		for _, migration in migrations do
			if migration.from == currentVersion then
				selected = migration
				break
			end
		end
		if not selected then
			return Result.err(
				"MigrationFailed",
				`missing migration from schema version {currentVersion}`,
				false
			)
		end
		if selected.to <= currentVersion or selected.to > targetVersion then
			return Result.err("MigrationFailed", "migration has an invalid target version", false)
		end
		local ok, migrated = pcall(selected.migrate, currentData)
		if not ok then
			return Result.err("MigrationFailed", "migration callback failed", false, migrated)
		end
		if selected.schema then
			local schemaOk, valid, message =
				pcall(selected.schema.Validate, selected.schema, migrated, "$")
			if not schemaOk or not valid then
				return Result.err(
					"MigrationFailed",
					message or "migration step schema validation failed",
					false,
					if schemaOk then nil else valid,
					{ from = selected.from, to = selected.to }
				)
			end
		end
		if validateStep then
			local stepFailure = validateStep(migrated, selected)
			if stepFailure then
				return Result.err(
					"MigrationFailed",
					"migration step produced invalid data",
					false,
					stepFailure.error,
					{ from = selected.from, to = selected.to }
				)
			end
		end
		currentData = migrated
		currentVersion = selected.to
	end
	return Result.ok(currentData)
end

return Migrate
