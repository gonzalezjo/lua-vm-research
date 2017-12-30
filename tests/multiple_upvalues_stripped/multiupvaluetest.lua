local a, b, c
function d()
	return a, b, c, function()
		return a, b, c, function()
			return a, b, c, function()
				return a, b, c
			end
		end
	end
end