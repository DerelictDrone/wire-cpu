--------------------------------------------------------------------------------
-- Zyelios VM (Zyelios CPU/GPU virtual machine)
--
-- Virtual machine implementation core
--------------------------------------------------------------------------------
ZVM = {}
-- TODO: Remove microcode debugging, it's not possible to access normally.
if not SERVER and not CLIENT then
  ZVM.MicrocodeDebug = true
end




--------------------------------------------------------------------------------
-- Include extra files
include("wire/zvm/zvm_opcodes.lua")
include("wire/zvm/zvm_features.lua")
include("wire/zvm/zvm_data.lua")





--------------------------------------------------------------------------------
-- Emit "microcode" to the output stream
if ZVM.MicrocodeDebug then -- Debug microcode generator
  local pad = 0
  function ZVM:Emit(text)
    -- TODO: Remove microcode debugging, it's not possible to access normally.
    if string.find(text,"end") and (not string.find(text,"if"))
    then pad = pad - 1 end

    if string.find(text,"elseif") or string.find(text,"else")
    then self.EmitBlock = self.EmitBlock..string.rep("  ",pad-1)..text.."\n"
    else self.EmitBlock = self.EmitBlock..string.rep("  ",pad)..text.."\n"
    end

    if (string.find(text,"if") or string.find(text,"for"))
       and (not string.find(text,"elseif"))
       and (not string.find(text,"end"))
    then pad = pad + 1 end
  end
else
  function ZVM:Emit(...)
    self.EmitBlock = self.EmitBlock..string.format(...).."\n"
  end
end




--------------------------------------------------------------------------------
-- Start new dynamic precompile block
function ZVM:Dyn_StartBlock()
  self.EmitBlock = ""
  self.EmitRegisterChanged = {}
  self.EmitOperand = { "0", "0" }
  self.EmitExpression = {}

  -- This instruction requires an interrupt check after being used
  self.EmitNeedInterruptCheck = false
  -- Operand RM function to be used for the operand
  self.EmitOperandRM = {}
  -- Operand byte to be used (replaces $BYTE)
  self.EmitOperandByte = {}
  -- Operand segment prefix to  be used (replaces $SEG)
  self.EmitOperandSegment = {}

  -- Mark local registers
  self:Emit("local EAX,EBX,ECX,EDX,ESI,EDI,ESP,EBP,OP1,OP2")
  self:Emit("local  R0, R1, R2, R3, R4, R5, R6, R7")
  self:Emit("local  R8, R9,R10,R11,R12,R13,R14,R15")
  self:Emit("local R16,R17,R18,R19,R20,R21,R22,R23")
  self:Emit("local R24,R25,R26,R27,R28,R29,R30,R31")
end




--------------------------------------------------------------------------------
-- Load/fetch operand (by RM)
function ZVM:Dyn_LoadOperand(OP,RM)
  if self.OperandReadFunctions[RM] then
    local preEmit
    if self.ReadInvolvedRegisterLookup[RM] and
       self.EmitRegisterChanged[self.ReadInvolvedRegisterLookup[RM]] then
      -- Available local value for this register
      preEmit = self.OperandFastReadFunctions[RM]
    else
      preEmit = self.OperandReadFunctions[RM]
    end

    -- Make sure segment register is global
    self:Dyn_EmitForceRegisterGlobal(self.EmitOperandSegment[OP])

    -- Generate operand text
    preEmit = string.gsub(preEmit,"$BYTE",self.EmitOperandByte[OP] or "0")
    preEmit = string.gsub(preEmit,"$SEG","VM."..(self.EmitOperandSegment[OP] or "DS"))
    self.EmitOperand[OP] = preEmit

    if self.NeedInterruptCheck[RM] then self.EmitNeedInterruptCheck = true end
  end

  self.EmitOperandRM[OP] = RM
end




