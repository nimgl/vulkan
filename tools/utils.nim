# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

const srcHeader* = """
# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

## Vulkan Bindings
## ====
## WARNING: This is a generated file. Do not edit
## Any edits will be overwritten by the generator.

import strutils

var vkGetProc: proc(procName: cstring): pointer {.cdecl.}

when not defined(vkCustomLoader):
  import dynlib

  when defined(windows):
    const vkDLL = "vulkan-1.dll"
  elif defined(macosx):
    quit("MacOSX is not supported (for the moment)!")
  else:
    const vkDLL = "libvulkan.so.1"

  let vkHandleDLL = loadLib(vkDLL)
  if isNil(vkHandleDLL):
    quit("could not load: " & vkDLL)

  let vkGetProcAddress = cast[proc(s: cstring): pointer {.stdcall.}](symAddr(vkHandleDLL, "vkGetInstanceProcAddr"))
  if vkGetProcAddress == nil:
    quit("failed to load `vkGetInstanceProcAddr` from " & vkDLL)

  vkGetProc = proc(procName: cstring): pointer {.cdecl.} =
    result = vkGetProcAddress(procName)
    if result != nil:
      return
    result = symAddr(vkHandleDLL, procName)
    if result == nil:
      raiseInvalidLibrary(procName)

proc setVKGetProc*(getProc: proc(procName: cstring): pointer {.cdecl.}) =
  vkGetProc = getProc

type
  VkHandle* = int64
  VkNonDispatchableHandle* = int64
  ANativeWindow = ptr object
  wl_display = ptr object
  wl_surface = ptr object
  HWND = ptr object
  Display = ptr object
  Window = ptr object
  HINSTANCE = ptr object
  xcb_window_t = ptr object
  xcb_connection_t = ptr object
  zx_handle_t = ptr object
  GgpStreamDescriptor = ptr object
  HANDLE = ptr object
  SECURITY_ATTRIBUTES = ptr object
  DWORD = ptr object
  LPCWSTR = ptr object
  CAMetalLayer = ptr object
  AHardwareBuffer = ptr object
  GgpFrameToken = ptr object
  HMONITOR = ptr object
"""

let keywords* = ["addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept",
                 "const", "continue", "converter", "defer", "discard", "distinct", "div", "do",
                 "elif", "else", "end", "enum", "except", "export", "finally", "for", "from", "func",
                 "if", "import", "in", "include", "interface", "is", "isnot", "iterator", "let",
                 "macro", "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or",
                 "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static", "template",
                 "try", "tuple", "type", "using", "var", "when", "while", "xor", "yield"]
