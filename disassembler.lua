do -- could be in an if, doesnt really matter
	os.execute('cls')
	os.execute('clear')
	-- io.write("\027[H\027[2J")
end

-- print('Lua runtime: ', _VERSION)
-- stick to one naming convention
-- maybe hungarian? ctrl-f maybe hungarian notation will be useful here

-- luac.out is print 'hello world', compiled on surface

-- local encoding = {
-- 	uint32_t = function(string, index)
-- 		return s:byte(index and 0 )
-- 	end
-- }

-- getmetatable(' ').__index = function(self, index)
-- 	return type(index) == 'number' and string.sub(self, index, index) or string[index] or encoding[index]
-- end

local ffi = require('ffi')
local structs = require('structs')
local reflect = require('reflect')
local consts = require('consts')
local bit = require('bit')
local instructions = require('instructions')
local hex_dump = require('hexdump')
local decode, maketypedefs, disassemble

string.rebase = function(message, position)
	return message:sub(position + 1)
end

function decode(dump)
	-- print('Decoding a dump of size ' .. #dump)
	local header = ffi.new(structs.DumpHeader)
	local header_t = reflect.typeof(header)

	ffi.copy(header, dump, consts.DUMP_HEADER_SIZE)

	-- for member in header_t:members() do
	-- 	print(member.name, header[member.name])
	-- end

	makecdefs(header)

	return disassemble(dump:rebase(12))
end

function makecdefs(header)
	local bigEndian = header.endianness == 0

	structs['int_l'] = ([[
		typedef struct {
			uint%d_t value;
		} int_l;
	]]):format(header.s_int * 8)

	structs['uint8_l'] = [[
		typedef struct {
			uint8_t value;
		} uint8_l;
	]]

	ffi.cdef('typedef uint8_l bool_l;')

	ffi.metatype(ffi.typeof('int_l'), {
		__tostring = function(self) -- tonumber DOES NOT work
			-- print('[ilt] Converting ' .. self.value)
			return
				-- bigEndian and self.value or
				-- header.s_int == 4 and bit.rshift(bit.bswap(self.value), 16) or
				-- bit.bswap(self.value) -- untested
				self.value
		end
	})

	structs['size_lt'] = ([[
		typedef struct {
			uint%d_t value;
		} size_lt;
	]]):format(header.s_size_t * 8)

	ffi.metatype(ffi.typeof('size_lt'), {
		__tostring = function(self) -- tonumber DOES NOT work
			-- print('[slt] Converting ' .. self.value)
			return
				bigEndian and self.value or
				header.s_size_t == 4 and bit.rshift(bit.bswap(self.value), 16) or
				bit.bswap(self.value) -- untested
		end
	})

	-- Add better support
	structs['number_l'] = ([[
		typedef struct {
			double value;
		} number_l;
	]])
	assert(header.integral == 0, 'Float mode required.')
	assert(header.s_lua_Number == 8, 'Doubles are required.')

	-- can probably use the above
	structs['instruction'] = ([[
		typedef struct {
			uint%d_t value;
		} instruction;
	]]):format(header.s_instruction * 8)

	structs['string_l'] = [[
		typedef struct {
			size_lt _length;
			const char str[?];
    } string_l;
	]]

	structs['FunctionHeader'] = [[
    typedef struct {
      int_l first_line;
      int_l last_line;
      uint8_t upvalues;
      uint8_t parameters;
      uint8_t is_vararg;
      uint8_t s_stack;
    } FunctionHeader;
  ]]

 	ffi.metatype(ffi.typeof('string_l'), {
 		__index = function(self, key)
 			if key == 'length' then
 				return tonumber(tostring(self._length.value - 1)) -- the fuck
 			end
 		end,
 		__tostring = function(self)
 			return ffi.string(self.str, self.length)
 		end
 	})
end

-- collectgarbage('stop')
function disassemble(dump)
	jit.off()
	local func = {
		dump = type(dump) == 'string' and {dump = dump} or dump, -- clean
		code = {},
		constants = {},
		protos = {},
		info = {
			lines = {},
			locals = {},
			upvalues = {},
		}
	}

	-- print(hex_dump(func.dump.dump))

	local length = ffi.new('size_lt') -- name should be more relevant, w/ comment
	ffi.copy(length, func.dump.dump, ffi.sizeof(length))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(length))
	length = tonumber(tostring(length.value)) -- cant inline?
	func.name = func.dump.dump:sub(1, length)

	-- print('Length', length)
	-- print('Name: ' .. func.name)

	func.dump.dump = func.dump.dump:rebase(length) -- may be a bug here
	local proto = ffi.new('FunctionHeader')
	ffi.copy(proto, func.dump.dump, ffi.sizeof(proto))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(proto))

	for member in reflect.typeof(proto):members() do
		-- print(member.name .. ': ' .. tostring(proto[member.name]))
		func[member.name] = proto[member.name] or 'fat'
	end

	local codesize = ffi.new('size_lt')
	ffi.copy(codesize, func.dump.dump, ffi.sizeof(codesize))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(codesize))

	-- print('CodeSize', codesize)
	for i = 1, codesize.value do
		local instruction = ffi.new('instruction')
		ffi.copy(instruction, func.dump.dump, ffi.sizeof(instruction))
		func.code[i] = instructions.decode(tonumber(instruction.value), ffi.sizeof(instruction))
		func.dump.dump = func.dump.dump:rebase(ffi.sizeof(instruction))
	end

	local constantssize = ffi.new('size_lt')
	ffi.copy(constantssize, func.dump.dump, ffi.sizeof(constantssize))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(constantssize))

	-- print('ConstantsSize', constantssize.value)
	for i = 1, constantssize.value do
		local indicator = ffi.new('bool_l')
		local variable
		ffi.copy(indicator, func.dump.dump, ffi.sizeof(indicator))
		func.dump.dump = func.dump.dump:rebase(ffi.sizeof(indicator))
		indicator = consts.types[tonumber(indicator.value)] -- unneeded?
		if indicator then
			local struct -- can tidy
			if indicator == 'bool_l' then
				struct = ffi.new(indicator)
				ffi.copy(struct, func.dump.dump, ffi.sizeof(struct))
				-- print('bool_l', bool_l.value)
				func.constants[i - 1] = struct.value == 1
			elseif indicator == 'number_l' then
				struct = ffi.new(indicator)
				ffi.copy(struct, func.dump.dump, ffi.sizeof(struct))
				func.constants[i - 1] = struct.value
			elseif indicator == 'string_l' then
				struct = ffi.new('string_l', #func.dump.dump)
				ffi.copy(struct, func.dump.dump, ffi.sizeof(struct))
				local message = tostring(struct)
				-- print('Constant: \'' .. tostring(message) .. '\'')
				func.constants[i - 1] = message
			end
			if indicator == 'string_l' then
				func.dump.dump = func.dump.dump:rebase(struct.length + 1 + ffi.sizeof(struct._length)) -- why 1 in middle
			else
				func.dump.dump = func.dump.dump:rebase(ffi.sizeof(struct))
			end
		end
	end

	local protossize = ffi.new('size_lt') -- maybe should be int_lt?
	ffi.copy(protossize, func.dump.dump, ffi.sizeof(protossize))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(protossize))
	-- print('ProtosSize', protossize.value) -- can probably overflow
	for i = 1, protossize.value do
		func.protos[i - 1] = disassemble(func.dump)
	end

	local lineinfosize = ffi.new('size_lt')
	ffi.copy(lineinfosize, func.dump.dump, ffi.sizeof(lineinfosize))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(lineinfosize))
	-- print('Line info size: ' .. lineinfosize.value)
	for i = 1, lineinfosize.value do
		local linenumber = ffi.new('int_l')
		ffi.copy(linenumber, func.dump.dump, ffi.sizeof(linenumber))
		func.info.lines[i] = tonumber(linenumber.value)
		func.dump.dump = func.dump.dump:rebase(ffi.sizeof(linenumber))
	end

	local localvariablessize = ffi.new('size_lt') -- hungarian notation would be useful here
	ffi.copy(localvariablessize, func.dump.dump, ffi.sizeof(localvariablessize))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(localvariablessize))
	-- print('Local variable info size: ' .. localvariablessize.value)
	for i = 1, localvariablessize.value do
		local struct = ffi.new('string_l', #func.dump.dump)  -- should check for crazy characters that obfuscators generate
		local name, range
		ffi.copy(struct, func.dump.dump, ffi.sizeof(struct))
		name = tostring(struct) -- order of name concerning
		func.dump.dump = func.dump.dump:rebase(ffi.sizeof(struct._length) + 1 + struct.length) -- add to 1 again

		range = {}
		for i = 1, 2 do
			local pc = ffi.new('size_lt') -- name
			ffi.copy(pc, func.dump.dump, ffi.sizeof(pc)) -- should make simple wrapper for copy
			-- print('pc: ' .. pc.value)
			-- print('name: ' .. name)
			range[i] = pc
			func.dump.dump = func.dump.dump:rebase(ffi.sizeof(pc))
		end

		func.info.locals[i] = {
			name = name,
			range = range
		}
	end


	local upvaluenamessize = ffi.new('size_lt')
	ffi.copy(upvaluenamessize, func.dump.dump, ffi.sizeof(upvaluenamessize))
	func.dump.dump = func.dump.dump:rebase(ffi.sizeof(upvaluenamessize))
	-- print('Upvalue info size: ' .. upvaluenamessize.value)
	for i = 1, upvaluenamessize.value do
		local struct = ffi.new('string_l', #func.dump.dump)  -- should check for crazy characters that obfuscators generate
		local name
		ffi.copy(struct, func.dump.dump, ffi.sizeof(struct))
		name = tostring(struct) -- order of name concerning
		func.dump.dump = func.dump.dump:rebase(ffi.sizeof(struct._length) + 1 + struct.length) -- add to 1 again
		func.info.upvalues[i] = name
	end
	func.info.upvalues.count = tonumber(upvaluenamessize.value)

	return func
end

local target = io.open('luac.out', 'rb')
-- print('Output: ', pcall(function()
-- 	decode(target:read('*all'))
-- end))

return decode(target:read('*all'))
-- return decode