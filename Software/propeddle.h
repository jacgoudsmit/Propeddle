/*
 * propeddle.h
 *
 * Library that can be used to control a 6502 processor, along with its
 * RAM memory, on the Propeddle hardware. Note: we refer to it as a 6502
 * throughout the documentation and comments, though it really is a 
 * Western Design Center (WDC) 65C02S, meaning it can be stopped at any
 * time in any clock state and won't lose its register data when doing so.
 * It can also be run at any clock speed up to 14MHz, but the Propeddle
 * hardware is only capable of clocking it at up to 1MHz speeds (when 
 * using a 5MHz crystal).
 *
 * This module can be compiled in any memory model but because the 6502
 * shares the clock line with the I2C pins, special consideration is
 * needed when compiling in a memory mode that needs those pins. Compiling
 * in LMM memory mode is recommended.
 *
 * This is the "top level" library of what a software-defined
 * computer would use to implement itself.
 *
 * All functions are fully reentrant (i.e. can be called by any cog at any
 * time without causing corruption) unless otherwise noted.
 *
 * The module uses one cog and one lock. It doesn't make sense to run more
 * than one cog because there are only enough pins to control one 6502, so
 * the data to control the cog is stored as a singleton and cannot be
 * accessed directly.
 *
 * The control cog is what really controls the 6502, the library controls
 * the cog by posting commands. The cog can be in the following states:
 * STOPPED:     
 *      The 6502 is stopped and the control cog is ready to accept commands
 *      (initiated by this library) e.g. to change signals that control the
 *      6502.
 * RUNNING:
 *      The control cog generates clock pulses at a predetermined frequency
 *      (up to 1MHz when a 5MHz crystal is used), which lets the 6502 
 *      execute program instructions in what it sees as the software-defined
 *      computer.
 *      The control cog doesn't have time to check for incoming commands
 *      while it's in this state, but it can be interrupted to make it go
 *      back to the STOPPED state.
 *      While the control cog is in RUNNING state, all functions in this
 *      library that wait for the lock will wait forever.
 *      The cog that switched the state to RUNNING "owns" the lock until
 *      it switches the state again.
 * DISCONNECTED:
 *      In this state, the control cog lets go of the I2C bus (SCL and SDA),
 *      so that it can be used for other hardware such as a Real-Time Clock
 *      or for the EEPROM. The 6502 clock is shared with I2C clock pin
 *      (SCL) and the other I2C pin (SDA) is held HIGH by the control cog to
 *      prevent activating other devices such as the boot EEPROM.
 *
 * (C) Copyright 2011-2012 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */


/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////


#include <propeller.h>
#include <stdbool.h>


/////////////////////////////////////////////////////////////////////////////
// PUBLIC FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


