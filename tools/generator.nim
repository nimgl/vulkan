# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

import std/[strutils, httpclient, os, xmlparser, xmltree, streams, strformat, math, tables, algorithm, bitops, sequtils]
import utils # local import

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
  VkFlags = object
    name: string
    flagbits: string
    bType: string

var vkProcs: seq[VkProc]
var vkStructs: seq[VkStruct]
var vkStructureTypes: seq[string]
var vkFlagsTypes: seq[VkFlags]
var vkFlagBitsTypes: seq[string]
var vkHandleTypes: seq[VkFlags]

proc camelCaseAscii*(s: string): string =
  ## Converts snake_case to CamelCase
  var L = s.len
  while L > 0 and s[L-1] == '_': dec L
  result = newStringOfCap(L)
  var i = 0
  result.add s[i]
  inc i
  var flip = false
  while i < L:
    if s[i] == '_':
      flip = true
    else:
      if flip:
        result.add toUpperAscii(s[i])
        flip = false
      else: result.add toLowerAscii(s[i])
    inc i

proc translateType(s: string): string =
  result = s
  result = result.multiReplace({
    "int64_t": "int64",
    "int32_t": "int32",
    "int16_t": "int16",
    "int8_t": "int8",
    "size_t": "uint", # uint matches pointer size just like size_t
    "float": "float32",
    "double": "float64",
    "VK_DEFINE_HANDLE": "VkHandle",
    "VK_DEFINE_NON_DISPATCHABLE_HANDLE": "VkNonDispatchableHandle",
    "const ": "",
    " const": "",
    "unsigned ": "u",
    "signed ": "",
    "struct ": "",
  })

  if result.startsWith('_'):
    result = result.substr(1)

  if result.contains('*'):
    let levels = result.count('*')
    result = result.replace("*", "")
    for i in 0..<levels:
      result = "ptr " & result

  result = result.multiReplace({
    "ptr void": "pointer",
    "ptr ptr char": "cstringArray",
    "ptr char": "cstring",
  })

