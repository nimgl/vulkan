import glfw
import glfw/wrapper as glfww
import vulkan
import vulkan/wrapper
import ../tests/triangle

{.pragma: glfwImport, dynlib: "libglfw.so.3".}
proc glfwCreateWindowSurface*(instance: VkInstance, window: glfww.Window, allocator: ptr VkAllocationCallbacks, surface: ptr VkSurfaceKHR): VkResult {.glfwImport, importc: "glfwCreateWindowSurface".}

when isMainModule:
  glfw.initialize()
  glfww.windowHint(glfww.hClientApi.int32, glfww.oaNoApi.int32)
  glfww.windowHint(glfww.hResizable.int32, 0)

  let handle = glfww.createWindow(triangle.WIDTH.int32, triangle.HEIGHT.int32, "Vulkan Triangle", nil, nil)
  if handle.isNil:
    glfw.terminate()
    quit(-1)

  var w = newWindow(handle)

  proc createSurface(instance: VkInstance): VkSurfaceKHR =
    checkVkResult glfwCreateWindowSurface(instance, w.getHandle(), nil, result.addr)

  var glfwExtensionCount: uint32 = 0
  var glfwExtensions: cstringArray
  glfwExtensions = glfww.getRequiredInstanceExtensions(glfwExtensionCount.addr)
  triangle.init(glfwExtensions, glfwExtensionCount, createSurface)

  while not w.shouldClose:
    if w.isKeyDown(keyEscape):
      w.shouldClose = true
    pollEvents()
    triangle.tick()

  triangle.deinit()
  w.destroy()
  glfw.terminate()
