include $(GNUSTEP_MAKEFILES)/common.make

#
# Application information
#
VERSION = 0.1
APP_NAME = CheriVis

#
# Resource files
#
CheriVis_LANGUAGES = English
CheriVis_RESOURCE_FILES = \
	CheriVis/Base.lproj/MainMenu.xib \
	CheriVis.tiff
CheriVis_APPLICATION_ICON = CheriVis.tiff
CheriVis_MAIN_MODEL_FILE = MainMenu.xib

#
# Source code
#
CheriVis_OBJCC_FILES = \
	CVDisassembler.mm \
	CVObjectFile.mm \
	CVStreamTrace.mm

CheriVis_OBJC_FILES = \
	CheriVis.m\
	CVCallGraph.m\
	CVColors.m\
	CVDisassemblyController.m\
	CVAddressMap.m\
	main.m

#
# Compile flags
#
LLVM_CONFIG?= llvm-config
COMPILE_FLAGS= -g -fobjc-arc -O0
ADDITIONAL_OBJCFLAGS  = -std=c11  ${COMPILE_FLAGS}
ADDITIONAL_OBJCCFLAGS = -std=gnu++11 `${LLVM_CONFIG} --cxxflags` -Wno-variadic-macros -Wno-gnu ${COMPILE_FLAGS} -fno-rtti
ADDITIONAL_LDFLAGS +=  `${LLVM_CONFIG} --ldflags` 
TARGET_SYSTEM_LIBS +=  `${LLVM_CONFIG} --libs all-targets DebugInfo mc mcparser mcdisassembler object` -ldispatch


include $(GNUSTEP_MAKEFILES)/application.make
