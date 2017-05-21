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
    else if([identity isEqualToString:@"Volume"]){
        if(item.volume > 0){
            return [NSString stringWithFormat:@"%.2f dB", item.volume];
        }
        else if(item.state == 1){
            return NSLocalizedStringFromTable(@"NoUndo", @"ui_text", @"Can't Undo");
        }
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

-(NSMutableArray<m3gInputItem*>*)allObjects{
    return list;
}

-(void)clear{
    [list removeAllObjects];
}

-(void)removeAtIndex:(int)idx{
    [list removeObjectAtIndex:idx];
}

#pragma mark Drag and Drop

-(NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation{
	    [tableView setDropRow:-1 dropOperation:NSTableViewDropOn]; //We always want to light up the table itself
	    NSArray* fileList = [[info draggingPasteboard] readObjectsForClasses:@[[NSURL class]] options:nil];
	    if(fileList.count > 0){
	        bool hasFiles = NO;
	        for(NSURL* url in fileList){
	            if(url.isFileURL){
	                hasFiles = YES;
	                break;
	            }
	        }
	        if(hasFiles){
	            return NSDragOperationCopy;
	        }
	    }
	    return NSDragOperationNone;
}

-(BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation{
    NSArray* fileList = [[info draggingPasteboard] readObjectsForClasses:@[[NSURL class]] options:nil];
    NSFileManager* fileMgr = [NSFileManager defaultManager];
    for(NSURL* url in fileList){
        if(url.isFileURL){
            BOOL isDir = NO;
            if([fileMgr fileExistsAtPath:url.path isDirectory:&isDir]){
                if(isDir){
                    //You're getting 5 as the default, unless I make this configurable some day
                    [self addDirectory:url.path subFoldersRemaining:5];
                }
                else{
                    [self addFile:url.path];
                }
            }
        }
    }
    [tableView reloadData];
    return NO;
}

-(void)addFile:(NSString*)filePath{
    //Note: Assumes file already exists. You should check this before calling this.
    if([[filePath lowercaseString] hasSuffix:@".mp3"]) {
        m3gInputItem* itemToAdd = [[m3gInputItem alloc] init];
        itemToAdd.filePath = [NSURL fileURLWithPath:filePath];
        [self addObject:itemToAdd];
    }
}

- (void)addDirectory:(NSString*)folderPath subFoldersRemaining:(int)depth{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray* files = [fileManager contentsOfDirectoryAtPath:folderPath error:nil];
    if(files != nil){
        if(![folderPath hasSuffix:@"/"]) folderPath = [folderPath stringByAppendingString:@"/"];
        int fileCount = (uint)[files count];
        for(int j=0; j<fileCount; j++){
            NSString* filePath = [folderPath stringByAppendingString:[files objectAtIndex:j]];
            BOOL isDirFlag = false;
            if([fileManager fileExistsAtPath:filePath isDirectory:&isDirFlag]==TRUE)
            {
                if(isDirFlag==FALSE) {
                    [self addFile:filePath];
                }
                else if(isDirFlag==TRUE && depth > 0){
                    [self addDirectory:filePath subFoldersRemaining:(depth-1)];
                }
            }
        }
    }
}

@end
