//
//  m3gInputList.h
//  Mp3GainMac
//
//  Created by Paul Kratt on 7/5/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "m3gInputItem.h"

@interface m3gInputList : NSObject<NSTableViewDataSource>{
    NSMutableArray *list;
}
-(NSUInteger)count;
-(void)addObject:(m3gInputItem*)item;
-(m3gInputItem*)objectAtIndex:(int)idx;
-(void)clear;
-(void)removeAtIndex:(int)idx;

-(void)addFile:(NSString*)filePath;
- (void)addDirectory:(NSString*)folderPath subFoldersRemaining:(int)depth;

@end