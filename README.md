CheriVis
========

Tool for exploring CHERI and BERI streamtraces.

Building
--------

When you clone this repository, make sure that you pass the
`--recurse-submodules` flag to `git`.  This will ensure that you have the copy
of the cheritrace library that CheriVis is tested with as a submodule.

On any normal UNIX-like platform, CheriVis builds with GNUstep Make.  If you
have the core GNUstep libraries installed, then you should just be able to run
[g]make to build.

You will need to have the cheritrace library installed before you build.
If you do not wish to install the cheritrace library, then you can use it in
place by building and running with these commands:

	$ [g]make LDFLAGS=-Lcheritrace/Build
	$ LD_LIBRARY_PATH=$LD_LIBRARY_PATH:cheritrace/Build/ opapp ./CheriVis.app

### Building on Mac OS X

On OS X, there is an XCode project.  This does *not* build the cheritrace
library, so you must build that with CMake first.  The following sequence of
steps should work:

	$ git clone --recurse-submodules https://github.com/CTSRD-CHERI/CheriVis.git
	$ cd CheriVis/cheritrace/
	$ mkdir Build
	$ cd Build
	$ cmake .. -DLLVM_CONFIG=path/to/CHERI-LLVM/llvm-config
	$ make
	$ cd ../..
	$ xcodebuild

You should now have a working `build/Release/CheriVis.app`.  For more complex
build configurations or to edit the code, open the XCode project.
