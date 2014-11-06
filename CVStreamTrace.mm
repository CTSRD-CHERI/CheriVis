#include <algorithm>
#include <map>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#ifndef DISPATCH_QUEUE_PRIORITY_BACKGROUND
#define DISPATCH_QUEUE_PRIORITY_BACKGROUND DISPATCH_QUEUE_PRIORITY_LOW
#endif

#import "CVStreamTrace.h"
#include <assert.h>

//FIXME: Include cheri_debug.h from cherilibs
struct cheri_debug_trace_entry_disk {
	uint8_t   version;
	uint8_t   exception;
	uint16_t  cycles;
	uint32_t  inst;
	uint64_t  pc;
	uint64_t  val1;
	uint64_t  val2;
} __attribute__((packed));



// We could compress this a lot by storing only the deltas, but given that the
// entire 4096 element trace will only generate about 1MB of data, it's not
// worth it (yet).  When we add in the CHERI state, this becomes a few MBs, so
// might be more sensible...  Alternatively, we may only compute it lazily and
// only cache some values (e.g. every 10th or 100th).

struct RegisterState
{
	uint8_t  exception;
	uint16_t deadCycles;
	uint32_t instr;
	uint32_t validRegisters;
	CVInstructionType instructionType;
	uint64_t pc;
	uint64_t cycleCount;
	uint64_t registers[32];
	// TODO: Capability registers
	// TODO: FPU registers
};
static const long long CacheSize = 32768;

@interface CVStreamTraceCache : NSObject
@property NSInteger length;
@property NSInteger start;
@end

static NSUInteger indexAtIndex(NSIndexSet *anIndexSet, NSUInteger anIndex)
{
	if (anIndex >= [anIndexSet count])
	{
		return 0;
	}
	NSUInteger max = [anIndexSet lastIndex];
	NSUInteger min = 0;
	NSRange searchRange = {0, anIndex};
	NSUInteger idx = [anIndexSet countOfIndexesInRange: searchRange];
	while (anIndex != idx)
	{
		if (idx < anIndex)
		{
			min = searchRange.length;
			if (max - searchRange.length == 1)
			{
				searchRange.length++;
			}
			else
			{
				searchRange.length += (max - searchRange.length) / 2;
			}
		}
		else
		{
			max = searchRange.length;
			searchRange.length -= (searchRange.length - min) / 2;
		}
		idx = [anIndexSet countOfIndexesInRange: searchRange];
	}
	searchRange.length = [anIndexSet indexGreaterThanIndex: searchRange.length];
	return searchRange.length;
}
static BOOL isKernelAddress(uint64_t anAddress)
{
	return  anAddress > 0xFFFFFFFF0000000;
}

@implementation CVStreamTraceCache
{
    struct RegisterState registers[CacheSize];
}
@synthesize start, length;

- (id)initWithInitialValue: (struct RegisterState)initialRegisterSet
                 traceData: (NSData*)aTrace
                startIndex: (NSInteger)anIndex
              disassembler: (CVDisassembler*)aDisassembler
{
	self = [super init];
	length = std::min((long long)[aTrace length] / 32, CacheSize);
	start = anIndex;
	struct RegisterState *ors = &initialRegisterSet;
	uint16_t lastCycleCount = 0;

	for (NSInteger i=anIndex ; i<(anIndex+length) ; i++)
	{
		struct cheri_debug_trace_entry_disk traceEntry;
		[aTrace getBytes: &traceEntry
		           range: NSMakeRange(i*32, 32)];

		struct RegisterState *rs = &registers[i-start];
		*rs = *ors;
		rs->pc = NSSwapBigLongLongToHost(traceEntry.pc);
		uint16_t cycleCount = NSSwapBigShortToHost(traceEntry.cycles);
		if (cycleCount < lastCycleCount)
		{
			rs->deadCycles = cycleCount + 1023 - lastCycleCount;
		}
		else if (cycleCount == lastCycleCount)
		{
			rs->deadCycles = 0;
		}
		else
		{
			rs->deadCycles = (cycleCount - lastCycleCount) - 1;
		}
		if (cycleCount > lastCycleCount)
		{
			rs->cycleCount = ors->cycleCount + 1 + rs->deadCycles;
		}
		assert(rs->deadCycles < 1024);
		rs->exception = traceEntry.exception;
		rs->instr = traceEntry.inst;
		if (traceEntry.version == 1 || traceEntry.version == 2)
		{
			int regNo = [aDisassembler destinationRegisterForInstruction: rs->instr];
			if (regNo >= 0)
			{
				rs->validRegisters |= (1<<regNo);
				rs->registers[regNo] = NSSwapBigLongLongToHost(traceEntry.val2);
			}
		}
		// Some entries in the streamtrace lack a program counter, because they include
		// capability register information (which we are not currently parsing)
		if (rs->pc == 0)
		{
			rs->pc = ors->pc+4;
		}
		ors = rs;
		lastCycleCount = cycleCount;
	}
	return self;
}
- (struct RegisterState)registerStateAtIndex: (NSInteger)anIndex
{
	assert(anIndex >= start);
	assert(anIndex < (start + length));
	return registers[anIndex - start];
}
@end

