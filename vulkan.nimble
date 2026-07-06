# Package

version     = "1.4.344"
author      = "Leonardo Mariscal"
description = "Vulkan bindings for Nim"
license     = "MIT"
srcDir      = "src"
skipDirs    = @["tests"]

# Dependencies
requires "nim >= 1.0.0"

feature "examples":
  requires "glfw"
  requires "chroma"
  requires "sdl2"

