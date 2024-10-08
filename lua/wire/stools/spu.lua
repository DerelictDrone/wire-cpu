WireToolSetup.setCategory( "Chips, Gates", "Other/Sound", "Advanced" )
WireToolSetup.open( "spu", "SPU", "gmod_wire_spu", nil, "SPUs" )

if CLIENT then
  language.Add("Tool.wire_spu.name", "SPU Tool (Wire)")
  language.Add("Tool.wire_spu.desc", "Spawns a sound processing unit")
  language.Add("ToolWirespu_Model",  "Model:" )
  TOOL.Information = {
    { name = "left", text = "Create/reflash " .. TOOL.Name },
    { name = "right", text = "Open editor" },
  }
end
WireToolSetup.BaseLang()
WireToolSetup.SetupMax( 7 )

TOOL.ClientConVar = {
  model             = "models/cheeze/wires/cpu.mdl",
  filename          = "",
  extensions        = ""
}

if CLIENT then
  ------------------------------------------------------------------------------
  -- Make sure firing animation is displayed clientside
  ------------------------------------------------------------------------------
  function TOOL:LeftClick()  return true end
  function TOOL:Reload()     return true end
  function TOOL:RightClick() return false end
end


if SERVER then
  util.AddNetworkString("ZSPU_RequestCode")
  util.AddNetworkString("ZSPU_OpenEditor")
  ------------------------------------------------------------------------------
  -- Reload: wipe ROM/RAM and reset memory model
  ------------------------------------------------------------------------------
  function TOOL:Reload(trace)
    if trace.Entity:IsPlayer() then return false end

    local player = self:GetOwner()
    if (trace.Entity:IsValid()) and
       (trace.Entity:GetClass() == "gmod_wire_spu") then
      trace.Entity:SetMemoryModel(self:GetClientInfo("memorymodel"))
      return true
    end
  end

  -- Left click: spawn SPU or upload current program into it
  function TOOL:CheckHitOwnClass(trace)
    return trace.Entity:IsValid() and (trace.Entity:GetClass() == self.WireClass or trace.Entity.WriteCell)
  end
  function TOOL:LeftClick_Update(trace)
    CPULib.SetUploadTarget(trace.Entity, self:GetOwner())
    net.Start("ZSPU_RequestCode") net.Send(self:GetOwner())
  end
  function TOOL:MakeEnt(ply, model, Ang, trace)
    local ent = WireLib.MakeWireEnt(ply, {Class = self.WireClass, Pos=trace.HitPos, Angle=Ang, Model=model})
    ent:SetMemoryModel(self:GetClientInfo("memorymodel"))
    ent:SetExtensionLoadOrder(self:GetClientInfo("extensions"))
    self:LeftClick_Update(trace)
    return ent
  end


  function TOOL:RightClick(trace)
    net.Start("ZSPU_OpenEditor") net.Send(self:GetOwner())
    return true
  end
end


