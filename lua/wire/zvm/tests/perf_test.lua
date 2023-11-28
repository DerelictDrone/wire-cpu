CPUTest = {}

function CPUTest:RunTest(VM,TestSuite)
	CPUTest.VM = VM
	CPUTest.TestSuite = TestSuite
	TestSuite.Compile("x: INC R0 INC R0 INC R0 INC R0 JMPR 0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 INC R0 JMP x",nil,CPUTest.RunCPU,CPUTest.CompileError)
end

function CPUTest.RunCPU()
	CPUTest.oldPrecompileInit = CPUTest.VM.Precompile_Initialize
	CPUTest.oldPrecompileFinalize = CPUTest.VM.Precompile_Finalize
	CPUTest.TotalPrecompileTime = 0
	function CPUTest.VM.Precompile_Initialize()
		print("starting precompile")
		CPUTest.PrevPrecompile = os.clock()
		CPUTest.oldPrecompileInit(CPUTest.VM)
	end
	function CPUTest.VM.Precompile_Finalize()
		print("end precompile")
		CPUTest.oldPrecompileFinalize(CPUTest.VM)
		CPUTest.TotalPrecompileTime = CPUTest.TotalPrecompileTime + (os.clock() - CPUTest.PrevPrecompile)
	end
	CPUTest.TestSuite.FlashData(CPUTest.VM,CPUTest.TestSuite.GetCompileBuffer()) -- upload compiled to virtual cpu
	CPUTest.VM.Clk = 1


	for i=0,4096 do
		CPUTest.VM:RunStep()
	end
	print("Total precompiling time: "..CPUTest.TotalPrecompileTime)
	-- False = no error, True = error
	if CPUTest.VM.R0 == 4096 then
		CPUTest.TestSuite.FinishTest(false)
	else
		CPUTest.TestSuite.Error("R0 is not 4096! R0 is "..tostring(CPUTest.VM.R0))
		CPUTest.TestSuite.FinishTest(true)
	end
end

function CPUTest.CompileError(msg)
	CPUTest.TestSuite.Error('hit a compile time error '..msg)
	CPUTest.TestSuite.FinishTest(true)
end
