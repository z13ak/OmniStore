--!strict

local DeepCopy = require(script.Parent.DeepCopy)

local function reconcile(target: unknown, template: unknown): unknown
	if type(template) ~= "table" then
		return target
	end
	if type(target) ~= "table" then
		return DeepCopy(template)
	end

	local targetTable = target :: table
	local targetAny = targetTable :: any
	for key, defaultValue in template :: table do
		local current = targetAny[key]
		if current == nil then
			targetAny[key] = DeepCopy(defaultValue)
		elseif type(current) == "table" and type(defaultValue) == "table" then
			reconcile(current, defaultValue)
		end
	end
	return targetTable
end

return reconcile