proc genTypes(node: XmlNode, output: var string) =
  echo "Generating Types..."
  output.add("\n# Types\n")
  var inType = false
  for types in node.findAll("types"):
    for t in types.items:
      if t.attr("category") == "include" or t.attr("requires") == "vk_platform" or
         t.tag != "type" or t.attr("name") == "int" or t.attr("api") == "vulkansc":
        continue

      # Require Header
      if t.attr("requires").contains(".h"):
        if not inType:
          output.add("\ntype\n")
          inType = true
        var name = t.attr("name")
        if name.startsWith('_'): name = name.substr(1)
        output.add(&"  {name}* {{.nodecl.}} = object\n")

      # Define category
      if t.attr("category") == "define":
        if t.child("name") == nil:
          continue
        if t.attr("api") == "vulkansc" or t.attr("deprecated") != "":
          continue
        inType = false
        let name = t.child("name").innerText
        if name == "VK_MAKE_API_VERSION":
          output.add("\ntemplate vkMakeVersion*(variant, major, minor, patch: untyped): untyped =\n")
          output.add("  (variant shl 29) or (major shl 22) or (minor shl 12) or patch\n")
        elif name == "VK_API_VERSION_VARIANT":
          output.add("\ntemplate vkVersionVariant*(version: untyped): untyped =\n")
          output.add("  uint32(version) shr 29\n")
        elif name == "VK_API_VERSION_MAJOR":
          output.add("\ntemplate vkVersionMajor*(version: untyped): untyped =\n")
          output.add("  uint32(version) shr 22\n")
        elif name == "VK_API_VERSION_MINOR":
          output.add("\ntemplate vkVersionMinor*(version: untyped): untyped =\n")
          output.add("  (uint32(version) shr 12) and 0x000003FF\n")
        elif name == "VK_API_VERSION_PATCH":
          output.add("\ntemplate vkVersionPatch*(version: untyped): untyped =\n")
          output.add("  uint32(version) and 0x00000FFF\n")
        elif name == "VK_API_VERSION_1_0":
          output.add("\nconst vkApiVersion1_0* = vkMakeVersion(0, 1, 0, 0)\n")
        elif name == "VK_API_VERSION_1_1":
          output.add("const vkApiVersion1_1* = vkMakeVersion(0, 1, 1, 0)\n")
        elif name == "VK_API_VERSION_1_2":
          output.add("const vkApiVersion1_2* = vkMakeVersion(0, 1, 2, 0)\n")
        elif name == "VK_API_VERSION_1_3":
          output.add("const vkApiVersion1_3* = vkMakeVersion(0, 1, 3, 0)\n")
        elif name == "VK_API_VERSION_1_4":
          output.add("const vkApiVersion1_4* = vkMakeVersion(0, 1, 4, 0)\n")
        elif name == "VK_HEADER_VERSION":
          output.add("const vkHeaderVersion* = 344\n")
        elif name == "VK_HEADER_VERSION_COMPLETE":
          output.add("const vkHeaderVersionComplete* = vkMakeVersion(0, 1, 4, vkHeaderVersion)\n")
        else:
          echo &"category:define not found {name}"
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
          if name == "VkRemoteAddressNV": bType = "pointer"
          output.add(&"  {name}* = distinct {bType}\n")
        elif t.innerText.contains("struct"):
          # Forward-declared struct typedef (e.g. OHNativeWindow)
          # Skip types already defined in srcHeader
          if name notin ["ANativeWindow", "AHardwareBuffer", "CAMetalLayer",
              "MTLDevice_id", "MTLCommandQueue_id", "MTLBuffer_id",
              "MTLTexture_id", "MTLSharedEvent_id", "IOSurfaceRef"]:
            output.add(&"  {name}* {{.nodecl.}} = object\n")
        continue

      # Bitmask category
      if t.attr("category") == "bitmask":
        var name = t.attr("name")
        if t.attr("api") == "vulkansc":
          continue
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
        output.add(&"  {name}* = {bType}\n")
        vkFlagsTypes.add VkFlags(
          name: name,
          flagbits: name.replace("Flags", "FlagBits"),
          bType: if bType == "VkFlags64": "uint64" else: "uint32"
        )
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
          vkHandleTypes.add(VkFlags(name: name, bType: bType))
          bType = "distinct " & bType
        output.add(&"  {name}* = {bType}\n")
        continue

      # Enum category
      if t.attr("category") == "enum":
        let name = t.attr("name")
        let alias = t.attr("alias")
        # We are only outputting aliased enums here
        # The real enums are implemented below
        if alias != "":
          if alias == "VkPrivateDataSlotCreateFlagBits": continue
          output.add(&"  {name}* = {alias}\n")
        continue

      # Funcpointer category
      if t.attr("category") == "funcpointer":
        let nameNode = if t.child("name") != nil: t.child("name")
                       elif t.child("proto") != nil: t.child("proto").child("name")
                       else: nil
        if nameNode == nil: continue
        let name = nameNode.innerText
        if name == "PFN_vkInternalAllocationNotification":
          output.add("  PFN_vkInternalAllocationNotification* = proc (pUserData: pointer; size: uint; allocationType: VkInternalAllocationType; allocationScope: VkSystemAllocationScope) {.cdecl.}\n")
        elif name == "PFN_vkInternalFreeNotification":
          output.add("  PFN_vkInternalFreeNotification* = proc (pUserData: pointer; size: uint; allocationType: VkInternalAllocationType; allocationScope: VkSystemAllocationScope) {.cdecl.}\n")
        elif name == "PFN_vkReallocationFunction":
          output.add("  PFN_vkReallocationFunction* = proc (pUserData: pointer; pOriginal: pointer; size: uint; alignment: uint; allocationScope: VkSystemAllocationScope): pointer {.cdecl.}\n")
        elif name == "PFN_vkAllocationFunction":
          output.add("  PFN_vkAllocationFunction* = proc (pUserData: pointer; size: uint; alignment: uint; allocationScope: VkSystemAllocationScope): pointer {.cdecl.}\n")
        elif name == "PFN_vkFreeFunction":
          output.add("  PFN_vkFreeFunction* = proc (pUserData: pointer; pMemory: pointer) {.cdecl.}\n")
        elif name == "PFN_vkVoidFunction":
          output.add("  PFN_vkVoidFunction* = proc () {.cdecl.}\n")
        elif name == "PFN_vkFaultCallbackFunction":
          output.add("  PFN_vkFaultCallbackFunction* = proc (unrecordedFaults: VkBool32; faultCount: uint32; pFaults: ptr VkFaultData) {.cdecl.}\n")
        elif name == "PFN_vkDeviceMemoryReportCallbackEXT":
          output.add("  PFN_vkDeviceMemoryReportCallbackEXT* = proc (pCallbackData: ptr VkDeviceMemoryReportCallbackDataEXT; pUserData: pointer) {.cdecl.}\n")
        elif name == "PFN_vkGetInstanceProcAddrLUNARG":
          output.add("  PFN_vkGetInstanceProcAddrLUNARG* = proc (instance: VkInstance; pName: cstring): PFN_vkVoidFunction {.cdecl.}\n")
        elif name == "PFN_vkDebugReportCallbackEXT":
          output.add("  PFN_vkDebugReportCallbackEXT* = proc (flags: VkDebugReportFlagsEXT; objectType: VkDebugReportObjectTypeEXT; cbObject: uint64; location: uint; messageCode: int32; pLayerPrefix: cstring; pMessage: cstring; pUserData: pointer): VkBool32 {.cdecl.}\n")
        elif name == "PFN_vkDebugUtilsMessengerCallbackEXT":
          output.add("  PFN_vkDebugUtilsMessengerCallbackEXT* = proc (messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageTypes: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: ptr VkDebugUtilsMessengerCallbackDataEXT, userData: pointer): VkBool32 {.cdecl.}\n")
        else:
          echo &"category:funcpointer not found {name}"
        continue

      # Struct category
      if t.attr("category") == "struct":
        let name = t.attr("name")
        var vkStruct: VkStruct
        vkStruct.name = name
        if t.attr("alias") != "":
          let val = t.attr("alias")
          output.add(&"\n  {name}* = {val}\n")
          continue
        output.add(&"\n  {name}* = object\n")
        for member in t.findAll("member"):
          if member.attr("api") == "vulkansc":
            continue
          var memberName = member.child("name").innerText
          if isKeyword(memberName):
            memberName = &"`{memberName}`"
          var memberType = member.child("type").innerText
          memberType = memberType.translateType()
          var isArray = false
          var arraySize = "0"
          if member.innerText.contains('['):
            arraySize = member.innerText[member.innerText.find('[') + 1 ..< member.innerText.find(']')]
            if arraySize != "":
              isArray = true
            if arraySize == "_DYNAMIC":
              isArray = false
          var depth = member.innerText.count('*')
          if memberType == "pointer":
            depth.dec
          for i in 0 ..< depth:
            memberType = "ptr " & memberType
          memberType = memberType.multiReplace({
            "ptr void": "pointer",
            "ptr ptr char": "cstringArray",
            "ptr char": "cstring",
          })
          var vkArg: VkArg
          vkArg.name = memberName
          if not isArray:
            vkArg.argType = memberType
          else:
            vkArg.argType = &"array[{arraySize}, {memberType}]"
          vkStruct.members.add(vkArg)
          if not isArray:
            output.add(&"    {memberName}*: {memberType}\n")
          else:
            output.add(&"    {memberName}*: array[{arraySize}, {memberType}]\n")
        vkStructs.add(vkStruct)
        continue

      # Union category

      if t.attr("category") == "union":
        let name = t.attr("name")
        if name == "VkBaseOutStructure" or name == "VkBaseInStructure":
          continue
        output.add(&"\n  {name}* {{.union.}} = object\n")
        for member in t.findAll("member"):
          var memberName = member.child("name").innerText
          if isKeyword(memberName):
            memberName = &"`{memberName}`"
          var memberType = member.child("type").innerText
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
          memberType = memberType.translateType()
          if not isArray:
            output.add(&"    {memberName}*: {memberType}\n")
          else:
            output.add(&"    {memberName}*: array[{arraySize}, {memberType}]\n")
        continue

