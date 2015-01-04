#!/bin/bash
# public domain (by filip wanstrom)
# Setup basic folder / app bundle structure
./makebundle.sh build/Handmade
./makexcscheme.sh build/Handmade.app osx_support_files/DebugHandmadeHybrid/DebugHandmadeHybrid.xcodeproj/xcshareddata/xcschemes/RunDebug.xcscheme

#CFLAGS="-g -Wall -Wno-c++11-compat-deprecated-writable-strings -Wno-null-dereference"
CFLAGS=-O2
FRAMEWORKS="-framework Cocoa -framework QuartzCore -framework OpenGL -framework IOKit -framework AudioUnit"
HANDMADE_DEFINES="-DHANDMADE_INTERNAL=1 -DHANDMADE_SLOW=1 -DHANDMADE_OSX=1"

# compile the window/view description file to a archieved object
ibtool --compile build/MainMenu.nib osx_support_files/MainMenu.xib

#copy archieved object into folder structure
cp build/MainMenu.nib build/Handmade.app/Contents/Resources/Base.lproj/MainMenu.nib

# compile and link the code, put inside folder structure
clang ${CFLAGS} ${HANDMADE_DEFINES} -dynamiclib -o build/Handmade.app/Contents/Frameworks/handmade.dylib handmade.cpp
clang ${CFLAGS} ${HANDMADE_DEFINES} ${FRAMEWORKS} -o build/Handmade.app/Contents/MacOS/Handmade osx_handmade.mm
