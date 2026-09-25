--!strict

local Schema = require(script.Parent.Schema)
local Types = require(script.Parent.Types)

local Model = {}

local function validTypeId(typeId: string): boolean
	return #typeId > 0 and #typeId <= 100 and string.match(typeId, "^[%w%._:/%-]+$") ~= nil
end

function Model.define(options: Types.ModelOptions): Types.ModelDefinition
	assert(type(options) == "table", "model options must be a table")
	assert(
		type(options.typeId) == "string" and validTypeId(options.typeId),
		"model typeId is invalid"
	)
	assert(
		type(options.version) == "number" and options.version >= 1 and options.version % 1 == 0,
		"model version must be a positive integer"
	)
	assert(Schema.is(options.schema), "model schema must be an OmniStore schema")
	return {
		typeId = options.typeId,
		version = options.version,
		schema = options.schema,
		template = options.template,
		migrations = options.migrations or {},
		codecs = options.codecs,
		allowLegacy = options.allowLegacy ~= false,
	}
end

return Model
