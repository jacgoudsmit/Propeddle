''***************************************************************************
''* Propeddle Hub Data module
''* Copyright (C) 2011-2014 Jac Goudsmit (Thanks to Vince Briel)
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
'' The hub data cog maps Hub memory into the 6502 address space. This can be
'' used for e.g. a video buffer or for emulating ROM.
''
'' This was partially based on a module that I wrote with Vince Briel for his
'' OSI Replica project, licensed under the MIT license.


OBJ

  hw:           "PropeddleHardware"


VAR

  long  g_CogId


PUB Start(HubPtr, MapPtr, Len, AllowWrite)
'' Starts a cog that provides access to the hub for the 6502.
''
'' Parameters:
'' - HubPtr:            Hub address of memory area to provide access to
'' - MapPtr:            First 6502 address to map
'' - Len:               Length of mapped area in bytes
'' - AllowWrite:        Zero for read-only mode, non-zero for read-write mode 
                                                   
  Stop

  g_HubPtr          := HubPtr
  g_MapPtr          := MapPtr
  g_Len             := Len
  g_AllowWrite      := AllowWrite   

  if cognew(@HubAccessCog, @g_CogId) => 0
    repeat until g_CogId ' The cog stores its own ID + 1
    

PUB Stop
'' Stops the trace cog if it is running.

  if g_CogId
    cogstop(g_CogId~ - 1)


DAT

'============================================================================
' Hub access cog

                        org     0
HubAccessCog
                        ' We are going to disable the RAM chip whenever we're
                        ' active, so make sure those pins are set for output.
                        mov     OUTA, #0
                        mov     DIRA, mask_RAM
                        
                        ' If the mode is non-zero (indicating read-write
                        ' mode), modify the instructions in the main loop so
                        ' they don't test for the R/W pin.
                        cmp     g_AllowWrite, #0 wz
        if_nz           mov     RangeTestIns1, RWRangeTestIns1
        if_nz           mov     RangeTestIns2, RWRangeTestIns2                 

                        ' Change the hub pointer into an offset that's
                        ' relative to the 6502 address.
                        sub     g_HubPtr, g_MapPtr

                        ' Change the length into the last address + 1 of the
                        ' mapped 6502 address space
                        add     g_Len, g_MapPtr

                        ' Let caller know we're running by storing cogid + 1
                        cogid   data
                        add     data, #1
                        wrlong  data, PAR
                                                                                                                         
                        jmp     #AccessLoopStart


'============================================================================
' Data

' Parameters, initialized by the Spin code before the cog is started
g_HubPtr                long    0               ' Also used as offset from 6502 address to hub address
g_MapPtr                long    0               ' Start of 6502 address area
g_Len                   long    0               ' Also used as top address of 6502 memory area + 1
g_AllowWrite            long    0               ' Nonzero for read/write, zero for read-only

