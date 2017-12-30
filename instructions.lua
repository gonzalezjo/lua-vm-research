local bit = require('bit')

local opnames = {
  [0] =  'MOVE',
  [1] =  'LOADK',
  [2] =  'LOADBOOL',
  [3] =  'LOADNIL',
  [4] =  'GETUPVAL',
  [5] =  'GETGLOBAL',
  [6] =  'GETTABLE',
  [7] =  'SETGLOBAL',
  [8] =  'SETUPVAL',
  [9] =  'SETTABLE',
  [10] = 'NEWTABLE',
  [11] = 'SELF',
  [12] = 'ADD',
  [13] = 'SUB',
  [14] = 'MUL',
  [15] = 'DIV',
  [16] = 'MOD',
  [17] = 'POW',
  [18] = 'UNM',
  [19] = 'NOT',
  [20] = 'LEN',
  [21] = 'CONCAT',
  [22] = 'JMP',
  [23] = 'EQ',
  [24] = 'LT',
  [25] = 'LE',
  [26] = 'TEST',
  [27] = 'TESTSET',
  [28] = 'CALL',
  [29] = 'TAILCALL',
  [30] = 'RETURN',
  [31] = 'FORLOOP',
  [32] = 'FORPREP',
  [33] = 'TFORLOOP',
  [34] = 'SETLIST',
  [35] = 'CLOSE',
  [36] = 'CLOSURE',
  [37] = 'VARARG',
}

local iABC , iABx, iAsBx = 'iABC', 'iABx', 'iAsBx'
local OpArgR, OpArgK, OpArgU, OpArgN = 'R', 'K', 'U', 'N'

-- #define opmode(t,a,b,c,m) (((t)<<7) | ((a)<<6) | ((b)<<4) | ((c)<<2) | (m))
local function opmode(t, a, b, c, m)
  -- plz
  return {
    ['t'] = t == 1,
    ['a'] = a == 1,
    ['b'] = b,
    ['c'] = c,
    ['m'] = m,
  }
end

local opmodes = {
  --            T  A    B       C     mode       opcode
  [0] =  opmode(0, 1, OpArgR, OpArgN, iABC),  -- OP_MOVE
  [1] =  opmode(0, 1, OpArgK, OpArgN, iABx),  -- OP_LOADK
  [2] =  opmode(0, 1, OpArgU, OpArgU, iABC),  -- OP_LOADBOOL
  [3] =  opmode(0, 1, OpArgR, OpArgN, iABC),  -- OP_LOADNIL
  [4] =  opmode(0, 1, OpArgU, OpArgN, iABC),  -- OP_GETUPVAL
  [5] =  opmode(0, 1, OpArgK, OpArgN, iABx),  -- OP_GETGLOBAL
  [6] =  opmode(0, 1, OpArgR, OpArgK, iABC),  -- OP_GETTABLE
  [7] =  opmode(0, 0, OpArgK, OpArgN, iABx),  -- OP_SETGLOBAL
  [8] =  opmode(0, 0, OpArgU, OpArgN, iABC),  -- OP_SETUPVAL
  [9] =  opmode(0, 0, OpArgK, OpArgK, iABC),  -- OP_SETTABLE
  [10] = opmode(0, 1, OpArgU, OpArgU, iABC),  -- OP_NEWTABLE
  [11] = opmode(0, 1, OpArgR, OpArgK, iABC),  -- OP_SELF
  [12] = opmode(0, 1, OpArgK, OpArgK, iABC),  -- OP_ADD
  [13] = opmode(0, 1, OpArgK, OpArgK, iABC),  -- OP_SUB
  [14] = opmode(0, 1, OpArgK, OpArgK, iABC),  -- OP_MUL
  [15] = opmode(0, 1, OpArgK, OpArgK, iABC),  -- OP_DIV
  [16] = opmode(0, 1, OpArgK, OpArgK, iABC),  -- OP_MOD
  [17] = opmode(0, 1, OpArgK, OpArgK, iABC),  -- OP_POW
  [18] = opmode(0, 1, OpArgR, OpArgN, iABC),  -- OP_UNM
  [19] = opmode(0, 1, OpArgR, OpArgN, iABC),  -- OP_NOT
  [20] = opmode(0, 1, OpArgR, OpArgN, iABC),  -- OP_LEN
  [21] = opmode(0, 1, OpArgR, OpArgR, iABC),  -- OP_CONCAT
  [22] = opmode(0, 0, OpArgR, OpArgN, iAsBx), -- OP_JMP
  [23] = opmode(1, 0, OpArgK, OpArgK, iABC),  -- OP_EQ
  [24] = opmode(1, 0, OpArgK, OpArgK, iABC),  -- OP_LT
  [25] = opmode(1, 0, OpArgK, OpArgK, iABC),  -- OP_LE
  [26] = opmode(1, 1, OpArgR, OpArgU, iABC),  -- OP_TEST
  [27] = opmode(1, 1, OpArgR, OpArgU, iABC),  -- OP_TESTSET
  [28] = opmode(0, 1, OpArgU, OpArgU, iABC),  -- OP_CALL
  [29] = opmode(0, 1, OpArgU, OpArgU, iABC),  -- OP_TAILCALL
  [30] = opmode(0, 0, OpArgU, OpArgN, iABC),  -- OP_RETURN
  [31] = opmode(0, 1, OpArgR, OpArgN, iAsBx), -- OP_FORLOOP
  [32] = opmode(0, 1, OpArgR, OpArgN, iAsBx), -- OP_FORPREP
  [33] = opmode(1, 0, OpArgN, OpArgU, iABC),  -- OP_TFORLOOP
  [34] = opmode(0, 0, OpArgU, OpArgU, iABC),  -- OP_SETLIST
  [35] = opmode(0, 0, OpArgN, OpArgN, iABC),  -- OP_CLOSE
  [36] = opmode(0, 1, OpArgU, OpArgN, iABx),  -- OP_CLOSURE
  [37] = opmode(0, 1, OpArgU, OpArgN, iABC),  -- OP_VARARG
}

local OPCODE_WIDTH = 6
local A_WIDTH = 8

local function decode(instruction, size_bytes) -- lets just use pure lua now...
  local opcode = bit.band(instruction, 2^OPCODE_WIDTH - 1)
  local mode = opmodes[opcode]
  local operands = bit.rshift((instruction - opcode), 6)

  local a, b, c = bit.band(operands,  2^A_WIDTH - 1)
  local bc = bit.rshift((operands - a), 8)
  assert(not b and not c, 'Uh oh.')

  if mode.m == 'iABx' then
    b = bc
  else
    local width = ((size_bytes * 8) - A_WIDTH - OPCODE_WIDTH) / 2
    if mode.m == 'iAsBx' then
      b = bc - 2^(2 * width - 1) + 1
    elseif mode.m == 'iABC' then
      c = bit.band(bc, 2^width - 1)
      b = bit.rshift((bc-c), width)
    else
      error('Invalid type.')
    end
  end

  local p_data = {}

  if mode.b == OpArgK then
    local const = b >= 256
    p_data.b_const, p_data.b = const, const and bit.bxor(b, 0x100) or b
  end

  if mode.c == OpArgK then
    local const = c >= 256
    p_data.c_const, p_data.c = const, const and bit.bxor(c, 0x100) or c
  end

  return {
    ['raw'] = instruction,
    ['opcode'] = {
      id = opcode,
      name = opnames[opcode],
      mode = mode,
    },
    ['operands'] = {
      a = a,
      b = b,
      c = c,
      p_data = p_data,
    }
  }
end

return {
  ['consts'] = consts, -- bad name
  ['decode'] = decode,
}