#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/StringRefMemoryObject.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCAtom.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCDisassembler.h"
#include "llvm/MC/MCFunction.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstPrinter.h"
#undef NO
#include "llvm/MC/MCInstrAnalysis.h"
#define NO (BOOL)0
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCModule.h"
#include "llvm/MC/MCObjectDisassembler.h"
#include "llvm/MC/MCObjectFileInfo.h"
#include "llvm/MC/MCObjectSymbolizer.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCRelocationInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"

#import <Foundation/Foundation.h>
#import "CVStreamTrace.h"

using namespace llvm;


//FIXME: Include cheri_debug.h from cherilibs
struct cheri_debug_trace_entry_disk {
	uint8_t   version;
	uint8_t   exception;
	uint16_t  cycles;
	uint32_t  inst;
	uint64_t  pc;
	uint64_t  val1;
	uint64_t  val2;
} __attribute__((packed));



// We could compress this a lot by storing only the deltas, but given that the
// entire 4096 element trace will only generate about 1MB of data, it's not
// worth it (yet).  When we add in the CHERI state, this becomes a few MBs, so
// might be more sensible...  Alternatively, we may only compute it lazily and
// only cache some values (e.g. every 10th or 100th).

struct RegisterState
{
	uint16_t cycle_count;
	uint32_t instr;
	uint8_t  exception;
	CVInstructionType instructionType;
	uint64_t pc;
	uint32_t validRegisters;
	uint64_t registers[32];
	// TODO: Capability registers
};

@implementation CVStreamTrace
{
	OwningArrayPtr<struct RegisterState> registers;
	NSInteger length;
	NSData *trace;
	NSInteger idx;
	CVDisassembler *disassembler;
}
- (id)initWithTraceData: (NSData*)aTrace
{
	if (nil == (self = [super init])) { return nil; }
	trace = aTrace;
	disassembler = [CVDisassembler new];
	length = [trace length] / 32;
	registers.reset(new struct RegisterState[length]);

	for (NSInteger i=0 ; i<length ; i++)
	{
		struct cheri_debug_trace_entry_disk traceEntry;
		[trace getBytes: &traceEntry
		          range: NSMakeRange(i*32, 32)];

		struct RegisterState &rs = registers[i];
		if (i > 1)
		{
			struct RegisterState &ors = registers[i-1];
			rs.validRegisters = ors.validRegisters;
			memcpy((void*)rs.registers, ors.registers, sizeof(rs.registers));
		}
		rs.pc = NSSwapBigLongLongToHost(traceEntry.pc);
		if ((i % 1000) == 0)
		rs.cycle_count = NSSwapBigShortToHost(traceEntry.cycles);
		rs.exception = traceEntry.exception;
		rs.instr = traceEntry.inst;
		if (traceEntry.version == 1 || traceEntry.version == 2)
		{
			int regNo = [disassembler destinationRegisterForInstruction: rs.instr];
			if (regNo >= 0)
			{
				rs.validRegisters |= (1<<regNo);
				rs.registers[regNo] = NSSwapBigLongLongToHost(traceEntry.val2);
			}
		}
	}
	return self;
}
- (BOOL)setStateToIndex: (NSInteger)anIndex
{
	if (anIndex < 0 || anIndex >= length)
	{
		return NO;
	}
	idx = anIndex;
	return YES;
}
- (NSString*)instruction
{
	return [disassembler disassembleInstruction: registers[idx].instr];
}
- (uint32_t)encodedInstruction
{
	return registers[idx].instr;
}
- (NSArray*)integerRegisters
{
	NSMutableArray *array = [NSMutableArray new];
	[array addObject: [NSNumber numberWithInt: 0]];
	uint32_t mask = registers[idx].validRegisters;
	uint64_t *regs = registers[idx].registers;
	for (int i=1 ; i<32 ; i++)
	{
		if ((mask & (1<<i)) == 0)
		{
			[array addObject: @"???"];
		}
		else
		{
			[array addObject: [NSNumber numberWithLongLong: (long long)regs[i]]];
		}
	}
	return array;
}
- (uint64_t)programCounter
{
	return registers[idx].pc;
}
- (NSInteger)numberOfTraceEntries
{
	return length;
}
- (NSArray*)integerRegisterNames
{
	NSMutableArray *array = [NSMutableArray new];
	for (size_t i=0 ; i<(sizeof(MipsRegisterNames) / sizeof(*MipsRegisterNames)) ; i++)
	{
		[array addObject: [NSString stringWithFormat: @"$%d %s", i, MipsRegisterNames[i]]];
	}
	return array;
}
- (CVInstructionType)instructionType
{
	return [disassembler typeOfInstruction: registers[idx].instr];
}
- (uint8_t)exception
{
	return registers[idx].exception;
}
- (BOOL)isKernel
{
	return registers[idx].pc > 0xFFFFFFFF0000000;
}
@end

