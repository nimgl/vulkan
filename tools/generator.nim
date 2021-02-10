# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

import strutils, ./utils, httpClient, os, xmlparser, xmltree, streams, strformat, math, tables, algorithm

type
  VkProc = object
    name: string
    rVal: string
    args: seq[VkArg]
  VkArg = object
    name: string
    argType: string
  VkStruct = object
    name: string
    members: seq[VkArg]

var vkProcs: seq[VkProc]
var vkStructs: seq[VkStruct]
var vkStructureTypes: seq[string]

proc translateType(s: string): string =
  result = s
  result = result.replace("int64_t", "int64")
  result = result.replace("int32_t", "int32")
  result = result.replace("int16_t", "int16")
  result = result.replace("int8_t", "int8")
  result = result.replace("size_t", "uint") # uint matches pointer size just like size_t
  result = result.replace("float", "float32")
  result = result.replace("double", "float64")
  result = result.replace("VK_DEFINE_HANDLE", "VkHandle")
  result = result.replace("VK_DEFINE_NON_DISPATCHABLE_HANDLE", "VkNonDispatchableHandle")
  result = result.replace("const ", "")
  result = result.replace(" const", "")
  result = result.replace("unsigned ", "u")
  result = result.replace("signed ", "")
  result = result.replace("floatble", "float")
  result = result.replace("struct ", "")

  if result.contains('*'):
    let levels = result.count('*')
    result = result.replace("*", "")
    for i in 0..<levels:
      result = "ptr " & result

  result = result.replace("ptr void", "pointer")
  result = result.replace("ptr ptr char", "cstringArray")
  result = result.replace("ptr char", "cstring")

