#!/bin/bash
# public domain (by filip wanstrom)
# Setup basic folder / app bundle structure
./makebundle.sh build/Handmade

# compile the window/view description file to a archieved object
ibtool --compile build/MainMenu.nib osx_support_files/MainMenu.xib

#copy archieved object into folder structure
cp build/MainMenu.nib build/Handmade.app/Contents/Resources/Base.lproj/MainMenu.nib

# compile and link the code, put inside folder structure
clang -g -Wall -DHANDMADE_INTERNAL=1 -DHANDMADE_SLOW=1 -DHANDMADE_OSX=1 -framework Cocoa -framework QuartzCore -framework OpenGL -framework IOKit -framework AudioUnit -o build/Handmade.app/Contents/MacOS/Handmade osx_handmade.mm