proc getEnumValue(e: XmlNode, name: string, extNumber: int): (int, string) =
  const companies =
    ["KHR", "EXT", "NV", "INTEL", "AMD", "MSFT", "QCOM", "ANDROID", "LUNARG", "HUAWEI", "QNX", "ARM"]
  var enumName = e.attr("name")
  enumName = camelCaseAscii(enumName)
  var tmp = name
  tmp = tmp.replace("FlagBits", "")
  var suffixes: seq[string] = @[]
  for suf in companies:
    if tmp.endsWith(suf):
      suffixes.add(camelCaseAscii(suf))
    tmp.removeSuffix(suf)
  for suf in suffixes.items:
    enumName.removeSuffix(suf)
  enumName.removePrefix(tmp)
  if enumName[0] in Digits:
    enumName = "N" & enumName
  var enumValueStr = e.attr("value")
  if enumValueStr == "":
    var num = 0
    if e.attr("bitpos") != "":
      let bitpos = e.attr("bitpos").parseInt()
      num.setBit(bitpos)
    if e.attr("offset") != "":
      let extNumberAttr = e.attr("extnumber")
      let extNumber = if extNumberAttr != "": extNumberAttr.parseInt() else: extNumber
      let enumBase = 1000000000 + (extNumber - 1) * 1000
      num = parseInt(e.attr("offset")) + enumBase
    if e.attr("dir") == "-":
      num = -num
    enumValueStr = $num
  enumValueStr = enumValueStr.translateType()
  var enumValue = 0
  if enumValueStr.startsWith("0x"):
    enumValue = fromHex[int](enumValueStr)
  else:
    enumValue = enumValueStr.parseInt()
  result = (enumValue, enumName)

