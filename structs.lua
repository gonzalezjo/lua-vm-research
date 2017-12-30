if _G.structs then
  error('structs cannot be loaded more than once')
end

local ffi = require('ffi')

local structs = {
  ['DumpHeader'] = {
    ffi.cdef [[
    typedef struct {
      uint32_t signature;
      uint8_t version;
      bool format;
      bool endianness;
      uint8_t s_int;
      uint8_t s_size_t;
      uint8_t s_instruction;
      uint8_t s_lua_Number;
      uint8_t integral;
    } DumpHeader; ]]
	},
}

_G.structs = structs

return setmetatable({}, {
  __index = function(self, key)
    if structs[key] then
      -- print 'Fetching struct'
      return key
    else
      return error('Struct not defined.')
    end
  end,
  __newindex = function(self, key, value)
    if structs[key] then
      return error(('Struct %s already defined'):format(key))
    end
    local t = type(value)
    structs[key] = t == 'string' and {ffi.cdef(value)} or t == 'table' and t or error(('Invalid type for struct %s'):format(key))
  end
})

-- basically augement