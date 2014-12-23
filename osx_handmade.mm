/*
    Author: Filip Wanstrom (@filipwanstrom)
    Latest change: 2014-12-21
    
    This is a WIP of a the Mac platform layer for Handmade Hero 
    (handmadehero.org, a game development project by Casey Muratori)

    This file will be marked "beta" when when it's good enough to use
    Until then, consider this a educational or something :)

    I have got a lot of inspiration, tips and help from the handmadehero 
    forums. I want to mention Jeff Buck(@itfrombit) and Arthur Langereis 
    (@zenmumbler) which have been especially engaged in the Mac port. 
    Jeff has a more or less complete implementation at

    I use code by my own research () except for the HID handling which is 
    copied  more or less directly from @itfrombit (Jeff Buck).
    This is mentioned in the code.

    TODO(filip):
    - AUDIO
        - add something that works
            - @zenmumbler and @itfrombit have working code
    - INPUT
        - handle gamepad like in win32
            - save name of controller
            - make difference between controllers (1-4)! 
            - Couple input to the correct controller

            - each up/down event = add to halftransition count
            - record ended down

        - handle keyboard just like gamepad
*/

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

// The game
#include "handmade.h"
#include "osx_handmade.h"

// NOTE(filip): copied from jeff
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
        NOTUSED(err);
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
    elements->keys[index] = key;
    elements->numElements++;
    
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

#pragma mark -- ObjC classes --
#define MAX_HID_BUTTONS 32
// View
@interface HandmadeView : NSOpenGLView {
@public
    CVDisplayLinkRef            _displayLink;
    real64                      _machTimebaseConversionFactor;
    HIDElements                 _hidElements;

    NSString                    *_mainBundlePath;

    game_sound_output_buffer    _soundBuffer;
    game_offscreen_buffer       _renderBuffer;
    game_memory                 _gameMemory;
    osx_game_code               _gameCode;
    osx_state                   _osxState;

