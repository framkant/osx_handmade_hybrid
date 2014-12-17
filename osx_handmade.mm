
#include <stdint.h>
#include <math.h>

// For the platform layer
#import <Cocoa/Cocoa.h> 
#import <OpenGL/gl3.h>
#import "IOKit/hid/IOHIDManager.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#include <mach/mach_time.h>


// The game
#include "handmade.h"

#include "osx_handmade.h"

#ifndef HANDMADE_USE_ASM_RDTSC
// NOTE(jeff): Thanks to @visitect for this suggestion
#define rdtsc __builtin_readcyclecounter
#else
internal inline uint64
rdtsc()
{
    uint32 eax = 0;
    uint32 edx;

    __asm__ __volatile__("cpuid;"
                 "rdtsc;"
                : "+a" (eax), "=d" (edx)
                :
                : "%rcx", "%rbx", "memory");

    __asm__ __volatile__("xorl %%eax, %%eax;"
                 "cpuid;"
                :
                :
                : "%rax", "%rbx", "%rcx", "%rdx", "memory");

    return (((uint64)edx << 32) | eax);
}
#endif

/*
 #####  #       ####### ######     #    #        #####  
#     # #       #     # #     #   # #   #       #     # 
#       #       #     # #     #  #   #  #       #       
#  #### #       #     # ######  #     # #        #####  
#     # #       #     # #     # ####### #             # 
#     # #       #     # #     # #     # #       #     # 
 #####  ####### ####### ######  #     # #######  #####  
*/                                                        



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
#include <dlfcn.h>

#include "osx_handmade.h"

osx_game_code OSXLoadGameCode(char * dylibname)
{
    osx_game_code ret;
    void* lib = dlopen(dylibname, RTLD_LAZY);
    ret.Lib = lib;
    void *f1 = dlsym(lib, "GameUpdateAndRender");    
    void *f2 = dlsym(lib, "GAME_GET_SOUND_SAMPLES");    
    ret.UpdateAndRender = (game_update_and_render *)f1;
    ret.GetSoundSamples = (game_get_sound_samples *)f2;
    ret.IsValid = true;
    return ret;
}




DEBUG_PLATFORM_FREE_FILE_MEMORY(DEBUGPlatformFreeFileMemory)
{
    if (Memory)
    {
        free(Memory);
    }
}


DEBUG_PLATFORM_READ_ENTIRE_FILE(DEBUGPlatformReadEntireFile)
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





DEBUG_PLATFORM_WRITE_ENTIRE_FILE(DEBUGPlatformWriteEntireFile)
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
 #####  #          #     #####   #####  #######  #####  
#     # #         # #   #     # #     # #       #     # 
#       #        #   #  #       #       #       #       
#       #       #     #  #####   #####  #####    #####  
#       #       #######       #       # #             # 
#     # #       #     # #     # #     # #       #     # 
 #####  ####### #     #  #####   #####  #######  #####  
*/   


#define MAX_NUM_HID_ELEMENTS 2048
struct HIDElement {
    long type;
    long page;
    long usage;
    long min;
    long max;
};
struct HIDElements {
    uint32_t       numElements;   
    uint32_t       keys[MAX_NUM_HID_ELEMENTS];
    HIDElement     elements[MAX_NUM_HID_ELEMENTS]; 
};

void HIDElementAdd(HIDElements * elements, uint32_t key, HIDElement e)
{
  //  Assert(elements->numElements < MAX_NUM_HID_ELEMENTS);
    uint32_t index = elements->numElements;
    elements->elements[index] = e;
    printf("hello 1\n");
    elements->keys[index] = key;
    printf("hello 2\n");
    elements->numElements++;
    printf("hello 3\n");
}
HIDElement* HIDElementGet(HIDElements * elements, uint32_t key)
{
    uint32_t numElements = elements->numElements;
    for(int i=0;i<numElements;i++){
        if(key == elements->keys[i]) {
            return &elements->elements[i]; 
        }
    }
    return 0;
}

//HIDElements                 g_hidElements;

#pragma mark -- ObjC classes --
#define MAX_HID_BUTTONS 32
// View
@interface HandmadeView : NSOpenGLView {
@public
    CVDisplayLinkRef            _displayLink;
    real64                      _machTimebaseConversionFactor;
    HIDElements                 _hidElements;

