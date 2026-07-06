# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019
import std/algorithm

const
  srcHeader* = """
# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

## Vulkan Bindings
## ====
## WARNING: This is a generated file. Do not edit
## Any edits will be overwritten by the generator.

var vkGetProc: proc (procName: cstring): pointer {.cdecl.}
var currInst: pointer = nil

when not defined(vkCustomLoader):
  import dynlib

  when defined(windows):
    const vkDLL = "vulkan-1.dll"
  elif defined(macosx):
    const vkDLL = "libMoltenVK.dylib"
  else:
    const vkDLL = "libvulkan.so.1"

  let vkHandleDLL = loadLib(vkDLL)
  if isNil(vkHandleDLL):
    raise newException(LibraryError, "could not load: " & vkDLL)

  let vkGetProcAddress = cast[proc (inst: pointer, s: cstring): pointer {.stdcall.}](checkedSymAddr(vkHandleDLL, "vkGetInstanceProcAddr"))

  vkGetProc = proc (procName: cstring): pointer {.cdecl.} =
    result = vkGetProcAddress(currInst, procName)
    if result == nil:
      raiseInvalidLibrary(procName)

proc setVKGetProc*(getProc: proc (procName: cstring): pointer {.cdecl.}) =
  vkGetProc = getProc

type
  VkHandle* = uint
  VkNonDispatchableHandle* = uint
  ANativeWindow* = object
  AHardwareBuffer* = object
  CAMetalLayer* = object
  MTLDevice_id* = object
  MTLCommandQueue_id* = object
  MTLBuffer_id* = object
  MTLTexture_id* = object
  MTLSharedEvent_id* = object
  IOSurfaceRef* = object
"""

  vkInit* = """
var
  vkCreateInstance*: proc (pCreateInfo: ptr VkInstanceCreateInfo, pAllocator: ptr VkAllocationCallbacks, pInstance: ptr VkInstance): VkResult {.stdcall.}
  vkEnumerateInstanceExtensionProperties*: proc (pLayerName: cstring, pPropertyCount: ptr uint32, pProperties: ptr VkExtensionProperties): VkResult {.stdcall.}
  vkEnumerateInstanceLayerProperties*: proc (pPropertyCount: ptr uint32, pProperties: ptr VkLayerProperties): VkResult {.stdcall.}
  vkEnumerateInstanceVersion*: proc (pApiVersion: ptr uint32): VkResult {.stdcall.}

proc vkPreload*(load1_1: bool = true) =
  vkGetInstanceProcAddr = cast[proc (instance: VkInstance, pName: cstring): PFN_vkVoidFunction {.stdcall.}](symAddr(vkHandleDLL, "vkGetInstanceProcAddr"))

  vkCreateInstance = cast[proc (pCreateInfo: ptr VkInstanceCreateInfo, pAllocator: ptr VkAllocationCallbacks, pInstance: ptr VkInstance): VkResult {.stdcall.}](vkGetProc("vkCreateInstance"))
  vkEnumerateInstanceExtensionProperties = cast[proc (pLayerName: cstring, pPropertyCount: ptr uint32, pProperties: ptr VkExtensionProperties): VkResult {.stdcall.}](vkGetProc("vkEnumerateInstanceExtensionProperties"))
  vkEnumerateInstanceLayerProperties = cast[proc (pPropertyCount: ptr uint32, pProperties: ptr VkLayerProperties): VkResult {.stdcall.}](vkGetProc("vkEnumerateInstanceLayerProperties"))

  if load1_1:
    vkEnumerateInstanceVersion = cast[proc (pApiVersion: ptr uint32): VkResult {.stdcall.}](vkGetProc("vkEnumerateInstanceVersion"))

proc vkInit*(instance: VkInstance, load1_0 = true, load1_1: bool = true, load1_2 = true, load1_3: bool = true, load1_4: bool = true) =
  currInst = cast[pointer](instance)
  if currInst == nil:
    raise newException(NilAccessDefect, "Instance is nil")
  if load1_0:
    vkLoad1_0()
  if load1_1:
    vkLoad1_1()
  if load1_2:
    vkLoad1_2()
  when not defined(macosx):
    if load1_3:
      vkLoad1_3()
    if load1_4:
      vkLoad1_4()
"""

  keywords = ["addr", "and", "as", "asm",
    "bind", "block", "break",
    "case", "cast", "concept", "const", "continue", "converter",
    "defer", "discard", "distinct", "div", "do",
    "elif", "else", "end", "enum", "except", "export",
    "finally", "for", "from", "func",
    "if", "import", "in", "include", "interface", "is", "isnot", "iterator",
    "let",
    "macro", "method", "mixin", "mod",
    "nil", "not", "notin",
    "object", "of", "or", "out",
    "proc", "ptr",
    "raise", "ref", "return",
    "shl", "shr", "static",
    "template", "try", "tuple", "type",
    "using",
    "var",
    "when", "while",
    "xor",
    "yield"]

proc isKeyword*(s: string): bool {.inline.} =
  ## Checks if an indentifier is a Nim keyword
  binarySearch(keywords, s) >= 0
