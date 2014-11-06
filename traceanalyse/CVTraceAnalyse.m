#import "CVTraceAnalyse.h"
#import "CVStreamTrace.h"
#import "CVAddressMap.h"

struct TraceStats
{
	long interrupt;
	long tlbModify;
	long tlbLoad;
	long tlbStore;
	long sysCall;
	long otherException;
	long userCycles;
	long kernelCycles;
};

static void usage()
{
	const char *progName = [[[NSProcessInfo processInfo] processName] UTF8String];
	fprintf(stderr, "Usage: %s {arguments}\n\nArguments:\n", progName);
	fprintf(stderr, "\t-traceFile {filename}\t\tThe name of the trace file to process\n");
	fprintf(stderr, "\t-start {index}\t\tThe start index in the trace to process\n");
	fprintf(stderr, "\t-end {index}\t\tThe end index in the trace to process\n");
	fprintf(stderr, "\t-startPC {address}\t\tIgnore all of the trace before this PC is reached\n");
	fprintf(stderr, "\t-endPC {address}\t\tIgnore all of the trace after this PC is reached\n");
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
- (void)printStats: (struct TraceStats)stats
{
	printf("%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\n",
		   stats.interrupt,
		   stats.tlbModify,
		   stats.tlbLoad,
		   stats.tlbStore,
		   stats.sysCall,
		   stats.otherException,
		   stats.userCycles,
		   stats.kernelCycles);
}
- (void)processTrace
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSInteger start = [defaults integerForKey: @"start"];
	NSInteger end = [defaults integerForKey: @"end"];
	uint64_t startPC = [defaults integerForKey: @"startPC"];
	uint64_t endPC = [defaults integerForKey: @"endPC"];
	if (end == 0)
	{
		end = [trace numberOfTraceEntries];
	}
	BOOL log = NO;
	if (startPC == 0)
	{
		log = YES;
	}
	NSLog(@"%ld - %ld", start, end);
	struct TraceStats s;
	bzero(&s, sizeof(s));
	printf("Interrupts\tTLB_Modify\tTLB_Load\tTLB_Store\tSyscall\tOther Exceptions\tUserspace Cycles\tKernel Cycles\n");

	for (NSInteger i=start ; i<end ; i++)
	{
		[trace setStateToIndex: i];
		// Sometimes we end up with a 0 entry at the start of the streamtrace.  If so, skip it.
		if ([trace programCounter] == 0)
		{
			continue;
		}
		if (log == NO)
		{
			if ([trace programCounter] != startPC)
			{
				continue;
			}
			log = YES;
		}
		else
		{
			if (endPC == [trace programCounter])
			{
				log = NO;
				[self printStats: s];
				bzero(&s, sizeof(s));
				continue;
			}
		}

		switch ([trace exception])
		{
			case 0:
				s.interrupt++;
				break;
			case 1:
				s.tlbModify++;
				break;
			case 2:
				s.tlbLoad++;
				break;
			case 3:
				s.tlbStore++;
				break;
			case 8:
				s.sysCall++;
				break;
			case 31:
				break;
			default:
				s.otherException++;
		}
		long *cycles = [trace isKernel] ? &s.kernelCycles : &s.userCycles;
		*cycles += [trace deadCycles] + 1;
	}
	if (log)
	{
		[self printStats: s];
	}
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
