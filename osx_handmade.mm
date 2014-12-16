
#import <Cocoa/Cocoa.h>

// Genral defines and types
#define internal static 
#define local_persist static 
#define global_variable static

#define Pi32 3.14159265359f

typedef int8_t int8;
typedef int16_t int16;
typedef int32_t int32;
typedef int64_t int64;
typedef int32 bool32;

typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;

typedef float real32;
typedef double real64;

// The game
#include "handmade.h"
#include "handmade.cpp"


// For the platform layer
#import <OpenGL/gl3.h>
#import "IOKit/hid/IOHIDManager.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

#include "osx_handmade.h"

/*
 #####  #       ####### ######     #    #        #####  
#     # #       #     # #     #   # #   #       #     # 
#       #       #     # #     #  #   #  #       #       
#  #### #       #     # ######  #     # #        #####  
#     # #       #     # #     # ####### #             # 
#     # #       #     # #     # #     # #       #     # 
 #####  ####### ####### ######  #     # #######  #####  
*/                                                        

global_variable osx_offscreen_buffer GlobalBackbuffer;

@class HandmadeView;
static NSWindow *s_window;
static HandmadeView *s_view;

// in NIB: "MainMenu" in file "Handmade.xib"
// (that is converted to Handmade.nib using libtool and copied into bundle)
// - window IBoutlet
// - delegate IBoutlet

// In plist (that I create in makebudle script)
// - menus
// - principal class "NSApplication"
// 

// https://developer.apple.com/library/mac/documentation/DeviceDrivers/Conceptual/HID/new_api_10_5/tn2187.html#//apple_ref/doc/uid/TP40000970-CH214-SW2

// example where queues are used:
//https://github.com/gameplay3d/GamePlay/blob/master/gameplay/src/PlatformMacOSX.mm

/*
####### ### #       #######    ### ####### 
#        #  #       #           #  #     # 
#        #  #       #           #  #     # 
#####    #  #       #####       #  #     # 
#        #  #       #           #  #     # 
#        #  #       #           #  #     # 
#       ### ####### #######    ### ####### 
                                           
*/

#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>   // fstat()
#include <unistd.h>     // lseek()
#include <fcntl.h>

#include "osx_handmade.h"

internal debug_read_file_result
DEBUGPlatformReadEntireFile(char* Filename)
{
    debug_read_file_result Result = {};

    int fd = open(Filename, O_RDONLY);
    if (fd != -1)
    {
        struct stat fileStat;
        if (fstat(fd, &fileStat) == 0)
        {
            uint32 FileSize32 = fileStat.st_size;
            Result.Contents = (char*)malloc(FileSize32);
            if (Result.Contents)
            {
                ssize_t BytesRead;
                BytesRead = read(fd, Result.Contents, FileSize32);
                if (BytesRead == FileSize32) // should have read until EOF
                {
                    Result.ContentsSize = FileSize32;
                }
                else
                {
                    DEBUGPlatformFreeFileMemory(Result.Contents);
                    Result.Contents = 0;
                }
            }
            else
            {
            }
        }
        else
        {
        }

        close(fd);
    }
    else
    {
    }

    return Result;
}


internal void
DEBUGPlatformFreeFileMemory(void* Memory)
{
    if (Memory)
    {
        free(Memory);
    }
}


internal bool32
DEBUGPlatformWriteEntireFile(char* Filename, uint32 MemorySize, void* Memory)
{
    bool32 Result = false;

    int fd = open(Filename, O_WRONLY | O_CREAT, 0644);
    if (fd != -1)
    {
        ssize_t BytesWritten = write(fd, Memory, MemorySize);
        Result = (BytesWritten == MemorySize);

        if (!Result)
        {
            // TODO(jeff): Logging
        }

        close(fd);
    }
    else
    {
    }

    return Result;
}


