/*
 * propeddle_load.c 
 *
 * (C) Copyright 2011-2013 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */
 
 
/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////


#include "p6502control.h"


/////////////////////////////////////////////////////////////////////////////
// MACROS
/////////////////////////////////////////////////////////////////////////////


// Maximum speed during RAM operations
#define DOWNLOAD_MINDELAY (80)


/////////////////////////////////////////////////////////////////////////////
// TYPES
/////////////////////////////////////////////////////////////////////////////


// State machine state
typedef enum
{
    STATE_NMI,
    STATE_VECTOR1,
    STATE_VECTOR2,
    STATE_WRITEDATA,
    STATE_ENDWRITE,
      
}   STATE;


/////////////////////////////////////////////////////////////////////////////
// CODE
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Copy hub memory to the Propeddle RAM chip
//
// Every 6502-based computer needs to have a ROM area when it starts up.
// The Propeddle doesn't have any ROM on-board, and doesn't need any: the
// Read-Enable and Write-Enable lines of the RAM chip are under control of 
// the Propeller, so it's possible to download code to the RAM and then deny
// write-access to the 6502 to pretend that the RAM is a ROM.
//
// The RAM chip on the Propeddle board is connected to the data bus and the
// address bus of the 6502, and the 6502 only uses the data bus during the
// second half of each clock cycle, so during the first half of the cycle,
// the Propeller has the opportunity to access the data in the RAM chip in
// any way it pleases, without the 6502 interfering.
//
// However, the 6502 determines which address is selected on the RAM chip.
// So we must trick the 6502 into generating the addresses for us. We do 
// this by generating a non-maskable interrupt (NMI) and feeding a fake
// address to the 6502 when it retrieves the interrupt vector. It then
// starts executing at the given location until it encounters an RTI (return
// from interrupt) instruction. The Propeller feeds dummy instructions to the
// 6502, so that it keeps increasing its address bus output by one address per
// clock cycle. Meanwhile, the Propeller accesses the memory during the first
// half of each clock cycle, while the 6502 isn't looking.
//
// Once the Propeller covers the entire memory area that's needed, it 
// generates an RTI instruction so the 6502 returns to what it was doing
// before.
//
// NOTE: the 6502 may be in the middle of an instruction which it needs to
// finish before it can actually respond to the NMI, so any supporting cogs
// will need to be active while this function runs.
//
// The I/O state after calling is compatible with the state before calling,
// so you can call the function multiple times and the 6502 will retain its
// state. But before calling this for the first time, you need to call the
// initialization function at least once (on the same cog, to initialize
// DIRA, OUTA and the 6502 signals.
_NATIVE
void propeddle_load(
    char *hubaddr,
    size_t len,
    unsigned addr6502,
    unsigned cycletime)
{
    // If nothing to do, return
    if (!len)
    {
        return;
    }
    
    // Make sure we don't break the speed limit
    // This gets optimized to one MIN instruction
    cycletime = (cycletime < DELAY_DOWNLOAD_MINDELAY) ? DELAY_DOWNLOAD_MINDELAY : cycletime;

    // At this point, the 6502's state is equivalent to the end of PHI2.
    // Activate NMI before the start of the first clock pulse so that
    // the 6502 has no chance to start a new instruction. Of course, it's
    // possible that the current instruction is still in progress and
    // it needs to save the current registers on the stack, so we have to
    // keep generating clock pulses and process all signals until the 6502
    // fetches the NMI vector.
    // Note, the NMI interrupt is edge-triggered. We keep it low during the
    // entire process so it doesn't get triggered again.
    Signals &= ~pmask(pin_NMI);
    
    for(;;)
    {
    
        unsigned rw;
        unsigned addr;
        
        // Start PHI1
        _OUTA = P6502_MASK_PHI1;

        // Wait for address bus to stabilize
        // Meanwhile, initialize direction and test for read/write
        _DIRA &= ~P6502_MASK_ADDR;
        
        // Get address and R/!W
        rw = _INA;
        addr = rw & P6502_MASK_ADDR;

        // Disable address bus
        _OUTA |= pmask(pin_AEN);
            
    
    
    
    
    
    
        unsigned rw;
        unsigned addr;
        
        // Get address and RW bit
        addr = startphi1();
        rw = addr & pmask(pin_RW);
        addr &= P6502_MASK_ADDR;
        
        if (
        
        
                        ' If the address matches the currently expected
                        ' address, jump to the currently defined state
                        cmp     addr, expectedaddr wz
:addrmatch    if_z      jmp     #(0)                    ' Modified to jump depending on state

                        '-------------------------------
                        ' The address doesn't match
                        ' Enable the RAM based on the R/W signal
:doram        if_c      andn    OUTA, mask_RAMOE        ' RAM to 65C02
              if_nc     andn    OUTA, mask_RAMWE        ' 65C02 to RAM

                        ' Start Phi2
:loopphi2                        
                        or      OUTA, mask_CLK0

                        ' Nothing to do during Phi2
:loopwait
                        ' Wait for the entire cycle time
                        mov     clock, CNT
                        add     clock, cycletime
                        waitcnt clock, #0
:loopins                jmp     #(:loop)                ' Changed to CommandDone when done                        

                        '-------------------------------
                        ' Feed a byte to the 6502 during Phi2
:feedbyte6502
                        or      OUTA, feedbyte          ' 16 bits or'ed, upper 8 bits ignored
                        or      DIRA, mask_DATA         ' because of this DIRA setting
                        or      OUTA, mask_CLK0         ' Start Phi2

                        jmp     #:loopwait                        

                        '-------------------------------
                        ' Initial state: Activate NMI
:state_nmi
                        ' Restore the jmp instruction
                        or      DIRA, mask_SIGNALS wz   ' Z is always 0
                        muxz    :addrmatch, mux_Z_TO_ALWAYS ' Change back to if_z

                        ' Generate NMI (which is edge triggered)
                        andn    signals, mask_NMI
                        call    #SendSignals

                        ' Change state when NMI vector appears
                        mov     expectedaddr, vector_NMI
                        movs    :addrmatch, #:state_vector1

                        ' Finish as normal cycle
                        jmp     #:loopphi2
                        
                        '-------------------------------
                        ' 6502 is fetching low part of vector
:state_vector1
                        ' Next time, check for the second half of the vector
                        add     expectedaddr, #1
                        movs    :addrmatch, #:state_vector2

                        ' Feed the low byte of the start address to the 6502
                        ' Note, bits 8-15 are ignored because of DIRA setting
                        ' We use this to store the value temporarily
                        mov     feedbyte, startaddr

                        jmp     #:feedbyte6502
                        
                        '-------------------------------
                        ' 6502 is fetching high part of vector
:state_vector2
                        ' Next time, check for the start address of our area
                        mov     expectedaddr, startaddr
                        movs    :addrmatch, #:state_writedata

                        ' Feed the high byte of the start address to the 6502
                        shr     feedbyte, #8
                        jmp     #:feedbyte6502

                        '-------------------------------
                        ' 6502 is iterating our target area
:state_writedata
                        ' Next time, expect the address to be one higher
                        ' but stay in this state
                        add     expectedaddr, #1

                        ' Get data from the hub at the current location 
                        rdbyte  data, hubaddr

                        ' Put data from hub on data bus
                        or      OUTA, data
                        or      DIRA, mask_DATA

                        ' Activate the RAM
                        andn    OUTA, mask_RAMWE

                        ' Wait for RAM to store the data
                        ' Meanwhile, do some housekeeping
                        add     hubaddr, #1
                        sub     hublen, #1 wz
              if_z      jmp     #:endwrite                                                        

                        ' Deactivate RAM
                        or      OUTA, mask_RAMWE

                        ' Feed a CMP Immediate instruction to the 6502.
                        mov     feedbyte, #$C9          ' CMP IMMEDIATE
                        jmp     #:feedbyte6502

                        '-------------------------------
                        ' Finishing up after last write-cycle
                        ' Z=1 at this time
:endwrite
                        ' Deactivate NMI
                        or      DIRA, mask_SIGNALS
                        or      signals, mask_NMI
                        call    #SendSignals

                        ' From now on, disregard match to expected address
                        ' and always jump to the state function                                                
                        movs    :addrmatch, #:state_endwrite
                        muxz    :addrmatch, mux_Z_TO_ALWAYS ' disregard address from now on

                        ' Feed RTI to the 6502
:feedRTI                mov     feedbyte, #$40          ' RTI
                        jmp     #:feedbyte6502
                                                
                        '-------------------------------
                        ' Done writing bytes to RAM
:state_endwrite
                        ' We're now sending RTI instructions to the 6502.
                        ' We do this until the current address doesn't match
                        ' the expected address anymore, which means that the
                        ' 6502 is fetching the flags and return address from
                        ' the stack.
              if_z      add     expectedaddr, #1
              if_z      jmp     #:feedRTI

                        ' Break out of the loop after finishing Phi2
                        movs    :loopins, #CommandDone
                        jmp     #:doram          
                        
                        
        

    
}


/*
CmdDownload
                        ' Initialize parameters
                        rdlong  hubaddr, parm_pHubAddr
                        rdlong  hublen, parm_pHubLen wz
                        rdlong  startaddr, parm_pAddr
                        rdlong  cycletime, parm_pCycleTime
                        
                        ' If nothing to do, return
              if_z      jmp     #CommandDone
              
                        ' Initialize timer
                        min     cycletime, #con_delay_MAINLOOP_MINDELAY

                        ' Initialize state machine
                        ' Z is always 0 at this time
                        ' For the first state, there is no address matching
                        muxnz   :addrmatch, mux_Z_TO_ALWAYS
                        movs    :addrmatch, #:state_nmi
                        movs    :loopins, #:loop

                        '-------------------------------                        
                        ' Downloading state machine starts here
:loop                        
                        ' Start Phi1
                        mov     OUTA, out_PHI1

                        ' Wait for address bus to stabilize
                        ' Meanwhile, initialize direction and test for
                        ' read/write.
                        andn    DIRA, mask_ADDR
                        test    INA, mask_RW wc

                        ' Get address
                        mov     addr, INA
                        and     addr, mask_ADDR

                        ' Disable address latches                                
                        or      OUTA, mask_AEN

                        ' If the address matches the currently expected
                        ' address, jump to the currently defined state
                        cmp     addr, expectedaddr wz
:addrmatch    if_z      jmp     #(0)                    ' Modified to jump depending on state

                        '-------------------------------
                        ' The address doesn't match
                        ' Enable the RAM based on the R/W signal
:doram        if_c      andn    OUTA, mask_RAMOE        ' RAM to 65C02
              if_nc     andn    OUTA, mask_RAMWE        ' 65C02 to RAM

                        ' Start Phi2
:loopphi2                        
                        or      OUTA, mask_CLK0

                        ' Nothing to do during Phi2
:loopwait
                        ' Wait for the entire cycle time
                        mov     clock, CNT
                        add     clock, cycletime
                        waitcnt clock, #0
:loopins                jmp     #(:loop)                ' Changed to CommandDone when done                        

                        '-------------------------------
                        ' Feed a byte to the 6502 during Phi2
:feedbyte6502
                        or      OUTA, feedbyte          ' 16 bits or'ed, upper 8 bits ignored
                        or      DIRA, mask_DATA         ' because of this DIRA setting
                        or      OUTA, mask_CLK0         ' Start Phi2

                        jmp     #:loopwait                        

                        '-------------------------------
                        ' Initial state: Activate NMI
:state_nmi
                        ' Restore the jmp instruction
                        or      DIRA, mask_SIGNALS wz   ' Z is always 0
                        muxz    :addrmatch, mux_Z_TO_ALWAYS ' Change back to if_z

                        ' Generate NMI (which is edge triggered)
                        andn    signals, mask_NMI
                        call    #SendSignals

                        ' Change state when NMI vector appears
                        mov     expectedaddr, vector_NMI
                        movs    :addrmatch, #:state_vector1

                        ' Finish as normal cycle
                        jmp     #:loopphi2
                        
                        '-------------------------------
                        ' 6502 is fetching low part of vector
:state_vector1
                        ' Next time, check for the second half of the vector
                        add     expectedaddr, #1
                        movs    :addrmatch, #:state_vector2

                        ' Feed the low byte of the start address to the 6502
                        ' Note, bits 8-15 are ignored because of DIRA setting
                        ' We use this to store the value temporarily
                        mov     feedbyte, startaddr

                        jmp     #:feedbyte6502
                        
                        '-------------------------------
                        ' 6502 is fetching high part of vector
:state_vector2
                        ' Next time, check for the start address of our area
                        mov     expectedaddr, startaddr
                        movs    :addrmatch, #:state_writedata

                        ' Feed the high byte of the start address to the 6502
                        shr     feedbyte, #8
                        jmp     #:feedbyte6502

                        '-------------------------------
                        ' 6502 is iterating our target area
:state_writedata
                        ' Next time, expect the address to be one higher
                        ' but stay in this state
                        add     expectedaddr, #1

                        ' Get data from the hub at the current location 
                        rdbyte  data, hubaddr

                        ' Put data from hub on data bus
                        or      OUTA, data
                        or      DIRA, mask_DATA

                        ' Activate the RAM
                        andn    OUTA, mask_RAMWE

                        ' Wait for RAM to store the data
                        ' Meanwhile, do some housekeeping
                        add     hubaddr, #1
                        sub     hublen, #1 wz
              if_z      jmp     #:endwrite                                                        

                        ' Deactivate RAM
                        or      OUTA, mask_RAMWE

                        ' Feed a CMP Immediate instruction to the 6502.
                        mov     feedbyte, #$C9          ' CMP IMMEDIATE
                        jmp     #:feedbyte6502

                        '-------------------------------
                        ' Finishing up after last write-cycle
                        ' Z=1 at this time
:endwrite
                        ' Deactivate NMI
                        or      DIRA, mask_SIGNALS
                        or      signals, mask_NMI
                        call    #SendSignals

                        ' From now on, disregard match to expected address
                        ' and always jump to the state function                                                
                        movs    :addrmatch, #:state_endwrite
                        muxz    :addrmatch, mux_Z_TO_ALWAYS ' disregard address from now on

                        ' Feed RTI to the 6502
:feedRTI                mov     feedbyte, #$40          ' RTI
                        jmp     #:feedbyte6502
                                                
                        '-------------------------------
                        ' Done writing bytes to RAM
:state_endwrite
                        ' We're now sending RTI instructions to the 6502.
                        ' We do this until the current address doesn't match
                        ' the expected address anymore, which means that the
                        ' 6502 is fetching the flags and return address from
                        ' the stack.
              if_z      add     expectedaddr, #1
              if_z      jmp     #:feedRTI

                        ' Break out of the loop after finishing Phi2
                        movs    :loopins, #CommandDone
                        jmp     #:doram          
                        
                        
*/


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
