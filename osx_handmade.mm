#include <stdint.h>
#include <math.h>

// For the platform layer
#import <Cocoa/Cocoa.h> 
#import <OpenGL/gl3.h>
#import "IOKit/hid/IOHIDManager.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#include <mach/mach_time.h>
#import <AudioUnit/AudioUnit.h>


#ifdef PRINT_STUFF
#define debugprintf(fmt, ...) printf(fmt, ##__VA_ARGS__)
#else
#define debugprintf(fmt, ...) 
#endif


// The game
#include "handmade.h"
#include "osx_handmade.h"


double GetTime()
{
    static int first = 1;
    static uint64_t abs_start = 0;
    static double resolution = 1;
    if(first) {
	mach_timebase_info_data_t timebase;
	mach_timebase_info(&timebase);
	resolution = (double) timebase.numer / (double)(timebase.denom *1.0e9);
	abs_start = mach_absolute_time();
	first = 0;
    }
    uint64_t abs_time = mach_absolute_time();
    double result = (double)(abs_time - abs_start)*resolution;
    return result;
}



#define rdtsc __builtin_readcyclecounter
    




/*
 #####  #       ####### ######     #    #        #####  
#     # #       #     # #     #   # #   #       #     # 
#       #       #     # #     #  #   #  #       #       
#  #### #       #     # ######  #     # #        #####  
#     # #       #     # #     # ####### #             # 
#     # #       #     # #     # #     # #       #     # 
 #####  ####### ####### ######  #     # #######  #####  
*/

// Graphics (+ key/mouse input?)
@class GLView;
static NSWindow             *s_window;
static GLView         *s_view;

// Audio
global_variable AudioUnit   GlobalAudioUnit;
global_variable double      GlobalAudioUnitRenderPhase;

global_variable Float64     GlobalFrequency = 800.0;
global_variable Float64     GlobalSampleRate = 48000.0;

// NSWindow IBoutlet called "window" and
// NSApplicationDelegate IBoutlet called "delegate" are created by xcode
// The XIB/NIB is called "MainMenu.xib"

// In the plist that I create in makebudle.sh script
// I set the name of 
// - principal class "NSApplication"

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
#include <sys/stat.h>   
#include <unistd.h>     
#include <fcntl.h>
#include <dlfcn.h>

#include "osx_handmade.h"
/**************************************************************************************************/
time_t OSXGetModTime(const char* filename)
{
    struct stat file_stat;
    stat(filename, &file_stat);
    return file_stat.st_mtime;
}

void OSXGetInputFileLocation(osx_state *State, bool32 InputStream,
                          int SlotIndex, char *Dest)
{
    sprintf(Dest, "%s/loop_edit_%d_%s.hmi",
                State->MainBundlePath, 
                SlotIndex,
                InputStream? "input":"state" );
}

// Dynamic loading and unloading of code
internal  
osx_game_code OSXLoadGameCode(char * dylibname)
{
    osx_game_code ret;
    void* lib = dlopen(dylibname, RTLD_NOW);

    ret.Lib = lib;
    void *f1 = dlsym(lib, "GameUpdateAndRender");    
    void *f2 = dlsym(lib, "GameGetSoundSamples");    
    ret.UpdateAndRender = (game_update_and_render *)f1;
    ret.GetSoundSamples = (game_get_sound_samples *)f2;
    ret.IsValid = true;
    ret.LastModified = OSXGetModTime(dylibname);
    strncpy(ret.DylibName, dylibname, 512);
    return ret;
}
internal
void OSXUnloadGameCode(osx_game_code* GameCode)
{
    if(GameCode->Lib) {
        GameCode->UpdateAndRender = 0;
        GameCode->GetSoundSamples = 0;
        int err = dlclose(GameCode->Lib);
        //NOTUSED(err);
    }
}
internal
void OSXReloadIfModified(osx_game_code *GameCode)
{
    if (GameCode)
    {
        time_t t = OSXGetModTime(GameCode->DylibName);
        if(t>GameCode->LastModified) {
            OSXUnloadGameCode(GameCode);
            
            // TODO(filip): why do a copy of the code work
            // but not a function call?
            
            //*GameCode = OSXLoadGameCode(GameCode->DylibName);
            
            osx_game_code ret;
            void* lib = dlopen(GameCode->DylibName, RTLD_NOW);

            ret.Lib = lib;
            void *f1 = dlsym(lib, "GameUpdateAndRender");    
            void *f2 = dlsym(lib, "GameGetSoundSamples");    
            ret.UpdateAndRender = (game_update_and_render *)f1;
            ret.GetSoundSamples = (game_get_sound_samples *)f2;
            ret.IsValid = true;
            ret.LastModified = OSXGetModTime(GameCode->DylibName);
            strncpy(ret.DylibName, GameCode->DylibName, 512);
            *GameCode= ret;
	}
    }
}

