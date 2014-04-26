''***************************************************************************
''* Propeddle control module
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


CON

  '==========================================================================
  ' States
  #0
  con_state_UNINITIALIZED                               ' Cog is not running                        
  con_state_STOPPED                                     ' Cog executing commands                        
  con_state_RUNNING                                     ' Cog is in main loop


  '==========================================================================
  ' Timing constants
  con_delay_MAINLOOP_MINDELAY = 80


  '==========================================================================
  ' Run results
  #0
  con_result_RUN_RUNNING                                ' Cog is still running
  con_result_RUN_NOT_RUNNING                            ' Cog isn't in RUNNING state
  con_result_RUN_TERMINATED                             ' Done after predetermined number of cycles
  con_result_RUN_ABORT_SPIN                             ' Aborted by Spin
  con_result_RUN_ABORT_PINT                             ' Aborted by another cog holding CLK0 high
                                                                          
OBJ
'' References

  hw:           "PropeddleHardware"                     ' Hardware constants
  
PUB Start
'' Starts the control cog and waits until it's initialized.
''
'' If the control cog is already started, the command is ignored.
'' If successful, the lock ID will be set to a value other than -1,
'' the cog ID will be set to a value other than -1 and the
'' 6502 will be in stopped state; all signals are HIGH.
''
'' This routine should not be called after you overwrite the reusable
'' hub memory (trashing the hub copy of the code). In most cases,
'' you should only need to call this once.

  ' If the control cog is already running, ignore command
  if (g_state == con_state_UNINITIALIZED)
    g_busylock := locknew
    if (g_busylock => 0)
      lockclr(g_busylock)

      ' Fire up the cog and wait until it's running
      g_controlcogid   := cognew(@ControlCog, @@0)
      if (g_controlcogid => 0)
        ' Wait until the control cog resets the command
        repeat until g_cmd == 0
      else
        ' Couldn't get a cog, free the lock
        lockret(g_busylock)
       

PUB Stop
'' Sends the Shutdown command to the control cog and waits until it's done.
'' This stops the control cog. Use Start to reinitialize.

  if (g_state <> con_state_UNINITIALIZED)
    ' If the cog is running the main loop, get it back to STOPPED state
    RunEnd

    ' Tell control cog to clean up the 6502 state for shutdown
    Open
    SendCommand(@CmdShutDown)

    ' At this point, the cog is waiting to be stopped
    cogstop(g_controlcogid)
  
    ' Return the lock
    lockclr(g_busylock)
    lockret(g_busylock)

    g_cmd := -1
    g_busylock := -1
    g_controlcogid := -1


PUB GetReusableHubMem
'' This function returns the address of the reusable hub memory. It can be
'' used to store any kind of data after the module is started.
'' The cog should be started before this memory can be used. If the memory
'' is overwritten, the cog cannot be restarted because the code that needs
'' to get downloaded to the cog will be gone.

 
  result := @ReusableHubMem


PUB GetReusableHubLen
'' Returns the length of the hub memory area that can be reused for other
'' purposes.

  result := (@ReusableHubMemEnd - @ReusableHubMem)

    
PUB LedOn
'' Switch the LED on
''
'' Returns TRUE if successful, FALSE if cog is not in STOPPED state

  result := (g_state == con_state_STOPPED)
  if result
    WaitSendCommand(@CmdLedOn)


PUB LedOff
'' Switch the LED off
''
'' Returns TRUE if successful, FALSE if cog is not in STOPPED state

  result := (g_state == con_state_STOPPED)
  if result
    WaitSendCommand(@CmdLedOff)


PUB LedToggle
'' Toggle the LED
''
'' Returns TRUE if successful, FALSE if cog is not in STOPPED state

  result := (g_state == con_state_STOPPED)
  if result
    WaitSendCommand(@CmdLedToggle)


PUB GetIna
'' Get value of control cog's INA register
''
'' Returns 0 if cog is not in STOPPED state

  if (g_state == con_state_STOPPED)
    result := WaitSendCommand(@CmdGetIna)
  else
    result := 0

        
PUB GetOuta
'' Get value of control cog's OUTA register
''
'' Returns 0 if cog is not in STOPPED state

  if (g_state == con_state_STOPPED)
    result := WaitSendCommand(@CmdGetOuta)
  else
    result := 0

        
PUB SetSignal(pin, high)
'' Changes a signal pin
'' The first parameter is the pin number. Should be one of hw#pin_...:
'' SEL0, SEL1, RAMA16, NMI, IRQ, RDY, RES, SO
'' The second parameter is true to make the pin high, false to make it low

  if (high)
    g_signals |= (|< pin)
  else
    g_signals &= !(|< pin)

  ' If the control cog is running, it will pick up the signals
  ' automatically on each clock cycle; if it's stopped, we have to force
  ' it here.
  if (g_state == con_state_STOPPED)
    WaitSendCommand(@CmdSignals)


