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
#include "llvm/MC/MCInstrAnalysis.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCModule.h"
#include "llvm/MC/MCObjectDisassembler.h"
#include "llvm/MC/MCObjectFileInfo.h"
#include "llvm/MC/MCObjectSymbolizer.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCRelocationInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"

#import "CVDisassembler.h"
#import <Foundation/Foundation.h>

#include <vector>
#include <cxxabi.h>

using namespace llvm;


static const Target *target;
static OwningPtr<const MCRegisterInfo> mri;
static OwningPtr<const MCAsmInfo> asmInfo;
static OwningPtr<const MCSubtargetInfo> sti;
static OwningPtr<const MCInstrInfo> mii;
static OwningPtr<const MCInstrAnalysis> mia;
static OwningPtr<MCDisassembler> disAsm;
static OwningPtr<MCInstPrinter> instrPrinter;

namespace llvm {
	extern const MCInstrDesc MipsInsts[];
}

static int registerIndexForString(const char *str)
{
	if (str[0] == '$')
	{
		str++;
	}
	char *end;
	long idx = strtol(str, &end, 10);
	if (str != end)
	{
		return idx;
	}
	for (size_t i=0 ; i<(sizeof(MipsRegisterNames) / sizeof(*MipsRegisterNames)) ; i++)
	{
		if (strcmp(str, MipsRegisterNames[i]) == 0)
		{
			return i;
		}
	}
	return -1;
}

static int registerIndexForLLVMRegNo(unsigned regNo)
{
	std::string regName;
	raw_string_ostream regStream(regName);
	instrPrinter->printRegName(regStream, regNo);
	return registerIndexForString(regStream.str().c_str());
}

static MCDisassembler::DecodeStatus disassembleInstruction(uint64_t anInstruction,
                                                           MCInst &inst)
{
	anInstruction = NSSwapBigIntToHost(anInstruction);
	StringRefMemoryObject memoryObject(StringRef((const char*)&anInstruction, sizeof(anInstruction)), 0);
	uint64_t size;
	return disAsm->getInstruction(inst, size, memoryObject, 0, errs(),
	                              errs());
}


@implementation CVDisassembler
- (NSString*)disassembleInstruction: (uint32_t)anInstruction
{
	MCInst inst;
	if (disassembleInstruction(anInstruction, inst) == MCDisassembler::Success)
	{
		// FIXME: Works around a bug in LLVM.
		if (inst.getOpcode() != 1051 &&
		    inst.getOpcode() != 1098)
		{
			std::string buffer;
			raw_string_ostream os(buffer);
			instrPrinter->printInst(&inst, os, "");
			return [NSString stringWithUTF8String: os.str().c_str()];
		}
	}
	return @"<Unable to disassemble>";
}
- (CVInstructionType)typeOfInstruction: (uint32_t)anInstruction
{
	MCInst inst;
	if (disassembleInstruction(anInstruction, inst) == MCDisassembler::Success)
	{
		const MCInstrDesc &desc = MipsInsts[inst.getOpcode()];
		if (desc.isBranch() || desc.isCall() || desc.isReturn())
		{
			return CVInstructionTypeFlowControl;
		}
		if (desc.mayLoad() || desc.mayStore())
		{
			return CVInstructionTypeMemory;
		}
	}
	return CVInstructionTypeUnknown;
}
- (int)destinationRegisterForInstruction: (uint32_t)anInstruction
{
	MCInst inst;
	if (disassembleInstruction(anInstruction, inst) == MCDisassembler::Success)
	{
		const MCInstrDesc &desc = MipsInsts[inst.getOpcode()];
		const uint16_t *implicitDefs = desc.getImplicitDefs();
		unsigned numImplicitDefs = desc.getNumImplicitDefs();
		for (unsigned i=0 ; i<numImplicitDefs ; i++)
		{
			int regNo = registerIndexForLLVMRegNo(implicitDefs[i]);
			if (regNo >= 0)
			{
				return regNo;
			}
		}
		if (inst.getNumOperands() > 0)
		{
			MCOperand op0 = inst.getOperand(0);
			if (op0.isReg())
			{
				if (desc.hasDefOfPhysReg(inst, op0.getReg(), *mri.get()))
				{
					int regNo = registerIndexForLLVMRegNo(op0.getReg());
					if (regNo >= 0)
					{
						return regNo;
					}
				}
			}
		}
	}
	return -1;
}
- (BOOL)isCallInstruction: (uint32_t)anInstruction
{
	MCInst inst;
	if (disassembleInstruction(anInstruction, inst) == MCDisassembler::Success)
	{
		const MCInstrDesc &desc = MipsInsts[inst.getOpcode()];
		return desc.isCall();
	}
	NSAssert(anInstruction != 0x0320f809, @"Failed to detect PIC call!");
	return NO;
}
- (BOOL)isReturnInstruction: (uint32_t)anInstruction
{
	// The MIPS back end currently uses a pseudo for returns and so the
	// disassembled instruction is not identifiable as a return.
	if (anInstruction == 0x03e00008)
	{
		return YES;
	}
	MCInst inst;
	if (disassembleInstruction(anInstruction, inst) == MCDisassembler::Success)
	{
		const MCInstrDesc &desc = MipsInsts[inst.getOpcode()];
		return desc.isReturn();
	}
	return NO;
}
+ (void)initialize
{
	InitializeAllTargetInfos();
	InitializeAllTargetMCs();
	InitializeAllAsmParsers();
	InitializeAllDisassemblers();
	//std::string triple("cheri-unknown-freebsd");
	std::string triple("mips64-unknown-freebsd");
	std::string features("");

	std::string Error;
	target = TargetRegistry::lookupTarget(triple, Error);
	if (target == 0)
	{
		NSLog(@"Failed to initialise target: %s\n", Error.c_str());
	}
	mri.reset(target->createMCRegInfo(triple));
	NSAssert(mri.isValid(), @"Failed to create MCRegisterInfo");
	asmInfo.reset(target->createMCAsmInfo(*mri, triple));
	NSAssert(asmInfo.isValid(), @"Failed to create MCAsmInfo");
	sti.reset(target->createMCSubtargetInfo(triple, "", features));
	NSAssert(sti.isValid(), @"Failed to create MCSubtargetInfo");
	mii.reset(target->createMCInstrInfo());
	NSAssert(mii.isValid(), @"Failed to create MCInstrInfo");
	//mia.reset(target->createMCInstrAnalysis(mii.get()));
	mia.reset(new MCInstrAnalysis(mii.get()));
	NSAssert(mia.isValid(), @"Failed to create MCInstrAnalysis");
	disAsm.reset(target->createMCDisassembler(*sti));
	NSAssert(disAsm.isValid(), @"Failed to create MCDisassembler");
	instrPrinter.reset(target->createMCInstPrinter(
        asmInfo->getAssemblerDialect(), *asmInfo, *mii, *mri, *sti));
	NSAssert(instrPrinter.isValid(), @"Failed to create MCInstPrinter");
}
@end
