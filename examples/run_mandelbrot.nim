import std/[strutils, os]
import sets
import chroma
import glfw
import glfw/wrapper as glfww
import vulkan
import vulkan/wrapper
import ./mandelbrot/mandelbrot

{.pragma: glfwImport, dynlib: "libglfw.so.3".}
proc glfwCreateWindowSurface*(instance: VkInstance, window: glfww.Window,
                              allocator: ptr VkAllocationCallbacks,
                              surface: ptr VkSurfaceKHR): VkResult
                              {.glfwImport, importc: "glfwCreateWindowSurface".}

const
  deviceExtensions = ["VK_KHR_swapchain"]


type
  QueueFamilyIndices = object
    graphicsFamily: uint32
    graphicsFamilyFound: bool
    presentFamily: uint32
    presentFamilyFound: bool

  SwapChainSupportDetails = object
    capabilities: VkSurfaceCapabilitiesKHR
    formats: seq[VkSurfaceFormatKHR]
    presentModes: seq[VkPresentModeKHR]

  SwapChain = object
    handle: VkSwapchainKHR
    images: seq[VkImage]
    format: VkFormat
    extent: VkExtent2D

proc isComplete(indices: QueueFamilyIndices): bool =
  indices.graphicsFamilyFound and indices.presentFamilyFound

proc findQueueFamilies(pDevice: VkPhysicalDevice, surface: VkSurfaceKHR): QueueFamilyIndices =
  var queueFamilyCount: uint32 = 0
  vkGetPhysicalDeviceQueueFamilyProperties(pDevice, queueFamilyCount.addr, nil)
  if queueFamilyCount == 0:
    return
  var queueFamilies = newSeq[VkQueueFamilyProperties](queueFamilyCount)
  vkGetPhysicalDeviceQueueFamilyProperties(pDevice, queueFamilyCount.addr, queueFamilies[0].addr)

  var index: uint32 = 0
  for queueFamily in queueFamilies:
    if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
      result.graphicsFamily = index
      result.graphicsFamilyFound = true
    var presentSupport: VkBool32
    discard vkGetPhysicalDeviceSurfaceSupportKHR(pDevice, index, surface, presentSupport.addr)
    if presentSupport.ord == 1:
      result.presentFamily = index
      result.presentFamilyFound = true
    if result.isComplete:
      break
    index.inc

proc checkDeviceExtensionSupport(pDevice: VkPhysicalDevice): bool =
  var extCount: uint32
  discard vkEnumerateDeviceExtensionProperties(pDevice, nil, extCount.addr, nil)
  var availableExts = newSeq[VkExtensionProperties](extCount)
  discard vkEnumerateDeviceExtensionProperties(pDevice, nil, extCount.addr, availableExts[0].addr)

  var requiredExts = deviceExtensions.toHashSet
  for ext in availableExts.mitems:
    requiredExts.excl($cast[cstring](ext.extensionName.addr))
  requiredExts.len == 0

proc querySwapChainSupport(pDevice: VkPhysicalDevice, surface: VkSurfaceKHR): SwapChainSupportDetails =
  discard vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pDevice, surface, result.capabilities.addr)
  var formatCount: uint32
  discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, surface, formatCount.addr, nil)
  if formatCount != 0:
    result.formats.setLen(formatCount)
    discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, surface, formatCount.addr, result.formats[0].addr)
  var presentModeCount: uint32
  discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, surface, presentModeCount.addr, nil)
  if presentModeCount != 0:
    result.presentModes.setLen(presentModeCount)
    discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, surface, presentModeCount.addr, result.presentModes[0].addr)

