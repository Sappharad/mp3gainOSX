//
//  Mp3GainTask.h
//  MP3GainExpress
//

#import <Foundation/Foundation.h>
#import "m3gInputItem.h"

typedef enum : NSUInteger {
    M3G_Analyze,
    M3G_Apply,
    M3G_Undo,
} MP3GActionType;

@interface Mp3GainTask : NSObject{
    NSTask* _task;
    NSPipe* _detailsPipe;
    NSPipe* _statusPipe;
    NSFileHandle* _statusHandle;
}
@property (retain) NSArray<m3gInputItem*>* Files;
@property MP3GActionType Action;
@property (retain) NSNumber* DesiredDb;
@property BOOL NoClipping;
@property BOOL InProgress;
@property BOOL TwoPass;
@property (nonatomic, copy) void(^onProcessingComplete)();
@property (nonatomic, copy) void(^onStatusUpdate)(double percentComplete);

+(Mp3GainTask*)taskWithFile:(m3gInputItem*)file action:(MP3GActionType)action;
+(Mp3GainTask*)taskWithFiles:(NSArray<m3gInputItem*>*)files action:(MP3GActionType)action;
-(void)process;
-(NSString*)getDescription;

@end