proc genEnums(node: XmlNode, output: var string) =
  var extOrFeature: seq[XmlNode] = @[]
  for ext in node.findAll("extension"):
    if ext.attr("supported") == "disabled": continue
    extOrFeature.add ext
  for feat in node.findAll("feature"):
    if feat.attr("supported") == "disabled": continue
    extOrFeature.add feat
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
          enumValue = enumValue.multiReplace({
            "(~0U)": "(not 0'u32)",
            "(~1U)": "(not 1'u32)",
            "(~2U)": "(not 2'u32)",
            "(~0U-1)": "(not 0'u32) - 1",
            "(~0U-2)": "(not 0'u32) - 2",
            "(~0ULL)": "(not 0'u64)",
          })
        if enumName == "VK_LUID_SIZE_KHR":
          enumValue = "VK_LUID_SIZE"
        elif enumName == "VK_QUEUE_FAMILY_EXTERNAL_KHR":
          enumValue = "VK_QUEUE_FAMILY_EXTERNAL"
        elif enumName == "VK_MAX_DEVICE_GROUP_SIZE_KHR":
          enumValue = "VK_MAX_DEVICE_GROUP_SIZE"
        # elif enumName == "VK_TRUE":
        #   enumValue = "VK_BOOL32(1)"
        # elif enumName == "VK_FALSE":
        #   enumValue = "VK_BOOL32(0)"
        output.add(&"  {enumName.camelCaseAscii()}* = {enumValue.camelCaseAscii()}\n")
  for extOrFeat in extOrFeature.items:
    if extOrFeat.tag == "feature": continue
    let name = extOrFeat.attr("name")
    output.add(&"  # Extension: {name}\n")
    for r in extOrFeat.items:
      if r.kind != xnElement or r.tag != "require":
        continue
      for e in r.items:
        if e.kind != xnElement or e.tag != "enum":
          continue
        if e.attr("api") == "vulkansc" or e.attr("deprecated") != "" or e.attr("alias") != "":
          continue
        let enumName = e.attr("name")
        if not enumName.endsWith("EXTENSION_NAME") and not enumName.endsWith("SPEC_VERSION"): continue
        var enumValue = e.attr("value")
        output.add(&"  {enumName.camelCaseAscii()}* = {enumValue}\n")
  for enums in node.findAll("enums"):
    let name = enums.attr("name")
    if name == "API Constants": continue
    if not inType:
      output.add("\ntype\n")
      inType = true
    var elements: OrderedTableRef[int, string] = newOrderedTable[int, string]()
    for e in enums.items:
      if e.kind != xnElement or e.tag != "enum":
        continue
      if e.attr("api") == "vulkansc" or e.attr("deprecated") != "" or e.attr("alias") != "":
        continue
      let (enumValue, enumName) = getEnumValue(e, name, 1)
      if elements.hasKey(enumValue):
        continue
      elements.add(enumValue, enumName)
    # Add extensions
    for extOrFeat in extOrFeature.items:
      let extNumberAttr = extOrFeat.attr("number")
      let extNumber =
        if extNumberAttr != "" and extOrFeat.tag == "extension": extNumberAttr.parseInt() else: 1
      for r in extOrFeat.items:
        if r.kind != xnElement or r.tag != "require":
          continue
        for e in r.items:
          if e.kind != xnElement or e.tag != "enum":
            continue
          if e.attr("api") == "vulkansc" or e.attr("deprecated") != "" or e.attr("alias") != "":
            continue
          let extends = e.attr("extends")
          if extends != name:
            continue
          let (enumValue, enumName) = getEnumValue(e, name, extNumber)
          if elements.hasKey(enumValue):
            continue
          elements.add(enumValue, enumName)
    if elements.len == 0:
      continue
    output.add(&"  {name}* {{.size: sizeof(int32).}} = enum\n")
    if name.contains("FlagBits"):
      vkFlagBitsTypes.add name
    elements.sort(system.cmp)
    var prev = -1
    for enumValue, enumName in elements.pairs:
      if name == "VkStructureType":
        vkStructureTypes.add(enumName)
      if prev + 1 != enumValue:
        output.add(&"    {enumName} = {enumValue}\n")
      else:
        output.add(&"    {enumName}\n")
      prev = enumValue
    output.add("\n")

