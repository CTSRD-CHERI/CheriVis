#import "cheritrace/cheritrace.hh"
#import "CVDisassemblyController.h"
#import "CVCallGraph.h"
#import "CVColors.h"
#include "cheritrace/addressmap.hh"
#include "cheritrace/objectfile.hh"
#import <Cocoa/Cocoa.h>
#include <inttypes.h>
#include <unordered_map>
#include <regex>
#include <thread>
#include <atomic>

using std::shared_ptr;
using namespace cheri;
using cheri::streamtrace::debug_trace_entry;
using cheri::streamtrace::register_set;

@interface CheriVis : NSObject  <NSTableViewDataSource, NSTableViewDelegate>
@end

NSString *CVCallGraphSelectionChangedNotification = @"_CVCallGraphSelectionChangedNotification";
NSString *kCVCallGraphSelectedAddressRange = @"kCVCallGraphSelectedAddressRange";

#ifdef  __linux__
#define snprintf_l(str, size, loc, fmt, ...) snprintf(str, size, fmt, __VA_ARGS__)
#endif

/**
 * Convenience function that writes the contents of a table view to a pasteboard in RTF format.
 */
BOOL WriteTableViewToPasteboard(id<NSTableViewDataSource> data,
                                NSTableView *aTableView,
                                NSIndexSet *rowIndexes,
                                NSPasteboard *pboard)
{
	[pboard declareTypes: [NSArray arrayWithObjects: NSRTFPboardType, NSStringPboardType, nil]
	               owner: nil];
	NSMutableAttributedString *str = [NSMutableAttributedString new];
	NSArray *tableColumns = [aTableView tableColumns];
	NSAttributedString *tab = [[NSAttributedString alloc] initWithString: @"\t"];
	NSAttributedString *nl = [[NSAttributedString alloc] initWithString: @"\n"];
	[rowIndexes enumerateIndexesUsingBlock: ^(NSUInteger rowIndex, BOOL *shouldStop) {
		for (NSTableColumn *column in tableColumns)
		{
			NSAttributedString *cellValue = [data tableView: aTableView
			                      objectValueForTableColumn: column
			                                            row: rowIndex];
			if (![cellValue isKindOfClass: [NSAttributedString class]])
			{
				cellValue = [[NSAttributedString alloc] initWithString: [cellValue description]];
			}
			[str appendAttributedString: cellValue];
			[str appendAttributedString: tab];
		}
		[str appendAttributedString: nl];
	}];
	[pboard setData: [str RTFFromRange: NSMakeRange(0, [str length]-1)
	                documentAttributes: nil]
	        forType: NSRTFPboardType];
	[pboard setData: [[str string] dataUsingEncoding: NSUTF8StringEncoding] forType: NSStringPboardType];
	return YES;
}

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

@interface CVMainThreadProxy : NSProxy
- (id)initWithReceiver: (id)proxied;
@end
@implementation CVMainThreadProxy
{
	id forward;
}
- (id)initWithReceiver: (id)proxied
{
	forward = proxied;
	return self;
}
- (NSMethodSignature*)methodSignatureForSelector: (SEL)aSelector
{
	return [forward methodSignatureForSelector: aSelector];
}
- (void)forwardInvocation: (NSInvocation *)invocation
{
	[invocation retainArguments];
	[invocation performSelectorOnMainThread: @selector(invokeWithTarget:)
								 withObject: forward
							  waitUntilDone: NO];
}
@end

