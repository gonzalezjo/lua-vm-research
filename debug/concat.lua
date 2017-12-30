local table_concat = table.concat

string.concat = string.concat or function(...)
	return table_concat {...}
end

return string.concat