if CLIENT then
  ------------------------------------------------------------------------------
  -- Compiler callbacks on the compiling state
  ------------------------------------------------------------------------------
  local function compile_success()
    CPULib.Upload()
  end

  local function compile_error(errorText)
    GAMEMODE:AddNotify(errorText,NOTIFY_GENERIC,7)
  end


  ------------------------------------------------------------------------------
  -- Request code to be compiled (called remotely from server)
  ------------------------------------------------------------------------------
  function ZSPU_RequestCode()
    if ZSPU_Editor then
      CPULib.Debugger.SourceTab = ZSPU_Editor:GetActiveTab()
      CPULib.Compile(ZSPU_Editor:GetCode(),ZSPU_Editor:GetChosenFile(),compile_success,compile_error,"SPU",ZSPU_Editor.Location)
    end
  end
  net.Receive("ZSPU_RequestCode", ZSPU_RequestCode)

  ------------------------------------------------------------------------------
  -- Open ZSPU editor
  ------------------------------------------------------------------------------
  function ZSPU_OpenEditor()
    if not ZSPU_Editor then
      ZSPU_Editor = vgui.Create("Expression2EditorFrame")
      CPULib.SetupEditor(ZSPU_Editor,"ZSPU Editor", "spuchip", "SPU")
    end
    ZSPU_Editor:Open()
  end
  net.Receive("ZSPU_OpenEditor", ZSPU_OpenEditor)

  ------------------------------------------------------------------------------
  -- Build tool control panel
  ------------------------------------------------------------------------------
  function TOOL.BuildCPanel(panel)
    local Button = vgui.Create("DButton" , panel)
    panel:AddPanel(Button)
    Button:SetText("Online ZSPU documentation")
    Button.DoClick = function(button) CPULib.ShowDocumentation("ZSPU") end

    local Button = vgui.Create("DButton" , panel)
    panel:AddPanel(Button)
    Button:SetText("Open Sound Browser")
    Button.DoClick = function()
      RunConsoleCommand("wire_sound_browser_open")
    end


    ----------------------------------------------------------------------------
    local currentDirectory
    local FileBrowser = vgui.Create("wire_expression2_browser" , panel)
    panel:AddPanel(FileBrowser)
    FileBrowser:Setup("spuchip")
    FileBrowser:SetSize(235,400)
	function FileBrowser:OnFileOpen(filepath, newtab)
	  if not ZSPU_Editor then
        ZSPU_Editor = vgui.Create("Expression2EditorFrame")
        CPULib.SetupEditor(ZSPU_Editor,"ZSPU Editor", "spuchip", "SPU")
      end
      ZSPU_Editor:Open(filepath, nil, newtab)
    end


    ----------------------------------------------------------------------------
    local New = vgui.Create("DButton" , panel)
    panel:AddPanel(New)
    New:SetText("New file")
    New.DoClick = function(button)
      ZSPU_OpenEditor()
      ZSPU_Editor:AutoSave()
      ZSPU_Editor:NewScript(false)
    end
    panel:AddControl("Label", {Text = ""})

    ----------------------------------------------------------------------------
    local OpenEditor = vgui.Create("DButton", panel)
    panel:AddPanel(OpenEditor)
    OpenEditor:SetText("Open Editor")
    OpenEditor.DoClick = ZSPU_OpenEditor


    ----------------------------------------------------------------------------
    WireDermaExts.ModelSelect(panel, "wire_spu_model", list.Get("Wire_gate_Models"), 2)
    panel:AddControl("Label", {Text = ""})

    local enabledExtensionOrder = {}
    local enabledExtensionLookup = {}
    local extensionConvar = GetConVar("wire_spu_extensions")
    for ext in string.gmatch(extensionConvar:GetString() or "","([^;]*);") do
      if CPULib.Extensions["SPU"] and CPULib.Extensions["SPU"][ext] then
        enabledExtensionLookup[ext] = true
        table.insert(enabledExtensionOrder,ext)
      end
    end

    local ExtensionPanel = vgui.Create("DListView")
    local DisabledExtensionPanel = vgui.Create("DListView")
    ExtensionPanel:AddColumn("Enabled Extensions")
    DisabledExtensionPanel:AddColumn("Disabled Extensions")
    ExtensionPanel:SetSize(235,200)
    DisabledExtensionPanel:SetSize(235,200)
    if CPULib.Extensions["SPU"] then
      for k,_ in pairs(CPULib.Extensions["SPU"]) do
        if enabledExtensionLookup[k] then
          ExtensionPanel:AddLine(k)
        else
          DisabledExtensionPanel:AddLine(k)
        end
      end
    end

    local function ReloadExtensions()
      local extensions = {}
      for _,line in pairs(ExtensionPanel:GetLines()) do
        table.insert(extensions,line:GetValue(1))
      end
      extensionConvar:SetString(CPULib:ToExtensionString(extensions))
      CPULib:LoadExtensionOrder(extensions,"SPU")
    end

    function ExtensionPanel:OnRowSelected(rIndex,row)
      DisabledExtensionPanel:AddLine(row:GetValue(1))
      self:RemoveLine(rIndex)
      ReloadExtensions()
    end

    function DisabledExtensionPanel:OnRowSelected(rIndex,row)
      ExtensionPanel:AddLine(row:GetValue(1))
      self:RemoveLine(rIndex)
      ReloadExtensions()
    end

    panel:AddItem(ExtensionPanel)
    panel:AddItem(DisabledExtensionPanel)
    -- Reload the extensions at least once to make sure users don't have to touch the list
    -- in order to use extensions on first opening of the tool menu
    ReloadExtensions()

  end

  ------------------------------------------------------------------------------
  -- Tool screen
  ------------------------------------------------------------------------------
  function TOOL:DrawToolScreen(width, height)
      CPULib.RenderCPUTool(1,"ZSPU")
  end
end
