/*
 * main.c
 *
 * Sample program.
 *
 * (C) Copyright 2011-2013 Jac Goudsmit
 * Distributed under the MIT license. See bottom of the file for details.
 */


/////////////////////////////////////////////////////////////////////////////
// INCLUDES
/////////////////////////////////////////////////////////////////////////////


#include <propeller.h>

#define INCLUDING // Workaround for SimpleIDE compiling .h files as modules
#include "p6502control.h"


/////////////////////////////////////////////////////////////////////////////
// FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


int main(void)
{
/*    cognew(_load_start_p6502control_cog, 0);
    
    unsigned i;
    
    p6502control_Init();
    
    for (;;)
    {
        OUTA ^= P6502_MASK_LED;

        p6502control_Run(1, 40000000);
    }*/
    
    return 0;
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
