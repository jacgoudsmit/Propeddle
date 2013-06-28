/*
 * p6502control.c 
 *
 * Control cog for the Propeddle system
 *
 * (C) Copyright 2011-2013 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */


// Issue 60 of the Propeller GCC compiler describes a problem where enum
// values cannot be put into some inline assembler directives as 
// immediate-value arguments.
// The workaround is to use #defines instead of enums, so the preprocessor
// knows the literal values (which is not the case for enums), and they
// can be placed in the code by using the stringize operator.
#define WORKAROUND_ISSUE60

 
/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////


#define INCLUDING // Workaround for SimpleIDE compiling .h files as modules
#include "p6502control.h"


/////////////////////////////////////////////////////////////////////////////
// MACROS
/////////////////////////////////////////////////////////////////////////////


// Delay constants for main loop, in Propeller clock cycles.
// Do not change.
#define DELAY_MAINLOOP_MINDELAY_INIT (95) // Initial loop min duration
#define DELAY_MAINLOOP_MINDELAY (80)  // Subsequent loops min duration


// Macro to turn anything into a string
#define _stringize(x) #x
#define _(x) _stringize(x)


/////////////////////////////////////////////////////////////////////////////
// TYPES
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Modes for internal function
#ifdef WORKAROUND_ISSUE60
#define P6502_MODE_NONE (0)
#define P6502_MODE_RUN  (1)
#define P6502_MODE_LOAD (2)
#define P6502_MODE_INIT (3)
#define W60(x) _(x)
typedef int P6502_MODE;
#else
typedef enum
{
    P6502_MODE_NONE = 0,                // Used internally, do not change
    P6502_MODE_RUN,                     // Run normally
    P6502_MODE_LOAD,                    // Load data from hub to RAM
    P6502_MODE_INIT,                    // Init and reset system
    
}   P6502_MODE;
#define W60(x) "%[" #x "]%"
#endif


/////////////////////////////////////////////////////////////////////////////
// STATIC DATA
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Static constants
//
// It's easier to initialize them this way than as parameters to __asm__
// because there is a hard limit of 30 parameters in GCC. The inline 
// assembler is able to access these as external variables, but their names
// are prefixed with '_' from the assembler's point of view.

// -- single pins --
const _COGMEM unsigned mask_NMI         = pmask(pin_NMI);
const _COGMEM unsigned mask_RES         = pmask(pin_RES);
const _COGMEM unsigned mask_RAMOE       = pmask(pin_RAMOE);
const _COGMEM unsigned mask_RAMWE       = pmask(pin_RAMWE);
const _COGMEM unsigned mask_RW          = pmask(pin_RW);
const _COGMEM unsigned mask_AEN         = pmask(pin_AEN);
const _COGMEM unsigned mask_SLC         = pmask(pin_SLC);
const _COGMEM unsigned mask_CLK0        = pmask(pin_CLK0);

#if pin_CLK0 == pin_PINT
#define mask_PINT mask_CLK0
#define label_PINT "_mask_CLK0"
#else
#warning PINT is not equal to CLK0, this was not tested
const _COGMEM unsigned mask_PINT        = pmask(pin_PINT);
#define label_PINT "_mask_PINT"
#endif

// -- multiple pins --
const _COGMEM unsigned mask_ADDR        = P6502_MASK_ADDR;
const _COGMEM unsigned mask_DATA        = P6502_MASK_DATA;
const _COGMEM unsigned mask_SIGNALS     = P6502_MASK_SIGNALS;
const _COGMEM unsigned mask_RESET       = P6502_MASK_RESET;

// -- all pins --
const _COGMEM unsigned mask_DIR_INIT    = P6502_MASK_DIR_INIT;
const _COGMEM unsigned mask_OUT_INIT    = P6502_MASK_OUT_INIT;
const _COGMEM unsigned mask_OUT_PHI1    = P6502_MASK_OUT_PHI1;

// -- other constants (not I/O)
                                        //  iiiiiiZCRIccccdddddddddsssssssss
const _COGMEM unsigned mux_R            = 0b00000000100000000000000000000000;


//---------------------------------------------------------------------------
// Signals
volatile unsigned Signals = P6502_MASK_SIGNALS;