    game_sound_output_buffer    _soundBuffer;
    game_offscreen_buffer       _renderBuffer;
    game_memory                 _gameMemory;
    osx_game_code               _gameCode;

    // input from callback
    int                         _hidX;
    int                         _hidY;
    uint8                       _hidButtons[MAX_HID_BUTTONS];


    GLuint _vao; 
    GLuint _vbo;
    GLuint _tex;
    GLuint _program;
    BOOL                        _setupComplete;
    
}

- (instancetype)initWithFrame:(NSRect)frameRect;
- (CVReturn) getFrameForTime:(const CVTimeStamp*)outputTime;
- (void)drawRect:(NSRect)dirtyRect;

@end

/*
#     # ### ######  
#     #  #  #     # 
#     #  #  #     # 
#######  #  #     # 
#     #  #  #     # 
#     #  #  #     # 
#     # ### ######                    
*/
// https://developer.apple.com/library/mac/documentation/DeviceDrivers/Conceptual/HID/new_api_10_5/tn2187.html#//apple_ref/doc/uid/TP40000970-CH214-SW2

// example where queues are used:
//https://github.com/gameplay3d/GamePlay/blob/master/gameplay/src/PlatformMacOSX.mm

static void OSXHIDDeviceAdded(
    void *          context,       // context from IOHIDManagerRegisterDeviceMatchingCallback
    IOReturn        result,        // the result of the matching operation
    void *          sender,        // the IOHIDManagerRef for the new device
    IOHIDDeviceRef  device // the new HID device
) {

    #pragma unused(context)
    #pragma unused(result)
    #pragma unused(sender)
    #pragma unused(device)

    HandmadeView* view = ( __bridge HandmadeView*)context;

    //IOHIDManagerRef mr = (IOHIDManagerRef)sender;

    CFStringRef manufacturerCFSR = (CFStringRef)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDManufacturerKey));
    CFStringRef productCFSR = (CFStringRef)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));

    NSLog(@"Gamepad was detected: %@ %@", ( NSString*)manufacturerCFSR, ( NSString*)productCFSR);

    NSArray *elements = ( NSArray *)IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);

    for (id element in elements)
    {
        IOHIDElementRef tIOHIDElementRef = ( IOHIDElementRef)element;

        IOHIDElementType tIOHIDElementType = IOHIDElementGetType(tIOHIDElementRef);

        switch(tIOHIDElementType)
        {
            case kIOHIDElementTypeInput_Misc:
            {
                printf("[misc] ");
                break;
            }

            case kIOHIDElementTypeInput_Button:
            {
                printf("[button] ");
                break;
            }

            case kIOHIDElementTypeInput_Axis:
            {
                printf("[axis] ");
                break;
            }

            case kIOHIDElementTypeInput_ScanCodes:
            {
                printf("[scancode] ");
                break;
            }
            default:
                continue;
        }

        uint32_t reportSize = IOHIDElementGetReportSize(tIOHIDElementRef);
        uint32_t reportCount = IOHIDElementGetReportCount(tIOHIDElementRef);
        if ((reportSize * reportCount) > 64)
        {
            continue;
        }

        uint32_t usagePage = IOHIDElementGetUsagePage(tIOHIDElementRef);
        uint32_t usage = IOHIDElementGetUsage(tIOHIDElementRef);
        if (!usagePage || !usage)
        {
            continue;
        }
        if (-1 == usage)
        {
            continue;
        }

        CFIndex logicalMin = IOHIDElementGetLogicalMin(tIOHIDElementRef);
        CFIndex logicalMax = IOHIDElementGetLogicalMax(tIOHIDElementRef);

        printf("page/usage = %d:%d  min/max = (%ld, %ld)\n", usagePage, usage, logicalMin, logicalMax);


        HIDElement e = {tIOHIDElementType, usagePage,usage,logicalMin, logicalMax };

        long key = (usagePage << 16) | usage;

        // TODO(jeff): Change NSDictionary to a simple hash table.
        // TODO(jeff): Add a hash table for each controller. Use cookies for ID.
        // TODO(jeff): Change HandmadeHIDElement to a simple struct.
       /* HandmadeHIDElement* e = [[HandmadeHIDElement alloc] initWithType:tIOHIDElementType
                                                               usagePage:usagePage
                                                                   usage:usage
                                                                     min:logicalMin
                                                                     max:logicalMax];
        */

        HIDElementAdd(&(view->_hidElements), key, e);
        //[view->_elementDictionary setObject:e forKey:[NSNumber numberWithLong:key]];
    }
   
}   

