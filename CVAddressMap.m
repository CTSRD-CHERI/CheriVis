#import "CVAddressMap.h"
#import <Foundation/Foundation.h>
#import <Foundation/NSTextCheckingResult.h>

@implementation CVAddressMap
{
	/**
	 * A C array of address ranges.
	 */
	CVAddressRange *addresses;
	/**
	 * The number of address ranges in the addresses array.
	 */
	NSInteger addressCount;
	/**
	 * An array holding the file names.  This exists solely to provide an owner
	 * for the strings referred to in the addresses array.
	 */
	NSMutableArray *files;
}
- (id)initWithProcstatOutput: (NSString*)procstat
{
	if (nil == (self = [super init])) { return nil; }

	NSArray *lines = [procstat componentsSeparatedByString: @"\n"];

	if ([lines count] < 2) { return nil; }

	// Ignore the header line
	lines = [lines subarrayWithRange: NSMakeRange(1, [lines count]-1)];
	addresses = calloc([lines count], sizeof(CVAddressRange));
	files = [NSMutableArray new];
	CVAddressRange *ar = addresses;
	// Each line looks something like this:
	//  1124        0x160010000        0x16002d000 r-x   29    0   1   0 C--- vn /libexec/ld-elf.so.1
	NSError *e;
	NSString *pattern = @"\\s*\\d+\\s+0x([0-9a-f]+)\\s+0x([0-9a-f]+)\\s+([r-])([w-])([x-])\\s+\\d+\\s+\\d+\\s+\\d+\\s+\\d+\\s+\\S+\\s+\\S+\\s*(\\S*)";
	NSRegularExpression *re =
	    [NSRegularExpression regularExpressionWithPattern: pattern
	                                              options: 0
	                                                error: &e];
	// FIXME: Proper error handling...
	if (e) NSLog(@"Error: %@", e);

	for (NSString *line in lines)
	{
		if ([line length] == 0) { continue; }
		NSArray *matches = [re matchesInString: line options: NSMatchingAnchored range: NSMakeRange(0, [line length])];
		NSTextCheckingResult *match = [matches objectAtIndex:0];
		if (match == nil)
		{
			NSLog(@"Failed to parse procstat line:\n%@", line);
			continue;
		}
		NSTextCheckingResult *r = [matches objectAtIndex: 0];
		ar->start = strtoll([[line substringWithRange: [r rangeAtIndex: 1]] UTF8String], 0, 16);
		ar->end = strtoll([[line substringWithRange: [r rangeAtIndex: 2]] UTF8String], 0, 16);
		ar->isReadable = [line characterAtIndex: [r rangeAtIndex: 3].location] == 'r';
		ar->isWriteable = [line characterAtIndex: [r rangeAtIndex: 4].location] == 'w';
		ar->isExecuteable = [line characterAtIndex: [r rangeAtIndex: 5].location] == 'x';
		NSRange fileRange = [r rangeAtIndex: 6];
		if (fileRange.length > 0)
		{
			NSString *fileName = [line substringWithRange: fileRange];
			[files addObject: fileName];
			ar->fileName = fileName;
		}
		ar++;
		addressCount++;
	}
	return self;
}
- (CVAddressRange)mappingForAddress: (unsigned long long)addr
{
	if (addr > 0xffffffff00000000)
	{
		CVAddressRange kernelAr = {
			0xffffffff00000000,
			0xffffffffffffffff,
			@"kernel",
			1, 0, 1
		};
		return kernelAr;
	}
	// Note: linear search because the size is small and there isn't a huge
	// advantage in doing anything more efficient...
	for (NSInteger i=0 ; i<addressCount ; i++)
	{
		CVAddressRange *ar = &addresses[i];
		if ((ar->start <= addr) && (ar->end >= addr))
		{
			return *ar;
		}
	}
	return (CVAddressRange){0};
}
- (void)dealloc
{
	free(addresses);
}
@end
