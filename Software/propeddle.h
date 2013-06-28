/*
 * propeddle.h
 *
 * (C) Copyright 2011-2013 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 *
 * Library that can be used to control a 6502 processor, along with its
 * RAM memory, on the Propeddle hardware. Note: we refer to it as a 6502
 * throughout the documentation and comments, though it really is a 
 * Western Design Center (WDC) 65C02S, meaning it can be stopped at any
 * time in any clock state and won't lose its register data when doing so.
 *
 * The WDC 65C02S can also be run at any clock speed up to 14MHz, but the
 * Propeddle hardware is only capable of clocking it at up to 1MHz when 
 * using a 5MHz crystal for the Propeller. Furthermore it has a number of
 * extra instructions compared to the original NMOS 6502, and many 
 * undocumented instructions were patched so they no longer work.
 * 
 * Theoretically it's possible for the Propeddle software to work with an
 * original NMOS 6502 if care is taken to work within the NMOS specs (for 
 * example it's not possible to arbitrarily stop and restart the clock).
 * This is no fully tested and may not be supported in the future. Keep in
 * mind that the pinout of the WDC 65C02S is slightly different from the
 * NMOS 6502 (pay special attention to pin 1) and the NMOS version requires
 * 5V power whereas the WDC will work fine on 3.3V which is the same voltage
 * as the Propeller. The Propeller is not 5V tolerant so resistors are
 * required to drop the voltage. Limited testing was done with resistors of
 * 1K and 2.7K, and this appeared to be successful.
 * 
 * This module can be compiled in any memory model but because the 6502
 * shares the clock line with the I2C pins, special consideration is
 * needed when compiling in a memory mode that needs those pins.
 *
 * This is the "top level" library of what a software-defined
 * computer would use to implement itself.
 *
 * All functions are fully reentrant (i.e. can be called by any cog at any
 * time without causing corruption) unless otherwise noted.
 *
 * The module uses one cog and one lock. It's not possible to have multiple
 * instances of the module because there are only enough pins to control one
 * 6502, so the data to control the cog is stored as a singleton and cannot 
 * be accessed directly.
 *
 * The control cog is what really controls the 6502, the library controls
 * that control cog by posting commands. The cog can be in the following
 * states:
 * SHUTDOWN:
 *      The control cog is not running. This is the state when the Propeller
 *      starts (obviously).
 * READY:     
 *      The control cog is running and waiting for commands (initiated by
 *      this library). The 6502 is stopped in Phi2 state.
 * RUNNING:
 *      The control cog generates clock pulses to the 6502 to make it execute
 *      code. It will keep doing this until a predetermined number of clocks
 *      has been generated, or until interrupted.
 * DISCONNECTED:
 *      This state is identical to the READY state but the cog disconnects
 *      from the SDA and SCL lines (after putting the 6502 in halt mode using
 *      the RDY input), so that other cogs can use the EEPROM and other 
 *      devices on the I2C bus.
 */

#if !defined(PROPEDDLE_H) && defined(INCLUDING)
#define PROPEDDLE_H

/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////


#include <propeller.h>
#include <stdbool.h>

#include "p6502features.h"


/////////////////////////////////////////////////////////////////////////////
// PUBLIC FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


#ifdef __cplusplus
extern "C"
{
#endif


//---------------------------------------------------------------------------
// Initialize the Propeddle system
bool                                    // Returns TRUE=success FALSE=failure
propeddle_Init(void);


//---------------------------------------------------------------------------
// Shut down the Propeddle system
#ifdef P6502_CONTROLCOG_SHUTDOWN
void
propeddle_Stop(void);
#endif


//---------------------------------------------------------------------------
// Disconnect from the I2C bus
#ifdef P6502_CONTROLCOG_I2C
bool                                    // Returns TRUE=success FALSE=failure
propeddle_DisconnectI2C(void);
#endif


//---------------------------------------------------------------------------
// Run the 6502 for a specified number of cycles, at the given frequency
bool                                    // Returns TRUE=sucess FALSE=failure
propeddle_Run(
    unsigned cycletime,                 // Num of Prop cycles per 6502 cycle
    unsigned numcycles);                // Number of cycles; 0=infinite


//---------------------------------------------------------------------------
// Get result of a Run operation
bool                                    // Returns TRUE=success FALSE=failure
propeddle_GetRunResult(
    bool *pfinished,                    // Optional: FALSE=still running
    bool *pinterrupted,                 // Optional: set true if interrupted
    unsigned *pcounter);                // Optional: cycle counter


//---------------------------------------------------------------------------
// Stop the control cog immediately if it's in RUNNING state
bool                                    // Returns TRUE=success FALSE=failure
propeddle_RunEnd(void);


#ifdef __cplusplus
};
#endif


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

#endif