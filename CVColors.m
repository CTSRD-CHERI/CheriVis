#import "CVColors.h"
#import <Cocoa/Cocoa.h>


static NSColor *greenColor;
static NSColor *redColor;

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
+ (NSColor*)colorForInstructionType: (CVInstructionType)aType
{
	switch (aType)
	{
		case CVInstructionTypeUnknown:
			return [NSColor blackColor];
		case CVInstructionTypeFlowControl:
			return [self flowControlInstructionColor];
		case CVInstructionTypeMemory:
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
