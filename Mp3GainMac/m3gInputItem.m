//
//  m3gInputItem.m
//  Mp3GainMac
//
//  Created by Paul Kratt on 7/4/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "m3gInputItem.h"

@implementation m3gInputItem
@synthesize filePath;
@synthesize volume;
@synthesize clipping;
@synthesize track_gain;
@synthesize state;

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        volume = 0;
        track_gain = 0;
        clipping = NO;
    }
    
    return self;
}

-(NSString*)getFilename{
    return [filePath lastPathComponent];
}

@end
