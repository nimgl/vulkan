# Package
version       = "0.1.0"
author        = "Antonis Geralis"
description   = "Vulkan compute example"
license       = "Public Domain"

# Dependencies
requires "nim >= 2.1.0"
requires "pixie >= 5.0.7"
requires "https://github.com/planetis-m/vulkan.git >= 1.3.279"

include "build_shaders.nims"
