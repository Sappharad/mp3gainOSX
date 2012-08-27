//
//  Mp3GainMacAppDelegate.h
//  Mp3GainMac
//
//  Created by Paul Kratt on 7/4/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "m3gInputList.h"

@interface Mp3GainMacAppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    IBOutlet NSTableView *tblFileList;
    IBOutlet NSTextField *txtTargetVolume;
    m3gInputList *inputList;
    IBOutlet NSPanel *pnlProgressView;
    IBOutlet NSTextField *lblCurrentFile;
    IBOutlet NSProgressIndicator *pbCurrentFile;
    IBOutlet NSProgressIndicator *pbTotalProgress;
    IBOutlet NSButton *btnCancel;
    bool cancelCurrentOperation;
}

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSTextField *lblCurrentFile;
@property (strong) IBOutlet NSProgressIndicator *pbCurrentFile;
@property (strong) IBOutlet NSProgressIndicator *pbTotalProgress;
- (IBAction)btnAddFiles:(id)sender;
- (IBAction)btnAddFolder:(id)sender;
- (IBAction)btnClearFile:(id)sender;
- (IBAction)btnClearAll:(id)sender;
- (IBAction)btnAnalyze:(id)sender;
- (IBAction)btnApplyGain:(id)sender;
- (IBAction)btnCancel:(id)sender;
-(void)doAnalysis;
-(void)doModify;
- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) theApplication;
@end
