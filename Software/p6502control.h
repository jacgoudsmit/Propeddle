/*
 * p6502control.h
 *
 * Internal Types and macros for the Propeddle system
 *
 * (C) Copyright 2011-2012 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */


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

typedef enum
{
    // Data bus during CLK0=1.
    pin_D0 = 0,
    pin_D1,
    pin_D2,
    pin_D3,
    pin_D4,
    pin_D5,
    pin_D6,
    pin_D7,

    // Address bus during CLK0=0 while AEN is active. 
    pin_A0 = 0,
    pin_A1,
    pin_A2,
    pin_A3,
    pin_A4,
    pin_A5,
    pin_A6,
    pin_A7,
    pin_A8,
    pin_A9,
    pin_A10,
    pin_A11,
    pin_A12,
    pin_A13,
    pin_A14,
    pin_A15,

    // Signal outputs while AEN is inactive
    // These are transferred to the 6502 when SLC transits 0->1
    pin_SEL0 = 8,
#if P6502_HWVER >= 9
    pin_BE = pin_SEL0,                  // Bus Enable on 65C02
#endif
    pin_SEL1 = 9,
    pin_SETUP = pin_SEL1,               // Previously known as SEL1
    pin_RAMA16 = 10,                    // RAM bank switch
    pin_NMI = 11,                       // Non-Maskable Interrupt (edge-triggered)
    pin_IRQ = 12,                       // Interrupt Request (level-triggered)
    pin_RDY = 13,                       // Hold the 6502 (read cycle only)
    pin_RES = 14,                       // Reset
    pin_SO = 15,                        // Set Overflow

    // Limited VGA: 1 bit (monochrome) or rewired (3 bits instead of 6) 
    // VSYNC and HSYNC are at the usual pin offsets, and so are Green MSB and
    // Blue MSB. However because we don't have enough pins for 6-bis VGA and
    // because we wanted to stay compatible with TV out, Red MSB was moved to
    // where normally the Blue LSB is, and only 8 colors are available instead
    // of 64.
    // To use this, program the video register the same way as you would use
    // a full VGA out, but use 0x2F as mask and map the colors to those bits.
    pin_VGA = 16,                       
    pin_VGA_VSYNC = pin_VGA,            // VSYNC at the usual pin offset
    pin_VGA_HSYNC = pin_VGA+1,          // HSYNC at the usual pin offset
    pin_VGA_R = pin_VGA+2,              // Red (where normally Blue LSB is)
    pin_VGA_B = pin_VGA+3,              // Blue (where normally Blue MSB is)
    pin_VGA_G = pin_VGA+5,              // Green (where normally Green MSB is)

    // Full TV output with optional audio
    // The TV outputs are on the pins where most boards have VGA out,
    // because we need all of P0-P15 to get the address bus as fast as possible.
    pin_TV = 16,
    pin_TV0 = pin_TV,
    pin_TV1 = pin_TV+1,
    pin_TV2 = pin_TV+2,
    pin_AUD = pin_TV+3,

    // Other outputs
#ifdef P6502_LED
    pin_LED = 19,                       // NOTE: conflicts with VGA and TV-audio
#endif
    pin_RAMOE = 20,                     // Read from RAM
    pin_RAMWE = 22,                     // Write to RAM
    pin_RW = 23,                        // Read / Not Write
    pin_AEN = 24,                       // Enable Address bus to P0-P15
    pin_SLC = 25,                       // Signal Latch Clock; 0->1 to transfer signals
    pin_SCL = 28,                       // EEPROM clock output
    pin_CLK0 = pin_SCL,                 // Clock is shared between EEPROM and 6502
    pin_PINT = pin_CLK0,                // Pseudo-interrupt pin, used internally
    pin_SDA = 29,                       // EEPROM data; always 1 during normal ops

    // Serial port
    pin_TX = 30,
    pin_RX = 31,
} pin;


//===========================================================================
// Bit masks
//===========================================================================

#define pmask(pin) (1 << (pin))

#ifdef P6502_LED
#define P6502_MASK_LED pmask(pin_LED)
#else
#define P6502_MASK_LED (0)
#endif

