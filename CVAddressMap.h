#import <Foundation/NSString.h>

/**
 * A single address range.  Defines the backing for an address range within the
 * inspected address space.
 */
typedef struct _CVAddressRange
{
	/**
	 * The start of this address range.
	 */
	unsigned long long start;
	/**
	 * The end of this address range.
	 */
	unsigned long long end;
	/**
	 * The file name.  The CVAddressMap object responsible for this address
	 * range owns the pointer to the string.
	 */
	__unsafe_unretained NSString *fileName;
	/**
	 * Is this object mapped with read permissions?
	 */
	BOOL isReadable: 1;
	/**
	 * Is this object mapped with write permissions?
	 */
	BOOL isWriteable: 1;
	/**
	 * Is this object mapped with execute permissions?
	 */
	BOOL isExecuteable: 1;
} CVAddressRange;

/**
 * The CVAddressMap class encapsulates the mapping from virtual addresses to
 * files in a process.
 */
@interface CVAddressMap : NSObject
/**
 * Parse the output from procstat -v and produce an address mapping.
 */
- (id)initWithProcstatOutput: (NSString*)procstat;
/**
 * Returns the mapping for an address.
 */
- (CVAddressRange)mappingForAddress: (unsigned long long)addr;
@end

/**
 * A convenience function for generating human-readable string from an address
 * range.
 */
__attribute__((unused))
static inline NSString *NSStringFromAddressRange(CVAddressRange r)
{
	return [NSString stringWithFormat: @"0x%llx 0x%llx %c%c%c %@",
	    r.start, r.end, (r.isReadable ? 'r' : '-'), (r.isWriteable? 'w' : '-'),
	    (r.isExecuteable ? 'x' : '-'), (r.fileName ? r.fileName: @"")];
}
