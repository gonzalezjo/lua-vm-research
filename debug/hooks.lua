local environment = _G.getfenv and _G or getfenv(0)
local string_concat = require('debug.concat')
local print = print

local functions = {}

-- Calls original function
local function setProxyHook(name, proxy)
	assert(not functions[name], string_concat('Hook already exists for: ', name))

	local toProxy = environment[name]
	functions[name] = toProxy

	environment[name] = function(...)
		proxy(...)
		return toProxy(...)
	end
end

local function removeHook(name)
	assert(hooks[name], string_concat('No hook exists for: ', name))
	environment[name] = hooks[name]
	hooks[name] = nil
end


return {
	setProxyHook = setProxyHook,
	removeHook = removeHook,
}