/*
#     # ### ######  
#     #  #  #     # 
#     #  #  #     # 
#######  #  #     # 
#     #  #  #     # 
#     #  #  #     # 
#     # ### ######                    
*/
// IO for gamepad
struct Devices {
    int x;
};
Devices g_devices;

static void OSXHIDDeviceAdded(
    void *          inContext,       // context from IOHIDManagerRegisterDeviceMatchingCallback
    IOReturn        inResult,        // the result of the matching operation
    void *          inSender,        // the IOHIDManagerRef for the new device
    IOHIDDeviceRef  inIOHIDDeviceRef // the new HID device
) {
    //printf("%s(context: %p, result: %p, sender: %p, device: %p).\n",
    //   __PRETTY_FUNCTION__, inContext, (void *) inResult, inSender, (void*) inIOHIDDeviceRef);
}   

// this will be called when a HID device is removed (unplugged)
static void OSXHIDDeviceRemoved(
    void *         inContext,       // context from IOHIDManagerRegisterDeviceMatchingCallback
    IOReturn       inResult,        // the result of the removing operation
    void *         inSender,        // the IOHIDManagerRef for the device being removed
    IOHIDDeviceRef inIOHIDDeviceRef // the removed HID device
    ) {
    //printf("%s(context: %p, result: %p, sender: %p, device: %p).\n",
    //        __PRETTY_FUNCTION__, inContext, (void *) inResult, inSender, (void*) inIOHIDDeviceRef);
}

static void OSXHIDValueChanged(
                void *          inContext,      // context from IOHIDManagerRegisterInputValueCallback
                IOReturn        inResult,       // completion result for the input value operation
                void *          inSender,       // the IOHIDManagerRef
                IOHIDValueRef   value // the new element value
) {

    
	IOHIDElementRef element = IOHIDValueGetElement(value);
	if (CFGetTypeID(element) != IOHIDElementGetTypeID())
	{
	    return;
	}
	
	IOHIDElementCookie cookie = IOHIDElementGetCookie(element);
	IOHIDElementType type = IOHIDElementGetType(element);
	CFStringRef name = IOHIDElementGetName(element);
	int usagePage = IOHIDElementGetUsagePage(element);
	int usage = IOHIDElementGetUsage(element);
	if( IOHIDValueGetLength(value) > 2 )
	    return;
	
	CFIndex elementValue = IOHIDValueGetIntegerValue(value);

	//printf("element valuel:%d\n", elementValue);
    
    //printf("%s(context: %p, result: %p, sender: %p, value: %p).\n",
    //__PRETTY_FUNCTION__, inContext, (void *) inResult, inSender, (void*) inIOHIDValueRef);
} 


void OSXHIDSetup()
{
  
    IOHIDManagerRef hidManager = IOHIDManagerCreate(kCFAllocatorDefault,
						    kIOHIDOptionsTypeNone);

    // from http://dolphin-emu.googlecode.com/svn-history/r5793/trunk/Source/Core/InputCommon/Src/ControllerInterface/OSX/OSX.mm
    // HID Manager will give us the following devices:
    // Keyboard, Keypad, Mouse, GamePad
    NSArray *matchingDevices =
	[NSArray arrayWithObjects:
		     /*[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_Keyboard],
			       @kIOHIDDeviceUsageKey, nil],
		 
		 [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_Keypad],
			       @kIOHIDDeviceUsageKey, nil],
		 
		 [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_Mouse],
			       @kIOHIDDeviceUsageKey, nil],
		     */
		 [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_GamePad],
			       @kIOHIDDeviceUsageKey, nil],
		 nil];

    // Pass NULL to get all devices
    IOHIDManagerSetDeviceMatchingMultiple(hidManager, (CFArrayRef)matchingDevices);

    // Callbacks for acquisition or loss of a matching device
    IOHIDManagerRegisterDeviceMatchingCallback(hidManager,
					       OSXHIDDeviceAdded, (void *)&g_devices);
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager,
					       OSXHIDDeviceRemoved, (void *)&g_devices);

    // Match devices that are plugged in right now
    IOHIDManagerScheduleWithRunLoop(hidManager,
				    CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    if (IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
	NSLog(@"Failed to open HID Manager");
    }else {
	IOHIDManagerRegisterInputValueCallback(hidManager, OSXHIDValueChanged, (void*)&g_devices);
    }
    
    // Wait while current devices are initialized
    // while (CFRunLoopRunInMode(OurRunLoop, 0, TRUE) ==
    // 	   kCFRunLoopRunHandledSource);
    
    // TODO(filip): ok, device added ok  
}
/*
   #    #     # ######  ### ####### 
  # #   #     # #     #  #  #     # 
 #   #  #     # #     #  #  #     # 
#     # #     # #     #  #  #     # 
####### #     # #     #  #  #     # 
#     # #     # #     #  #  #     # 
#     #  #####  ######  ### #######                                     
*/