PUB SetSignals(value)
'' Set all signals

  g_signals := value

  ' If the control cog is running, it will pick up the signals
  ' automatically on each clock cycle; if it's stopped, we have to force
  ' it here.
  if (g_state == con_state_STOPPED)
    WaitSendCommand(@CmdSignals)
    

PUB GetSignal(pin)
'' Gets the current value of the given pin as a "true" or "false" value

  return ((g_signals & (|< pin)) <> 0)


PUB GetSignals
'' Gets all current signals

  return g_signals

  
PUB DisconnectI2C
'' Temporarily disconnects the I2C bus to allow access to the EEPROM
'' This can only be done in stop mode. When the next command is issued,
'' the 65C02 is reconnected to the I2C bus.
'' Any cogs that synchronize to the main cog should be stopped first.
''
'' Returns TRUE if successful, FALSE if cog is not in STOPPED state

  result := (g_state == con_state_STOPPED)
  if result
    WaitSendCommand(@CmdDisconnectI2C)
    

PUB Download(parm_cycletime, parm_hubaddr, parm_addr, parm_numbytes)
'' Downloads data from the given address in the hub to the RAM
''
'' Returns TRUE if successful, FALSE if cog is not in STOPPED state

  result := (g_state == con_state_STOPPED)
  if result
    g_cycletime := parm_cycletime
    g_hubaddr   := parm_hubaddr
    g_hublen    := parm_numbytes
    g_addr      := parm_addr

    WaitSendCommand(@CmdDownload)

    
PUB Run(parm_cycletime, parm_numcycles)
'' Runs the 65C02 for the specified number of cycles at the given number
'' of system cycles per 65C02 cyle.
''
'' If the routine is called with a cycle time that's below the minimum,
'' the main loop will run at the maximum speed.
''
'' After this, the same cog has to call the RunWait, RunEnd or Stop routine;
'' other cogs are blocked from executing commands.
'' The calling cog will own the lock.
''
'' Returns TRUE if successful, FALSE if cog is not in STOPPED state

  result := (g_state == con_state_STOPPED)
  if result
    Open

    g_cycletime := parm_cycletime
    g_counter := parm_numcycles

    SendCommand(@CmdRun)


PUB RunWait(timecount)
'' In running state, wait until the control cog stops, or until CNT passes
'' the given count
'' The lock will be freed afterwards if the control cog stopped within the
'' timeout
''
'' Returns a run-result

  if (g_state == con_state_RUNNING)
    repeat until ((cnt - timecount) => 0)
      if (g_retval <> con_result_RUN_RUNNING)
        result := g_retval
        g_retval := 0 ' Let control cog know we got the result; changes state to STOPPED
        
        Close 
        quit
  else
    result := con_result_RUN_NOT_RUNNING            

PUB RunEnd | s
'' Stops the control cog if it is running by forcing a pseudo-interrupt via
'' the signals.
'' The lock will be freed afterwards 
''
'' Returns a run-result

  if (g_state == con_state_RUNNING)
    ' Backup signals
    s := g_signals

    ' Zero the signals to stop the loop
    g_signals := 0

    repeat while (g_retval == con_result_RUN_RUNNING)

    ' restore flags
    g_signals := s
    
    result := g_retval
    g_retval := 0 ' Let control cog know we got the result; changes state to STOPPED

    Close
  else
    result := con_result_RUN_NOT_RUNNING

    
PUB IsStarted
'' Returns TRUE if the control cog is started

  return (g_state <> con_state_UNINITIALIZED)


PRI Open
' Takes ownership of the control cog before sending a command

  repeat until not lockset(g_busylock)


PRI Close
' Allows other cogs to send commands
'
' This should be used to pick up results after a command is complete

  lockclr(g_busylock)


PRI SendCommand(cmdtosend)
' Sends the given command to the control cog
'
' This should only be called after waiting for the lock and setting
' parameters for the command in hub memory.
' The caller should pick up the results and release the lock
'
' The parameter to this subroutine should be the hub address of a label in
' the control cog code that the caller wants the control cog to jump to.

  ' Set the command by converting the given address from hub address
  ' to assembler address. The offset in bytes is the distance from the
  ' start of the cog code, and that value has to be shifted right by 2 to
  ' get the cog address because cog addresses are longword addresses, not
  ' byte addresses.
  g_cmd := (cmdtosend - @ControlCog) >> 2

  ' Wait until the control cog picks up the command
  repeat while (g_cmd == cmdtosend)

  result := g_retval
  

