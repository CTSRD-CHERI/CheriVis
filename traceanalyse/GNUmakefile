include $(GNUSTEP_MAKEFILES)/common.make

#
# Application information
#
VERSION = 0.1
TOOL_NAME = traceanalyse

#
# Source code
#
traceanalyse_OBJCC_FILES = \
	../CVDisassembler.mm \
	../CVObjectFile.mm \
	../CVStreamTrace.mm

traceanalyse_OBJC_FILES = \
	CVTraceAnalyse.m\
	../CVAddressMap.m\
	main.m

#
# Compile flags
#
LLVM_CONFIG?= llvm-config
COMPILE_FLAGS= -g -fobjc-arc -O0
ADDITIONAL_OBJCFLAGS  = -std=c11  ${COMPILE_FLAGS} -I.. 
ADDITIONAL_OBJCCFLAGS = -std=gnu++11 `${LLVM_CONFIG} --cxxflags` -Wno-variadic-macros -Wno-gnu ${COMPILE_FLAGS} -fno-rtti
ADDITIONAL_LDFLAGS +=  `${LLVM_CONFIG} --ldflags` 
TARGET_SYSTEM_LIBS +=  `${LLVM_CONFIG} --libs Mips DebugInfo mc mcparser mcdisassembler object` -ldispatch
TARGET_SYSTEM_LIBS +=  `${LLVM_CONFIG} --system-libs`


include $(GNUSTEP_MAKEFILES)/tool.make