// STATE REPLAY
internal osx_replay_buffer *
OSXGetReplayBuffer(osx_state *State, int unsigned Index)
{
    Assert(Index < ArrayCount(State->ReplayBuffers));
    osx_replay_buffer *Result = &State->ReplayBuffers[Index];
    return(Result);
}
internal void
OSXBeginRecordingInput(osx_state *State, int InputRecordingIndex)
{
    osx_replay_buffer *ReplayBuffer = OSXGetReplayBuffer(State, InputRecordingIndex);

    if (ReplayBuffer->MemoryBlock){
        State->InputRecordingIndex = InputRecordingIndex;

        char FileName[512];
        OSXGetInputFileLocation(State, true, InputRecordingIndex, FileName);
        State->RecordingHandle = fopen(FileName, "w");
/*
        int fd = PR_FileDesc2NativeHandle(aFD);
     fstore_t store = {F_ALLOCATECONTIG, F_PEOFPOSMODE, 0, aLength};
     // Try to get a continous chunk of disk space
     int ret = fcntl(fd, F_PREALLOCATE, &store);
    if(-1 == ret){
       // OK, perhaps we are too fragmented, allocate non-continuous
       store.fst_flags = F_ALLOCATEALL;
       ret = fcntl(fd, F_PREALLOCATE, &store);
       if (-1 == ret)
         return false;
     }

*/        

        fstore_t store = {F_ALLOCATECONTIG, F_PEOFPOSMODE, 0, State->TotalSize};
        int fret = fcntl(ReplayBuffer->FileDescriptor, F_PREALLOCATE, &store);
        if (fret == -1)
        {
            store.fst_flags = F_ALLOCATEALL;
            fret = fcntl(ReplayBuffer->FileDescriptor, F_PREALLOCATE, &store);
            if (-1 == fret){
                printf("store error\n");    
            }
            
        }        

        //ftruncate(ReplayBuffer->FileDescriptor, State->TotalSize);
        off_t ret2 = lseek(ReplayBuffer->FileDescriptor, State->TotalSize-1, SEEK_SET);
        if (ret2 )
        {
            int ret = write(ReplayBuffer->FileDescriptor, "", 1);
            printf("file resized\n");
        }
        memcpy(ReplayBuffer->MemoryBlock, State->GameMemoryBlock, State->TotalSize);
        
        State->RecordingHandle = 0;
        State->RecordingHandle = fopen(FileName, "a");    
    }
    
    
}

internal void
OSXEndRecordingInput(osx_state *OSXState)
{
    fclose(OSXState->RecordingHandle);
    OSXState->InputRecordingIndex = 0;
}

internal void
OSXBeginInputPlayBack(osx_state *State, int Index)
{
    osx_replay_buffer * ReplayBuffer = OSXGetReplayBuffer(State, Index);
    if(ReplayBuffer->MemoryBlock) {
        State->InputPlayingIndex = Index;

        char FileName[512];
        OSXGetInputFileLocation(State, true, Index, FileName);
        State->PlaybackHandle = fopen(FileName, "r");

        memcpy(State->GameMemoryBlock, ReplayBuffer->MemoryBlock, State->TotalSize);
    }


#if 0   
    OSXState->InputPlayingIndex = InputPlayingIndex;
    char *FileName = OSXState->FileName;
    OSXState->PlaybackHandle  = fopen(FileName, "r");
    
    size_t BytesToRead = (size_t)OSXState->TotalSize;
    Assert(OSXState->TotalSize == BytesToRead);
    uint32_t ObjectsRead;
    ObjectsRead = fread(OSXState->GameMemoryBlock, BytesToRead, 1, OSXState->PlaybackHandle);        
#endif
}

internal void
OSXEndInputPlayBack(osx_state *OSXState)
{
    if(OSXState->PlaybackHandle)fclose(OSXState->PlaybackHandle);
    OSXState->InputPlayingIndex = 0;
}