PRI WaitSendCommand(cmdtosend)
' Sends the given command without parameters and without results
'
' Waits for the lock and releases the lock afterwards

  Open
  result := SendCommand(cmdtosend)
  Close


DAT
'' Global data
''
'' Note: There can only be one control cog, therefore this data is in a DAT
'' block, not in a VAR block.

  ' These are only used by the Spin code
  g_controlcogid        long    -1                      ' Control Cog ID (there can be only one)
  g_busylock            long    -1                      ' Lock ID for lock that protects command
  

DAT

'============================================================================
' Control Cog

                        org     0
ControlCog              jmp     #Init


'============================================================================
' Globals / Parameters

' Global variables are used to transfer parameters and results between the
' control cog and the hub. For each of these global variables, we need:
' 1. The value as stored in the hub
' 2. The value as stored in the cog
' 3. Pointers to the items in the hub
'
' Items 1 and 2 are represented by the same block of data which follows here.

g_state                 long    con_state_UNINITIALIZED ' Current state, don't use in loops!
g_cmd                   long    -1                      ' Current command, protected by busy-lock
g_retval                long    0                       ' Result from previous command
g_signals               long    hw#con_MASK_SIGNALS     ' Signals for command
g_addr                  long    0                       ' Address bus for command
g_data                  long    0                       ' Data bus for command
g_hubaddr               long    0                       ' Hub address for command
g_hublen                long    0                       ' Length of hub area for command
g_counter               long    0                       ' Counter for e.g. limited clock run
g_cycletime             long    0                       ' Clock cycle time                 

' Pointers to the hub version of the above which can be used in
' rdlong/wrlong instructions
pointertable
parm_pState             long    @g_state                ' Pointer to state
parm_pCmd               long    @g_cmd                  ' Pointer to command
parm_pRetval            long    @g_retval               ' Pointer to result
parm_pSignals           long    @g_signals              ' Pointer to signals
parm_pAddr              long    @g_addr                 ' Pointer to 6502 address       
parm_pData              long    @g_data                 ' Pointer to 6502 data (bus)
parm_pHubAddr           long    @g_hubaddr              ' Pointer to hub address        
parm_pHubLen            long    @g_hublen               ' Pointer to hub length
parm_pCounter           long    @g_counter              ' Pointer to counter
parm_pCycleTime         long    @g_cycletime            ' Pointer to cycle time        
pointertable_len        long    (@pointertable_len - @pointertable) >> 2

'============================================================================
' HUB MEMORY AREA BELOW THIS POINT CAN BE REUSED FOR OTHER PURPOSES
' (As long as you don't want to restart the control cog after stopping it)
ReusableHubMem

Init
                        ' Adjust the hub pointers. PAR should contain @@0.
                        '
                        ' The problem we're solving here is that the Spin
                        ' compiler writes module-relative values whenever the
                        ' @ operator is used in a DAT section, instead of
                        ' absolute hub locations. The Spin language has the
                        ' @@ operator to work around this (it converts a
                        ' module-relative pointer to an absolute pointer) so
                        ' @@0 represents the offset of the current module
                        ' which we can use to convert any pointers. It's much
                        ' more efficient to convert an entire pointer table
                        ' in Assembler than in Spin. Doing it in Assembler
                        ' also prevents problems such as accidentally doing
                        ' the conversion twice.
                        add     pointertable, PAR
                        add     Init, d1
                        djnz    pointertable_len, #init

                        ' Init direction register
                        mov     DIRA, dir_INIT

                        ' Initialize all outputs except signals
                        mov     OUTA, out_INIT

                        ' Fall through
'============================================================================
' Command fetching loop

                        
SetStopState
                        ' Initialize state
                        mov     g_state, #con_state_STOPPED 
                        wrlong  g_state, parm_pState

CmdSignals                        
                        ' Read signals from the hub and put them out
                        call    #UpdateSignals                        

CommandDone
                        ' Signal that we're done with current command
                        mov     g_cmd, #0
                        wrlong  g_cmd, parm_pCmd                        

                        ' At this point, other cogs may read results, set
                        ' new values and issue a new command.
                        
                        ' Get command and execute it
GetCommand              rdlong  g_cmd, parm_pCmd wz
ProcessCommand          movs    :jmptocommand, g_cmd
              if_z      jmp     #GetCommand             ' No action if cmd=0
:jmptocommand           jmp     #(CmdShutDown)          ' Src replaced by cmd                        


'============================================================================
' Debugging


CmdLedOn
                        or      OUTA, mask_LED
                        jmp     #CommandDone


CmdLedOff               andn    OUTA, mask_LED
                        jmp     #CommandDone


