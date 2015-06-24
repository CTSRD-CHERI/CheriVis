#import "CVDisassemblyController.h"
#include "cheritrace/disassembler.hh"
#import "CVColors.h"
#import <Cocoa/Cocoa.h>

using namespace cheri::disassembler;

BOOL WriteTableViewToPasteboard(id<NSTableViewDataSource> data,
                                NSTableView *aTableView,
                                NSIndexSet *rowIndexes,
                                NSPasteboard *pboard);

/**
 * Helper function that creates an attributed string by applying a single
 * colour and a fixed-width font to a string.
 */
static NSAttributedString* stringWithColor(NSString *str, NSColor *color)
{
	if (nil == color)
	{
		color = [NSColor blackColor];
	}
	NSFont *font = [NSFont userFixedPitchFontOfSize: 12];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
		font, NSFontAttributeName,
		color, NSForegroundColorAttributeName, nil];
	return [[NSAttributedString alloc] initWithString: str attributes: dict];
}

/**
 * The CVDisassemblyController class implements the controller for disassembly
 * view in the application.  
 *
 * A single instance of it is created in the main nib file for the application.
 */
@implementation CVDisassemblyController
{
	/**
	 * The view that shows the disassembly of the current function.
	 */
	IBOutlet __unsafe_unretained NSTableView  *disassembly;
	/**
	 * The text field containing the name of the current function.
	 */
	IBOutlet __unsafe_unretained NSTextField  *nameField;
	/**
	 * The text field containing the demangled name of the current function.
	 */
	IBOutlet __unsafe_unretained NSTextField  *demangledNameField;
	/**
	 * The function currently being shown.
	 */
	std::shared_ptr<cheri::objectfile::function> currentFunction;
	/**
	 * The address at which this function starts.
	 */
	uint64_t startAddress;
	/**
	 * Disassembler for human-friendly display.
	 */
	disassembler disassembler;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return (currentFunction == nullptr) ? 0 : currentFunction->size()/4;
}
-             (id)tableView: (NSTableView*)aTableView
  objectValueForTableColumn: (NSTableColumn*)aTableColumn
                        row: (NSInteger)rowIndex
{
	NSString *columnId = [aTableColumn identifier];
	if ([@"pc" isEqualToString: columnId])
	{
		return stringWithColor([NSString stringWithFormat: @"0x%.16" PRIx64,
				startAddress + (rowIndex * 4)], nil);
	}
	if ([@"instruction" isEqualToString: columnId])
	{
		return stringWithColor([NSString stringWithFormat: @"0x%.8x",
			(*currentFunction)[4*rowIndex]], nil);
	}
	NSAssert([@"disassembly" isEqualToString: columnId], @"Unexpected column id!");
	uint32_t instr = (*currentFunction)[4*rowIndex];
	auto info = disassembler.disassemble(instr);
	NSColor *textColor = [CVColors colorForInstructionType: info.type];
	NSString *instruction = [NSString stringWithUTF8String: info.name.c_str()];
	return stringWithColor(instruction, textColor);
}
- (void)scrollAddressToVisible: (uint64_t)anAddress
{
	uint64_t rowIdx = anAddress - startAddress;
	rowIdx /= 4;
	if (rowIdx > 0 && rowIdx < currentFunction->size())
	{
		[disassembly scrollRowToVisible: rowIdx];
		[disassembly selectRow: rowIdx byExtendingSelection: NO];
	}
}
- (void)setFunction: (std::shared_ptr<cheri::objectfile::function>&)aFunction
	withBaseAddress: (uint64_t)aBase
{
	if (aFunction != currentFunction)
	{
		startAddress = aBase;
		currentFunction = aFunction;
		[nameField setStringValue: [NSString stringWithUTF8String: aFunction->mangled_name().c_str()]];
		[demangledNameField setStringValue: [NSString stringWithUTF8String: aFunction->demangled_name().c_str()]];
		[disassembly reloadData];
	}
}
-    (BOOL)tableView:(NSTableView*)aTableView
writeRowsWithIndexes:(NSIndexSet*)rowIndexes
        toPasteboard:(NSPasteboard*)pboard
{
	return WriteTableViewToPasteboard(self, aTableView, rowIndexes, pboard);
}
@end

