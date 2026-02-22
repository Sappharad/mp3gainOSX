//
//  Mp3GainMacAppDelegate.m
//  MP3Gain Express
//

#import "Mp3GainMacAppDelegate.h"
#import "m3gInputItem.h"
#import "m3gPreferences.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation Mp3GainMacAppDelegate

@synthesize window = _window;
@synthesize pbTotalProgress;
@synthesize updater;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Initialize Sparkle updater
    updater = [SUUpdater sharedUpdater];
    [updater setDelegate:self];
    
    _inputList = [[m3gInputList alloc] init];
    [tblFileList setDataSource:_inputList];
    [tblFileList setDelegate:_inputList];
    [tblFileList registerForDraggedTypes:[NSArray arrayWithObjects:NSPasteboardTypeURL, nil]];
    
    m3gPreferences* prefs = [m3gPreferences SharedPreferences];
    [pnlWarning setTitle:NSLocalizedString(@"WarningTitle", @"Warning")];
    [lblWarningMessage setStringValue:NSLocalizedString(@"WarningText", @"In some situations the modifications made by MP3Gain could damage your files. If you have never used this application before or are concerned about the results, please backup your original files before making changes to them.")];
    if(prefs.RememberOptions){
        [txtTargetVolume setFloatValue:prefs.Volume];
        [chkAvoidClipping setState:prefs.NoClipping?NSControlStateValueOn:NSControlStateValueOff];
    }
    if(!prefs.HideWarning){
        [chkDoNotWarnAgain setTitle:NSLocalizedString(@"DontWarnAgain", @"Do not show this warning again")];
        [pnlWarning setIsVisible:YES];
    }
    //Set toolbar images at template, so when we're in dark mode they get inverted automatically:
    NSImage* addSong = [NSImage imageNamed:@"AddSong.png"];
    [addSong setTemplate:YES];
    [tbiAddFile setImage:addSong];
    NSImage* addFolder = [NSImage imageNamed:@"AddFolder.png"];
    [addFolder setTemplate:YES];
    [tbiAddFolder setImage:addFolder];
    NSImage* clearSong = [NSImage imageNamed:@"ClearSong.png"];
    [clearSong setTemplate:YES];
    [tbiClearFile setImage:clearSong];
    NSImage* clearAll = [NSImage imageNamed:@"ClearAll.png"];
    [clearAll setTemplate:YES];
    [tbiClearAll setImage:clearAll];
    if (@available(macOS 11.0, *)) {
         [mnuCheckForUpdates setImage:[NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath" accessibilityDescription:@"Check for updates"]];
     }
}

-(void)applicationWillTerminate:(NSNotification *)notification{
    m3gPreferences* prefs = [m3gPreferences SharedPreferences];
    if(prefs.RememberOptions){
        float targetVol = [txtTargetVolume floatValue];
        if(targetVol >= 50 && targetVol <= 100){
            prefs.Volume = targetVol;
        }
        prefs.NoClipping = (chkAvoidClipping.state == NSControlStateValueOn);
    }
}

- (IBAction)showPreferences:(id)sender {
    [wndPreferences makeKeyAndOrderFront:self];
}

- (IBAction)btnAddFiles:(id)sender {
    NSOpenPanel *fbox = [NSOpenPanel openPanel];
    if (@available(macOS 12.0, *)) {
        fbox.allowedContentTypes = @[
            [UTType typeWithFilenameExtension:@"mp3"],
            [UTType typeWithFilenameExtension:@"mp4"],
            [UTType typeWithFilenameExtension:@"m4a"]
        ];
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        fbox.allowedFileTypes = @[@"mp3",@"mp4",@"m4a"];
        #pragma clang diagnostic pop
    }
    fbox.allowsOtherFileTypes = YES;
    [fbox setAllowsMultipleSelection:YES];
    [fbox beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
        if(result == NSModalResponseOK){
            uint fileCount = (uint)[[fbox URLs] count];
            for (uint f=0; f<fileCount; f++) {
                NSURL* selfile = [[fbox URLs] objectAtIndex:f];
                if ([selfile isFileURL]) {
                    [self->_inputList addFile:selfile.path];
                }
            }
            [self->tblFileList reloadData];
        }
    }];
}

