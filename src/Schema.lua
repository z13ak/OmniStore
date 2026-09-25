--!strict

export type Schema = {
	Validate: (self: Schema, value: unknown, path: string?) -> (boolean, string?),
	_kind: string,
	_validate: (value: unknown, path: string) -> (boolean, string?),
}

local Schema = {}

local function make(kind: string, validator: (unknown, string) -> (boolean, string?)): Schema
	local node = {
		_kind = kind,
		_validate = validator,
	} :: any
	function node:Validate(value: unknown, path: string?): (boolean, string?)
		return self._validate(value, path or "$")
	end
	return node :: Schema
end

local function failure(path: string, expected: string, value: unknown): (boolean, string)
	return false, `{path} expected {expected}, got {typeof(value)}`
end

local function assertSchema(value: unknown, argument: string): Schema
	assert(Schema.is(value), `{argument} must be an OmniStore schema`)
	return value :: Schema
end

function Schema.is(value: unknown): boolean
	return type(value) == "table"
		and type((value :: any).Validate) == "function"
		and type((value :: any)._validate) == "function"
end

function Schema.any(): Schema
	return make("any", function()
		return true, nil
	end)
end

function Schema.string(options: { minLength: number?, maxLength: number? }?): Schema
	local settings = options or {}
	return make("string", function(value, path)
		if type(value) ~= "string" then
			return failure(path, "string", value)
		end
		if settings.minLength and #value < settings.minLength then
			return false, `{path} must contain at least {settings.minLength} bytes`
		end
		if settings.maxLength and #value > settings.maxLength then
			return false, `{path} must contain at most {settings.maxLength} bytes`
		end
		return true, nil
	end)
end

function Schema.number(options: { min: number?, max: number?, integer: boolean? }?): Schema
	local settings = options or {}
	return make("number", function(value, path)
		if type(value) ~= "number" then
			return failure(path, "number", value)
		end
		if settings.integer and value % 1 ~= 0 then
			return false, `{path} must be an integer`
		end
		if settings.min and value < settings.min then
			return false, `{path} must be at least {settings.min}`
		end
		if settings.max and value > settings.max then
			return false, `{path} must be at most {settings.max}`
		end
		return true, nil
	end)
end

function Schema.boolean(): Schema
	return make("boolean", function(value, path)
		if type(value) ~= "boolean" then
			return failure(path, "boolean", value)
		end
		return true, nil
	end)
end

function Schema.literal(expected: unknown): Schema
	return make("literal", function(value, path)
		if value ~= expected then
			return false, `{path} must equal {tostring(expected)}`
		end
		return true, nil
	end)
end

function Schema.optional(inner: Schema): Schema
	local child = assertSchema(inner, "inner")
	return make("optional", function(value, path)
		if value == nil then
			return true, nil
		end
		return child:Validate(value, path)
	end)
end

function Schema.array(inner: Schema, options: { minLength: number?, maxLength: number? }?): Schema
	local child = assertSchema(inner, "inner")
	local settings = options or {}
	return make("array", function(value, path)
		if type(value) ~= "table" then
			return failure(path, "array", value)
		end
		local length = #value
		local count = 0
		for key in value do
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
				return false, `{path} must be a contiguous array`
			end
			count += 1
		end
		if count ~= length then
			return false, `{path} must be a contiguous array`
		end
		if settings.minLength and length < settings.minLength then
			return false, `{path} must contain at least {settings.minLength} items`
		end
		if settings.maxLength and length > settings.maxLength then
			return false, `{path} must contain at most {settings.maxLength} items`
		end
		for index, item in value do
			local ok, message = child:Validate(item, `{path}[{index}]`)
			if not ok then
				return false, message
			end
		end
		return true, nil
	end)
end

function Schema.map(inner: Schema): Schema
	local child = assertSchema(inner, "inner")
	return make("map", function(value, path)
		if type(value) ~= "table" then
			return failure(path, "string-keyed map", value)
		end
		for key, item in value do
			if type(key) ~= "string" then
				return false, `{path} map keys must be strings`
			end
			local ok, message = child:Validate(item, `{path}.{key}`)
			if not ok then
				return false, message
			end
		end
		return true, nil
	end)
end

function Schema.object(fields: { [string]: Schema }, options: { allowUnknown: boolean? }?): Schema
	local checked: { [string]: Schema } = {}
	for key, child in fields do
		assert(type(key) == "string", "object field names must be strings")
		checked[key] = assertSchema(child, `field {key}`)
	end
	local allowUnknown = options ~= nil and options.allowUnknown == true
	return make("object", function(value, path)
		if type(value) ~= "table" then
			return failure(path, "object", value)
		end
		for key in value do
			if type(key) ~= "string" then
				return false, `{path} object keys must be strings`
			end
			if checked[key] == nil and not allowUnknown then
				return false, `{path}.{key} is not declared in the schema`
			end
		end
		for key, child in checked do
			local ok, message = child:Validate((value :: any)[key], `{path}.{key}`)
			if not ok then
				return false, message
			end
		end
		return true, nil
	end)
end

function Schema.union(...: Schema): Schema
	local variants = { ... }
	assert(#variants > 0, "union requires at least one schema")
	for index, variant in variants do
		variants[index] = assertSchema(variant, `variant {index}`)
	end
	return make("union", function(value, path)
		local messages = {}
		for _, variant in variants do
			local ok, message = variant:Validate(value, path)
			if ok then
				return true, nil
			end
			table.insert(messages, message or "validation failed")
		end
		return false, `{path} did not match any union variant: {table.concat(messages, "; ")}`
	end)
end

function Schema.custom(validator: (value: unknown) -> (boolean, string?), name: string?): Schema
	assert(type(validator) == "function", "validator must be a function")
	return make(name or "custom", function(value, path)
		local ok, valid, message = pcall(validator, value)
		if not ok then
			return false, `{path} custom validator threw: {tostring(valid)}`
		end
		if not valid then
			return false, message or `{path} failed custom validation`
		end
		return true, nil
	end)
end

return Schema
