# Package

version       = "0.1.0"
author        = "xmonader"
description   = "client for sonic search backend"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 0.19.4"

task genDocs, "Create code documentation for sonic":
    exec "nim doc --threads:on --project src/sonic.nim && rm -rf docs/api; mkdir -p docs && mv src/htmldocs docs/api "