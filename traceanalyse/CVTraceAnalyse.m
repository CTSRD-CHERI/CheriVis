#import "CVTraceAnalyse.h"
#import "CVStreamTrace.h"
#import "CVAddressMap.h"

static void usage()
{
	const char *progName = [[[NSProcessInfo processInfo] processName] UTF8String];
	fprintf(stderr, "Usage: %s {arguments}\n\nArguments:\n", progName);
	fprintf(stderr, "\t-traceFile {filename}\t\tThe name of the trace file to process\n");
	exit(EXIT_FAILURE);
}

static void reportErrorIf(NSString *context, NSError *error)
{
	if (error == nil)
	{
		return;
	}
	fprintf(stderr, "Error %s: %s\n", [context UTF8String], [[error localizedDescription] UTF8String]);
	exit(EXIT_FAILURE);
}

@implementation CVTraceAnalyse
{
	CVStreamTrace *trace;
	CVAddressMap  *procstat;
	NSString *functionName;
}
- (void)traceLoaded: (NSNotification*)aNotification
{
	NSDictionary *userInfo = [aNotification userInfo];
	fprintf(stderr, "%lld...", [[userInfo objectForKey: kCVStreamTraceLoadedEntriesCount] longLongValue]);
	NSAssert([aNotification object] == trace, @"Unexpected notification!");
	if ([[userInfo objectForKey: kCVStreamTraceLoadedAllEntries] boolValue])
	{
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name: CVStreamTraceLoadedEntriesNotification
													  object: [aNotification object]];
		fprintf(stderr, "done\n");
		[self processTrace];
	}
}
- (void)processTrace
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSInteger start = [defaults integerForKey: @"start"];
	NSInteger end = [defaults integerForKey: @"end"];
	if (end == 0)
	{
		end = [trace numberOfTraceEntries];
	}
	NSLog(@"%ld - %ld", start, end);
	long interrupt = 0;
	long tlbModify = 0;
	long tlbLoad = 0;
	long tlbStore = 0;
	long sysCall = 0;
	long otherException = 0;
	long userCycles = 0;
	long kernelCycles = 0;

	for (NSInteger i=start ; i<end ; i++)
	{
		[trace setStateToIndex: i];

		switch ([trace exception])
		{
			case 0:
				interrupt++;
				break;
			case 1:
				tlbModify++;
				break;
			case 2:
				tlbLoad++;
				break;
			case 3:
				tlbStore++;
				break;
			case 8:
				sysCall++;
				break;
			case 31:
				break;
			default:
				otherException++;
		}
		long *cycles = [trace isKernel] ? &kernelCycles : &userCycles;
		*cycles += [trace deadCycles] + 1;
	}
	printf("Interrupts\tTLB_Modify\tTLB_Load\tTLB_Store\tSyscall\tOther Exceptions\tUserspace Cycles\tKernel Cycles\n");
	printf("%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\n", interrupt, tlbModify, tlbLoad, tlbStore, sysCall, otherException, userCycles, kernelCycles);
	exit(EXIT_SUCCESS);
}
- (void)run
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *traceFile = [defaults stringForKey: @"traceFile"];
	NSError *error = nil;
	if (traceFile == nil)
	{
		usage();
	}
	NSData *traceData = [[NSData alloc] initWithContentsOfFile: traceFile
													   options: NSDataReadingMappedAlways
														 error: &error];
	reportErrorIf(@"opening trace file", error);
	trace = [[CVStreamTrace alloc] initWithTraceData: traceData
									   notesFileName: nil
											   error: &error];
	reportErrorIf(@"reading trace", error);
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(traceLoaded:)
												 name: CVStreamTraceLoadedEntriesNotification
											   object: trace];
	fprintf(stderr, "Loading trace...");
	[[NSRunLoop currentRunLoop] run];
}

@end
