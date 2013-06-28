/*
 * p6502control.h
 *
 * Internal Types and macros for the Propeddle system
 *
 * (C) Copyright 2011-2013 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */

#if !defined(_P6502CONTROL_H) && defined(INCLUDING)
#define _P6502CONTROL_H

/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////


#include "p6502features.h"
#include <propeller.h>


/////////////////////////////////////////////////////////////////////////////
// MACROS
/////////////////////////////////////////////////////////////////////////////


// Change the following depending on your circuit board design.
// The lowest supported version is 8.
#define P6502_HWREV = 8

// Required stack size in DWORDS
#define P6502_STACK_SIZE (4)


//===========================================================================
// Pin usage
//===========================================================================

/////////////////////////////////////////////////////////////////////////////
// DATA
/////////////////////////////////////////////////////////////////////////////


// The signals to the 6502 are continuously updated from this global
// variable while we run it.
// Only the signal bits should be set, all other bits should remain zero.
extern volatile HUBDATA unsigned Signals;

// Automatically generated symbol containing startup code for this module
extern unsigned _load_start_p6502control_cog[];


/////////////////////////////////////////////////////////////////////////////
// CODE
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Initialize the system
//
// This should be called first, before calling any other functions
void p6502control_Init(void);


//---------------------------------------------------------------------------
// Load data
//
// Loads a block of data from the hub into the RAM
unsigned                                // Returns 0=success, other=interrupt
P6502control_Load(
    void *pSrc,                         // Source hub address
    unsigned short pTarget,             // Address in 6502 space
    size_t size);                       // Length in bytes
  
  
//---------------------------------------------------------------------------
// Run
//
// Runs the 6502 at given speed until number of given clocks are reached,
// or until another cog interrupts by holding the clock high when the control
// cog wants to make it low.
//
// If the cycle time is too low, it's adjusted automatically to make the
// system run at the maximum speed.
unsigned                                // Returns 0=done, other=interrupt
P6502control_Run(
    unsigned nClockCount,               // Number of clock cycles, 0=infinite
    unsigned nCycleTime);               // Num Prop cycles per 6502 cycles


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