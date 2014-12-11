#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>

@class HandmadeView;

// Globals
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

// View

@interface HandmadeView : NSOpenGLView {
    CVDisplayLinkRef        _displayLink;
    void *                  _dataPtr;

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
    NSLog(@"callback");
    return result;
}

@implementation HandmadeView

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

#define BUFFER_OFFSET(i) ((char *)NULL + (i))
- (void)prepareOpenGL
{
    NSLog(@"Preparing opengl");
    [super prepareOpenGL];
    [[self openGLContext] makeCurrentContext];
    [[self window] makeKeyAndOrderFront: self];
    
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

    // Create opengl objects
    // fullscreen quad using two triangles
    glGenVertexArrays(1, &_vao);
    glBindVertexArray(_vao);

    glGenBuffers(1, &_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
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

    // uploade data
    glBufferData(GL_ARRAY_BUFFER, bytes, vertices, GL_STATIC_DRAW);
    // specify vertex format
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(float)*5, BUFFER_OFFSET(0));

    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(float)*5, BUFFER_OFFSET(12));

    // Shader source
    static const char* vertexShaderString =
	"#version 330 core\n"
	"layout (location = 0) in vec3 position;\n"
	"layout (location = 1) in vec2 texcoord;\n"
	"out vec2 v_texcoord;\n"
	"void main(void) {\n"
	"	gl_Position  = vec4(position, 1.0);\n"
	"       v_texcoord = texcoord;\n"
	"}\n";

    static const char* fragmentShaderString =
	"#version 330 core\n"
	"layout (location = 0) out vec4 outColor0;\n"
	"uniform sampler2D texture0;\n"
	"in vec2 v_texcoord;\n "
	"void main(void)\n"
	"{\n"
	"        vec4 texel = texture(texture0, v_texcoord.st);\n"
	"        outColor0 = vec4(1.0, 1.0, 0.0, 1.0);//texel;\n"
	"}\n";
    
    // Create the shader
    GLuint program, vertex, fragment;
    program = glCreateProgram();
    vertex = glCreateShader(GL_VERTEX_SHADER);
    fragment = glCreateShader(GL_FRAGMENT_SHADER);
    GLint logLength;
    GLint status;	

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

- (void)drawRect:(NSRect)rect {

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

    glClearColor(0.2, 0.22 ,0.20, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glDisable(GL_DEPTH_TEST);
    glViewport(0, 0, rect.size.width, rect.size.height);
    glUseProgram(_program);
    glBindVertexArray(_vao);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
        
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


// Entry

int main(int argc, const char * argv[]) {
    NSLog(@"Starting");
    return NSApplicationMain(argc, argv);
}


