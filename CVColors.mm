#import "CVColors.h"

static NSColor *greenColor;
static NSColor *redColor;

typedef cheri::disassembler::instruction_info::instruction_type inst_type;

@implementation CVColors : NSObject
+ (void)initialize
{
	// Depending on the theme that we have selected, the default light green
	// colour may not be easy to see on the table view background.  If we've
	// got a theme with a light colour, use a darker green than the default.
	NSColor *tableColor = [NSColor controlBackgroundColor];
	tableColor = [tableColor colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
	if ([tableColor brightnessComponent] > 0.6)
	{
		greenColor = [NSColor colorWithCalibratedRed: 0 green: 0.5 blue: 0 alpha: 1];
	}
	else
	{
		greenColor = [[NSColor greenColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
	}
	redColor = [[NSColor redColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
}
+ (NSColor*)memoryInstructionColor
{
	return greenColor;
}
+ (NSColor*)flowControlInstructionColor
{
	return redColor;
}
+ (NSColor*)colorForInstructionType: (inst_type)aType
{
	switch (aType)
	{
		case cheri::disassembler::instruction_info::unknown:
			return [NSColor blackColor];
		case cheri::disassembler::instruction_info::flow_control:
			return [self flowControlInstructionColor];
		case cheri::disassembler::instruction_info::memory_access:
			return [self memoryInstructionColor];
	}
}
+ (NSColor*)kernelAddressColor
{
	return redColor;
}
+ (NSColor*)userspaceAddressColor
{
	return greenColor;
}
+ (NSColor*)undefinedRegisterValueColor
{
	return redColor;
}
@end