// this will be called when a HID device is removed (unplugged)
static void OSXHIDDeviceRemoved(
    void *         inContext,       // context from IOHIDManagerRegisterDeviceMatchingCallback
    IOReturn       inResult,        // the result of the removing operation
    void *         inSender,        // the IOHIDManagerRef for the device being removed
    IOHIDDeviceRef inIOHIDDeviceRef // the removed HID device
    ) {
    
}

static void OSXHIDValueChanged(
                void *          context,      // context from IOHIDManagerRegisterInputValueCallback
                IOReturn        result,       // completion result for the input value operation
                void *          sender,       // the IOHIDManagerRef
                IOHIDValueRef   value // the new element value
) {

    #pragma unused(result)
    #pragma unused(sender)

    // NOTE(jeff): Check suggested by Filip to prevent an access violation when
    // using a PS3 controller.
    // TODO(jeff): Investigate this further...
    if (IOHIDValueGetLength(value) > 2)
    {
        //NSLog(@"OSXHIDAction: value length > 2: %ld", IOHIDValueGetLength(value));
        return;
    }

    IOHIDElementRef element = IOHIDValueGetElement(value);
    if (CFGetTypeID(element) != IOHIDElementGetTypeID())
    {
        return;
    }

    //IOHIDElementCookie cookie = IOHIDElementGetCookie(element);
    //IOHIDElementType type = IOHIDElementGetType(element);
    //CFStringRef name = IOHIDElementGetName(element);
    int usagePage = IOHIDElementGetUsagePage(element);
    int usage = IOHIDElementGetUsage(element);

    CFIndex elementValue = IOHIDValueGetIntegerValue(value);

    // NOTE(jeff): This is the pointer back to our view
    HandmadeView* view = ( HandmadeView*)context;

    // NOTE(jeff): This is just for reference. From the USB HID Usage Tables spec:
    // Usage Pages:
    //   1 - Generic Desktop (mouse, joystick)
    //   2 - Simulation Controls
    //   3 - VR Controls
    //   4 - Sports Controls
    //   5 - Game Controls
    //   6 - Generic Device Controls (battery, wireless, security code)
    //   7 - Keyboard/Keypad
    //   8 - LED
    //   9 - Button
    //   A - Ordinal
    //   B - Telephony
    //   C - Consumer
    //   D - Digitizers
    //  10 - Unicode
    //  14 - Alphanumeric Display
    //  40 - Medical Instrument

    if (usagePage == 1) // Generic Desktop Page
    {
        int hatDelta = 16;

        long key = ((usagePage << 16) | usage);
        HIDElement* e = HIDElementGet(&view->_hidElements, key);

        float normalizedValue = 0.0;
        if (e->max != e->min)
        {
            normalizedValue = (float)(elementValue - e->min) / (float)(e->max - e->min);
        }
        float scaledMin = -25.0;
        float scaledMax = 25.0;

        int scaledValue = scaledMin + normalizedValue * (scaledMax - scaledMin);

        //printf("page:usage = %d:%d  value = %ld  ", usagePage, usage, elementValue);
        switch(usage)
        {
            case 0x30: // x
                view->_hidX = scaledValue;
                //printf("[x] scaled = %d\n", view->_hidX);
                break;

            case 0x31: // y
                view->_hidY = scaledValue;
                //printf("[y] scaled = %d\n", view->_hidY);
                break;

            case 0x32: // z
                //view->_hidX = scaledValue;
                //printf("[z] scaled = %d\n", view->_hidX);
                break;

            case 0x35: // rz
                //view->_hidY = scaledValue;
                //printf("[rz] scaled = %d\n", view->_hidY);
                break;

            case 0x39: // Hat 0 = up, 2 = right, 4 = down, 6 = left, 8 = centered
            {
                printf("[hat] ");
                switch(elementValue)
                {
                    case 0:
                        view->_hidX = 0;
                        view->_hidY = -hatDelta;
                        printf("n\n");
                        break;

                    case 1:
                        view->_hidX = hatDelta;
                        view->_hidY = -hatDelta;
                        printf("ne\n");
                        break;

                    case 2:
                        view->_hidX = hatDelta;
                        view->_hidY = 0;
                        printf("e\n");
                        break;

                    case 3:
                        view->_hidX = hatDelta;
                        view->_hidY = hatDelta;
                        printf("se\n");
                        break;

                    case 4:
                        view->_hidX = 0;
                        view->_hidY = hatDelta;
                        printf("s\n");
                        break;

                    case 5:
                        view->_hidX = -hatDelta;
                        view->_hidY = hatDelta;
                        printf("sw\n");
                        break;

                    case 6:
                        view->_hidX = -hatDelta;
                        view->_hidY = 0;
                        printf("w\n");
                        break;

                    case 7:
                        view->_hidX = -hatDelta;
                        view->_hidY = -hatDelta;
                        printf("nw\n");
                        break;

                    case 8:
                        view->_hidX = 0;
                        view->_hidY = 0;
                        printf("up\n");
                        break;
                }

            } break;

            default:
                //NSLog(@"Gamepad Element: %@  Type: %d  Page: %d  Usage: %d  Name: %@  Cookie: %i  Value: %ld  _hidX: %d",
                //      element, type, usagePage, usage, name, cookie, elementValue, view->_hidX);
                break;
        }
    }
    else if (usagePage == 7) // Keyboard
    {
        // NOTE(jeff): usages 0-3:
        //   0 - Reserved
        //   1 - ErrorRollOver
        //   2 - POSTFail
        //   3 - ErrorUndefined
        // Ignore them for now...
        if (usage < 4) return;

        NSString* keyName = @"";

        // TODO(jeff): Store the keyboard events somewhere...

        switch(usage)
        {
            case kHIDUsage_KeyboardW:
                keyName = @"w";
                break;

            case kHIDUsage_KeyboardA:
                keyName = @"a";
                break;

            case kHIDUsage_KeyboardS:
                keyName = @"s";
                break;

            case kHIDUsage_KeyboardD:
                keyName = @"d";
                break;

            case kHIDUsage_KeyboardQ:
                keyName = @"q";
                break;

            case kHIDUsage_KeyboardE:
                keyName = @"e";
                break;

            case kHIDUsage_KeyboardSpacebar:
                keyName = @"Space";
                break;

            case kHIDUsage_KeyboardEscape:
                keyName = @"ESC";
                break;

            case kHIDUsage_KeyboardUpArrow:
                keyName = @"Up";
                break;

            case kHIDUsage_KeyboardLeftArrow:
                keyName = @"Left";
                break;

            case kHIDUsage_KeyboardDownArrow:
                keyName = @"Down";
                break;

            case kHIDUsage_KeyboardRightArrow:
                keyName = @"Right";
                break;

            default:
                return;
                break;
        }
        if (elementValue == 1)
        {
            NSLog(@"%@ pressed", keyName);
        }
        else if (elementValue == 0)
        {
            NSLog(@"%@ released", keyName);
        }
    }
    else if (usagePage == 9) // Buttons
    {
        if (elementValue == 1)
        {
            view->_hidButtons[usage] = 1;
            NSLog(@"Button %d pressed", usage);
        }
        else if (elementValue == 0)
        {
            view->_hidButtons[usage] = 0;
            NSLog(@"Button %d released", usage);
        }
        else
        {
            //NSLog(@"Gamepad Element: %@  Type: %d  Page: %d  Usage: %d  Name: %@  Cookie: %i  Value: %ld  _hidX: %d",
            //    element, type, usagePage, usage, name, cookie, elementValue, view->_hidX);
        }
    }
    else
    {
        //NSLog(@"Gamepad Element: %@  Type: %d  Page: %d  Usage: %d  Name: %@  Cookie: %i  Value: %ld  _hidX: %d",
        //    element, type, usagePage, usage, name, cookie, elementValue, view->_hidX);
    }
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
		     [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_Joystick],
			       @kIOHIDDeviceUsageKey, nil],
		 
		 [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_GamePad],
			       @kIOHIDDeviceUsageKey, nil],
		 
		 [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_MultiAxisController],
			       @kIOHIDDeviceUsageKey, nil],
		     
		 [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger:kHIDPage_GenericDesktop],
			       @kIOHIDDeviceUsagePageKey,
				[NSNumber numberWithInteger:kHIDUsage_GD_Keyboard],
			       @kIOHIDDeviceUsageKey, nil],
		 nil];

    // Pass NULL to get all devices
    IOHIDManagerSetDeviceMatchingMultiple(hidManager, (__bridge CFArrayRef)matchingDevices);

    // Callbacks for acquisition or loss of a matching device
    IOHIDManagerRegisterDeviceMatchingCallback(hidManager,
					       OSXHIDDeviceAdded, (__bridge void *)s_view);
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager,
					       OSXHIDDeviceRemoved, (__bridge void *)s_view);

    // Match devices that are plugged in right now
    IOHIDManagerScheduleWithRunLoop(hidManager,
				    CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    if (IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
	NSLog(@"Failed to open HID Manager");
    }else {
	IOHIDManagerRegisterInputValueCallback(hidManager, OSXHIDValueChanged, (void*)s_view);
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


static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, 
				    const CVTimeStamp* now, 
				    const CVTimeStamp* outputTime, 
				    CVOptionFlags flagsIn, 
				    CVOptionFlags* flagsOut, 
				    void* displayLinkContext)
{
    CVReturn result = [( HandmadeView*)displayLinkContext getFrameForTime:outputTime];
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
    if (_setupComplete){
        printf("trying to init again...\n");
        return self;
    }
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
        _renderBuffer.Width = 800;
        _renderBuffer.Height = 600;
        _renderBuffer.Pitch = _renderBuffer.Width * 4; // bytes per pixel = 4
        _renderBuffer.Memory = calloc(1, _renderBuffer.Pitch * _renderBuffer.Height);
    }

    // General Game mem

    _gameMemory.PermanentStorageSize = Megabytes(64);
    _gameMemory.TransientStorageSize = Gigabytes(1);
    _gameMemory.DEBUGPlatformFreeFileMemory = DEBUGPlatformFreeFileMemory;
    _gameMemory.DEBUGPlatformReadEntireFile = DEBUGPlatformReadEntireFile;
    _gameMemory.DEBUGPlatformWriteEntireFile = DEBUGPlatformWriteEntireFile;


    // TODO(casey): Handle various memory footprints (USING SYSTEM METRICS)
    uint64 TotalSize = _gameMemory.PermanentStorageSize + _gameMemory.TransientStorageSize;
    kern_return_t result = vm_allocate((vm_map_t)mach_task_self(),
                                       (vm_address_t*)&_gameMemory.PermanentStorage,
                                       TotalSize,
                                       VM_FLAGS_ANYWHERE);
    if (result != KERN_SUCCESS)
    {
        NSLog(@"Error allocating memory");
    }
    
    _gameMemory.TransientStorage = ((uint8*)_gameMemory.PermanentStorage
                                   + _gameMemory.PermanentStorageSize);

    
    // load game code
    const char *frameworksPath = [[[NSBundle mainBundle] privateFrameworksPath] UTF8String];
    char dylibpath[512];
    snprintf(dylibpath, 512, "%s%s", frameworksPath, "\/handmade.dylib");


    _gameCode = OSXLoadGameCode(dylibpath);



    // timing
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    _machTimebaseConversionFactor = (double)timebase.numer / (double)timebase.denom;

    _setupComplete = YES;
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
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _renderBuffer.Width, _renderBuffer.Height,
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
    CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, ( void *)(self));

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

    game_offscreen_buffer Buffer = {};
    Buffer.Memory = _renderBuffer.Memory;
    Buffer.Width = _renderBuffer.Width; 
    Buffer.Height = _renderBuffer.Height;
    Buffer.Pitch = _renderBuffer.Pitch; 

// NOTE(jeff): Don't run the game logic during resize events

    // TODO(jeff): Fix this for multiple controllers
    local_persist game_input Input[2] = {};
    local_persist game_input* NewInput = &Input[0];
    local_persist game_input* OldInput = &Input[1];

    game_controller_input* OldController = &OldInput->Controllers[0];
    game_controller_input* NewController = &NewInput->Controllers[0];

    NewController->IsAnalog = true;
    NewController->StickAverageX = _hidX;
    NewController->StickAverageX = _hidY;

    NewController->MoveDown.EndedDown = _hidButtons[1];
    NewController->MoveUp.EndedDown = _hidButtons[2];
    NewController->MoveLeft.EndedDown = _hidButtons[3];
    NewController->MoveRight.EndedDown = _hidButtons[4];


    _gameCode.UpdateAndRender(&_gameMemory, NewInput, &Buffer);

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
        // init joysticks etc
        OSXHIDSetup();
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


