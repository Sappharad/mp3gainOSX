//
//  Mp3GainMacAppDelegate.m
//  MP3Gain Express
//

#import "Mp3GainMacAppDelegate.h"
#import "m3gInputItem.h"
#import "Mp3GainTask.h"
#import "FileProgressViewItem.h"
#import "m3gPreferences.h"

@implementation Mp3GainMacAppDelegate

@synthesize window = _window;
@synthesize pbTotalProgress;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    inputList = [[m3gInputList alloc] init];
    [tblFileList setDataSource:inputList];
    [tblFileList registerForDraggedTypes:[NSArray arrayWithObjects:NSURLPboardType, nil]];
    
    //Note: Intentionally using the legacy API here for compatbility with older versions of macOS.
    [cvProcessFiles setItemPrototype:[FileProgressViewItem new]];
    [cvProcessFiles setMaxItemSize:NSMakeSize(0, 52.0f)];
    [cvProcessFiles setMinItemSize:NSMakeSize(0, 52.0f)];
    
    m3gPreferences* prefs = [m3gPreferences SharedPreferences];
    if(prefs.RememberOptions){
        [txtTargetVolume setFloatValue:prefs.Volume];
        [chkAvoidClipping setState:prefs.NoClipping?NSOnState:NSOffState];
    }
    if(!prefs.HideWarning){
        NSMutableAttributedString *attrTitle = [[NSMutableAttributedString alloc] initWithString:NSLocalizedStringFromTable(@"DontWarnAgain", @"ui_text", @"Do not show this warning again")];
        [attrTitle addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, attrTitle.length)];
        [chkDoNotWarnAgain setAttributedTitle:attrTitle];
        [pnlWarning setIsVisible:YES];
    }
}

-(void)applicationWillTerminate:(NSNotification *)notification{
    m3gPreferences* prefs = [m3gPreferences SharedPreferences];
    if(prefs.RememberOptions){
        float targetVol = [txtTargetVolume floatValue];
        if(targetVol >= 50 && targetVol <= 100){
            prefs.Volume = targetVol;
        }
        prefs.NoClipping = (chkAvoidClipping.state == NSOnState);
    }
}

- (IBAction)showPreferences:(id)sender {
    [wndPreferences makeKeyAndOrderFront:self];
}

- (IBAction)btnAddFiles:(id)sender {
    NSOpenPanel *fbox = [NSOpenPanel openPanel];
    [fbox setAllowsMultipleSelection:YES];
    [fbox beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
        if(result == NSOKButton){
            uint fileCount = (uint)[[fbox URLs] count];
            for (uint f=0; f<fileCount; f++) {
                NSURL* selfile = [[fbox URLs] objectAtIndex:f];
                if ([selfile isFileURL]) {
                    [inputList addFile:selfile.path];
                }
            }
            [tblFileList reloadData];
        }
    }];
}

- (IBAction)btnAddFolder:(id)sender {
    NSOpenPanel *fbox = [NSOpenPanel openPanel];
    [fbox setAllowsMultipleSelection:YES];
    [fbox setCanChooseDirectories:TRUE];
    [fbox setCanChooseFiles:FALSE];
    [ddlSubfolders removeAllItems];
    [ddlSubfolders addItemWithTitle:NSLocalizedStringFromTable(@"None", @"ui_text", @"None")];
    [ddlSubfolders addItemWithTitle:NSLocalizedStringFromTable(@"1_Below", @"ui_text", @"1_Below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedStringFromTable(@"2_Below", @"ui_text", @"2_Below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedStringFromTable(@"3_Below", @"ui_text", @"3_Below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedStringFromTable(@"4_Below", @"ui_text", @"4_Below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedStringFromTable(@"5_Below", @"ui_text", @"5_Below")];
    [fbox setAccessoryView:vwSubfolderPicker];
    if([fbox respondsToSelector:@selector(isAccessoryViewDisclosed)]){
        fbox.accessoryViewDisclosed = YES;
    }
    [fbox beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
        if(result == NSOKButton){
            uint folderCount = (uint)[[fbox URLs] count];
            int depthAmount = (int)[ddlSubfolders indexOfSelectedItem];
            for (uint f=0; f<folderCount; f++) {
                NSURL* folder = [[fbox URLs] objectAtIndex:f];
                [inputList addDirectory:[folder path] subFoldersRemaining:depthAmount];
            }
            [tblFileList reloadData];
        }
    }];
}

- (IBAction)btnClearFile:(id)sender {
    NSIndexSet* selRows = [tblFileList selectedRowIndexes];
    
    NSUInteger curidx = [selRows lastIndex];
    while (curidx != NSNotFound)
    {
        [inputList removeAtIndex:(int)curidx];
        curidx = [selRows indexLessThanIndex: curidx];
    }
    [tblFileList reloadData];
}

- (IBAction)btnClearAll:(id)sender {
    [inputList clear];
    [tblFileList reloadData];
}

-(BOOL)checkValidOperation{
    float gain = [txtTargetVolume floatValue];
    if(gain < 50.0 || gain >= 100.0){
        NSAlert *alert = [NSAlert new];
        [alert setMessageText:NSLocalizedStringFromTable(@"InvalidVolume", @"ui_text", @"Invalid target volume!")];
        [alert setInformativeText:NSLocalizedStringFromTable(@"VolumeInfo", @"ui_text", @"The target volume should be a number between 50 and 100 dB.")];
        [alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"ui_text", @"OK")];
        [alert runModal];
        return NO;
    }
    return YES;
}

