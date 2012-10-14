/*
 * propeddle.c 
 *
 * (C) Copyright 2011-2012 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */


/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////

 
#include "p6502control.h" 
#include "propeddle.h"


/////////////////////////////////////////////////////////////////////////////
// TYPES
/////////////////////////////////////////////////////////////////////////////


#ifdef P6502_CHECK_STATE
typedef enum
{
    propeddle_STATE_UNINITIALIZED,      // Not started yet
    propeddle_STATE_ACCEPTING,          // Accepting commands
    propeddle_STATE_RUNNING,            // Running, need pseudo-int
    propeddle_STATE_DISCONNECTED,       // Disconnected from I2C bus
    
    propeddle_STATE_NUM
}   propeddle_STATE;
#endif


/////////////////////////////////////////////////////////////////////////////
// DATA
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// A lock can be used if more than one cog calls the functions in this module
//
// If only one cog calls this module, the lock-related code can be disabled
// in the features header file.
#ifdef P6502_USE_LOCK
volatile static int propeddle__LockId = -1;
#endif


//---------------------------------------------------------------------------
// Current state of the module
#ifdef P6502_CHECK_STATE
propeddle_STATE propeddle__State = propeddle_STATE_UNINITIALIZED;
#endif


/////////////////////////////////////////////////////////////////////////////
// LOCAL FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Check if the current status matches what's expected
#ifdef P6502_CHECK_STATE
inline static bool propeddle__InState(propeddle_STATE state)
{
    return (propeddle__State == state);
}
#endif


//---------------------------------------------------------------------------
// Check if the Start function was called before
#ifdef P6502_USE_LOCK
inline static bool propeddle__IsStarted(void)
{
    return (propeddle__LockId != -1);
}
#else
#define propeddle__IsStarted() (true)
#endif


//---------------------------------------------------------------------------
// Wait until command interface is available, and take it by setting the lock
#ifdef P6502_USE_LOCK
inline static void propeddle__Take(void)
{
    while (lockset(propeddle__LockId))
    {
        // Nothing to do here
    }
}
#else
#define propeddle__Take()
#endif


//---------------------------------------------------------------------------
// Free the command interface by clearing the lock
#ifdef P6502_USE_LOCK
inline static void propeddle__Leave(void)
{
    lockclr(propeddle__LockId);
}
#else
#define propeddle__Leave()
#endif


//---------------------------------------------------------------------------
// Send a command
//
// This posts a command to the control cog and waits until the control cog
// picks up the command.
// The lock must be set and the parameters must be stored before calling
// this.
// The caller is responsible for getting the results and clearing the 
// lock after the command is done.
static void
propeddle__SendCommand(
    P6502_CMD cmd)                      // Command to send
{
    p6502_globals.cmd = cmd;
    
    // Wait until the control cog changes the command
    // NOTE: this may not necessarily mean that it's done processing
    while (p6502_globals.cmd == cmd)
    {
        // Nothing to do
    }
}


//---------------------------------------------------------------------------
// Send a command without parameters, including taking and leaving the lock
inline static bool                      // Returns TRUE=success FALSE=failure
propeddle__WaitSendCommand(
    propeddle_STATE neededstate,        // Need to be in this state
    P6502_CMD cmd)                      // Command to send
{
    bool result;
    
    propeddle__Take();
    
    result = (neededstate == propeddle_STATE_NUM) || (propeddle__InState(neededstate));
    
    if (result)
    {
        propeddle__SendCommand(cmd);
    }
    
    propeddle__Leave();
    
    return result;
}


//---------------------------------------------------------------------------
// Internal destructor
static void
propeddle__Stop(void)
{
#ifdef P6502_USE_LOCK
    lockret(propeddle__LockId);

    propeddle__LockId = -1;
#endif
    
    propeddle__State = propeddle_STATE_UNINITIALIZED;
}


/////////////////////////////////////////////////////////////////////////////
// PUBLIC FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Initialize the control cog
bool                                    // Returns TRUE=success FALSE=failure
propeddle_Start(void)
{
    bool result = true;

#ifdef P6502_CONTROLCOG_SHUTDOWN
    propeddle_Stop();
#endif

#ifdef P6502_USE_LOCK
    result = (propeddle__LockId = locknew()) >= 0;
#endif

    if (result)
    {
        static volatile int stack[P6502_STACK_SIZE];
        
        p6502_globals.cmd       = P6502_CMD_NUM; // Invalid command
        p6502_globals.signals   = P6502_MASK_HALT;

        // Fire up the control cog
        // Note, the compiler generates the _load_start_identifier_cog symbol
        // The parameter must be a pointer to the end of the stack
        result = (-1 < cognew(_load_start_p6502control_cog, &stack[P6502_STACK_SIZE]));
        
        if (result)
        {
            // Wait until the control cog is running
            while(p6502_globals.cmd != P6502_CMD_NONE)
            {
                // Nothing to do here
            }
            
            // Let rest of the code know we're up and running
            propeddle__State = propeddle_STATE_ACCEPTING;
        }
        else
        {
            // Can't allocate cog, clean up internal data
            propeddle__Stop();
        }
    }

    return result;
}


