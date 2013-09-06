//
//  PhWebViewController.m
//  PhFacebook
//
//  Created by Philippe on 10-08-27.
//  Copyright 2010 Philippe Casgrain. All rights reserved.
//

#import "PhWebViewController.h"
#import "PhFacebook_URLs.h"
#import "PhFacebook.h"
#import "Debug.h"
#import "JSONKit.h"

//#define ALWAYS_SHOW_UI

@interface PhWebViewController ()

@property (retain) id popover;

@end

@implementation PhWebViewController

@synthesize window;
@synthesize webView;
@synthesize cancelButton;
@synthesize progressIndicator;
@synthesize parent;
@synthesize permissions;
@synthesize popover=_popover;

// Designated initializer
//
- (id) init
{
	if (self = [super initWithNibName:[self className] bundle:[NSBundle bundleForClass:[self class]]])
	{
        ;
	}
	return self;
}

- (id) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	// Disregard parameters - nib name is an implementation detail
	return [self init];
}

- (void) dealloc
{
    [_popover release];
    [super dealloc];
}

- (void) awakeFromNib
{
    NSBundle *bundle = [NSBundle bundleForClass: [PhFacebook class]];
    
    self.cancelButton.title = [bundle localizedStringForKey: @"FBAuthWindowCancel" value: @"" table: nil];

    if ([self preferPopover])
    {
        self.popover = [[[NSPopover alloc] init] autorelease];
        [self.popover setDelegate:self];
        [self.popover setContentViewController:self];
    } else {
        [self.window setContentView:self.view];
        self.window.title = [bundle localizedStringForKey: @"FBAuthWindowTitle" value: @"" table: nil];
        self.window.delegate = self;
        self.window.level = NSFloatingWindowLevel;
    }
}

- (BOOL) preferPopover
{
    //    return NO;
    return NSAppKitVersionNumber >= NSAppKitVersionNumber10_7;
}

- (void) setRelativeToRect:(NSRect)relativeToRect ofView:(NSView *)view
{
    _relativeToRect = relativeToRect;
    _rectParentView = view;
}

- (void) popoverWillClose: (NSNotification*) notification
{
    [parent performSelector: @selector(didDismissUI)];
}

- (void) windowWillClose: (NSNotification*) notification
{
    [parent performSelector: @selector(didDismissUI)];
}

#pragma mark Delegate

- (void) showUI
{
    // Facebook needs user input, so show login view
    
    // Use NSPopover when possible
    if ([self preferPopover]) {
        [self.popover showRelativeToRect:_relativeToRect ofView:_rectParentView preferredEdge:NSMaxYEdge];
    } else {
        // Use NSWindow as fallback
        [self.window makeKeyAndOrderFront: self];
    }
    // Notify parent that we're about to show UI
    [self.parent webViewWillShowUI];
}


/**
 
 */
- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    [self.progressIndicator startAnimation:self];
}


