# Memories

## Patterns

### mem-1773700733-c977
> Project uses PBXFileSystemSynchronizedRootGroup — new Swift files in Quant/ and QuantTests/ are auto-discovered by Xcode. No pbxproj edits needed for file references.
<!-- tags: xcode, project-structure | created: 2026-03-16 -->

### mem-1773700728-1966
> QuantNoWatchTests scheme runs unit tests (QuantTests target). The Quant scheme only runs QuantUITests. Use -scheme QuantNoWatchTests for unit testing from CLI. Fixed scheme to include Quant.app build dependency and buildImplicitDependencies=YES.
<!-- tags: testing, xcode, scheme | created: 2026-03-16 -->

## Decisions

## Fixes

### mem-1773883326-2c51
> Metal Toolchain must be downloaded separately on Xcode 26.3: xcodebuild -downloadComponent MetalToolchain. Without it, .metal files fail to compile with 'cannot execute tool metal due to missing Metal Toolchain'
<!-- tags: metal, xcode, toolchain | created: 2026-03-19 -->

## Context
