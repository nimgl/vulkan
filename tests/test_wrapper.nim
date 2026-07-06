import vulkan
import vulkan/wrapper

when isMainModule:
  var err: ref VulkanError
  doAssert err.isNil
  try:
    raiseVkError("boom", VkSuccess)
    doAssert false
  except VulkanError as e:
    doAssert e.res == VkSuccess
  echo "ok"
