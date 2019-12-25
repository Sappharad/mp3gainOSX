//
//  FileProgressViewItem.m
//  MP3GainExpress
//

#import "FileProgressViewItem.h"

@interface FileProgressViewItem ()

@end

@implementation FileProgressViewItem

-(void)setRepresentedObject:(id)representedObject{
    [super setRepresentedObject:representedObject];
    self.IsStarted = NO;
    self.pbStatus.minValue = 0.0;
    self.pbStatus.maxValue = 100.0;
    self.pbStatus.usesThreadedAnimation = YES;
    
    if(NSAppKitVersionNumber < NSAppKitVersionNumber10_10){
        //Work-around for the progress bar not being visible on OS X 10.7
        //I think this is caused by using newer dev tools and couldn't find a fix.
        //So just use a different control instead because this one doesn't disappear.
        [self.pbStatus setHidden:YES];
        [self.pbStatusOld setHidden:NO];
    }
    
    if([representedObject isKindOfClass:[Mp3GainTask class]]){
        self.itemTask = representedObject;
        if(self.itemTask.Files.count > 1){
            [self.pbStatus setIndeterminate:YES];
        }
        self.itemTask.onStatusUpdate = ^(double percentComplete) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(self.pbStatus){
                    if(!self.IsStarted){
                        if(self.itemTask.Files.count > 1){
                            [self.pbStatus setIndeterminate:NO];
                        }
                        if(NSAppKitVersionNumber >= NSAppKitVersionNumber10_10){
                            [self.pbStatus startAnimation:self];
                        }
                        self.IsStarted = YES;
                    }
                    if(percentComplete == 100.0 && self.itemTask.Files.count > 1){
                        //Go back to indeterminate at the end of Album gain because it takes a few seconds to apply
                        //changes to all files after the scanning has finished.
                        [self.pbStatus setIndeterminate:YES];
                    }
                    else{
                        if(NSAppKitVersionNumber < NSAppKitVersionNumber10_10){
                            [self.pbStatusOld setDoubleValue:percentComplete];
                        }
                        else{
                            self.pbStatus.doubleValue = (double)percentComplete;
                        }
                    }
                }
            });
        };
        
        [_lblFilename setStringValue:[self.itemTask getDescription]];
    }
}

@end
