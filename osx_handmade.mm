#import <Cocoa/Cocoa.h>
#import <CoreVideo/CVDisplayLink.h>

// NOTE:
// This is a work in progress.
// I trying to understand how the cocoa run loop works
// For the moment this is a hybrid approach where I have a xib with
// window, some kind of default view, menubar etc
// I use the simple view from @zenmumbler for making sure
// the view is set at all.
//
// Currently there are many problems:
// 1. Doesn't seem to terminate as expected
// 2. lot's of implicit things depending on names set in the XIB and plist
//   - the build script (makebundle) creates a plist where the principa class
//     is set to <bundlename>Application, so using "Handmade" for bundlename
//     we get a principal class "HandmadeApplication"
//     this needs to be set in the XIB as well
//     it is assumed you do this on the initial setup in xcode



// Globals
static NSWindow* s_window;
@class HHView;


// Application delegate that takes care of init  and terminiation
// NOTE: why can this not be in the Application object itself?
// Can I let NSApplication implement the <NSApplicationDelegate> protocol?
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, retain) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification{
    NSLog(@"applicationDidFinishLaunching");
   
    if (window)
    {
	NSLog(@"We also have a window");
    }
    s_window = window;// [windows objectAtIndex: 0];

    if (s_window ) {
	NSLog(@"got window!");
	NSRect rect = [[s_window contentView] bounds];
	HHView *mainView = [[HHView alloc] initWithFrame:rect];
	[s_window setContentView: mainView];
    }else {
	NSLog(@"no windows");
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    NSLog(@"applicationWillTerminate");
}


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
    NSLog(@"applicationShouldTerminateAfterLastWindowClosed");
    return YES;
}



@end

// simple view from zenmumbler
@interface HHView : NSView {
	void* dataPtr_;
	CGContextRef backBuffer_;
}
- (instancetype)initWithFrame:(NSRect)frameRect;
- (void)drawRect:(NSRect)dirtyRect;
- (void*)bitmapData;
@end
@implementation HHView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame: frameRect];
	if (self) {
		int width = frameRect.size.width;
		int height = frameRect.size.height;
		int rowBytes = 4 * width;
		dataPtr_ = calloc(1, rowBytes * height); // calloc clears memory upon first touch
		
		CMProfileRef prof; // these 2 calls are deprecated as of 10.6, but still work and I can't find their modern equivalent.
		CMGetSystemProfile(&prof);
		CGColorSpaceRef colorSpace = CGColorSpaceCreateWithPlatformColorSpace(prof);
		
		backBuffer_ = CGBitmapContextCreate(dataPtr_, width, height, 8, rowBytes, colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
		CGColorSpaceRelease(colorSpace);
		CMCloseProfile(prof);
	}
	return self;
}

- (void*)bitmapData {
	return dataPtr_;
}

- (void)drawRect:(NSRect)dirtyRect {
	CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
	CGImageRef backImage = CGBitmapContextCreateImage(backBuffer_);
	CGContextDrawImage(ctx, self.frame, backImage);
	CGImageRelease(backImage);
}
@end

@interface HandmadeApplication : NSApplication
{
    bool _shouldKeepRunning;
}
- (void) run;
- (void) terminate:(id)sender;
@end

@implementation HandmadeApplication

- (void)run
{
    NSLog(@"Calling run 1");
    
    [[NSNotificationCenter defaultCenter]
		postNotificationName:NSApplicationWillFinishLaunchingNotification
			      object:NSApp];
    [[NSNotificationCenter defaultCenter]
		postNotificationName:NSApplicationDidFinishLaunchingNotification
			      object:NSApp];
    NSLog(@"Calling run 2");
    _shouldKeepRunning = YES;
    do
    {
	NSEvent *event =
	    
	    [self nextEventMatchingMask:NSAnyEventMask
			      untilDate:[NSDate distantFuture]
				 inMode:NSDefaultRunLoopMode
				dequeue:YES];
	
	[self sendEvent:event];
	[self updateWindows];
    } while (_shouldKeepRunning);

    [[NSNotificationCenter defaultCenter]
		postNotificationName:NSApplicationWillTerminateNotification
			      object:NSApp];
    
}

- (void)terminate:(id)senderframe
{
    NSLog(@"got termninte");
    _shouldKeepRunning = NO;
}

@end
static NSArray* s_nibObjects;
int HandmadeApplicationMain(int argc, const char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    // get the plist
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    // Find principal class (HandmadeApplication)
    Class principalClass =
	NSClassFromString([infoDictionary objectForKey:@"NSPrincipalClass"]);
    NSApplication *applicationObject = [principalClass sharedApplication];

    AppDelegate *appDelegate = [applicationObject delegate];
    NSString *mainNibName = [infoDictionary objectForKey:@"NSMainNibFile"];
    [[NSBundle mainBundle] loadNibNamed: mainNibName owner:appDelegate topLevelObjects: &s_nibObjects];
//    NSNib *mainNib = [[NSNib alloc] initWithNibNamed:mainNibName bundle:[NSBundle mainBundle]];
    NSLog([principalClass description]);
    NSLog(@"Main nib name");
    NSLog(mainNibName);
    // NOTE: top level objects need to be retained or they will be deallocated


    if(applicationObject)
    {
	NSLog(@"Got valid app");
    }
    
    // [mainNib instantiateWithOwner:applicationObject topLevelObjects:&s_nibObjects];
    NSLog(@"HandmadeApplicationMain");

    // get frame from window
   
    
    if ([applicationObject respondsToSelector:@selector(run)])
    {
	[applicationObject
			performSelectorOnMainThread:@selector(run)
					 withObject:nil
				      waitUntilDone:YES];
    }
    NSLog(@"HandmadeApplicationMain after run");
    //[mainNib release];
    [pool release];
	
    return 0;
}



// Entry point
// NOTE(filip): See cocoa with love for example of this 
int main(int argc, const char * argv[]) {
    return HandmadeApplicationMain(argc, argv);
}