#ifdef __cplusplus
extern "C"
{
#endif


//---------------------------------------------------------------------------
// Initialize the Propeddle system
//
// This uses one cog and one lock. If they are not both available, the
// function returns false and the cog is not started.
//
// If the control cog is already started, it's stopped and restarted. Note:
// It's not recommended to stop and restart the Propeddle system unless you
// also plan on resetting the 6502.
//
// It wouldn't make sense to have multiple control cogs running, so the data
// that's needed to communicate with the control cog is stored as static
// data and is not directly accessible outside the library.
//
// The control cog starts up in STOPPED state: all signals to the 6502 are
// deactivated to make it ready to run, and the clock is made HIGH but no
// further clock pulses are generated in this state.
//
// This function is not reentrant: only one cog should call this function.
bool                                    // Returns TRUE=success FALSE=failure
propeddle_Start(void);


//---------------------------------------------------------------------------
// Stop the control cog
//
// Stops the Propeddle control cog and frees up the cog and the lock.
//
// If the control cog is in RUNNING state, it is changed to STOPPED state
// first by interrupting it (this influences other cogs that might be 
// waiting for the 6502). All auxiliary cogs are stopped too.
//
// The 6502 is halted (RDY activated) so that it won't execute any 
// instructions. Nevertheless, because the data bus is uncontrolled, the
// behavior of the 6502 may not be predictable if the control cog is
// restarted.
//
// This function is not reentrant: only one cog should call this function.
void
propeddle_Stop(void);


//---------------------------------------------------------------------------
// Check if the control cog is running
bool                                    // Returns TRUE=running FALSE=not
propeddle_IsStarted(void);


//---------------------------------------------------------------------------
// Turn LED on
//
// This can be used for debugging, if the LED is present and enabled (the
// LED pin is shared with a video pin).
//
// The function waits until it can take the lock.
//
// Returns FALSE if the control cog is not running.
bool                                    // Returns TRUE=success FALSE=failure
propeddle_LedOn(void);


//---------------------------------------------------------------------------
// Turn LED off
//
// This can be used for debugging, if the LED is present and enabled (the
// LED pin is shared with a video pin).
//
// The function waits until it can take the lock.
//
// Returns FALSE if the control cog is not running.
bool                                    // Returns TRUE=success FALSE=failure
propeddle_LedOff(void);


//---------------------------------------------------------------------------
// Toggle LED
//
// This can be used for debugging, if the LED is present and enabled (the
// LED pin is shared with a video pin).
//
// The function waits until the cog is in STOPPED state and until it can
// take the lock. It returns false if the control cog is not running.
bool                                    // Returns TRUE=success FALSE=failure
propeddle_LedToggle(void);


//---------------------------------------------------------------------------
// Get value of the control cog's INA register
//
// This can be used for debugging.
//
// The function waits until it can take the lock.
//
// Returns 0 if the control cog is not running.
unsigned                                // Returns INA from the control cog
propeddle_GetINA(void);


//---------------------------------------------------------------------------
// Get value of the control cog's OUTA register
//
// This can be used for debugging.
//
// The function waits until it can take the lock.
//
// Returns 0 if the control cog is not running.
unsigned                                // Returns OUTA from the control cog
propeddle_GetOUTA(void);


//---------------------------------------------------------------------------
// Change the value of the signal pins
//
// This can be used for debugging. Use of this function is discouraged
// because it requires knowledge about the hardware.
//
// This can be used at any time but changing the state to RUNNING at the
// same time that this function is executing may result in this function 
// getting stuck. 
//
// Returns false if the control cog isn't running
bool                                    // Returns TRUE=success FALSE=failure
propeddle_SetSignals(unsigned sigmask); // Signal mask


//---------------------------------------------------------------------------
// Get the value of the signal pins
//
// This can be used for debugging. Use of this function is discouraged
// because it requires knowledge about the hardware.
//
// This can be used at any time.
//
// The result is undefined if the control cog isn't running
unsigned                                // Returns signal mask
propeddle_GetSignals(void);


//---------------------------------------------------------------------------
// Disconnect from the I2C bus
//
// This switches the state of the control cog to DISCONNECTED: it halts the
// 6502 (activates the RDY line) and turns the SCL and SDA lines off in its
// DIRA register.
//
// The function waits until it can take the lock.
//
// Returns FALSE if the control cog is not running.
bool                                    // Returns TRUE=success FALSE=failure
propeddle_DisconnectI2C(void);


//---------------------------------------------------------------------------
// Run the 6502 for a specified number of cycles, at the given frequency
//
// The function waits until it can take the lock. It will "own" the lock
// until it switches the state (see below).
//
// This function is not reentrant: only one cog should call this function.
//
// The control cog executes this command as a very accurately timed loop of
// assembler instructions that control the signals to the 6502 and the RAM
// chip. Additional cogs can be used to map parts of the 6502 memory map
// into the hub of the Propeller, or to prevent the 6502 from overwriting
// RAM memory (ROM emulation).
// 
// The maximum frequency at which the 6502 can be run depends on the crystal
// frequency. With a 5MHz crystal, the maximum frequency for the 6502 is
// 1MHz.
//
// The function returns immediately after the control cog starts the loop
// in the RUNNING state. It's possible to interrupt the RUNNING state (see
// below) but the cog will not respond to commands. Once the control cog
// is in this state, the same cog that called this function should also
// call one of the functions to end the RUNNING state.
//
// The frequency is given in Propeller cycles. The minimum cycle time is
// 80, meaning that one clock is generated for the 6502 on every 80 
// Propeller cycles. That means on a 5MHz crystal (80MHz clock frequency
// in PLL16 mode), the 6502 can be run at 1MHz. The slowest speed possible
// is 0xFFFFFFFF, but if you want to run that slow, you'll probably just
// want to single-step.
//
// The number of cycles to execute can be limited: If set to a value unequal
// to zero, only the given number of clock pulses is generated on the 6502.
//
// Returns FALSE if the control cog is not running.
bool                                    // Returns TRUE=sucess FALSE=failure
propeddle_Run(
    unsigned cycletime,                 // Num of Prop cycles per 6502 cycle
    unsigned numcycles);                // Number of cycles; 0=infinite


//---------------------------------------------------------------------------
// Wait until control cog stops while in RUNNING state, or until timeout
//
// This can be used in RUNNING state (only) to wait for the control cog to
// finish running the predetermined number of cycles, or the given timeout.
//
// If the control cog doesn't finish before the timeout, it is kept in the
// RUNNING state (i.e. it's not forced to stop). If the control cog DOES
// finish, the state is changed back to STOPPED and other cogs can send
// commands again.
//
// Note, you should call this function repeatedly while the cog is in
// RUNNING state, otherwise other cogs will never be able to send commands
// again. To accomplish an infinite timeout, just execute this function
// in an infinite for-loop with a timeout value of 0xFFFFFFFF.
//
// Returns TRUE if the cog is back in STOPPED state (or if the function
// was called in error), FALSE if it's still running after the timeout.
bool                                    // Returns TRUE=stopped FALSE=timeout
propeddle_RunWait(
    unsigned timeout);                  // Time-out in Propeller cycles


//---------------------------------------------------------------------------
// Stop the control cog immediately if it's in RUNNING state
//
// This can be used to immediately terminate the RUNNING state of the 
// control cog and bring it back to STOPPED state. The 6502 is left in a
// predictable state so it can easily be restarted by changing to RUNNING
// state again.
//
// This function should only be called from the function that changed the
// control cog to the RUNNING state.
//
// The lock is cleared so that commands can be executed again.
//
// Returns FALSE if the control cog isn't running.
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
