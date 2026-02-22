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

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    m3gInputItem* item = [list objectAtIndex:row];
    
    NSString* identity = [tableColumn identifier];
    
    // Get a reused cell view or create a new one
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identity owner:self];
    
    if (cellView == nil) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cellView.identifier = identity;
        
        // Create text field for the cell
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        textField.bordered = NO;
        textField.backgroundColor = [NSColor clearColor];
        textField.editable = NO;
        textField.selectable = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        [cellView addSubview:textField];
        cellView.textField = textField;
        
        // Setup constraints for the text field to fill the cell
        [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-2-[textField]-2-|" 
                                                                          options:0 
                                                                          metrics:nil 
                                                                            views:@{@"textField": textField}]];
        [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[textField]|" 
                                                                          options:0 
                                                                          metrics:nil 
                                                                            views:@{@"textField": textField}]];
    }
    
    // Set the text based on column
    if([identity isEqualToString:@"File"]){
        cellView.textField.stringValue = [item getFilename];
    }
    else if([identity isEqualToString:@"Volume"]){
        if(item.volume > 0){
            cellView.textField.stringValue = [NSString stringWithFormat:@"%.2f dB", item.volume];
        }
        else if(item.state == 1){
            cellView.textField.stringValue = NSLocalizedString(@"NoUndo", @"Can't Undo");
        }
        else if(item.state == 2){
            cellView.textField.stringValue = NSLocalizedString(@"UnsupportedFile", @"Unsupported File");
        }
        else if(item.state == 3){
            cellView.textField.stringValue = NSLocalizedString(@"Not_MP3_file", @"Not MP3 file");
        }
        else {
            // Clear text for recycled cells to prevent stale data from previous row
            cellView.textField.stringValue = @"";
        }
    }
    else if([identity isEqualToString:@"Clipping"]){
        // Clipping is always a boolean (Yes/No), so no need to clear for recycling
        cellView.textField.stringValue = item.clipping?NSLocalizedString(@"Yes", @"Yes"):NSLocalizedString(@"No", @"No");
    }
    else if([identity isEqualToString:@"TrackGain"]){ //Not a mistake, don't use item.track_gain.
        if(item.volume > 0){
            cellView.textField.stringValue = [NSString stringWithFormat:@"%.2f dB", item.track_gain];
        }
        else {
            // Clear text for recycled cells to prevent stale data from previous row
            cellView.textField.stringValue = @"";
        }
    }
    
    return cellView;
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
    if([[filePath lowercaseString] hasSuffix:@".mp3"] ||
       [[filePath lowercaseString] hasSuffix:@".mp4"] ||
       [[filePath lowercaseString] hasSuffix:@".m4a"]) {
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
