import std/[strutils, os]

task test, "Run tests/test.nim":
  exec("nim c -r tests/test.nim")
  exec("nim c -r tests/test_wrapper.nim")
  exec("nim c examples/run_triangle.nim")
  exec("nim c examples/run_mandelbrot.nim")

task gen, "Generate bindings from source":
  exec("nim c -d:ssl -r tools/generator.nim")

task shaders, "Compile GLSL shaders to SPIR-V format":
  let
    shaderDir = "examples/mandelbrot/shaders"
    outputDir = "examples/mandelbrot/build/shaders"
  mkDir(outputDir)
  for f in listFiles(shaderDir):
    if f.endsWith(".glsl"):
      exec "glslc -g -fshader-stage=comp " & f & " -o " & outputDir / splitFile(f).name & ".spv"