proc genHelpers(output: var string) =
  output.add("\n# VkDeviceSize helpers\n")
  output.add("""
proc `==`*(x, y: VkDeviceSize): bool {.borrow.}
proc `<=`*(x, y: VkDeviceSize): bool {.borrow.}
proc `< `*(x, y: VkDeviceSize): bool {.borrow.}
proc `+`*(x, y: VkDeviceSize): VkDeviceSize {.borrow.}
proc `-`*(x, y: VkDeviceSize): VkDeviceSize {.borrow.}
proc `*`*(x, y: VkDeviceSize): VkDeviceSize {.borrow.}
proc `not`*(x: VkDeviceSize): VkDeviceSize {.borrow.}
proc `div`*(x, y: VkDeviceSize): VkDeviceSize {.borrow.}
proc `and`*(x, y: VkDeviceSize): VkDeviceSize {.borrow.}
proc `shl`*(x: VkDeviceSize; y: uint64): VkDeviceSize {.borrow.}
proc `shr`*(x: VkDeviceSize; y: uint64): VkDeviceSize {.borrow.}

""")
  echo "Generating Handle helpers..."
  output.add("\n# Handle helpers\n")
  for handle in vkHandleTypes.items:
    output.add(&"""
proc `==`*(x, y: {handle.name}): bool {{.borrow.}}
""")
  echo "Generating Flag helpers..."
  output.add("\n# Flags helpers\n")
  output.add("""
import std/macros

macro flagsImpl(base, bits: typed, args: varargs[untyped]): untyped =
  let arr = newNimNode(nnkBracketExpr)
  for n in args: arr.add newCall(base, if n.kind == nnkDotExpr: n else: newDotExpr(bits, n))
  result = nestList(bindSym"or", arr)

""")
  for flags in vkFlagsTypes.items:
    if not vkFlagBitsTypes.anyIt(it == flags.flagbits): continue
    output.add(&"""
template `{{}}`*(t: typedesc[{flags.name}]; args: varargs[untyped]): untyped =
  t(flagsImpl({flags.bType}, {flags.flagbits}, args))

proc `==`*(x, y: {flags.name}): bool {{.inline.}} =
  x.{flags.bType} == y.{flags.bType}
proc `<=`*(x, y: {flags.name}): bool {{.inline.}} =
  (x.{flags.bType} and not y.{flags.bType}) == 0
proc contains*(x: {flags.name}; y: {flags.flagbits}): bool {{.inline.}} =
  (x.{flags.bType} and y.{flags.bType}) != 0

""")
# proc incl*(x: var {flags.name}; y: {flags.flagbits}) {{.inline.}} =
#   x = {flags.name}(x.{flags.bType} or y.{flags.bType})
# proc excl*(x: var {flags.name}; y: {flags.flagbits}) {{.inline.}} =
#   x = {flags.name}(x.{flags.bType} and not y.{flags.bType})

