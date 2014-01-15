#import <Foundation/NSString.h>

/**
 * A CVFunction encapsulates a single function.
 */
@interface CVFunction : NSObject
/**
 * The name of the function.
 */
- (NSString*)mangledName;
/**
 * The function name, demangled if it is a C++ function.
 */
- (NSString*)demangledName;
/**
 * Returns the number of instructions in this fuction
 */
- (NSUInteger)numberOfInstructions;
/**
 * Returns the instruction at the specified address.  The address is an offset
 * from the start of the function.
 */
- (uint32_t)instructionAtAddress: (uint64_t)anAddress;
/**
 * Returns the address where this starts within the object that contains it.
 */
- (uint64_t)baseAddress;
@end

/**
 * The CVObjectFile class encapsulates an object file (a program or a shared
 * library) and is responsible for looking up addresses and symbols and
 * dissassembling parts of the file.
 */
@interface CVObjectFile : NSObject
/**
 * Returns a new object file, parsing the code at the specified path.
 */
+ (CVObjectFile*)objectFileForFilePath: (NSString*)aPath;
/**
 * Creates a new function object encapsulating a function surrounding a
 * specified pc address.
 */
- (CVFunction*)functionForAddress: (uint64_t)anAddress;
@end
