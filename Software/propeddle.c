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
// DATA
/////////////////////////////////////////////////////////////////////////////


volatile static int propeddle__LockId = -1;


/////////////////////////////////////////////////////////////////////////////
// LOCAL FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Wait until command interface is available, and take it by setting the lock
inline static void propeddle__Take(void)
{
    while (lockset(propeddle__LockId))
    {
        // Nothing to do here
    }
}


//---------------------------------------------------------------------------
// Free the command interface by clearing the lock
inline static void propeddle__Leave(void)
{
    lockclr(propeddle__LockId);
}


//---------------------------------------------------------------------------
// Send a command
//
// This posts a command to the control cog and waits until the control cog
// reports that the command is done.
// The lock must be set and the parameters must be stored before calling
// this.
// The caller is responsible for getting the results and clearing the 
// lock after the command is done.
// The return value is the result set by the control cog.
static unsigned                         // Returns result of operation 
propeddle__SendCommand(
    P6502_CMD cmd)                      // Command to send
{
    p6502_globals.cmd = cmd;
    while (p6502_globals.cmd == cmd)
    {
        // Nothing to do
    }
    
    return p6502_globals.retval;
}


//---------------------------------------------------------------------------
// Send a command without parameters, including taking and leaving the lock
inline static unsigned                  // Returns result of operation
propeddle__WaitSendCommand(
    P6502_CMD cmd)                      // Command to send
{
    unsigned result;
    
    propeddle__Take();
    result = propeddle__SendCommand(cmd);
    propeddle__Leave();
    
    return result;
}


/////////////////////////////////////////////////////////////////////////////
// PUBLIC FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------------
// Initialize the control cog
bool                                    // Returns TRUE=success FALSE=failure
propeddle_Start(void)
{
    bool result;

    if (propeddle__LockId != -1)
    {
        propeddle_Stop();
    }

    result = (propeddle__LockId = locknew()) >= 0;

    if (result)
    {
        p6502_globals.cmd       = P6502_CMD_NUM; // Invalid command
        p6502_globals.signals   = P6502_MASK_HALT;

        result = (-1 < cognew(_load_start_p6502control_cog, 0));
        
        if (result)
        {
            while(p6502_globals.cmd != P6502_CMD_NONE)
            {
                // Nothing to do here
            }
        }
        else
        {
            lockret(propeddle__LockId);
        }
    }

    return result;
}


//---------------------------------------------------------------------------
// Stop the control cog
void
propeddle_Stop(void)
{
    //propeddle_RunEnd();
    //propeddle_Halt()
    
    propeddle__Take();
    propeddle__SendCommand(P6502_CMD_SHUTDOWN);
    
    while (p6502_globals.cmd != P6502_CMD_NONE)
    {
        // Nothing to do here
    }
    
//    propeddle_StopTrace();

    propeddle__Leave();
    
    lockret(propeddle__LockId);
    
    propeddle__LockId = -1;
}


//---------------------------------------------------------------------------
// Turn LED on
bool
propeddle_LedOn(void)
{
    bool result = (propeddle__LockId != -1);
    
    if (result)
    {
        propeddle__WaitSendCommand(P6502_CMD_LED_ON);
    }
    
    return result;
}


//---------------------------------------------------------------------------
// Turn LED off
bool
propeddle_LedOff(void)
{
    bool result = (propeddle__LockId != -1);
    
    if (result)
    {
        propeddle__WaitSendCommand(P6502_CMD_LED_OFF);
    }
    
    return result;
}


//---------------------------------------------------------------------------
// Toggle LED
bool
propeddle_LedToggle(void)
{
    bool result = (propeddle__LockId != -1);
    
    if (result)
    {
        propeddle__WaitSendCommand(P6502_CMD_LED_TOGGLE);
    }
    
    return result;
}


//---------------------------------------------------------------------------
// 
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
