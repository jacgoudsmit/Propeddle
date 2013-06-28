/*
 * p6502_control.h
 *
 * Inline Assembly functions to control the 6502
 *
 * (C) Copyright 2011-2013 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */


#ifndef P6502_CONTROL_H
#define P6502_CONTROL_H


#ifdef __cplusplus
extern "C"
{
#endif 


/////////////////////////////////////////////////////////////////////////////
// MACROS
/////////////////////////////////////////////////////////////////////////////


#define P6502_CONTROL_DELAY_MIN (80)    // Minimum prop cycles per 6502 cycle


/////////////////////////////////////////////////////////////////////////////
// CODE
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Initialize registers and timer
void
inline p6502_control_init(void)
{
  _OUTA = P6502_MASK_OUT_INIT;
  _DIRA = P6502_MASK_DIR_INIT;
}


//---------------------------------------------------------------------------
// Control loop
_NAKED
unsigned                                // Returns remaining clock cycles
inline p6502_control_main(
  unsigned clockcount,                  // Number of clock cycles, 0=infinite
  unsigned cycletime,                   // Prop cycles per 6502 cycle, 0=min
  unsigned *psignals)                   // Signals in hub memory
{
  __asm__ __volatile__ (
"\n                 .pasm"

                    // Make sure we don't break the speed limit
"\n                 min     %[cycletime], %[iDELAY_MIN]"

                    // Note: This is NOT the entry point for the main loop.
                    // The end of the code jumps here if it needs to wait
                    // for the requested cycle time.
"\nMainLoop"
                    // Wait for the end of the requested cycle time
                    // Initialization may change the jump-instruction at the
                    // end of the loop so that this instruction is skipped.
//t0=67..82
//tn=67
"\n                 waitcnt clock,      %[cycletime]"

                    // Turn off the Write Enable to the RAM.
                    // In other 6502 systems, the RAM is usually disabled
                    // BECAUSE (and therefore AFTER) the clock goes low (and
                    // within the Write Data Hold Time of the 6502), so that
                    // the data that gets written to the RAM is stable.
                    // On the Propeddle hardware, we have full control over
                    // the clock, but the RAMWE line is independent from it.
                    // In the ideal case, we would turn RAMWE off at the
                    // same time as making CLK0 low, however RAMWE has to go
                    // HIGH to go off, so the only way to simultaneously
                    // change both pins is to use an XOR, but we can't do 
                    // that because RAMWE is not always LOW to begin with.
                    // So we turn RAMWE off before we set the clock low,
                    // which may look a little weird on a logic analyzer but
                    // the RAM should have had plenty of time to write the
                    // data.
                    // As a bonus, any other cog that's overriding the RAMWE
                    // by setting it high, can simply wait until CLK0 goes
                    // low before setting it low again. No extra delays 
                    // required.
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
                    // of the fact that we couldn't change the CLK0 output
                    // as the 6502 is.
//t0=0
//tn=0
"\n                 test    _mask_CLK0, INA wc"
"\n     if_c        jmp     #EndMainLoop"

                    // Initialize all output signals:
                    // - The RAM is disabled; this has to happen a short time
                    //   AFTER setting the clock low, so that (in the case of
                    //   a read-cycle) the 6502 has time to read the data bus.
                    //   Normally it would be sufficient to turn the RAM off
                    //   at the same time as switching the clock, however
                    //   this is impossible because we can't set one pin low 
                    //   and another pin high at the same time unless we use
                    //   XOR and that's not possible because we can't be sure 
                    //   of the state of the RAM pins at this point.
                    // - The signals in the OUTA register are initialized to
                    //   0 so it's possible to use an OR instruction to mask 
                    //   the signals from the hub in there a little bit later.
                    // - The clock for the signal flipflops (SLC) is reset so
                    //   that all it takes to get the signals to the 6502 is
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
"\n                 test    _mask_RW,   INA wc"         // c=1 read, c=0 write
"\n                 mov     addr,       INA"            // Value only used in Load mode

                    // Turn the address buffers off again
//t0=20
//tn=20
"\n                 or      OUTA,       _mask_AEN"

                    // Put the signals on the flip-flops on P8..P15. The
                    // other cogs can override the signals by waiting for
                    // AEN to go HIGH and then putting their signal output
                    // on P8-P15.
//t0=24
//tn=24                    
"\n                 or      OUTA,       signals"
"\n                 or      DIRA,       _mask_SIGNALS"

                    // In Load mode, a CALL is placed here to check the
                    // current address of the 6502 and enable the RAM if
                    // necessary
                    // Other cogs can wait for AEN HIGH to override signals
                    // at this time.
//t0=32
//tn=32                    
//@@@"\nPhi1AltIns"

                    // In non-Run modes, execution continues here
//@@@"\nPhi1Continue"

                    // Clock the flip-flops to send the signals to the 6502.
"\n                 or      OUTA,       _mask_SLC"
"\n                 waitcnt clock,      %[cycletime]"

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
  [cycletime]             "rC"        (cycletime),

  // Globals
  [psignals]              "rC"        (psignals),

  // Constants that can be implemented as immediates (must be 9 bits or less)
  [iDELAY_MIN]            "i"         (P6502_CONTROL_DELAY_MIN)
:
  );

  return clockcount;
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


#ifdef __cplusplus
};
#endif
#endif
