# https://youtu.be/1BMGTyIF5dI
import std/[sequtils, math, strutils], chroma
import vulkan
import vulkan/wrapper

## Ported from https://github.com/planetis-m/mandelbrot/tree/master
##

type
  MandelbrotGenerator* = object
    width, height: int32
    workgroupSize: WorkgroupSize
    instance: VkInstance
    physicalDevice: VkPhysicalDevice
    device: VkDevice
    queue: VkQueue
    queueFamilyIndex: uint32
    storageBuffer: VkBuffer
    storageBufferMemory: VkDeviceMemory
    uniformBuffer: VkBuffer
    uniformBufferMemory: VkDeviceMemory
    descriptorSetLayout: VkDescriptorSetLayout
    descriptorPool: VkDescriptorPool
    descriptorSets: seq[VkDescriptorSet]
    pipelineLayout: VkPipelineLayout
    pipeline: VkPipeline
    commandPool: VkCommandPool
    commandBuffer: VkCommandBuffer
    when defined(vkDebug):
      debugUtilsMessenger: VkDebugUtilsMessengerEXT

  WorkgroupSize = object
    x, y: uint32

proc cleanup(x: MandelbrotGenerator) =
  # Clean up
  freeMemory(x.device, x.uniformBufferMemory)
  destroyBuffer(x.device, x.uniformBuffer)
  freeMemory(x.device, x.storageBufferMemory)
  destroyBuffer(x.device, x.storageBuffer)
  destroyPipeline(x.device, x.pipeline)
  destroyPipelineLayout(x.device, x.pipelineLayout)
  destroyDescriptorPool(x.device, x.descriptorPool)
  destroyDescriptorSetLayout(x.device, x.descriptorSetLayout)
  destroyCommandPool(x.device, x.commandPool)
  destroyDevice(x.device)
  when defined(vkDebug):
    destroyDebugUtilsMessenger(x.instance, x.debugUtilsMessenger)
  destroyInstance(x.instance)

proc newMandelbrotGenerator*(width, height: int32): MandelbrotGenerator =
  ## Create a generator with the width and the height of the image.
  result = MandelbrotGenerator(
    width: width,
    height: height,
    workgroupSize: WorkgroupSize(x: 32, y: 32)
  )

proc fetchRenderedImage(x: MandelbrotGenerator): seq[ColorRGBA] =
  let count = x.width*x.height
  let mappedMemory = mapMemory(x.device, x.storageBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(Color)*count), 0.VkMemoryMapFlags)
  let data = cast[ptr UncheckedArray[Color]](mappedMemory)
  result = newSeq[ColorRGBA](count)
  # Transform data from [0.0f, 1.0f] (float) to [0, 255] (uint8).
  for i in 0..result.high:
    result[i] = rgba(data[i])
  unmapMemory(x.device, x.storageBufferMemory)

