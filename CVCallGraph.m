#import <Foundation/Foundation.h>
#import "CVStreamTrace.h"
#import "CVDisassembler.h"
#import "CVAddressMap.h"
#import "CVObjectFile.h"
#import "CVCallGraph.h"

#import <Cocoa/Cocoa.h>

@interface CVCallGraphEntry : NSObject
@end

@implementation CVCallGraphEntry
{
	/**
	 * The point in the stream trace where the function is entered.
	 */
	NSInteger entryPoint;
	/**
	 * The point in the stream trace where the function is exited.
	 */
	NSInteger exitPoint;
	/**
	 * The function that is currently being executed.
	 */
	CVFunction *function;
	/**
	 * The trace containing the call graph.
	 */
	CVStreamTrace *trace;
	/**
	 * Functions that are called by this function.
	 */
	NSMutableArray *children;
	/**
	 * Flag indicating whether this call is in userspace or kernel.
	 */
	BOOL inKernel;
}
- (void)pushChild: (CVCallGraphEntry*)aChild
{
	if (children == nil)
	{
		children = [NSMutableArray new];
	}
	[children insertObject: aChild atIndex: 0];
	if (aChild->entryPoint < entryPoint)
	{
		entryPoint = aChild->entryPoint;
	}
}
-    (id)initWithTrace: (CVStreamTrace*)aTrace
             fromIndex: (NSInteger)anIndex
               toIndex: (NSInteger*)endIndex
         indexesToShow: (NSIndexSet*)anIndexSet
      withDisassembler: (CVDisassembler*)aDisassembler
            addressMap: (CVAddressMap*)anAddressMap
   functionLookupBlock: (CVFunction*(^)(uint64_t))lookupBlock
kernelTransitionIsCall: (BOOL)isKernelCall
{
	if (nil == (self = [super init])) { return nil; }
	entryPoint = anIndex;
	trace = aTrace;
	uint64_t pc = [aTrace programCounter];
	[aTrace setStateToIndex: anIndex];
	inKernel = [aTrace isKernel];


	function = lookupBlock(pc);
	NSInteger end = [trace numberOfTraceEntries];
	for (exitPoint=entryPoint+1 ; exitPoint<end ;
	     exitPoint = [anIndexSet indexGreaterThanIndex: exitPoint])
	{
		[aTrace setStateToIndex: exitPoint];
		BOOL isCall = NO;
		if ([aTrace isKernel] != inKernel)
		{
			if (!isKernelCall)
			{
				break;
			}
			isCall = YES;
		}
		else
		{
			uint32_t instr = [aTrace encodedInstruction];
			if ([aDisassembler isReturnInstruction: instr])
			{
				break;
			}
			if ([aDisassembler isCallInstruction: instr])
			{
				isCall = YES;
			}
		}
		if (isCall)
		{
			CVCallGraphEntry *newEntry = [[CVCallGraphEntry alloc]
			               initWithTrace: aTrace
			                   fromIndex: exitPoint
			                     toIndex: &exitPoint
			               indexesToShow: anIndexSet
			            withDisassembler: aDisassembler
			                  addressMap: anAddressMap
			         functionLookupBlock: (CVFunction*(^)(uint64_t))lookupBlock
			      kernelTransitionIsCall: !isKernelCall];
			if (children == nil)
			{
				children = [NSMutableArray new];
			}
			[children addObject: newEntry];
		}
	}
	if (endIndex)
	{
		*endIndex = exitPoint;
	}
	return self;
}
- (void)dumpWithTabs: (NSInteger)tabIndex;
{
	for (NSInteger i=0 ; i<tabIndex ; i++)
	{
		printf("\t");
	}
	printf("%s", inKernel ? "[kernel] " : "[userspace]");
	if (function != nil)
	{
		printf("%s\n", [[function demangledName] UTF8String]);
	}
	else
	{
		printf("<unknown function>\n");
	}
	for (CVCallGraphEntry *child in children)
	{
		[child dumpWithTabs: tabIndex+1];
	}
}
- (void)dump
{
	[self dumpWithTabs: 0];
}
@end

@implementation CVCallGraph
{
	/**
	 * The root entry in the call graph.
	 */
	CVCallGraphEntry *root;

}
- (id)initWithStreamTrace: (CVStreamTrace*)aTrace
               addressMap: (CVAddressMap*)anAddressMap
            indexesToShow: (NSIndexSet*)anIndexSet
      functionLookupBlock: (CVFunction*(^)(uint64_t))lookupBlock;
{
	if (nil == (self = [super init])) { return nil; }
	NSInteger end = [anIndexSet lastIndex];
	NSInteger parsedEnd;
	NSInteger start = [anIndexSet firstIndex];
	root = [[CVCallGraphEntry alloc] initWithTrace: aTrace
	                                     fromIndex: start
	                                       toIndex: &parsedEnd
	                                 indexesToShow: anIndexSet
	                              withDisassembler: [CVDisassembler new]
	                                    addressMap: anAddressMap
	                           functionLookupBlock: (CVFunction*(^)(uint64_t))lookupBlock
	                        kernelTransitionIsCall: YES];
	while (parsedEnd < end)
	{
		CVCallGraphEntry *incompleteChild = root;
		root = [[CVCallGraphEntry alloc] initWithTrace: aTrace
		                                     fromIndex: [anIndexSet indexGreaterThanIndex: parsedEnd]
		                                       toIndex: &parsedEnd
		                                 indexesToShow: anIndexSet
		                              withDisassembler: [CVDisassembler new]
		                                    addressMap: anAddressMap
		                           functionLookupBlock: (CVFunction*(^)(uint64_t))lookupBlock
		                        kernelTransitionIsCall: YES];
		[root pushChild: incompleteChild];
	}
	[root dump];
	return self;
}

@end
