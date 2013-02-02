//
//  Mp3GainAdapter.h
//
//  Created by Paul Kratt on 7/9/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "m3gInputItem.h"

@interface Mp3GainAdapter : NSObject
+(void)AnalyzeFile:(m3gInputItem*)item withVol:(double)desiredDb withProgress:(NSProgressIndicator*)progBar;
+(void)ModifyFile:(m3gInputItem*)item withVol:(double)desiredDb avoidClipping:(bool)dontClip withProgress:(NSProgressIndicator*)progBar;
+(void)UndoFileModify:(m3gInputItem*)item withProgress:(NSProgressIndicator*)progBar;
@end
