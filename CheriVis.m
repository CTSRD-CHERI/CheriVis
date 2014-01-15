#import "CVStreamTrace.h"
#import "CVDisassemblyController.h"
#import "CVAddressMap.h"
#import "CVObjectFile.h"
#import "CVCallGraph.h"
#import "CVColors.h"
#import <Cocoa/Cocoa.h>

@interface CheriVis : NSObject
@end


/**
 * Helper function that pops up a dialog to open a file.
 */
static NSString *openFile(NSString *title)
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setTitle: title];
	[panel setAllowsMultipleSelection: NO];
	if (NSOKButton != [panel runModalForTypes: nil])
	{
		return nil;
	}
	NSArray *files = [panel filenames];
	if ([files count] > 0)
	{
		return [files objectAtIndex: 0];
	}
	return nil;
}

/**
 * Helper function that creates an attributed string by applying a single
 * colour and a fixed-width font to a string.
 */
static NSAttributedString* stringWithColor(NSString *str, NSColor *color)
{
	NSFont *font = [NSFont userFixedPitchFontOfSize: 12];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
		font, NSFontAttributeName,
		color, NSForegroundColorAttributeName, nil];
	return [[NSAttributedString alloc] initWithString: str attributes: dict];
}

/**
 * Helper function that matches a string against either another string or a
 * regular expression.  This is used to implement the search box, which allows
 * various aspects of the state to be matched against either a string or a
 * regular expression.
 */
static inline BOOL matchStringOrRegex(NSString *string, id pattern, BOOL isRegex)
{
	if (isRegex)
	{
		NSRegularExpression *p = pattern;
		return ([p numberOfMatchesInString: string
		                           options: 0
		                             range: NSMakeRange(0, [string length])] > 0);
	}
	else
	{
		return ([string rangeOfString: pattern].location != NSNotFound);
	}
}
/**
 * The CheriVis class implements the controller for the CheriVis application.
 * A single instance of it is created in the main nib file for the application.
 */