@implementation NSObject (inMainThread)
- (id)inMainThread
{
	return [[CVMainThreadProxy alloc] initWithReceiver: self];
}
@end

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
	 * Checkbox indicating whether searches should search indexes.
	 */
	IBOutlet __unsafe_unretained NSButton *searchIndexes;
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
	 * The status bar along the bottom of the window.
	 */
	IBOutlet __unsafe_unretained NSTextField *statusBar;
	/**
	 * The controller for the call graph view.
	 */
	IBOutlet __unsafe_unretained CVCallGraph *callGraph;
	/**
	 * The currently loaded stream trace.
	 */
	shared_ptr<streamtrace::trace> streamTrace;
	/**
	 * The view on the streamtrace that corresponds to kernel addresses.
	 */
	shared_ptr<streamtrace::trace> kernelTrace;
	/**
	 * The view on the streamtrace that corresponds to userspace addresses.
	 */
	shared_ptr<streamtrace::trace> userTrace;
	/**
	 * The address map, containing the parsed procstat information, which maps
	 * from address ranges to files.
	 */
	std::shared_ptr<cheri::addressmap> addressMap;
	/**
	 * Cached list of the integer register names.
	 */
	NSArray *integerRegisterNames;
	/**
	 * The current register values.
	 */
	streamtrace::register_set registers;
	/**
	 * Dictionary of all of the object files that we've loaded.
	 */
	std::unordered_map<std::string, shared_ptr<objectfile::file>> objectFiles;
	/**
	 * Messages that will be put in the title bar.
	 */
	NSMutableDictionary *messages;
	/**
	 * The number of entries that were loaded last time we did a redisplay
	 */
	NSUInteger lastLoaded;
	/**
	 * The location of the stream trace.  Used to look for files.
	 */
	NSString *traceDirectory;
	/**
	 * The name of the file containing the notes.
	 */
	NSString *notesFile;
	/**
	 * Notes associated with the streamtrace.
	 */
	NSMutableDictionary *notes;
	/**
	 * Counter used to lazily invalidate searches.
	 */
	std::atomic<unsigned long long> searchCount;
	/**
	 * Thread used for running searches in the background.
	 */
	std::thread searchThread;
}
- (void)awakeFromNib
{
	// FIXME: These should be done in the .gorm
	[regsView setDelegate: self];
	[regsView setDataSource: self];

	messages = [NSMutableDictionary new];

	[[NSNotificationCenter defaultCenter]
	    addObserver: self
	       selector: @selector(selectionDidChange:)
	           name: NSTableViewSelectionDidChangeNotification
	         object: traceView];

	[[NSNotificationCenter defaultCenter]
	    addObserver: self
	       selector: @selector(defaultsDidChange:)
	           name: NSUserDefaultsDidChangeNotification
	         object: nil];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		   selector: @selector(selectRange:)
	           name: CVCallGraphSelectionChangedNotification
	         object: nil];
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
- (shared_ptr<streamtrace::trace>&)currentTrace
{
	BOOL showKern = [showKernel state] == NSOnState;
	BOOL showUser = [showUserspace state] == NSOnState;
	auto &trace = showKern ? (showUser ? streamTrace : kernelTrace) : userTrace;
	if (trace == nullptr)
	{
		trace = streamTrace;
	}
	return trace;
}
- (void)defaultsDidChange: (NSNotification*)aNotification
{
	// We could check if the defaults that have changed are related to this,
	// but the easiest thing to do is just redraw everything, since redraws are
	// cheap and changes to user defaults are infrequent.
	[[mainWindow contentView] setNeedsDisplay: YES];
}
- (void)selectionDidChange: (NSNotification*)aNotification
{
	NSIndexSet *indexes = [traceView selectedRowIndexes];
	NSUInteger first = [indexes firstIndex];
	NSUInteger last = [indexes lastIndex]+1;
	NSUInteger count = [indexes count];
	if (last - first != count)
	{
		[statusBar setStringValue: [NSString stringWithFormat: @"Selected %ld rows", count]];
		return;
	}
	auto trace = [self currentTrace];

	trace->seek_to(last);
	uint64_t cycles = trace->get_entry().cycles;
	trace->seek_to(first);
	cycles -= trace->get_entry().cycles;

	[statusBar setStringValue: [NSString stringWithFormat: @"Selected %ld rows, %" PRId64 " cycles", count, cycles]];
}
- (void)selectRange: (NSNotification*)aNotification
{
	NSRange r = [[[aNotification userInfo] objectForKey: kCVCallGraphSelectedAddressRange] rangeValue];
	[traceView selectRowIndexes: [NSIndexSet indexSetWithIndexesInRange: r]
		   byExtendingSelection: NO];
	[traceView scrollRowToVisible: r.location];
}
- (void)searchWithIncrement: (NSInteger)increment
{
	auto trace = [self currentTrace];
	if (trace == nullptr)
	{
		return;
	}
	NSInteger start = [traceView selectedRow];
	// If no row is selected, start from 0
	if (start == -1)
	{
		start = 0;
	}
	else
	{
		start += increment;
	}
	uint64_t end = trace->size();
	if ((uint64_t)start >= end)
	{
		start = 0;
	}
	else if (start < 0)
	{
		start = end;
	}

	BOOL idxs = [searchIndexes state] == NSOnState;
	BOOL addrs = [searchAddresses state] == NSOnState;
	BOOL instrs = [searchInstructions state] == NSOnState;
	BOOL disasm = [searchDisassembly state] == NSOnState;
	BOOL regs = [searchRegisterValues state] == NSOnState;
	BOOL isRegex = [regexSearch state] == NSOnState;

	NSString *search = [searchText stringValue];

	searchCount++;
	unsigned long long searchCountCopy = searchCount;
	[self setMessage: @"[Searching...]" forKey: @"Search"];
	if (searchThread.joinable())
	{
		searchThread.join();
	}

	searchThread = std::thread([=](){
		locale_t cloc = newlocale(LC_ALL_MASK, "C", NULL);
		NSInteger i;
		NSInteger foundReg = NSNotFound;
		bool found = false;
		disassembler::disassembler dis;

		std::function<bool(const std::string &)> match;
		// If the string is supposed to be a regular expression, parse it and
		// report an error.  The matchStringOrRegex() function will use this for
		// matching if required.
		if (isRegex)
		{
			std::regex r([search UTF8String]);
			match = [r](const std::string &text) {
				return std::regex_search(text, r);
			};
		}
		else
		{
			std::string s([search UTF8String]);
			match = [s](const std::string &text) {
				return text.find(s) != std::string::npos;
			};
		}

		auto filter = [&](const debug_trace_entry &e, const register_set &rs, uint64_t idx) {
			const size_t buffer_size = 2 /* 0x */ + 16 /* 64 bits */ + 1 /* null terminator */;
			char buffer[buffer_size];
			if (idxs)
			{
				snprintf_l(buffer, buffer_size, cloc, "%" PRIu64, idx);
				std::string s(buffer);
				found  = match(s);
			}
			if (!found && addrs)
			{
				snprintf_l(buffer, buffer_size, cloc,"0x%.16" PRIx64, e.pc);
				std::string s(buffer);
				found  = match(s);
			}
			if (!found && instrs)
			{
				snprintf_l(buffer, buffer_size, cloc,"0x%.8" PRIx32, e.inst);
				std::string s(buffer);
				found  = match(s);
			}
			if (!found && disasm)
			{
				auto instr = dis.disassemble(e.inst);
				std::string s(std::move(instr.name));
				if (e.exception != 31)
				{
					snprintf_l(buffer, buffer_size, cloc, "%x", e.exception);
					s += " [ Exception 0x";
					s += buffer;
					s += " ]";
				}
				NSUInteger deadCycles = e.dead_cycles;
				if (deadCycles > 0)
				{
					snprintf(buffer, buffer_size, "%lld", (long long)deadCycles);
					s += " ; ";
					s += buffer;
					s += " dead cycles";
				}
				found  = match(s);
			}
			if (!found && regs)
			{
				NSInteger regIdx=0;
				for (uint64_t gpr : rs.gpr)
				{
					regIdx++;
					snprintf_l(buffer, buffer_size, cloc,"0x%.16" PRIx64, gpr);
					std::string s(buffer);
					found = match(s);
					if (found)
					{
						foundReg = regIdx;
						break;
					}
				}
			}
			if (!found)
			{
				i+=increment;
			}
			// If another search has started then abort this one.
			return found || (searchCount != searchCountCopy);
		};
		if (increment < 0)
		{
			i = start;
			trace->scan(filter, 0, start, streamtrace::trace::backwards);
			if (!found)
			{
				i = end;
				trace->scan(filter, start, end, streamtrace::trace::backwards);
			}
		}
		else
		{
			i = start;
			trace->scan(filter, start, end);
			if (!found)
			{
				i = 0;
				trace->scan(filter, 0, start);
			}
		}
		if (cloc != nullptr)
		{
			freelocale(cloc);
		}
		[[self inMainThread] searchResult: found
							   traceIndex: i
									  reg: foundReg
							  searchCount: searchCountCopy];
	});
}
/**
 * Method that handles search results.  This is called in the main thread when
 * the searching thread finds a result.
 */