proc genProcs(node: XmlNode, output: var string) =
  echo "Generating Procedures..."
  output.add("\n# Procs\n")
  output.add("var\n")
  for commands in node.findAll("commands"):
    for command in commands.findAll("command"):
      var vkProc: VkProc
      if command.child("proto") == nil or command.attr("api") == "vulkansc":
        continue
      vkProc.name = command.child("proto").child("name").innerText
      vkProc.rVal = command.child("proto").innerText
      vkProc.rVal = vkProc.rVal[0 ..< vkProc.rval.len - vkProc.name.len]
      while vkProc.rVal.endsWith(" "):
        vkProc.rVal = vkProc.rVal[0 ..< vkProc.rVal.len - 1]
      vkProc.rVal = vkProc.rVal.translateType()
      # Skip commands that are preloaded
      if vkProc.name == "vkCreateInstance" or
          vkProc.name == "vkEnumerateInstanceExtensionProperties" or
          vkProc.name == "vkEnumerateInstanceLayerProperties" or
          vkProc.name == "vkEnumerateInstanceVersion":
        continue
      for param in command.findAll("param"):
        var vkArg: VkArg
        if param.child("name") == nil or param.attr("api") == "vulkansc":
          continue
        vkArg.name = param.child("name").innerText
        vkArg.argType = param.innerText
        if vkArg.argType.contains('['):
          let openBracket = vkArg.argType.find('[')
          let arraySize = vkArg.argType[openBracket + 1 ..< vkArg.argType.find(']')]
          var typeName = vkArg.argType[0..<openBracket].translateType()
          typeName = typeName[0 ..< typeName.len - vkArg.name.len]
          vkArg.argType = &"array[{arraySize}, {typeName}]"
        else:
          vkArg.argType = vkArg.argType[0 ..< vkArg.argType.len - vkArg.name.len]
          vkArg.argType = vkArg.argType.translateType().strip
        for part in vkArg.name.split(" "):
          if isKeyword(part):
            vkArg.name = &"`{vkArg.name}`"
        vkProc.args.add(vkArg)
      vkProcs.add(vkProc)
      output.add(&"  {vkProc.name}*: proc (")
      for arg in vkProc.args:
        if not output.endsWith('('):
          output.add(", ")
        output.add(&"{arg.name}: {arg.argType}")
      if vkProc.rval == "void":
        output.add(")")
      else:
        output.add(&"): {vkProc.rval}")
      output.add(" {.stdcall.}\n")

