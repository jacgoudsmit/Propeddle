/*
 * p6502features.h
 *
 * Macros that control which features are compiled
 * You may have to modify this file depending on your project
 *
 * (C) Copyright 2011-2012 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */
 

/////////////////////////////////////////////////////////////////////////////
// MACROS
/////////////////////////////////////////////////////////////////////////////


// Uncomment this if you want to use the LED, e.g. for testing.
// Note, the LED may use a pin that conflicts with VGA out
#define P6502_LED

// Uncomment this if you need to shut down the control cog.
#define P6502_CONTROLCOG_SHUTDOWN

// Uncomment this if you want the debugging code in the control cog:
// In most cases you shouldn't need this
#define P6502_CONTROLCOG_DEBUG

// Uncomment this if you need the I2C bus (pins 28 and 29) for any purpose
// other than booting from the EEPROM. If so, you have to stop the 6502 and
// call the disconnect function.
#define P6502_CONTROLCOG_I2C

// Uncomment this if you will be calling the functions in propeddle.h from
// more than one cog. If not, you can save a lock.
#define P6502_USE_LOCK

// Uncomment this to implement state checks on entry of each API function
#define P6502_CHECK_STATE


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
