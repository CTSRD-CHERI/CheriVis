CheriVis
========

Tool for exploring CHERI and BERI streamtraces.

Building
--------

CheriVis builds with GNUstep Make.  If you have the core GNUstep libraries
installed, then you should just be able to run [g]make to build.

LLVM is a dependency.  If you build with a stock LLVM, then you will only get
BERI (MIPS) support.  To build with CHERI/LLVM, define the `LLVM_CONFIG` macro
on the command line to point to the `llvm-config` from your CHERI/LLVM build.
