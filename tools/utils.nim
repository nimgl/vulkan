# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

const srcHeader* = """
# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

## Vulkan Bindings
## ====
## WARNING: This is a generated file. Do not edit
## Any edits will be overwritten by the generator.

var vkGetProc: proc(procName: cstring): pointer {.cdecl.}
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
    quit("could not load: " & vkDLL)

  let vkGetProcAddress = cast[proc(inst: pointer, s: cstring): pointer {.stdcall.}](symAddr(vkHandleDLL, "vkGetInstanceProcAddr"))
  if vkGetProcAddress == nil:
    quit("failed to load `vkGetInstanceProcAddr` from " & vkDLL)

  vkGetProc = proc(procName: cstring): pointer {.cdecl.} =
    when defined(windows):
      result = vkGetProcAddress(currInst, procName)
      if result != nil:
        return
    result = symAddr(vkHandleDLL, procName)
    if result == nil:
      raiseInvalidLibrary(procName)

proc setVKGetProc*(getProc: proc(procName: cstring): pointer {.cdecl.}) =
  vkGetProc = getProc

type
  VkHandle* = int64
  VkNonDispatchableHandle* = uint64
  ANativeWindow = ptr object
  CAMetalLayer = ptr object
  AHardwareBuffer = ptr object
"""

const vkInit* = """
var
  vkCreateInstance*: proc(pCreateInfo: ptr VkInstanceCreateInfo , pAllocator: ptr VkAllocationCallbacks , pInstance: ptr VkInstance ): VkResult {.stdcall.}
  vkEnumerateInstanceExtensionProperties*: proc(pLayerName: cstring , pPropertyCount: ptr uint32 , pProperties: ptr VkExtensionProperties ): VkResult {.stdcall.}
  vkEnumerateInstanceLayerProperties*: proc(pPropertyCount: ptr uint32 , pProperties: ptr VkLayerProperties ): VkResult {.stdcall.}
  vkEnumerateInstanceVersion*: proc(pApiVersion: ptr uint32 ): VkResult {.stdcall.}

proc vkPreload*(load1_1: bool = true) =
  vkGetInstanceProcAddr = cast[proc(instance: VkInstance, pName: cstring ): PFN_vkVoidFunction {.stdcall.}](symAddr(vkHandleDLL, "vkGetInstanceProcAddr"))

  vkCreateInstance = cast[proc(pCreateInfo: ptr VkInstanceCreateInfo , pAllocator: ptr VkAllocationCallbacks , pInstance: ptr VkInstance ): VkResult {.stdcall.}](vkGetProc("vkCreateInstance"))
  vkEnumerateInstanceExtensionProperties = cast[proc(pLayerName: cstring , pPropertyCount: ptr uint32 , pProperties: ptr VkExtensionProperties ): VkResult {.stdcall.}](vkGetProc("vkEnumerateInstanceExtensionProperties"))
  vkEnumerateInstanceLayerProperties = cast[proc(pPropertyCount: ptr uint32 , pProperties: ptr VkLayerProperties ): VkResult {.stdcall.}](vkGetProc("vkEnumerateInstanceLayerProperties"))

  if load1_1:
    vkEnumerateInstanceVersion = cast[proc(pApiVersion: ptr uint32 ): VkResult {.stdcall.}](vkGetProc("vkEnumerateInstanceVersion"))

proc vkInit*(instance: VkInstance, load1_0: bool = true, load1_1: bool = true): bool =
  currInst = cast[pointer](instance)
  if load1_0:
    vkLoad1_0()
  when not defined(macosx):
    if load1_1:
      vkLoad1_1()
  return true
"""

let keywords* = ["addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept",
                 "const", "continue", "converter", "defer", "discard", "distinct", "div", "do",
                 "elif", "else", "end", "enum", "except", "export", "finally", "for", "from", "func",
                 "if", "import", "in", "include", "interface", "is", "isnot", "iterator", "let",
                 "macro", "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or",
                 "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static", "template",
                 "try", "tuple", "type", "using", "var", "when", "while", "xor", "yield"]
