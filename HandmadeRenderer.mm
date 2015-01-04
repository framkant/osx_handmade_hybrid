/* -*- mode: objc -*- */

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

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

// TODO(filip): Move HID stuff to a separate HID file?
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

#define MAX_HID_BUTTONS 32

// Mac OS X Code specific to this game
struct HandmadeRenderData
{
    // Game data
    game_sound_output_buffer    soundBuffer;
    game_offscreen_buffer       renderBuffer;
    game_memory                 gameMemory;
    osx_game_code               gameCode;
    osx_state                   osxState;


    // Input
    HIDElements                 hidElements;
    int                         hidStickX;
    int                         hidStickY;
    int                         hidStickZ;
    int                         hidStickRZ;
    int                         dummy[1024];
    uint8                       hidButtons[MAX_HID_BUTTONS];

    // OpenGL
    GLuint width, height;
    GLuint vao; 
    GLuint vbo;
    GLuint tex;
    GLuint program;

    int                         recordingOn;
};


void OSXSetupData(HandmadeRenderData * handmade)
{
    
    // General Game mem
    handmade->gameMemory.PermanentStorageSize = Megabytes(64);
    handmade->gameMemory.TransientStorageSize = Gigabytes(1);
    handmade->gameMemory.DEBUGPlatformFreeFileMemory = DEBUGPlatformFreeFileMemory;
    handmade->gameMemory.DEBUGPlatformReadEntireFile = DEBUGPlatformReadEntireFile;
    handmade->gameMemory.DEBUGPlatformWriteEntireFile = DEBUGPlatformWriteEntireFile;
        
    // TODO(casey): Handle various memory footprints (USING SYSTEM METRICS)
    uint64 TotalSize =
	handmade->gameMemory.PermanentStorageSize
	+ handmade->gameMemory.TransientStorageSize;
	
    // NOTE:(filip): mac os x has a quite different mem system then windows so 
    // we can't transfer the exact same values. My test shows that a BaseAddress
    //  above 5 GB seems to work. I would prefer to have a solid number here but
    //  since it is for debugging purposes this is easily changed so that it 
    // works per dev machine/OS version etc.
	
    // The game
	void * RequestedAddress = (void*)Gigabytes(8);
	void * BaseAddress;
	
	BaseAddress = mmap(RequestedAddress, TotalSize,
			   PROT_READ|PROT_WRITE,
			   MAP_PRIVATE|MAP_FIXED|MAP_ANON,
			   -1, 0);
	if (BaseAddress == MAP_FAILED)
    {
        NSLog(@"Mapping faield.");
    }
    handmade->osxState.TotalSize = TotalSize;
    handmade->osxState.GameMemoryBlock = (void*)BaseAddress;

    handmade->gameMemory.PermanentStorage = handmade->osxState.GameMemoryBlock ;
    handmade->gameMemory.TransientStorage =
	((uint8*)handmade->gameMemory.PermanentStorage
	 + handmade->gameMemory.PermanentStorageSize);
    
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    NSString *secondParentPath = [[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    //handmade->mainBundlePath
    NSString *mainPath= [secondParentPath stringByDeletingLastPathComponent];
    //NSLog(@"main bundle path%@", _mainBundlePath);
    strcpy(handmade->osxState.MainBundlePath, [mainPath UTF8String]);
    printf("main bundle string:%s\n", handmade->osxState.MainBundlePath);
    
    for(int ReplayIndex = 0;
	ReplayIndex < ArrayCount(handmade->osxState.ReplayBuffers);
	++ReplayIndex)
    {
	osx_replay_buffer *ReplayBuffer = &handmade->osxState.ReplayBuffers[ReplayIndex];
            
            // Create filename for the state
	OSXGetInputFileLocation(&handmade->osxState, false, ReplayIndex, ReplayBuffer->FileName );
	
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
    
    handmade->gameCode = OSXLoadGameCode(dylibpath);


}

void OSXSetupOpenGL(HandmadeRenderData * handmade)
{
    printf("OSXSetupOpenGL\n");
           
    // Offscreen render buffer 
    handmade->renderBuffer.Width = 960;
    handmade->renderBuffer.BytesPerPixel = 4;
    handmade->renderBuffer.Height = 540;
    handmade->renderBuffer.Pitch = handmade->renderBuffer.Width * 4; // bytes per pixel = 4
    handmade->renderBuffer.Memory = calloc(1, handmade->renderBuffer.Pitch * handmade->renderBuffer.Height);
            
    // Create a texture object
    glGenTextures(1, &handmade->tex);
    glBindTexture(GL_TEXTURE_2D, handmade->tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, handmade->renderBuffer.Width, handmade->renderBuffer.Height,
		 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
    // Create opengl objects
    // fullscreen quad using two triangles
    glGenVertexArrays(1, &handmade->vao);
    glBindVertexArray(handmade->vao);

    glGenBuffers(1, &handmade->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, handmade->vbo);
    PrintOpenGLError();
    // define data and upload (interleaved x,y,z,s,t
    // A-D
    // |\|
    // B-C
     
    // GLfloat vertices[] = {
    // 	-1,  1, 0, 0, 1, // A
    // 	-1, -1, 0, 0, 0, // B
    // 	1,  -1, 0, 1, 0, // C

    // 	-1,  1, 0, 0, 1, // A
    // 	1,  -1, 0, 1, 0, // C
    // 	1,  1,  0, 1, 1 //  D 
    // };

    // A-D
    // |\|
    // B-C
    
    GLfloat vertices[] = {
	-1,  1, 0, 0, 0, // A
	-1, -1, 0, 0, 1, // B
	1,  -1, 0, 1, 1, // C

	-1,  1, 0, 0, 0, // A
	1,  -1, 0, 1, 1, // C
	1,  1,  0, 1, 0 //  D 
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
        
	free(log);    }
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (status == 0) {
	NSLog(@"fragmetb shgader compile failed\n");
    }
    handmade->program = program;
    PrintOpenGLError();
}

void OSXRender(HandmadeRenderData * handmade)
{
    //printf("OSXRender\n");
    static double t0;
    static double t1;
    static uint32_t counter = 0;
    t1 = GetTime();
    double diff = t1-t0;
    counter++;
    if (diff > 2.0/60.0) printf("r (%d) : frame-to-frame: %f\n", counter, diff );
    t0 = t1;
        
    thread_context Thread = {};
    
    game_offscreen_buffer Buffer = {};
    Buffer.Memory = handmade->renderBuffer.Memory;
    Buffer.Width = handmade->renderBuffer.Width; 
    Buffer.Height = handmade->renderBuffer.Height;
    Buffer.Pitch = handmade->renderBuffer.Pitch; 
    Buffer.BytesPerPixel = handmade->renderBuffer.BytesPerPixel; 

    real32 MonitorRefreshHz = 60;
    real32 GameUpdateHz = (MonitorRefreshHz / 2.0f);
    real32 TargetSecondsPerFrame = 1.0f / (real32)GameUpdateHz;

    // TODO(jeff): Fix this for multiple controllers
    local_persist game_input Input[2] = {};
    local_persist game_input* NewInput = &Input[0];
    local_persist game_input* OldInput = &Input[1];

    game_controller_input* OldController = &OldInput->Controllers[0];
    game_controller_input* NewController = &NewInput->Controllers[0];

    NewController->IsAnalog = false;
    int RightDown = handmade->dummy[kHIDUsage_KeyboardRightArrow];
    int LeftDown = handmade->dummy[kHIDUsage_KeyboardLeftArrow];

    NewController->StickAverageX = RightDown? 2:LeftDown?-2:0;
    NewController->StickAverageY = handmade->dummy[kHIDUsage_KeyboardUpArrow]*2;
    GlobalFrequency = 440.0 + (15 * NewController->StickAverageY); 

    NewController->MoveDown.EndedDown = handmade->hidButtons[1];
    NewController->MoveUp.EndedDown = handmade->hidButtons[2];
    NewController->MoveLeft.EndedDown = handmade->hidButtons[3];
    NewController->MoveRight.EndedDown = handmade->hidButtons[4];

    NewInput->dtForFrame = TargetSecondsPerFrame;
    
    if (handmade->recordingOn) printf("handmade->recordingOn:%d\n", handmade->recordingOn);
    if(handmade->osxState.InputRecordingIndex && handmade->recordingOn)
    {
        OSXRecordInput(&handmade->osxState, NewInput);
        printf("recording\n");
    }

    if(handmade->osxState.InputPlayingIndex && handmade->recordingOn == 0)
    {
        OSXPlayBackInput(&handmade->osxState, NewInput);
        printf("playing back\n");
    }

    if(handmade->gameCode.UpdateAndRender){
        handmade->gameCode.UpdateAndRender(&Thread, &handmade->gameMemory, NewInput, &Buffer);
    }

    // copy into texture
    
    PrintOpenGLError();
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, handmade->tex);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, Buffer.Width, Buffer.Height,
		    GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, Buffer.Memory);

    
    glClearColor(0.2, 0.72 ,0.20, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    PrintOpenGLError();
    glDisable(GL_DEPTH_TEST);
    glViewport(0, 0, handmade->width, handmade->height);
    PrintOpenGLError();
    GLuint loc = glGetUniformLocation(handmade->program, "tex0");
    glUseProgram(handmade->program);
    PrintOpenGLError();
    glUniform1i(loc, 0);
    PrintOpenGLError();

    glBindVertexArray(handmade->vao);
    PrintOpenGLError();
    glBindBuffer(GL_ARRAY_BUFFER, handmade->vbo);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);

    PrintOpenGLError();
    OSXReloadIfModified(&handmade->gameCode);

    

}

