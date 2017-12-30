local print, string_concat = print, require('debug.concat')

local logs = {}
local loggers = {}
local LOG_FORMATTER = '[%s] %s | Severity: %d'

local logger_mt = {
	__newindex = function()
		error('This table is locked.')
	end,
	__metatable = 'Locked'
}

local log_mt = {
	__tostring = function(self)
		return(LOG_FORMATTER:format(
			tostring(self.name),
			tostring(self.message),
			tostring(self.severity))
		)
	end,
	__newindex = function()
		error('This table is locked.')
	end,
	__metatable = 'Locked',
}

function logs.new(name)
	assert(not logs[name], string_concat('Logger already exists for name ', name))

	local self = {}
	local printOnSeverityThreshold = math.huge
	local defaultSeverity = 1

	local logPool = {}
	logs[name] = logPool

	function self:getLogs()
		return logPool
	end

	function self:printLogs()
		for _, log in ipairs(logPool) do
			print(log)
		end
	end

	function self:setPrintingSeverity(severity)
		printOnSeverityThreshold = severity
	end

	function self:put(message, severity)
		severity = severity or defaultSeverity

		local log = setmetatable({
			name = name,
			message = message,
			severity = severity
		}, log_mt)

		if severity >= printOnSeverityThreshold then
			print(log)
		end

		logPool[#logPool + 1] = log
	end

	setmetatable(self, logger_mt)
	loggers[name] = self

	return self
end

function logs.getAll()
	return loggers
end

return logs