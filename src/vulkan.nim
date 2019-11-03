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

# Types

template vkMakeVersion*(major, minor, patch: untyped): untyped =
  (((major) shl 22) or ((minor) shl 12) or (patch))

template vkVersionMajor*(version: untyped): untyped =
  ((uint32)(version) shr 22)

template vkVersionMinor*(version: untyped): untyped =
  (((uint32)(version) shr 12) and 0x000003FF)

template vkVersionPatch*(version: untyped): untyped =
  ((uint32)(version) and 0x00000FFF)

const vkApiVersion1_0* = vkMakeVersion(1, 0, 0)
const vkApiVersion1_1* = vkMakeVersion(1, 1, 0)

type
  VkSampleMask* = distinct uint32
  VkBool32* = distinct uint32
  VkFlags* = distinct uint32
  VkDeviceSize* = distinct uint64
  VkDeviceAddress* = distinct uint64
  VkFramebufferCreateFlags* = distinct VkFlags
  VkQueryPoolCreateFlags* = distinct VkFlags
  VkRenderPassCreateFlags* = distinct VkFlags
  VkSamplerCreateFlags* = distinct VkFlags
  VkPipelineLayoutCreateFlags* = distinct VkFlags
  VkPipelineCacheCreateFlags* = distinct VkFlags
  VkPipelineDepthStencilStateCreateFlags* = distinct VkFlags
  VkPipelineDynamicStateCreateFlags* = distinct VkFlags
  VkPipelineColorBlendStateCreateFlags* = distinct VkFlags
  VkPipelineMultisampleStateCreateFlags* = distinct VkFlags
  VkPipelineRasterizationStateCreateFlags* = distinct VkFlags
  VkPipelineViewportStateCreateFlags* = distinct VkFlags
  VkPipelineTessellationStateCreateFlags* = distinct VkFlags
  VkPipelineInputAssemblyStateCreateFlags* = distinct VkFlags
  VkPipelineVertexInputStateCreateFlags* = distinct VkFlags
  VkPipelineShaderStageCreateFlags* = distinct VkFlags
  VkDescriptorSetLayoutCreateFlags* = distinct VkFlags
  VkBufferViewCreateFlags* = distinct VkFlags
  VkInstanceCreateFlags* = distinct VkFlags
  VkDeviceCreateFlags* = distinct VkFlags
  VkDeviceQueueCreateFlags* = distinct VkFlags
  VkQueueFlags* = distinct VkFlags
  VkMemoryPropertyFlags* = distinct VkFlags
  VkMemoryHeapFlags* = distinct VkFlags
  VkAccessFlags* = distinct VkFlags
  VkBufferUsageFlags* = distinct VkFlags
  VkBufferCreateFlags* = distinct VkFlags
  VkShaderStageFlags* = distinct VkFlags
  VkImageUsageFlags* = distinct VkFlags
  VkImageCreateFlags* = distinct VkFlags
  VkImageViewCreateFlags* = distinct VkFlags
  VkPipelineCreateFlags* = distinct VkFlags
  VkColorComponentFlags* = distinct VkFlags
  VkFenceCreateFlags* = distinct VkFlags
  VkSemaphoreCreateFlags* = distinct VkFlags
  VkFormatFeatureFlags* = distinct VkFlags
  VkQueryControlFlags* = distinct VkFlags
  VkQueryResultFlags* = distinct VkFlags
  VkShaderModuleCreateFlags* = distinct VkFlags
  VkEventCreateFlags* = distinct VkFlags
  VkCommandPoolCreateFlags* = distinct VkFlags
  VkCommandPoolResetFlags* = distinct VkFlags
  VkCommandBufferResetFlags* = distinct VkFlags
  VkCommandBufferUsageFlags* = distinct VkFlags
  VkQueryPipelineStatisticFlags* = distinct VkFlags
  VkMemoryMapFlags* = distinct VkFlags
  VkImageAspectFlags* = distinct VkFlags
  VkSparseMemoryBindFlags* = distinct VkFlags
  VkSparseImageFormatFlags* = distinct VkFlags
  VkSubpassDescriptionFlags* = distinct VkFlags
  VkPipelineStageFlags* = distinct VkFlags
  VkSampleCountFlags* = distinct VkFlags
  VkAttachmentDescriptionFlags* = distinct VkFlags
  VkStencilFaceFlags* = distinct VkFlags
  VkCullModeFlags* = distinct VkFlags
  VkDescriptorPoolCreateFlags* = distinct VkFlags
  VkDescriptorPoolResetFlags* = distinct VkFlags
  VkDependencyFlags* = distinct VkFlags
  VkSubgroupFeatureFlags* = distinct VkFlags
  VkIndirectCommandsLayoutUsageFlagsNVX* = distinct VkFlags
  VkObjectEntryUsageFlagsNVX* = distinct VkFlags
  VkGeometryFlagsNV* = distinct VkFlags
  VkGeometryInstanceFlagsNV* = distinct VkFlags
  VkBuildAccelerationStructureFlagsNV* = distinct VkFlags
  VkDescriptorUpdateTemplateCreateFlags* = distinct VkFlags
  VkDescriptorUpdateTemplateCreateFlagsKHR* = VkDescriptorUpdateTemplateCreateFlags
  VkPipelineCreationFeedbackFlagsEXT* = distinct VkFlags
  VkPipelineCompilerControlFlagsAMD* = distinct VkFlags
  VkShaderCorePropertiesFlagsAMD* = distinct VkFlags
  VkSemaphoreWaitFlagsKHR* = distinct VkFlags
  VkCompositeAlphaFlagsKHR* = distinct VkFlags
  VkDisplayPlaneAlphaFlagsKHR* = distinct VkFlags
  VkSurfaceTransformFlagsKHR* = distinct VkFlags
  VkSwapchainCreateFlagsKHR* = distinct VkFlags
  VkDisplayModeCreateFlagsKHR* = distinct VkFlags
  VkDisplaySurfaceCreateFlagsKHR* = distinct VkFlags
  VkAndroidSurfaceCreateFlagsKHR* = distinct VkFlags
  VkViSurfaceCreateFlagsNN* = distinct VkFlags
  VkWaylandSurfaceCreateFlagsKHR* = distinct VkFlags
  VkWin32SurfaceCreateFlagsKHR* = distinct VkFlags
  VkXlibSurfaceCreateFlagsKHR* = distinct VkFlags
  VkXcbSurfaceCreateFlagsKHR* = distinct VkFlags
  VkIOSSurfaceCreateFlagsMVK* = distinct VkFlags
  VkMacOSSurfaceCreateFlagsMVK* = distinct VkFlags
  VkMetalSurfaceCreateFlagsEXT* = distinct VkFlags
  VkImagePipeSurfaceCreateFlagsFUCHSIA* = distinct VkFlags
  VkStreamDescriptorSurfaceCreateFlagsGGP* = distinct VkFlags
  VkHeadlessSurfaceCreateFlagsEXT* = distinct VkFlags
  VkPeerMemoryFeatureFlags* = distinct VkFlags
  VkPeerMemoryFeatureFlagsKHR* = VkPeerMemoryFeatureFlags
  VkMemoryAllocateFlags* = distinct VkFlags
  VkMemoryAllocateFlagsKHR* = VkMemoryAllocateFlags
  VkDeviceGroupPresentModeFlagsKHR* = distinct VkFlags
  VkDebugReportFlagsEXT* = distinct VkFlags
  VkCommandPoolTrimFlags* = distinct VkFlags
  VkCommandPoolTrimFlagsKHR* = VkCommandPoolTrimFlags
  VkExternalMemoryHandleTypeFlagsNV* = distinct VkFlags
  VkExternalMemoryFeatureFlagsNV* = distinct VkFlags
  VkExternalMemoryHandleTypeFlags* = distinct VkFlags
  VkExternalMemoryHandleTypeFlagsKHR* = VkExternalMemoryHandleTypeFlags
  VkExternalMemoryFeatureFlags* = distinct VkFlags
  VkExternalMemoryFeatureFlagsKHR* = VkExternalMemoryFeatureFlags
  VkExternalSemaphoreHandleTypeFlags* = distinct VkFlags
  VkExternalSemaphoreHandleTypeFlagsKHR* = VkExternalSemaphoreHandleTypeFlags
  VkExternalSemaphoreFeatureFlags* = distinct VkFlags
  VkExternalSemaphoreFeatureFlagsKHR* = VkExternalSemaphoreFeatureFlags
  VkSemaphoreImportFlags* = distinct VkFlags
  VkSemaphoreImportFlagsKHR* = VkSemaphoreImportFlags
  VkExternalFenceHandleTypeFlags* = distinct VkFlags
  VkExternalFenceHandleTypeFlagsKHR* = VkExternalFenceHandleTypeFlags
  VkExternalFenceFeatureFlags* = distinct VkFlags
  VkExternalFenceFeatureFlagsKHR* = VkExternalFenceFeatureFlags
  VkFenceImportFlags* = distinct VkFlags
  VkFenceImportFlagsKHR* = VkFenceImportFlags
  VkSurfaceCounterFlagsEXT* = distinct VkFlags
  VkPipelineViewportSwizzleStateCreateFlagsNV* = distinct VkFlags
  VkPipelineDiscardRectangleStateCreateFlagsEXT* = distinct VkFlags
  VkPipelineCoverageToColorStateCreateFlagsNV* = distinct VkFlags
  VkPipelineCoverageModulationStateCreateFlagsNV* = distinct VkFlags
  VkPipelineCoverageReductionStateCreateFlagsNV* = distinct VkFlags
  VkValidationCacheCreateFlagsEXT* = distinct VkFlags
  VkDebugUtilsMessageSeverityFlagsEXT* = distinct VkFlags
  VkDebugUtilsMessageTypeFlagsEXT* = distinct VkFlags
  VkDebugUtilsMessengerCreateFlagsEXT* = distinct VkFlags
  VkDebugUtilsMessengerCallbackDataFlagsEXT* = distinct VkFlags
  VkPipelineRasterizationConservativeStateCreateFlagsEXT* = distinct VkFlags
  VkDescriptorBindingFlagsEXT* = distinct VkFlags
  VkConditionalRenderingFlagsEXT* = distinct VkFlags
  VkResolveModeFlagsKHR* = distinct VkFlags
  VkPipelineRasterizationStateStreamCreateFlagsEXT* = distinct VkFlags
  VkPipelineRasterizationDepthClipStateCreateFlagsEXT* = distinct VkFlags
  VkSwapchainImageUsageFlagsANDROID* = distinct VkFlags