proc isDeviceSuitable(pDevice: VkPhysicalDevice, surface: VkSurfaceKHR): bool =
  let indices: QueueFamilyIndices = findQueueFamilies(pDevice, surface)
  let extsSupported = pDevice.checkDeviceExtensionSupport
  var swapChainAdequate = false
  if extsSupported:
    let swapChainSupport = querySwapChainSupport(pDevice, surface)
    swapChainAdequate =
      swapChainSupport.formats.len != 0 and
      swapChainSupport.presentModes.len != 0
  indices.isComplete and extsSupported and swapChainAdequate

proc chooseSwapSurfaceFormat(availableFormats: seq[VkSurfaceFormatKHR]): VkSurfaceFormatKHR =
  for availableFormat in availableFormats:
    if availableFormat.format == VK_FORMAT_R8G8B8A8_UNORM and
        availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return availableFormat
  for availableFormat in availableFormats:
    if availableFormat.format == VK_FORMAT_B8G8R8A8_UNORM and
        availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return availableFormat
  availableFormats[0]

proc chooseSwapPresentMode(availablePresentModes: seq[VkPresentModeKHR]): VkPresentModeKHR =
  for presentMode in availablePresentModes:
    if presentMode == VK_PRESENT_MODE_MAILBOX_KHR:
      return presentMode
  VK_PRESENT_MODE_FIFO_KHR

proc chooseSwapExtent(capabilities: VkSurfaceCapabilitiesKHR, width, height: int32): VkExtent2D =
  if capabilities.currentExtent.width != 0xFFFFFFFF'u32:
    return capabilities.currentExtent
  result.width = width.uint32
  result.height = height.uint32
  result.width = max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, result.width))
  result.height = max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, result.height))

proc createSwapChain(device: VkDevice, physicalDevice: VkPhysicalDevice,
                     surface: VkSurfaceKHR, width, height: int32): SwapChain =
  let
    swapChainSupport = querySwapChainSupport(physicalDevice, surface)
    surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats)
    presentMode = chooseSwapPresentMode(swapChainSupport.presentModes)
    extent = chooseSwapExtent(swapChainSupport.capabilities, width, height)
  var imageCount = swapChainSupport.capabilities.minImageCount + 1
  if swapChainSupport.capabilities.maxImageCount > 0 and
      imageCount > swapChainSupport.capabilities.maxImageCount:
    imageCount = swapChainSupport.capabilities.maxImageCount

  let indices = findQueueFamilies(physicalDevice, surface)
  let queueFamilyIndices =
    if indices.graphicsFamily != indices.presentFamily:
      @[indices.graphicsFamily, indices.presentFamily]
    else:
      @[]

  var createInfo = newVkSwapchainCreateInfoKHR(
    surface = surface,
    minImageCount = imageCount,
    imageFormat = surfaceFormat.format,
    imageColorSpace = surfaceFormat.colorSpace,
    imageExtent = extent,
    imageArrayLayers = 1,
    imageUsage = VkImageUsageFlags{TransferDstBit},
    imageSharingMode = if queueFamilyIndices.len > 0:
      VK_SHARING_MODE_CONCURRENT else: VK_SHARING_MODE_EXCLUSIVE,
    queueFamilyIndices = queueFamilyIndices,
    preTransform = swapChainSupport.capabilities.currentTransform,
    compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    presentMode = presentMode,
    clipped = VkBool32(VK_TRUE),
    oldSwapchain = VkSwapchainKHR(0)
  )

  checkVkResult vkCreateSwapchainKHR(device, createInfo.addr, nil, result.handle.addr)
  discard vkGetSwapchainImagesKHR(device, result.handle, imageCount.addr, nil)
  result.images.setLen(imageCount)
  discard vkGetSwapchainImagesKHR(device, result.handle, imageCount.addr, result.images[0].addr)
  result.format = surfaceFormat.format
  result.extent = extent