/*
####### ######  ####### #     #  #####  #       
#     # #     # #       ##    # #     # #       
#     # #     # #       # #   # #       #       
#     # ######  #####   #  #  # #  #### #       
#     # #       #       #   # # #     # #       
#     # #       #       #    ## #     # #       
####### #       ####### #     #  #####  ####### 
*/                                                
// OpenGL utils
const char* GetErrorString(GLenum errorCode)
{
    static const struct {
        GLenum code;
        const char *string;
    } errors[]=
    {
        /* GL */
        {GL_NO_ERROR, "no error"},
        {GL_INVALID_ENUM, "invalid enumerant"},
        {GL_INVALID_VALUE, "invalid value"},
        {GL_INVALID_OPERATION, "invalid operation"},
//        {GL_STACK_OVERFLOW, "stack overflow"},
//        {GL_STACK_UNDERFLOW, "stack underflow"},
        {GL_OUT_OF_MEMORY, "out of memory"},

        {0, NULL }
    };

    int i;

    for (i=0; errors[i].string; i++)
    {
        if (errors[i].code == errorCode)
        {
            return errors[i].string;
        }
     }

    return NULL;
}
int PrintOglError(char *file, int line)
{

    GLenum glErr;
    int    retCode = 0;

    glErr = glGetError();
    if (glErr != GL_NO_ERROR)
    {
        printf("glError in file %s @ line %d: %s\n",
			     file, line, GetErrorString(glErr));
        retCode = 1;
    }
    return retCode;
}
#define PrintOpenGLError() PrintOglError(__FILE__, __LINE__)

/*
 #####  #          #     #####   #####  #######  #####  
#     # #         # #   #     # #     # #       #     # 
#       #        #   #  #       #       #       #       
#       #       #     #  #####   #####  #####    #####  
#       #       #######       #       # #             # 
#     # #       #     # #     # #     # #       #     # 
 #####  ####### #     #  #####   #####  #######  #####  
*/                                                      

#pragma mark -- ObjC classes --

// View
@interface HandmadeView : NSOpenGLView {
    CVDisplayLinkRef        _displayLink;
    
    osx_offscreen_buffer    _offscreenBuffer;
    game_memory             _gameMemory;

    GLuint _vao;
    GLuint _vbo;
    GLuint _tex;
    GLuint _program;
    
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
    CVReturn result = [(__bridge HandmadeView*)displayLinkContext getFrameForTime:outputTime];
    // NSLog(@"callback");
    return result;
}


