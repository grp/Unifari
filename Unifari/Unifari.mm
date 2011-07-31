//
//  Unifari.m
//  Unifari
//
//  Created by Grant Paul on 07/31/11.
//  Copyright 2011 Xuzz Productions, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>

#ifdef SUBSTRATE
#import <substrate.h>
#endif

@interface BrowserWindowControllerMac : NSWindowController {
}

- (id)searchField;
- (NSTextField *)locationField;
- (NSString *)_locationFieldText;
- (void)searchForString:(NSString *)search;

@end

@interface LocationTextField : NSTextField {
}

@end

static BOOL is_string_url(NSString *location) {
    if ([location hasPrefix:@"?"])
        return NO;
    
    NSUInteger offset = 0;
    
    offset = [location rangeOfString:@":"].location;
    if (offset != NSNotFound) {
        NSString *scheme = [location substringToIndex:offset];
        
        NSMutableCharacterSet *character = [NSMutableCharacterSet alphanumericCharacterSet];
        [character addCharactersInString:@"-"];
        BOOL alphanumeric = ([[scheme stringByTrimmingCharactersInSet:character] length] == 0);
        
        BOOL special = ([scheme isEqualToString:@"localhost"]);
        
        NSLog(@"i am alpha:%d and special:%d for string: %@", alphanumeric, special, scheme);
        
        if (alphanumeric && !special)
            return YES;
    }
    
    offset = [location rangeOfString:@"/"].location;
    if (offset != NSNotFound) {
        NSString *domain = [location substringToIndex:offset];
        
        BOOL space = ([domain rangeOfString:@" "].location != NSNotFound);
        BOOL dot = ([domain rangeOfString:@"."].location != NSNotFound);
        
        BOOL localhost = ([domain isEqualToString:@"localhost"]);
        
        if ((dot && !space) || localhost)
            return YES;
    }
    
    BOOL space = ([location rangeOfString:@" "].location != NSNotFound);
    BOOL dot = ([location rangeOfString:@"."].location != NSNotFound);
    
    if (dot && !space)
        return YES;
    
    return NO;
}

static void (*original_browserwindowcontrollermac_gototoolbarlocation)(BrowserWindowControllerMac *self, id _cmd, NSTextField *field);
static void browserwindowcontrollermac_gototoolbarlocation(BrowserWindowControllerMac *self, id _cmd, NSTextField *field) {
    NSString *location = [self _locationFieldText];
    location = [location stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (!is_string_url(location)) {
        [self searchForString:location];
    } else {
        original_browserwindowcontrollermac_gototoolbarlocation(self, _cmd, field);
    }
}

static void setup_window_controller(BrowserWindowControllerMac *browserController) {
    id searchField = [browserController searchField];
    [searchField removeFromSuperview];
}

static id supercall_browserwindowcontrollermac_initwithwindow(BrowserWindowControllerMac *self, SEL _cmd, NSWindow *window) {
    struct objc_super sup = { self, [self superclass] };
    return objc_msgSendSuper(&sup, _cmd, window);
}
static id (*original_browserwindowcontrollermac_initwithwindow)(BrowserWindowControllerMac *self, SEL _cmd, NSWindow *window);
static id browserwindowcontrollermac_initwithwindow(BrowserWindowControllerMac *self, SEL _cmd, NSWindow *window) {
    self = original_browserwindowcontrollermac_initwithwindow(self, _cmd, window);
    
    setup_window_controller(self);
    
    return self;
}

static BOOL (*original_locationtextfield_becomefirstresponder)(LocationTextField *self, SEL _cmd);
static BOOL locationtextfield_becomefirstresponder(LocationTextField *self, SEL _cmd) {
    BOOL result = original_locationtextfield_becomefirstresponder(self, _cmd);
    
    if (result) {
        [self performSelector:@selector(selectText:) withObject:self afterDelay:0];
    }
    
    return result;
}

static void hook_class(Class cls, SEL selector, IMP replacement, IMP *original) {
#ifdef SUBSTRATE
    MSHookMessageEx(cls, selector, replacement, original);
#endif
    
#ifdef SIMBL
    if (cls == nil || selector == NULL || replacement == NULL) {
        NSLog(@"ERROR: Couldn't hook because a required argument was nil or NULL.");
        return;
    }
    
    Method method = class_getInstanceMethod(cls, selector);
    
    if (method == NULL) {
        NSLog(@"ERROR: Unable to find method [%@ %@].", cls, NSStringFromSelector(selector));
        return;
    }
    
    IMP result = method_setImplementation(method, replacement);
    
    if (original != NULL) {
        *original = result;
    }
#endif
}

static void add_to_class(Class cls, SEL selector, IMP implementation, const char *encoding) {
    BOOL success = class_addMethod(cls, selector, implementation, encoding);   
    
    if (!success) {
        NSLog(@"ERROR: Unable to add [%@ %@].", cls, NSStringFromSelector(selector));
        return;
    }
}

#ifdef SUBSTRATE
__attribute__((constructor)) static void Unifari_init()
#endif

#ifdef SIMBL
@interface Unifari : NSObject { }
@end

@implementation Unifari
+ (void)load
#endif

{
    add_to_class(NSClassFromString(@"BrowserWindowControllerMac"), @selector(initWithWindow:), (IMP) supercall_browserwindowcontrollermac_initwithwindow, "@@:@");
    hook_class(NSClassFromString(@"BrowserWindowControllerMac"), @selector(initWithWindow:), (IMP) browserwindowcontrollermac_initwithwindow, (IMP *) &original_browserwindowcontrollermac_initwithwindow);
    hook_class(NSClassFromString(@"BrowserWindowControllerMac"), @selector(goToToolbarLocation:), (IMP) browserwindowcontrollermac_gototoolbarlocation, (IMP *) &original_browserwindowcontrollermac_gototoolbarlocation);
    hook_class(NSClassFromString(@"LocationTextField"), @selector(becomeFirstResponder), (IMP) locationtextfield_becomefirstresponder, (IMP *) &original_locationtextfield_becomefirstresponder);
    
#ifdef SIMBL
    for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
        NSWindowController *controller = [window windowController];
        
        if ([controller isKindOfClass:NSClassFromString(@"BrowserWindowControllerMac")]) {
            BrowserWindowControllerMac *browserController = (BrowserWindowControllerMac *) controller;
            setup_window_controller(browserController);
        }
    }
#endif
    
}

#ifdef SIMBL
@end
#endif