proc findMemoryType(physicalDevice: VkPhysicalDevice, typeFilter: uint32,
                    properties: VkMemoryPropertyFlags): uint32 =
  let memoryProperties = getPhysicalDeviceMemoryProperties(physicalDevice)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    let memoryType = memoryProperties.memoryTypes[i]
    if (typeFilter and (1'u32 shl i.uint32)) != 0 and
        memoryType.propertyFlags >= properties:
      return i.uint32
  raise newException(Exception, "Failed to find suitable memory type")

proc createBuffer(device: VkDevice, physicalDevice: VkPhysicalDevice,
                  size: VkDeviceSize, usage: VkBufferUsageFlags,
                  properties: VkMemoryPropertyFlags): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferCreateInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = []
  )
  let buffer = createBuffer(device, bufferCreateInfo)
  let bufferMemoryRequirements = getBufferMemoryRequirements(device, buffer)
  let allocInfo = newVkMemoryAllocateInfo(
    allocationSize = bufferMemoryRequirements.size,
    memoryTypeIndex = findMemoryType(physicalDevice,
                                     bufferMemoryRequirements.memoryTypeBits,
                                     properties)
  )
  let bufferMemory = allocateMemory(device, allocInfo)
  bindBufferMemory(device, buffer, bufferMemory, 0.VkDeviceSize)
  result = (buffer, bufferMemory)

proc toPixelBytes(pixels: seq[ColorRGBA], format: VkFormat): seq[uint8] =
  result = newSeq[uint8](pixels.len * 4)
  let useBgra = format == VK_FORMAT_B8G8R8A8_UNORM
  for i, p in pixels:
    let base = i * 4
    if useBgra:
      result[base] = p.b
      result[base + 1] = p.g
      result[base + 2] = p.r
      result[base + 3] = p.a
    else:
      result[base] = p.r
      result[base + 1] = p.g
      result[base + 2] = p.b
      result[base + 3] = p.a

proc recordCopy(cmd: VkCommandBuffer, image: VkImage, extent: VkExtent2D,
                buffer: VkBuffer) =
  let beginInfo = newVkCommandBufferBeginInfo(pInheritanceInfo = nil)
  checkVkResult vkBeginCommandBuffer(cmd, beginInfo.addr)

  var barrierToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    srcAccessMask: 0.VkAccessFlags,
    dstAccessMask: VkAccessFlags{TransferWriteBit},
    oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags{ColorBit},
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: 1
    )
  )

  vkCmdPipelineBarrier(
    cmd,
    VkPipelineStageFlags{TopOfPipeBit},
    VkPipelineStageFlags{TransferBit},
    0.VkDependencyFlags,
    0, nil,
    0, nil,
    1, barrierToTransfer.addr
  )

  var region = VkBufferImageCopy(
    bufferOffset: 0.VkDeviceSize,
    bufferRowLength: 0,
    bufferImageHeight: 0,
    imageSubresource: VkImageSubresourceLayers(
      aspectMask: VkImageAspectFlags{ColorBit},
      mipLevel: 0,
      baseArrayLayer: 0,
      layerCount: 1
    ),
    imageOffset: VkOffset3D(x: 0, y: 0, z: 0),
    imageExtent: VkExtent3D(width: extent.width, height: extent.height, depth: 1)
  )

  vkCmdCopyBufferToImage(
    cmd,
    buffer,
    image,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    1,
    region.addr
  )

  var barrierToPresent = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{MemoryReadBit},
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    newLayout: VkImageLayout.PresentSrcKhr,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags{ColorBit},
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: 1
    )
  )

  vkCmdPipelineBarrier(
    cmd,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{BottomOfPipeBit},
    0.VkDependencyFlags,
    0, nil,
    0, nil,
    1, barrierToPresent.addr
  )

  checkVkResult vkEndCommandBuffer(cmd)

