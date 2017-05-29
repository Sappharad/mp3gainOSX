//
//  m3gPreferences.h
//  MP3GainExpress
//
//  Created by Paul Kratt on 5/26/17.
//

#import <Foundation/Foundation.h>

@interface m3gPreferences : NSObject

+(m3gPreferences*)SharedPreferences;

@property (readonly, getter=getMaxCores) unsigned int MaxCores;
@property (getter=getNumProcesses, setter=setNumProcesses:) int NumProcesses;
@property (getter=getRememberOptions, setter=setRememberOptions:) BOOL RememberOptions;
@property (getter=getVolume, setter=setVolume:) float Volume;
@property (getter=getNoClipping, setter=setNoClipping:) BOOL NoClipping;

@end
