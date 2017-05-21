//
//  FileProgressViewItem.h
//  MP3GainExpress
//

#import <Cocoa/Cocoa.h>
#import "Mp3GainTask.h"

@interface FileProgressViewItem : NSCollectionViewItem
@property (assign) IBOutlet NSTextField *lblFilename;
@property (assign) IBOutlet NSProgressIndicator *pbStatus;
@property (nonatomic, assign) Mp3GainTask *itemTask;

@end