/////////////////////////////////////////////////////////////////////////////
// CODE
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Control the 6502
//
// This function is used to:
// - Initialize the system
// - Load hub memory to the RAM chip
// - Run the 6502 for normal program execution
//
//
// INIT MODE:
//
// In this mode, the DIRA and OUTA registers are initialized, and the 6502
// is reset. The function generates a few clock pulses until just before
// the reset sequence starts.
//
// The function must be called in this mode at least once before any other
// modes, but the mode can be used again to reset the 6502 later.
// 
//
// RUN MODE:
//
// The function runs the 6502 at the given speed, given in Propeller clock
// cycles per 6502 clock cycle. For example, if the system runs at 80MHz, a
// speed value of 80 runs the 6502 at (80_000_000 / 80) = 1MHz. You can run
// at maximum speed by passing 0.
//
// An optional counter can be used to stop after a predetermined number of
// 6502 cycles. If the counter is set to 0, the function doesn't stop
// generating clock cycles until another cog holds the CLK0 output high
// after this function makes it high and then low. The return value is the
// remaining number of clocks which will be 0 if the function ran to 
// completion, or nonzero if a nonzero count was specified and another cog
// held the clock high when this function made it low.
//
// During execution, the code updates the signals to the 6502 from the 
// Signals global variable during each 6502 clock cycle. Other cogs may 
// change the signal bits in the global, to control the 6502 signal bits: 
// NMI, IRQ, RDY, RESET, SO. The other bits should be left zero.
//
// Starting the main loop in a cog in Run mode is enough to let the 6502
// execute code from memory without the need for any other cogs. The RAM
// chip is activated (for read or write, depending on the R/!W output of the
// 6502), for each clock cycle. Of course if the entire memory area is mapped
// to RAM, there is no input or output. So if you want to turn the computer
// into something useful, you'll probably want to run other cogs that disable
// the RAM (by making their RAMWE and RAMOE output pins high during Phi2,
// which overrides the RAMWE and RAMOE outputs from this cog), and that
// communicate with the 6502 in some other way during Phi2.
//
// LOAD MODE:
//
//
// The function can also be used to copy data from the hub to the RAM chip.
// This works by generating an NMI (Non-Maskable Interrupt) on the 6502, and
// feeding dummy-instructions to it while we copy the data to the RAM behind
// its back. This is how it works:
//
// During the first half of the clock cycle (which we call Phi1), the 6502
// doesn't use the data bus, but it does put the current address on the
// address bus, which is directly connected to the RAM chip. So during Phi1,
// the Propeller can put data on the data bus and activate the RAMWE pin
// to store it into the RAM. Then, during Phi2, when the 6502 pays attention
// to the databus, the Propeller can put a dummy instruction there, so that
// the Program Counter register keeps increasing until it reaches the end of
// the memory area that we want to write, while no other registers are 
// modified.
//
// In Dennis Ferron's Prop-6502 project on which Propeddle was based, he used
// the NOP instruction to accomplish this. The NOP (No OPeration) instruction
// is one byte and takes two cycles, so the address only advances every other
// clock cycle. To make the process more efficient, we use the CMP (Compare,
// Immediate) instruction instead. It's two bytes and takes two cycles (the
// 6502 doesn't have any instructions that take less than 2 cycles). Unlike
// NOP, it does change the state of the 6502: it updates the flags. However,
// because the entire operation is an interrupt, the flags have been saved
// on the stack and will be restored at the end of the operation when we feed
// an RTI (Return From Interrupt) to the 6502.
//
// The 6502 may still be busy executing an instruction when we generate the
// NMI. It won't start processing the NMI until the end of the instruction.
// Then it will push the current Program Counter register and the flags onto
// the stack, before it retrieves the NMI vector (which the Propeller 
// provides). When the 6502 processes the RTI instruction, it reads the flags
// and the return address off the stack before it continues where it left
// off. All these operations are handled as normal clock cycles, so they
// should be handled as usual. That's why the Load code is mixed into the
// normal control loop: this way all the timings match with those of the
// normal execution cycles. Also, all cogs that handle virtual memory should
// run while the Load is active. Note however that other cogs should not
// interfere with the actual Load operation. To prevent this, don't attempt 
// to run a Load operation on memory that's normally virtualized by another
// cog.
//
// There are a few possible snags about the way Load Mode is implemented.
// First of all, the system is effectively stopped for a significant amount
// of time. The 6502 can't do anything else so this is not really the same
// as Direct Memory Access. NMI has a higher priority than IRQ, so it's
// possible that the Load happens while the 6502 is processing an IRQ, and
// the IRQ may not be processed correctly if it takes longer than expected.
// Also, an IRQ from other hardware will not be processed while the Load is
// in progress, because interrupts are disabled while the NMI is processed.
// Finally, unless another cog is started to prevent it, the Load operation
// uses the stack bytes that are normally involved with an NMI; if there
// isn't enough space on the stack, the operation will fail silently.
// (NOTE, I may not even have thought of all the possible problems).
//
// All these problems mentioned above are minor, and can be prevented by
// making sure that there are no cogs that are virtualizing any memory
// locations that overlap with the memory that we're about to write to.
// There is however a potentially major problem: Let's say another cog is
// used to virtualize a memory area that overlaps with what you want to 
// write to (e.g. the vectors at the top of memory), you should stop that
// cog before starting this function. However if the 6502 is currently
// reading from, or writing to that area as part of the last instruction
// before it starts processing the NMI, the instruction will not be processed
// correctly. We expect that in most cases, the Load functionality will be
// used only when the system is initializing, so even when an instruction
// has the wrong effect it's probably not going to be a big deal. In the
// future we may add some functionality here that makes it possible to 
// keep all supplementary cogs running, regardless of which addresses they
// cover; we may automatically disable or shut down those other cogs at the
// exact clock cycle when the 6502 starts executing dummy instructions. For
// now, we will see it as a known problem that's unfixed for the time being.
// 
//
// REMARKS:
//
// The main loop was meticulously constructed to be able to generate one
// 6502 clock cycle per 80 Propeller clock cycles, and get all the timings
// right. There are also some delays in the code (in the form of NOP
// instructions) to compensate for propagation delays and setup times,
// based on the Western Design Center 65C02S data sheet, and datasheets for
// the 74HCxxx chips that are used in Propeddle Rev. 7 and up.
// This results in the following truth table:
// - If the Propeller runs at a frequency less than 80MHz, the 6502 can only
//   run at speeds that are slower than 1MHz. Everything should function
//   correctly but this has not been tested.
// - If the Propeller runs at a frequency of at least 80MHz and at most
//   100MHz, the maximum speed of the 6502 is 1/80th of the Propeller speed
//   (so the 6502 can run at up to 1MHz to 1.25MHz). Functionality was
//   tested at 80MHz and 100MHz (using a 5MHz and 6.25MHz crystal).
// - If the Propeller runs faster than 100MHz, the NOP delays may become
//   too short to guarantee correct operation (but the Propeller is already
//   out of spec at this frequency). This has not been tested.
//
// It's important to keep in mind that other cogs may depend on the timing
// of this cog, too; for example, while this cog doesn't actually read the
// address bus, it enables the address bus at a certain point in time, and
// other cogs can only read it during that short time. The other cogs
// (or even other Propellers!) may monitor the CLK0, AEN and SLC outputs to
// synchronize with this cog. This is another reason not to change the code
// in this function.
//
// Timings in comments are Propeller clock cycles; t=0 corresponds to the
// start of Phi1 (CLK0 changes from high to low). t0 represents timing on
// the first iteration, tn represents timing on subsequent iterations. All
// timings are based on a minimum duration for the waitcnt instruction.
//
// The first iteration of the loop may take longer than subsequent
// iterations because there is a hub instruction in the loop which may take
// longer during the first iteration than during the following iterations.
// However, after executing the loop once, all subsequent executions take
// the same amount of time: 80 Propeller clock cycles. A timing analysis
// document is available to prove this.
_NATIVE
unsigned                                // Returns number of cycles remaining
static p6502__control(
    P6502_MODE mode,                    // Mode
    unsigned clockcount,                // Number of clock cycles to execute
    unsigned cycletime,                 // Clock cycle time
    unsigned startaddr,                 // 6502 address bus value for command
    unsigned hubaddr,                   // Hub address for command
    unsigned hubcount)                  // Number of hub bytes for command
{
    __asm__ (
                    // This directive ensures that the assembler uses cog 
                    // addresses instead of byte addresses.
"\n                 .pasm"

                    // Make sure we don't break the speed limit
"\n                 min     %[cycletime], %[iDELAY_MIN]"

                    // Initialize locals from globals
"\n                 rdlong  signals,    %[psignals]"

                    // Initialize the loop depending on mode
                    // Test for Run mode first, this is the most common case
"\n                 cmp     %[mode],    %[iP6502_MODE_RUN] wz"
"\n     if_z        jmp     #Run_Init"

                    // Fall through for non-RUN mode initialization
                    
//---------------------------------------------------------------------------
// Initialization for non-Run modes
//---------------------------------------------------------------------------

                    // When running in a mode other than RUN, it's necessary
                    // patch the main loop in a couple of places. This
                    // patching is completely controlled by tables which 
                    // makes the following code pretty complicated (with
                    // structs and pointers and self-modifying code) but 
                    // makes it easier to add and modify patches to the main
                    // loop.
                    
                    // Init pointer to mode table
                    // { r8 = &InitModeTable[0]; }
"\n                 mov     r8,         #InitModeTable"

                    // Initialization loop starts here
"\nInitLoop"
                    // Copy mode from source pointer
                    // { if ((r10 = *r8++) == P6502_MODE_NONE) goto EndMainLoop; }
"\n                 movs    InitGetMode, r8"            // Get mode from table
"\n                 add     r8,         #1"
"\nInitGetMode      mov     r10,        (0)"            // Source = mode from table
"\n                 cmp     r10,        %[iP6502_MODE_NONE] wz"
"\n     if_z        jmp     #EndMainLoop"               // Mode not found

                    // Set Z flag depending on whether mode matches
                    // { Z = (r10 == mode); }
"\n                 cmp     r10,        %[mode] wz"      // Check if mode matches

                    // Init pointer to patch table
                    // { r9 = &InitPatchTable[0]; }
"\n                 mov     r9,         #InitPatchTable"

                    // At this point, r8 points to the first patch address
                    // in the mode table and r9 points to the first group in
                    // the patch table.
                    
                    // Patch loop starts here
"\nPatchLoop"
                    // Check for end of the patch table
                    // { C = borrow((? = *r9++) - 1); }
"\n                 movd    PatchCheckEnd, r9"          // Get table entry to check
"\n                 movs    PatchBackupPtr, r9"         // Get instruction to patch
"\n                 add     r9,         #1"
"\nPatchCheckEnd"
"\n                 sub     (0),        #1 wc,nr"       // set C flag if address was 0

                    // If C is set, we're at the end of the patch table, and
                    // r8 points at the location for the rest of the 
                    // initialization code. If this is the case (and ONLY if
                    // it is the case) move the pointer ahead.
                    // { if (C) { if (Z) goto *r8++; } else r8++; }
"\n     if_c_and_z  movs    PatchJmpInit, r8"           // Get init code jmp location
"\n     if_c        add     r8,         #1"             // Only bump ptr if at end of group

                    // If both Z and C are set, we're at the end of the patch
                    // table entries, and the mode matched, so we need to
                    // jump to the init code for this mode.
"\nPatchJmpInit"
"\n     if_c_and_z  jmp     (0)"                       // Jump to init code

                    // If we're at the end of the patch table entries,
                    // process the next group of mode table entries
                    // { if (C) goto InitLoop; }
"\n     if_c        jmp     #InitLoop"                  // We're done and no match

                    // Resolve pointer
                    // { *?; }
"\nPatchBackupPtr"
"\n                 movs    PatchBackup, (0)"           // Get backup source pointer

                    // Backup original instruction into patch table
                    // { if (Z) { *r9++ = *?; } }
"\n                 movd    PatchBackup, r9"            // Get backup destination
"\n                 add     r9,         #1"
"\nPatchBackup"
"\n     if_z        mov     (0),        (0)"            // Backup from main loop to backup in patch tbl

                    // If mode matches, patch the main loop from the mode table
                    // { *? = *r8++; }
"\n                 movd    PatchDoPatch, PatchBackup"  // Use source of backup ins as target for patch
"\n                 movs    PatchDoPatch, r8"           // Get instruction location
"\n                 add     r8,         #1"
"\nPatchDoPatch"
"\n     if_z        mov     (0),        (0)"            // Patch main loop from patched ins in patch tbl

                    // At this point, the destination pointer is at the start
                    // of the next table entry
"\n                 jmp     #PatchLoop"


//---------------------------------------------------------------------------
// Restore main loop patches
//---------------------------------------------------------------------------

                    // Every non-RUN mode should jump here (eventually) from
                    // their end-of-loop code, so the patched locations in
                    // the main loop are restored to their backup values.
                    // After this happens, execution leaves the function.
                    // { r9 = &InitPatchTable[0]; }
"\nRestore"
"\n                 mov     r9,         #InitPatchTable"

                    // Restore loop starts here
                    // { ? = *r9++; }
"\nRestoreLoop"
"\n                 movd    RestoreCheckEnd, r9"        // Get address to check for 0
"\n                 movs    RestoreSetPtr, r9"          // Get address in main loop
"\n                 add     r8,         #1"
                    
                    // When done, jump to the restored instruction at the
                    // end of the main loop
                    // { if (? == 0) { goto EndAltIns; } }
"\nRestoreCheckEnd"
"\n                 cmp     (0),        #0 wz"          // Check for end of patch table
"\n     if_z        jmp     #EndAltIns"                 // Leave func by jumping to restored ins

                    // Resolve pointer
                    // { *?; }
"\nRestoreSetPtr"
"\n                 movd    RestoreDoRestore, (0)"      // Resolve pointer again


                    // Restore a longword
                    // { *? = *r9++; goto RestoreLoop; }
"\n                 movs    RestoreDoRestore, r9"       // Get address of backup
"\n                 add     r8,         #1"
"\nRestoreDoRestore"
"\n                 mov     (0),        (0)"            // Restore the instruction    
"\n                 jmp     #RestoreLoop"

                    
//---------------------------------------------------------------------------
// Initialization tables
//---------------------------------------------------------------------------

                    //-------------------------------------------------------
                    // Patch table
                    //
                    // This table describes each instruction in the main loop
                    // that needs to be patched. It also reserves space for
                    // a backup of the original instruction so it can be 
                    // restored before the function returns. The instructions
                    // to be stored in the main loop are retrieved from the 
                    // mode table below.
                    //
                    // Each group in this table consists of the following:
                    // - Pointer of address to patch
                    // - Backup of original instruction
                    //
                    // The table ends with a location that's set to 0.
"\nInitPatchTable"
"\n                 long    Phi1AltIns"                 // Location of Phi1 alternate instruction
"\nPhi1Backup       long    0"                          // Replaced by backup of Phi1 original ins

"\n                 long    Phi2AltIns"                 // Location of Phi2 alternate instruction
"\nPhi2Backup       long    0"                          // Replaced by backup of Phi2 original ins

"\n                 long    LoopIns"                    // Location of DJNZ instruction
"\nLoopBackup       long    0"                          // Replaced by backup of DJNZ original ins

"\n                 long    EndAltIns"                  // Location of End-of-loop alternate ins
"\nEndBackup        long    0"                          // Replaced by backup of End-of-loop org ins

                    // Add more patch location information here
                    
                    // End of patch table
"\n                 long    0"


                    //-------------------------------------------------------
                    // Mode table
                    //
                    // Table with source values to store into the substituted
                    // instructions as defined by the patch table above,
                    // based on the mode.
                    //
                    // Each entry consists of the following data:
                    // - Mode for this entry
                    // - Instructions to store in the main loop: one for each
                    //   entry in the patch table.
                    //   (The number of instructions to store in the main
                    //   loop depends on the number of groups in the Patch
                    //   table)
                    // - Address of additional initialization code, to run
                    //   before entering the main loop
                    //
                    // The table ends with a mode entry for mode NONE.
"\nInitModeTable"       
"\n                 long    " W60(P6502_MODE_LOAD)      // Following data is for Load mode
"\n                 jmp     #Load_Phi1"                 // Phi1 for Load mode
"\n                 jmp     #Load_Phi2"                 // Phi2 for Load mode
"\n                 nop"                                // DJNZ for Load mode
"\n                 jmp     #Restore"                   // End of Load mode
"\n                 long    Load_Init"                  // Init of Load mode

"\n                 long    " W60(P6502_MODE_INIT)      // Following data is for Init mode
"\n                 jmp     #Init_Phi1"                 // Phi1 for Init mode
"\n                 jmp     #Init_Phi2"                 // Phi2 for Init mode
"\n                 djnz    %[clockcount], #MainLoop"   // DJNZ for Init mode
"\n                 jmp     #Restore"                   // End of Init mode
"\n                 long    Init_Init"                  // Init of Init mode

                    // End of mode table
"\n                 long    " W60(P6502_MODE_NONE)


//---------------------------------------------------------------------------
// Other data
//---------------------------------------------------------------------------


                    //-------------------------------------------------------
                    // Working data
"\nclock            long    0"                          // Used in WAITCNT
"\nsignals          long    0"                          // Local version of Signals in hub
"\naddr             long    0"                          // 6502 address bus
"\nexpected         long    0"                          // Expected address
"\nfeed             long    0"                          // Byte to feed to the 6502


                    //-------------------------------------------------------
                    // Constants
"\nVector_NMI       long    0xFFFA"


//---------------------------------------------------------------------------
// Initialization code for each mode
//---------------------------------------------------------------------------


                    //-------------------------------------------------------
                    // Init mode Initialization
"\nInit_Init"
"\n                 mov     OUTA,       _mask_OUT_INIT"
"\n                 mov     DIRA,       _mask_DIR_INIT"

                    // Turn off all signals, but turn RESET on
                    // The global variable is ignored and will not be updated
                    // until we're done.
"\n                 mov     signals,    _mask_RESET"

                    // Reset needs to be active for 2 cycles and it takes 6
                    // cycles to return to normal, so we leave after 8 
                    // cycles.
"\n                 mov     %[clockcount], #8"

                    // Continue initialization as if in run mode
"\n                 jmp     #Run_Init"


                    //-------------------------------------------------------
                    // Load mode initialization
"\nLoad_Init"
                    // Leave if there's nothing to do
"\n                 cmp     %[hubcount], #0 wz"
"\n     if_z        jmp     #EndMainLoop"

                    // Make sure the number of clocks is not limited
"\n                 mov     %[clockcount], #0"

                    // Activate NMI during first cycle
                    // Note, the signals don't get updated from the hub
                    // during load mode.
"\n                 andn    signals,    _mask_NMI"

                    // Initialize state machine
"\n                 mov     expected,   Vector_NMI"
"\n                 movs    LoadStateJmp, #state_VEC1"

                    // Fall through to Run mode init
                    
                    //-------------------------------------------------------
                    // Run mode initialization
"\nRun_Init"
                    // The clock variable is used in the WAITCNT
                    // instructions.
                    // Initialize it to the cycle time, but minimize
                    // this by the minimum time for the first cycle,
                    // which may need to take longer than all subsequent
                    // cycles because we need to synchronize with the hub.
                    // Note, CNT is added just before jumping into the
                    // loop.
"\n                 mov     clock,      %[cycletime]"
"\n                 min     clock,      %[iDELAY_MIN_INIT]"

                    // Depending on whether the count is 0, enable or
                    // disable the check at the end of the loop.
                    // In other words, if z=1 here, modify the DJNZ
                    // instructions so that the result is never written.
"\n                 cmp     %[clockcount], #0 wz"
"\n                 muxnz   LoopIns,    _mux_R"
"\n                 muxnz   LoopIns2,   _mux_R"

                    // Add the system clock to the local clock. This
                    // should be done just before jumping into the loop.
"\n                 add     clock,      CNT"
"\n                 jmp     #StartMainLoop"


//---------------------------------------------------------------------------
// Load mode
//---------------------------------------------------------------------------


                    //-------------------------------------------------------
                    // Phi1 code for Load Mode state machine
                    
                    //.......................................................
                    // Jump to current state's code if address matches
                    //
                    // Filter the address from the INA value that we got at
                    // the start of Phi1 and check if it matches the addres
                    // we're expecting.
                    // If it does, jump to the current state label which
                    // knows what to do for the current state.
"\nLoad_Phi1"
"\n                 and     addr,       _mask_ADDR"
"\n                 cmp     addr,       expected wz"

                    // If address matches and the 6502 is reading,
                    // jump to the current state label.
                    //
                    // If the 6502 is writing or the address doesn't match,
                    // handle the cycle normally. At this point, the
                    // carry flag is still set if R/!W is high (i.e. the
                    // 6502 is reading).
                    //
                    // The destination is modified during execution
"\nLoadStateJmp"
"\n     if_z_and_c  jmp     #(0)"                       // Jump if 6502 is reading expected address

                    // Fall through if not a match, or if writing

                    //.......................................................
                    // Return from Phi1, prepare to let the 6502 access RAM
                    
                    // The current address doesn't match, so do a normal RAM
                    // write during Phi2
"\nLoadPhi1RAMRet   movs    Phi2AltIns, #LoadPhi2Normal"
"\n                 jmp     #Phi1Continue"

                    //.......................................................
                    // Return from Phi1 and prepare to feed a byte to 6502
"\nLoadPhi1FeedRet"
"\n                 movs    Phi2AltIns, #LoadPhi2Feed"
"\n                 jmp     #Phi1Continue"

                    //.......................................................
                    // Detect stack access at end of Load mode
                    //
                    // This code is used when we're done copying the hub
                    // memory to the RAM. At this point we're feeding RTI
                    // instructions to the 6502 and we're waiting for the
                    // 6502 to pick it up (this should happen within one
                    // or two cycles). The address matching code above 
                    // doesn't work, because we have to check for _any_
                    // address in the 6502's stack area ($0100-$01FF), and
                    // it has to keep feeding RTI's _until_ (not _while_)
                    // the address matches.
"\nLoadPhi1End"
                    // Test if the current address is in the stack area
"\n                 shr     addr,       #8"
"\n                 and     addr,       #0xFF"

                    // Keep feeding RTI until the 6502 picks up data from 
                    // the stack.
                    // This should only happen once, at the most.
"\n                 cmp     addr,       #1 wz"
"\n     if_nz       jmp     #state_RTI"

                    // Fall through if 6502 is accessing the stack
                    
                    //.......................................................
                    // Phi1 cleanup on the way out of Load mode
                    //
                    // We're in the middle of Phi1 at this point, so we have
                    // to jump back to the main loop to finish the cycle.
                    //
                    // Before that, we have to clean up the main loop: we
                    // restore it to the backed-up instruction to make it
                    // behave as in Run mode.
                    //
                    // Also, we need to stage the data in such a way that
                    // the main loop exits at the end of the cycle.
"\nLoadPhi1Done"
                    // Clear NMI on the way out
"\n                 or      signals,    _mask_NMI"

                    // Restore Phi2 instruction backup and jump back to the
                    // main loop.
                    //
                    // There is still a NOP stored at the end of the loop
                    // (placed there during init) which will make execution
                    // drop out of the loop. After that, the restore code
                    // is executed.
"\n                 mov     Phi2AltIns, Phi2Backup"
"\n                 jmp     #Phi1Continue"

                    //.......................................................
                    // State VEC1
                    //
                    // The 6502 is picking up the low byte of the NMI vector.
"\nstate_VEC1"
                    // Next, we wait for the high part of the NMI vector
"\n                 add     expected,   #1"
"\n                 movs    LoadStateJmp, #state_VEC2"

                    // Feed the low byte of the starting address to the 6502
"\n                 mov     feed,       %[startaddr]"
"\n                 jmp     #LoadPhi1FeedRet"

                    //.......................................................
                    // State VEC2
                    //
                    // The 6502 is picking up the high byte of the NMI 
                    // vector.
"\nstate_VEC2"
                    // Next expected address is the starting address of our
                    // memory area
"\n                 mov     expected,   %[startaddr]"
"\n                 movs    LoadStateJmp, #state_TARGET"

                    // Feed the high byte of the starting address to the 6502
"\n                 shr     feed,       #8"             // Go to high byte
"\n                 jmp     #LoadPhi1FeedRet"

                    //.......................................................
                    // State TARGET
                    //
                    // The 6502 is executing instructions in the target area
                    // We feed it with dummy instructions until we're done.
                    // But during Phi1 (i.e. here) we store data from the
                    // hub into the RAM.
"\nstate_TARGET"
                    // Start by getting a byte from the hub, and storing it
                    // in the RAM.
"\n                 rdbyte  feed,       %[hubaddr]"     // Get byte from hub
"\n                 or      OUTA,       feed"           // Put byte on output
"\n                 or      DIRA,       _mask_DATA"     // Activate data bus
"\n                 andn    OUTA,       _mask_RAMWE"    // Activate RAM

                    // While the RAM is active, we finish processing
                    // This takes much longer than required, but that's okay
"\n                 add     %[hubaddr],    #1"          // Update address
"\n                 add     expected,   #1"             

                    // Feed a CMP Immediate instruction to the 6502
"\n                 mov     feed,       %[iINS6502_CMPIMM]"

                    // Decrement the copy counter.
                    // When we're done, switch the state
"\n                 sub     %[hubcount], #1 wz"
"\n     if_z        movs    LoadStateJmp, #state_RTI"   // Otherwise state remains unchanged

                    // Turn the RAM off again, and disable the databus 
                    // output.
                    // Remove the data, it needs to be replaced with the
                    // dummy instruction during Phi2.
"\n                 or      OUTA,       _mask_RAMWE"    // Disable RAM
"\n                 andn    DIRA,       _mask_DATA"     // Disable outputs
"\n                 andn    OUTA,       _mask_DATA"     // Remove data
"\n                 jmp     #LoadPhi1FeedRet"

                    //.......................................................
                    // State RTI
                    //
                    // We're done filling the target area.
"\nstate_RTI"
                    // We're going to feed an RTI instruction to the 6502, 
                    // but it's possible that it's not ready for an 
                    // instruction yet: it might be in the middle of the last
                    // dummy instruction, so we keep feeding RTI 
                    // instructions until the 6502 reads data from the stack.
"\n                 movs    Phi1AltIns, #LoadPhi1End"

                    // Feed RTI instruction to the 6502
"\n                 mov     feed,       %[iINS6502_RTI]"
"\n                 jmp     #LoadPhi1FeedRet"


                    //-------------------------------------------------------
                    // Phi2 code for Load Mode state machine
                    
                    //.......................................................
                    // Normal RAM access
                    //
                    // This just makes the cycle behave normally: Enable the
                    // RAM depending on the RW pin, so the 6502 reads from,
                    // or writes to the RAM as normal.
                    // If other cogs want to interfere, they can do so as
                    // usual.
                    //
                    // The code here is almost the same as the Phi2 code for
                    // the normal Run mode loop, except we ignore the counter
                    // and we don't wait for the timer.
"\nLoad_Phi2"
"\nInit_Phi2"
"\nLoadPhi2Normal"
                    // The Run mode Phi1 code sets the C flag depending on
                    // the R/W pin but the flag may have been trashed by the
                    // patched Phi1 code so we test it again here.
"\n                 test    _mask_RW,   INA wc"

                    // Because of the re-test above, and the jump to here 
                    // from the loop, the instructions that enable the RAM
                    // are executed slightly later (from the start of Phi2)
                    // than normal, so that other cogs who want to disable
                    // the RAM can do so at their normal pace.
"\n     if_nc       andn    OUTA,       _mask_RAMWE"
"\n     if_c        andn    OUTA,       _mask_RAMOE"

"\n                 nop"                                // Wait for settle times
"\n                 or      OUTA,       _mask_RAMWE"

                    // Fall through to start Phi1
                    
                    //.......................................................
                    // Start Phi1 at end of Phi2
"\nLoadStartPhi1"
"\n                 andn    OUTA,       _mask_CLK0"

                    // Test for pseudo-interrupt. If it happens, go to the
                    // end of the loop where the patches will be restored.
                    // Note, this may leave the system in an unstable state
                    // because the download wasn't finished yet.
"\nLoadPINTLoop"
"\n                 test    " label_PINT ", INA wc"
"\n     if_c        jmp     #EndMainLoop"

                    // Reset DIRA
                    // This is only really necessary when we're feeding data
                    // to the 6502 but it doesn't hurt.
                    // The data bus in OUTA will get reset in the main loop.
"\n                 andn    DIRA,       _mask_DATA"

                    // If the counter is in use, the NR is changed to R
"\nLoopIns2"
"\n                 djnz    %[clockcount], #Phi1Start nr"
"\n                 jmp     #EndMainLoop"

                    //.......................................................
                    // Load mode: Feed a byte to the 6502
                    //
                    // Note: up to a 16 bit value can be stored in the feed
                    // data; bits 8-15 are ignored.
                    // The extra bits are cleared at the start of Phi1.
"\nLoadPhi2Feed"
"\n                 or      OUTA,       feed"
"\n                 or      DIRA,       _mask_DATA"
"\n                 jmp     #LoadStartPhi1"


//---------------------------------------------------------------------------
// Init mode
//---------------------------------------------------------------------------


                    //-------------------------------------------------------
                    // Phi1 code for Init mode
"\nInit_Phi1"
                    // Deactivate reset after 2 cycles (8-2=6)
"\n                 cmp     %[clockcount], #6 wz"
"\n     if_z        or      signals,    _mask_RES"

"\n                 jmp     #Phi1Continue"


//---------------------------------------------------------------------------
// Main loop
//---------------------------------------------------------------------------


                    // This is NOT the entry point for the main loop, but
                    // rather the point at the end of Phi2 just before we
                    // wait for the clock. It makes sense to put the DJNZ
                    // just before the WAITCNT instruction and enter the
                    // loop not at this point, but further down.
"\nMainLoop"
                    // Wait for the end of the requested cycle time
                    // Initialization may change the instruction at the end
                    // of the loop so that this instruction is skipped.
//t0=67..82
//tn=67
"\n                 waitcnt clock,      %[cycletime]"

                    // Turn off the Write Enable to the RAM
                    // In other 6502 systems, the RAM is usually disabled
                    // BECAUSE the clock goes low, but because we have
                    // control over the clock but we don't have control
                    // over how long the 6502 will hold the address and data
                    // that is written to the RAM, we have to disable the
                    // RAMWE line before switching the clock, not after.
//t0=72..87
//tn=72
"\n                 or      OUTA,       _mask_RAMWE"

                    //-------------------------------------------------------
                    // MAIN LOOP ENTRY POINT
                    //
                    // The function enters and leaves with the CLK0 output
                    // set to HIGH, so that older 6502 processors can be
                    // stopped without worrying about registers losing their
                    // values (the WDC 65C02S can be stopped at any time).

                    // Set the clock LOW
                    // This starts the PHI1 part of the clock cycle, unless
                    // one of the other cogs makes the clock high too
                    // (pseudo-interrupt).
                    // We will check for that next.
//t0=76..91
//tn=76
"\nStartMainLoop"
"\n                 andn    OUTA,       _mask_CLK0"

                    // Check if another cog is keeping the clock in the high
                    // state, indicating that they want us to stop running.
                    // If that is the case, we break out of the loop here.
                    // Because the outputs are retained between our change of
                    // the CLK0 output and here, it's possible to restart the
                    // loop without need to worry about the 6502.
                    // The other cogs that depend on the timing of this cog
                    // can also safely keep running: they are just as unaware
                    // of the fact that we couldn't change the CLK0 output to
                    // low as the 6502 is.
//t0=0
//tn=0
"\n                 test    " label_PINT ", INA wc"
"\n     if_c        jmp     #EndMainLoop"

                    // Initialize all output signals:
                    // - The RAM is disabled; this has to happen a short time
                    //   after setting the clock low, so that the 6502 has
                    //   time to read the data bus. Normally it would be
                    //   sufficient to turn the RAM off at the same time as
                    //   switching the clock, however this is impossible
                    //   because we can't set one pin low and another pin 
                    //   high at the same time unless we use XOR and that's
                    //   not possible because we can't be sure of the state
                    //   of the RAM pins at this point.
                    // - The signals in the OUTA register are initialized to
                    //   0 so it's possible to OR the signals from the hub in
                    //   there.
                    // - The clock for the signal flipflops (SLC) is reset so
                    //   that all it takes to get them to the 6502 again is
                    //   to turn SLC on again.
                    // - The address buffers are enabled so other cogs can
                    //   read the address from P0..P15
//t0=8
//tn=8
"\nPhi1Start"                                           // Load mode jumps here
"\n                 mov     OUTA,       _mask_OUT_PHI1"

                    // It takes a little while before the address can be read
                    // reliably because of setup time and propagation delays.
                    // Also we want to give the other cogs some time to pick
                    // up the address, so we check the read/write output of
                    // the 6502 here, and then wait for one instruction time.
//t0=12
//tn=12
"\n                 mov     addr,       INA"        // Value only used in Load mode
"\n                 test    addr,       _mask_RW wc" // c=1 read, c=0 write

                    // Turn the address buffers off again
//t0=20
//tn=20
"\n                 or      OUTA,       _mask_AEN"

                    // Put the signals on the flip-flops on P8..P15. They
                    // need a little time to settle and we also want to give
                    // other cogs the opportunity to override them so there's
                    // some extra delay in there.
//t0=24
//tn=24                    
"\n                 or      OUTA,       signals"
"\n                 or      DIRA,       _mask_SIGNALS"


                    // In Load mode, a CALL is placed here to check the
                    // current address of the 6502 and enable the RAM if
                    // necessary
//t0=32
//tn=32                    
"\nPhi1AltIns"
"\n                 nop"                // Other cogs write signal pins here

                    // In non-Run modes, execution continues here
"\nPhi1Continue"

                    // Clock the flip-flops to send the signals to the 6502.
//t0=36
//tn=36
"\n                 or      OUTA,       _mask_SLC"


                    //-------------------------------------------------------
                    // Phi2
                    
                    
                    // Set the clock HIGH
                    // This starts the PHI2 part of the clock cycle.
                    // Note: it's possible to combine this instruction with
                    // the previous one, but the SO signal is picked up by
                    // the 6502 at the start of PHI2 (the other signals are
                    // picked up later) so by clocking the flipflops before
                    // switching CLK0, we guarantee that the delay for all
                    // signals is minimal.
//t0=40
//tn=40
"\n                 or      OUTA,       _mask_CLK0"

                    // Remove the signals from P8..P15
                    // They are still set in OUTA but they will be cleared
                    // from there at the beginning of PHI1.
                    // Pins P8..P15 aren't used during PHI2, this is
                    // reserved for future expansion.
//t0=44
//tn=44
"\n                 andn    DIRA,       _mask_SIGNALS"

                    // Get the signals from the hub
                    // The signals must be clean, i.e. no non-signal bits
                    // should be set.
                    // 
                    // In Load mode, the following instruction is replaced
                    // by a JMP that finishes Phi2. Execution doesn't come
                    // back here in Load Mode.
//t0=48
//tn=48
"\nPhi2AltIns"
"\n                 rdlong  signals,    %[psignals]"

                    // Enable the RAM chip, either for write or for read,
                    // depending on whether the 6502 is in read or write
                    // mode. By now the other cogs should have had plenty
                    // of time to check the address, and possibly override
                    // the RAM outputs (i.e. turn them off) and take
                    // their own actions, such as redirecting to/from the
                    // hub or making sure the RAM cannot be overwritten.
//t0=55..62
//tn=55
"\n     if_nc       andn    OUTA,       _mask_RAMWE"
"\n     if_c        andn    OUTA,       _mask_RAMOE"

                    // We reached the end of the loop.
                    // If we're supposed to execute a limited number of
                    // instructions, the counter is decreased here and we
                    // leave the loop when it reaches zero.
                    // If we run without limitation, the initialization
                    // code changes the instruction so it doesn't store
                    // the result (NR), so this loops forever.
//t0=59..66
//tn=59
"\nLoopIns"
"\n                 djnz    %[clockcount], #MainLoop"


//===========================================================================
    
                    // We dropped out of the loop
                    // Make sure the last cycle's duration is the same
                    // as all other cycles
"\n                 waitcnt clock,      %[cycletime]"
"\nEndMainLoop"
                    // Make sure the CLK0 output is high, so that we leave
                    // in a state of PHI2
"\n                 or      OUTA,       _mask_CLK0"

                    // The instruction at the end may get replaced by a
                    // jmp to the restore code which cleans up the patched
                    // code. The restore code jumps back to here afterwards.
"\nEndAltIns"
:
    // OUTPUTS
    [clockcount]            "+rC"       (clockcount)
:
    // INPUTS
    
    // Parameters
    //output+input [counter]               "rC"        (counter),
    [mode]                  "rC"        (mode),
    [cycletime]             "rC"        (cycletime),
    [startaddr]             "rC"        (startaddr),
    [hubaddr]               "rC"        (hubaddr),
    [hubcount]              "rC"        (hubcount),

    // Globals
    [psignals]              "rC"        (&Signals),

    // Constants that can be implemented as immediates (must be 9 bits or less)
    [iDELAY_MIN]            "i"         (DELAY_MAINLOOP_MINDELAY),
    [iDELAY_MIN_INIT]       "i"         (DELAY_MAINLOOP_MINDELAY_INIT),
    [iP6502_MODE_NONE]      "i"         (P6502_MODE_NONE),
    [iP6502_MODE_RUN]       "i"         (P6502_MODE_RUN),    
    [iP6502_MODE_LOAD]      "i"         (P6502_MODE_LOAD),
    [iP6502_MODE_INIT]      "i"         (P6502_MODE_INIT),
    [iINS6502_CMPIMM]       "i"         (0xC9),
    [iINS6502_RTI]          "i"         (0x40)
:
    "r8",
    "r9",
    "r10"
    );

    return clockcount;
}