proc genFeatures(node: XmlNode, output: var string) =
  echo "Generating and Adding Features..."

  # Collect all commands from internal sub-features into their parent version
  # New vk.xml splits 1.0-1.4 into BASE/COMPUTE/GRAPHICS sub-features
  var versionCommands: OrderedTable[string, seq[string]]
  for feature in node.findAll("feature"):
    let api = feature.attr("api")
    if api == "" or api == "vulkansc": continue
    let name = feature.attr("name")
    let number = feature.attr("number").replace(".", "_")
    var cmds: seq[string]
    for command in feature.findAll("command"):
      let cmdName = command.attr("name")
      if cmdName != "":
        cmds.add(cmdName)
    if name.startsWith("VK_VERSION_"):
      if not versionCommands.hasKey(number):
        versionCommands[number] = @[]
      for c in cmds:
        versionCommands[number].add(c)
    elif name.startsWith("VK_BASE_VERSION_") or
         name.startsWith("VK_COMPUTE_VERSION_") or
         name.startsWith("VK_GRAPHICS_VERSION_"):
      # Internal sub-feature — merge commands into the parent VK_VERSION_
      if not versionCommands.hasKey(number):
        versionCommands[number] = @[]
      for c in cmds:
        versionCommands[number].add(c)
    # Skip other feature types (e.g. vulkansc-only)

  for number, cmds in versionCommands:
    output.add(&"\n# Vulkan {number}\n")
    output.add(&"proc vkLoad{number}*() =\n")
    var found = false
    for cmdName in cmds:
      for vkProc in vkProcs:
        if cmdName == vkProc.name:
          found = true
          output.add(&"  {cmdName} = cast[proc (")
          for arg in vkProc.args:
            if not output.endsWith("("):
              output.add(", ")
            output.add(&"{arg.name}: {arg.argType}")
          if vkProc.rval == "void":
            output.add(&")")
          else:
            output.add(&"): {vkProc.rVal}")
          output.add(&" {{.stdcall.}}](vkGetProc(\"{vkProc.name}\"))\n")
    if not found:
      output.add("  discard\n")

proc genExtensions(node: XmlNode, output: var string) =
  echo "Generating and Adding Extensions..."
  for extensions in node.findAll("extensions"):
    for extension in extensions.findAll("extension"):
      # if extension.attr("supported") == "disabled": continue
      # if extension.attr("api") == "vulkansc": continue
      var commands: seq[VkProc]
      for require in extension.findAll("require"):
        for command in require.findAll("command"):
          for vkProc in vkProcs:
            if vkProc.name == command.attr("name"):
              commands.add(vkProc)
      if commands.len == 0:
        continue
      let name = extension.attr("name")
      output.add(&"\n# Load {name}\n")
      output.add(&"proc load{name}*() =\n")
      for vkProc in commands:
        output.add(&"  {vkProc.name} = cast[proc (")
        for arg in vkProc.args:
          if not output.endsWith('('):
            output.add(", ")
          output.add(&"{arg.name}: {arg.argType}")
        if vkProc.rval == "void":
          output.add(&")")
        else:
          output.add(&"): {vkProc.rVal}")
        output.add(&" {{.stdcall.}}](vkGetProc(\"{vkProc.name}\"))\n")

proc isPlural(x: string): bool =
  # Determine if an identifier is plural
  x.endsWith("es") or (not x.endsWith("ss") and x.endsWith('s')) or
      endsWith(x.normalize, "data") or endsWith(x.normalize, "code")

