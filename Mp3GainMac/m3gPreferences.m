//
//  m3gPreferences.m
//  MP3GainExpress
//
//  Created by Paul Kratt on 5/26/17.
//

#import "m3gPreferences.h"
#include <sys/sysctl.h>

@implementation m3gPreferences

static m3gPreferences* _preferences;

+(m3gPreferences*)SharedPreferences{
    if(_preferences == nil){
        _preferences = [m3gPreferences new];
    }
    return _preferences;
}

-(unsigned int)getMaxCores{
    unsigned int numCores;
    size_t len = sizeof(numCores);
    sysctlbyname("hw.ncpu", &numCores, &len, NULL, 0);
    
    return numCores;
}

-(int)getNumProcesses{
    unsigned int maxCores = [self getMaxCores];
    int retval = 2;
    if(maxCores >= 4){
        retval = 4;
    }
    
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    if([userDefaults objectForKey:@"m3g_NumProcesses"]){
        NSInteger userProcesses = [userDefaults integerForKey:@"m3g_NumProcesses"];
        if(userProcesses <= maxCores){
            retval = (int)userProcesses;
        }
    }
    return retval;
}

-(void)setNumProcesses:(int)numProcesses{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:numProcesses forKey:@"m3g_NumProcesses"];
}

-(BOOL)getRememberOptions{
    BOOL retval = YES;
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    if([userDefaults objectForKey:@"m3g_RememberOptions"]){
        retval = [userDefaults boolForKey:@"m3g_RememberOptions"];
    }
    return retval;
}

-(void)setRememberOptions:(BOOL)remember{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:remember forKey:@"m3g_RememberOptions"];
}

-(float)getVolume{
    float retval = 89.0;
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    if([userDefaults objectForKey:@"m3g_Volume"]){
        retval = [userDefaults floatForKey:@"m3g_Volume"];
    }
    
    return retval;
}

-(void)setVolume:(float)volume{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setFloat:volume forKey:@"m3g_Volume"];
}

-(BOOL)getNoClipping{
    BOOL retval = NO;
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    if([userDefaults objectForKey:@"m3g_NoClipping"]){
        retval = [userDefaults boolForKey:@"m3g_NoClipping"];
    }
    return retval;
}

-(void)setNoClipping:(BOOL)noClipping{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:noClipping forKey:@"m3g_NoClipping"];
}

@end