- (void) webView: (WebView*) sender didCommitLoadForFrame: (WebFrame*) frame;
{
    NSString *url = [sender mainFrameURL];
    DebugLog(@"didCommitLoadForFrame: {%@}", [url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);

    NSString *urlWithoutSchema = [url substringFromIndex: [@"http://" length]];
    if ([url hasPrefix: @"https://"])
        urlWithoutSchema = [url substringFromIndex: [@"https://" length]];
    
    NSString *uiServerURLWithoutSchema = [kFBUIServerURL substringFromIndex: [@"http://" length]];
    NSComparisonResult res = [urlWithoutSchema compare: uiServerURLWithoutSchema options: NSCaseInsensitiveSearch range: NSMakeRange(0, [uiServerURLWithoutSchema length])];
    if (res == NSOrderedSame)
        [self showUI];

#ifdef ALWAYS_SHOW_UI
    [self showUI];
#endif
}

- (NSString*) extractParameter: (NSString*) param fromURL: (NSString*) url
{
    NSString *res = nil;

    NSRange paramNameRange = [url rangeOfString: param options: NSCaseInsensitiveSearch];
    if (paramNameRange.location != NSNotFound)
    {
        // Search for '&' or end-of-string
        NSRange searchRange = NSMakeRange(paramNameRange.location + paramNameRange.length, [url length] - (paramNameRange.location + paramNameRange.length));
        NSRange ampRange = [url rangeOfString: @"&" options: NSCaseInsensitiveSearch range: searchRange];
        if (ampRange.location == NSNotFound)
            ampRange.location = [url length];
        res = [url substringWithRange: NSMakeRange(searchRange.location, ampRange.location - searchRange.location)];
    }

    return res;
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    [self showError:error];
}

-(void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    [self showError:error];
}

- (void) webView: (WebView*) sender didFinishLoadForFrame: (WebFrame*) frame
{
    [self.progressIndicator stopAnimation:self];

    NSString *url = [sender mainFrameURL];
    DebugLog(@"didFinishLoadForFrame: {%@}", [url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);

    NSString *urlWithoutSchema = [url substringFromIndex: [@"http://" length]];
    if ([url hasPrefix: @"https://"])
        urlWithoutSchema = [url substringFromIndex: [@"https://" length]];
    
    NSString *loginSuccessURLWithoutSchema = [kFBLoginSuccessURL substringFromIndex: 7];
    NSComparisonResult res = [urlWithoutSchema compare: loginSuccessURLWithoutSchema options: NSCaseInsensitiveSearch range: NSMakeRange(0, [loginSuccessURLWithoutSchema length])];
    if (res == NSOrderedSame)
    {
        NSString *accessToken = [self extractParameter: kFBAccessToken fromURL: url];
        NSString *tokenExpires = [self extractParameter: kFBExpiresIn fromURL: url];
        NSString *errorReason = [self extractParameter: kFBErrorReason fromURL: url];
        
        if (errorReason) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      errorReason, NSLocalizedDescriptionKey,
                                      nil];
            // For lack of better code picked arbitrary
            parent.loginError = [NSError errorWithDomain:@"PhFacebookError" code:-1 userInfo:userInfo];
        }
        [parent setAccessToken:accessToken expires:[tokenExpires floatValue] permissions:self.permissions];
        
        if ([self preferPopover]) {
            if ([self.popover isShown]) {
                [self.popover close];
            } else {
                // If popover was not shown we have to manually trigger a notification
                [self popoverWillClose:nil];
            }
        } else {
            [self.window close];
        }
    }
    else
    {
        // If access token is not retrieved, allow user to login/authorize or show an error message
        
        // Here we assume that getting a json response is always a sign of an error
        WebDataSource *dataSource = [[sender mainFrame] dataSource];
        if ([[[dataSource response] MIMEType] isEqualToString:@"application/json"]) {
            NSDictionary *responseDict = nil;
            if (NSAppKitVersionNumber >= NSAppKitVersionNumber10_7) {
                responseDict = (NSDictionary *) [NSJSONSerialization JSONObjectWithData:[dataSource data] options:0 error:nil];
            } else {
                responseDict = (NSDictionary *) [[JSONDecoder decoder] objectWithData:[dataSource data] error:nil];
            }
            NSLog(@"Error when loading Facebook page: %@", responseDict);
            [self showError:[self errorFromFacebookError:[responseDict valueForKey:@"error"]]];
        } else {
            [self showUI];
        }
        sender.UIDelegate = self;
    }

#ifdef ALWAYS_SHOW_UI
    [self showUI];
#endif
}

- (IBAction) cancel: (id) sender
{
    if ([self preferPopover]) {
        [self.popover close];
    } else {
        [self.window close];
    }
}

#pragma mark WebUIDelegate

// Need to implement this delegate method since user might click on "Cancel" button in web view
// which doesn't seem to trigger invocation of -popoverWillClose.
//
-(void)webViewClose:(WebView *)sender
{
    if ([self preferPopover]) {
        [self.popover close];
    } else {
        [self.window close];
    }
}

#pragma mark Utility

- (NSError *) errorFromFacebookError:(NSDictionary *)facebookError
{
    if (!facebookError) return nil;
    
    NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
    NSString *errorMessage = [myBundle localizedStringForKey: @"FBAuthWindowErrorGenericMessage" value: @"" table: nil];
    
//    IMBResourceAccessibility iMediaErrorCode;
    NSUInteger errorCode = [[facebookError valueForKey:@"code"] unsignedIntegerValue];
//    switch (errorCode) {
//        case 190:
//            iMediaErrorCode = kIMBResourceNoPermission;
//            break;
//            
//        default:
//            iMediaErrorCode = kIMBResourceNoPermission;
//    }
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: errorMessage};
    return [NSError errorWithDomain:@"PhFacebookError" code:errorCode userInfo:userInfo];
}

- (void) showError:(NSError *)error
{
    NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
    NSString *messagePath = [myBundle pathForResource:@"error_message" ofType:@"html"];
    NSURL *baseURL = [NSURL fileURLWithPath:[messagePath stringByDeletingLastPathComponent]];
    NSError *fileLoadingError = nil;
    NSString *errorIntro = [myBundle localizedStringForKey: @"FBAuthWindowErrorIntro" value: @"" table: nil];
    NSString *messageFormat = [NSString stringWithContentsOfFile:messagePath
                                                        encoding:NSUTF8StringEncoding
                                                           error:&fileLoadingError];
    NSString *errorMessage = [NSString stringWithFormat:messageFormat, errorIntro, error.localizedDescription];
    
    [self.webView.mainFrame loadHTMLString:errorMessage baseURL:baseURL];
    
    // Always log error to console to support support
    NSLog(@"%@: %@", errorIntro, error);
}
@end