--------------------------------------------------------------------------------
-- Write operand (by RM)
function ZVM:Dyn_WriteOperand(OP,RM)
  if RM == 9 then -- Special case: attempting to write to CS
    self:Dyn_EmitInterrupt("13","1")
    return
  end

  if self.OperandWriteFunctions[RM] then
    if self.EmitExpression[OP] then -- check if we need writeback
      local preEmit
      if self.WriteInvolvedRegisterLookup[RM] then
        preEmit = self.OperandFastWriteFunctions[RM]
        self.EmitRegisterChanged[self.WriteInvolvedRegisterLookup[RM]]
          = self.InternalRegister[self.WriteInvolvedRegisterLookup[RM]]
        else
        if self.WriteRequiredRegisterLookup[RM] and
           self.EmitRegisterChanged[self.WriteRequiredRegisterLookup[RM]] then
          preEmit = self.OperandFastWriteFunctions[RM]
        else
          preEmit = self.OperandWriteFunctions[RM]
        end
      end

      preEmit = string.gsub(preEmit,"$EXPR",self.EmitExpression[OP])
      preEmit = string.gsub(preEmit,"$BYTE",self.EmitOperandByte[OP] or "0")
      preEmit = string.gsub(preEmit,"$SEG","VM."..(self.EmitOperandSegment[OP] or "0"))

      self:Emit(preEmit)
    end
  end
end




--------------------------------------------------------------------------------
-- Preprocess microcode text (for microcode syntax to work)
function ZVM:Dyn_PreprocessEmit(text)
  local preEmit = string.gsub(   text,"$1",self.EmitOperand[1])
        preEmit = string.gsub(preEmit,"$2",self.EmitOperand[2])
  return string.gsub(preEmit,"$L","local")
end




--------------------------------------------------------------------------------
-- Emit preprocessed text
function ZVM:Dyn_Emit(...)
  self:Emit(self:Dyn_PreprocessEmit(string.format(...)))
end




--------------------------------------------------------------------------------
-- Emit operand being set to specific expression
function ZVM:Dyn_EmitOperand(OP,text,emitNow)
  if not text then
    self.EmitExpression[1] = self:Dyn_PreprocessEmit(OP)
  else
    self.EmitExpression[OP] = self:Dyn_PreprocessEmit(text)
    if emitNow then
      self:Emit("OP"..OP.." = "..self.EmitExpression[OP])
      self.EmitExpression[OP] = "OP"..OP
    end
  end
end




--------------------------------------------------------------------------------
-- Force current state to be updated
function ZVM:Dyn_EmitState(errorState)
  -- Do we need to emit registers
  for v,v in pairs(self.EmitRegisterChanged) do
    --if (not errorState) or (not self.EmitRegisterChangedByOperand[k]) then
    self:Emit("VM."..v.." = "..v)
    --end
  end
end




--------------------------------------------------------------------------------
-- Emit forced block return
function ZVM:Dyn_EmitBreak(emitIP)
  self:Emit("VM.TMR = VM.TMR + %d",self.PrecompileInstruction)
  self:Emit("VM.CODEBYTES = VM.CODEBYTES + %d",self.PrecompileBytes)
  if emitIP then
    self:Emit("VM.IP = %d",(self.PrecompileIP or 0))
    self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
  end
  if self.ExtraEmitFunction then self.ExtraEmitFunction(self) end
  self:Emit("if true then return end")
end




--------------------------------------------------------------------------------
-- Make sure specific register value is really globally set
function ZVM:Dyn_EmitForceRegisterGlobal(register)
  for k,v in pairs(self.EmitRegisterChanged) do
    if v == register then
      self:Emit("VM."..v.." = "..v)
      self.EmitRegisterChanged[k] = nil
      return
    end
  end
end




--------------------------------------------------------------------------------
-- Make sure specific register value is really locally set
function ZVM:Dyn_EmitForceRegisterLocal(register)
  if not self.EmitRegisterChanged[self.NeedRegisterLookup[register]] then
    self:Emit(register.." = ".."VM."..register)
    self.EmitRegisterChanged[self.NeedRegisterLookup[register]] = register
  end
end




--------------------------------------------------------------------------------
-- Flag register as changed/altered
function ZVM:Dyn_EmitRegisterValueChanged(register)
  for k,v in pairs(self.InternalRegister) do
    if string.upper(v) == register then
      self.EmitRegisterChanged[k] = register
    end
  end
end




--------------------------------------------------------------------------------
-- Emit specific opcode
function ZVM:Dyn_EmitOpcode(opcode)
  self.EmitExpression = {}
  if self.OpcodeTable[opcode] then
    self.OpcodeTable[opcode](self)
  end
end




