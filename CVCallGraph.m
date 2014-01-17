#import <Foundation/Foundation.h>
#import "CVStreamTrace.h"
#import "CVDisassembler.h"
#import "CVAddressMap.h"
#import "CVObjectFile.h"
#import "CVCallGraph.h"

#import <Cocoa/Cocoa.h>

NSString *CVCallGraphSelectionChangedNotification = @"CVCallGraphSelectionChangedNotification";
NSString *kCVCallGraphSelectedAddressRange = @"CVCallGraphSelectionChangedNotification";

@interface CVCallGraphEntry : NSObject
/**
 * The point in the stream trace where the function is entered.
 */
@property (readonly) NSInteger entryPoint;
/**
 * The point in the stream trace where the function is exited.
 */
@property (readonly) NSInteger exitPoint;
@end

@implementation CVCallGraphEntry
{
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
@synthesize entryPoint, exitPoint;
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
	BOOL expectingCall = NO;
	for (exitPoint=entryPoint+1 ; exitPoint<end ;
	     exitPoint = [anIndexSet indexGreaterThanIndex: exitPoint])
	{
		[aTrace setStateToIndex: exitPoint];
		if ([aTrace isKernel] != inKernel)
		{
			if (!isKernelCall)
			{
				break;
			}
			expectingCall = YES;
		}
		else
		{
			uint32_t instr = [aTrace encodedInstruction];
			if ([aDisassembler isReturnInstruction: instr])
			{
				break;
			}
			if ([aDisassembler isCallInstruction: instr] ||
			    ([aDisassembler typeOfInstruction: instr] == CVInstructionTypeFlowControl))
			{
				expectingCall = YES;
			}
		}
		CVFunction *nextFunction = lookupBlock([aTrace programCounter]);
		if (![nextFunction isEqual: function])
		{
			if (expectingCall)
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
			break;
		}
	}
	if (endIndex)
	{
		*endIndex = exitPoint;
	}
	return self;
}
- (NSString*)description
{
	return [function demangledName];
}
- (void)dumpWithTabs: (NSInteger)tabIndex
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
- (NSInteger)numberOfChildren
{
	return [children count];
}
- (CVCallGraphEntry*)childAtIndex: (NSInteger)anIndex
{
	return [children objectAtIndex: anIndex];
}
@end

@implementation CVCallGraph
{
	/**
	 * The root entry in the call graph.
	 */
	CVCallGraphEntry *root;
	/**
	 * The window that contains the call graph.
	 */
	IBOutlet __unsafe_unretained NSWindow *callGraphWindow;
	/**
	 * The outline view that contains the call graph.
	 */
	IBOutlet __unsafe_unretained NSOutlineView *outline;
}
- (void)showStreamTrace: (CVStreamTrace*)aTrace
             addressMap: (CVAddressMap*)anAddressMap
          indexesToShow: (NSIndexSet*)anIndexSet
    functionLookupBlock: (CVFunction*(^)(uint64_t))lookupBlock
{
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
	[callGraphWindow makeKeyAndOrderFront: self];
	[outline reloadData];
	[root dump];
}
- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (item == nil)
	{
		return root;
	}
	return [item childAtIndex: index];
}
- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item
{
	return (item == nil) ? 1 : [item numberOfChildren];
}
- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item
{
	return (item == nil) || ([item numberOfChildren] > 0);
}
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	return [item description];
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	CVCallGraphEntry *entry = [outline itemAtRow:[outline selectedRow]];
	NSValue *range = [NSValue valueWithRange: NSMakeRange(entry.entryPoint, entry.exitPoint - entry.entryPoint)];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject: range
														 forKey: kCVCallGraphSelectedAddressRange];
	[[NSNotificationCenter defaultCenter] postNotificationName: CVCallGraphSelectionChangedNotification
														object: self
													  userInfo: userInfo];
}
@end