internal void
OSXRecordInput(osx_state *OSXState, game_input *NewInput)    
{
    uint32_t ObjectsWritten;
    ObjectsWritten = fwrite(NewInput, sizeof(*NewInput), 1, OSXState->RecordingHandle);
}

internal void
OSXPlayBackInput(osx_state *OSXState, game_input *NewInput)
{

    uint32_t ObjectsRead=0;
    ObjectsRead = fread(NewInput, sizeof(*NewInput), 1, OSXState->PlaybackHandle);        
    printf("read: %d\n", ObjectsRead);
    if(ObjectsRead == 0){ // end of stream
        printf("end of stream, restarting\n");
        int PlayingIndex = OSXState->InputPlayingIndex;
        OSXEndInputPlayBack(OSXState);
        OSXBeginInputPlayBack(OSXState, PlayingIndex);
        
        ObjectsRead = fread(NewInput, sizeof(*NewInput), 1, OSXState->PlaybackHandle);
    }
}

// NOTE(filip): this is copied from Jeff
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
                    DEBUGPlatformFreeFileMemory(Thread, Result.Contents);
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

struct HIDGamePad
{
    int leftStickX;
    int leftStickY;
    int rightStickX;
    int rightStickY;
    int dPadLeft;
    int dPadRight;
    int dPadDown;
    int dPadUp;
    int buttonUp;
    int buttonLeft;
    int buttonRight;
    int buttonDown;
    int shoulderLeft;
    int shoulderRight;
};

#include "glview.insert"

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

static Boolean IOHIDDevice_GetLongProperty(
    IOHIDDeviceRef inDeviceRef,     // the HID device reference
    CFStringRef inKey,              // the kIOHIDDevice key (as a CFString)
    long * outValue)                // address where to return the output value
{
    Boolean result = FALSE;
 
    CFTypeRef tCFTypeRef = IOHIDDeviceGetProperty(inDeviceRef, inKey);
    if (tCFTypeRef) {
        // if this is a number
        if (CFNumberGetTypeID() == CFGetTypeID(tCFTypeRef)) {
            // get its value
            result = CFNumberGetValue((CFNumberRef) tCFTypeRef, kCFNumberSInt32Type, outValue);
        }
    }
    return result;
}   // IOHIDDevice_GetLongProperty
// Get a HID device's product ID (long)
long IOHIDDevice_GetProductID(IOHIDDeviceRef inIOHIDDeviceRef)
{
    long result = 0;
    (void) IOHIDDevice_GetLongProperty(inIOHIDDeviceRef, CFSTR(kIOHIDProductIDKey), &result);
    return result;
} // IOHIDDevice_GetProductID