- (IBAction)btnAnalyze:(id)sender {
    if([self checkValidOperation] && inputList.count > 0){
        [NSApp beginSheet:pnlProgressView modalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:nil];
        [lblStatus setStringValue:NSLocalizedStringFromTable(@"Working", @"ui_text", @"Working...")];
        [pbTotalProgress setUsesThreadedAnimation:YES];
        [pbTotalProgress startAnimation:self];
        [pbTotalProgress setMinValue:0.0];
        [pbTotalProgress setMaxValue:[inputList count]];
        [pbTotalProgress setDoubleValue:0.0];
        [btnCancel setEnabled:TRUE];
        cancelCurrentOperation = false;
        
        BOOL albumGain = (chkAlbumGain.state == NSOnState);
        [self doAnalysis:albumGain];
    }
}

-(int)getNumConcurrentTasks{
    return [m3gPreferences SharedPreferences].NumProcesses;
}

-(void)doAnalysis:(BOOL)album{
    NSMutableArray<Mp3GainTask*>* tasks = [NSMutableArray new];
    for(int i=0; i<[inputList count]; i++){
        Mp3GainTask* m3t = [Mp3GainTask taskWithFile:[inputList objectAtIndex:i] action:M3G_Analyze];
        m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [tasks addObject:m3t];
    }
    if(album && inputList.count > 1){
        Mp3GainTask* m3t = [Mp3GainTask taskWithFiles:[inputList allObjects] action:M3G_Analyze];
        m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [tasks addObject:m3t];
    }
    
    [cvProcessFiles setContent:tasks];
    for(int i=0; i<inputList.count && i<[self getNumConcurrentTasks]; i++){
        [[tasks objectAtIndex:i] process];
    }
}

-(void)handleTaskCompletion:(Mp3GainTask*)task{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray<Mp3GainTask*>* replacement = [NSMutableArray new];
        for (Mp3GainTask* origTask in cvProcessFiles.content) {
            if(origTask != task){
                [replacement addObject:origTask];
            }
        }
        [cvProcessFiles setContent:replacement];
        double total = inputList.count - replacement.count;
        [pbTotalProgress setDoubleValue:total];
        
        NSUInteger filesLeft = replacement.count;
        if(filesLeft == 0){
            [NSApp endSheet:pnlProgressView]; //Tell the sheet we're done.
            [pnlProgressView orderOut:self]; //Lets hide the sheet.
            [tblFileList reloadData];
        }
        else{
            //Find next file to begin processing
            for (Mp3GainTask* nextTask in replacement) {
                //Album task MUST be processed last, so check files left even though it should always be at the end of the list.
                if(!nextTask.InProgress && (filesLeft == 1 || nextTask.Files.count == 1)){
                    [nextTask process];
                    break;
                }
            }
        }
    });
}

