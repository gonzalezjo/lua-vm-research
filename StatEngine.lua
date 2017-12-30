-- i shouldn't pass operands to the function every time. operands should be its own local, i think. for Speed. or nah.

local disassembly = require('disassembler')
local bit = require('bit')
local opcodes = require('opcodes_interpreter')

local print = print

local hooks = require('debug.hooks')
local logs = require('debug.logs')
local printLogger = logs.new('VMPrints')

local fires = 0
hooks.setProxyHook('print', function(...)
  local args = {...}
  local tmp = ''
  fires = fires + 1
  -- if fires >= 3 then error('f') end
  for _, v in pairs(args) do
    if type(v) == 'table' then
      print'Ha!'
      for j,h in pairs(v) do print(j,h) end
      print('ok')
    end
    tmp = tmp ..'\t' .. tostring(v)
  end
  -- print('VMHooks', ..., table.concat{tmp})
  printLogger:put(tmp)
end)
printLogger:setPrintingSeverity(-math.huge)

local function loaddisassembly(disassembly)
  assert(disassembly, 'No disassembly provided.')

  local interpreter

  local ip = 1
  local stack = {height = -1} -- ty necrobumpist
  function stack:pop()
    -- print(self.height)
    local output = self[self.height - 1]
    self[self.height] = nil -- possibly unnecessary
    self.height = self.height - 1
    -- assert(output, 'Off by one?')
    return output
  end

  local open_upvalues = setmetatable({}, {
    __mode = 'v' -- holy shit if this works
  })

  local stack_mt = {
    __newindex = function(self, key, value) -- idea shamelessly stolen from necrobumpist
      if value then
        assert(key, 'No key.')
        assert(self.height, 'No height')
        if key > self.height then
          rawset(self, 'height', key)
        end
        rawset(self, key, value)
      else
        rawset(self, key, nil)
      end
    end
  }

  setmetatable(stack, stack_mt)

  local stack_size = 0
  local environment = getfenv(0)

  local state = {
    ['callstack'] = {height = -1},
    ['upvalues'] = {},
    ['code'] = disassembly.code,
    ['constants'] = disassembly.constants,
    ['protos'] = disassembly.protos,
    ['currentname'] = disassembly.name,
    ['info'] = disassembly.info,
    ['upvalues'] = {},
  }

  setmetatable(state.callstack, stack_mt)

  local virtualized = {} -- might weaken keys
  local tostring = tostring
  local virtualized_mt = {
    __tostring = function(self)
      local self_f = getmetatable(self).__tostring
      getmetatable(self).__tostring = nil
      local identifier = ('function: (spoofed %s) '):format(state.currentname or '[UNDEFINED]') .. tostring(self):gsub('%w+: ', '')
      getmetatable(self).__tostring = self_f
      return identifier
    end,
    -- __metatable = '', -- do stuff about rawget later
  }

  local upvalue_mt = {
    __index = function(self, key)
    end,
    __newindex = function(self, key, value)
    end,
  }

  local type = type
  environment.type = function(v)
    return virtualized[v] and 'function' or type(v)
  end

  local wrappers = {
    -- a = dest, b = source
    [opcodes.MOVE] = function(operands) -- 0
      if stack[operands.a] == 5 then
        -- error ('Debug trap/MOVE')
      end
      print('WTF move?', stack[operands.a], stack[operands.b])
      if virtualized[operands.b] then
        error('Moving closure')
      end
      stack[operands.a] = stack[operands.b]
      -- assert(stack[operands.a], 'MOVE FAIL')
    end,

    -- a = dest, b = const position
    [opcodes.LOADK] = function(operands) -- 1
      -- print('Constant', state.constants[operands.b])
      stack[operands.a] = state.constants[operands.b]
    end,

   [opcodes.LOADBOOL] = function(operands) -- 2
      stack[operands.a] = operands.b ~= 0
      ip = operands.c ~= 0 and ip + 1 or ip
    end,

    [opcodes.LOADNIL] = function(operands) -- 3
      print('LOADNIL')
      for i = operands.a, operands.b do
        stack[i] = nil
      end
    end,

    -- Copies the value in upvalue number B into register R(A).
    [opcodes.GETUPVAL] = function(operands) -- 4
      local upvalue = state.callstack[#state.callstack].upvalues[operands.b+1]
      stack[operands.a] = upvalue.val
      assert(stack[operands.a], 'Getupval fail')
    end,

    [opcodes.GETGLOBAL] = function(operands) -- 5
      stack[operands.a] = environment[state.constants[operands.b]]
    end,

    [opcodes.GETTABLE] = function(operands) -- 6
      local p_data = operands.p_data
      stack[operands.a] = stack[operands.b][p_data.c_const and state.constants[p_data.c] or stack[p_data.c]]
      print('gettable', stack[operands.a])
    end,

    [opcodes.SETGLOBAL] = function(operands) -- 7
      environment[state.constants[operands.b]] = stack[operands.a]
    end,

    -- copy from R(A) into upvalue R(B)
    [opcodes.SETUPVAL] = function(operands) -- 8
      local upvalue = state.callstack[#state.callstack].upvalues[operands.b + 1]
      state.callstack[#state.callstack].stack[upvalue.operand] = stack[operands.a]
      upvalue.val = stack[operands.a]
    end,

    [opcodes.SETTABLE] = function(operands) -- 9
      local p_data = operands.p_data
      local index = p_data.b_const and state.constants[p_data.b] or stack[p_data.b]
      stack[operands.a][index] = p_data.c_const and state.constants[p_data.c] or stack[p_data.c]
      print('SETTABLE', stack[operands.a][index])
    end,

    [opcodes.NEWTABLE] = function(operands) -- 10
      stack[operands.a] = {}
    end,

    [opcodes.SELF] = function(operands) -- 11
      local p_data = operands.p_data
      stack[operands.a + 1] = stack[operands.b]
      stack[operands.a] = stack[operands.b][p_data.c_const and state.constants[p_data.c] or stack[p_data.c]]
    end,

    [opcodes.ADD] = function(operands) -- 12
      local p_data = operands.p_data
      stack[operands.a] = (p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) + (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])
    end,

    [opcodes.SUB] = function(operands) -- 13
      local p_data = operands.p_data
      stack[operands.a] = (p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) - (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])
    end,

    [opcodes.MUL] = function(operands) -- 14
      local p_data = operands.p_data
      stack[operands.a] = (p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) * (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])
    end,

    [opcodes.DIV] = function(operands) -- 15
      local p_data = operands.p_data
      stack[operands.a] = (p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) / (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])
    end,

    [opcodes.MOD] = function(operands) -- 16
      local p_data = operands.p_data
      stack[operands.a] = (p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) % (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])
    end,

    [opcodes.POW] = function(operands) -- 17
      local p_data = operands.p_data
      stack[operands.a] = (p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) ^ (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])
    end,

    [opcodes.UNM] = function(operands) -- 18
      stack[operands.a] = -stack[operands.b]
    end,

    [opcodes.NOT] = function(operands) -- 19
      stack[operands.a] = not stack[operands.b]
    end,

    [opcodes.LEN] = function(operands) -- 20
      stack[operands.a] = #stack[operands.b]
    end,

    -- R(A) = R(B) .. R(C)
    [opcodes.CONCAT] = function(operands) -- 21
      local b, concatted = operands.b, ''
      for str = b + 1, operands.c do
        concatted = concatted .. stack[str]
      end
    end,

    [opcodes.JMP] = function(operands) -- 22
      print('JMPTest: ', operands.b)
      ip = ip + operands.b
    end,

    [opcodes.EQ] = function(operands) -- 23
      ip = ip + (((p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) == (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])) ~= operands.a) and 1 or 0
    end,

    [opcodes.LT] = function(operands) -- 24
      ip = ip + (((p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) < (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])) ~= operands.a) and 1 or 0
    end,

    [opcodes.LE] = function(operands) -- 25
      ip = ip + (((p_data.b_const and state.constants[p_data.b] or stack[p_data.b]) <= (p_data.c_const and state.constants[p_data.c] or stack[p_data.c])) ~= operands.a) and 1 or 0
    end,

    [opcodes.TEST] = function(operands) -- 26
      ip = ip + (((operands.a and 1 or 0) == operands.c) and 1 or 0)
    end,

    [opcodes.TESTSET] = function(operands) -- 27
      if operands.a and 1 or 0 == operands.c then
        ip = ip + 1
      else
        stack[operands.b] = stack[operands.a] -- probably? LOOK INTO
      end
    end,

    -- a = callee, b = argument count+1, c = return count+1, args start
    -- if b == 0, then go from R(A+1) to top of stack
    [opcodes.CALL] = function(operands) -- 28, should rewrite like opcodes.RETURN
      local a, b, c = operands.a, operands.b, operands.c
      local callee = stack[a]
      local argument_list = {}

      print("ARGUMENTS_TOTAL", b - 1, callee, string.sub)
      if b == 0 then -- reach for top of stack
        for i = a + 1, stack.height do
          argument_list[i - a] = stack[i]
        end
      elseif b ~= 1 then -- Selected argument count
        for i = a + 1, a + b - 1 do
          argument_list[i - a] = stack[i]
        end
      else
        print('Skipping arguments.')
      end

      print('Argument list', unpack(argument_list)) -- will be empty for increment
      for i,v in pairs(argument_list) do print(i,v) end
      print'Done listing args'

      if virtualized[callee] then
        print('Virtualizing a call.')
        state.callstack[#state.callstack + 1] = {
          ip = ip,
          state = state,
          c = c,
          a = a,
          -- upvalues = setmetatable({}, {
          --  __mode = 'v'
          -- }),
          called = callee,
          upvalues = callee.upvalues,
          stack = stack,
        }
        local _stack = setmetatable({height = -1}, stack_mt)
        for i = 0, b do
          _stack[i] = argument_list[i + 1]
        end
        stack = _stack
        -- for i, v in pairs(callee.upvalues) do -- optimize later
        --   print(i, v)
        --   stack[v.operand] = v
        -- end
        -- os.exit(-1)
        state = callee.state
        ip = 1
        -- stack = callee.stack
      else
        print('C Call', 'callee', callee, 'print', print)
        local actual_returned_count, return_list = (function(...)
          return select('#', ...), {...}
        end)(callee(unpack(argument_list))) -- plz dont break with nils PLZZZZ god
        rawset(stack, 'height', operands.a) -- fixes CallTest.lua. somehow, im pretty sure this is wrong.
        if c == 0 then -- reach for top of stack
          print('Returning from C call with the FULL stack', actual_returned_count)
          for i = 0, actual_returned_count do
            stack[i + a] = return_list[i + 1] -- before 9/26, this did not add 1 to i
          end
        elseif c ~= 1 then -- if 1, then no need to update for returned values
          print('Case two')
          for i = 0, c - 2 do
            stack[i + a] = return_list[i + 1]
          end
        end
        -- stack:pop()
        -- stack.height = a -- test
      end
    end,

    [opcodes.TAILCALL] = function(operands) -- 29
      error('TAILCALL not implemented')
    end,

    -- a = where parameters start, b = determines amt of parameters. b-1 = amount. b=1, no return. b = 0, return to top of stack.
    [opcodes.RETURN] = function(operands) -- 30
      -- must close open upvalues
      print('Return called.')
      local callstack = state.callstack
      local callstack_size = #state.callstack
      -- error('No.')
      if callstack_size == 0 then
        return error('No work left.')
      else -- any little bit clearer helps with this. so, explicit.
        local frame = callstack[callstack_size]
        -- if #frame.upvalues ~= 0 then
        --   for i = 1, #frame.upvalues do
        --     print('f', frame.upvalues[i])
        --     print('fi', frame.upvalues[i].i)
        --     print('fo', frame.upvalues[i].operand)
        --     print('fv', frame.upvalues[i].v)
        --     stack[frame.upvalues[i].operand] = frame.upvalues[i].v
        --     print('UV: ', frame.upvalues[i].v, frame.upvalues[i].operand)
        --   end
        -- end

        do
          local a = operands.a
          local amount_to_return =
            (operands.b == 0 and
              (stack.height - a) or -- to top of stack
            (operands.b == 1 and nil or operands.b - 1))

          local cvirt_c, cvirt_actual_returned_count, cvirt_return_list, cvirt_a =
            frame.c, amount_to_return, {}, frame.a

          assert(cvirt_c, 'No C?')
          -- print('poop')
          -- for i,v in pairs(cvirt_return_list) do print('sad',i,v) end

          print('Actual returned: ', amount_to_return)

          if not amount_to_return then
            error('No returning.')
            cvirt_actual_returned_count, cvirt_return_list = 0, {}
          else
            for i = a, a + amount_to_return - 1 do -- is this right/wrong?
              cvirt_return_list[i - a] = stack[i]
              print(i-a,'z',stack[i],'GREPFLAG1')
            end
          end

          state, ip, stack = frame.state, frame.ip, frame.stack
          if cvirt_c == 0 then -- reach for top of stack
            print('RET To the top.')
            for i = 0, cvirt_actual_returned_count - 1 do
              stack[i + cvirt_a] = cvirt_return_list[i]
              print(i+cvirt_a, 'b', cvirt_return_list[i])
            end
          elseif cvirt_c ~= 1 then -- if 1, then no need to update for returned values
            print('Updating returned values.', cvirt_c)
            for i = 0, cvirt_c - 1 do
              print(i+cvirt_a, 'c', cvirt_return_list[i])
              stack[i + cvirt_a] = cvirt_return_list[i]
            end
          end
          callstack[callstack_size] = nil
          -- stack.height = operands.a
          -- stack:pop()
        end
      end
      -- stack.height = cvirt_a -- probably bad, this was during mybbmagic testing
      -- collectgarbage()
    end,

    [opcodes.FORLOOP] = function(operands) -- 31
      local a = operands.a
      local new = stack[a] + stack[a + 2]

      if (0 > stack[a + 2]) == (new > stack[a + 1]) then
        ip = ip + operands.b
        stack[a], stack[a + 3] = new, new
      end
    end,

    [opcodes.FORPREP] = function(operands) -- 32
      stack[operands.a] = stack[operands.a] - stack[operands.a + 2]
      ip = ip + operands.b
    end,

    [opcodes.TFORLOOP] = function(operands) -- 33
      error('TFORLOOP not implemented.')
    end,

    -- R(A) references array, B is amount of elements to set. C C is # of table to be initialized
    -- Values used to initialize table in R(A+1), R(A+2), R(A+3)
    -- if B == 0, then table is set with variable number of array elements, from R(A+1) to top of stack.
    -- See: last element in constructor is vararg or function call
    -- If C is 0, then the next instruction is cast as an integer, and used as the C value.
    -- happens only when operand C cannot encode the block number (C > 511), equivalent to an array index greater than 25550
    [opcodes.SETLIST] = function(operands) -- 34 / assumes FPF of 50
      local a, b, c = operands.a

      if b == 0 then
        b = stack.height - operands.a
      else
        b = operands.b
      end

      if c == 0 then
        c = state.code[ip].raw
        ip = ip + 1
      else
        c = operands.c
      end

      local array = stack[a]
      local base = (c - 1) * 50

      for i = 1, operands.b do
        array[base + i] = stack[a+i]
      end
    end,

    -- close all local variables from R(A) onwards
    -- has no effect on locals not used as upvalues
    -- >= R(A)
    [opcodes.CLOSE] = function(operands) -- 35
      -- local error = print
      -- local upvalues = state.
      -- for i = operands.a, stack.height do
        -- if upvalues
      -- end
      print('Close called.')
      -- error('Close called')
      -- i need to CLOSE on usedUpvalue and stuff

      -- collectgarbage() -- plz
    end,

    -- upvalues set by closure
    -- bx is function number, zero indexed
    -- a becomes reference to function
    -- for each upvalue used, 'pseudo-instruction'
      -- of either MOVE or GETUPVAlUE
      -- where only b matters
    -- move corresponds to local in r(b) in current lex block
    -- getupvalue is upvalue B in current lexical block
    [opcodes.CLOSURE] = function(operands) -- 36
      -- for i,v in pairs(state.protos) do print(i,v) end
      local func = state.protos[operands.b]
      local upvalues_count = func.info.upvalues.count
      -- print('Creating closure', upvalues_count)
      -- print('#upvals:' .. tostring(upvalues_count))

      local closure = setmetatable({
        state = {
          callstack = state.callstack, -- bad decision
          code = func.code,
          constants = func.constants,
          protos = func.protos,
          currentname = func.currentname,
          info = info,
        },
        -- stack = setmetatable({height = -1}, stack_mt),
        upvalues = {map={}}
      }, virtualized_mt)


      local upvalues, map = closure.upvalues, closure.upvalues.map
      local i = ip
      while true do
        local pos = i - ip
        local instruction = state.code[i]

        if instruction.opcode.id == opcodes.MOVE then -- seems correct
          -- b is going to be the position on the stack, which can get CHANGED LATER!!! D:
          -- closure.upvalues[pos + 1] = {i=instruction.operands.b,v=stack[instruction.operands.b]}
          print('Move special devirtualiation', 'b', instruction.operands.b, 'stack.b', stack[instruction.operands.b])
          -- stack[instruction.operands.a] = stack[instruction.operands.b] and 5
          -- stack[instruction.operands.a] = {virtualizedVariable=true, stack=stack, operand=instruction.operands.b}
          upvalues[#upvalues + 1] = {
            virt = true,
            opid = #upvalues + 1,
            val=stack[instruction.operands.b],
            operand = instruction.operands.b
          }
          upvalues.map[operands.b] = #upvalues
        elseif instruction.opcode.id == opcodes.GETUPVAL then
          print('Getupval special devirtualiation')
          print('DEVIRTData: ', stack[instruction.operands.b])
          closure[pos + 1] = {i=instruction.operands.b,v=stack[instruction.operands.b]}
          -- stack[instruction.operands.a] = state.upvalues[instruction.operands.b]
        -- elseif instruction.opcode.id == opcodes.CLOSE then
          -- error('Virtualizing CLOSE')
          -- ip = ip + 1
        else
          -- ip = ip - 1 -- breaks multivalue test
          -- print(instruction.opcode.name)
          -- print('Broken closure code and/or malicious code generation. Name: ' .. state.code[i].opcode.name)
          break
        end
        i = i + 1
      end
      ip = i

      -- state.code[ip] = ip + upvalues_count
      -- os.exit(-1)

      stack[operands.a] = closure -- holy shit this is it i think
      virtualized[closure] = true
    end,

  }

  local function dump_logs()
    local FORMAT_STRING = '%d\t%s\t\t%s\t%s\t%s\t%s\t%s'
    assert(state, 'DEBUG INFO DESTROYED; NO STATE')
    print('Chunk ip: ' .. ip)
    print('Chunk name: ' .. (state.currentname or '[UNDEFINED]'))
    print('Call stack height: ' .. #state.callstack)
    print('Last instructions:\n')

    print(('-'):rep(10*select(2,FORMAT_STRING:gsub('\t', ''))+2)) -- lol
    print('OFFSET\tOPCODE\t\t\tR(A)\tR(B)\tR(C)\tMODE\tCOMMENT')
    print(('-'):rep(10*select(2,FORMAT_STRING:gsub('\t', ''))+2)) -- lol
    for i = 1, ip - 1 do
      local instruction = state.code[i]
      print(string.format(FORMAT_STRING,
        -(ip-i-1),
        (instruction.opcode.name .. (' '):rep(8 - #instruction.opcode.name)),
        instruction.operands.a, instruction.operands.b or '',
        instruction.operands.c or '',
        instruction.opcode.mode.m,
        instruction.opcode.id == opcodes.LOADK and ('(' .. tostring(state.constants[instruction.operands.b]) .. ')') or ''))
    end
    print(('-'):rep(10*select(2,FORMAT_STRING:gsub('\t', ''))+2)) -- lol
    print()
    print(('-'):rep(4*select(2,FORMAT_STRING:gsub('\t', ''))+2)) -- lol
    -- print('Heights: ', stack.height, #stack)
    for i = 0, #state.callstack do
      print('Stack: ' .. i)
      print(('-'):rep(4*select(2,FORMAT_STRING:gsub('\t', ''))+2)) -- lol
      if not stack.height then
        print('WARNING; NO STACK HEIGHT!')
      else
        for i = 0, stack.height do
          print(i, stack[i])
          if type(stack[i]) == 'table' then
            for k, v in pairs(stack[i]) do
              print('\t', k, v)
            end
          end
        end
        for i = stack.height + 1, stack.height + 8 do
          if type(stack[i]) == 'table' then
            for k, v in pairs(stack[i]) do
              print('\t', k, v)
            end
          end
          print(('[%d]+'):format(i), stack[i])
        end
      end
      print(('-'):rep(4*select(2,FORMAT_STRING:gsub('\t', ''))+2)) -- lol
      stack = state.callstack[#state.callstack - i]
      if not stack then
        break
      end
    end

    print('\n[LOGGER] Dumping logs')
    for name, logger in pairs(logs.getAll()) do
      print(('Logger: %s (%d)'):format(name, #logger:getLogs()))
      for logId, log in ipairs(logger:getLogs()) do
        print('    ', logId, log)
      end
      print()
    end

    if state.currentname and state.info.lines[ip - 1] then
      print('Debug data detected.')
      print(('Name: %s\nLine %d\n'):format(state.currentname, state.info.lines[ip - 1]))
    end
    -- state.info.lines[i]
  end

  function interpreter()
    -- local pcall = function(f) return f() end -- debug
    local debug_messages = {}

    local i
    local succeeded = {xpcall(function()
      local abort
      repeat
        i = state.code[ip] -- rewrite
        if not i then
          error(('No instruction: %s, %s'):format(tostring(ip), tostring(state.currentname)))
        end
        if not wrappers[i.opcode.id] then
          print('\n[Warning] Unsupported operation (' .. i.opcode.name .. ', ' .. i.opcode.id .. ') ' .. 'Exiting...\n')
          -- os.exit(-1)
          break
        end
        ip = ip + 1
        abort = wrappers[i.opcode.id](i.operands)
      until abort
    end, function(message)
      debug_messages.error = message
      debug_messages.trace = debug.traceback()
    end)}

    if not succeeded[1] then
      print('\n\nDEBUG INFORMATION\n')
      print('Recorded errors: \n', debug_messages.error)
      print('Stack trace:')
      print('    ' .. debug_messages.trace)
      print()
      dump_logs()
      os.exit(1)
    end

    -- print(unpack(errored))
    -- print(i.opcode.name, ip)

  end

  return interpreter
end

-- for _, opcode in ipairs(disassembly.code) do
--   print(string.format('%s %s %s %s %s', opcode.opcode.name, opcode.operands.a, opcode.operands.b or '', opcode.operands.c or '', opcode.opcode.mode.m))
-- end
-- os.exit(-1)

local start_interpreter = loaddisassembly(disassembly)
start_interpreter()
-- coroutine.wrap(start_interpreter)()
