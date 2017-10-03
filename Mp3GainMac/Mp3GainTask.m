//
//  Mp3GainTask.m
//  MP3GainExpress
//

#import "Mp3GainTask.h"

@implementation Mp3GainTask

+(Mp3GainTask*)taskWithFile:(m3gInputItem*)file action:(MP3GActionType)action{
    Mp3GainTask* task = [Mp3GainTask new];
    task.Files = [NSArray<m3gInputItem*> arrayWithObject:file];
    task.Action = action;
    task.InProgress = NO;
    task.TwoPass = NO;
    task.FailureCount = 0;
    file.state = 0;
    return task;
}

+(Mp3GainTask*)taskWithFiles:(NSArray<m3gInputItem*>*)files action:(MP3GActionType)action{
    Mp3GainTask* task = [Mp3GainTask new];
    task.Files = files;
    task.Action = action;
    task.InProgress = NO;
    task.TwoPass = NO;
    task.FailureCount = 0;
    return task;
}

-(void)process{
    self.InProgress = YES;
    if(self.Files.count == 1){
        for (m3gInputItem* file in self.Files) {
            file.clipping = NO; //Clear clipping flag, will be set later.
        }
    }
    if(self.Action == M3G_Analyze){
        [self AnalyzeFile];
    }
    else if(self.Action == M3G_Apply){
        if(self.Files.count == 1 && (!self.NoClipping || [self.Files objectAtIndex:0].volume == 0)){
            //Always need 2 passes if NoClipping is off, because we don't get notified about clipping during the Apply process.
            //Can't trust previous data because they could change the desired volume on us.
            self.TwoPass = YES;
            [self AnalyzeFile];
        }
        else{
            [self ApplyGain];
        }
    }
    else if(self.Action == M3G_Undo){
        [self UndoGain];
    }
}
-(NSString*)getDescription{
    if(self.Files){
        if(self.Files.count > 1){
            //When in Album mode, we always scan the tracks individually so that multiple tracks can be scanned at the same time.
            //Then we run it again in album mode, which doesn't need to rescan the files because ReplayGain tags were generated
            //during the initial scan. This allows album mode to benefit from the performance gained by scanning multiple files at once.
            return @"Reprocess as Album...";
        }
        return [[self.Files objectAtIndex:0] getFilename];
    }
    return @"";
}

-(void)AnalyzeFile{
    float desiredDb = 89.0f;
    if(self.DesiredDb){
        desiredDb = [self.DesiredDb floatValue];
    }
    NSMutableArray<NSString*>* arguments = [NSMutableArray arrayWithObjects:@"-d",[NSString stringWithFormat:@"%f",(desiredDb-89.0)], nil];
    for (m3gInputItem* file in self.Files) {
        [arguments addObject:[file.filePath path]];
    }
    
    [self doProcessing:arguments];
}

-(void)ApplyGain{
    float desiredDb = 89.0f;
    if(self.DesiredDb){
        desiredDb = [self.DesiredDb floatValue];
    }
    NSMutableArray<NSString*>* arguments;
    if(self.NoClipping){
        arguments = [NSMutableArray arrayWithObjects:@"-r",@"-k",@"-d",[NSString stringWithFormat:@"%f",(desiredDb-89.0)],nil];
    }
    else{
        arguments = [NSMutableArray arrayWithObjects:@"-r",@"-c",@"-d",[NSString stringWithFormat:@"%f",(desiredDb-89.0)],nil];
    }
    if(self.Files.count > 1){
        [arguments replaceObjectAtIndex:0 withObject:@"-a"];
    }
    for (m3gInputItem* file in self.Files) {
        [arguments addObject:[file.filePath path]];
    }
    
    [self doProcessing:arguments];
}

-(void)UndoGain{
    NSArray<NSString*>* arguments = @[@"-u",[[self.Files objectAtIndex:0].filePath path]];
    
    [self doProcessing:arguments];
}

-(void)doProcessing:(NSArray<NSString*>*)arguments{
    _task = [NSTask new];
    NSString* launchPath = [[NSBundle mainBundle] pathForResource:@"aacgain" ofType:nil];
    [_task setLaunchPath:launchPath];
    [_task setArguments:arguments];
    
    _detailsPipe = [NSPipe pipe];
    [_task setStandardInput:[NSPipe pipe]];
    [_task setStandardOutput:_detailsPipe];
    
    if(self.Files.count == 1){
        _statusPipe = [NSPipe pipe];
        [_task setStandardError:_statusPipe];
        //Fun fact: Having status on stderr caused file corruption in previous releases when mp3gain was internal
        
        _statusHandle = [_statusPipe fileHandleForReading];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleIncomingStatus:)
                                                     name:NSFileHandleDataAvailableNotification
                                                   object:_statusHandle];
        [_statusHandle waitForDataInBackgroundAndNotifyForModes:@[NSDefaultRunLoopMode]];
    }
    
    __weak Mp3GainTask* weakSelf = self;
    __weak NSPipe* weakPipe = _detailsPipe;
    _task.terminationHandler = ^(NSTask* myself)
    {
        NSData* detailsData = [[weakPipe fileHandleForReading] readDataToEndOfFile];
        NSString* detailsOutput = [[NSString alloc] initWithData:detailsData encoding:NSUTF8StringEncoding];
        
        //NSLog(@"%@", detailsOutput);
        [weakSelf parseProcessDetails:detailsOutput];
        
        if(myself.terminationStatus > 0){
            for (m3gInputItem* file in weakSelf.Files) {
                if(file.state == 0){
                    file.state = 2; //MP3Gain exited with an error. Show 'Bad File' error.
                }
            }
        }
        if(myself.terminationStatus == 0 && weakSelf.TwoPass == YES && weakSelf.Action == M3G_Apply){
            weakSelf.TwoPass = NO;
            [weakSelf cleanupTaskAndApply];
        }
        else if(weakSelf.onProcessingComplete){
            weakSelf.onProcessingComplete();
        }
    };
    @try{
        [_task launch];
    } @catch (NSException* exception){
        //Failed to launch mp3gain command line tool for some reason.
        //Add this task to the end of the list if this was the first time it failed, otherwise remove it and mark it as failed.
        if(self.FailureCount == 1){
            for (m3gInputItem* file in weakSelf.Files) {
                if(file.state == 0){
                    file.state = 2; //MP3Gain exited with an error. Show 'Bad File' error.
                }
            }
        }
        self.FailureCount = self.FailureCount + 1;
        if(self.FailureCount == 1){
            self.InProgress = NO;
        }
        if(self.onProcessingComplete){
            self.onProcessingComplete(); //Not actually complete, but this will check FailureCount and requeue the failures.
        }
    }
}