proc isArray(x: VkArg): bool =
  x.name.isPlural() and x.name.startsWith('p') and
    (x.argType.startsWith("ptr") or x.argType == "cstringArray")

proc isCounter(x: string): bool =
  let x = x.normalize
  endsWith(x, "count") or endsWith(x, "size")

proc uncapitalizeAscii*(s: string): string =
  if s.len == 0: result = ""
  else: result = toLowerAscii(s[0]) & substr(s, 1)

proc toArgName(x: string): string =
  result = x
  result.removePrefix("p")
  result = uncapitalizeAscii(result)

proc isSpecialCase(x: VkStruct): bool =
  x.name in ["VkAccelerationStructureBuildGeometryInfoKHR",
        "VkMicromapBuildInfoEXT",
        "VkAccelerationStructureTrianglesOpacityMicromapEXT",
        "VkAccelerationStructureTrianglesDisplacementMicromapNV"]

proc isException(x: VkArg): bool =
  x.name in ["pWaitDstStageMask"]

proc genConstructors(node: XmlNode, output: var string) =
  echo "Generating and Adding Constructors..."
  output.add("\n# Constructors\n")
  for s in vkStructs:
    if s.members.len == 0:
      continue
    let isSpecialCase = isSpecialCase(s)
    output.add(&"\nproc new{s.name}*(")
    var foundMany = false
    for i, m in s.members:
      if m.name.isCounter() and
          i < s.members.high and s.members[i+1].isArray():
        foundMany = true
        continue
      if not output.endsWith('('):
        output.add(", ")
      if foundMany:
        var argType = m.argType
        argType.removePrefix("ptr ")
        if m.name == "pCode": argType = "char"
        if argType == "cstringArray": argType = "cstring"
        output.add(&"{m.name.toArgName}: openarray[{argType}]")
      else:
        output.add(&"{m.name}: {m.argType}")
      if m.name.contains("flags"):
        output.add(&" = 0.{m.argType}")
      if m.name == "sType":
        for structType in vkStructureTypes:
          let styp = s.name.substr(2)
          if structType.cmpIgnoreStyle(styp) == 0:
            output.add(&" = VkStructureType.{styp}")
      if not foundMany and m.argType == "pointer":
        output.add(" = nil")
      if foundMany and (i >= s.members.high or not (s.members[i+1].isArray() or
          s.members[i+1].isException)):
        foundMany = false
    output.add(&"): {s.name} =\n")
    output.add(&"  result = {s.name}(\n")
    foundMany = false
    for i, m in s.members:
      output.add("    ")
      if m.name.isCounter and
          i < s.members.high and s.members[i+1].isArray():
        output.add(&"{m.name}: ")
        if isSpecialCase:
          output.add(&"if len({s.members[i+1].name.toArgName}) == 0: ")
          output.add(&"len({s.members[i+2].name.toArgName}).{m.argType} ")
          output.add(&"else: len({s.members[i+1].name.toArgName}).{m.argType},\n")
        else:
          output.add(&"len({s.members[i+1].name.toArgName}).{m.argType},\n")
        foundMany = true
        continue
      if foundMany:
        output.add(&"{m.name}: if len({m.name.toArgName}) == 0: nil ")
        output.add(&"else: cast[{m.argType}]({m.name.toArgName}),\n")
      else:
        output.add(&"{m.name}: {m.name},\n")
      if foundMany and (i >= s.members.high or not (s.members[i+1].isArray() or
          s.members[i+1].isException)):
        foundMany = false
    output.add("  )\n")

proc main() =
  if not os.fileExists("vk.xml"):
    let client = newHttpClient()
    let glUrl = "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/xml/vk.xml"
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
  genHelpers(output)

  output.add("\n" & vkInit)
  output.add("\ninclude vulkan/headers\n")

  writeFile("../src/vulkan.nim", output)

if isMainModule:
  main()
