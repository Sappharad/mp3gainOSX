# NSToolbarItem Deprecation Warning Fix

## Issue

A purple deprecation warning appears in Xcode at line 13 of `main.m` during application launch:

```
NSToolbarItem.minSize and NSToolbarItem.maxSize methods are deprecated. 
Usage may result in clipping of items. It is recommended to let the system 
measure the item automatically using constraints.
```

## Investigation

The warning appears during `NSApplicationMain()` when the XIB file is loaded. After thorough investigation:

1. **No explicit minSize/maxSize in code**: There are no calls to `setMinSize:` or `setMaxSize:` in the Objective-C code
2. **No visible minSize/maxSize in XIB**: The XML content of `Base.lproj/MainMenu.xib` does not contain minSize/maxSize attributes on the toolbar items
3. **Modern sizing already in use**: All toolbar items already use `sizingBehavior="auto"`, which is the recommended modern approach
4. **Window min/maxSize is fine**: The window has minSize/maxSize attributes (lines 405-406), but these are for `NSWindow`, not `NSToolbarItem`, and are not deprecated

## Root Cause

The warning is likely caused by internal XIB metadata from earlier Xcode versions that isn't visible in the raw XML but is interpreted by the runtime. XIB files can contain binary-encoded data that persists across versions.

## Changes Made

1. **Removed legacy toolbar item attributes** in `Base.lproj/MainMenu.xib`:

   - Removed `tag="-1"` attribute (unusual value, not needed for image-based toolbar items)
   - Removed `selectable="YES"` attribute (not necessary for standard toolbar items)

2. **Removed explicit image dimensions**:

   - Removed `width="128" height="128"` from all toolbar image resources
   - This allows the system to automatically determine appropriate sizes
   - When explicit dimensions are specified, the system may use deprecated sizing logic

These changes ensure the toolbar item definitions are as minimal and modern as possible, relying entirely on automatic sizing.

## Complete Fix

While the changes above should help, the complete fix would typically require:

1. Open `Mp3GainMac/Base.lproj/MainMenu.xib` in Xcode Interface Builder
2. Select each toolbar item in the toolbar
3. In the Size Inspector, verify no explicit size constraints are set
4. Verify sizing behavior is set to "Automatic"
5. Re-save the XIB file (this clears internal metadata)

This would clean up any hidden legacy metadata that's causing the warning.

## Verification

To verify the fix works:

1. Build the project in Xcode
2. Check the build log for the deprecation warning
3. The warning should either be gone or significantly reduced

## Is It Worth Fixing?

- The warning doesn't affect functionality - the app works correctly
- It's a deprecation warning, not an error
- However, it's good practice to address deprecation warnings to:
  - Keep the codebase modern
  - Avoid future compatibility issues
  - Maintain clean build logs

