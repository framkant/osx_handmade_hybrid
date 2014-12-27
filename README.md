osx_handmade_hybrid
===================

This is the start of a minimal OSX application that could serve as a basis for a platform layer for "Handmade Hero". A project developed by Casey Muratori. Please read more at handmadehero.org

The idea here is to set up things in xcode (once) and then leave it be and do the rest work from command line using simple build scripts and a text editor.

There are at least two mayor approaches: Embracing Xcode or doing everything programmatically.

Jeff Buck has two good examples of this:
First an example of using cocoa through xcode tools in a "typical" way:
https://github.com/itfrombit/osx_handmade/tree/master/handmade
and programmatical approach:
https://github.com/itfrombit/osx_handmade_minimal

I started this repo as a separate endeavour to learn more about how cocoa and the mac works on a deeper level. Jeffs examples are very good and you are better served going there for the time being. I use audio and input code from his repos with some minor changes.

Main differences from Jeffs examples:
- I use Core OpenGL3.3 for the rendering backend just because I like it.
- Menus and windows are set up in xcode while the rest of the development is done externally.
- Different buildning and app bundling


##Build##
Just drop the day 30 game code inside this folder and run the build.sh script from the terminal.

##Run##
open build/Handmade.app

##Debug##
Open the xcodeproj in the osx_support files. 






