#import <Foundation/NSObject.h>

@class CVFunction;

/**
 * The CVDisassemblyController class is the controller for the disassembled
 * object view in CheriVis.  A single instance of this class is created in the
 * main nib.
 */
@interface CVDisassemblyController : NSObject <NSTableViewDataSource>
/**
 * Makes the specified address in the disassembly visible.
 */
- (void)scrollAddressToVisible: (uint64_t)anAddress;
/**
 * Sets the current function.  The base address is the address in memory where
 * the function is located.  
 */
- (void)setFunction: (CVFunction*)aFunction withBaseAddress: (uint64_t)aBase;
@end
