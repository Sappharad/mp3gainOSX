# MP3Gain Express Changelog

This document tracks improvements, changes, and fixes made to MP3Gain Express for macOS ([mp3gainOSX](https://github.com/Sappharad/mp3gainOSX)) in February 2026.

## Performance Improvements

### Faster Table View

mp3gainOSX has a problem when processing large file lists. When the number of files exceeds 600-800, the app may crash right at the end of file processing. This is more frequent when applying gain (which consumes more resources) than when analyzing. Issue [#24](https://github.com/Sappharad/mp3gainOSX/issues/24), from September 2029 by *jri*, warns of this problem.

A fix is ​​proposed, its only drawback is that it requires upgrading from the minimum supported macOS version to Big Sur.

**Implementation: View-Based NSTableView**

The main file list table has been modernized from the legacy cell-based approach to a modern view-based implementation for significantly better performance and memory efficiency.

**Key Changes:**

  - Implemented `tableView:viewForTableColumn:row:` instead of the deprecated `tableView:objectValueForTableColumn:row:`
  - Added cell view reuse with `makeViewWithIdentifier:owner:` for efficient memory usage
  - Programmatically creates `NSTableCellView` instances with properly configured text fields
  - Uses Auto Layout constraints for proper cell content layout
  - Optimized cell recycling to prevent stale data from appearing in reused cells

**Benefits:**

  - Better performance with large file lists
  - Lower memory footprint
  - Smoother scrolling
  - Modern macOS best practices

**Files Modified:**

  - `MP3GainExpress/Process/m3gInputList.m` - Lines 37-109

### Progress Window Simplification

**Streamlined UI for Better Responsiveness**

The progress window shows the files scrolling from bottom to top as they are processed. When there are many files, there's barely enough time to see them scrolling; it's not useful information for the user and it consumes resources.

The progress window has been simplified to use a cleaner, more efficient layout: Working/Canceling... text, progress bar and Cancel button.

- **Key Changes:**
  
  - Removed collection view complexity from progress panel
  - Simplified to a basic layout with label, progress bar, and cancel button
  - Progress updates directly to a single progress indicator instead of per-file views

- **Benefits:**
  
  - Faster UI updates during file processing
  - Reduced overhead during batch operations
  - Cleaner, more focused user experience
  - Better performance with many concurrent file operations

- **Files Modified:**
  
  - `MP3GainExpress/Base.lproj/MainMenu.xib` - Lines 372-418
  - `MP3GainExpress/Mp3GainMacAppDelegate.m` - Lines 17-45

![Processing window](../Images/Window2.png)

## Memory Management & Stability

### NSFileHandle Observer Cleanup

**Critical Fix to Prevent Crashes**

Fixed a critical memory safety issue where NSFileHandle notification observers weren't being properly cleaned up, leading to `EXC_BAD_ACCESS` crashes.

- **Problem:** When NSTask terminated, notification observers remained registered with deallocated NSFileHandle objects

- **Solution:** 
  
  - Added observer removal in NSTask termination handlers
  - Added observer cleanup in dealloc methods
  - Implemented weak self references to prevent retain cycles

- **Benefits:**
  
  - Eliminates `EXC_BAD_ACCESS` crashes
  - Proper resource cleanup
  - More stable application lifecycle

- **Files Modified:**
  
  - `MP3GainExpress/Process/Mp3GainTask.m` - Lines 33-38, 146-155, 209-213

### Block Retain Cycle Prevention

**Proper Memory Management**

Implemented proper weak self references in blocks to prevent retain cycles.

- **Key Changes:**
  
  - Use `__weak self` references in blocks assigned to properties
  - Prevents memory leaks in completion handlers
  - Proper task lifecycle management

- **Benefits:**
  
  - No memory leaks
  - Proper object deallocation
  - Better overall memory usage

- **Files Modified:**
  
  - `MP3GainExpress/Mp3GainMacAppDelegate.m` - Lines 180-183, 266-269, 310-312

## macOS Compatibility

### Modern File Type Handling

**UniformTypeIdentifiers Framework**

Updated file type handling to use the modern UTType API.

- **Key Changes:**
  
  - Uses `UniformTypeIdentifiers.framework` on macOS 12.0+
  - Falls back to deprecated `allowedFileTypes` on older systems
  - Properly linked framework in Xcode project

- **Benefits:**
  
  - Modern API usage
  - Follows Apple's current best practices

- **Files Modified:**
  
  - `MP3GainExpress/Mp3GainMacAppDelegate.m` - Lines 10, 66-77

## User Interface Improvements

### Toolbar Modernization

**Removed Deprecated APIs**

Updated toolbar items to use modern sizing behavior and removed deprecated attributes.

- **Key Changes:**
  
  - Use `sizingBehavior="auto"` for all toolbar items
  - Removed explicit image dimensions from XIB resources
  - Removed legacy attributes (`tag="-1"`, `selectable="YES"`)
  - Removed deprecated `minSize`/`maxSize` usage

- **Benefits:**
  
  - No deprecation warnings in Xcode
  - System-controlled automatic sizing
  - Future-proof implementation
  - Follows current macOS standards

- **Documentation:** See this [document](Documentation/Toolbar-deprecations.md) for detailed explanation

- **Files Modified:**
  
  - `MP3GainExpress/Base.lproj/MainMenu.xib` - Lines 618-637, 915-921

### XIB File Improvements

**Cleaner Interface Builder Files**

Multiple improvements to XIB files for better compatibility and cleaner structure.

- **Key Changes:**
  
  - Removed explicit `contentBorderThickness` from regular windows
  - Cleaned up table column definitions for view-based NSTableView
  - Removed unnecessary `dataCell` elements from view-based table columns

- **Benefits:**
  
  - Better Xcode Interface Builder compatibility
  - Cleaner XIB structure
  - No spurious warnings

- **Files Modified:**
  
  - `MP3GainExpress/Base.lproj/MainMenu.xib` - Lines 485-532, 851

## Code Quality

### Table View Cell Recycling

**Proper Stale Data Prevention**

Fixed potential display issues with recycled table cells.

- **Problem:** Recycled cells could show stale data from previous rows
- **Solution:** Explicitly clear text fields when no data should be displayed
- **Benefits:** Correct display in all scenarios, no visual artifacts

- **Files Modified:**
  
  - `MP3GainExpress/Process/m3gInputList.m` - Lines 89-92, 102-105

### Drag and Drop Support

**Enhanced File Input**

The table view supports drag and drop of files and folders.

- **Features:**
  
  - Drag files directly into the table
  - Drag folders with configurable subfolder depth
  - Duplicate prevention
  - Visual feedback during drag operations

- **Files Modified:**
  
  - `MP3GainExpress/Process/m3gInputList.m` - Lines 136-208

## Cleanup

### Removed Unused Files

**Code Organization**

Identified and documented unused legacy files that can be safely removed.

- **Unused Files:**
  
  - `MP3GainExpress/Process/FileProgressViewItem.h`
  - `MP3GainExpress/Process/FileProgressViewItem.m`
  - `MP3GainExpress/FileProgressViewItem.xib`

These files are no longer referenced after the progress window simplification and have been removed.

## Build System

### Platform Requirements

- **Minimum macOS:** 11.5+
- **Xcode:** 15+
- **Language:** Objective-C
- **Frameworks:** 
  - Foundation
  - AppKit
  - UniformTypeIdentifiers (macOS 11.5+)

## Summary

The improvements focus on:

1. **Performance** - Faster table view rendering and simplified progress tracking
2. **Stability** - Fixed memory leaks and crash-prone code
3. **Modernization** - Updated to current macOS APIs and best practices
4. **Compliance** - Follows Apple's Human Interface Guidelines
5. **Code Quality** - Better memory management and cleaner implementation

These changes make MP3Gain Express more responsive, stable, and maintainable while providing a better user experience on modern macOS versions.
