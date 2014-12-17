#if !defined(OSX_HANDMADE_H)
struct osx_offscreen_buffer
{
    // NOTE(casey): Pixels are alwasy 32-bits wide, Memory Order BB GG RR XX
    void *Memory;
    int Width;
    int Height;
    int Pitch;
    int BytesPerPixel;
};

struct osx_window_dimension
{
    int Width;
    int Height;
};

struct osx_sound_output
{
    int SamplesPerSecond;
    uint32 RunningSampleIndex;
    int BytesPerSample;
    real32 tSine;
    int LatencySampleCount;
    // TODO(casey): Should running sample index be in bytes as well
    // TODO(casey): Math gets simpler if we add a "bytes per second" field?
};

struct osx_game_code
{
    char  DylibName[512];
    void* Lib;
    time_t LastModified;
    game_update_and_render *UpdateAndRender;
    game_get_sound_samples *GetSoundSamples;

    bool32 IsValid;
};

#define OSX_HANDMADE_H
#endif