--------------------------------------------------------------------------------
-- Emit interrupt call
-- intNo can only be numeric or "$1"
-- intParam can only be numeric or "IDX"
function ZVM:Dyn_EmitInterrupt(intNo,intParam)
  self:Dyn_EmitState()
  self:Emit("VM.IP = %d",(self.PrecompileIP or 0))
  self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
  self:Dyn_Emit("VM:Interrupt(%s,%s)",intNo,intParam)
  self:Dyn_EmitBreak()
end




--------------------------------------------------------------------------------
-- Emit interrupt check
function ZVM:Dyn_EmitInterruptCheck()
  if self.RQCAP == 1 then
    self:Emit("if VM.MEMRQ > 0 then") -- Extended memory request
      self:Emit("if VM.MEMRQ == 1 then") -- Delayed request
        self:Emit("VM.IP = %d",self.PrecompileStartIP)
        self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
        self:Emit("VM.IDLE = 1")
        self:Dyn_EmitState(true)
        self:Dyn_EmitBreak()
      self:Emit("elseif VM.MEMRQ == 2 then") -- Reading
        self:Dyn_EmitState(true)
        self:Emit("VM.MEMRQ = 4")
        self:Emit("VM.IP = %d",self.PrecompileStartIP)
        self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
        self:Emit("VM:Interrupt(28,VM.LADD)")
        self:Dyn_EmitBreak()
      self:Emit("elseif VM.MEMRQ == 3 then") -- Writing
        self:Dyn_EmitState(true)
        self:Emit("VM.MEMRQ = 5")
        self:Emit("VM.IP = %d",self.PrecompileStartIP)
        self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
        self:Emit("VM:Interrupt(29,VM.LADD)")
        self:Dyn_EmitBreak()
      self:Emit("end")
    self:Emit("end")
  end
  self:Emit("if VM.INTR == 1 then")
    self:Dyn_EmitBreak(false)
  self:Emit("end")
end




--------------------------------------------------------------------------------
-- End precompile block
function ZVM:Dyn_EndBlock()
  if not self.PrecompileBreak then
    self:Dyn_EmitState()
    self:Dyn_EmitBreak(true)
  end
  -- TODO: Remove microcode debugging, it's not possible to access normally.
  if self.MicrocodeDebug then
    if Msg then
      local str = self.EmitBlock
      Msg("BLOCK: \n")
      while str ~= "" do
        Msg(string.sub(str,1,100))
        str = string.sub(str,101)
      end
      Msg("\n")
    else
      print(self.EmitBlock)
    end
  end
  return self.EmitBlock
end

--------------------------------------------------------------------------------
-- Begins a block of code that will only run if we're in a quota supporting environment
-- and about to exit due to quota.
function ZVM:Dyn_BeginQuotaOnlyCode()
  self:Dyn_Emit("if VM.QuotaSupported then")
    self:Dyn_Emit("if VM.TMR > VM.Quota then")
end

--------------------------------------------------------------------------------
-- Ends a block of "Quota only" code.
function ZVM:Dyn_EndQuotaOnlyCode()
    self:Dyn_Emit("end")
  self:Dyn_Emit("end")
end

--------------------------------------------------------------------------------
-- Check if over quota on processors that support it, code between here and EndQuotaInterrupt
-- will be run on next available tick to wrap up what was started by this instruction
--
-- Note that to take arguments, you will have to store your values somewhere in VM and
-- clear them at the end of your function
function ZVM:Dyn_StartQuotaInterrupt()
  self:Dyn_Emit("if VM.QuotaSupported then")
    self:Dyn_Emit("if VM.TMR > VM.Quota then")
      self:Dyn_EmitState()
      self:Dyn_Emit("VM.LASTQUO = VM.TIMER+%d*VM.TimerDT",(self.PrecompileInstruction or 0))
      self:Dyn_Emit("VM.QUOFLAG = 1")
      self:Dyn_Emit("VM.IP = %d",self.PrecompileIP)
      self:Dyn_Emit("VM.XEIP = %d",self.PrecompileXEIP)
      self:Dyn_Emit("$L function quotafunc(VM)")
end

function ZVM:Dyn_EndQuotaInterrupt()
  self:Dyn_EmitState()
  self:Dyn_Emit("end")
  self:Dyn_Emit("VM.QuotaOverrunFunc = quotafunc")
  self:Dyn_Emit("VM.EndedOnQuota = true")
  self:Dyn_EmitBreak()
  self:Dyn_Emit("end")
  self:Dyn_Emit("end")