NSString *CVStreamTraceLoadedEntriesNotification = @"CVStreamTraceLoadedEntriesNotification";
NSString *kCVStreamTraceLoadedEntriesCount = @"kCVStreamTraceLoadedEntriesCount";
NSString *kCVStreamTraceLoadedAllEntries = @"kCVStreamTraceLoadedAllEntries";

@interface CVInMainThreadProxy : NSProxy
{
@public
	id receiver;
}
@end
@implementation CVInMainThreadProxy
- (NSMethodSignature*)methodSignatureForSelector:(SEL)aSel
{
	return [receiver methodSignatureForSelector: aSel];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
	[anInvocation retainArguments];
	[anInvocation performSelectorOnMainThread: @selector(invokeWithTarget:)
	                               withObject: receiver
	                            waitUntilDone: NO];
}
@end
@implementation NSObject (InMainThread)
- (id)inMainThread
{
	CVInMainThreadProxy	*p = [CVInMainThreadProxy alloc];
	p->receiver = self;
	return p;
}
@end

@implementation CVStreamTrace
{
	std::map<NSInteger,struct RegisterState> registerKeyframes;
	NSInteger currentIndex;
	struct RegisterState currentState;
	CVStreamTraceCache *cache;
	NSInteger length;
	NSData *trace;
	CVDisassembler *disassembler;
	NSMutableIndexSet *kernelRanges;
	NSMutableIndexSet *userspaceRanges;
	NSMutableDictionary *notes;
	NSString *notesFileName;
}
- (void) notifyLoaded: (NSInteger)lastIndex finished: (BOOL)isDone
{
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
	      [NSNumber numberWithInteger: lastIndex], kCVStreamTraceLoadedEntriesCount,
	      [NSNumber numberWithBool: isDone], kCVStreamTraceLoadedAllEntries,
	      nil];
	[[NSNotificationCenter defaultCenter]
	    postNotificationName: CVStreamTraceLoadedEntriesNotification
	                  object: self
	                userInfo: userInfo];
}

- (void)addKeyFrame: (struct RegisterState)aKeyframe atIndex: (NSInteger)anIndex
{
	registerKeyframes[anIndex] = aKeyframe;
	[self notifyLoaded:anIndex * CacheSize finished:NO];
}
- (void)addRange: (NSRange)aRange isKernel: (BOOL)isKernel
{
	if (isKernel)
	{
		[kernelRanges addIndexesInRange: aRange];
	}
	else
	{
		[userspaceRanges addIndexesInRange: aRange];
	}
}
- (id)initWithTraceData: (NSData*)aTrace notesFileName: (NSString*)aString error: (NSError **)error
{
	if (nil == (self = [super init])) { return nil; }
	trace = aTrace;
	disassembler = [CVDisassembler new];
	length = [trace length] / 32;
	registerKeyframes[0] = currentState;

	// In the background, load all of the information that we need to be able to handle the stream trace
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
		^(void) {
			CVDisassembler *dis = [CVDisassembler new];
			struct RegisterState rs = {0,0,0,0,CVInstructionTypeUnknown,0,0,{0}};
			BOOL lastWasKernel = NO;
			NSRange currentRange = {0,0};
			NSUInteger i;
			CVStreamTrace *mainThreadSelf = [self inMainThread];
			for (i=0 ; i<([trace length] / 32) ; i++)
			{
				struct cheri_debug_trace_entry_disk traceEntry;
				[aTrace getBytes: &traceEntry
				           range: NSMakeRange(i*32, 32)];
				rs.pc = NSSwapBigLongLongToHost(traceEntry.pc);
				rs.exception = traceEntry.exception;
				rs.instr = traceEntry.inst;
				if (isKernelAddress(rs.pc) != lastWasKernel)
				{
					[mainThreadSelf addRange: currentRange isKernel: lastWasKernel];
					currentRange.location = i;
					currentRange.length = 1;
					lastWasKernel = !lastWasKernel;
				}
				else
				{
					currentRange.length++;
				}
				if (traceEntry.version == 1 || traceEntry.version == 2)
				{
					int regNo = [dis destinationRegisterForInstruction: rs.instr];
					if (regNo >= 0)
					{
						rs.validRegisters |= (1<<regNo);
						rs.registers[regNo] = NSSwapBigLongLongToHost(traceEntry.val2);
					}
				}
				if ((i+1) % CacheSize == 0)
				{
					[mainThreadSelf addKeyFrame: rs atIndex: i/CacheSize];
				}
			}
			[mainThreadSelf notifyLoaded: i finished: YES];
		});

	notesFileName = aString;
	if ([[NSFileManager defaultManager] fileExistsAtPath: aString])
	{
		notes =
		    [NSJSONSerialization JSONObjectWithData: [NSData dataWithContentsOfFile: aString]
			                                options: NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
		                                      error: error];
	}
	else
	{
		notes = [NSMutableDictionary new];
	}

	cache = [[CVStreamTraceCache alloc] initWithInitialValue: currentState
	                                               traceData: aTrace
	                                              startIndex: 0
	                                            disassembler: disassembler];
	kernelRanges = [NSMutableIndexSet new];
	userspaceRanges = [NSMutableIndexSet new];


	return self;
}
- (NSInteger)numberOfKernelTraceEntries
{
	return [kernelRanges count];
}
- (NSInteger)numberOfUserspaceTraceEntries
{
	return [userspaceRanges count];
}
- (NSInteger)kernelTraceEntryAtIndex: (NSInteger)anIndex
{
	return indexAtIndex(kernelRanges, anIndex);
}
- (NSInteger)userspaceTraceEntryAtIndex: (NSInteger)anIndex
{
	return indexAtIndex(userspaceRanges, anIndex);
}

