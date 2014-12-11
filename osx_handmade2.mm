#import <Cocoa/Cocoa.h>

// ffwd ddecl
@class HHView;

// Globals
static NSWindow *s_window;
static HHView *s_view;

// in NIB:MainMenu in file Handmade.xib (that is converted to Handmade.nib)
// - menus
// - principal class (NSApplication)

// View

// simple view from zenmumbler
@interface HHView : NSView {
    void* dataPtr_;
    CGContextRef backBuffer_;
    CVDisplayLinkRef        displayLink_;
}
- (instancetype)initWithFrame:(NSRect)frameRect;
- (CVReturn) getFrameForTime:(const CVTimeStamp*)outputTime;
- (void)drawRect:(NSRect)dirtyRect;
- (void*)bitmapData;
@end

static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, 
				    const CVTimeStamp* now, 
				    const CVTimeStamp* outputTime, 
				    CVOptionFlags flagsIn, 
				    CVOptionFlags* flagsOut, 
				    void* displayLinkContext)
{
    CVReturn result = [(__bridge HHView*)displayLinkContext getFrameForTime:outputTime];
    
    return result;
}

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

	// Display link
	CVDisplayLinkCreateWithActiveCGDisplays(&displayLink_);
        if (displayLink_ != NULL) {
	    CGDirectDisplayID displayId = CVDisplayLinkGetCurrentCGDisplay(displayLink_);
	    CVDisplayLinkSetCurrentCGDisplay(displayLink_, displayId);
	    CVDisplayLinkSetOutputCallback(displayLink_, &DisplayLinkCallback, self);
            
            // Activate the display link
            CVDisplayLinkStart(displayLink_);
        }

	
	return self;
}

- (CVReturn) getFrameForTime:(const CVTimeStamp*)outputTime
{
    @autoreleasepool
    {
	[self drawRect: NSZeroRect];
    }
    
    return kCVReturnSuccess;
}
- (void*)bitmapData {
	return dataPtr_;
}

- (void)drawRect:(NSRect)dirtyRect {

    static int xOffset = 100;
    xOffset++;
    printf("x: %d\n", xOffset);
    uint32_t *bitmap = (uint32_t*)([s_view bitmapData]);
    int width = [s_view frame].size.width,
	height = [s_view frame].size.height;
    
    for (int y=0; y < height; ++y) {
	for (int x=0; x < width; ++x) {
	    uint8_t blue = x + xOffset;
	    uint8_t green = y;
	    *bitmap++ = ((green << 16) | blue << 8);
	}
	
    }
        
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGImageRef backImage = CGBitmapContextCreateImage(backBuffer_);
    CGContextDrawImage(ctx, self.frame, backImage);
    CGImageRelease(backImage);
}
@end


// AppDelegate
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
	s_window = window;

	NSRect rect = [[s_window contentView] bounds];
	s_view = [[HHView alloc] initWithFrame:rect];
	[s_window setContentView: s_view];
	
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    NSLog(@"applicationWillTerminate");
}


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
    return YES;
}
@end


// Entry

int main(int argc, const char * argv[]) {
    return NSApplicationMain(argc, argv);
}


