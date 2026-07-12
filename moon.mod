// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "moonforge/moon_forge"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/MrsFlower/moonforge-graphkit"

license = "Apache-2.0"

keywords = [ ]

preferred_target = "native"

description = "AI-assisted formal verification infrastructure and verified graph algorithm building blocks for MoonBit."

import {
  "moonbitlang/async@0.20.1",
}