static void OSXHIDDeviceAdded(
    void *          context,       // context from IOHIDManagerRegisterDeviceMatchingCallback
    IOReturn        result,        // the result of the matching operation
    void *          sender,        // the IOHIDManagerRef for the new device
    IOHIDDeviceRef  device // the new HID device
    ) {
    
    GLView* view = ( __bridge GLView*)context;
    
    CFStringRef manufacturer = (CFStringRef)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDManufacturerKey));
    CFStringRef product = (CFStringRef)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    long productId = IOHIDDevice_GetProductID(device);
        
    NSLog(@"Device was detected: %@ %@ id(%x)", ( NSString*)manufacturer, ( NSString*)product, productId);

    // Return all HID elements for this device
    NSArray *elements = ( NSArray *)IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);
    NSLog(@"Device elements: %d\n", [elements count]);
    
    
    for (id element in elements)
    {
	if (CFGetTypeID(element) != IOHIDElementGetTypeID()) {
	    // this is a valid HID element reference
	    NSLog(@"Not Valid");
	}
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
	

	default:
	    continue;
	
        }

        uint32_t reportSize = IOHIDElementGetReportSize(tIOHIDElementRef);
        uint32_t reportCount = IOHIDElementGetReportCount(tIOHIDElementRef);

	if ((reportSize * reportCount) > 64){
	    printf("reportSize * reportCount)  64)\n");
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
	if (usagePage > 65000)
	{
	    continue;
	}
	
        CFIndex logicalMin = IOHIDElementGetLogicalMin(tIOHIDElementRef);
        CFIndex logicalMax = IOHIDElementGetLogicalMax(tIOHIDElementRef);

        printf("page/usage = %d:%d  min/max = (%ld, %ld)\n", usagePage, usage, logicalMin, logicalMax);


        HIDElement e = {tIOHIDElementType, usagePage,usage,logicalMin, logicalMax };
        long key = (usagePage << 16) | usage;
        HIDElementAdd(&(view->_handmadeContext.renderData.hidElements), key, e);
    }
}   
static void OSXHIDDeviceAddedOld(
    void *          context,       // context from IOHIDManagerRegisterDeviceMatchingCallback
    IOReturn        result,        // the result of the matching operation
    void *          sender,        // the IOHIDManagerRef for the new device
    IOHIDDeviceRef  device // the new HID device
) {

    #pragma unused(context)
    #pragma unused(result)
    #pragma unused(sender)
    #pragma unused(device)

    GLView* view = ( __bridge GLView*)context;
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
        HIDElementAdd(&(view->_handmadeContext.renderData.hidElements), key, e);
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

    IOHIDElementCookie cookie = IOHIDElementGetCookie(element);
    IOHIDElementType type = IOHIDElementGetType(element);
    CFStringRef name = IOHIDElementGetName(element);
    int usagePage = IOHIDElementGetUsagePage(element);
    int usage = IOHIDElementGetUsage(element);

    CFIndex elementValue = IOHIDValueGetIntegerValue(value);

    // NOTE(jeff): This is the pointer back to our view
    GLView* view = ( GLView*)context;

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
        HIDElement* e = HIDElementGet(&view->_handmadeContext.renderData.hidElements, key);

        float normalizedValue = 0.0;
        if (e->max != e->min)
        {
            normalizedValue = (float)(elementValue - e->min) / (float)(e->max - e->min);
        }
        float scaledMin = -25.0;
        float scaledMax = 25.0;

        int scaledValue = scaledMin + normalizedValue * (scaledMax - scaledMin);

        //debugprintf("page:usage = %d:%d  value = %ld  ", usagePage, usage, elementValue);
        switch(usage)
        {
            case 0x30: // x
                view->_handmadeContext.renderData.hidStickX = scaledValue;
                debugprintf("[x] scaled = %d\n", view->_handmadeContext.renderData.hidStickX);
                break;

            case 0x31: // y
                view->_handmadeContext.renderData.hidStickY = scaledValue;
                debugprintf("[y] scaled = %d\n", view->_handmadeContext.renderData.hidStickY);
                break;

            case 0x32: // z
                view->_handmadeContext.renderData.hidStickZ = scaledValue;
                debugprintf("[z] scaled = %d\n", view->_handmadeContext.renderData.hidStickZ);
                break;

            case 0x35: // rz
                view->_handmadeContext.renderData.hidStickY = scaledValue;
                debugprintf("[rz] scaled = %d\n", view->_handmadeContext.renderData.hidStickRZ);
                break;

            case 0x39: // Hat 0 = up, 2 = right, 4 = down, 6 = left, 8 = centered
            {
                debugprintf("[hat] ");
                switch(elementValue)
                {
                    case 0:
                        view->_handmadeContext.renderData.hidStickX = 0;
                        view->_handmadeContext.renderData.hidStickY = -hatDelta;
                        debugprintf("n\n");
                        break;

                    case 1:
                        view->_handmadeContext.renderData.hidStickX = hatDelta;
                        view->_handmadeContext.renderData.hidStickY = -hatDelta;
                        debugprintf("ne\n");
                        break;

                    case 2:
                        view->_handmadeContext.renderData.hidStickX = hatDelta;
                        view->_handmadeContext.renderData.hidStickY = 0;
                        debugprintf("e\n");
                        break;

                    case 3:
                        view->_handmadeContext.renderData.hidStickX = hatDelta;
                        view->_handmadeContext.renderData.hidStickY = hatDelta;
                        debugprintf("se\n");
                        break;

                    case 4:
                        view->_handmadeContext.renderData.hidStickX = 0;
                        view->_handmadeContext.renderData.hidStickY = hatDelta;
                        debugprintf("s\n");
                        break;

                    case 5:
                        view->_handmadeContext.renderData.hidStickX = -hatDelta;
                        view->_handmadeContext.renderData.hidStickY = hatDelta;
                        debugprintf("sw\n");
                        break;

                    case 6:
                        view->_handmadeContext.renderData.hidStickX = -hatDelta;
                        view->_handmadeContext.renderData.hidStickY = 0;
                        debugprintf("w\n");
                        break;

                    case 7:
                        view->_handmadeContext.renderData.hidStickX = -hatDelta;
                        view->_handmadeContext.renderData.hidStickY = -hatDelta;
                        debugprintf("nw\n");
                        break;

                    case 8:
                        view->_handmadeContext.renderData.hidStickX = 0;
                        view->_handmadeContext.renderData.hidStickY = 0;
                        debugprintf("up\n");
                        break;
                }

            } break;

            default:
                //NSLog(@"Gamepad Element: %@  Type: %d  Page: %d  Usage: %d  Name: %@  Cookie: %i  Value: %ld  _hidStickX: %d",
                //      element, type, usagePage, usage, name, cookie, elementValue, view->_handmadeContext.renderData.hidStickX);
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
		view->_handmadeContext.renderData.hidButtons[2] = elementValue;
                break;

            case kHIDUsage_KeyboardLeftArrow:
                keyName = @"Left";
		view->_handmadeContext.renderData.hidButtons[3] = elementValue;
                break;

            case kHIDUsage_KeyboardDownArrow:
                keyName = @"Down";
		view->_handmadeContext.renderData.hidButtons[1] = elementValue;
                break;

            case kHIDUsage_KeyboardRightArrow:
                keyName = @"Right";
		view->_handmadeContext.renderData.hidButtons[4] = elementValue;
                break;
            case kHIDUsage_KeyboardL:
            {
                keyName = @"l";
                if (elementValue == 1){
                    if(view->_handmadeContext.renderData.recordingOn == 0){ // turn on
                        OSXEndInputPlayBack(&view->_handmadeContext.renderData.osxState);
                        OSXBeginRecordingInput(&view->_handmadeContext.renderData.osxState, 1);
                        debugprintf("starting recordning\n");
                        view->_handmadeContext.renderData.recordingOn = 1;
                    }
                    else // turn off
                    {
                        debugprintf("ending recordning\n");
                        view->_handmadeContext.renderData.recordingOn = 0;
                        OSXEndRecordingInput(&view->_handmadeContext.renderData.osxState);
                        OSXBeginInputPlayBack(&view->_handmadeContext.renderData.osxState, 1);

                        
                    }

                    
                }
                    
            }
                break;


            default:
                return;
                break;
        }
        if (elementValue == 1)
        {
            NSLog(@"%@ pressed (%d)", keyName, usage);
            view->_handmadeContext.renderData.dummy[usage] = 1;
            
        }
        else if (elementValue == 0)
        {
            NSLog(@"%@ released", keyName);
            view->_handmadeContext.renderData.dummy[usage] = 0;
            
        }
    }
    
    else if (usagePage == 9) // Buttons
    {
        if (elementValue == 1)
        {
            view->_handmadeContext.renderData.hidButtons[usage] = 1;
            NSLog(@"Button %d pressed", usage);
        }
        else if (elementValue == 0)
        {
            view->_handmadeContext.renderData.hidButtons[usage] = 0;
            NSLog(@"Button %d released", usage);
        }
        else
        {
            //NSLog(@"Gamepad Element: %@  Type: %d  Page: %d  Usage: %d  Name: %@  Cookie: %i  Value: %ld  _hidStickX: %d",
            //    element, type, usagePage, usage, name, cookie, elementValue, view->_handmadeContext.renderData.hidStickX);
        }
    }
    else
    {
        //NSLog(@"Element: %@  Page: %d  Usage: %d  Name: %@  Cookie: %i  Value: %ld  _hidStickX: %d",
	//element, usagePage, usage, name, cookie, elementValue, view->_handmadeContext.renderData.hidStickX);
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


OSStatus SineWaveRenderCallback(void * inRefCon,
                                AudioUnitRenderActionFlags * ioActionFlags,
                                const AudioTimeStamp * inTimeStamp,
                                UInt32 inBusNumber,
                                UInt32 inNumberFrames,
                                AudioBufferList * ioData)
{
    #pragma unused(ioActionFlags)
    #pragma unused(inTimeStamp)
    #pragma unused(inBusNumber)

    double currentPhase = *((double*)inRefCon);
    Float32* outputBuffer = (Float32 *)ioData->mBuffers[0].mData;
    const double phaseStep = (GlobalFrequency / GlobalSampleRate) * (2.0 * M_PI);

    for (UInt32 i = 0; i < inNumberFrames; i++)
    {
        outputBuffer[i] = 0.0;//0.7 * sin(currentPhase);
        currentPhase += phaseStep;
    }

    // Copy to the stereo (or the additional X.1 channels)
    for(UInt32 i = 1; i < ioData->mNumberBuffers; i++)
    {
        memcpy(ioData->mBuffers[i].mData, outputBuffer, ioData->mBuffers[i].mDataByteSize);
    }

    *((double *)inRefCon) = currentPhase;

    return noErr;
}
// https://developer.apple.com/library/mac/technotes/tn2091/_index.html
void OSXInitCoreAudio()
{
    AudioComponent comp;

    AudioComponentDescription desc;
    desc.componentType         = kAudioUnitType_Output;
    desc.componentSubType      = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags       = 0;
    desc.componentFlagsMask   = 0;

    comp = AudioComponentFindNext(NULL, &desc);
    AudioComponentInstanceNew(comp, &GlobalAudioUnit);
    AudioUnitInitialize(GlobalAudioUnit);

    #if 0
 //There are several different types of Audio Units.
    //Some audio units serve as Outputs, Mixers, or DSP
    //units. See AUComponent.h for listing
    desc.componentType = kAudioUnitType_Output;
 
    //Every Component has a subType, which will give a clearer picture
    //of what this components function will be.
    desc.componentSubType = kAudioUnitSubType_HALOutput;
 
     //all Audio Units in AUComponent.h must use
     //"kAudioUnitManufacturer_Apple" as the Manufacturer
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
 
    //Finds a component that meets the desc spec's
    comp = AudioComponentFindNext(NULL, &desc);
    if (comp == NULL) exit (-1);
 
     //gains access to the services provided by the component
    AudioComponentInstanceNew(comp, &auHAL);

#endif

    // NOTE(jeff): Make this stereo
    AudioStreamBasicDescription asbd;
    asbd.mSampleRate       = GlobalSampleRate;
    asbd.mFormatID         = kAudioFormatLinearPCM;
    asbd.mFormatFlags      = kAudioFormatFlagsNativeFloatPacked;
    asbd.mChannelsPerFrame = 1;
    asbd.mFramesPerPacket  = 1;
    asbd.mBitsPerChannel   = 1 * sizeof(Float32) * 8;
    asbd.mBytesPerPacket   = 1 * sizeof(Float32);
    asbd.mBytesPerFrame    = 1 * sizeof(Float32);

    // TODO(jeff): Add some error checking...
    AudioUnitSetProperty(GlobalAudioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &asbd,
                         sizeof(asbd));

    UInt32 maxFramesPerSlice = 4096;
    AudioUnitSetProperty(GlobalAudioUnit, 
                        kAudioUnitProperty_MaximumFramesPerSlice, 
                        kAudioUnitScope_Global, 0, &maxFramesPerSlice, sizeof(UInt32));

    AURenderCallbackStruct cb;
    cb.inputProc       = SineWaveRenderCallback;
    cb.inputProcRefCon = &GlobalAudioUnitRenderPhase;

    AudioUnitSetProperty(GlobalAudioUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,
                         &cb,
                         sizeof(cb));

    AudioOutputUnitStart(GlobalAudioUnit);
}


void OSXStopCoreAudio()
{
    NSLog(@"Stopping Core Audio");
    AudioOutputUnitStop(GlobalAudioUnit);
    AudioUnitUninitialize(GlobalAudioUnit);
    AudioComponentInstanceDispose(GlobalAudioUnit);
}




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
	s_view = [[GLView alloc] initWithFrame: frame];
	[s_window setContentView:   s_view];
	
	[s_window orderFrontRegardless];
	[window setLevel: NSStatusWindowLevel];
	[window makeKeyAndOrderFront:self];
	
	// init joysticks etc
	OSXHIDSetup();
	OSXInitCoreAudio();
	
    }

}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    [s_window setAlphaValue: 1.0];
    [s_window setIgnoresMouseEvents: NO];
}

- (void)applicationDidResignActive:(NSNotification *)aNotification {
    [s_window setAlphaValue: 0.3];
    [s_window setIgnoresMouseEvents: YES];
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


