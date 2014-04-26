''***************************************************************************
''* Propeddle RAM chip control
''* Copyright (C) 2011-2014 Jac Goudsmit
''*
''* TERMS OF USE: MIT License                                                            
''*
''* Permission is hereby granted, free of charge, to any person obtaining a
''* copy of this software and associated documentation files (the
''* "Software"), to deal in the Software without restriction, including
''* without limitation the rights to use, copy, modify, merge, publish,
''* distribute, sublicense, and/or sell copies of the Software, and to permit
''* persons to whom the Software is furnished to do so, subject to the
''* following conditions:
''*
''* The above copyright notice and this permission notice shall be included
''* in all copies or substantial portions of the Software.
''*
''* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
''* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
''* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
''* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
''* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT
''* OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
''* THE USE OR OTHER DEALINGS IN THE SOFTWARE.
''***************************************************************************
''
'' This module controls the RAM chip by working together with the control
'' cog and disabling the RAMOE and/or RAMWR lines for certain memory areas.
''
'' The module runs a cog that switches the RAM outputs off and on in sync
'' with the control module. Before it starts doing this, it builds a bitmap
'' in cog memory, based on the initialization table that's given at startup.
''
'' The initialization table is an array of longs formatted as follows:
''
'' 3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
'' 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
'' ---------------------------------------------------------------
'' A A A A A A A A A A A A A 0 0 0 L L L L L L L L L L L L L 0 0 0
''
'' Where A is the start address and L is the length of the memory block
'' Memory blocks are aligned at 8-byte borders. Whenever the 6502 puts an
'' address on the address bus that matches one of the memory blocks in the
'' initialization table, the cog overrides the RAM access with the given
'' pattern. That way, the 6502 will see some of its memory as ROM or as
'' non-accessible. 
''
'' IMPORTANT: While the control cog executes a Download, the RAM cog
'' should be stopped, otherwise it will interfere. The cog can be restarted
'' after downloading is done.
''
'' Also, this cog should be kept running while the Control Cog is in RUNNING
'' mode; when the RAM cog is stopped, the RAM chip is mapped into the entire
'' memory area.


OBJ

  hw:           "PropeddleHardware"
  
VAR

  ' Don't change the order or size of these variables
  long  g_InitTable             ' Pointer to initialization table
  long  g_CogId                 ' Cog ID + 1
  long  g_OutMask               ' Bitmask for matched memory areas  

PUB Start(InitTable, OutMask)
'' This starts a cog to control the RAM chip. The parameter is the address
'' of the first entry in the table, as described above.
'' If the cog is already running, it is stopped first.
''
'' This should be called while the control cog is active, but not while
'' it's in RUNNING mode.

  Stop
  g_InitTable := InitTable
  g_OutMask   := OutMask
  if cognew(@RAMcontrolcog, @g_InitTable) => 0
    repeat until g_CogId ' The cog stores its own ID + 1
    

PUB Stop
'' Stops the RAM control cog if it is running
''
'' This should not be called while the control cog is in RUNNING mode.

  if g_CogId
    cogstop(g_CogId~ - 1)

  
DAT

'============================================================================
' RAM Control Cog starts here
'
' The following PASM code can be used to control the on-board RAM. When it
' starts, it builds a table of 256 longs at the start of cog memory from the
' table stored at PAR, according to the specs given at the top of this source
' file.
' Each bit in the table represents the value that should be set on the RAMWR
' or RAMOE outputs, to override the output of the control cog. Since those
' lines are active-low on the hardware, and the Propeller applies a logic-OR
' to the outputs of all cogs, it's easy for this cog to make memory areas
' appear read-only, write-only or non-existent to the 6502. Other cogs can
' also monitor the data bus and read/write data to/from hub memory.  

                        org     0

                        ' Relocate code to make space for the table                        
RAMControlCog
:loop
:relocstep              mov     RAMrelocated, RAMprereloc
                        add     :relocstep, RAMoneone           
                        djnz    RAMreloccounter, #:loop

                        jmp     #RAMrelocated

RAMoneone               long    %1_000000001        
RAMreloccounter         long    @RAMrelocatedend - @RAMrelocated             
RAMprereloc
                        org     256
RAMrelocated

'============================================================================
' Relocated code

                        ' Fill the table with zeroes
id                        
:loop                        
:clearstep              mov     255, #0
                        sub     :clearstep, RAMoned
                        djnz    RAMcounter, #:loop                        


'============================================================================
' Initialize table

                        ' Initialize the table from PAR
                        rdlong  ptab, PAR
tableentry                        
                        ' Read length and starting address
                        rdword  len, ptab
                        add     ptab, #2  
                        rdword  addr, ptab
                        add     ptab, #2

                        ' A length of zero ends the table
                        tjz     len, tabledone

                        shr     len, #3
tableloop
                        mov     bitaddr, addr
                        shr     bitaddr, #8                                
                        mov     shift, addr
                        shr     shift, #3

                        movd    tablesaveins, bitaddr
                        mov     data, #1
                        shl     data, shift
tablesaveins                        
                        or      (0), data                         

                        add     addr, #8
                        djnz    len, #tableloop

                        jmp     #tableentry

'============================================================================
' Initialization done, notify the calling cog
                                  
tabledone
                        ' Write cogid + 1 to hub to let calling cog know that
                        ' we're done initializing
                        cogid   id
                        add     id, #1
                        add     PAR, #4
                        wrlong  id, PAR

                        add     PAR, #4
                        rdlong  mask_OUT, PAR

'============================================================================
' Main loop
                        
                        mov     OUTA, #0
                        mov     DIRA, mask_OUT

Loop
'60
                        ' Wait until the control cog enables the address bus
                        ' It takes a bit of time until the address is valid
                        ' because of setup time and propagation delay, so
                        ' we'll do something useful in the mean time 
                        waitpeq zero, mask_AEN
                        mov     OUTA, #0
'16
                        mov     shift, INA
                        and     shift, mask_ADDR
                        mov     addr, shift
                        shr     addr, #8
'32
                        movs    LoadIns, addr
                        shr     shift, #3
LoadIns
'40
                        mov     data, (0)
                        ror     data, shift                         
                        ror     data, #1 wc
'52                        
        if_c            or      OUTA, mask_RAM
'56        
                        jmp     Loop                                                                       


'============================================================================
' Variables

mask_OUT                long    0

RAMcounter              long    256
RAMoned                 long    %1_000000000

addr                    long    0
shift                   long    0
data                    long    0
ptab                    long    0
len                     long    0
bitaddr                 long    0        
                

'============================================================================
' Constants

mask_AEN                long    (|< hw#pin_AEN)
mask_RAM                long    hw#con_mask_RAM
mask_ADDR               long    hw#con_mask_ADDR

zero                    long    0


'============================================================================
' End
RAMrelocatedEnd

                        fit
                        