@implementation CheriVis
{
	/**
	 * The main window of the CheriVis application.
	 */
	IBOutlet __unsafe_unretained NSWindow *mainWindow;
	/**
	 * The table view that contains the register state.
	 */
	IBOutlet __unsafe_unretained NSTableView *regsView;
	/**
	 * The table view that shows the instruction trace.
	 */
	IBOutlet __unsafe_unretained NSTableView *traceView;
	/**
	 * The view that shows the disassembly of the current function.
	 */
	IBOutlet __unsafe_unretained CVDisassemblyController *disassembly;
	/**
	 * The text field containing the search string or regular expression.
	 */
	IBOutlet __unsafe_unretained NSTextField  *searchText;
	/**
	 * Checkbox indicating whether searches should search the disassembly.
	 */
	IBOutlet __unsafe_unretained NSButton *searchDisassembly;
	/**
	 * Checkbox indicating whether searches should search program counter
	 * addresses.
	 */
	IBOutlet __unsafe_unretained NSButton *searchAddresses;
	/**
	 * Checkbox indicating whether searches should search register values.
	 */
	IBOutlet __unsafe_unretained NSButton *searchRegisterValues;
	/**
	 * Checkbox indicating whether searches should search the disassembly.
	 */
	IBOutlet __unsafe_unretained NSButton *searchInstructions;
	/**
	 * Checkbox indicating whether search strings should be interpreted as
	 * strings or regular expressions.
	 */
	IBOutlet __unsafe_unretained NSButton *regexSearch;
	/**
	 * Checkbox indicating whether instructions in the kernel should be shown.
	 */
	IBOutlet __unsafe_unretained NSButton *showKernel;
	/**
	 * Checkbox indicating whether instructions in userspace should be shown.
	 */
	IBOutlet __unsafe_unretained NSButton *showUserspace;
	/**
	 * The controller for the call graph view.
	 */
	IBOutlet __unsafe_unretained CVCallGraph *callGraph;
	/**
	 * The currently loaded stream trace.
	 */
	CVStreamTrace *streamTrace;
	/**
	 * A dictionary mapping from row indexes to stream trace entries
	 * corresponding to kernel addresses.  This is used when hiding userspace
	 * addresses, to quickly find the correct stream trace entry to show.
	 */
	NSMutableDictionary *kernelAddresses;
	/**
	 * A dictionary mapping from row indexes to stream trace entries
	 * corresponding to userspace addresses.  This is used when hiding kernel
	 * addresses, to quickly find the correct stream trace entry to show.
	 */
	NSMutableDictionary *userAddresses;
	/**
	 * The address map, containing the parsed procstat information, which maps
	 * from address ranges to files.
	 */
	CVAddressMap *addressMap;
	/**
	 * Cached list of the integer register names.
	 */
	NSArray *integerRegisterNames;
	/**
	 * The current integer register values.
	 */
	NSArray *integerRegisterValues;
	// TODO: This might be better as an NSCache
	/**
	 * Dictionary of all of the object files that we've loaded.
	 */
	NSMutableDictionary *objectFiles;
}
- (void)awakeFromNib
{
	// FIXME: These should be done in the .gorm
	[regsView setDelegate: self];
	[regsView setDataSource: self];

	objectFiles = [NSMutableDictionary new];

	[[NSNotificationCenter defaultCenter]
		addObserver: self
		   selector: @selector(defaultsDidChange:)
			   name: NSUserDefaultsDidChangeNotification
			 object: nil];
}
- (void)defaultsDidChange: (NSNotification*)aNotification
{
	// We could check if the defaults that have changed are related to this,
	// but the easiest thing to do is just redraw everything, since redraws are
	// cheap and changes to user defaults are infrequent.
	[[mainWindow contentView] setNeedsDisplay: YES];
}
- (void)searchWithIncrement: (NSUInteger)increment;
{
	NSInteger end = [traceView selectedRow];
	// If no row is selected, start from 0
	if (end == -1)
	{
		end = 0;
	}
	NSInteger i = end;
	NSInteger wrap = [streamTrace numberOfTraceEntries];
	if (wrap == 0)
	{
		return;
	}
	BOOL addrs = [searchAddresses state] == NSOnState;
	BOOL instrs = [searchInstructions state] == NSOnState;
	BOOL disasm = [searchDisassembly state] == NSOnState;
	BOOL regs = [searchRegisterValues state] == NSOnState;
	BOOL isRegex = [regexSearch state] == NSOnState;
	id search = [searchText stringValue];
	NSInteger foundReg = NSNotFound;
	// If the string is supposed to be a regular expression, parse it and
	// report an error.  The matchStringOrRegex() function will use this for
	// matching if required.
	if (isRegex)
	{
		NSError *error = nil;
		search = [NSRegularExpression regularExpressionWithPattern: search
		                                                   options: 0
		                                                     error: &error];
		if (error != nil)
		{
			[[NSAlert alertWithError: error] runModal];
			return;
		}
	}

	do
	{
		i += increment;
		if (i >= wrap)
		{
			i = 0;
		}
		if (i < 0)
		{
			i = wrap - 1;
		}
		[streamTrace setStateToIndex: i];
		if (addrs)
		{
			NSString *str = [NSString stringWithFormat: @"0x%.16" PRIx64, [streamTrace programCounter]];
			if (matchStringOrRegex(str, search, isRegex))
			{
				break;
			}
		}
		if (instrs)
		{
			NSString *str = [NSString stringWithFormat: @"0x%.8" PRIx32, [streamTrace encodedInstruction]];
			if (matchStringOrRegex(str, search, isRegex))
			{
				break;
			}
		}
		if (disasm)
		{
			NSString *str = [streamTrace instruction];
			uint8_t ex = [streamTrace exception];
			if (ex != 31)
			{
				str = [NSString stringWithFormat: @"%@ [ Exception 0x%x ]", str, ex];
			}
			if (matchStringOrRegex(str, search, isRegex))
			{
				break;
			}
		}
		if (regs)
		{
			NSArray *intRegs = [streamTrace integerRegisters];
			BOOL found = NO;
			NSInteger regIdx=-1;
			for (id reg in intRegs)
			{
				regIdx++;
				if ([reg isKindOfClass: [NSString class]])
				{
					continue;
				}
				NSString *str = [NSString stringWithFormat: @"0x%.16llx", [reg longLongValue]];
				if (matchStringOrRegex(str, search, isRegex))
				{
					found = YES;
					foundReg = regIdx;
					break;
				}
			}
			if (found)
			{
				break;
			}
		}
	} while (end != i);
	if (i != end)
	{
		[traceView scrollRowToVisible: i];
		[traceView selectRow: i byExtendingSelection: NO];
		if (foundReg != NSNotFound)
		{
			[regsView scrollRowToVisible: foundReg];
			[regsView selectRow: foundReg byExtendingSelection: NO];
		}
	}
	else
	{
		NSBeep();
	}
}
- (IBAction)search: (id)sender
{
	[self searchWithIncrement: 1];
}
- (IBAction)searchBack: (id)sender
{
	[self searchWithIncrement: -1];
}
- (IBAction)openTrace: (id)sender
{
	NSString *file = openFile(@"Open Stream Trace");
	if (file != nil)
	{
		NSData *traceData = [NSData dataWithContentsOfFile: file];
		streamTrace = [[CVStreamTrace alloc] initWithTraceData: traceData];
		kernelAddresses = [NSMutableDictionary new];
		userAddresses = [NSMutableDictionary new];
		for (NSInteger i=0, e=[streamTrace numberOfTraceEntries],
		     kernIdx=0, userIdx=0 ; i<e ; i++)
		{
			[streamTrace setStateToIndex: i];
			if ([streamTrace isKernel])
			{
				[kernelAddresses setObject: [NSNumber numberWithInteger: i]
				                    forKey: [NSNumber numberWithInteger: kernIdx++]];
			}
			else
			{
				[userAddresses setObject: [NSNumber numberWithInteger: i]
				                  forKey: [NSNumber numberWithInteger: userIdx++]];
			}
		}
		[traceView reloadData];
		integerRegisterNames = [streamTrace integerRegisterNames];
	}
}
- (IBAction)openProcstat: (id)sender
{
	NSString *file = openFile(@"Open output from procstat -v");
	if (file != nil)
	{
		NSString *procstat = [NSString stringWithContentsOfFile: file];
		addressMap = [[CVAddressMap alloc] initWithProcstatOutput: procstat];
	}
	// Currently disabled.  Eventually, we should construct a call graph from a
	// specific range.
#if 0
	if ((addressMap != nil) && (streamTrace != nil))
	{
		[[CVCallGraph alloc] initWithStreamTrace: streamTrace
		                              addressMap: addressMap
		                     functionLookupBlock: ^(uint64_t pc) {
			return [self functionForPC: &pc isRelocated: NULL rangeStart: NULL];
		 }];
	}
#endif
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if (aTableView == traceView)
	{
		BOOL showKern = [showKernel state] == NSOnState;
		BOOL showUser = [showUserspace state] == NSOnState;
		if (showKern && showUser)
		{
			return [streamTrace numberOfTraceEntries];
		}
		if (showKern)
		{
			return [kernelAddresses count];
		}
		if (showUser)
		{
			return [userAddresses count];
		}
		return 0;
	}
	NSAssert(aTableView == regsView, @"Unexpected table view!");
	return (streamTrace == nil) ? 0 : 32;
}
-             (id)tableView: (NSTableView*)aTableView
  objectValueForTableColumn: (NSTableColumn*)aTableColumn
                        row: (NSInteger)rowIndex
{
	NSString *columnId = [aTableColumn identifier];
	if (aTableView == traceView)
	{
		BOOL showKern = [showKernel state] == NSOnState;
		BOOL showUser = [showUserspace state] == NSOnState;
		if (showKern && !showUser)
		{
			rowIndex = [[kernelAddresses objectForKey: [NSNumber numberWithInteger: rowIndex]] integerValue];
		}
		else if (showUser && !showKern)
		{
			rowIndex = [[userAddresses objectForKey: [NSNumber numberWithInteger: rowIndex]] integerValue];
		}
		[streamTrace setStateToIndex: rowIndex];
		if ([@"pc" isEqualToString: columnId])
		{
			NSColor *textColor = [streamTrace isKernel] ?
				[CVColors kernelAddressColor] : [CVColors userspaceAddressColor];
			return stringWithColor([NSString stringWithFormat: @"0x%.16llx", [streamTrace programCounter]], textColor);
		}
		if ([@"instruction" isEqualToString: columnId])
		{
			return stringWithColor([NSString stringWithFormat: @"0x%.8x", 
					[streamTrace encodedInstruction]], [NSColor blackColor]);
		}
		if ([@"disassembly" isEqualToString: columnId])
		{
			NSColor *textColor = [CVColors colorForInstructionType: [streamTrace instructionType]];
			NSString *instr = [streamTrace instruction];
			uint8_t ex = [streamTrace exception];
			if (ex != 31)
			{
				instr = [NSString stringWithFormat: @"%@ [ Exception 0x%x ]", instr, ex];
			}
			return stringWithColor(instr, textColor);
		}
	}

	NSAssert(aTableView == regsView, @"Unexpected table view!");
	if ([@"name" isEqualToString: columnId])
	{
		return [integerRegisterNames objectAtIndex: rowIndex];
	}
	if ([@"value" isEqualToString: columnId])
	{
		id value = [integerRegisterValues objectAtIndex: rowIndex];
		if ([value isKindOfClass: [NSNumber class]])
		{
			return stringWithColor([NSString stringWithFormat: @"0x%.16llx", [value longLongValue]], [NSColor blackColor]);
		}
		NSAssert([value isKindOfClass: [NSString class]], @"Unexpected register value!");
		return stringWithColor(value, [NSColor redColor]);
	}
	return nil;
}
- (CVFunction*)functionForPC: (uint64_t*)aPc isRelocated: (BOOL*)outBool rangeStart: (uint64_t*)rs
{
	uint64_t pc = *aPc;
	CVAddressRange range = [addressMap mappingForAddress: pc];
	if (range.fileName == 0)
	{
		NSLog(@"Could not find address range");
		return nil;
	}
	if (rs != NULL)
	{
		*rs = range.start;
	}
	CVObjectFile *objectFile = [objectFiles objectForKey: range.fileName];
	if (nil == objectFile)
	{
		NSString *path = openFile([NSString stringWithFormat: @"Open object file: %@", range.fileName]);
		if (path != nil)
		{
			objectFile = [CVObjectFile objectFileForFilePath: path];
			if (objectFile == nil)
			{
				[[NSAlert alertWithMessageText: @"Unable to open object file"
				                 defaultButton: nil
				               alternateButton: nil
				                   otherButton: nil
				     informativeTextWithFormat: @""] runModal];
				return nil;
			}
			[objectFiles setObject: objectFile forKey: range.fileName];
		}
	}
	BOOL isRelocated = NO;
	if ([[range.fileName lastPathComponent] rangeOfString: @".so"].location != NSNotFound)
	{
		pc -= range.start;
		isRelocated = YES;
		*aPc = pc;
	}
	if (outBool != 0)
	{
		*outBool = isRelocated;
	}
	return [objectFile functionForAddress: pc];
}
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == traceView)
	{
		[regsView reloadData];
		NSUInteger selectedRow = [traceView selectedRow];
		BOOL showKern = [showKernel state] == NSOnState;
		BOOL showUser = [showUserspace state] == NSOnState;
		if (showKern && !showUser)
		{
			selectedRow = [[kernelAddresses objectForKey: [NSNumber numberWithInteger: selectedRow]] integerValue];
		}
		else if (showUser && !showKern)
		{
			selectedRow = [[userAddresses objectForKey: [NSNumber numberWithInteger: selectedRow]] integerValue];
		}
		[streamTrace setStateToIndex: selectedRow];
		integerRegisterValues = [streamTrace integerRegisters];
		if (addressMap == nil)
		{
			return;
		}
		uint64_t pc = [streamTrace programCounter];
		BOOL isRelocated;
		uint64_t rs;
		CVFunction *func = [self functionForPC: &pc isRelocated: &isRelocated rangeStart: &rs];
		if (func == nil)
		{
			return;
		}
		[disassembly setFunction: func
		         withBaseAddress: [func baseAddress] + (isRelocated ? rs : 0)];
		[disassembly scrollAddressToVisible: pc + (isRelocated ? rs : 0)];
	}
}
- (IBAction)changeDisplay: (id)sender
{
	[traceView reloadData];
}
@end