end

-- Allows you to set up code that runs if greater than this runlevel
function ZVM:Dyn_BeginUnprivilegedCode(Runlevel)
  self:Emit("if (VM.PCAP == 1) and (VM.CurrentPage.RunLevel > %d) then",Runlevel)
end

-- For readability to signify the end of an unprivileged block.
function ZVM:Dyn_EndUnprivilegedCode()
  self:Emit("end")
end

-- Set PreqOperands and an interrupt to return to just before this instruction, so it can be handled like a MEMRQ
function ZVM:Dyn_EmitUnprivilegedRequestInterrupt(Opcode)
  self:Dyn_Emit("VM.PreqOperand1 = $1 or 0")
  self:Dyn_Emit("VM.PreqOperand2 = $2 or 0")
  self:Dyn_Emit("VM.PreqReturn = 0")
  -- Default PreqHandled to -1 (meaning unhandled, don't take return value, just skip the instruction)
  self:Dyn_Emit("VM.PreqHandled = -1")
  -- Return to just before instruction, to allow the instruction to get the return value if handled
  self:Dyn_EmitState()
  self:Dyn_Emit("VM.IP = %d",self.PrecompileIP-self.PrecompileCurInstructionSize)
  self:Dyn_Emit("VM.XEIP = %d",self.PrecompileXEIP-self.PrecompileCurInstructionSize)
  self:Dyn_Emit("VM:Interrupt(13,%d)",Opcode)
  self:Dyn_EmitBreak()
end

--------------------------------------------------------------------------------
function ZVM:Precompile_Initialize()
  self.PrecompileXEIP = self.XEIP
  self.PrecompileIP = self.IP
  self.PrecompileStartXEIP = self.XEIP
  self.PrecompileBreak = false
  self.PrecompileInstruction = 0
  self.PrecompileBytes = 0
  self.PrecompileCurInstructionSize = 0

  self.PrecompilePreviousPage = math.floor(self.XEIP / 128)
  self:Dyn_StartBlock()
end

function ZVM:Precompile_Finalize()
  -- Emit finalizer
  self:Dyn_EndBlock()

  local result,message = CompileString(self.EmitBlock,"ZVM:[".. tonumber(self.PrecompileStartXEIP) or 0 .."]")
  if not result then
    print("[ZVM ERROR]: "..(message or "unknown error"))
  else
    -- This should guarantee the physical addresses for things.
    local page = self:GetPageByIndex(math.floor(self.PrecompileStartXEIP/128))
    local precompileStartPEIP = self.PrecompileStartXEIP
    local precompilePEIP = self.PrecompileXEIP
    if page.Remapped == 1 then
      precompileStartPEIP = page.MappedIndex*128+self.PrecompileStartXEIP%128
      precompilePEIP = precompileStartPEIP+(self.PrecompileXEIP-self.PrecompileStartXEIP)
    end
    for address = precompileStartPEIP, precompilePEIP-1 do
      if not self.IsAddressPrecompiled[address] then
        self.IsAddressPrecompiled[address] = { }
      end
      table.insert(self.IsAddressPrecompiled[address],precompileStartPEIP)
    end
    setfenv(result,self.Env)
    self.PrecompiledData[precompileStartPEIP] = result
  end

  return result
end

function ZVM:Precompile_Fetch()
  local prevIF = self.IF
  self.IF = 0
  local value = self:ReadCell(self.PrecompileXEIP) or 0
  self.IF = prevIF
  self.PrecompileCurInstructionSize = self.PrecompileCurInstructionSize + 1
  self.PrecompileXEIP = self.PrecompileXEIP + 1
  self.PrecompileIP = self.PrecompileIP + 1
  self.PrecompileBytes = self.PrecompileBytes + 1
  return value or 0
end

function ZVM:Precompile_Peek()
  local prevIF = self.IF
  self.IF = 0
  self:ReadCell(self.PrecompileXEIP)
  self.IF = prevIF
end

function ZVM:Precompile_Step()
  -- Set true XEIP register value for this step (this value will be used if XEIP is accessed)
  self.PrecompileTrueXEIP = self.PrecompileXEIP
  self.PrecompileStartIP = self.PrecompileIP

  -- Move on to the next instruction
  self.PrecompileInstruction = self.PrecompileInstruction + 1

  -- Reset requirement for an interrupt check, reset registers
  self.EmitNeedInterruptCheck = false
  --self.EmitRegisterChangedByOperand = {}

  -- Reset interrupts trigger if precompiling
  self.INTR = 0

  -- Allows an opcode to know how big the instruction is.
  self.PrecompileCurInstructionSize = 0

  -- Check if we crossed the page boundary, if so - repeat the check
  if math.floor(self.PrecompileXEIP / 128) ~= self.PrecompilePreviousPage then
    self:Emit("VM:SetCurrentPage(%d)",math.floor(self.PrecompileXEIP/128))
    self:Emit("if (VM.PCAP == 1) then")
    self:Emit("if (VM.CurrentPage.Execute == 0) and (VM.PreviousPage.RunLevel ~= 0) then")
        self:Dyn_EmitInterrupt("14",self.PrecompileIP)
      self:Emit("end")
    local expectedPage = self:GetPageByIndex(math.floor(self.PrecompileXEIP/128))
    if expectedPage.MappedIndex ~= math.floor(expectedPage.MappedIndex) then
      -- Bad address because MappedIndex is a float, send out an invalid address interrupt if this gets executed(it probably will in a sec)
      self:Dyn_EmitInterrupt(15,expectedPage.MappedIndex*128)
    end
    self:Emit("end")
    self:Emit("if (VM.CurrentPage.MappedIndex ~= %d) then",expectedPage.MappedIndex)
      -- This page wasn't the expected continuation, we should invalidate this address. (force recompile at this point)
      self:Emit("VM:InvalidateVirtualPrecompileAddress(VM.XEIP)")
      self:Dyn_EmitBreak(true)
    self:Emit("end")
    self:Emit("VM:SetPreviousPage(%d)",math.floor(self.PrecompileXEIP/128))

    self.PrecompilePreviousPage = math.floor(self.PrecompileXEIP / 128)
  end

  -- Fetch instruction and RM byte
  local Opcode,RM = self:Precompile_Fetch(),0
  local isFixedSize = false
  local OpCount,OpRunLevel = self.OperandCount,self.OpcodeRunLevel
  local negativeOp = Opcode and Opcode < 0
  if negativeOp then
    OpCount,OpRunLevel = self.ExtOperandCount,self.ExtOpcodeRunLevel
    Opcode = Opcode * - 1
  end
  -- Check if it is a fixed-size instruction
  if ((Opcode >= 2000) and (Opcode < 4000)) or
     ((Opcode >= 12000) and (Opcode < 14000)) then
    Opcode = Opcode - 2000
    isFixedSize = true
  end

  -- Fetch RM if required

  if (OpCount[Opcode % 1000] and (OpCount[Opcode % 1000] > 0))
    or (self:Precompile_Peek() == 0) or isFixedSize then
    RM = self:Precompile_Fetch()
  end

  -- If failed to fetch opcode/RM then report an error
  if (not Opcode) or (not RM) then--if self.INTR == 1 then
    self.IF = 1
    self:Interrupt(5,12)
    return
  end

  -- Check opcode runlevel
  if self.OpcodeRunLevel[Opcode] then
    self:Dyn_BeginUnprivilegedCode(self.OpcodeRunLevel[Opcode])
      self:Dyn_Emit("if VM.PreqHandled == 0 then")
        self:Dyn_EmitUnprivilegedRequestInterrupt(Opcode)
      self:Dyn_Emit("end")
      -- Skip running the privileged code if this was deemed "handled"
      self:Dyn_Emit("VM.PreqHandled = 0")
    self:Dyn_Emit("else")
      -- Privileged code will get wrapped in this block
  end

  -- Calculate operand RM bytes
  local dRM2 = math.floor(RM / 10000)
  local dRM1 = RM - dRM2*10000

  -- Default segment offsets
  local Segment1 = -4
  local Segment2 = -4

  -- Decode segment prefixes
  if Opcode > 1000 then
    if Opcode > 10000 then
      Segment2 = self:Precompile_Fetch() or 0

      Opcode = Opcode-10000
      if Opcode > 1000 then
        Segment1 = self:Precompile_Fetch() or 0

        Opcode = Opcode-1000

        local temp = Segment2
        Segment2 = Segment1
        Segment1 = temp
      else
        if isFixedSize then
          self:Precompile_Fetch()
        end
      end
    else
      Segment1 = self:Precompile_Fetch() or 0
      Opcode = Opcode-1000
      if isFixedSize then
        self:Precompile_Fetch()
      end
    end
  elseif isFixedSize then
    self:Precompile_Fetch()
    self:Precompile_Fetch()
  end

  -- If failed to fetch segment prefix then report an error
  if (not Segment1) or (not Segment2) then--if self.INTR == 1 then
    self:Interrupt(5,12)
    return
  end

  -- Check if opcode is invalid
  if not OpCount[Opcode] then
    self:Dyn_EmitInterrupt("4",Opcode)
    self.PrecompileBreak = true
  else
    -- Emit segment prefix if required
    self.EmitOperandSegment[1] = self.SegmentLookup[Segment1]
    self.EmitOperandSegment[2] = self.SegmentLookup[Segment2]

    -- Fetch immediate values if required
    if isFixedSize then
      self.EmitOperandByte[1] = self:Precompile_Fetch() or 0
      if not self.EmitOperandByte[1] then self:Interrupt(5,22) return end
      self.EmitOperandByte[2] = self:Precompile_Fetch() or 0
      if not self.EmitOperandByte[2] then self:Interrupt(5,32) return end

      if OpCount[Opcode] > 0 then
        self:Dyn_LoadOperand(1,dRM1)
        if OpCount[Opcode] > 1 then
          self:Dyn_LoadOperand(2,dRM2)
        end
      end
    else
      if OpCount[Opcode] > 0 then
        if self.NeedFetchByteLookup[dRM1] then
          self.EmitOperandByte[1] = self:Precompile_Fetch() or 0
          -- If failed to read the byte, report an error
          if not self.EmitOperandByte[1] then self:Interrupt(5,22) return end
        end
        self:Dyn_LoadOperand(1,dRM1)

        if OpCount[Opcode] > 1 then
          if self.NeedFetchByteLookup[dRM2] then
            self.EmitOperandByte[2] = self:Precompile_Fetch() or 0
            -- If failed to read the byte, report an error
            if not self.EmitOperandByte[2] then self:Interrupt(5,32) return end
          end
          self:Dyn_LoadOperand(2,dRM2)
        end
      end
    end

    -- Emit interrupt check prefix
    if self.EmitNeedInterruptCheck then
      self:Emit("VM.IP = %d",(self.PrecompileIP or 0))
      self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
    end

    -- Emit opcode
    if negativeOp then
      self:Dyn_EmitOpcode(Opcode*-1)
    else
      self:Dyn_EmitOpcode(Opcode)
    end

    -- Write back the values
    if OpCount[Opcode] and (OpCount[Opcode] > 0) then
      self:Dyn_WriteOperand(1,dRM1)
      if OpCount[Opcode] > 1 then
        self:Dyn_WriteOperand(2,dRM2)
      end
    end

    -- Emit interrupt check
    if self.EmitNeedInterruptCheck then
      self:Dyn_EmitInterruptCheck()
    end
    if self.OpcodeRunLevel[Opcode] then
      -- Wrap the privileged block up here.
      self:Dyn_EndUnprivilegedCode()
    end
  end

  -- Do not repeat if opcode breaks the stream
  return not self.PrecompileBreak
end

-- Helper that will convert virtual => physical for you if necessary and then invalidate them.
function ZVM:InvalidateVirtualPrecompileAddress(Address)
  local Page = self:GetPageByIndex(math.floor(Address/128))
  local newAddress = Address
  if Page.Remapped == 1 then
    Address = (Page.MappedIndex*128)+(Address%128)
  end
  self:InvalidatePrecompileAddress(Address)
end

-- These should be physical addresses.
function ZVM:InvalidatePrecompileAddress(Address)
      -- Invalidate precompiled data (Moved so the address will be changed to physical if necessary)
    if self.IsAddressPrecompiled[Address] then
      for k,v in ipairs(self.IsAddressPrecompiled[Address]) do
        self.PrecompiledData[v] = nil
        self.IsAddressPrecompiled[Address][k] = nil
      end
    end
end

--------------------------------------------------------------------------------
-- VM step forward
function ZVM:Step(overrideSteps,extraEmitFunction)
  if self.BusLock == 1 then return end

  -- Trigger timers
  self:TimerLogic()

  -- Calculate absolute execution address and set current page
  self.XEIP = self.IP + self.CS
  self:SetCurrentPage(math.floor(self.XEIP/128))

  -- Do not allow execution if we are not on kernel page, or not calling from kernel page
  if (self.PCAP == 1) and (self.CurrentPage.Execute == 0) and
     (self.PreviousPage.RunLevel ~= 0) then
    self:Interrupt(14,self.IP)
    return -- Step failed
  end

  -- Reset interrupts flags
  self.INTR = 0
  if self.NIF then
    self.IF = self.NIF
    self.NIF = nil
  end

  local address = self.XEIP
  if self.CurrentPage.Remapped == 1 then
    address = (self.CurrentPage.MappedIndex*128)+(self.XEIP%128)
  end

  -- Check if current instruction is precompiled
  local instructionPEIP = address
  if self.PrecompiledData[instructionPEIP] or overrideSteps then
    -- Precompile next instruction
    if overrideSteps then
      self:Precompile_Initialize()
      self.ExtraEmitFunction = extraEmitFunction
      local instruction = 1
      while (instruction <= overrideSteps) and self:Precompile_Step() do
        if self.ExtraEmitFunction then
          self:Emit("VM.IP = %d",(self.PrecompileIP or 0))
          self:Emit("VM.XEIP = %d",(self.PrecompileTrueXEIP or 0))
          self.ExtraEmitFunction(self)
        end
        instruction = instruction + 1
      end
      self.ExtraEmitFunction = nil
      self:Precompile_Finalize()

      -- Step clock forward (account for precompiling)
      self.TMR = self.TMR + 24*8000 -- + overrideSteps*9000
    end
    -- Execute precompiled instruction
    if CLIENT then -- FIXME: hack around crash on PCALL
      self.PrecompiledData[address]()
    else
      local status,message = pcall(self.PrecompiledData[address])
      if not status then
        print("[ZVM ERROR]: "..message)
        self:Interrupt(5,1)
      end
    end
  else
    -- Precompile several next instructions
    self:Precompile_Initialize()

    local instruction = 1
    while (instruction <= 24) and self:Precompile_Step() do
      instruction = instruction + 1
    end

    self:Precompile_Finalize()

    -- Step clock forward (account for precompiling)
    self.TMR = self.TMR + 24*8000--instruction*9000
  end

  -- Set this page as previous (if it is executable)
  self.XEIP = self.IP + self.CS
  self:SetPreviousPage(math.floor(self.XEIP/128))
  return
end

-- Any library that's needed by the entirety of the ZVM instruction set should go here
-- Platform dependant libraries(GPU or SPU for example) should be added to the env by the platform
ZVM.Env = {
  math={
    Clamp = math.Clamp,
    Round = math.Round,
    floor = math.floor,
    ceil = math.ceil,
    fmod = math.fmod,
    min = math.min,
    max = math.max,
    mod = math.mod,
    sqrt = math.sqrt,
    sin = math.sin,
    cos = math.cos,
    tan = math.tan,
    asin = math.asin,
    acos = math.acos,
    atan = math.atan,
    log = math.log,
    log10 = math.log10,
    exp = math.exp,
    pi = math.pi,
    abs = math.abs,
    random = math.random
  },
  bit={
    bnot = bit.bnot,
    band = bit.band,
    bor = bit.bor,
    bxor = bit.bxor,
    lshift = bit.lshift,
    rshift = bit.rshift
  },
  VM = ZVM
}


--------------------------------------------------------------------------------
function ZVM:PrintState()
  print("===========================")
  print("TMR="..self.TMR.."  TIMER="..self.TIMER.."  IP="..self.IP.."  CMPR="..self.CMPR)
  print("EAX="..self.EAX.."  EBX="..self.EBX.."  ECX="..self.ECX.."  EDX="..self.EDX)
  print("ESI="..self.ESI.."  EDI="..self.EDI.."  ESP="..self.ESP.."  EBP="..self.EBP.."  ESZ="..self.ESZ)
  print("CS="..self.CS.." SS="..self.SS.." DS="..self.DS.." FS="..self.FS..
       " GS="..self.GS.." ES="..self.ES.." KS="..self.KS.." LS="..self.LS)
  print("MEMRQ="..self.MEMRQ.." MEMADDR="..self.MEMADDR.." LADD="..self.LADD)
end