CmdLedToggle            xor     OUTA, mask_LED
                        jmp     #CommandDone

                        
CmdGetIna               mov     g_retval, INA   
                        wrlong  g_retval, parm_pRetVal
                        jmp     #CommandDone


CmdGetOuta              mov     g_retval, OUTA
                        wrlong  g_retval, parm_pRetVal
                        jmp     #CommandDone
                                                                                                 

'============================================================================
' Helper subroutine: Update signals


UpdateSignals
                        rdlong  g_signals, parm_pSignals
SendSignals                        
                        and     g_signals, mask_SIGNALS
                        andn    OUTA, mask_SLC_SIGNALS
                        or      OUTA, g_signals
                        nop                             ' Do not remove
                        or      OUTA, mask_SLC          ' Clock the flipflops

UpdateSignals_Ret
SendSignals_Ret
                        ret

                        
'============================================================================
' Shut down
                        
CmdShutDown
                        mov     OUTA, out_INIT
                        'nop
                        'or      OUTA, mask_SLC

                        ' Change state back to UNINITIALIZED so we can be
                        ' restarted
                        mov     g_state, #con_state_UNINITIALIZED
                        wrlong  g_state, parm_pState

                        ' Signal that we're done with the command
                        mov     g_cmd, #0                        
                        wrlong  g_cmd, parm_pCmd

                        ' The caller is responsible for stopping the cog
                        ' Alternatively, the command can be set to a nonzero
                        ' value to restart the control cog. This might be
                        ' useful in case the hub copy of this code gets
                        ' overwritten to reuse the memory for other purposes
                        ' Of course, when restarting, the parameters aren't
                        ' reinitialized because the code is not loaded from
                        ' hub memory. Normally this should not be a problem.
:shutdownloop
                        rdlong  g_cmd, parm_pCmd wz
              if_z      jmp     #0
                        jmp     #:shutdownloop                         


'============================================================================
' Disconnect from the I2C lines to allow other cogs to use the EEPROM
'
' The 65C02 gets reconnected when the next command is received.
' NOTE: other cogs that synchronize with the control cog should be stopped.

CmdDisconnectI2C
                        ' Activate the RDY line temporarily to prevent the
                        ' 65C02 from interpreting I2C pulses as clocks
                        or      g_signals, mask_CNRDY
                        call    #SendSignals

                        ' Disable the outputs until the next command
                        andn    DIRA, mask_I2C

                        ' Reset command
                        mov     g_cmd, #0
                        wrlong  g_cmd, parm_pCmd

                        ' Read new command until there is one
:loop                   rdlong  g_cmd, parm_pCmd wz                        
              if_z      jmp     #:loop

                        ' Reset the direction register
                        mov     DIRA, dir_INIT

                        ' Reset the signals
                        call    #UpdateSignals

                        ' Set the state
                        mov     g_state, #con_state_STOPPED
                        wrlong  g_state, parm_pState
                        
                        ' Process the command
                        jmp     #ProcessCommand                          
                        

'============================================================================
' Download data from the hub to the RAM

CmdDownload
                        ' Initialize parameters
                        rdlong  g_hubaddr, parm_pHubAddr
                        rdlong  g_hublen, parm_pHubLen wz
                        rdlong  startaddr, parm_pAddr
                        rdlong  g_cycletime, parm_pCycleTime
                        
                        ' If nothing to do, return
              if_z      jmp     #CommandDone
              
                        ' Initialize timer
                        min     g_cycletime, #con_delay_MAINLOOP_MINDELAY

                        ' Initialize state machine
                        ' Z is always 0 at this time
                        ' For the first state, there is no address matching
                        muxnz   :addrmatch, mux_Z_TO_ALWAYS
                        movs    :addrmatch, #:state_nmi
                        movs    :loopins, #:loop

                        '-------------------------------                        
                        ' Downloading state machine starts here
:loop                        
                        ' Start Phi1
                        mov     OUTA, out_PHI1

                        ' Wait for address bus to stabilize
                        ' Meanwhile, initialize direction and test for
                        ' read/write.
                        andn    DIRA, mask_ADDR
                        test    INA, mask_RW wc

                        ' Get address
                        mov     g_addr, INA
                        and     g_addr, mask_ADDR

                        ' Disable address latches                                
                        or      OUTA, mask_AEN

                        ' If the address matches the currently expected
                        ' address, jump to the currently defined state
                        cmp     g_addr, expectedaddr wz
:addrmatch    if_z      jmp     #(0)                    ' Modified to jump depending on state

                        '-------------------------------
                        ' The address doesn't match
                        ' Enable the RAM based on the R/W signal
