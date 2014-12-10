#import <Cocoa/Cocoa.h>

// App delegate
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, retain) IBOutlet NSWindow *window;
@end



@implementation AppDelegate

@synthesize window;



- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}
@end


int main(int argc, const char * argv[]) {
    return NSApplicationMain(argc, argv);
}
