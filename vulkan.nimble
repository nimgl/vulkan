# Package

version     = "1.1.0"
author      = "Leonardo Mariscal"
description = "Vulkan bindings for Nim"
license     = "MIT"
srcDir      = "src"
skipDirs    = @["tests"]

# Dependencies

requires "nim >= 1.0.2"

task gen, "Generate bindings from source":
  exec("nim c -r tools/generator.nim")

task test, "Create basic triangle with Vulkan and GLFW":
  requires "nimgl@#1.0" # Please https://github.com/nim-lang/nimble/issues/482
  exec("nim c -r test/tvulkan.nim")