:doram        if_c      andn    OUTA, mask_RAMOE        ' RAM to 65C02
              if_nc     andn    OUTA, mask_RAMWE        ' 65C02 to RAM

                        ' Start Phi2
:loopphi2                        
                        or      OUTA, mask_CLK0

                        ' Nothing to do during Phi2
:loopwait
                        ' Wait for the entire cycle time
                        mov     clock, CNT
                        add     clock, g_cycletime
                        waitcnt clock, #0
:loopins                jmp     #(:loop)                ' Changed to CommandDone when done                        

                        '-------------------------------
                        ' Feed a byte to the 6502 during Phi2
:feedbyte6502
                        or      OUTA, feedbyte          ' 16 bits or'ed, upper 8 bits ignored
                        or      DIRA, mask_DATA         ' because of this DIRA setting
                        or      OUTA, mask_CLK0         ' Start Phi2

                        jmp     #:loopwait                        

                        '-------------------------------
                        ' Initial state: Activate NMI
:state_nmi
                        ' Restore the jmp instruction
                        or      DIRA, mask_SIGNALS wz   ' Z is always 0
                        muxz    :addrmatch, mux_Z_TO_ALWAYS ' Change back to if_z

                        ' Generate NMI (which is edge triggered)
                        or      g_signals, mask_CNMI
                        call    #SendSignals

                        ' Change state when NMI vector appears
                        mov     expectedaddr, vector_NMI
                        movs    :addrmatch, #:state_vector1

                        ' Finish as normal cycle
                        jmp     #:loopphi2
                        
                        '-------------------------------
                        ' 6502 is fetching low part of vector
:state_vector1
                        ' Next time, check for the second half of the vector
                        add     expectedaddr, #1
                        movs    :addrmatch, #:state_vector2

                        ' Feed the low byte of the start address to the 6502
                        ' Note, bits 8-15 are ignored because of DIRA setting
                        ' We use this to store the value temporarily
                        mov     feedbyte, startaddr

                        jmp     #:feedbyte6502
                        
                        '-------------------------------
                        ' 6502 is fetching high part of vector
:state_vector2
                        ' Next time, check for the start address of our area
                        mov     expectedaddr, startaddr
                        movs    :addrmatch, #:state_writedata

                        ' Feed the high byte of the start address to the 6502
                        shr     feedbyte, #8
                        jmp     #:feedbyte6502

                        '-------------------------------
                        ' 6502 is iterating our target area
:state_writedata
                        ' Next time, expect the address to be one higher
                        ' but stay in this state
                        add     expectedaddr, #1

                        ' Get data from the hub at the current location 
                        rdbyte  data, g_hubaddr

                        ' Put data from hub on data bus
                        or      OUTA, data
                        or      DIRA, mask_DATA

                        ' Activate the RAM
                        andn    OUTA, mask_RAMWE

                        ' Wait for RAM to store the data
                        ' Meanwhile, do some housekeeping
                        add     g_hubaddr, #1
                        sub     g_hublen, #1 wz
              if_z      jmp     #:endwrite                                                        

                        ' Deactivate RAM
                        or      OUTA, mask_RAMWE

                        ' Feed a CMP Immediate instruction to the 6502.
                        mov     feedbyte, #$C9          ' CMP IMMEDIATE
                        jmp     #:feedbyte6502

                        '-------------------------------
                        ' Finishing up after last write-cycle
                        ' Z=1 at this time
:endwrite
                        ' Deactivate NMI
                        or      DIRA, mask_SIGNALS
                        andn    g_signals, mask_CNMI
                        call    #SendSignals

                        ' From now on, disregard match to expected address
                        ' and always jump to the state function                                                
                        movs    :addrmatch, #:state_endwrite
                        muxz    :addrmatch, mux_Z_TO_ALWAYS ' disregard address from now on

                        ' Feed RTI to the 6502
:feedRTI                mov     feedbyte, #$40          ' RTI
                        jmp     #:feedbyte6502
                                                
                        '-------------------------------
                        ' Done writing bytes to RAM
:state_endwrite
                        ' We're now sending RTI instructions to the 6502.
                        ' We do this until the current address doesn't match
                        ' the expected address anymore, which means that the
                        ' 6502 is fetching the flags and return address from
                        ' the stack.
              if_z      add     expectedaddr, #1
              if_z      jmp     #:feedRTI

                        ' Break out of the loop after finishing Phi2
                        movs    :loopins, #CommandDone
                        jmp     #:doram          
                        
                        
