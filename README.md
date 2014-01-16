CheriVis
========

Tool for exploring CHERI and BERI streamtraces.

Building
--------

On any normal UNIX-like platform, CheriVis builds with GNUstep Make.  If you
have the core GNUstep libraries installed, then you should just be able to run
[g]make to build.

LLVM is a dependency.  If you build with a stock LLVM, then you will only get
BERI (MIPS) support.  To build with CHERI/LLVM, define the `LLVM_CONFIG` macro
on the command line to point to the `llvm-config` from your CHERI/LLVM build.

On OS X, there is an XCode project.  Unfortunately, this does not run
llvm-config, and you must manually add the relevant output to the LDFLAGS and
CXXFLAGS.  LDFLAGS requires the output from:

	llvm-config --ldflags
	llvm-config --libs all-targets DebugInfo mc mcparser mcdisassembler object

CXXFLAGS requires the output from:

	llvm-config --cxxflags

Patches to automate this welcome!
