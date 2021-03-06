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

You will need to have built the cheritrace library installed before you build,
in a `Build` subdirectory of the `cheritrace` directory.  The resulting .so
file will be included in the `CheriVis.app` bundle.

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