'============================================================================
' Run the main loop
'
' NOTE: The main loop was meticulously constructed to generate a loop that
' can be executed at up to 1MHz when the Propeller is clocked at 80MHz.
' When the Propeller runs at 100MHz, the 65C02 can be run at up to 1.25MHz.
'
' The timing was based on the 65C02 datasheet from Western Design Center, and
' that's what it was tested on, too. The code may not run correctly on older
' 6502s because they may have different timing requirements: especially the
' setup times at the start of Phi1 are much longer for the original 6502 than
' for later models. If you insist on using a different 6502, you may need to
' modify this code (and it may not run at the full 1MHz) and the code for
' other cogs that depend on the timing of the control cog may also need to be
' modified.
'
' The timing values in comments are:
' tn=The number of Propeller cycles from waitcnt instruction. By the time the cog reaches the waitcnt
'    again, tn must be less than the minimum cycle time plus the minimum time
'    for the waitcnt.
' tx=The number of Propeller cycles relative to the Hub access time window.
'    This cog gets access to the hub every 16 cycles, and when a hub
'    instruction executes, it waits for access for up to 15 cycles. After
'    every hub instruction, tx is always equal to 8 because that's how long
'    a hub instruction takes to execute, once it has hub access.
'    There are hub instructions that are executed before the cog goes into
'    the main loop, so the loop always starts with tx at a fixed value.
' tp=The number of clock cycles from the point where Phi1 starts. These
'    numbers are used to synchronization other cogs with this cog.

CmdRun
                        ' Read the time that each clock cycle should take
                        ' Make sure the value is at least equal to the
                        ' minimum execution time.
                        rdlong  g_cycletime, parm_pCycleTime
                        min     g_cycletime, #con_delay_MAINLOOP_MINDELAY

                        ' Read the number of clock cycles to execute.
                        ' Depending on whether the count is 0, enable or
                        ' disable the storing of the result in the DJNZ
                        ' instruction at the end of the loop. If Z=1 here,
                        ' change the instruction to use NR so that the
                        ' DJNZ loads the counter, subtracts one, sees
                        ' that the result is non-zero (so it loops) but
                        ' doesn't store the result so counter stays 0.
                        rdlong  g_counter, parm_pCounter wz
                        muxnz   LoopIns, mux_WR

                        ' Initialize return value
                        ' This is used by the Spin code to indicate that the
                        ' main loop is (still) running.
                        mov     g_retval, #con_result_RUN_RUNNING
                        wrlong  g_retval, parm_pRetVal
                        
                        ' Set the state to Running after setting the result
                        mov     g_state, #con_state_RUNNING
                        wrlong  g_state, parm_pState

                        ' Load initial signals
                        ' If they are zero, bail out right away.
                        rdlong  g_signals, parm_pSignals wz
        if_z            jmp     #EndMainLoop
'tx=12
                        ' Initialize the clock. This should be done just
                        ' before jumping into the loop.
                        ' The minimum delay for a WAITCNT instruction is 6
                        ' cycles, but when the ADD instruction picks up the
                        ' value of CNT, it does this one cycle later than
                        ' the WAITCNT instructions so it appears as if the
                        ' minimum WAITCNT instruction only takes 5 cycles.
                        ' We need the first WAITCNT instruction to wait for
                        ' the next hub access time window, which is 6 cycles
                        ' later than the minimum time. 
                        mov     clock, #6+5
                        add     clock, CNT
'tx=20 <-- The first WAITCNT should wait for 12 cycles total to accomplish tx=0 afterwards
                        
'============================================================================
' Main loop: generate clock cycles to let the 65C02 run its program

'tn=68
'tx=4 
'tp=72                        
MainLoop
                        ' Wait for the end of the requested cycle time
                        ' Initialization may change the DJNZ at the end of the
                        ' loop so that this instruction is skipped.
                        waitcnt clock, g_cycletime

'tn=0
'tx=0
'tp=72+                    
                        ' Turn off the Write Enable to the RAM.
                        ' In other 6502 systems, the RAM is usually disabled
                        ' BECAUSE (and therefore AFTER) the clock goes low (and
                        ' within the Write Data Hold Time of the 6502), so that
                        ' the data that gets written to the RAM is stable.
                        ' On the Propeddle hardware, we have full control over
                        ' the clock, but the RAMWE line is independent from it;
                        ' by disabling the RAMWE line BEFORE making CLK0 low,
                        ' we ensure that any data written to the RAM is stored
                        ' safely.
                        or      OUTA, mask_RAMWE
'tn=4
'tx=4
'tp=76+
StartMainLoop
                        ' This is the entry point to the main loop
                        '
                        ' The function enters and leaves with the CLK0 output
                        ' set to HIGH, so that older 6502 processors can be
                        ' stopped without worrying about registers losing their
                        ' values (the WDC 65C02S can be stopped at any time).
                        '
                        ' Start by setting the clock LOW, starting PHI1.
                        andn    OUTA, mask_CLK0