-(void)cleanupTaskAndApply{
    if(_statusHandle){
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleDataAvailableNotification object:_statusHandle];
        [_statusHandle closeFile];
    }
    _detailsPipe = nil;
    _statusPipe = nil;
    _statusHandle = nil;
    _task = nil;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ApplyGain];
    });
}

-(void)parseProcessDetails:(NSString*)details{
    NSArray<NSString*>* lines = [details componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString* line in lines) {
        NSNumberFormatter* numberParse = [NSNumberFormatter new];
        [numberParse setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        //The strings we search for are copy/pasted from the source of the mp3gain build we're running against, so they should be correct.
        NSRange trackChange = [line rangeOfString:@"Recommended \"Track\" dB change: "];
        NSRange clipping = [line rangeOfString:@"WARNING: some clipping may occur with this gain change!"];
        NSRange applyClipped = [line rangeOfString:@"Applying auto-clipped mp3 gain change of "];
        NSRange albumGain = [line rangeOfString:@"Recommended \"Album\" dB change for all files: "];
        NSRange notMp3 = [line rangeOfString:@"Can't find any valid MP3 frames"];
        NSRange alsoNotMp3 = [line rangeOfString:@"MPEG Layer I file, not a layer III file"];
        if(trackChange.location != NSNotFound){
            NSNumber* dbChange = [numberParse numberFromString:[line substringFromIndex:trackChange.location+trackChange.length]];
            if(dbChange){
                for (m3gInputItem* file in self.Files) {
                    float desiredDb = 89.0f;
                    if(self.DesiredDb){
                        desiredDb = [self.DesiredDb floatValue];
                    }
                    double gain = [dbChange doubleValue];
                    file.volume = desiredDb - gain;
                    file.track_gain = gain;
                }
            }
        }
        else if(clipping.location != NSNotFound){
            for (m3gInputItem* file in self.Files) {
                file.clipping = YES;
            }
        }
        else if(applyClipped.location != NSNotFound){
            NSUInteger searchStart = applyClipped.location+applyClipped.length;
            NSRange endOfNumber = [line rangeOfString:@" to " options:NSLiteralSearch range:NSMakeRange(searchStart, line.length-searchStart)];
            if(endOfNumber.location != NSNotFound){
                NSNumber* dbChange = [numberParse numberFromString:[line substringWithRange:NSMakeRange(searchStart, endOfNumber.location-searchStart)]];
                if(dbChange){
                    for (m3gInputItem* file in self.Files) {
                        file.track_gain = [dbChange doubleValue];
                    }
                }
            }
        }
        else if(albumGain.location != NSNotFound){
            NSNumber* dbChange = [numberParse numberFromString:[line substringFromIndex:albumGain.location+albumGain.length]];
            if(dbChange){
                for (m3gInputItem* file in self.Files) {
                    float desiredDb = 89.0f;
                    if(self.DesiredDb){
                        desiredDb = [self.DesiredDb floatValue];
                    }
                    double gain = [dbChange doubleValue];
                    file.volume = desiredDb - gain;
                    file.track_gain = gain;
                }
            }
        }
        else if(notMp3.location != NSNotFound || alsoNotMp3.location != NSNotFound){
            for (m3gInputItem* file in self.Files) {
                file.state = 3; //Not MP3 Error
            }
        }
    }
    
}

-(void)handleIncomingStatus:(NSNotification*)notification
{
    NSFileHandle* fileHandle = (NSFileHandle*)[notification object];
    NSData* data = [fileHandle availableData];
    
    if ([data length]) {
        NSString* actualText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        actualText = [actualText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        NSRange percentLoc = [actualText rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"%"]];
        NSRange noChangesToUndo = [actualText rangeOfString:@"No changes to undo in"];
        NSRange noUnfoInfo = [actualText rangeOfString:@"No undo information in"];
        if(actualText.length > 4 && percentLoc.location != NSNotFound && percentLoc.length == 1){
            //Find the % and convert it to a double
            NSString* number = [actualText substringWithRange:NSMakeRange(0, percentLoc.location)];
            NSNumber* progress = [[NSNumberFormatter new] numberFromString:number];
            if(progress && _onStatusUpdate){
                _onStatusUpdate([progress doubleValue]);
            }
        }
        else if(noChangesToUndo.location != NSNotFound || noUnfoInfo.location != NSNotFound){
            for (m3gInputItem* file in self.Files) {
                file.state = 1; //Nothing to undo
            }
        }
        
        [fileHandle waitForDataInBackgroundAndNotify];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleDataAvailableNotification object:fileHandle];
    }
}

@end