//---------------------------------------------------------------------------
// Initialize the system
void
_NATIVE p6502control_Init(void)
{
    (void)p6502__control(
      P6502_MODE_INIT,                  // Init mode
      0,                                // Clock count irrelevant
      0,                                // Cycle time irrelevant
      0,                                // Start address irrelevant
      0,                                // Hub address irrelevant
      0);                               // Hub length irrelevant
}


//---------------------------------------------------------------------------
// Load data
unsigned                                // Returns 0=success, other=interrupt
_NATIVE P6502control_Load(
    void *pSrc,                         // Source hub address
    unsigned short pTarget,             // Address in 6502 space
    size_t size)                        // Length in bytes
{
    return p6502__control(
      P6502_MODE_LOAD,                  // Load mode
      0,                                // Clock count irrelevant
      0,                                // Cycle time irrelevant
      pTarget,                          // 6502 address
      (unsigned)pSrc,                   // Hub address
      size);                            // Size in bytes
}  
  
  
//---------------------------------------------------------------------------
// Run
unsigned                                // Returns 0=done, other=interrupt
_NATIVE p6502control_Run(
    unsigned nClockCount,               // Number of clock cycles, 0=infinite
    unsigned nCycleTime)                // Num Prop cycles per 6502 cycles
{
    return p6502__control(
        P6502_MODE_RUN,                 // Run mode
        nClockCount,                    // Clock count
        nCycleTime,                     // Cycle time
        0,                              // 6502 address irrelevant
        0,                              // Hub address irrelevant
        0);                             // Length irrelevant
}


/////////////////////////////////////////////////////////////////////////////
// TERMS OF USE: MIT LICENSE
/////////////////////////////////////////////////////////////////////////////


/* Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
 
 
/////////////////////////////////////////////////////////////////////////////
// END
/////////////////////////////////////////////////////////////////////////////
