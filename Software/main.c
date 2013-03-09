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


//#define INCLUDING // Workaround for SimpleIDE compiling .h files as modules
//#include "p6502control.cogc"

#include <propeller.h>


/*


NOTE: The reason I'm abandoning the C version of the project for now, is
that the following inline assembly code (and a lot of instructions in the
.cogc module) currently don't compile/assemble correctly: The assembler
doesn't translate immediate values correctly if they refer to cog 
addresses (except for JMP / CALL instructions for which it follows a
different execution path).

Also, data directives that store (cog) pointers to other items currently
don't generate the correct addresses.
 
The problem is caused by the fact that the GNU tools insist on using
byte-based addressing, and the current version of the Propeller assembler
converts the immediate parameters to cog pointers at too early a stage,
and doesn't translate data at all. This is all fine for the C compiler
which uses stores data in the hub and regards the cog as a huge register
bank (try taking the address of a variable declared with _COGMEM), but
it needs some work for projects with serious amounts of inline assembly
such as this one, especially if it contains self-modifying code.
 
The maintainers are aware of the problem but they are apparently just as
busy as I am: communication is slow and tedious, and they are 
(understandably) afraid that changes to the Assembler will break GCC. I 
have commit access to the PropGCC source code but I'm not fully familiar
with the Binutils source code at this time, and the dependencies between
the various tools and of course I don't want to break anything either,
and I really want to get this done before the Official Parallax 
Conference on May 4, 2013, so I decided to upload the current status to
Github, and I'll copy/paste all the important parts to a new Spin 
module, and translate the inline assembly so it can be used with the
(known to be stable) Spin compiler.
 
For more information, see this discussion on the Parallax forums:
http://forums.parallax.com/showthread.php/146333
 
 
*/
int main(int argc, char **argv)
{
  unsigned n = 0;
  unsigned *p = &n;
  
  __asm__ __volatile__ (
  ".cog_ram;"
  "     long $A7A7A7A7;" // Marker to find this code in objdump of a.out
  "x:"
  "     mov r8, x;"
  "     mov r8, #x;" //<--- Compiles the wrong value for x
  "     jmp x;"
  "     jmp #x;"
  "     long x" //<--- Compiles the wrong value for x
  "
  :
  :
  : "r8"
  );
}


#if 0
#include "p6502control.h"


/////////////////////////////////////////////////////////////////////////////
// FUNCTIONS
/////////////////////////////////////////////////////////////////////////////


int main(int argc, char **argv)
{

    /*unsigned i;
    
    p6502control_Init();
    
    for (;;)
    {
        OUTA ^= P6502_MASK_LED;

        p6502control_Run(1, 40000000);
    }*/
    
//    return 0;
}
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