proc genTypes(node: XmlNode, output: var string) =
  echo "Generating Types..."
  output.add("\n# Types\n")

  var inType = false

  for types in node.findAll("types"):
    for t in types.items:
      if t.attr("category") == "include" or t.attr("requires") == "vk_platform" or
         t.tag != "type" or t.attr("name") == "int":
        continue

      # Require Header
      if t.attr("requires").contains(".h"):
        if not inType:
          output.add("\ntype\n")
          inType = true

        output.add("  {t.attr(\"name\")}* = ptr object\n".fmt)

      # Define category

      if t.attr("category") == "define":
        if t.child("name") == nil:
          continue
        inType = false
        let name = t.child("name").innerText
        if  name == "VK_MAKE_VERSION":
          output.add("\ntemplate vkMakeVersion*(major, minor, patch: untyped): untyped =\n")
          output.add("  (((major) shl 22) or ((minor) shl 12) or (patch))\n")
        elif name == "VK_VERSION_MAJOR":
          output.add("\ntemplate vkVersionMajor*(version: untyped): untyped =\n")
          output.add("  ((uint32)(version) shr 22)\n")
        elif name == "VK_VERSION_MINOR":
          output.add("\ntemplate vkVersionMinor*(version: untyped): untyped =\n")
          output.add("  (((uint32)(version) shr 12) and 0x000003FF)\n")
        elif name == "VK_VERSION_PATCH":
          output.add("\ntemplate vkVersionPatch*(version: untyped): untyped =\n")
          output.add("  ((uint32)(version) and 0x00000FFF)\n")
        elif name == "VK_API_VERSION_1_0":
          output.add("\nconst vkApiVersion1_0* = vkMakeVersion(1, 0, 0)\n")
        elif name == "VK_API_VERSION_1_1":
          output.add("const vkApiVersion1_1* = vkMakeVersion(1, 1, 0)\n")
        else:
          echo "category:define not found {name}".fmt
        continue

      # Basetype category

      if t.attr("category") == "basetype":
        if not inType:
          output.add("\ntype\n")
          inType = true
        let name = t.child("name").innerText
        if t.child("type") != nil:
          var bType = t.child("type").innerText
          bType = bType.translateType()

          output.add("  {name}* = distinct {bType}\n".fmt)
        continue

      # Bitmask category

      if t.attr("category") == "bitmask":
        var name = t.attr("name")
        if t.child("name") != nil:
          name = t.child("name").innerText

        var bType = t.attr("alias")
        var alias = true
        if t.child("type") != nil:
          alias = false
          bType = t.child("type").innerText
        bType = bType.translateType()
        if not alias:
          bType = "distinct " & bType

        output.add("  {name}* = {bType}\n".fmt)
        continue

      # Handle category

      if t.attr("category") == "handle":
        var name = t.attr("name")
        if t.child("name") != nil:
          name = t.child("name").innerText

        var bType = t.attr("alias")
        var alias = true
        if t.child("type") != nil:
          alias = false
          bType = t.child("type").innerText
        bType = bType.translateType()
        if not alias:
          bType = "distinct " & bType


        output.add("  {name}* = {bType}\n".fmt)
        continue

      # Enum category

      if t.attr("category") == "enum":
        let name = t.attr("name")
        let alias = t.attr("alias")
        # We are only outputting aliased enums here
        # The real enums are implemented below
        if alias != "":
          output.add("  {name}* = {alias}\n".fmt)
        continue

      # Funcpointer category

      if t.attr("category") == "funcpointer":
        let name = t.child("name").innerText
        if name == "PFN_vkInternalAllocationNotification":
          output.add("  PFN_vkInternalAllocationNotification* = proc(pUserData: pointer; size: csize; allocationType: VkInternalAllocationType; allocationScope: VkSystemAllocationScope) {.cdecl.}\n")
        elif name == "PFN_vkInternalFreeNotification":
          output.add("  PFN_vkInternalFreeNotification* = proc(pUserData: pointer; size: csize; allocationType: VkInternalAllocationType; allocationScope: VkSystemAllocationScope) {.cdecl.}\n")
        elif name == "PFN_vkReallocationFunction":
          output.add("  PFN_vkReallocationFunction* = proc(pUserData: pointer; pOriginal: pointer; size: csize; alignment: csize; allocationScope: VkSystemAllocationScope): pointer {.cdecl.}\n")
        elif name == "PFN_vkAllocationFunction":
          output.add("  PFN_vkAllocationFunction* = proc(pUserData: pointer; size: csize; alignment: csize; allocationScope: VkSystemAllocationScope): pointer {.cdecl.}\n")
        elif name == "PFN_vkFreeFunction":
          output.add("  PFN_vkFreeFunction* = proc(pUserData: pointer; pMemory: pointer) {.cdecl.}\n")
        elif name == "PFN_vkVoidFunction":
          output.add("  PFN_vkVoidFunction* = proc() {.cdecl.}\n")
        elif name == "PFN_vkDebugReportCallbackEXT":
          output.add("  PFN_vkDebugReportCallbackEXT* = proc(flags: VkDebugReportFlagsEXT; objectType: VkDebugReportObjectTypeEXT; cbObject: uint64; location: csize; messageCode:  int32; pLayerPrefix: cstring; pMessage: cstring; pUserData: pointer): VkBool32 {.cdecl.}\n")
        elif name == "PFN_vkDebugUtilsMessengerCallbackEXT":
          output.add("  PFN_vkDebugUtilsMessengerCallbackEXT* = proc(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageTypes: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: VkDebugUtilsMessengerCallbackDataEXT, userData: pointer): VkBool32 {.cdecl.}\n"):
        else:
          echo "category:funcpointer not found {name}".fmt
        continue

      # Struct category

      if t.attr("category") == "struct":
        let name = t.attr("name")
        if name == "VkBaseOutStructure" or name == "VkBaseInStructure":
          continue

        var vkStruct: VkStruct
        vkStruct.name = name

        output.add("\n  {name}* = object\n".fmt)

        for member in t.findAll("member"):
          var memberName = member.child("name").innerText
          if keywords.contains(memberName):
            memberName = "`{memberName}`".fmt
          var memberType = member.child("type").innerText
          memberType = memberType.translateType()

          var isArray = false
          var arraySize = "0"
          if member.innerText.contains('['):
            arraySize = member.innerText[member.innerText.find('[') + 1 ..< member.innerText.find(']')]
            if arraySize != "":
              isArray = true
            if arraySize == "_DYNAMIC":
              memberType = "ptr " & memberType
              isArray = false

          var depth = member.innerText.count('*')
          if memberType == "pointer":
            depth.dec
          for i in 0 ..< depth:
            memberType = "ptr " & memberType

          memberType = memberType.replace("ptr void", "pointer")
          memberType = memberType.replace("ptr ptr char", "cstringArray")
          memberType = memberType.replace("ptr char", "cstring")

          var vkArg: VkArg
          vkArg.name = memberName
          if not isArray:
            vkArg.argType = memberType
          else:
            vkArg.argType = "array[{arraySize}, {memberType}]".fmt
          vkStruct.members.add(vkArg)

          if not isArray:
            output.add("    {memberName}*: {memberType}\n".fmt)
          else:
            output.add("    {memberName}*: array[{arraySize}, {memberType}]\n".fmt)
        vkStructs.add(vkStruct)
        continue

      # Union category

      if t.attr("category") == "union":
        let name = t.attr("name")
        if name == "VkBaseOutStructure" or name == "VkBaseInStructure":
          continue

        output.add("\n  {name}* {{.union.}} = object\n".fmt)

        for member in t.findAll("member"):
          var memberName = member.child("name").innerText
          if keywords.contains(memberName):
            memberName = "`{memberName}`".fmt
          var memberType = member.child("type").innerText
          memberType = memberType.translateType()

          var isArray = false
          var arraySize = "0"
          if member.innerText.contains('['):
            arraySize = member.innerText[member.innerText.find('[') + 1 ..< member.innerText.find(']')]
            if arraySize != "":
              isArray = true
            if arraySize == "_DYNAMIC":
              memberType = "ptr " & memberType
              isArray = false

          var depth = member.innerText.count('*')
          if memberType == "pointer":
            depth.dec
          for i in 0 ..< depth:
            memberType = "ptr " & memberType

          if not isArray:
            output.add("    {memberName}*: {memberType}\n".fmt)
          else:
            output.add("    {memberName}*: array[{arraySize}, {memberType}]\n".fmt)
        continue