// All relevant output pins except signals
#define P6502_MASK_OUTPUTS  (P6502_MASK_LED  | pmask(pin_RAMOE) | pmask(pin_RAMWE)  | pmask(pin_AEN) | pmask(pin_SLC) | pmask(pin_CLK0) | pmask(pin_SDA))
// Signal pins
#define P6502_MASK_SIGNALS  (pmask(pin_SEL0) | pmask(pin_SEL1)  | pmask(pin_RAMA16) | pmask(pin_NMI) | pmask(pin_IRQ) | pmask(pin_RDY)  | pmask(pin_RES) | pmask(pin_SO))
// Signal bit pattern for startup
#define P6502_MASK_HALT     (P6502_MASK_SIGNALS & (~pmask(pin_RDY)))
// Signal bit pattern for reset
#define P6502_MASK_RESET    (P6502_MASK_SIGNALS & (~pmask(pin_RES)))
// RAM controls
#define P6502_MASK_RAM      (pmask(pin_RAMOE) | pmask(pin_RAMWE))
// Data bus
#define P6502_MASK_DATA     (pmask(pin_D0) | pmask(pin_D1) | pmask(pin_D2)  | pmask(pin_D3)  | pmask(pin_D4)  | pmask(pin_D5)  | pmask(pin_D6)  | pmask(pin_D7))
// Address bus
#define P6502_MASK_ADDR     (pmask(pin_A0) | pmask(pin_A1) | pmask(pin_A2)  | pmask(pin_A3)  | pmask(pin_A4)  | pmask(pin_A5)  | pmask(pin_A6)  | pmask(pin_A7) | \
                             pmask(pin_A8) | pmask(pin_A9) | pmask(pin_A10) | pmask(pin_A11) | pmask(pin_A12) | pmask(pin_A13) | pmask(pin_A14) | pmask(pin_A15))
// I2C bus
#define P6502_MASK_I2C      (pmask(pin_SCL) | pmask(pin_SDA))

// Initial values for direction register
#define P6502_MASK_DIR_INIT (P6502_MASK_OUTPUTS | P6502_MASK_SIGNALS)
// Initial values of output pins
#define P6502_MASK_OUT_INIT (pmask(pin_CLK0) | pmask(pin_AEN) | pmask(pin_SDA) | P6502_MASK_RAM)
// Initial values of output pins at beginning of PHI1 (first half of clock cycle)
#define P6502_MASK_OUT_PHI1 (pmask(pin_SDA) | P6502_MASK_RAM)
// Safe values for outputs when 6502 is not in use
#define P6502_MASK_OUT_SAFE (pmask(pin_AEN) | pmask(pin_SDA) | P6502_MASK_RAM)


/////////////////////////////////////////////////////////////////////////////
// TYPES
/////////////////////////////////////////////////////////////////////////////


//===========================================================================
// Commands
//===========================================================================

typedef enum
{
    P6502_CMD_NONE,                     // No command (previous cmd done)
    
#ifdef P6502_CONTROLCOG_SHUTDOWN
    P6502_CMD_SHUTDOWN,                 // Shut down control cog
#endif
    
#ifdef P6502_LED
    P6502_CMD_LED_ON,                   // Turn the LED on
    P6502_CMD_LED_OFF,                  // Turn the LED off
    P6502_CMD_LED_TOGGLE,               // Toggle the LED
#endif

#ifdef P6502_CONTROLCOG_DEBUG
    P6502_CMD_GET_INA,                  // Get input register
    P6502_CMD_GET_OUTA,                 // Get output register
#endif

#ifdef P6502_CONTROLCOG_I2C
    P6502_CMD_DISCONNECT_I2C,           // Disconnect from I2C bus
#endif

    P6502_CMD_SET_SIGNALS,              // Set signals in stopped mode
    P6502_CMD_RUN,                      // Run full speed until interrupted

    P6502_CMD_NUM
}   P6502_CMD;


/////////////////////////////////////////////////////////////////////////////
// DATA
/////////////////////////////////////////////////////////////////////////////


// There can never be more than one control cog, and it's controlled by
// this data struct, stored as singleton in the hub.
extern volatile HUBDATA struct P6502_GLOBALS_T
{
    P6502_CMD       cmd;                // Current command
    unsigned        retval;             // Result of command
    unsigned        signals;            // Current signal outputs
    unsigned        addr;               // 6502 address bus value for command
    unsigned        data;               // 6502 data bus value for command
    unsigned        hubaddr;            // Hub address for command
    unsigned        hublen;             // Hub length for command
    unsigned        counter;            // Counter used by command
    unsigned        cycletime;          // Clock cycle time

}   p6502_globals;


// Automatically generated symbol containing startup code for this module
extern unsigned _load_start_p6502control_cog[];


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
