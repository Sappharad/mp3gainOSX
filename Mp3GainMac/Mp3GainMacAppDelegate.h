//
//  Mp3GainMacAppDelegate.h
//  Mp3Gain Express for Mac OS X
//

#import <Cocoa/Cocoa.h>
#import "m3gInputList.h"
#import <AppKit/AppKit.h>

@interface Mp3GainMacAppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *_window;
    IBOutlet NSView *vwMainBody;
    IBOutlet NSTableView *tblFileList;
    IBOutlet NSTextField *txtTargetVolume;
    m3gInputList *inputList;
    IBOutlet NSPanel *pnlProgressView;
    IBOutlet NSCollectionView *cvProcessFiles;
    __weak IBOutlet NSTextField *lblStatus;
    IBOutlet NSProgressIndicator *pbTotalProgress;
    IBOutlet NSButton *btnCancel;
    bool cancelCurrentOperation;
    IBOutlet NSView *vwSubfolderPicker;
    IBOutlet NSPopUpButton *ddlSubfolders;
    IBOutlet NSMenu *mnuAdvancedGain;
    IBOutlet NSButton *chkAvoidClipping;
    IBOutlet NSButton *btnAdvancedMenu;
    IBOutlet NSButton *chkAlbumGain;
}

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSProgressIndicator *pbTotalProgress;
@property (atomic) int NumConcurrentTasks;
- (IBAction)btnAddFiles:(id)sender;
- (IBAction)btnAddFolder:(id)sender;
- (IBAction)btnClearFile:(id)sender;
- (IBAction)btnClearAll:(id)sender;
- (IBAction)btnAnalyze:(id)sender;
- (IBAction)btnApplyGain:(id)sender;
- (IBAction)btnCancel:(id)sender;
- (IBAction)btnShowAdvanced:(id)sender;
- (IBAction)doGainRemoval:(id)sender;
@end