- (BOOL)setStateToIndex: (NSInteger)anIndex
{
	if (anIndex < 0 || anIndex >= length)
	{
		return NO;
	}
	if (currentIndex == anIndex)
	{
		return YES;
	}
	currentIndex = anIndex;
	// See if we can satisfy this from the cache
	NSInteger cacheStart = cache.start;
	if (cacheStart <= anIndex && (cacheStart + cache.length) > anIndex)
	{
		currentState = [cache registerStateAtIndex: anIndex];
		return YES;
	}
	// We can't, so let's find the relevant part of the cache
	NSInteger keyFrameIndex = anIndex / CacheSize;
	auto keyFrame = registerKeyframes.find(keyFrameIndex-1);
	struct RegisterState ors = {0,0,0,0,CVInstructionTypeUnknown,0,0,{0}};

	if (keyFrame != registerKeyframes.end())
	{
		ors = (*keyFrame).second;
	}
	cache = [[CVStreamTraceCache alloc] initWithInitialValue: ors
	                                               traceData: trace
	                                              startIndex: keyFrameIndex * CacheSize
	                                            disassembler: disassembler];
	currentState = [cache registerStateAtIndex: anIndex];
	return YES;
}
- (NSString*)instruction
{
	return [disassembler disassembleInstruction: currentState.instr];
}
- (uint32_t)encodedInstruction
{
	return currentState.instr;
}
- (NSArray*)integerRegisters
{
	NSMutableArray *array = [NSMutableArray new];
	[array addObject: [NSNumber numberWithInt: 0]];
	uint32_t mask = currentState.validRegisters;
	uint64_t *regs = currentState.registers;
	for (int i=1 ; i<32 ; i++)
	{
		if ((mask & (1<<i)) == 0)
		{
			[array addObject: @"???"];
		}
		else
		{
			[array addObject: [NSNumber numberWithLongLong: (long long)regs[i]]];
		}
	}
	return array;
}
- (uint64_t)programCounter
{
	return currentState.pc;
}
- (NSInteger)numberOfTraceEntries
{
	return length;
}
- (NSArray*)integerRegisterNames
{
	NSMutableArray *array = [NSMutableArray new];
	for (size_t i=0 ; i<(sizeof(MipsRegisterNames) / sizeof(*MipsRegisterNames)) ; i++)
	{
		[array addObject: [NSString stringWithFormat: @"$%d %s", (int)i, MipsRegisterNames[i]]];
	}
	return array;
}
- (CVInstructionType)instructionType
{
	return [disassembler typeOfInstruction: currentState.instr];
}
- (uint8_t)exception
{
	return currentState.exception;
}
- (BOOL)isKernel
{
	return isKernelAddress(currentState.pc);
}
- (NSUInteger)deadCycles
{
	return currentState.deadCycles;
}
- (uint64_t)cycleCount
{
	return currentState.cycleCount;
}
- (NSString*)notes
{
	NSString *key = [NSString stringWithFormat: @"%lld", (long long)currentIndex];
	return [notes objectForKey: key];
}
- (void)setNotes: (NSString*)aString error: (NSError **)error
{
	NSString *key = [NSString stringWithFormat: @"%lld", (long long)currentIndex];
	[notes setObject: aString forKey: key];
	NSLog(@"Notes: %@", notes);
	NSData *json = [NSJSONSerialization dataWithJSONObject: notes
												   options: NSJSONWritingPrettyPrinted
													 error: error];
	if (*error)
	{
		return;
	}
	[json writeToFile: notesFileName atomically: YES];
}
@end