proc main(params: seq[string]) =
  if params.len notin [0, 2]:
    quit("Usage: mandelbrot <width> <height>")

  let width = if params.len == 0: 800 else: params[0].parseInt
  let height = if params.len == 0: 600 else: params[1].parseInt

  var generator = newMandelbrotGenerator(width.int32, height.int32)
  let pixels = generator.generate()
  doAssert pixels.len == width * height

  glfw.initialize()
  glfww.windowHint(glfww.hClientApi.int32, glfww.oaNoApi.int32)
  glfww.windowHint(glfww.hResizable.int32, 0)

  let handle = glfww.createWindow(width.int32, height.int32, "Mandelbrot", nil, nil)
  if handle.isNil:
    glfw.terminate()
    quit("failed to create window")

  let window = newWindow(handle)

  vkPreload()
  let
    glfwExtensionCount = block:
      var count: uint32 = 0
      discard glfww.getRequiredInstanceExtensions(count.addr)
      count
    glfwExtensions = glfww.getRequiredInstanceExtensions(glfwExtensionCount.addr)

  let instance = block:
    let appInfo = newVkApplicationInfo(
      pApplicationName = "Mandelbrot",
      applicationVersion = vkMakeVersion(0, 1, 0, 0),
      pEngineName = "No Engine",
      engineVersion = vkMakeVersion(0, 1, 0, 0),
      apiVersion = vkApiVersion1_1
    )
    var extensionNames = newSeq[cstring](glfwExtensionCount.int)
    for i in 0..<glfwExtensionCount.int:
      extensionNames[i] = glfwExtensions[i]
    let instanceCreateInfo = newVkInstanceCreateInfo(
      pApplicationInfo = appInfo.addr,
      pEnabledLayerNames = [],
      pEnabledExtensionNames = extensionNames
    )
    createInstance(instanceCreateInfo)

  vkInit(instance, load1_2 = false, load1_3 = false)
  loadVK_KHR_surface()

  var surface: VkSurfaceKHR
  checkVkResult glfwCreateWindowSurface(instance, window.getHandle(), nil, surface.addr)

  var physicalDevice: VkPhysicalDevice
  block:
    var deviceCount: uint32 = 0
    discard vkEnumeratePhysicalDevices(instance, deviceCount.addr, nil)
    var devices = newSeq[VkPhysicalDevice](deviceCount)
    discard vkEnumeratePhysicalDevices(instance, deviceCount.addr, devices[0].addr)
    for pDevice in devices:
      if isDeviceSuitable(pDevice, surface):
        physicalDevice = pDevice
        break
    if physicalDevice == VkPhysicalDevice(0):
      quit("Suitable physical device not found")

  let indices = findQueueFamilies(physicalDevice, surface)
  let uniqueQueueFamilies = [indices.graphicsFamily, indices.presentFamily].toHashSet

  var queuePriority = 1f
  var queueCreateInfos = newSeq[VkDeviceQueueCreateInfo]()
  for queueFamily in uniqueQueueFamilies:
    let deviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
      queueFamilyIndex = queueFamily,
      queuePriorities = [queuePriority]
    )
    queueCreateInfos.add(deviceQueueCreateInfo)

  var deviceExts = newSeq[cstring](deviceExtensions.len)
  for i, ext in deviceExtensions:
    deviceExts[i] = ext.cstring

  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfos = queueCreateInfos,
    enabledFeatures = [],
    pEnabledLayerNames = [],
    pEnabledExtensionNames = deviceExts
  )

  var device = createDevice(physicalDevice, deviceCreateInfo)
  var graphicsQueue: VkQueue
  var presentQueue: VkQueue
  vkGetDeviceQueue(device, indices.graphicsFamily, 0, graphicsQueue.addr)
  vkGetDeviceQueue(device, indices.presentFamily, 0, presentQueue.addr)

  loadVK_KHR_swapchain()
  let swapChain = createSwapChain(device, physicalDevice, surface, width.int32, height.int32)

  let pixelBytes = toPixelBytes(pixels, swapChain.format)
  let bufferSize = VkDeviceSize(pixelBytes.len)
  let (stagingBuffer, stagingMemory) = createBuffer(
    device,
    physicalDevice,
    bufferSize,
    VkBufferUsageFlags{TransferSrcBit},
    VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit}
  )

  let mappedMemory = mapMemory(device, stagingMemory, 0.VkDeviceSize, bufferSize, 0.VkMemoryMapFlags)
  copyMem(mappedMemory, pixelBytes[0].addr, pixelBytes.len)
  unmapMemory(device, stagingMemory)

  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = indices.graphicsFamily,
    flags = VkCommandPoolCreateFlags{ResetCommandBufferBit}
  )
  var commandPool: VkCommandPool
  checkVkResult vkCreateCommandPool(device, commandPoolCreateInfo.addr, nil, commandPool.addr)

  let allocInfo = newVkCommandBufferAllocateInfo(
    commandPool = commandPool,
    level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount = 1
  )
  var commandBuffer: VkCommandBuffer
  checkVkResult vkAllocateCommandBuffers(device, allocInfo.addr, commandBuffer.addr)

  let semaphoreInfo = newVkSemaphoreCreateInfo()
  var imageAvailableSemaphore: VkSemaphore
  var renderFinishedSemaphore: VkSemaphore
  checkVkResult vkCreateSemaphore(device, semaphoreInfo.addr, nil, imageAvailableSemaphore.addr)
  checkVkResult vkCreateSemaphore(device, semaphoreInfo.addr, nil, renderFinishedSemaphore.addr)

  let fenceInfo = newVkFenceCreateInfo(flags = VkFenceCreateFlags{SignaledBit})
  var inFlightFence: VkFence
  checkVkResult vkCreateFence(device, fenceInfo.addr, nil, inFlightFence.addr)

  while not window.shouldClose:
    if window.isKeyDown(keyEscape):
      window.shouldClose = true

    pollEvents()

    checkVkResult vkWaitForFences(device, 1, inFlightFence.addr, VkBool32(VK_TRUE), high(uint64))
    checkVkResult vkResetFences(device, 1, inFlightFence.addr)

    var imageIndex: uint32 = 0
    checkVkResult vkAcquireNextImageKHR(device, swapChain.handle, high(uint64),
      imageAvailableSemaphore, VkFence(0), imageIndex.addr)

    checkVkResult vkResetCommandBuffer(commandBuffer, 0.VkCommandBufferResetFlags)
    recordCopy(commandBuffer, swapChain.images[imageIndex.int], swapChain.extent, stagingBuffer)

    let submitInfo = newVkSubmitInfo(
      waitSemaphores = [imageAvailableSemaphore],
      waitDstStageMask = [VkPipelineStageFlags{TransferBit}],
      commandBuffers = [commandBuffer],
      signalSemaphores = [renderFinishedSemaphore]
    )
    checkVkResult vkQueueSubmit(graphicsQueue, 1, submitInfo.addr, inFlightFence)

    let presentInfo = newVkPresentInfoKHR(
      waitSemaphores = [renderFinishedSemaphore],
      swapchains = [swapChain.handle],
      imageIndices = [imageIndex],
      results = @[]
    )
    discard vkQueuePresentKHR(presentQueue, presentInfo.addr)

  checkVkResult vkDeviceWaitIdle(device)

  vkDestroyFence(device, inFlightFence, nil)
  vkDestroySemaphore(device, renderFinishedSemaphore, nil)
  vkDestroySemaphore(device, imageAvailableSemaphore, nil)
  vkDestroyCommandPool(device, commandPool, nil)
  destroyBuffer(device, stagingBuffer)
  freeMemory(device, stagingMemory)
  vkDestroySwapchainKHR(device, swapChain.handle, nil)
  vkDestroySurfaceKHR(instance, surface, nil)
  destroyDevice(device)
  destroyInstance(instance)
  window.destroy()
  glfw.terminate()

when isMainModule:
  try:
    main(commandLineParams())
  except:
    quit("unknown exception: " & getCurrentExceptionMsg())
