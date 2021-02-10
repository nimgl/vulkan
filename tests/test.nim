import nimgl/glfw
from nimgl/vulkan import nil
from triangle import nil

proc keyCallback(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
  if action == GLFW_PRESS and key == GLFWKey.Escape:
    window.setWindowShouldClose(true)

if isMainModule:
  doAssert glfwInit()

  glfwWindowHint(GLFWClientApi, GLFWNoApi)
  glfwWindowHint(GLFWResizable, GLFWFalse)

  var w = glfwCreateWindow(triangle.WIDTH, triangle.HEIGHT, "Vulkan Triangle")
  if w == nil:
    quit(-1)

  discard w.setKeyCallback(keyCallback)

  proc createSurface(instance: vulkan.VkInstance): vulkan.VkSurfaceKHR =
    if glfwCreateWindowSurface(instance, w, nil, result.addr) != vulkan.VKSuccess:
      quit("failed to create surface")

  var glfwExtensionCount: uint32 = 0
  var glfwExtensions: cstringArray
  glfwExtensions = glfwGetRequiredInstanceExtensions(glfwExtensionCount.addr)
  triangle.init(glfwExtensions, glfwExtensionCount, createSurface)

  while not w.windowShouldClose():
    glfwPollEvents()
    triangle.tick()

  triangle.deinit()
  w.destroyWindow()
  glfwTerminate()
