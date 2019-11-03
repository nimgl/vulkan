import vulkan, glfw

proc keyProc(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32): void {.cdecl.} =
  if key == GLFWKey.Escape and action == GLFWPress:
    window.setWindowShouldClose(true)

proc main() =
  assert glfwInit()

  glfwWindowHint(GLFWResizable, GLFW_FALSE)
  glfwWindowHint(GLFWClientAPI, GLFW_NO_API)

  let w: GLFWWindow = glfwCreateWindow(800, 600)
  if w == nil:
    quit(-1)

  discard w.setKeyCallback(keyProc)
  w.makeContextCurrent()

  if not glfwVulkanSupported():
    echo "Vulkan is NOT Supported!"
    w.destroyWindow()
    glfwTerminate()
    return

  if not vkInit():
    echo "Failed to load Vulkan"

  while not w.windowShouldClose:
    glfwPollEvents()
    w.swapBuffers()

  w.destroyWindow()
  glfwTerminate()

main()
