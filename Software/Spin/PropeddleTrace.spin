''***************************************************************************
''* Propeddle Trace module
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
'' The trace cog writes a long to hub memory for each clock cycle on the
'' 6502, until it runs out of space. The long has the following format:
''
'' 3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
'' 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
'' ---------------------------------------------------------------
'' C C C C C C C C A A A A A A A A A A A A A A A A D D D D D D D D
''
'' Where:
'' A=Address bits
'' D=Data bits
'' C=Control bits originally at bit 16-23
''
'' Outgoing signals are not recorded; many of them can be deducted
'' from execution flow.
''
'' Pins 24-31 are discarded; the hardware was designed in such a way that
'' none of these pins carry information that's useful in an execution trace.
''
'' The data bus is only available (and reliable) to the trace cog at the end
'' of Phi2, and the address bus is only available during a small window of
'' time at the start of Phi1. For that reason, the trace cog writes its data
'' to the hub after it gets the data bus for the next cycle. That means the
'' logged data is delayed by one cycle.
''
'' Also, when the control cog drops out of RUNNING mode by a pseudo-interrupt
'' or because it reaches its predetermined number of cycles to run, the trace
'' cog may still have data to log and may be waiting for the control cog to
'' execute another clock cycle.
''
'' If you want to single-step the 6502, you should restart the trace cog
'' with a length parameter of 1 before performing each step with the control
'' cog, so that the trace cog stores the value immediately after the end of
'' the single 6502 clock cycle without waiting for the next cycle.
''
'' It's possible to run multiple trace cogs though there's probably no reason
'' to do so except in extraordinary situations. They can use overlapping
'' memory areas because they read from the pins and write to the hub.


OBJ

  hw:           "PropeddleHardware"


VAR

  long  g_CogId


PUB Start(TraceBuffer, TraceLen)
'' This starts a cog to trace the 6502. The parameters are the hub address
'' of the target buffer, and the number of longs that can be stored in it.
''
'' The control cog should be active before this is called. It doesn't have
'' to be running.

  Stop
  longfill(TraceBuffer, 0, TraceLen)

  if (TraceLen > 0) ' Don't start the cog if there's nothing to log
    g_TraceBuffer := TraceBuffer
    g_TraceLen    := TraceLen
    if cognew(@TraceCog, @g_CogId) => 0
      repeat until g_CogId ' The cog stores its own ID + 1
      

PUB Stop
'' Stops the trace cog if it is running.

  if g_CogId
    cogstop(g_CogId~ - 1)

  
DAT

'============================================================================
' Trace cog

                        org     0
                        
TraceCog
                        ' Set the C flag to skip the hub instructions
                        ' during the first iteration
                        sub     zero, #1 nr,wc

                        ' The hub address is increased in the loop before the
                        ' first data longword is stored; make up for this
                        ' by pre-decreasing it here
                        sub     g_TraceBuffer, #4

                        ' Let caller know we're running by storing cogid + 1
                        cogid   data
                        add     data, #1
                        wrlong  data, PAR

'============================================================================
' Main loop                        

Loop
'tp=82 <-- Next clock cycle already started by this time

                        ' Wait until AEN is active
                        ' If this would wait the minimum amount of time that
                        ' a WAITPNE could wait, it would wait until tp=8
                        ' However AEN doesn't go low until just before tp=12
                        waitpne mask_AEN, mask_AEN
'tp=12
                        ' Wait for one instruction before picking up the
                        ' address bus, so the address bus buffers are
                        ' stable. Meanwhile, store the instruction counter
                        ' so we can synchronize with the end of Phi2
                        ' later on. 
                        mov     clock, CNT
                        mov     newaddr, INA
'tp=20
                        ' The last step of preparing the data to be stored
                        ' is to combine the address bus with the data bus
                        ' We do this here because we have to pick up the
                        ' data bus as late as possible (towards the end
                        ' of Phi2) and we have to pick up the address bus
                        ' as early as possible, and there's not a whole
                        ' lot to do in the mean time.
                        and     data, mask_DATA
                        or      data, addr
'tp=28
                        ' Store the logging data to the hub
                        ' On the first iteration of the loop, the instruction
                        ' is skipped because C=1, since we won't have
                        ' anything to log yet. 
        if_nc           wrlong  data, g_TraceBuffer
'tp=36..51                        
                        ' Bump the hub address so we'll write the next item
                        ' one longword after the current item
                        add     g_TraceBuffer, #4 wc
'tp=40..55
                        ' Copy the new address bus value and shift it to make
                        ' space for the data bus
                        mov     addr, newaddr 
                        shl     addr, #8
'tp=48..63
                        ' Pick up the data bus just before the control cog
                        ' makes CLK0 low at the end of Phi2 (which is when
                        ' the 6502 picks up incoming data too).
                        ' If the clock is running slower than maximum speed,
                        ' that point in time is still a good one because
                        ' the data bus is guaranteed to have stable data,
                        ' no matter what.
                        ' We always want to sample the data bus at the same
                        ' time relative to the start of Phi1, so we use
                        ' a waitcnt instruction based on the time that Phi1
                        ' started.
                        ' We want to make sure that the mov-from-INA
                        ' instruction is slightly ahead of the control cog's
                        ' mov-to-OUTA instruction so we time the mov-from-INA
                        ' to be done by tp=78. So it has to start at tp=74.
                        ' We recorded CNT at tp=12 so we need to add 62.
                        ' These two instructions take at least 4+6 cycles,
                        ' which gives us one cycle to spare in the worst case
                        ' before we hit tp=74 which is where we want to be. 
                        add     clock,#62 ' <-- wait until 12+62 cycles after start of Phi1 
                        waitcnt clock, #0 ' <-- min wait time would result in tp=73
'tp=74                         
                        mov     data, INA
'tp=78                        
                        djnz    g_TraceLen, #Loop

                        ' Log the last item without waiting
                        ' This is needed to make it possible to do single
                        ' stepping.
                        and     data, mask_DATA
                        or      data, addr
                        wrlong  data, g_TraceBuffer
                        
                        ' We land here when we run out of space.
InfiniteLoop            jmp     #InfiniteLoop                        

                        
'============================================================================
' Constants

zero                    long    0
mask_AEN                long    (|< hw#pin_AEN)
mask_DATA               long    hw#con_mask_DATA


'============================================================================
' Working variables

addr                    long    0
newaddr                 long    0
data                    long    0
clock                   long    0        


'============================================================================
' Parameters

g_TraceBuffer           long    0
g_TraceLen              long    0

                        fit
                        