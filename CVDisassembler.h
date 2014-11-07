#import <Foundation/NSString.h>

/**
 * Enumerated type for instruction types.  This is currently very
 * coarse-grained, but may be improved in the future.
 */
typedef enum {
	/** Unknown instruction type. */
	CVInstructionTypeUnknown = 0,
	/** Flow control instructions (jumps and branches). */
	CVInstructionTypeFlowControl,
	/** Memory access instructions (loads and stores). */
	CVInstructionTypeMemory
} CVInstructionType;

/**
 * The CVDisassembler class encapsulates a dissassembler for CHERI / MIPS.
 * It assumes fixed-width 32-bit instructions, in host-endian order.
 */
@interface CVDisassembler : NSObject
/**
 * Diassemble the instruction, returning the decoded version as a string.
 */
- (NSString*)disassembleInstruction: (uint32_t)anInstruction;
/**
 * Disassemble the instruction and return its type.
 */
- (CVInstructionType)typeOfInstruction: (uint32_t)anInstruction;
/**
 * Disassemble the instruction and return the destination register number, or
 * -1 if this instruction does not define a register.
 */
- (int)destinationRegisterForInstruction: (uint32_t)anInstruction;
/**
 * Returns YES if the instruction can be decoded and identified as a call
 * instruction, NO otherwise.
 */
- (BOOL)isCallInstruction: (uint32_t)anInstruction;
/**
 * Returns YES if the instruction can be decoded and identified as a return
 * instruction, NO otherwise.
 */
- (BOOL)isReturnInstruction: (uint32_t)anInstruction;
/**
 * Returns YES if the instruction has a delay slot, otherwise NO.
 */
- (BOOL)hasDelaySlot: (uint32_t)anInstruction;
@end

static const char* const MipsRegisterNames[] = {
	"zero", "at", "v0", "v1",
	"a0", "a1", "a2", "a3", 
	"t0", "t1", "t2", "t3", 
	"t4", "t5", "t6", "t7", 
	"s0", "s1", "s2", "s3", 
	"s4", "s5", "s6", "s7", 
	"t8", "t9", "k0", "k1",
	"gp", "sp", "fp", "ra"
};