/*
### #     # ### ####### 
 #  ##    #  #     #    
 #  # #   #  #     #    
 #  #  #  #  #     #    
 #  #   # #  #     #    
 #  #    ##  #     #    
### #     # ###    #    
*/
@implementation HandmadeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSLog(@"initWithFrame");
    // setup pixel format
    NSOpenGLPixelFormatAttribute attribs[] = {

	NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        0
    };
    
    NSOpenGLPixelFormat *fmt = [[NSOpenGLPixelFormat alloc]
				       initWithAttributes: attribs];
    
    self = [super initWithFrame: frameRect pixelFormat:fmt];
    
    // Offscreen render buffer 
    if (self) {
        int BytesPerPixel = 4;
        _offscreenBuffer.Width = 1280;
        _offscreenBuffer.Height = 720;
        _offscreenBuffer.BytesPerPixel = BytesPerPixel;
        _offscreenBuffer.Pitch = _offscreenBuffer.Width * BytesPerPixel;
        _offscreenBuffer.Memory = calloc(1, _offscreenBuffer.Pitch * _offscreenBuffer.Height);
    }

    // General Game mem

    _gameMemory.PermanentStorageSize = Megabytes(64);
    _gameMemory.TransientStorageSize = Gigabytes(1);

    uint64 totalSize = _gameMemory.PermanentStorageSize + _gameMemory.TransientStorageSize;
    // TODO(casey): Handle various memory footprints (USING SYSTEM METRICS)
    uint64 TotalSize = _gameMemory.PermanentStorageSize + _gameMemory.TransientStorageSize;
    kern_return_t result = vm_allocate((vm_map_t)mach_task_self(),
                                       (vm_address_t*)&_gameMemory.PermanentStorage,
                                       totalSize,
                                       VM_FLAGS_ANYWHERE);
    if (result != KERN_SUCCESS)
    {
        NSLog(@"Error allocating memory");
    }
    
    _gameMemory.TransientStorage = ((uint8*)_gameMemory.PermanentStorage
                                   + _gameMemory.PermanentStorageSize);

    // init joysticks etc
    OSXHIDSetup();
    return self;
}

#define BUFFER_OFFSET(i) ((char *)NULL + (i))
- (void)prepareOpenGL
{
    NSLog(@"Preparing opengl");
    [super prepareOpenGL];
    [[self openGLContext] makeCurrentContext];
    [[self window] makeKeyAndOrderFront: self];
    
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

    // Create a texture object
    glGenTextures(1, &_tex);
    glBindTexture(GL_TEXTURE_2D, _tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _offscreenBuffer.Width, _offscreenBuffer.Height,
		 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
    // Create opengl objects
    // fullscreen quad using two triangles
    glGenVertexArrays(1, &_vao);
    glBindVertexArray(_vao);

    glGenBuffers(1, &_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    PrintOpenGLError();
    // define data and upload (interleaved x,y,z,s,t
    // A-D
    // |\|
    // B-C
     
    GLfloat vertices[] = {
	-1,  1, 0, 0, 1, // A
	-1, -1, 0, 0, 0, // B
	1,  -1, 0, 1, 0, // C

	-1,  1, 0, 0, 1, // A
	1,  -1, 0, 1, 0, // C
	1,  1,  0, 1, 1 //  D 
    };
    size_t bytes = sizeof(GLfloat) * 6 *5;

    // upload data
    glBufferData(GL_ARRAY_BUFFER, bytes, vertices, GL_STATIC_DRAW);
    // specify vertex format
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(float)*5, BUFFER_OFFSET(0));

    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 2, GL_FLOAT, GL_FALSE, sizeof(float)*5, BUFFER_OFFSET(12));
    PrintOpenGLError();
    // Shader source
    static const char* vertexShaderString =
	"#version 330 core\n"
	"layout (location = 2) in vec3 position;\n"
	"layout (location = 3) in vec2 texcoord;\n"
	"out vec2 v_texcoord;\n"
	"void main(void) {\n"
	"	gl_Position  = vec4(position, 1.0);\n"
	"       v_texcoord = texcoord;\n"
	"}\n";

    static const char* fragmentShaderString =
	"#version 330 core\n"
	"layout (location = 0) out vec4 outColor0;\n"
	"uniform sampler2D tex0;\n"
	"in vec2 v_texcoord;\n "
	"void main(void)\n"
	"{\n"
	"        vec4 texel = texture(tex0, v_texcoord.st);\n"
	"        outColor0 = texel;\n"
	"}\n";
    
    // Create the shader
    GLuint program, vertex, fragment;
    program = glCreateProgram();
    vertex = glCreateShader(GL_VERTEX_SHADER);
    fragment = glCreateShader(GL_FRAGMENT_SHADER);
    GLint logLength;
    GLint status;	
    PrintOpenGLError();
    glShaderSource(vertex, 1, (const GLchar **)&vertexShaderString, NULL);
    glCompileShader(vertex);
	
    glGetShaderiv(vertex, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
	GLchar *log = (GLchar *)malloc(logLength);
	glGetShaderInfoLog(vertex, logLength, &logLength, log);
	printf("VertexShader compile log:\n%s\n", log);
	free(log);
    }
    glGetShaderiv(vertex, GL_COMPILE_STATUS, &status);
    
    if (status == 0)
    {
	glDeleteShader(vertex);
	NSLog(@"vertex shgader compile failed\n");
    }
	
    glShaderSource(fragment, 1, (const GLchar **)&fragmentShaderString, NULL);
    glCompileShader(fragment);
	    
    glGetShaderiv(fragment, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
	GLchar *log = (GLchar *)malloc(logLength);
	glGetShaderInfoLog(fragment, logLength, &logLength, log);
	printf("FragmentShader compile log:\n%s\n", log);
	free(log);
    }
    
    glGetShaderiv(fragment, GL_COMPILE_STATUS, &status);
    
    if (status == 0)
    {
	glDeleteShader(fragment);
	NSLog(@"fragmetb shgader compile failed\n");
    }
	
    // Attach vertex shader to program
    glAttachShader(program, vertex);
    
    // Attach fragment shader to program
    glAttachShader(program, fragment);

    
    glLinkProgram(program);
	
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
	GLchar *log = (GLchar *)malloc(logLength);
	glGetProgramInfoLog(program, logLength, &logLength, log);
	printf("Program link log:\n%s\n", log);
        
	free(log);
    }
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (status == 0) {
	NSLog(@"fragmetb shgader compile failed\n");
    }
    _program = program;
    PrintOpenGLError();
    
    
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
    //NSLog(@"getFrameForTImel");
    @autoreleasepool
    {
	
	[self drawRect: [self bounds]];
    }
    
    return kCVReturnSuccess;
}