- (IBAction)btnAddFolder:(id)sender {
    NSOpenPanel *fbox = [NSOpenPanel openPanel];
    [fbox setAllowsMultipleSelection:YES];
    [fbox setCanChooseDirectories:TRUE];
    [fbox setCanChooseFiles:FALSE];
    [ddlSubfolders removeAllItems];
    [ddlSubfolders addItemWithTitle:NSLocalizedString(@"None", @"None")];
    [ddlSubfolders addItemWithTitle:NSLocalizedString(@"1_below", @"1 subfolder below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedString(@"2_below", @"2 subfolders below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedString(@"3_below", @"3 subfolders below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedString(@"4_below", @"4 subfolders below")];
    [ddlSubfolders addItemWithTitle:NSLocalizedString(@"5_below", @"5 subfolders below")];
    [fbox setAccessoryView:vwSubfolderPicker];
    if([fbox respondsToSelector:@selector(isAccessoryViewDisclosed)]){
        fbox.accessoryViewDisclosed = YES;
    }
    [fbox beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
        if(result == NSModalResponseOK){
            uint folderCount = (uint)[[fbox URLs] count];
            int depthAmount = (int)[self->ddlSubfolders indexOfSelectedItem];
            for (uint f=0; f<folderCount; f++) {
                NSURL* folder = [[fbox URLs] objectAtIndex:f];
                [self->_inputList addDirectory:[folder path] subFoldersRemaining:depthAmount];
            }
            [self->tblFileList reloadData];
        }
    }];
}

- (IBAction)btnClearFile:(id)sender {
    NSIndexSet* selRows = [tblFileList selectedRowIndexes];
    
    NSUInteger curidx = [selRows lastIndex];
    while (curidx != NSNotFound)
    {
        [_inputList removeAtIndex:(int)curidx];
        curidx = [selRows indexLessThanIndex: curidx];
    }
    [tblFileList reloadData];
}

- (IBAction)btnClearAll:(id)sender {
    [_inputList clear];
    [tblFileList reloadData];
}

-(BOOL)checkValidOperation{
    float gain = [txtTargetVolume floatValue];
    if(gain < 50.0 || gain >= 100.0){
        NSAlert *alert = [NSAlert new];
        [alert setMessageText:NSLocalizedString(@"InvalidVolume", @"Invalid target volume!")];
        [alert setInformativeText:NSLocalizedString(@"VolumeInfo", @"The target volume should be a number between 50 and 100 dB.")];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
        [alert runModal];
        return NO;
    }
    return YES;
}

- (IBAction)btnAnalyze:(id)sender {
    if([self checkValidOperation] && _inputList.count > 0){
        [_window beginSheet:pnlProgressView completionHandler:nil];
        [lblStatus setStringValue:NSLocalizedString(@"Working", @"Working...")];
        [pbTotalProgress setUsesThreadedAnimation:YES];
        [pbTotalProgress startAnimation:self];
        [pbTotalProgress setMinValue:0.0];
        [pbTotalProgress setMaxValue:[_inputList count]];
        [pbTotalProgress setDoubleValue:0.0];
        [btnCancel setEnabled:TRUE];
        cancelCurrentOperation = false;
        
        BOOL albumGain = (chkAlbumGain.state == NSControlStateValueOn);
        [self doAnalysis:albumGain];
    }
}

-(int)getNumConcurrentTasks{
    return [m3gPreferences SharedPreferences].NumProcesses;
}

-(void)doAnalysis:(BOOL)album{
    _tasks = [NSMutableArray new];
    if(!album || _inputList.count == 1){
        for(int i=0; i<[_inputList count]; i++){
            Mp3GainTask* m3t = [Mp3GainTask taskWithFile:[_inputList objectAtIndex:i] action:M3G_Analyze];
            m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
            __weak Mp3GainTask* taskBackup = m3t;
            m3t.onProcessingComplete = ^{
                [self handleTaskCompletion:taskBackup];
            };
            [_tasks addObject:m3t];
        }
    }
    else{
        //This is an album - Do not process it twice because reprocessing doesn't use single file data.
        Mp3GainTask* m3t = [Mp3GainTask taskWithFiles:[_inputList allObjects] action:M3G_Analyze];
        m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [_tasks addObject:m3t];
    }
    
    for(int i=0; i<_tasks.count && i<[self getNumConcurrentTasks]; i++){
        [[_tasks objectAtIndex:i] process];
    }
}

-(void)handleTaskCompletion:(Mp3GainTask*)task{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray<Mp3GainTask*>* replacement = [NSMutableArray new];
        for (Mp3GainTask* origTask in self->_tasks) {
            if(origTask != task){
                [replacement addObject:origTask];
            }
        }
        if(task.FailureCount == 1){
            //Re-add file to end of the list on the first failure.
            [replacement addObject:task];
        }
        self->_tasks = replacement;
        double total = self->_inputList.count - replacement.count;
        [self->pbTotalProgress setDoubleValue:total];
        
        NSUInteger filesLeft = replacement.count;
        if(filesLeft == 0){
            [NSApp endSheet:self->pnlProgressView]; //Tell the sheet we're done.
            [self->pnlProgressView orderOut:self]; //Lets hide the sheet.
            [self->tblFileList reloadData];
            [self->_tasks removeAllObjects];
            self->_tasks = nil;
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
    if([self checkValidOperation] && _inputList.count > 0){
        [_window beginSheet:pnlProgressView completionHandler:nil];
        [lblStatus setStringValue:NSLocalizedString(@"Working", @"Working...")];
        [pbTotalProgress setUsesThreadedAnimation:YES];
        [pbTotalProgress startAnimation:self];
        [pbTotalProgress setMinValue:0.0];
        [pbTotalProgress setMaxValue:[_inputList count]];
        [pbTotalProgress setDoubleValue:0.0];
        [btnCancel setEnabled:TRUE];
        cancelCurrentOperation = false;
        
        BOOL albumGain = (chkAlbumGain.state == NSControlStateValueOn);
        BOOL avoidClipping = (chkAvoidClipping.state == NSControlStateValueOn);
        
        [self doModify:avoidClipping albumMode:albumGain];
    }
}

-(void)doModify:(BOOL)noClip albumMode:(BOOL)album{
    _tasks = [NSMutableArray new];
    if(!album || _inputList.count == 1){
        for(int i=0; i<[_inputList count]; i++){
            Mp3GainTask* m3t = [Mp3GainTask taskWithFile:[_inputList objectAtIndex:i] action:M3G_Apply];
            m3t.NoClipping = noClip;
            m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
            __weak Mp3GainTask* taskBackup = m3t;
            m3t.onProcessingComplete = ^{
                [self handleTaskCompletion:taskBackup];
            };
            [_tasks addObject:m3t];
        }
    }
    else{
        //Album mode - Don't process twice because it doesn't use analyze data
        Mp3GainTask* m3t = [Mp3GainTask taskWithFiles:[_inputList allObjects] action:M3G_Apply];
        m3t.NoClipping = noClip;
        m3t.DesiredDb = [NSNumber numberWithDouble:[txtTargetVolume floatValue]];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [_tasks addObject:m3t];
    }
    
    for(int i=0; i<_tasks.count && i<[self getNumConcurrentTasks]; i++){
        [[_tasks objectAtIndex:i] process];
    }
}

- (IBAction)doGainRemoval:(id)sender {
    if(_inputList.count > 0){
        [_window beginSheet:pnlProgressView completionHandler:nil];
        [lblStatus setStringValue:NSLocalizedString(@"Working", @"Working...")];
        [pbTotalProgress setUsesThreadedAnimation:YES];
        [pbTotalProgress startAnimation:self];
        [pbTotalProgress setMinValue:0.0];
        [pbTotalProgress setMaxValue:[_inputList count]];
        [pbTotalProgress setDoubleValue:0.0];
        [btnCancel setEnabled:TRUE];
        cancelCurrentOperation = false;
        
        [self undoModify];
    }
}

-(void)undoModify{
    _tasks = [NSMutableArray new];
    for(int i=0; i<[_inputList count]; i++){
        Mp3GainTask* m3t = [Mp3GainTask taskWithFile:[_inputList objectAtIndex:i] action:M3G_Undo];
        __weak Mp3GainTask* taskBackup = m3t;
        m3t.onProcessingComplete = ^{
            [self handleTaskCompletion:taskBackup];
        };
        [_tasks addObject:m3t];
    }
    
    for(int i=0; i<_tasks.count && i<[self getNumConcurrentTasks]; i++){
        [[_tasks objectAtIndex:i] process];
    }
}

- (IBAction)btnCancel:(id)sender {
    //Clicking cancel stops after the currently processing files are done. It removes any that haven't started yet.
    cancelCurrentOperation = true;
    [lblStatus setStringValue:NSLocalizedString(@"Canceling", @"Canceling")];
    [btnCancel setEnabled:FALSE];
    
    //Rebuild the pending file list without tasks that haven't started yet.
    NSMutableArray<Mp3GainTask*>* replacement = [NSMutableArray new];
    for (Mp3GainTask* task in _tasks) {
        if(task.InProgress){
            [replacement addObject:task];
        }
    }
    _tasks = replacement;
    double total = _inputList.count - replacement.count;
    [pbTotalProgress setDoubleValue:total];
}

- (IBAction)btnShowAdvanced:(id)sender {
    [mnuAdvancedGain popUpMenuPositioningItem:nil atLocation:[btnAdvancedMenu frame].origin inView:vwMainBody];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) theApplication{
    return TRUE;
}

- (IBAction)checkForUpdates:(id)sender {
    [updater checkForUpdates:sender];
}

@end
