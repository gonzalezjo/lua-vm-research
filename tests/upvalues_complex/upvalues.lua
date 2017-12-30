local foo
do
	local bar = 5
	local unused = 'Should not display'
	function foo()
		return function()
			print(bar)
		end
	end
end

print(unused)
foo()()