- (void)drawRect:(NSRect)rect {

    //NSLog(@"drawing");
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [self reshape];
    
    // TODO: make this input real!
    game_input NewInput = {};

    game_offscreen_buffer Buffer = {};
    Buffer.Memory = _offscreenBuffer.Memory;
    Buffer.Width = _offscreenBuffer.Width; 
    Buffer.Height = _offscreenBuffer.Height;
    Buffer.Pitch = _offscreenBuffer.Pitch; 
    GameUpdateAndRender(&_gameMemory, &NewInput, &Buffer);

    // copy into texture
    [[self openGLContext] makeCurrentContext];

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _tex);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, Buffer.Width, Buffer.Height,
		    GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, Buffer.Memory);

    
    glClearColor(0.2, 0.22 ,0.20, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glDisable(GL_DEPTH_TEST);
    glViewport(0, 0, rect.size.width, rect.size.height);
    glUniform1i(glGetUniformLocation(_program, "tex0"), 0);
    glUseProgram(_program);
    glBindVertexArray(_vao);

    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    PrintOpenGLError();
    CGLFlushDrawable([[self openGLContext] CGLContextObj]);
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
 }
@end

/*
####### #     # ####### ######  #     # 
#       ##    #    #    #     #  #   #  
#       # #   #    #    #     #   # #   
#####   #  #  #    #    ######     #    
#       #   # #    #    #   #      #    
#       #    ##    #    #    #     #    
####### #     #    #    #     #    #                                          
*/

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
	s_view = [[HandmadeView alloc] initWithFrame: frame];
	[s_window setContentView: s_view];
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


int main(int argc, const char * argv[]) {
    NSLog(@"Starting");
    return NSApplicationMain(argc, argv);
}


