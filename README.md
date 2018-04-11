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

### Building on Linux (Ubuntu 16.04.4 LTS Xenial Xerus)
#### Cheritrace
On Linux, first you must build the cheritrace library, e.g. by doing

    $ cd cheritrace
    $ mkdir Build
    $ cd Build
    $ # Make sure you have a recent clang
    $ cmake .. -GNinja -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_C_COMPILER=/usr/bin/clang -DLLVM_CONFIG=/path/to/cheri/sdk/bin/llvm-config
    $ ninja

If you get a message about
`/path/to/cheri/sdk/lib/libLLVMDebugInfoDWARF.a` being the wrong
format (and if you do `file
/path/to/cheri/sdk/lib/libLLVMDebugInfoDWARF.a` and it says it is
empty, you need a CHERI-SDK which has that file, e.g. by using
`cheribuild.py` (from github).


#### Modern GNUstep (libobjc2)
The Ubuntu GNUstep stuff is too old, so these steps install a GNUstep
system under `/usr/GNUstep/`.

    mkdir GNUstep-build
    cd GNUstep-build

    export CC=clang
    export CXX=clang++

    mkdir -p libobjc2 && wget -qO- https://github.com/gnustep/libobjc2/archive/v1.8.1.tar.gz | tar xz -C libobjc2 --strip-components=1
    mkdir -p make && wget -qO- ftp://ftp.gnustep.org/pub/gnustep/core/gnustep-make-2.6.8.tar.gz | tar xz -C make --strip-components=1
    mkdir -p base && wget -qO- ftp://ftp.gnustep.org/pub/gnustep/core/gnustep-base-1.24.9.tar.gz | tar xz -C base --strip-components=1
    mkdir -p gui && wget -qO- ftp://ftp.gnustep.org/pub/gnustep/core/gnustep-gui-0.25.0.tar.gz | tar xz -C gui --strip-components=1
    mkdir -p back && wget -qO- ftp://ftp.gnustep.org/pub/gnustep/core/gnustep-back-0.25.0.tar.gz | tar xz -C back --strip-components=1

    cd make
    ./configure --enable-debug-by-default --with-layout=gnustep --enable-objc-nonfragile-abi --enable-objc-arc
    make -j8
    sudo -E make install
    cd ..

    . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh

    cd libobjc2
    rm -Rf build
    mkdir build && cd build
    cmake ../ -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang -DCMAKE_ASM_COMPILER=clang -DTESTS=OFF
    cmake --build .
    sudo -E make install
    sudo ldconfig
    cd ../..

    export LDFLAGS=-ldispatch

    OBJCFLAGS="-fblocks -fobjc-runtime=gnustep-1.8.1"

    cd make
    ./configure --enable-debug-by-default --with-layout=gnustep --enable-objc-nonfragile-abi --enable-objc-arc
    make -j8
    sudo -E make install
    cd ..

    cd base/
    ./configure
    make -j8
    sudo -E make install
    cd ..

    cd gui
    ./configure
    make -j8
    sudo -E make install
    cd ..

    cd back
    ./configure
    make -j8
    sudo -E make install
    cd ..

#### CheriVis
Make sure you have `gnustep-make` installed. Also source the GNUstep
environment installed in the previous step by doing

    . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh

Then you can compile CheriVis with

    gs_make clean all

and run it with

    openapp ./CheriVis.app