- (void)searchResult: (BOOL)found
		  traceIndex: (NSInteger)i
				 reg: (NSInteger)foundReg
		 searchCount: (unsigned long long)aSearchCount
{
	// If this is a stale result, give up.
	if (searchCount != aSearchCount)
	{
		return;
	}
	if (found)
	{
		[self setMessage: nil forKey: @"Search"];
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
		[self setMessage: @"[Search term not found]" forKey: @"Search"];
		NSBeep();
	}
}
- (void)dealloc
{
	searchCount++;
	if (searchThread.joinable())
	{
		searchThread.join();
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
- (void)loadedKernel: (std::shared_ptr<streamtrace::trace>)kernel
				user: (std::shared_ptr<streamtrace::trace>)user
			forTrace: (std::shared_ptr<streamtrace::trace>)originalTrace
{
	if (streamTrace.get() == originalTrace.get())
	{
		kernelTrace = std::move(kernel);
		userTrace = std::move(user);
		[traceView reloadData];
	}

}
- (void)loadedEntries: (uint64_t)loadedEntries done: (BOOL)isFinished
{
	// 50000 is a compromise to avoid overwhelming the table view with
	// redraw events, but still allowing the user to quickly get to the
	// end of the trace quickly.
	if (isFinished || (lastLoaded < 1000) || (loadedEntries - lastLoaded > 500000))
	{
		[self setMessage: [[NSString alloc] initWithFormat: @"Loaded %s%" PRIu64 " entries"
		                                            locale: [NSLocale currentLocale],
															isFinished ? "all " : "",
		                                                    loadedEntries]

				  forKey: @"loadedCount"];
		lastLoaded = loadedEntries;
		[traceView reloadData];
	}
}
- (IBAction)openTrace: (id)sender
{
	NSString *file = openFile(@"Open Stream Trace");
	if (file != nil)
	{
		std::string fileName([file UTF8String]);
		NSError *error = nil;
		id mainThreadSelf = [self inMainThread];
		auto callback = [self,mainThreadSelf](streamtrace::trace *t, uint64_t count, bool finished) {
			if (streamTrace.get() != t)
			{
				return true;
			}
			[mainThreadSelf loadedEntries: count done: finished];
			return false;
		};
		streamTrace = streamtrace::trace::open(fileName, callback);
		if (!streamTrace)
		{
			// FIXME: Sensible error
			[NSApp presentError: nil];
			return;
		}
		auto traceRefCopy = streamTrace;
		std::thread([self,traceRefCopy](){
			auto kernfilter = [](const streamtrace::debug_trace_entry &e) { return e.is_kernel(); };
			auto kernel = traceRefCopy->filter(kernfilter);
			auto user = kernel->inverted_view();
			[[self inMainThread] loadedKernel: kernel
										 user: user
									 forTrace: traceRefCopy];
		}).detach();
		notesFile = [NSString stringWithFormat: @"%@.notes.json", file];
		NSData *notesBinary = [NSData dataWithContentsOfFile: notesFile];
		if (notesBinary != nil)
		{
			notes =
				[NSJSONSerialization JSONObjectWithData: [NSData dataWithContentsOfFile: notesFile]
										options: NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
										  error: &error];
		}
		if (notes == nil)
		{
			notes = [NSMutableDictionary new];
		}
		[traceView reloadData];
		NSMutableArray *names = [NSMutableArray new];
		for (const char *name : cheri::disassembler::MipsRegisterNames)
		{
			[names addObject: [NSString stringWithUTF8String: name]];
		}
		for (unsigned int i=0 ; i<32 ; i++)
		{
			[names addObject: [NSString stringWithFormat: @"c%d", i]];
		}
		// Get an immutable version of the array
		integerRegisterNames = [names copy];
		traceDirectory = [file stringByDeletingLastPathComponent];
	}
}
- (IBAction)openProcstat: (id)sender
{
	NSString *file = openFile(@"Open output from procstat -v");
	if (file != nil)
	{
		addressMap = cheri::addressmap::open_procstat(std::string([file UTF8String]));
	}
}
- (IBAction)callGraph:(id)sender
{
#if 0
	// Currently disabled.  Eventually, we should construct a call graph from a
	// specific range.
	if ((addressMap != nil) && (streamTrace != nil))
	{
		[callGraph showStreamTrace: streamTrace
					    addressMap: addressMap
					 indexesToShow: [traceView selectedRowIndexes]
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
		return lastLoaded;
	}
	NSAssert(aTableView == regsView, @"Unexpected table view!");
	return (streamTrace == nullptr) ? 0 : 64;
}
-             (id)tableView: (NSTableView*)aTableView
  objectValueForTableColumn: (NSTableColumn*)aTableColumn
                        row: (NSInteger)rowIndex
{
	NSString *columnId = [aTableColumn identifier];
	if (aTableView == traceView)
	{
		auto trace = [self currentTrace];
		assert((uint64_t)rowIndex < trace->size());
		trace->seek_to(rowIndex);
		auto entry = trace->get_entry();
		if ([@"pc" isEqualToString: columnId])
		{
			NSColor *textColor = entry.is_kernel() ?
				[CVColors kernelAddressColor] : [CVColors userspaceAddressColor];
			return stringWithColor([NSString stringWithFormat: @"0x%.16" PRIx64,
					entry.pc], textColor);
		}
		if ([@"instruction" isEqualToString: columnId])
		{
			return stringWithColor([NSString stringWithFormat: @"0x%.8x", 
					entry.inst], [NSColor blackColor]);
		}
		if ([@"disassembly" isEqualToString: columnId])
		{
			disassembler::disassembler dis;
			auto info = dis.disassemble(entry.inst);
			NSColor *textColor = [CVColors colorForInstructionType: info.type];
			NSString *instr = [[NSString stringWithUTF8String: info.name.c_str()]
									stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
			NSMutableAttributedString *field = [stringWithColor(instr, textColor) mutableCopy];
			uint8_t ex = entry.exception;
			if (ex != 31)
			{
				[field appendAttributedString: stringWithColor([NSString stringWithFormat:@" [ Exception 0x%x ]", ex], [NSColor redColor])];
			}
			NSUInteger deadCycles = entry.dead_cycles;
			if (deadCycles > 0)
			{
				NSString *str = [NSString stringWithFormat: @" ; %lld dead cycles", (long long)deadCycles];
				[field appendAttributedString: stringWithColor(str, [NSColor blueColor])];

			}
			return field;
		}
		if ([@"cycles" isEqualToString: columnId])
		{
			return [NSString stringWithFormat: @"%" PRId64, entry.cycles];
		}
		if ([@"index" isEqualToString: columnId])
		{
			return [NSString stringWithFormat: @"%" PRId64, trace->instruction_number_for_index(rowIndex)];
		}
		NSString *note = [notes objectForKey: [NSString stringWithFormat: @"%" PRIu64, trace->instruction_number_for_index(rowIndex)]];
		// Work around a GNUstep bug where nil in a table view is not editable.
		return note ? note : @" ";
	}

	NSAssert(aTableView == regsView, @"Unexpected table view!");
	if ([@"name" isEqualToString: columnId])
	{
		return [integerRegisterNames objectAtIndex: rowIndex];
	}
	if ([@"value" isEqualToString: columnId])
	{
		NSUInteger gpridx = rowIndex - 1;
		if (rowIndex == 0)
		{
			return @"0";
		}
		NSAssert(gpridx >= 0, @"GPR index out of range");
		if (gpridx < 31)
		{
			NSAssert(gpridx >= 0 && gpridx<31, @"GPR index out of range");
			if (!registers.valid_gprs[gpridx])
			{
				return stringWithColor(@"???", [NSColor redColor]);
			}
			uint64_t value = registers.gpr[gpridx];
			return stringWithColor([NSString stringWithFormat: @"0x%.16" PRIx64, value], [NSColor blackColor]);
		}
		gpridx -= 31;
		NSAssert(gpridx >= 0 && gpridx<32, @"GPR index out of range");
		if (!registers.valid_caps[gpridx])
		{
			return stringWithColor(@"???", [NSColor redColor]);
		}
		auto &cap = registers.cap_reg[gpridx];
		return stringWithColor([NSString stringWithFormat: @"t:%1d u:%1d perms:0x%8.8" PRIx16
								" type:0x%6.6" PRIx32
								" offset:0x%16.16" PRIx64
								" base:0x%16.16" PRIx64
								" length:0x%16.16" PRIx64,
								(int)cap.valid,
								(int)cap.unsealed,
								cap.permissions,
								cap.type,
								cap.offset,
								cap.base,
								cap.length], [NSColor blackColor]);
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
	auto &trace = [self currentTrace];
	uint64_t idx = trace->instruction_number_for_index(rowIndex);
	[notes setObject: [anObject description] forKey: [NSString stringWithFormat: @"%" PRIu64, idx]];
	NSError *error = nil;
	NSData *json = [NSJSONSerialization dataWithJSONObject: notes
												   options: NSJSONWritingPrettyPrinted
													 error: &error];
	if (error)
	{
		[NSApp presentError: error];
		return;
	}
	[json writeToFile: notesFile atomically: YES];
}
- (std::shared_ptr<objectfile::function>)functionForPC: (uint64_t*)aPc isRelocated: (BOOL*)outBool rangeStart: (uint64_t*)rs
{
	uint64_t pc = *aPc;
	auto range = addressMap->mapping_for_address(pc);
	if (range.file_name == std::string())
	{
		NSLog(@"Could not find address range");
		return nullptr;
	}
	if (rs != NULL)
	{
		*rs = range.start;
	}
	auto objectFile = objectFiles[range.file_name];
	NSString *fileName = [NSString stringWithUTF8String: range.file_name.c_str()];
	if (objectFile == nullptr)
	{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *fileName = [NSString stringWithUTF8String: range.file_name.c_str()];
		NSString *path = [traceDirectory stringByAppendingPathComponent: [fileName lastPathComponent]];
		if ([fm fileExistsAtPath: path])
		{
			objectFile = objectfile::file::open(std::string([path UTF8String]));
		}
		if (objectFile == nullptr)
		{
			path = [traceDirectory stringByAppendingPathComponent: fileName];
			if ([fm fileExistsAtPath: path])
			{
				objectFile = objectfile::file::open(std::string([path UTF8String]));
			}
		}
		if (objectFile == nullptr)
		{
			path = openFile([NSString stringWithFormat: @"Open object file: %@", fileName]);
			if (path != nil)
			{
				objectFile = objectfile::file::open(std::string([path UTF8String]));
				if (objectFile == nullptr)
				{
					[[NSAlert alertWithMessageText: @"Unable to open object file"
					                 defaultButton: nil
					               alternateButton: nil
					                   otherButton: nil
					     informativeTextWithFormat: @""] runModal];
					return nullptr;
				}
			}
		}
		if (objectFile == nullptr)
		{
			return nullptr;
		}
		objectFiles[range.file_name] = objectFile;
	}
	BOOL isRelocated = NO;
	if ([[fileName lastPathComponent] rangeOfString: @".so"].location != NSNotFound)
	{
		pc -= range.start;
		isRelocated = YES;
		*aPc = pc;
	}
	if (outBool != 0)
	{
		*outBool = isRelocated;
	}
	return objectFile->function_at_address(pc);
}
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == traceView)
	{
		NSInteger selectedRow = [traceView selectedRow];
		if (selectedRow == -1)
		{
			return;
		}
		auto trace = [self currentTrace];
		trace->seek_to(selectedRow);
		registers = std::move(trace->get_regs());
		[regsView reloadData];
		if (addressMap == nullptr)
		{
			return;
		}
		uint64_t pc = trace->get_entry().pc;
		BOOL isRelocated;
		uint64_t rs;
		auto func = [self functionForPC: &pc isRelocated: &isRelocated rangeStart: &rs];
		if (func == nullptr)
		{
			return;
		}
		[disassembly setFunction: func
		         withBaseAddress: func->base_address() + (isRelocated ? rs : 0)];
		[disassembly scrollAddressToVisible: pc + (isRelocated ? rs : 0)];
	}
}
-    (BOOL)tableView:(NSTableView*)aTableView
writeRowsWithIndexes:(NSIndexSet*)rowIndexes
        toPasteboard:(NSPasteboard*)pboard
{
	return WriteTableViewToPasteboard(self, aTableView, rowIndexes, pboard);
}
- (IBAction)changeDisplay: (id)sender
{
	[traceView reloadData];
}
@end



