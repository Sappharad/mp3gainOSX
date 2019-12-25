//
//  Mp3GainMacAppDelegate.h
//  Mp3Gain Express for Mac OS X
//

#import <Cocoa/Cocoa.h>
#import "m3gInputList.h"
#import <AppKit/AppKit.h>
#import "Mp3GainTask.h"

@interface Mp3GainMacAppDelegate : NSObject <NSApplicationDelegate> {
    m3gInputList *_inputList;
    NSMutableArray<Mp3GainTask*> *_tasks;
    NSWindow *_window;
    IBOutlet NSView *vwMainBody;
    IBOutlet NSTableView *tblFileList;
    IBOutlet NSTextField *txtTargetVolume;
    IBOutlet NSPanel *pnlProgressView;
    IBOutlet NSCollectionView *cvProcessFiles;
    IBOutlet NSTextField *lblStatus;
    IBOutlet NSProgressIndicator *pbTotalProgress;
    IBOutlet NSButton *btnCancel;
    bool cancelCurrentOperation;
    IBOutlet NSView *vwSubfolderPicker;
    IBOutlet NSPopUpButton *ddlSubfolders;
    IBOutlet NSMenu *mnuAdvancedGain;
    IBOutlet NSButton *chkAvoidClipping;
    IBOutlet NSButton *btnAdvancedMenu;
    IBOutlet NSButton *chkAlbumGain;
    IBOutlet NSWindow *wndPreferences;
    IBOutlet NSPanel *pnlWarning;
    IBOutlet NSButton *chkDoNotWarnAgain;
    IBOutlet NSToolbarItem *tbiAddFile;
    IBOutlet NSToolbarItem *tbiAddFolder;
    IBOutlet NSToolbarItem *tbiClearFile;
    IBOutlet NSToolbarItem *tbiClearAll;
}

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSProgressIndicator *pbTotalProgress;
- (IBAction)showPreferences:(id)sender;
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