//---------------------------------------------------------------------------
// Stop the control cog
#ifdef P6502_CONTROLCOG_SHUTDOWN
void
propeddle_Stop(void)
{
    if (propeddle__IsStarted())
    {
        propeddle_RunEnd(); // Stop running if needed
        
        //propeddle_Halt(); // Stop other cogs synced to control cog
        
        propeddle__WaitSendCommand(propeddle_STATE_NUM, P6502_CMD_SHUTDOWN);

        propeddle__Stop();
    }
}
#endif


//---------------------------------------------------------------------------
// Turn LED on
#ifdef P6502_LED
bool
propeddle_LedOn(void)
{
    bool result = propeddle__IsStarted();

    if (result)
    {
        propeddle__WaitSendCommand(propeddle_STATE_ACCEPTING, P6502_CMD_LED_ON);
    }
    
    return result;
}
#endif


//---------------------------------------------------------------------------
// Turn LED off
#ifdef P6502_LED
bool
propeddle_LedOff(void)
{
    bool result = propeddle__IsStarted();
    
    if (result)
    {
        propeddle__WaitSendCommand(propeddle_STATE_ACCEPTING, P6502_CMD_LED_OFF);
    }
    
    return result;
}
#endif


//---------------------------------------------------------------------------
// Toggle LED
#ifdef P6502_LED
bool
propeddle_LedToggle(void)
{
    bool result = propeddle__IsStarted();

    if (result)
    {
        propeddle__WaitSendCommand(propeddle_STATE_ACCEPTING, P6502_CMD_LED_TOGGLE);
    }
    
    return result;
}
#endif


//---------------------------------------------------------------------------
// Run the 6502 for a specified number of cycles, at the given frequency
bool                                    // Returns TRUE=sucess FALSE=failure
propeddle_Run(
    unsigned cycletime,                 // Num of Prop cycles per 6502 cycle
    unsigned numcycles)                 // Number of cycles; 0=infinite
{
    bool result = propeddle__IsStarted();
    
    if (result)
    {
        propeddle__Take();
        
        result = propeddle__InState(propeddle_STATE_ACCEPTING);
        
        if (result)
        {
            p6502_globals.cycletime = cycletime;
            p6502_globals.counter   = numcycles;
            propeddle__SendCommand(P6502_CMD_RUN);
        
            propeddle__State = propeddle_STATE_RUNNING;
        }
        
        propeddle__Leave();
        
        
    }
    
    return result;
}


//---------------------------------------------------------------------------
// Get result of a Run operation
bool                                    // Returns TRUE=success FALSE=failure
propeddle_GetRunResult(
    bool *pfinished,                    // Optional: FALSE=still running
    bool *pinterrupted,                 // Optional: set true if interrupted
    unsigned *pcounter)                 // Optional: cycle counter
{
    bool result = propeddle__IsStarted();
    bool finished = false;
    
    if (result)
    {
        propeddle__Take();
        
        result = propeddle__InState(propeddle_STATE_RUNNING);
        
        if (result)
        {
            finished = (p6502_globals.cmd == P6502_CMD_NONE);
            
            if (finished)
            {
                propeddle__State = propeddle_STATE_ACCEPTING;
            }
        }
        
        propeddle__Leave();
    }
    
    if (pfinished)
    {
        *pfinished = finished;
    }
    
    if (pinterrupted)
    {
        *pinterrupted = (p6502_globals.retval != 0);
    }
    
    if (pcounter)
    {
        // Note: value is invalid if not finished
        *pcounter = p6502_globals.counter;
    }
    
    return result;
}


//---------------------------------------------------------------------------
// Stop the control cog immediately if it's in RUNNING state
bool                                    // Returns TRUE=success FALSE=failure
propeddle_RunEnd(void)
{
    bool result = propeddle__IsStarted();
    
    if (result)
    {
        propeddle__Take();
        
        result = propeddle__InState(propeddle_STATE_RUNNING);
        
        /*
        if (result)
        {
            __volatile__ __asm__ (
            //@@@
            );
        }
        */
        
        propeddle__Leave();
    }
    
    return result;
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
