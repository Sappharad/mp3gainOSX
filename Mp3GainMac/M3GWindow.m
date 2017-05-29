//
//  M3GWindow.m
//  MP3GainExpress
//
//  Created by Paul Kratt on 4/29/17.
//
//

#import "M3GWindow.h"

@implementation M3GWindow

-(void)awakeFromNib{
    NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
    if([osxMode isEqualToString:@"Dark"]){
        _originalView = self.contentView;
        NSRect contentFrame = self.contentView.frame;
        NSRect windowFrame = self.frame;
        
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        self.titlebarAppearsTransparent = YES;
        
        //NSVisualEffectView is only available in 10.10 and later. But so is Dark mode, so I shouldn't need to check if it exists.
        NSVisualEffectView* vev = [NSVisualEffectView new];
        vev.frame = contentFrame;
        vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        vev.state = NSVisualEffectStateActive;
        vev.material = NSVisualEffectMaterialUltraDark;
        self.styleMask = self.styleMask | NSFullSizeContentViewWindowMask;
        self.contentView = vev;
        
        [vev addSubview:_originalView];
        [_originalView setFrame:self.contentLayoutRect];
        [self setFrame:windowFrame display:YES];
        self.delegate = self;
        
        [self addObserver:self forKeyPath:@"contentLayoutRect" options:NSKeyValueObservingOptionNew context:nil];
    }
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if([keyPath isEqualToString:@"contentLayoutRect"]){
        [_originalView setFrame:self.contentLayoutRect];
    }
}

- (NSRect)window:(NSWindow *)window willPositionSheet:(NSWindow *)sheet
       usingRect:(NSRect)rect {
    NSRect region = self.contentLayoutRect;
    region.origin.y = region.origin.y + region.size.height;
    region.size.height = 0;
    return region;
}

@end