proc genEnums(node: XmlNode, output: var string) =
  echo "Generating and Adding Enums"
  output.add("# Enums\n")
  var inType = false
  for enums in node.findAll("enums"):
    let name = enums.attr("name")

    if name == "API Constants":
      inType = false
      output.add("const\n")
      for e in enums.items:
        let enumName = e.attr("name")
        var enumValue = e.attr("value")
        if enumValue == "":
          if e.attr("alias") == "":
            continue
          enumValue = e.attr("alias")
        else:
          enumValue = enumValue.replace("(~0U)", "(not 0'u32)")
          enumValue = enumValue.replace("(~0U-1)", "(not 0'u32) - 1")
          enumValue = enumValue.replace("(~0U-2)", "(not 0'u32) - 2")
          enumValue = enumValue.replace("(~0ULL)", "(not 0'u64)")

        if enumName == "VK_LUID_SIZE_KHR":
          enumValue = "VK_LUID_SIZE"
        elif enumName == "VK_QUEUE_FAMILY_EXTERNAL_KHR":
          enumValue = "VK_QUEUE_FAMILY_EXTERNAL"
        elif enumName == "VK_MAX_DEVICE_GROUP_SIZE_KHR":
          enumValue = "VK_MAX_DEVICE_GROUP_SIZE"

        output.add("  {enumName}* = {enumValue}\n".fmt)
      continue

    if not inType:
      output.add("\ntype\n")
      inType = true

    var elements: OrderedTableRef[int, string] = newOrderedTable[int, string]()
    for e in enums.items:
      if e.kind != xnElement or e.tag != "enum":
        continue

      let enumName = e.attr("name")
      var enumValueStr = e.attr("value")
      if enumValueStr == "":
        if e.attr("bitpos") == "":
          continue
        let bitpos = e.attr("bitpos").parseInt()
        enumValueStr = $nextPowerOfTwo(bitpos)
      enumValueStr = enumValueStr.translateType()

      var enumValue = 0
      if enumValueStr.contains('x'):
        enumValue = fromHex[int](enumValueStr)
      else:
        enumValue = enumValueStr.parseInt()

      if elements.hasKey(enumValue):
        continue
      elements.add(enumValue, enumName)

    if elements.len == 0:
      continue

    output.add("  {name}* {{.size: int32.sizeof.}} = enum\n".fmt)
    elements.sort(system.cmp)
    for k, v in elements.pairs:
      if name == "VkStructureType":
        vkStructureTypes.add(v.replace("_", ""))
      output.add("    {v} = {k}\n".fmt)