- (IBAction)btnApplyGain:(id)sender {
    if([self checkValidOperation] && inputList.count > 0){
        [NSApp beginSheet:pnlProgressView modalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:nil];
        [lblStatus setStringValue:NSLocalizedStringFromTable(@"Working", @"ui_text", @"Working...")];
        [pbTotalProgress setUsesThreadedAnimation:YES];
        [pbTotalProgress startAnimation:self];
        [pbTotalProgress setMinValue:0.0];
        [pbTotalProgress setMaxValue:[inputList count]];
        [pbTotalProgress setDoubleValue:0.0];
        [btnCancel setEnabled:TRUE];
        cancelCurrentOperation = false;
        
        BOOL albumGain = (chkAlbumGain.state == NSOnState);
        BOOL avoidClipping = (chkAvoidClipping.state == NSOnState);
        
        [self doModify:avoidClipping albumMode:albumGain];
    }
}

-(void)doModify:(BOOL)noClip albumMode:(BOOL)album{
    NSMutableArray<Mp3GainTask*>* tasks = [NSMutableArray new];
    MP3GActionType firstAction = M3G_Apply;
    if(album && inputList.count > 1){
        firstAction = M3G_Analyze;
    }
    for(int i=0; i<[inputList count]; i++){
        Mp3GainTask* m3t = [Mp3GainTask taskWithFile:[inputList objectAtIndex:i] action:firstAction];
        m3t.NoClipping = noClip;
        m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [tasks addObject:m3t];
    }
    if(album && inputList.count > 1){
        Mp3GainTask* m3t = [Mp3GainTask taskWithFiles:[inputList allObjects] action:M3G_Apply];
        m3t.NoClipping = noClip;
        m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [tasks addObject:m3t];
    }
    
    [cvProcessFiles setContent:tasks];
    for(int i=0; i<inputList.count && i<[self getNumConcurrentTasks]; i++){
        [[tasks objectAtIndex:i] process];
    }
}

- (IBAction)doGainRemoval:(id)sender {
    if(inputList.count > 0){
        [NSApp beginSheet:pnlProgressView modalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:nil];
        [lblStatus setStringValue:NSLocalizedStringFromTable(@"Working", @"ui_text", @"Working...")];
        [pbTotalProgress setUsesThreadedAnimation:YES];
        [pbTotalProgress startAnimation:self];
        [pbTotalProgress setMinValue:0.0];
        [pbTotalProgress setMaxValue:[inputList count]];
        [pbTotalProgress setDoubleValue:0.0];
        [btnCancel setEnabled:TRUE];
        cancelCurrentOperation = false;
        
        [self undoModify];
    }
}

-(void)undoModify{
    NSMutableArray<Mp3GainTask*>* tasks = [NSMutableArray new];
    for(int i=0; i<[inputList count]; i++){
        Mp3GainTask* m3t = [Mp3GainTask taskWithFile:[inputList objectAtIndex:i] action:M3G_Undo];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [tasks addObject:m3t];
    }
    
    [cvProcessFiles setContent:tasks];
    for(int i=0; i<tasks.count && i<[self getNumConcurrentTasks]; i++){
        [[tasks objectAtIndex:i] process];
    }
}

- (IBAction)btnCancel:(id)sender {
    //Clicking cancel stops after the currently processing files are done. It removes any that haven't started yet.
    cancelCurrentOperation = true;
    [lblStatus setStringValue:NSLocalizedStringFromTable(@"Canceling_soon", @"ui_text", @"Canceling soon")];
    [btnCancel setEnabled:FALSE];
    
    //Rebuild the pending file list without tasks that haven't started yet.
    NSMutableArray<Mp3GainTask*>* replacement = [NSMutableArray new];
    for (Mp3GainTask* task in cvProcessFiles.content) {
        if(task.InProgress){
            [replacement addObject:task];
        }
    }
    [cvProcessFiles setContent:replacement];
    double total = inputList.count - replacement.count;
    [pbTotalProgress setDoubleValue:total];
}

- (IBAction)btnShowAdvanced:(id)sender {
    [mnuAdvancedGain popUpMenuPositioningItem:nil atLocation:[btnAdvancedMenu frame].origin inView:vwMainBody];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) theApplication{
    return TRUE;
}

@end
