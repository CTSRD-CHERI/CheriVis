/*-
 * Copyright (c) 2015 David T Chisnall
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */
#import "CVColors.h"
#import <AppKit/AppKit.h>

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