proc getLayers(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add("VK_LAYER_KHRONOS_validation")

proc getExtensions(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)

proc createInstance(x: var MandelbrotGenerator) =
  # Create an ApplicationInfo struct
  let applicationInfo = newVkApplicationInfo(
    pApplicationName = "Mandelbrot",
    applicationVersion = vkMakeVersion(0, 1, 0, 0),
    pEngineName = "No Engine",
    engineVersion = vkMakeVersion(0, 1, 0, 0),
    apiVersion = vkApiVersion1_3
  )
  when defined(vkDebug):
    # Enable the Khronos validation layer
    let layerProperties = enumerateInstanceLayerProperties()
    let foundValidationLayer = layerProperties.anyIt(
        "VK_LAYER_KHRONOS_validation" == cast[cstring](it.layerName.addr))
    assert foundValidationLayer, "Validation layer required, but not available"
    # Shader printf is a feature of the validation layers that needs to be enabled
    let features = newVkValidationFeaturesEXT(
      enabledValidationFeatures = [VkValidationFeatureEnableEXT.DebugPrintf],
      disabledValidationFeatures = []
    )
  # Create a Vulkan instance
  let layers = getLayers()
  let extensions = getExtensions()
  let instanceCreateInfo = newVkInstanceCreateInfo(
    pNext = when defined(vkDebug): addr features else: nil,
    pApplicationInfo = applicationInfo.addr,
    pEnabledLayerNames = layers,
    pEnabledExtensionNames = extensions
  )
  x.instance = createInstance(instanceCreateInfo)

proc findPhysicalDevice(x: var MandelbrotGenerator) =
  # Enumerate physical devices
  let physicalDevices = enumeratePhysicalDevices(x.instance)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  # We simply choose the first available physical device.
  x.physicalDevice = physicalDevices[0]

proc getComputeQueueFamilyIndex(physicalDevice: VkPhysicalDevice): uint32 =
  # Find a compute queue family
  let queueFamilyProperties = getQueueFamilyProperties(physicalDevice)
  for i in 0 ..< queueFamilyProperties.len:
    let property = queueFamilyProperties[i]
    if property.queueCount > 0 and
        VkQueueFlagBits.ComputeBit in property.queueFlags:
      return i.uint32
  assert false, "Could not find a queue family that supports operations"

proc createDevice(x: var MandelbrotGenerator) =
  x.queueFamilyIndex = getComputeQueueFamilyIndex(x.physicalDevice)
  let queuePriority: array[1, float32] = [1.0]
  let queueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = x.queueFamilyIndex,
    queuePriorities = queuePriority
  )
  let layers = getLayers()
  # let features = VkPhysicalDeviceFeatures(
  #   robustBufferAccess: true.VkBool32,
  #   fragmentStoresAndAtomics: true.VkBool32,
  #   vertexPipelineStoresAndAtomics: true.VkBool32
  # )
  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfos = [queueCreateInfo],
    pEnabledLayerNames = layers,
    pEnabledExtensionNames = [],
    enabledFeatures = []
  )
  # Create a logical device
  x.device = createDevice(x.physicalDevice, deviceCreateInfo)
  # Get the compute queue
  x.queue = getDeviceQueue(x.device, x.queueFamilyIndex, 0)

proc findMemoryType(physicalDevice: VkPhysicalDevice, typeFilter: uint32,
    size: VkDeviceSize, properties: VkMemoryPropertyFlags): uint32 =
  # Find a suitable memory type for a Vulkan physical device
  let memoryProperties = getPhysicalDeviceMemoryProperties(physicalDevice)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    let memoryType = memoryProperties.memoryTypes[i]
    if (typeFilter and (1'u32 shl i.uint32)) != 0 and
        memoryType.propertyFlags >= properties and
        size <= memoryProperties.memoryHeaps[memoryType.heapIndex].size:
      return i.uint32
  assert false, "Failed to find suitable memory type"

proc createBuffer(x: MandelbrotGenerator, size: VkDeviceSize, usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferCreateInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = []
  )
  let buffer = createBuffer(x.device, bufferCreateInfo)
  # Memory requirements
  let bufferMemoryRequirements = getBufferMemoryRequirements(x.device, buffer)
  # Allocate memory for the buffer
  let allocInfo = newVkMemoryAllocateInfo(
    allocationSize = bufferMemoryRequirements.size,
    memoryTypeIndex = findMemoryType(x.physicalDevice,
                                     bufferMemoryRequirements.memoryTypeBits,
                                     bufferMemoryRequirements.size, properties)
  )
  let bufferMemory = allocateMemory(x.device, allocInfo)
  # Bind the memory to the buffer
  bindBufferMemory(x.device, buffer, bufferMemory, 0.VkDeviceSize)
  result = (buffer, bufferMemory)

proc createBuffers(x: var MandelbrotGenerator) =
  # Allocate memory for both buffers
  (x.storageBuffer, x.storageBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(float32)*4*x.width*x.height),
    VkBufferUsageFlags{StorageBufferBit},
    VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit})
  (x.uniformBuffer, x.uniformBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(int32)*2),
    VkBufferUsageFlags{UniformBufferBit},
    VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit})
  # Map the memory and write to the uniform buffer
  let mappedMemory = mapMemory(x.device, x.uniformBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(int32)*2), 0.VkMemoryMapFlags)
  let ubo = [x.width.int32, x.height.int32]
  copyMem(mappedMemory, ubo.addr, sizeof(int32)*2)
  unmapMemory(x.device, x.uniformBufferMemory)