' Constants
mask_CLK0               long    (|< hw#pin_CLK0)
mask_RW                 long    (|< hw#pin_RW)
mask_RAM                long    hw#con_mask_RAM
mask_DATA_RAM           long    hw#con_mask_DATA | hw#con_mask_RAM
mask_ADDR               long    hw#con_mask_ADDR

' Variables
addr                    long    0               ' Current address
data                    long    0               ' Various data

' Instructions to patch into the main loop in read/write mode
RWRangeTestIns1
                        cmp     addr, g_MapPtr wc
RWRangeTestIns2
        if_nc           cmp     g_Len, addr wc                        

'============================================================================
' Main Loop
'
' The loop has an "interesting" timing problem. Assuming that the control
' cog is running at its fastest (80 Propeller cycles for each 6502 cycle),
' this loop takes 81 cycles to execute in the worst case, which is when the
' hub instruction takes the full 23 cycles.
'
' Obviously, 81 cycles is longer than 80, but this only happens in the case
' that the hub instruction has to wait 15 cycles before getting access to
' the hub. Surprisingly, this is okay, and this is why: In the event that
' the first loop takes 81 cycles, the code will pick up the address bus one
' cycle later in the next loop. This is still within the valid time window
' though. Also, in the event that the execution follows the same path as
' during the first loop, the cog is now executing that hub instruction 81
' cycles later, and if it had to wait 15 cycles in the previous loop, it
' won't have to wait for the hub at all now because it will be at the next
' 16-cycle window. In other words, it's impossible for the worst case of
' 81 cycles to happen during two consecutive loops, and because of the wait
' instruction at beginning of Phi1, the cog will be exactly in sync with the
' control cog again. The timing values show the clock cycles relative to the
' start of Phi1 of the first loop. The values in parentheses show the
' timing in the second loop. As explained above, the hub instructions can
' never take the full 23 cycles during two consecutive loops. 
' 
' NOTE: the first line of the code is not the entry point. The code is
' organized in such a way that the jump to the beginning of the loop is at
' the one and only point in time where there's nothing else to do.

AccessLoop
'tp=4 (85)
                        ' Switch data bus bits back to input mode in case
                        ' we were writing data to it during the previous
                        ' cycle.                        
                        andn    DIRA, #hw#con_mask_DATA ' Take data off the data bus
                        andn    OUTA, mask_DATA_RAM ' Enable the RAM chip too
'tp=12 (93)
                        ' Get the R/W pin into the Z flag.
                        ' Z=1 if the 6502 is writing
                        ' Z=0 if the 6502 is reading
                        test    mask_RW, INA wz
'tp=16 (97)
                        ' Get address; this must be done at this EXACT
                        ' point in time to be in sync with the control cog.  
                        mov     addr, INA
'tp=20 (101)
                        ' Strip out irrelevant bits
                        and     addr, mask_ADDR
'tp=24 (105)
                        ' At this time, the carry is set.
                        ' The following two instructions clear the C flag if
                        ' the address is in range, but only if the 6502 is
                        ' reading.
                        ' In read-write mode, the conditions are modified
                        ' at initialization time so the if_nz condition is
                        ' removed.
RangeTestIns1                         
        if_nz           cmp     addr, g_MapPtr wc
RangeTestIns2         
        if_nz_and_nc    cmp     g_Len, addr wc
'tp=32 (113)
                        ' Add the hub offset to the 6502 address
        if_nc           add     addr, g_HubPtr ' Add hub address
'tp=36 (117)
                        ' By now, Phi2 has started, i.e. the clock is high.
                        ' Make sure the RAM chip is disabled
        if_nc           or      OUTA, mask_RAM
'tp=40 (121)                         
                        ' Depending on the R/W pin, put the data on the data
                        ' bus or get the data to be stored from the 6502.
        if_nc_and_nz    jmp     #FromHub

'tp=44 (125)       
                        ' If R/W is LOW  (6502->hub), the Z flag is 1.
                        ' Get data from data bus pins and write to hub
        if_nc_and_z     mov     data, INA       ' Get bits (only lowest 8 bits significant)
'tp=48 (129)        
        if_nc_and_z     wrbyte  data, addr      ' Remember WRLONG operands are reversed
'tp=56..71 (137..151 see above)        
        if_nc_and_z     jmp     #AccessLoopStart ' tp=60..75 (141..155) on arrival after the jump

'tp=44 (125)
FromHub        
                        ' If R/W is HIGH (hub->6502), the Z flag is 0.
                        ' Get data from hub and put it on the data bus
        if_nc_and_nz    rdbyte  data, addr      ' Read byte from hub (up to 23 prop clocks)
'tp=52..67 (133..147 see above)        
        if_nc_and_nz    or      OUTA, data      ' Write to output
'tp=56..71 (137..151)        
        if_nc_and_nz    or      DIRA, #hw#con_mask_DATA ' Activate output (until after end of cycle)
'tp=60..75 (141..155)
                        ' The loop starts here.
                        ' Start by waiting for CLK0 to go low
AccessLoopStart
                        waitpne mask_CLK0, mask_CLK0 ' Wait until CLK0 goes low
'tp=0 (81) (147..161)
                        jmp     #AccessLoop wc   ' Set the C flag

                        fit
                        