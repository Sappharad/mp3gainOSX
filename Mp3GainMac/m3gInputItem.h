//
//  m3gInputItem.h
//  Mp3GainMac
//
//  Created by Paul Kratt on 7/4/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface m3gInputItem : NSObject{
    NSString* filePath;
    double volume;
    bool clipping;
    double track_gain;
    unsigned short state;
}
@property (retain) NSString* filePath;
@property double volume;
@property bool clipping;
@property double track_gain;
@property unsigned short state;
-(NSString*)getFilename;

@end