proc createDescriptorSetLayout(x: var MandelbrotGenerator) =
  # Define the descriptor set layout bindings
  let bindings = [
    newVkDescriptorSetLayoutBinding(
      binding = 0,
      descriptorType = VkDescriptorType.StorageBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{ComputeBit},
      pImmutableSamplers = nil
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{ComputeBit},
      pImmutableSamplers = nil
    )
  ]
  # Create a descriptor set layout
  let createInfo = newVkDescriptorSetLayoutCreateInfo(
    bindings = bindings
  )
  x.descriptorSetLayout = createDescriptorSetLayout(x.device, createInfo)

proc createDescriptorSets(x: var MandelbrotGenerator) =
  # Create a descriptor pool
  let descriptorPoolSizes = [
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.StorageBuffer,
      descriptorCount = 1
    ),
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.UniformBuffer,
      descriptorCount = 1
    )
  ]
  let descriptorPoolCreateInfo = newVkDescriptorPoolCreateInfo(
    maxSets = 2,
    poolSizes = descriptorPoolSizes
  )
  x.descriptorPool = createDescriptorPool(x.device, descriptorPoolCreateInfo)
  # Allocate a descriptor set
  let descriptorSetAllocateInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = x.descriptorPool,
    setLayouts = [x.descriptorSetLayout]
  )
  let descriptorSet = allocateDescriptorSets(x.device, descriptorSetAllocateInfo)
  x.descriptorSets = @[descriptorSet]
  # Update the descriptor set with the buffer information
  let descriptorStorageBufferInfo = newVkDescriptorBufferInfo(
    buffer = x.storageBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(float32)*4*x.width*x.height)
  )
  let descriptorUniformBufferInfo = newVkDescriptorBufferInfo(
    buffer = x.uniformBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(int32)*2)
  )
  let writeDescriptorSets = [
    newVkWriteDescriptorSet(
      dstSet = x.descriptorSets[0],
      dstBinding = 0,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      pImageInfo = nil,
      pBufferInfo = descriptorStorageBufferInfo.addr,
      pTexelBufferView = nil
    ),
    newVkWriteDescriptorSet(
      dstSet = x.descriptorSets[0],
      dstBinding = 1,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = descriptorUniformBufferInfo.addr,
      pTexelBufferView = nil
    )
  ]
  updateDescriptorSets(x.device, writeDescriptorSets, [])

proc createComputePipeline(x: var MandelbrotGenerator) =
  # Create the shader module
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    code = readFile("examples/mandelbrot/build/shaders/mandelbrot.comp.spv")
  )
  let computeShaderModule = createShaderModule(x.device, shaderModuleCreateInfo)
  let specializationMapEntries = [
    newVkSpecializationMapEntry(
      constantID = 0,
      offset = offsetOf(WorkgroupSize, x).uint32,
      size = sizeof(uint32).uint
    ),
    newVkSpecializationMapEntry(
      constantID = 1,
      offset = offsetOf(WorkgroupSize, y).uint32,
      size = sizeof(uint32).uint
    )
  ]
  let specializationInfo = newVkSpecializationInfo(
    mapEntries = specializationMapEntries,
    dataSize = sizeof(WorkgroupSize).uint,
    pData = x.workgroupSize.addr
  )
  let shaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.ComputeBit,
    module = computeShaderModule,
    pName = "main",
    pSpecializationInfo = specializationInfo.addr
  )
  # Create a pipeline layout with the descriptor set layout
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [x.descriptorSetLayout],
    pushConstantRanges = []
  )
  x.pipelineLayout = createPipelineLayout(x.device, pipelineLayoutCreateInfo)
  # Create the compute pipeline
  let createInfos = [
    newVkComputePipelineCreateInfo(
      stage = shaderStageCreateInfo,
      layout = x.pipelineLayout,
      basePipelineHandle = 0.VkPipeline,
      basePipelineIndex = -1
    )
  ]
  x.pipeline = createComputePipelines(x.device, 0.VkPipelineCache, createInfos)
  destroyShaderModule(x.device, computeShaderModule)