'tn=8
'tx=8
'tp=0                        
                        ' Check if another cog is keeping the clock in the high
                        ' state, indicating that they want us to stop running.
                        ' If that is the case, we break out of the loop here.
                        ' Because the outputs are retained between our change of
                        ' the CLK0 output and here, it's possible to restart the
                        ' loop without need to worry about the 6502.
                        ' The other cogs that depend on the timing of this cog
                        ' can also safely keep running: they are just as unaware
                        ' of the fact that we couldn't change the CLK0 output
                        ' as the 6502 is.
                        test    mask_CLK0, INA wc
        if_c            jmp     #EndMainLoop

'tn=16
'tx=0
'tp=8                       
Phi1Start
                        ' Initialize all output signals:
                        ' - The RAM is disabled; this has to happen a short time
                        '   AFTER setting the clock low, so that (in the case of
                        '   a read-cycle) the 6502 has time to read the data bus.
                        '   Normally it would be sufficient to turn the RAM off
                        '   at the same time as switching the clock, however
                        '   this is impossible because we can't set one pin low 
                        '   and another pin high at the same time unless we use
                        '   XOR and that's not possible because we can't be sure 
                        '   of the state of the RAM pins at this point.
                        ' - The signals in the OUTA register are initialized to
                        '   0 so it's possible to use an OR instruction to mask 
                        '   the signals from the hub in there a little bit later.
                        ' - The clock for the signal flipflops (SLC) is reset so
                        '   that all it takes to get the signals to the 6502 is
                        '   to change SLC to high again.
                        ' - The address buffers are enabled so other cogs can
                        '   read the address from P0..P15
                        mov     OUTA, out_PHI1
                        
