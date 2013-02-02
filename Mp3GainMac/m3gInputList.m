//
//  m3gInputList.m
//  Mp3GainMac
//
//  Created by Paul Kratt on 7/5/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "m3gInputList.h"

@implementation m3gInputList

- (id)init
{
    self = [super init];
    if (self) {
        list = [[NSMutableArray alloc] init];
    }
    
    return self;
}

-(void)addObject:(m3gInputItem*)item{
    bool hasAlready = false;
    for(int i=0; i<[list count]; i++){
        m3gInputItem* oldThing = [list objectAtIndex:i];
        if ([[oldThing.filePath path] isEqual:[item.filePath path]]) {
            hasAlready = true;
        }
    }
    
    if(!hasAlready){
        [list addObject:item];
    }
}

- (id)tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
    m3gInputItem* item = [list objectAtIndex:rowIndex];
    
    NSString* identity = [aTableColumn identifier];
    if([identity isEqualToString:@"File"]){
        return [item getFilename];
    }
    else if([identity isEqualToString:@"Volume"] && item.volume > 0){
        return [NSString stringWithFormat:@"%.2f dB", item.volume];
    }
    else if([identity isEqualToString:@"Clipping"]){
        return item.clipping?NSLocalizedStringFromTable(@"Yes", @"ui_text", @"Yes"):NSLocalizedStringFromTable(@"No", @"ui_text", @"No");
    }
    else if([identity isEqualToString:@"TrackGain"] && item.volume > 0){ //Not a mistake, don't use item.track_gain.
        return [NSString stringWithFormat:@"%.2f dB", item.track_gain];
    }
    
    return nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)aTableView
{
    return [list count];  
}

-(NSUInteger)count{
    return [list count];
}

-(m3gInputItem*)objectAtIndex:(int)idx{
    return [list objectAtIndex:idx];
}

-(void)clear{
    [list removeAllObjects];
}

-(void)removeAtIndex:(int)idx{
    [list removeObjectAtIndex:idx];
}

@end
