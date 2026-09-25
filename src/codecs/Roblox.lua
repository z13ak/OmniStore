--!strict

local Types = require(script.Parent.Parent.Types)

local RobloxCodecs = {}

local CODECS: { Types.Codec } = {
	{
		typeId = "roblox.Vector2/v1",
		isType = function(value)
			return typeof(value) == "Vector2"
		end,
		encode = function(value)
			local vector = value :: Vector2
			return { vector.X, vector.Y }
		end,
		decode = function(payload)
			local values = payload :: { number }
			return Vector2.new(values[1], values[2])
		end,
	},
	{
		typeId = "roblox.Vector3/v1",
		isType = function(value)
			return typeof(value) == "Vector3"
		end,
		encode = function(value)
			local vector = value :: Vector3
			return { vector.X, vector.Y, vector.Z }
		end,
		decode = function(payload)
			local values = payload :: { number }
			return Vector3.new(values[1], values[2], values[3])
		end,
	},
	{
		typeId = "roblox.Color3/v1",
		isType = function(value)
			return typeof(value) == "Color3"
		end,
		encode = function(value)
			local color = value :: Color3
			return { color.R, color.G, color.B }
		end,
		decode = function(payload)
			local values = payload :: { number }
			return Color3.new(values[1], values[2], values[3])
		end,
	},
	{
		typeId = "roblox.CFrame/v1",
		isType = function(value)
			return typeof(value) == "CFrame"
		end,
		encode = function(value)
			return { (value :: CFrame):GetComponents() }
		end,
		decode = function(payload)
			return CFrame.new(table.unpack(payload :: { number }))
		end,
	},
	{
		typeId = "roblox.UDim/v1",
		isType = function(value)
			return typeof(value) == "UDim"
		end,
		encode = function(value)
			local dimension = value :: UDim
			return { dimension.Scale, dimension.Offset }
		end,
		decode = function(payload)
			local values = payload :: { number }
			return UDim.new(values[1], values[2])
		end,
	},
	{
		typeId = "roblox.UDim2/v1",
		isType = function(value)
			return typeof(value) == "UDim2"
		end,
		encode = function(value)
			local dimension = value :: UDim2
			return {
				dimension.X.Scale,
				dimension.X.Offset,
				dimension.Y.Scale,
				dimension.Y.Offset,
			}
		end,
		decode = function(payload)
			local values = payload :: { number }
			return UDim2.new(values[1], values[2], values[3], values[4])
		end,
	},
}

function RobloxCodecs.registerAll(registry: any): any
	for _, codec in CODECS do
		registry:Register(codec)
	end
	return registry
end

function RobloxCodecs.list(): { Types.Codec }
	return table.clone(CODECS)
end

return RobloxCodecs