    // input from callback
    int                         _hidX;
    int                         _hidY;
    uint8                       _hidButtons[MAX_HID_BUTTONS];
    int                         _recordingOn;
    int                         _dummy[1024];

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
        HIDElementAdd(&(view->_hidElements), key, e);
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
            case kHIDUsage_KeyboardL:
            {
                keyName = @"l";
                if (elementValue == 1){
                    if(view->_recordingOn == 0){ // turn on
                        OSXEndInputPlayBack(&view->_osxState);
                        OSXBeginRecordingInput(&view->_osxState, 1);
                        printf("starting recordning\n");
                        view->_recordingOn = 1;
                    }
                    else // turn off
                    {
                        printf("ending recordning\n");
                        view->_recordingOn = 0;
                        OSXEndRecordingInput(&view->_osxState);
                        OSXBeginInputPlayBack(&view->_osxState, 1);

                        
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
            view->_dummy[usage] = 1;
            
        }
        else if (elementValue == 0)
        {
            NSLog(@"%@ released", keyName);
            view->_dummy[usage] = 0;
            
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
        outputBuffer[i] = 0.7 * sin(currentPhase);
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

- (BOOL) acceptsFirstResponder{
    return YES;
}

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
        _renderBuffer.BytesPerPixel = 4;
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

    // NOTE:(filip): mac os x has a quite different mem system then windows so 
    // we can't transfer the exact same values. My test shows that a BaseAddress
    //  above 5 GB seems to work. I would prefer to have a solid number here but
    //  since it is for debugging purposes this is easily changed so that it 
    // works per dev machine/OS version etc.

    // The game
    void * RequestedAddress = (void*)Gigabytes(8);
    void * BaseAddress;
#if 0
    kern_return_t result = vm_allocate((vm_map_t)mach_task_self(),
                                       (vm_address_t*)&BaseAddress,
                                       TotalSize,
                                       VM_FLAGS_FIXED);

    if (result != KERN_SUCCESS)
    {
        NSLog(@"Error allocating memory");
    }
#endif
    BaseAddress = mmap(RequestedAddress, TotalSize,
                                        PROT_READ|PROT_WRITE,
                                        MAP_PRIVATE|MAP_FIXED|MAP_ANON,
                                        -1, 0);
    if (BaseAddress == MAP_FAILED)
    {
        NSLog(@"Mapping faield.");
    }
    _osxState.TotalSize = TotalSize;
    _osxState.GameMemoryBlock = (void*)BaseAddress;

    _gameMemory.PermanentStorage = _osxState.GameMemoryBlock ;
    _gameMemory.TransientStorage = ((uint8*)_gameMemory.PermanentStorage
                                   + _gameMemory.PermanentStorageSize);
    
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    NSString *secondParentPath = [[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    _mainBundlePath = [secondParentPath stringByDeletingLastPathComponent];
    NSLog(@"main bundle path%@", _mainBundlePath);
    strcpy(_osxState.MainBundlePath, [_mainBundlePath UTF8String]);
    printf("main bundle string:%s\n", _osxState.MainBundlePath);

    for(int ReplayIndex = 0;
            ReplayIndex < ArrayCount(_osxState.ReplayBuffers);
            ++ReplayIndex)
        {
            osx_replay_buffer *ReplayBuffer = &_osxState.ReplayBuffers[ReplayIndex];
            
            // Create filename for the state
            OSXGetInputFileLocation(&_osxState, false, ReplayIndex, ReplayBuffer->FileName );

            ReplayBuffer->FileDescriptor = open(
                ReplayBuffer->FileName, O_RDWR | O_CREAT /*| O_NONBLOCK|  O_TRUNC*/, 0666);


            
            // pre alloc?
            //fstore_t store = {F_ALLOCATECONTIG, F_PEOFPOSMODE, 0, TotalSize};
            //int ret = fcntl(ReplayBuffer->FileDescriptor, F_PREALLOCATE, &store);
            //ftruncate(ReplayBuffer->FileDescriptor, TotalSize);
            
            ReplayBuffer->MemoryBlock = mmap(0, TotalSize, 
                PROT_READ|PROT_WRITE, /*MAP_SHARED*/MAP_PRIVATE, 
                ReplayBuffer->FileDescriptor, 0);
        
            
            if(ReplayBuffer->MemoryBlock)
            {

            }
            else
            {
                // TODO(casey): Diagnostic
            }
        }


    // load game code
    const char *frameworksPath = [[[NSBundle mainBundle] privateFrameworksPath] UTF8String];
    char dylibpath[512];
    snprintf(dylibpath, 512, "%s%s", frameworksPath, "/handmade.dylib");
    
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
- (void) becomeKeyWindow
{

    [s_window setAlphaValue:1.0];
}

/*
######  ######     #    #     # 
#     # #     #   # #   #  #  # 
#     # #     #  #   #  #  #  # 
#     # ######  #     # #  #  # 
#     # #   #   ####### #  #  # 
#     # #    #  #     # #  #  # 
######  #     # #     #  ## ##  
                                
*/ 


- (void)drawRect:(NSRect)rect {

    //NSLog(@"drawing");
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [self reshape];

    game_offscreen_buffer Buffer = {};
    Buffer.Memory = _renderBuffer.Memory;
    Buffer.Width = _renderBuffer.Width; 
    Buffer.Height = _renderBuffer.Height;
    Buffer.Pitch = _renderBuffer.Pitch; 
    Buffer.BytesPerPixel = _renderBuffer.BytesPerPixel; 
    


    // TODO(jeff): Fix this for multiple controllers
    local_persist game_input Input[2] = {};
    local_persist game_input* NewInput = &Input[0];
    local_persist game_input* OldInput = &Input[1];

    game_controller_input* OldController = &OldInput->Controllers[0];
    game_controller_input* NewController = &NewInput->Controllers[0];

    NewController->IsAnalog = true;
    int RightDown = _dummy[kHIDUsage_KeyboardRightArrow];
    int LeftDown = _dummy[kHIDUsage_KeyboardLeftArrow];

    NewController->StickAverageX = RightDown? 2:LeftDown?-2:0;
    NewController->StickAverageY = _dummy[kHIDUsage_KeyboardUpArrow]*2;
    GlobalFrequency = 440.0 + (15 * NewController->StickAverageY); 

    NewController->MoveDown.EndedDown = _hidButtons[1];
    NewController->MoveUp.EndedDown = _hidButtons[2];
    NewController->MoveLeft.EndedDown = _hidButtons[3];
    NewController->MoveRight.EndedDown = _hidButtons[4];

    if (_recordingOn) printf("_recordingOn:%d\n", _recordingOn);
    if(_osxState.InputRecordingIndex && _recordingOn)
    {
        OSXRecordInput(&_osxState, NewInput);
        printf("recording\n");
    }

    if(_osxState.InputPlayingIndex && _recordingOn == 0)
    {
        OSXPlayBackInput(&_osxState, NewInput);
        printf("playing back\n");
    }

    if(_gameCode.UpdateAndRender){
        _gameCode.UpdateAndRender(&_gameMemory, NewInput, &Buffer);
    }

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
    OSXReloadIfModified(&_gameCode);
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