'tn=20
'tx=4
'tp=12                        
                        ' The 74*244 bus drivers are also enabled with the
                        ' previous instruction, but we have to wait for the
                        ' 65C02 to generate the address (setup time), and for
                        ' the '244s to forward the address to us (propagation
                        ' delay). We use this time to reset the direction of
                        ' the signal pins and to test the value of the R/W pin.
                        ' There may be a short timespan during which both
                        ' the '244s and the Propeller drive the pins, but
                        ' this only happens for a few nanoseconds so it
                        ' shouldn't cause any damage.
                        mov     DIRA, dir_PHI1

'tn=24
'tx=8
'tp=16
                        ' Other cogs should inspect the address during this
                        ' instruction (i.e. tp=16..22 or so)                        
                        test    mask_RW, INA wc
                        
'tn=28
'tx=12
'tp=20                        
                        ' Deactivate the address buffers again
                        or      OUTA, mask_AEN

'tn=32
'tx=0
'tp=24                        
                        ' Put the signals on the flip-flops on P8..P15. The
                        ' other cogs can override the signals by waiting for
                        ' AEN to go HIGH and then putting their signal output
                        ' on P8-P15.
                        or      OUTA, g_signals
                        or      DIRA, mask_SIGNALS
                        or      OUTA, mask_SLC                        

'tn=44
'tx=12
'tp=36                        
Phi2Start                        
                        ' Start Phi2 by setting the clock high.
                        ' This starts the PHI2 part of the clock cycle.
                        ' Note: it's possible to combine this instruction with
                        ' the previous one, but the SO signal is picked up by
                        ' the 6502 at the start of PHI2 (the other signals are
                        ' picked up later) so by clocking the flipflops before
                        ' switching CLK0, we guarantee that the delay for all
                        ' signals is minimal.
                        or      OUTA, mask_CLK0

'tn=48
'tx=0
'tp=40 --> Phi2 always starts at this point regardless of cycle time                        
                        ' There's not a whole lot that we need to do during
                        ' Phi2: this is when the 65C02 does its work.
                        ' We use this time to retrieve the signals from the
                        ' hub so we can send them to the 65C02 during the
                        ' next clock cycle.
                        '
                        ' The signals variable in the hub should only contain
                        ' bits that pertain to the signals, otherwise
                        ' unexpected results will occur when these are ORed
                        ' to the outputs during the next clock cycle.
                        '
                        ' Setting the signals to 0 breaks out of the loop.
                        rdlong  g_signals, parm_pSignals wz

'tn=56
'tx=8
'tp=48                        
                        ' Enable the RAM depending on the R/!W output of the
                        ' 6502.
                        ' Any cogs that want to inhibit access to the RAM
                        ' chip (e.g. because they want to read or write
                        ' data directly from hub to 6502 or vice versa, or
                        ' they guard the ROM area of the memory chip against
                        ' writing, or they map an I/O chip into the 6502's
                        ' memory) can do so before this time, by making their
                        ' own RAM outputs HIGH.
        if_nc           andn    OUTA, mask_RAMWE        ' 65C02 to RAM
        if_c            andn    OUTA, mask_RAMOE        ' RAM to 65C02

'tn=64
'tx=0
'tp=56                    
LoopIns                         
                        ' The DJNZ instruction conditionally jumps back to
                        ' the beginning, to wait for the system timer.
                        ' The initialization code may override the bits in
                        ' the instruction so it doesn't store the counter
                        ' if it's initialized to 0 (changing the DJNZ into
                        ' an infinite loop).
                        ' The initialization code may also override the
                        ' source part of the instruction to skip over the
                        ' WAITCNT instruction at the beginning of the loop,
                        ' to make the loop run as fast as possible.
        if_nz           djnz    g_counter, #MainLoop wc ' C=0 when dropping out

                        ' We dropped out of the loop
                        ' Make sure the last cycle's duration is at least as
                        ' long as all other cycles
                        add     clock, #8       ' 4 because djnz is 8 instead of 4 cycles; 4 for this instruction
DropOutIns              waitcnt clock, g_cycletime
        
EndMainLoop
                        ' Make sure the pins have the correct direction and
                        ' value.
                        mov     DIRA, dir_INIT
                        mov     OUTA, out_INIT

                        ' Store the counter back into the hub
                        wrlong  g_counter, parm_pCounter
                        
                        ' The loop ends for one of three reasons:
                        ' - The spin code set the signals to 0
                        '   (Z=1, C may be 0 or 1)
                        ' - Some other cog held the CLK0 output high
                        '   (Z=0 and C=1)   
                        ' - The specified number of clocks were executed
                        '   (Z=0 and C=0)
                        ' Set the result to a value that reflects this.
        if_z            mov     g_retval, #con_result_RUN_ABORT_SPIN
        if_nz_and_nc    mov     g_retval, #con_result_RUN_TERMINATED
        if_nz_and_c     mov     g_retval, #con_result_RUN_ABORT_PINT 
                        wrlong  g_retval, parm_pRetVal

                        ' Read the return value back and wait until the
                        ' calling cog resets it
:loop                   rdlong  g_retval, parm_pRetVal wz
              if_nz     jmp     #:loop
                                                                       
                        ' Finally, change the state and receive next command              
                        jmp     #SetStopState                                  


'============================================================================
' Working variables

                        ' Download working variables
startaddr               long    0
expectedaddr            long    0
feedbyte                long    0
clock                   long    0
data                    long    0                        

'============================================================================
' Constants

                        ' Output Initializers
out_INIT                long    hw#con_OUT_INIT         ' Initial
out_PHI1                long    hw#con_OUT_PHI1         ' Beginning of Phi1

                        ' Initial direction registers
dir_INIT                long    hw#con_mask_OUTPUTS | hw#con_mask_SIGNALS
dir_PHI1                long    hw#con_mask_OUTPUTS
                                                  
                        ' Bitmasks to change conditions in instructions
                        ' using a MUX instruction.
mux_NEVER_TO_ALWAYS     long    %000000_0000_1111_000000000_000000000 ' if_never (%0000) to if_always (%1111)
mux_Z_TO_ALWAYS         long    %000000_0000_0101_000000000_000000000 ' if_z (%1010) to if_always (%1111)

                        ' Bitmask to change the WR (store result) bit
mux_WR                  long    %000000_0010_0000_000000000_000000000
                                                        
                        ' Other bitmasks used in the program
mask_SIGNALS            long    hw#con_mask_SIGNALS     
mask_SLC                long    (|< hw#pin_SLC)
mask_SLC_SIGNALS        long    (|< hw#pin_SLC) | hw#con_mask_SIGNALS
mask_LED                long    hw#con_mask_LED
mask_RAMOE              long    (|< hw#pin_RAMOE)
mask_RAMWE              long    (|< hw#pin_RAMWE)        
mask_AEN                long    (|< hw#pin_AEN)
mask_RW                 long    (|< hw#pin_RW)
mask_CLK0               long    (|< hw#pin_CLK0)
mask_CNRDY              long    (|< hw#pin_CNRDY)
mask_I2C                long    hw#con_mask_I2C

                        ' Constants for download
vector_NMI              long    $FFFA
mask_ADDR               long    hw#con_mask_ADDR
mask_DATA               long    hw#con_mask_DATA
mask_CNMI               long    (|< hw#pin_CNMI)        

                        ' Others
d1                      long    (|< 9)                  ' 1 as destination                                                                                

'============================================================================
' End

ReusableHubMemEnd

                        fit