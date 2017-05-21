//
//  FileProgressViewItem.m
//  MP3GainExpress
//

#import "FileProgressViewItem.h"

@interface FileProgressViewItem ()

@end

@implementation FileProgressViewItem

- (void)viewDidLoad {
    [super viewDidLoad];
    self.pbStatus.minValue = 0.0;
    self.pbStatus.maxValue = 100.0;
}

-(void)setRepresentedObject:(id)representedObject{
    [super setRepresentedObject:representedObject];
    
    if([representedObject isKindOfClass:[Mp3GainTask class]]){
        self.itemTask = representedObject;
        if(self.itemTask.Files.count > 1){
            [self.pbStatus setIndeterminate:YES];
        }
        else{
            self.itemTask.onStatusUpdate = ^(double percentComplete) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if(self.pbStatus){
                        self.pbStatus.doubleValue = (double)percentComplete;
                    }
                });
            };
        }
        [_lblFilename setStringValue:[self.itemTask getDescription]];
    }
}

@end
