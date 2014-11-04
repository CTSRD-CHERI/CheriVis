#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/StringRefMemoryObject.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCDisassembler.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstPrinter.h"
#undef NO
#include "llvm/MC/MCInstrAnalysis.h"
#define NO (BOOL)0
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCObjectDisassembler.h"
#include "llvm/MC/MCObjectFileInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCRelocationInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/DebugInfo/DIContext.h"

#import "CVObjectFile.h"
#import <Foundation/Foundation.h>


#include <vector>
#include <cxxabi.h>

using namespace __cxxabiv1;
using namespace llvm;
using namespace llvm::object;

static inline bool PrintDebugErrors()
{
#ifdef _NDEBUG
	static bool shouldLog = (0 == getenv("CHERIVIS_DEBUG"));
	return shouldLog;
#else
	return true;
#endif
}

#define DebugLogErrorCode(ec, action) \
	if (ec && PrintDebugErrors())\
	{\
		NSLog(@"Error: %s %s:%d, %s", __PRETTY_FUNCTION__, __FILE__, __LINE__, ec.message().c_str());\
		action;\
	}

namespace llvm {
	extern const MCInstrDesc MipsInsts[];
}

template<typename T>
bool findAddress(T &si, T &&se, uint64_t anAddress)
{
	std::error_code ec;
	for ( ; si != se; ++si) {
		uint64_t start, size;
		ec = si->getAddress(start);
		DebugLogErrorCode(ec, return false);
		ec = si->getSize(size);
		DebugLogErrorCode(ec, return false);
		if ((start > anAddress) || (anAddress > (start+size)))
		{
			continue;
		}
		return true;
	}
	return false;
}

std::error_code getContents(section_iterator si, StringRef &data)
{
	return si->getContents(data);
}

std::error_code getContents(symbol_iterator si, StringRef &data)
{
	section_iterator sec((SectionRef()));
	uint64_t start, secStart, size;
	std::error_code ec = si->getSection(sec);
	ec = sec->getContents(data);
	if (ec)  { return ec; }
	ec = sec->getAddress(secStart);
	if (ec)  { return ec; }

	ec = si->getAddress(start);
	if (ec)  { return ec; }
	ec = si->getSize(size);
	if (ec)  { return ec; }
	data = data.substr(start - secStart, size);
	return ec;
}

template<typename T>
bool extractSymbolInfo(T &si,
                      StringRef &name,
                      StringRef &data,
                      uint64_t &baseAddress)
{
	std::error_code ec = si->getAddress(baseAddress);
	DebugLogErrorCode(ec, return false);
	ec = getContents(si, data);
	DebugLogErrorCode(ec, return false);
	ec = si->getName(name);
	DebugLogErrorCode(ec, return false);
	return true;
}

@implementation CVFunction
{
	NSString *name;
	NSString *demangledName;
	StringRef data;
	uint64_t baseAddress;
	CVObjectFile *owner;
}
- (NSUInteger)hash
{
	return (NSUInteger)owner;
}
- (id)copyWithZone: (NSZone*)aZone
{
	return self;
}
- (id)initWithName: (StringRef)aName
              data: (StringRef)aBuffer
       baseAddress: (uint64_t)anAddress
     forObjectFile: (CVObjectFile*)anObjectFile
{
	if (nil == (self = [super init])) { return nil; }
	name = [NSString stringWithUTF8String: aName.str().c_str()];
	data = aBuffer;
	baseAddress = anAddress;
	owner = anObjectFile;
	return self;
}
- (BOOL)isEqual: (id)other
{
	if (![other isKindOfClass: [CVFunction class]])
	{
		return NO;
	}
	CVFunction *o = other;
	if (o->owner != owner)
	{
		return NO;
	}
	return [name isEqualToString: [o mangledName]];
}
- (uint64_t)baseAddress
{
	return baseAddress;
}
- (uint32_t)instructionAtAddress: (uint64_t)anAddress
{
	// TODO: Check that the section start address really wasn't needed..
	StringRefMemoryObject memoryObject(data, 0);
	uint32_t instBytes;
	memoryObject.readBytes(anAddress, 4, (uint8_t*)&instBytes);
	return NSSwapBigIntToHost(instBytes);
}
- (NSUInteger)numberOfInstructions
{
	return data.size() / 4;
}

- (NSString*)mangledName
{
	return name;
}

- (NSString*)demangledName 
{
	if (demangledName != nil)
	{
		return demangledName;
	}
	size_t len;
	int status;
	char *demangled = __cxa_demangle([name UTF8String], 0, &len, &status);
	if (status == 0)
	{
		demangledName = [[NSString alloc] initWithBytesNoCopy: demangled
		                                               length: len
		                                             encoding: NSUTF8StringEncoding
		                                         freeWhenDone: YES];
	}
	else
	{
		free(demangled);
		demangledName = name;
	}
	return demangledName;
}

@end


@implementation CVObjectFile
{
	OwningBinary<ObjectFile> objectFileHolder;
	ObjectFile *objectFile;
	DIContext *debugInfo;
}
- (void)dealloc
{
	delete debugInfo;
}
+ (CVObjectFile*)objectFileForFilePath: (NSString*)aPath
{
	return [[self alloc] initWithPath: aPath];
}
- (id)initWithPath: (NSString*)aPath
{
	auto of = ObjectFile::createObjectFile([aPath UTF8String]);
	if (!of)
	{
		NSLog(@"Failed to create object file: %s", of.getError().message().c_str());
		return nil;
	}
	objectFileHolder = std::move(of.get());
	objectFile = objectFileHolder.getBinary().get();
	debugInfo = DIContext::getDWARFContext(*objectFile);
	return self;
}
- (CVFunction*)functionForAddress: (uint64_t)anAddress
{
	if (debugInfo != 0)
	{
		//DILineInfo line = debugInfo->getLineInfoForAddress(anAddress, DILineInfoSpecifier(1+2+4));
		//NSLog(@"File: %s function: %s line: %d", line.getFileName(), line.getFunctionName(), (int)line.getLine());
	}
	// This could be sped up with some caching, but it's probably not worth
	// implementing it here, when the MCModule stuff will do a better job when
	// it's finished.
	std::error_code ec;
	auto sections = objectFile->sections();
	auto symbols = objectFile->symbols();
	symbol_iterator si = symbols.begin();
	section_iterator seci = sections.begin();
	StringRef name, data;
	uint64_t baseAddress;
	if (findAddress(si, symbols.end(), anAddress))
	{
		extractSymbolInfo(si, name, data, baseAddress);
	}
	else if (findAddress(seci, sections.end(), anAddress))
	{
		extractSymbolInfo(seci, name, data, baseAddress);
	}
	else
	{
		return nil;
	}
	return [[CVFunction alloc] initWithName: name
	                                   data: data
	                            baseAddress: baseAddress
	                          forObjectFile: self];
}
@end
