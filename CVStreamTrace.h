#import <Foundation/NSString.h>
#import "CVDisassembler.h"

/**
 * The CVStreamTrace class encapsulates a stream trace from the CHERI debug
 * unit.  This includes a sequence of instructions and the inferred machine
 * state arising.
 */
@interface CVStreamTrace : NSObject
/**
 * Initialises the stream trace object with some stream data.  This data is in
 * the binary format generated by cherictl -b streamtrace.
 *
 * The file name is where annotations will be loaded from and stored.
 */
- (id)initWithTraceData: (NSData*)aTrace notesFileName: (NSString*)aString error: (NSError **)error;
/**
 * Sets the index of the stream trace object to a specified offset into the
 * stream.  Stateful accessor methods use this index.  Returns YES if passed a
 * valid index, NO otherwise.
 */
- (BOOL)setStateToIndex: (NSInteger)anIndex;
/**
 * Returns the number of entries in the trace that this object was initialised
 * with.
 */
- (NSInteger)numberOfTraceEntries;
/**
 * Returns the number of trace entries where the program counter is in the
 * kernel address range.
 */
- (NSInteger)numberOfKernelTraceEntries;
/**
 * Returns the number of trace entries where the program counter is in the
 * userspace address range.
 */
- (NSInteger)numberOfUserspaceTraceEntries;
/**
 * Returns the index in the trace that corresponds to the index within just the
 * kernelspace instructions.
 */
- (NSInteger)kernelTraceEntryAtIndex: (NSInteger)anIndex;
/**
 * Returns the index in the trace that corresponds to the index within just the
 * userspace instructions.
 */
- (NSInteger)userspaceTraceEntryAtIndex: (NSInteger)anIndex;
/**
 * Returns the (decoded) instruction for the current index in the stream.
 */
- (NSString*)instruction;
/**
 * Returns the instruction for the current index in the stream, in encoded (big
 * endian) form.
 */
- (uint32_t)encodedInstruction;
/**
 * Returns the number of dead cycles before this instruction.
 */
- (NSUInteger)deadCycles;
/**
 * Returns an array of the integer registers whose value can be inferred at
 * this point in the trace.  Values that can not be inferred are represented by
 * the placeholder string "???".
 */
- (NSArray*)integerRegisters;
/**
 * Returns an array of the ABI names of the integer registers returned by
 * -integerRegisters.
 */
- (NSArray*)integerRegisterNames;
/**
 * Returns the program counter value for the current index in the stream trace.
 */
- (uint64_t)programCounter;
/**
 * Returns the number of cycles in the current trace before the current instruction.
 */
- (uint64_t)cycleCount;
/**
 * Returns the type of the instruction at the current index in the stream.
 */
- (CVInstructionType)instructionType;
/**
 * Returns the value of the exception code.  A value of 31 indicates no
 * exception (this is really a signed 5-bit quantity, with -1 indicating no
 * exception).
 */
- (uint8_t)exception;
/**
 * Returns YES if the current instruction is from a kernelspace address, NO if
 * it is from a userspace address.
 */
- (BOOL)isKernel;
/**
 * Returns the annotation associated with this entry.
 */
- (NSString*)notes;
/**
 * Associate notes with this entry.
 */
- (void)setNotes: (NSString*)aString error: (NSError **)error;
@end

extern NSString *CVStreamTraceLoadedEntriesNotification;
extern NSString *kCVStreamTraceLoadedEntriesCount;
extern NSString *kCVStreamTraceLoadedAllEntries;
