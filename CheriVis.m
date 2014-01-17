#import "CVStreamTrace.h"
#import "CVDisassemblyController.h"
#import "CVAddressMap.h"
#import "CVObjectFile.h"
#import "CVCallGraph.h"
#import "CVColors.h"
#import <Cocoa/Cocoa.h>

@interface CheriVis : NSObject  <NSTableViewDataSource, NSTableViewDelegate>
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

@implementation NSTableView (Copy)
- (IBAction)copy:(id)sender
{
	[[self dataSource] tableView: self
	        writeRowsWithIndexes: [self selectedRowIndexes]
	                toPasteboard: [NSPasteboard generalPasteboard]];
}
@end

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
	/**
	 * Messages that will be put in the title bar.
	 */
	NSMutableDictionary *messages;
	/**
	 * The number of entries that were loaded last time we did a redisplay
	 */
	NSUInteger lastLoaded;
}
- (void)awakeFromNib
{
	// FIXME: These should be done in the .gorm
	[regsView setDelegate: self];
	[regsView setDataSource: self];

	messages = [NSMutableDictionary new];

	objectFiles = [NSMutableDictionary new];

	[[NSNotificationCenter defaultCenter]
	    addObserver: self
	       selector: @selector(defaultsDidChange:)
	           name: NSUserDefaultsDidChangeNotification
	         object: nil];
	[[NSNotificationCenter defaultCenter]
 	    addObserver: self
	       selector: @selector(loadedEntries:)
	           name: CVStreamTraceLoadedEntriesNotification
	         object: nil];
#ifndef GNUSTEP
	[mainWindow setCollectionBehavior: NSWindowCollectionBehaviorFullScreenPrimary];
#endif

}
- (void)setMessage: (NSString*)aString forKey: (id)aKey
{
	if (aString == nil)
	{
		[messages removeObjectForKey: aKey];
	}
	else
	{
		[messages setObject: aString forKey: aKey];
	}
	NSMutableString *title = [@"CheriVis" mutableCopy];
	for (NSString *message in [messages objectEnumerator])
	{
		[title appendFormat: @" – %@", message];
	}
	[mainWindow setTitle: title];
}
- (void)defaultsDidChange: (NSNotification*)aNotification
{
	// We could check if the defaults that have changed are related to this,
	// but the easiest thing to do is just redraw everything, since redraws are
	// cheap and changes to user defaults are infrequent.
	[[mainWindow contentView] setNeedsDisplay: YES];
}
- (void)loadedEntries: (NSNotification*)aNotification
{
	NSDictionary *userInfo = [aNotification userInfo];
	NSNumber *loadedEntries = [userInfo objectForKey: kCVStreamTraceLoadedEntriesCount];
	NSNumber *loadedAllEntries = [userInfo objectForKey: kCVStreamTraceLoadedAllEntries];
	NSUInteger loaded = [loadedEntries unsignedIntegerValue];
	[self setMessage: [NSString stringWithFormat: @"Loaded %@ entries", loadedEntries]
	          forKey: @"loadedCount"];
	if ((loaded - lastLoaded > 100000) || [loadedAllEntries boolValue])
	{
		[traceView reloadData];
	}
	lastLoaded = loaded;
}
- (void)searchWithIncrement: (NSUInteger)increment
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
		NSData *traceData = [NSData dataWithContentsOfMappedFile: file];
		NSString *notesFile = [NSString stringWithFormat: @"%@.notes.json", file];
		streamTrace = [[CVStreamTrace alloc] initWithTraceData: traceData
		                                         notesFileName: notesFile];
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
			return [streamTrace numberOfKernelTraceEntries];
		}
		if (showUser)
		{
			return [streamTrace numberOfUserspaceTraceEntries];
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
			rowIndex = [streamTrace kernelTraceEntryAtIndex: rowIndex];
		}
		else if (showUser && !showKern)
		{
			rowIndex = [streamTrace userspaceTraceEntryAtIndex: rowIndex];
		}
		[streamTrace setStateToIndex: rowIndex];
		if ([@"pc" isEqualToString: columnId])
		{
			NSColor *textColor = [streamTrace isKernel] ?
				[CVColors kernelAddressColor] : [CVColors userspaceAddressColor];
			return stringWithColor([NSString stringWithFormat: @"0x%.16" PRIx64,
					[streamTrace programCounter]], textColor);
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
			NSMutableAttributedString *field = [stringWithColor(instr, textColor) mutableCopy];
			uint8_t ex = [streamTrace exception];
			if (ex != 31)
			{
				[field appendAttributedString: stringWithColor(@" [ Exception 0x%x ]", [NSColor redColor])];
			}
			NSUInteger deadCycles = [streamTrace deadCycles];
			if (deadCycles > 0)
			{
				NSString *str = [NSString stringWithFormat: @" ; %lld dead cycles", (long long)deadCycles];
				[field appendAttributedString: stringWithColor(str, [NSColor blueColor])];

			}
			return field;
		}
		if ([@"index" isEqualToString: columnId])
		{
			return [NSString stringWithFormat: @"%lld", (long long)rowIndex];
		}
		NSString *notes = [streamTrace notes];
		// Work around a GNUstep bug where nil in a table view is not editable.
		return notes ? notes : @" ";
	}

	NSAssert(aTableView == regsView, @"Unexpected table view!");
	if ([@"name" isEqualToString: columnId])
	{
		return [integerRegisterNames objectAtIndex: rowIndex];
	}
	if ([@"value" isEqualToString: columnId])
	{
		id value = [integerRegisterValues objectAtIndex: rowIndex];
		if (value == nil)
		{
			return nil;
		}
		if ([value isKindOfClass: [NSNumber class]])
		{
			return stringWithColor([NSString stringWithFormat: @"0x%.16llx", [value longLongValue]], [NSColor blackColor]);
		}
		NSAssert([value isKindOfClass: [NSString class]], @"Unexpected register value!");
		return stringWithColor(value, [NSColor redColor]);
	}
	return nil;
}
- (void)tableView: (NSTableView*)aTableView
   setObjectValue: (id)anObject
   forTableColumn: (NSTableColumn*)aTableColumn
			  row: (NSInteger)rowIndex
{
	if (!((aTableView == traceView) && [@"notes" isEqualToString: [aTableColumn identifier]]))
	{
		return;
	}
	[streamTrace setStateToIndex: rowIndex];
	[streamTrace setNotes: [anObject description]];
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
			selectedRow = [streamTrace kernelTraceEntryAtIndex: selectedRow];
		}
		else if (showUser && !showKern)
		{
			selectedRow = [streamTrace userspaceTraceEntryAtIndex: selectedRow];
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
-    (BOOL)tableView:(NSTableView*)aTableView
writeRowsWithIndexes:(NSIndexSet*)rowIndexes
        toPasteboard:(NSPasteboard*)pboard
{
	if (aTableView != traceView)
	{
		return NO;
	}
	[pboard declareTypes: [NSArray arrayWithObjects: NSRTFPboardType, NSStringPboardType, nil]
	               owner: nil];
	NSMutableAttributedString *str = [NSMutableAttributedString new];
	[rowIndexes enumerateIndexesUsingBlock: ^(NSUInteger rowIndex, BOOL *shouldStop) {
		BOOL showKern = [showKernel state] == NSOnState;
		BOOL showUser = [showUserspace state] == NSOnState;
		if (showKern && !showUser)
		{
			rowIndex = [streamTrace kernelTraceEntryAtIndex: rowIndex];
		}
		else if (showUser && !showKern)
		{
			rowIndex = [streamTrace userspaceTraceEntryAtIndex: rowIndex];
		}
		[streamTrace setStateToIndex: rowIndex];
		NSString *cellString = [NSString stringWithFormat:@"%lld\t", (long long)rowIndex];
		NSAttributedString *cellValue =
		    [[NSAttributedString alloc] initWithString: cellString];
		[str appendAttributedString: cellValue];
		    NSColor *textColor = [streamTrace isKernel] ?
		        [CVColors kernelAddressColor] : [CVColors userspaceAddressColor];
		[str appendAttributedString: stringWithColor([NSString stringWithFormat: @"0x%.16" PRIx64,
		                                             [streamTrace programCounter]], textColor)];
		[str appendAttributedString: stringWithColor([NSString stringWithFormat: @"0x%.8x",
		                                             [streamTrace encodedInstruction]], [NSColor blackColor])];
		textColor = [CVColors colorForInstructionType: [streamTrace instructionType]];
		NSString *instr = [streamTrace instruction];
		NSMutableAttributedString *field = [stringWithColor(instr, textColor) mutableCopy];
		uint8_t ex = [streamTrace exception];
		if (ex != 31)
		{
			[field appendAttributedString: stringWithColor(@" [ Exception 0x%x ]", [NSColor redColor])];
		}
		NSUInteger deadCycles = [streamTrace deadCycles];
		if (deadCycles > 0)
		{
			NSString *str = [NSString stringWithFormat: @" ; %lld dead cycles", (long long)deadCycles];
			[field appendAttributedString: stringWithColor(str, [NSColor blueColor])];

		}
		[str appendAttributedString:field];
		NSString *notes = [streamTrace notes];
		notes = notes ? [NSString stringWithFormat: @"\t%@\n", notes] : @"\n";
		cellValue =	[[NSAttributedString alloc] initWithString: notes];
		[str appendAttributedString: cellValue];
	}];

	[pboard setData: [str RTFFromRange: NSMakeRange(0, [str length]-1)
	                documentAttributes: nil]
	        forType: NSRTFPboardType];
	[pboard setData: [[str string] dataUsingEncoding: NSUTF8StringEncoding] forType: NSStringPboardType];
	return YES;
}
- (IBAction)changeDisplay: (id)sender
{
	[traceView reloadData];
}
@end

