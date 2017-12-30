local foo

do
	local bar = 5
	function foo()
		print(bar)
	end
end

foo()