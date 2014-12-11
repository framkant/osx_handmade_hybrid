#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>

// ffwd decl
@class HHView;

// Globals
static NSWindow *s_window;
static HHView *s_view;

// in NIB: "MainMenu" in file "Handmade.xib" (that is converted to Handmade.nib)
// - window IBoutlet
// - delegate IBoutlet


// In plist (that I create in makebudle script
// - menus
// - principal class (NSApplication)
// 

// View

// simple view from zenmumbler
@interface HHView : NSOpenGLView {
    CVDisplayLinkRef        _displayLink;
    void *                  _dataPtr;
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
    NSLog(@"callback");
    return result;
}

@implementation HHView

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSLog(@"initWithFrame");
    // setup pixel format
    NSOpenGLPixelFormatAttribute attribs[] = {
	NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
	NSOpenGLPFAAccelerated,
	NSOpenGLPFADoubleBuffer,
	NSOpenGLPFADepthSize, 24,
	NSOpenGLPFAAlphaSize, 8,
	NSOpenGLPFAColorSize, 32,
	NSOpenGLPFADepthSize, 24,
	NSOpenGLPFANoRecovery,
	kCGLPFASampleBuffers, 1,
	kCGLPFASamples, 1,
	0
    };
    
    NSOpenGLPixelFormat *fmt = [[NSOpenGLPixelFormat alloc]
				       initWithAttributes: attribs];
    
    self = [super initWithFrame: frameRect pixelFormat:fmt];

    
    if (self) {
	int width = frameRect.size.width;
	int height = frameRect.size.height;
	int rowBytes = 4 * width;
	_dataPtr = calloc(1, rowBytes * height); // calloc clears memory upon first touch	
    }
    
   
    
    return self;
}

- (void)prepareOpenGL
{
    NSLog(@"Preparing opengl");
    [super prepareOpenGL];
    [[self openGLContext] makeCurrentContext];
    [[self window] makeKeyAndOrderFront: self];
    
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

    // Display link
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, (__bridge void *)(self));

    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    CVDisplayLinkStart(_displayLink);
}
- (CVReturn) getFrameForTime:(const CVTimeStamp*)outputTime
{
    NSLog(@"getFrameForTImel");
    @autoreleasepool
    {
	[self drawRect: NSZeroRect];
    }
    
    return kCVReturnSuccess;
}
- (void*)bitmapData {
    return _dataPtr;
}

- (void)drawRect:(NSRect)dirtyRect {

    NSLog(@"drawing");
    CGLLockContext([[self openGLContext] CGLContextObj]);
    
    // Update the buffer
    /*static int xOffset = 100;
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
    */


    // copy into texture
    
    [[self openGLContext] makeCurrentContext];

    glClearColor(0.2, 0.2 ,0.22, 1);
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    // draw on a large triangle covering the whole screen
    
    
    

    CGLFlushDrawable([[self openGLContext] CGLContextObj]);
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
 }
@end


// AppDelegate
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, retain) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification{

    // Get a pointer the window (it is defined in the NIB)
    // Create a View for drawing graphics
    NSLog(@"applicationDidFinishLaunching");
    if (window)
    {
	s_window = window;
	NSRect frame = [[s_window contentView] bounds];
	s_view = [[HHView alloc] initWithFrame: frame];
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
    NSLog(@"Starting");
    return NSApplicationMain(argc, argv);
}