proc createCommandBuffer(x: var MandelbrotGenerator) =
  # Create a command pool
  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = x.queueFamilyIndex
  )
  x.commandPool = createCommandPool(x.device, commandPoolCreateInfo)
  # Allocate a command buffer from the command pool
  let commandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = x.commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
  )
  x.commandBuffer = allocateCommandBuffers(x.device, commandBufferAllocateInfo)
  # Begin recording the command buffer
  let commandBufferBeginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags{OneTimeSubmitBit},
    pInheritanceInfo = nil
  )
  beginCommandBuffer(x.commandBuffer, commandBufferBeginInfo)
  # Bind the compute pipeline
  cmdBindPipeline(x.commandBuffer, VkPipelineBindPoint.Compute, x.pipeline)
  # Bind the descriptor set
  cmdBindDescriptorSets(x.commandBuffer, VkPipelineBindPoint.Compute,
                        x.pipelineLayout, 0, x.descriptorSets, [])
  # Dispatch the compute work
  let numWorkgroupX = ceilDiv(x.width.uint32, x.workgroupSize.x)
  let numWorkgroupY = ceilDiv(x.height.uint32, x.workgroupSize.y)
  cmdDispatch(x.commandBuffer, numWorkgroupX, numWorkgroupY, 1)
  # End recording the command buffer
  endCommandBuffer(x.commandBuffer)

proc submitCommandBuffer(x: MandelbrotGenerator) =
  let submitInfos = [
    newVkSubmitInfo(
      waitSemaphores = [],
      waitDstStageMask = [],
      commandBuffers = [x.commandBuffer],
      signalSemaphores = []
    )
  ]
  # Create a fence
  let fenceCreateInfo = newVkFenceCreateInfo()
  let fence = createFence(x.device, fenceCreateInfo)
  when defined(useRenderDoc): startFrameCapture(x.instance)
  # Submit the command buffer
  queueSubmit(x.queue, submitInfos, fence)
  when defined(useRenderDoc): endFrameCapture(x.instance)
  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  waitForFence(x.device, fence, true.VkBool32, high(uint64))
  destroyFence(x.device, fence)

when defined(vkDebug):
  proc debugCallback(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
                     messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
                     pCallbackData: ptr VkDebugUtilsMessengerCallbackDataEXT,
                     pUserData: pointer): VkBool32 {.cdecl.} =
    var message = $pCallbackData.pMessage
    if "WARNING-DEBUG-PRINTF" == pCallbackData.pMessageIdName:
      # Validation messages are a bit verbose.
      let delimiter = "| vkQueueSubmit():  "
      if (let pos = message.find(delimiter); pos >= 0):
        # Extract the part of the message after the delimiter
        message = message.substr(pos + len(delimiter))
    stderr.writeLine(message)
    return false.VkBool32

  proc setupDebugUtilsMessenger(x: var MandelbrotGenerator) =
    let severityFlags = VkDebugUtilsMessageSeverityFlagsEXT{
      VerboseBit, InfoBit, WarningBit, ErrorBit}
    let messageTypeFlags = VkDebugUtilsMessageTypeFlagsEXT{
      GeneralBit, ValidationBit, PerformanceBit}
    let createInfo = newVkDebugUtilsMessengerCreateInfoEXT(
      messageSeverity = severityFlags,
      messageType = messageTypeFlags,
      pfnUserCallback = debugCallback
    )
    x.debugUtilsMessenger = createDebugUtilsMessengerEXT(x.instance, createInfo)

proc generate*(x: var MandelbrotGenerator): seq[ColorRGBA] =
  ## Return the raw data of a mandelbrot image.
  try:
    vkPreload()
    # Hardware Setup Stage
    createInstance(x)
    vkInit(x.instance, load1_2 = false, load1_3 = false)
    when defined(vkDebug):
      loadVkExtDebugUtils()
      setupDebugUtilsMessenger(x)
    findPhysicalDevice(x)
    createDevice(x)
    # Resource Setup Stage
    createBuffers(x)
    # Pipeline Setup Stage
    createDescriptorSetLayout(x)
    createDescriptorSets(x)
    createComputePipeline(x)
    # Command Execution Stage
    createCommandBuffer(x)
    submitCommandBuffer(x)
    # Fetch data from VRAM to RAM.
    result = fetchRenderedImage(x)
  finally:
    cleanup(x)
