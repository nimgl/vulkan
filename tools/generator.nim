# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

import strutils, ./utils, httpClient, os, xmlparser, xmltree, streams, strformat

proc translateType(s: string): string =
  result = s
  result = result.replace("uint32_t", "uint32")
  result = result.replace("uint64_t", "uint64")

proc genTypes(node: XmlNode, output: var string) =
  echo "Generating Types..."
  output.add("# Types\n")

  var count = 0
  var inType = false

  for types in node.findAll("types"):
    for t in types.items:
      if t.attr("category") == "include" or t.attr("requires").contains(".h") or
         t.attr("requires") == "vk_platform" or t.tag != "type" or t.attr("name") == "int":
        continue

      # Define category

      if t.attr("category") == "define":
        if t.child("name") == nil:
          continue
        inType = false
        let name = t.child("name").innerText
        if  name == "VK_MAKE_VERSION":
          output.add("\ntemplate vkMakeVersion*(major, minor, patch: untyped): untyped =\n")
          output.add("  (((major) shl 22) or ((minor) shl 12) or (patch))\n")
        elif name == "VK_VERSION_MAJOR":
          output.add("\ntemplate vkVersionMajor*(version: untyped): untyped =\n")
          output.add("  ((uint32)(version) shr 22)\n")
        elif name == "VK_VERSION_MINOR":
          output.add("\ntemplate vkVersionMinor*(version: untyped): untyped =\n")
          output.add("  (((uint32)(version) shr 12) and 0x000003FF)\n")
        elif name == "VK_VERSION_PATCH":
          output.add("\ntemplate vkVersionPatch*(version: untyped): untyped =\n")
          output.add("  ((uint32)(version) and 0x00000FFF)\n")
        elif name == "VK_API_VERSION_1_0":
          output.add("\nconst vkApiVersion1_0* = vkMakeVersion(1, 0, 0)\n")
        elif name == "VK_API_VERSION_1_1":
          output.add("const vkApiVersion1_1* = vkMakeVersion(1, 1, 0)\n")
        continue

      # Basetype category

      if t.attr("category") == "basetype":
        if not inType:
          output.add("\ntype\n")
          inType = true
        let name = t.child("name").innerText
        var bType = t.child("type").innerText
        bType = bType.translateType()

        output.add("  {name}* = distinct {bType}\n".fmt)
        continue

      # Bitmask category

      if t.attr("category") == "bitmask":
        if not inType:
          output.add("\ntype\n")
          inType = true

        var name = t.attr("name")
        if t.child("name") != nil:
          name = t.child("name").innerText

        var bType = t.attr("alias")
        var alias = true
        if t.child("type") != nil:
          alias = false
          bType = t.child("type").innerText
        bType = bType.translateType()
        if not alias:
          bType = "distinct " & bType

        output.add("  {name}* = {bType}\n".fmt)
        continue

      # Handle category

      count.inc
      if count > 10:
        continue
      echo t



proc main() =
  if not os.fileExists("vk.xml"):
    let client = newHttpClient()
    let glUrl = "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/master/xml/vk.xml"
    client.downloadFile(glUrl, "vk.xml")

  var output = srcHeader & "\n"

  let file = newFileStream("vk.xml", fmRead)
  let xml = file.parseXml()

  xml.genTypes(output)

  writeFile("src/vulkan.nim", output)

if isMainModule:
  main()
