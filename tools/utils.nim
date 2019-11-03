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

  let vkHandle = loadLib(vkDLL)
  if isNil(vkHandle):
    quit("could not load: " & vkDLL)

  let vkGetProcAddress = cast[proc(s: cstring): pointer {.stdcall.}](symAddr(vkHandle, "vkGetInstanceProcAddr"))
  if vkGetProcAddress == nil:
    quit("failed to load `vkGetInstanceProcAddr` from " & vkDLL)

  vkGetProc = proc(procName: cstring): pointer {.cdecl.} =
    result = vkGetProcAddress(procName)
    if result != nil:
      return
    result = symAddr(vkHandle, procName)
    if result == nil:
      raiseInvalidLibrary(procName)

proc setVKGetProc*(getProc: proc(procName: cstring): pointer {.cdecl.}) =
  vkGetProc = getProc
"""