proc genProcs(node: XmlNode, output: var string) =
  echo "Generating Procedures..."
  output.add("\n# Procs\n")
  output.add("var\n")
  for commands in node.findAll("commands"):
    for command in commands.findAll("command"):
      var vkProc: VkProc
      if command.child("proto") == nil:
        continue
      vkProc.name = command.child("proto").child("name").innerText
      vkProc.rVal = command.child("proto").innerText
      vkProc.rVal = vkProc.rVal[0 ..< vkProc.rval.len - vkProc.name.len]
      while vkProc.rVal.endsWith(" "):
        vkProc.rVal = vkProc.rVal[0 ..< vkProc.rVal.len - 1]
      vkProc.rVal = vkProc.rVal.translateType()

      if vkProc.name == "vkGetTransformFeedbacki_v":
        continue

      for param in command.findAll("param"):
        var vkArg: VkArg
        if param.child("name") == nil:
          continue
        vkArg.name = param.child("name").innerText
        vkArg.argType = param.innerText
        vkArg.argType = vkArg.argType[0 ..< vkArg.argType.len - vkArg.name.len]
        while vkArg.argType.endsWith(" "):
          vkArg.argType = vkArg.argType[0 ..< vkArg.argType.len - 1]

        for part in vkArg.name.split(" "):
          if keywords.contains(part):
            vkArg.name = "`{vkArg.name}`".fmt

        vkArg.argType = vkArg.argType.translateType()

        if param.innerText.contains('['):
          let arraySize = param.innerText[param.innerText.find('[') + 1 ..< param.innerText.find(']')]
          vkArg.argType = "array[{arraySize}, {vkArg.argType}]".fmt

        vkProc.args.add(vkArg)

      vkProcs.add(vkProc)
      output.add("  {vkProc.name}*: proc(".fmt)
      for arg in vkProc.args:
        if not output.endsWith('('):
          output.add(", ")
        output.add("{arg.name}: {arg.argType}".fmt)
      output.add("): {vkProc.rval} {{.stdcall.}}\n".fmt)

proc genFeatures(node: XmlNode, output: var string) =
  echo "Generating and Adding Features..."
  for feature in node.findAll("feature"):
    let number = feature.attr("number").replace(".", "_")
    output.add("\n# Vulkan {number}\n".fmt)
    output.add("proc vkLoad{number}*() =\n".fmt)

    for command in feature.findAll("command"):
      let name = command.attr("name")
      for vkProc in vkProcs:
        if name == vkProc.name:
          output.add("  {name} = cast[proc(".fmt)
          for arg in vkProc.args:
            if not output.endsWith("("):
              output.add(", ")
            output.add("{arg.name}: {arg.argType}".fmt)
          output.add("): {vkProc.rVal} {{.stdcall.}}](vkGetProc(\"{vkProc.name}\"))\n".fmt)

proc genExtensions(node: XmlNode, output: var string) =
  echo "Generating and Adding Extensions..."
  for extensions in node.findAll("extensions"):
    for extension in extensions.findAll("extension"):

      var commands: seq[VkProc]
      for require in extension.findAll("require"):
        for command in require.findAll("command"):
          for vkProc in vkProcs:
            if vkProc.name == command.attr("name"):
              commands.add(vkProc)

      if commands.len == 0:
        continue

      let name = extension.attr("name")
      output.add("\n# Load {name}\n".fmt)
      output.add("proc load{name}*() =\n".fmt)

      for vkProc in commands:
        output.add("  {vkProc.name} = cast[proc(".fmt)
        for arg in vkProc.args:
          if not output.endsWith("("):
            output.add(", ")
          output.add("{arg.name}: {arg.argType}".fmt)
        output.add("): {vkProc.rVal} {{.stdcall.}}](vkGetProc(\"{vkProc.name}\"))\n".fmt)

proc genConstructors(node: XmlNode, output: var string) =
  echo "Generating and Adding Constructors..."
  output.add("\n# Constructors\n")
  for s in vkStructs:
    if s.members.len == 0:
      continue
    output.add("\nproc new{s.name}*(".fmt)
    for m in s.members:
      if not output.endsWith('('):
        output.add(", ")
      output.add("{m.name}: {m.argType}".fmt)

      if m.name.contains("flags"):
        output.add(" = 0.{m.argType}".fmt)
      if m.name == "sType":
        for structType in vkStructureTypes:
          if structType.cmpIgnoreStyle("VkStructureType{s.name[2..<s.name.len]}".fmt) == 0:
            output.add(" = VkStructureType{s.name[2..<s.name.len]}".fmt)
      if m.argType == "pointer":
        output.add(" = nil")

    output.add("): {s.name} =\n".fmt)

    for m in s.members:
      output.add("  result.{m.name} = {m.name}\n".fmt)

proc main() =
  if not os.fileExists("vk.xml"):
    let client = newHttpClient()
    let glUrl = "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/master/xml/vk.xml"
    client.downloadFile(glUrl, "vk.xml")

  var output = srcHeader & "\n"

  let file = newFileStream("vk.xml", fmRead)
  let xml = file.parseXml()

  xml.genEnums(output)
  xml.genTypes(output)
  xml.genConstructors(output)
  xml.genProcs(output)
  xml.genFeatures(output)
  xml.genExtensions(output)

  output.add("\n" & vkInit)

  writeFile("src/vulkan.nim", output)

if isMainModule:
  main()
