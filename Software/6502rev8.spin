''***************************************************************************
''* Propeddle 6502 Driver Object for PCB/Schematic Revision 8
''* Author: Jac Goudsmit
''* Copyright (C) 2011-2012 Jac Goudsmit
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
''
'' INTRODUCTION
'' ============
'' Propeddle is a software-defined 65C02 computer based on the Propeller
'' Platform. For more information, see http://www.propeddle.com
''
'' This module contains the PASM code that controls the Propeddle hardware.
'' The bulk of the work is done by one control cog that runs an assembler
'' program. This cog can be controlled in Spin or PASM by other cogs. The
'' code in this module provides everything needed to download a program into
'' the RAM and execute it on the 65C02, but additional modules (and cogs) are
'' needed to support video and keyboard, and to manage the memory (e.g.
'' virtual ROM can be implemented by denying write-access to the RAM for
'' certain address locations).
''
'' The control cog can be controlled from Spin or PASM to perform various
'' tasks, such as generating a control signals (Reset, NMI, IRQ...),
'' downloading a program, and running that program. A number of debugging
'' features are also implemented: for example you can single-step the 65C02,
'' you can tell it to execute a predetermined number of instructions, or you
'' can interrupt it while it's running at full speed, which is 1MHz on an
'' 80MHz Propeller system, or 1.2MHz on a 100MHz system. You can also run the
'' 65C02 at a lower speed if you wish.
''
'' The following paragraphs explain how the Propeddle software works (see the
'' website for hardware information). You don't need to read this unless
'' you're interested in how all this fits together "inside the box".
'' Reading the sample code and the documentation of the subroutines should be
'' enough to get you started on running your own Software-Defined 6502
'' Computer! 
''
''
'' INITIALIZATION, STATES
'' ======================
'' The Control Cog is started when the Start subroutine is called, and
'' stopped when the Stop routine is called. It can be in one of the following
'' states:
'' - UNINITIALIZED: The Start subroutine was never called before, or the Stop
''   routine was used to shut the module down. In this state, it's possible
''   to Start the control cog (again).
'' - STOPPED: The control cog is accepting or executing commands while the
''   65C02 is on hold. In this state, you can change the signals, stop the
''   control cog or run the 65C02. At this time you can also start any of the
''   cogs that synchronize themselves to the control cog.
'' - RUNNING: The control cog is running the 65C02 at a predetermined speed,
''   and it's not possible to send regular commands, but stopping is
''   possible. Other cogs can change signals to control the 65C02 by changing
''   the hub variable. The control cog will stop running the 65C02 after a
''   predetermined number of clock cycles, or when a pseudo-interrupt is
''   generated (see below).
''
''
'' STOPPED STATE, COMMANDS
'' =======================
'' As soon as the control cog is running, it sets the state to STOPPED and
'' resets the Command in the hub to 0. Then it waits for the command to be
'' changed to something other than 0. As soon as this happens, the control
'' cog starts executing the command. When it's finished with the command, it
'' resets the command to 0 again.
''
'' Commands are the cog address (not the hub address!) of a label to jump to.
''
'' For some commands, the control cog may reset the command BEFORE it starts
'' executing, in cases where there are no side-effects and no result values.
'' The result is that it will seem as if the control cog executes the command
'' faster but takes longer to pick up the next command.
''
'' While the cog is in STOPPED state, any cog can issue a command by waiting
'' for the command to be reset to 0 (indicating that the control cog is ready
'' for new commands) and then setting the command parameters (e.g. address,
'' signals, data bus values) before setting the command. The cog will store
'' any resulting data (if necessary) and will set the command back to 0.
''
'' To prevent multiple cogs from trying to send commands at the same time,
'' the spin code in this module uses a lock. The lock is purely to prevent
'' contention between calling cogs, it's not used by the control cog.
''
'' All commands except RUN are guaranteed to finish within a finite amount
'' of time, so a calling cog can safely use an infinite loop to wait for the
'' command to be reset to 0.
''
'' During the Stop state, the CLK0 output is held HIGH, for compatibility
'' with early 6502 models which were only guaranteed to keep their state
'' if the clock was held high. Nevertheless, the Propeddle hardware was only
'' tested with a 65C02, not with any older 6502 models. Some of the older
'' 6502s have radically different timing requirements (e.g. much longer setup
'' times for the address bus) which are impossible to fullfill with an 80MHz
'' system clock.
''
''
'' RUNNING STATE, INTERRUPTING
'' ===========================
'' The RUN command starts running the 6502 at full speed (or at reduced speed
'' if desired) after it resets the return value in the hub and changes the
'' state. The run loop depends on extremely accurate timing to achieve full
'' speed, so it doesn't check for incoming commands.
''
'' The run loop reads the control signals from the hub and forwards them to
'' the 65C02 on each clock cycle. Other cogs can set the PINT bit in the
'' signals hub variable to force the control cog to break out of the loop and
'' accept commands again (the PINT bit is not sent to the output in this
'' case). This is very easy to accomplish in Spin and is done in the Spin
'' code below.
''
'' Another way to stop the RUN command is to hold the PINT output pin high
'' after the control cog makes the CLK0 output high. The other cog should NOT
'' make the pin high during any other time, so this can only be done in PASM,
'' not in Spin; Spin is too slow to check for the CLK0 and set the PINT
'' output fast enough afterwards. This is why there's no Spin routine to do
'' this.
''
'' The RUN command can be instructed to execute a predetermined number of
'' 65C02 cycles (any number between 1 and $FFFF_FFFF). This makes it possible
'' to do debugging by single-stepping through the program.
''
'' Once the control cog breaks out of the run loop, it updates the return
'' value to indicate how it was stopped, and waits until the calling cog
'' clears the return value. This was done because the calling cog is keeping
'' the lock. The need for the calling cog to clear the result allows it to do
'' other things, and other cogs will still see the control cog as RUNNING.
''
''
'' COOPERATION WITH OTHER COGS, TRACING, VIRTUAL MEMORY
'' ====================================================
'' The control cog generates the timing to multiplex the data bus, address
'' bus and control signals between the Propeller and the 65C02. It generates
'' CLK0 pulses, it sends the control signals from the hub variable to the
'' 65C02 and it connects it to the RAM. The only data from the 65C02 that the
'' control cog is interested in, is the R/!W pin which tells it whether to
'' enable the RAM in Read mode or Write mode.
''
'' For any software-defined computer to be useful, it needs to have some
'' input/output devices. Other cogs can implement these by synchronizing with
'' the control cog, by waiting for output pins (controlled by the control
'' cog) to switch High or Low. This happens at closely timed intervals. The
'' following is basically what can be expected from the control cog, in terms
'' of synchronization with other cogs:
''
'' 1. At the beginning of Phi1, the CLK0 pin changes from high to low. The
''    address bus buffers are enabled.
'' 2. After 2 instructions or so (setup time and propagation time), the
''    address bits can be retrieved for about 2 instruction times. After
''    this, the address lines become unavailable because the address latches
''    are disabled so the pins can be used for the signals.
'' 3. About 8 instruction times after the CLK0 changes from high to low, the
''    control cog activates one of the RAM lines. Other cogs can provide
''    their own functionality (basically implementing "virtual memory" to
''    provide an I/O operation) by ORing the two RAM outputs with 1, and
''    either reading or writing their own databus values from/to the 65C02.
'' 4. The control cog sets the CLK0 output HIGH right after it enables the
''    RAM line. This marks the start of Phi2. The duration of Phi1 is always
''    the same.
'' 5. At the end of the clock pulse, the CLK0 output goes low again to begin
''    Phi1. The Phi2 phase may last any amount of time, at least 10
''    instruction times. After this, the control cog returns the CLK0 output
''    to LOW state. If the control cog is stopped by a pseudo-interrupt or
''    because the cycle counter reaches 0, the 65C02 remains in Phi2 state.
'' 5. During the entire duration of Phi2, the data bus (read or write) is
''    available on pins P0..P7 of the Propeller, and the signal pins that
''    are stored during Phi1 will remain on P8..P15.
''
'' In order to trace the execution of the 65C02, a Trace Cog can be started.
'' The Trace Cog reads the address bus, the data bus and the 65C02 output
'' pins and stores a LONG into hub memory for each 65C02 clock cycle that
'' describes what the 65C02 was doing.
''
'' A Memory Manager Cog can be launched to disable the RAM controls for a
'' given area of the 65C02 memory map, and/or map some hub memory into the
'' 65C02 processor's memory map.  
''
''
'' DOWNLOADING PROGRAMS
'' ====================
'' Whenever the 65C02 is started by a Reset sequence, it will start executing
'' code from memory. To do this, the software has to be there in the first
'' place of course. In "normal" 65C02 computers, this is accomplished with
'' non-volatile memory at the top of the memory map.
''
'' In the Propeddle system, there is no ROM to map into 65C02 memory space.
'' Instead, we have two options: one is to run a Memory Cog that emulates the
'' ROM from hub memory, another is to download code into the RAM (and
'' optionally use a memory cog to prevent overwriting that memory once it's
'' initialized). 
''
'' The 65C02 has sole control over the address bus of the RAM chip, so we use
'' a trick to download data from the hub into RAM (a similar trick can be
'' used to read data from the RAM but this is not implemented for now). We
'' use the fact that the 65C02 only uses the data bus during the second half
'' of each clock cycle (Phi2), and doesn't care about what we put on the data
'' bus during the second half of the clock cycle.
''
'' The Download command of the control cog generates an NMI on the 65C02, and
'' when the 65C02 reads the NMI vector, Propeddle feeds it with the starting
'' address of the memory block to download data into. The 65C02 jumps to this
'' location and starts executing. We feed fake instructions to the 65C02
'' during the second half of each clock cycle, but during the first half of
'' the clock cycle we put the destination bytes on the data bus and write
'' them to the RAM chip. When the address reaches the end of the block, we
'' feed a RTI (return-from-interrupt) instruction to the 65C02.
''
'' The byte that we feed to the 65C02 as fake instruction is $C9. This gets
'' interpreted as a two-byte instruction $C9 $C9, which translates to
'' "CMP #$C9". We could have used $EA ("NOP") instead but NOP is a one-byte,
'' two cycle instruction whereas $C9 $C9 is a two-byte, two-cycle
'' instruction. That means that $C9 is twice as efficient as NOP because the
'' address bus will get incremented by the Program Counter in the 65C02 on
'' every clock pulse, not every other clock pulse.
''
'' The NMI instruction is edge-triggered, unlike the IRQ interrupt which is
'' level-triggered. The Propeller software keeps the NMI signal low for the
'' entire duration of the download, which can be used by external hardware
'' to detect that the Propeller is accessing the RAM.
''
'' By using NMI (not Reset) and CMP instructions (which only affect the
'' status register of the 65C02 and no other registers) followed by RTI
'' (which restores the status register), it's possible to initiate a Download
'' while the 65C02 is running, and let it return to what it was doing before.
'' This can be used as a form of DMA.
''
''
'' TIMING ANALYSIS OF THE MAIN LOOP
'' ================================
'' The main loop contains one hub instruction to retrieve the control signals
'' from the hub. There are 15 other non-hub 4-clock instructions in the loop,
'' plus the WAITCNT instruction which takes at least 5 clocks.
''
'' On the first execution of the loop, it's possible that the hub instruction
'' takes up to 6 instruction times (minus one clock) to execute: The hub
'' takes up to 15 clocks (i.e. 4 instruction times minus one clock) to serve
'' the control cog, and it takes 2 additional instruction times to actually
'' execute it. That means in the worst case (where the hub instruction has
'' to wait 23 clocks), the first 65C02 cycle takes 15*4+5+23=88 clocks.  
''
'' The initialization code may modify the loop so that the WAITCNT
'' instruction is skipped and the loop runs at its maximum speed without
'' waiting. In that case, there are 15 other instructions besides the hub
'' instruction. Including the time to execute the hub instruction itself,
'' that makes 17*4=68 clocks. The next hub access after this will occur 12
'' clocks later (80%16=0), so in this case, the total time to go through one
'' 6502 cycle is exactly 80 clocks, i.e. 20 instructions, i.e. 1 microsecond
'' at 80MHz, or 800ns at 100Mhz.
''
'' If the WAITCNT instruction is part of the loop, and it's tuned to generate
'' the minimum delay of 5 additional clocks, it takes 5 more cycles to
'' execute the loop. So the time between two executions of the hub
'' instruction ends up being 68+5=73 clocks. The next time the cog has hub
'' access is still at 80ns, so the minimum delay for the WAITCNT can be
'' achieved by setting the delay between loops to 80 clocks. However, because
'' the initial run of the loop may take up to 88 clocks, the delay needs to
'' be initialized at 88 clocks.


{
  ACKNOWLEDGMENTS AND SHAMELESS PLUGS:

  The Propeddle project would have been impossible (or at least much harder)
  if it wouldn't have been for the following people and companies, who helped
  me, inspired me and/or encouraged me to make this:
  - Dennis Ferron (Prop-6502 project)
    http://www.parallax.com/tabid/708/Default.aspx
  - Vince Briel (MicroKim and PockeTerm)
    http://www.brielcomputers.com  
  - Chris Savage and everyone else at Parallax and SavageCircuits.com and
    the #savagecircuits IRC channel. 
    http://www.parallax.com
    http://www.savagecircuits.com
  - Jeff Ledger (OldBitCollector) at propellerpowered.com (and savagecircuits
    and GadgetGangster).
    http://www.propellerpowered.com
  - James Neal (@laen) at Dorkbot PDX PCB for getting the circuit boards made.
    http://dorkbotpdx.org/wiki/pcb_order
  - Gadget Gangster for the Propeller Platform boards and the (future)
    cooperation selling Propeddle kits to the masses
    http://www.gadgetgangster.com
  - Brian Riley at The Shoppe at Wulfden and Steve Denson ("jazzed"), for the
    Propalyzer PPLA Digital Logic Analyzer.  
    http://www.wulfden.org/TheShoppe/prop/ppla/index.shtml
    http://forums.parallax.com/showthread.php?110762
  - Addy and Whisker at Toymakers for the mutual "promotional considerations"
    http://www.tymkrs.com
}

CON
  _clkmode = XTAL1 + PLL16X
  _xinfreq = 6_250_000


  '==========================================================================
  ' Pin Assignments

  ' Data bus, during CLK2=1 only
  ' Do not change
  pin_D0     = 0
  pin_D7     = 7

  ' Address bus, when AEN=0 (on), during CLK2=0 only
  ' Do not change
  pin_A0     = 0
  pin_A15    = 15

  ' Latch outputs, when AEN=1 (off) and SLC transitions L->H
  pin_SEL0   = 8  ' (for future expansion)
  pin_SEL1   = 9  ' (for future expansion)
  pin_RAMA16 = 10 ' Extra address line for 128K RAM chip
  pin_NMI    = 11 ' Negative edge during CLK2=0 triggers non-maskable interrupt on 6502
  pin_IRQ    = 12 ' 0=interrupt request on 6502
  pin_RDY    = 13 ' 0=hold the 6502 (read cycle only) for slow devices
  pin_RES    = 14 ' 0=reset the 6502, Reset sequence starts 6 cycles after positive edge 
  pin_SO     = 15 ' 0=set the V flag in the 6502 status register
  
  ' Direct Outputs
  pin_LED    = 19 ' (Optional, otherwise used for audio, video or SYNC)
  pin_RAMOE  = 20 ' 0=RAM reads to databus
  pin_RAMWE  = 22 ' 0=RAM written from databus
  pin_AEN    = 24 ' 0=Enables address bus on P0-P15, during CLK2=0 only
  pin_SLC    = 25 ' Signal Latch Clock (during CLK2=0 only); P8-P15 loaded on low-to-high transition
  pin_SCL    = 28 ' SCL output to EEPROM
  pin_CLK0   = pin_SCL ' EEPROM clock shared with 65C02 clock
  pin_SDA    = 29 ' SDA output to EEPROM, held HIGH to prevent interference
  
  ' Direct Inputs
  pin_SYNC   = 19 ' 1=6502 reads an opcode (Optional, otherwise used for audio, video or debugging LED)
  pin_CLK2   = 21 ' CLK2 from the 6502 (Optional, otherwise used for VGA video)
  pin_RW     = 23 ' 1=6502 reads from databus, 0=6502 writes to databus   

  ' Pseudo-pin that can be used to "interrupt" the control cog when it's
  ' running at full speed:
  ' Any cog can set this bit in the global signals to stop the control cog.
  ' The bit will be reset after the cog stops, before it resets the command.
  ' Setting the bit in the global signals will not set the bit on the outputs
  ' but other cogs that execute assembler can interrupt the control cog by
  ' keeping this pin high at the end of Phi2.  
  pin_PINT   = pin_CLK0
  
  ' Pins reserved for other devices:
  ' VGA: 16, 17, 18, 19*, 21* (VSync, HSync, Blue LSB, Blue MSB*, Green MSB* only), depending on wiring 
  ' TV: 16, 17, 18
  ' Audio or LED: 19 depending on wiring
  ' PS/2 keyboard: 26, 27
  ' EEPROM: 28, 29
  ' Serial port: 30, 31
  '
  ' Note that no pins between 24 and 31 are used by the Propeddle hardware;
  ' this fact is used by the trace cog to format its data (the data bus is
  ' shifted into the high 8 bits where there is normally no relevant
  ' information from the 65C02.
  

  '==========================================================================
  ' Masks for pins
'{{LED
  con_mask_LED     = (|< pin_LED)
'LED}}
{{!LED
  con_mask_LED     = 0
!LED}}

  con_mask_OUTPUTS = con_mask_LED   | (|< pin_RAMOE) | (|< pin_RAMWE)  | (|< pin_AEN) | (|< pin_SLC) | (|< pin_CLK0) | (|< pin_SDA)
  con_mask_SIGNALS = (|< pin_SEL0)  | (|< pin_SEL1)  | (|< pin_RAMA16) | (|< pin_NMI) | (|< pin_IRQ) | (|< pin_RDY)  | (|< pin_RES) | (|< pin_SO)
  con_mask_RESET   = con_mask_SIGNALS & !(|<pin_RES)
  con_mask_RAM     = (|< pin_RAMOE) | (|< pin_RAMWE)
  con_mask_DATA    = $FF
  con_mask_ADDR    = $FFFF


  '==========================================================================
  ' Output bit patterns
              
  
  ' Initial values of output pins at Beginning Of World:
  ' This will hold the 6502 in resetting state.
  ' - CLK0 high
  ' - AEN inactive (high)
  ' - SLC low
  ' - SDA high
  ' - RAM off (high)
  ' - All signals set to 0 (low) so they can be easily OR'ed into this 
  ' The signal latches should be clocked (SLC->high) after sending this to
  ' the outputs, with a one-instruction delay to give the latches some time
  ' to settle.
  ' SDA should always stay high to prevent unexpected EEPROM behavior.
  con_OUT_INIT     = (|< pin_CLK0) | (|< pin_AEN) | (|< pin_SDA) | con_mask_RAM

  ' Initial values for output pins at beginning of Phi1 (first half of cycle)
  ' - CLK0 low
  ' - AEN active (low)
  ' - SLC low
  ' - SDA high
  ' - RAM off (high)
  ' - All signals set to 0 (low) so they can be easily OR'ed into this
  con_OUT_PHI1     = (|< pin_SDA) | con_mask_RAM   

  ' Safe value to set the outputs to when this module is not in use, or
  ' has been stopped.
  ' - CLK0 low (keeps the 65C02 from the databus
  ' - AEN inactive (high), keeps the address bus from the databus and Prop
  ' - SLC low
  ' - SDA high
  ' - RAM off (high)
  ' All others low
  con_OUT_SAFE     = (|< pin_AEN) | (|< pin_SDA) | con_mask_RAM
   
  '==========================================================================
  ' States
  #0
  con_state_UNINITIALIZED
  con_state_STOPPED
  con_state_RUNNING


  '==========================================================================
  ' Timing constants (see timing analysis above)
  con_delay_MAINLOOP_INIT     = 88
  con_delay_MAINLOOP_MINDELAY = 80


  '==========================================================================
  ' Results from the RUN command (bit pattern)
  con_result_RUN_TERMINATED  = (|< 0)                   ' Clock counter reached 0 
  con_result_RUN_INTERRUPTED = (|< 1)                   ' Interrupted


DAT
' Global data
'
' Note, there can only be one control cog no matter how many times you
' instantiate the object. Therefore this data is in a DAT block, not a VAR
' block.

  ' These are only used by the Spin code
  g_controlcogid        long    -1                      ' Control Cog ID (there can be only one)
  g_busylock            long    -1                      ' Lock ID for lock that protects command
  g_tracecogid          long    -1                      ' Cog ID for Trace Cog
  g_memcogid            long    -1                      ' Cog ID for Memory Cog
  
  
  ' Global variables are transferred back and forth to/from the control hub as needed
  ' For most commands, only one or a few of these are needed, so it might be possible
  ' to reduce the number of variables; however it's easier to understand how the
  ' program works if overlap is minimized. In other words: the value of these
  ' variables pretty much always means the same thing but sometimes the data goes
  ' TO the control hub, and sometimes it comes FROM the control hub; this should be
  ' obvious from the name of the command. 
  g_state               long    con_state_UNINITIALIZED ' Current state, don't use in loops!
  g_cmd                 long    0                       ' Current command, protected by busy-lock
  g_retval              long    0                       ' Result from previous command
  g_signals             long    con_MASK_SIGNALS        ' Signals for command
  g_addr                long    0                       ' Address bus for command
  g_data                long    0                       ' Data bus for command
  g_hubaddr             long    0                       ' Hub address for command
  g_hublen              long    0                       ' Length of hub area for command
  g_counter             long    0                       ' Counter for e.g. limited clock run
  g_cycletime           long    0                       ' Clock cycle time (normally 1_000_000)                 


' ROM image
  '                  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
  romimage    byte $EE, $F9, $FF, $4C, $F0, $FF, $00, $00, $00, $00, $F0, $FF, $F0, $FF, $F0, $FF
  romend      byte

    
PUB Start
'' Starts the control cog and waits until it's initialized.
''
'' If the control cog is already started, the command is ignored.
'' If successful, the lock ID will be set to a value other than -1,
'' the cog ID will be set to a value other than -1 and the
'' 6502 will be in stopped state; all signals are HIGH.

  ' If the control cog is already running, ignore command
  if (g_state == con_state_UNINITIALIZED)

    g_busylock := locknew
    if (g_busylock => 0)
      lockclr(g_busylock)

      ' Initialize parameters to download into cog
      parm_pState      := @g_state
      parm_pCmd        := @g_cmd
      parm_pRetval     := @g_retval
      parm_pSignals    := @g_signals
      parm_pAddr       := @g_addr                                      
      parm_pData       := @g_data
      parm_pHubAddr    := @g_hubaddr
      parm_pHubLen     := @g_hublen
      parm_pCounter    := @g_counter
      parm_pCycleTime  := @g_cycletime

      ' Fire up the cog and wait until it's running
      g_cmd            := -1 ' Set command to a dummy value          
      g_controlcogid   := cognew(@ControlCog, 0)
      if (g_controlcogid => 0)
        ' Wait until the control cog resets the command
        repeat until g_cmd == 0
      else
        lockret(g_busylock)
       

PUB Stop
'' Sends the Shutdown command to the control cog and waits until it's done.
'' This stops the control cog. Use Start to reinitialize.

  if (g_state <> con_state_UNINITIALIZED)
    ' If the cog is running at full speed, get it back to STOPPED state
    RunEnd

    ' Tell control cog to clean up the 6502 state for shutdown
    Open
    SendCommand(@CmdShutDown)

    repeat until g_cmd == 0

    StopTrace
    'StopMem
        
    ' At this point, the cog is waiting to be stopped
    cogstop(g_controlcogid)
  
    ' Return the lock
    lockclr(g_busylock)
    lockret(g_busylock)

    g_busylock := -1
    g_controlcogid := -1


PUB LedOn
'' Switch the LED on

  if (g_state == con_state_STOPPED)
    WaitSendCommand(@CmdLedOn)


PUB LedOff
'' Switch the LED off

  if (g_state == con_state_STOPPED)
    WaitSendCommand(@CmdLedOff)


PUB LedToggle
'' Toggle the LED

  if (g_state == con_state_STOPPED)
    WaitSendCommand(@CmdLedToggle)


PUB GetIna
'' Get value of control cog's INA register

  if (g_state == con_state_STOPPED)
    result := WaitSendCommand(@CmdGetIna)

        
PUB GetOuta
'' Get value of control cog's OUTA register

  if (g_state == con_state_STOPPED)
    result := WaitSendCommand(@CmdGetOuta)

        
PUB SetSignal(pin, high)
'' Changes a signal pin
'' The first parameter is the pin number. Should be one of pin_...:
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
'' Set all signals (not recommended)

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
'' Gets all current signals (not recommended)

  return g_signals

  
PUB DisconnectI2C
'' Temporarily disconnects the I2C bus to allow access to the EEPROM
'' This can only be done in stop mode. When the next command is issued,
'' the 65C02 is reconnected to the I2C bus.
'' Any cogs that synchronize to the main cog should be stopped first.

  if (g_state == con_state_STOPPED)
    WaitSendCommand(@CmdDisconnectI2C)
    

PUB Run(parm_cycletime, parm_numcycles)
'' Runs the 65C02 for the specified number of cycles at the given number
'' of system cycles per 65C02 cyle. If the speed exceeds the maximum, it's
'' reduced.
'' After this, the same cog has to call the RunWait, RunEnd or Stop routine;
'' other cogs are blocked from executing commands.
'' The calling cog will own the lock.

  if (g_state == con_state_STOPPED)
    Open

    g_cycletime := parm_cycletime
    g_counter := parm_numcycles

    SendCommand(@CmdRun)  


PUB RunWait(timeout) | timer
'' In running state, wait until the control cog stops, or the timeout
'' in Propeller cycles.
'' The lock will be freed afterwards if the control cog stopped within the
'' timeout

  if (g_state == con_state_RUNNING)
    timer := cnt

    repeat while ((cnt - timer) < timeout) and (g_retval == 0)

    result := g_retval ' 0 means timeout
    
    if (result <> 0)
      g_retval := 0

      Close
    

PUB RunEnd
'' Stops the control cog if it is running by forcing a pseudo-interrupt via
'' the signals.
'' The lock will be freed afterwards 

  if (g_state == con_state_RUNNING)
    ' Generate pseudo-interrupt
    g_signals |= (|< pin_PINT)

    repeat while (g_retval == 0)

    g_signals &= !(|< pin_PINT)
    
    result := g_retval
    g_retval := 0

    Close

    
PUB IsStarted
'' Returns TRUE if the control cog is started

  return (g_state <> con_state_UNINITIALIZED)


PUB StopTrace
'' Stops the Trace cog if it is running

  if (g_tracecogid <> -1)
    cogstop(g_tracecogid)

  g_tracecogid := -1

  
PUB StartTrace(parm_hubaddr, parm_hublen) | done
'' Clears the given area of hub memory and starts the trace cog.
'' If it's already running, it's stopped first

  StopTrace
  
  longfill(parm_hubaddr, 0, parm_hublen)

  trace_parm_HubAddr := parm_hubaddr
  trace_parm_HubLen  := parm_hublen

  done := false
  g_tracecogid := cognew(@TraceCog, @done)
  repeat until done


{{PUB StopMem
'' Stop the memory manager cog

  if (g_memcogid <> -1)
    cogstop(g_memcogid)

  g_memcogid := -1


PUB StartMem(parm_startaddr, parm_hubaddr, parm_hublen) | done
'' Start memory manager cog

  StopMem

  done := false
  mem_parm_StartAddr := parm_startaddr
  mem_parm_HubAddr := parm_hubaddr
  mem_parm_HubLen := parm_hublen
  g_memcogid := cognew(@MemoryCog, @done)
  repeat until done
  
 }} 
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
  repeat while g_cmd == cmdtosend

  result := g_retval
  

PRI WaitSendCommand(cmdtosend)
' Sends the given command without parameters and without results
'
' Waits for the lock and releases the lock afterwards

  Open
  result := SendCommand(cmdtosend)
  Close


DAT
'============================================================================
' Control Cog code starts here


                        org     0
ControlCog
'                       ' Init direction register
                        mov     DIRA, dir_INIT

                        ' Initialize all outputs except signals
                        mov     OUTA, out_INIT

                        ' Fall through
'============================================================================
' Command fetching loop

                        
SetStopState
                        ' Initialize state
                        mov     state, #con_state_STOPPED 
                        wrlong  state, parm_pState

CmdSignals                        
                        ' Read signals from the hub and put them out
                        call    #UpdateSignals                        

CommandDone
                        ' Signal that we're done with current command
                        mov     cmd, #0
                        wrlong  cmd, parm_pCmd                        

                        ' At this point, other cogs may read results, set
                        ' new values and issue a new command.
                        
                        ' Get command and execute it
GetCommand              rdlong  cmd, parm_pCmd wz
ProcessCommand          movs    :jmptocommand, cmd
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

                        
CmdGetIna               mov     retval, INA   
                        wrlong  retval, parm_pRetVal
                        jmp     #CommandDone


CmdGetOuta              mov     retval, OUTA
                        wrlong  retval, parm_pRetVal
                        jmp     #CommandDone
                                                                                                 

'============================================================================
' Helper subroutine: Update signals


UpdateSignals
                        rdlong  signals, parm_pSignals
SendSignals                        
                        and     signals, mask_SIGNALS
                        andn    OUTA, mask_SLC_SIGNALS
                        or      OUTA, signals
                        nop                             ' Do not remove
                        or      OUTA, mask_SLC          ' Clock the flipflops

UpdateSignals_Ret
SendSignals_Ret
                        ret

                        
'============================================================================
' Shut down
                        
CmdShutDown
                        mov     OUTA, out_INIT
                        nop
                        or      OUTA, mask_SLC

                        ' Change state back to UNINITIALIZED so we can be
                        ' restarted
                        mov     state, #con_state_UNINITIALIZED
                        wrlong  state, parm_pState

                        ' Signal that we're done with the command                        
                        mov     cmd, #0
                        wrlong  cmd, parm_pCmd

                        ' The caller is responsible for stopping the cog
                        ' Alternatively, the command can be set to a nonzero
                        ' value to restart the control cog. This might be
                        ' useful in case the hub copy of this code gets
                        ' overwritten to reuse the memory for other purposes
                        ' Of course, when restarting, the parameters aren't
                        ' reinitialized because the code is not loaded from
                        ' hub memory. Normally this should not be a problem.
:shutdownloop
                        rdlong  cmd, parm_pCmd wz
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
                        andn    signals, mask_RDY
                        call    #SendSignals

                        ' Disable the outputs until the next command
                        andn    DIRA, mask_I2C

                        ' Reset command
                        mov     cmd, #0
                        wrlong  cmd, parm_pCmd

                        ' Read new command until there is one
:loop                   rdlong  cmd, parm_pCmd wz                        
              if_z      jmp     #:loop

                        ' Reset the direction register
                        mov     DIRA, dir_INIT

                        ' Reset the signals
                        call    #UpdateSignals

                        ' Set the state
                        mov     state, #con_state_STOPPED
                        wrlong  state, parm_pState
                        
                        ' Process the command
                        jmp     #ProcessCommand                          
                        

'============================================================================
' Download data from the hub to the RAM

CmdDownload
                        ' Initialize parameters
                        rdlong  hubaddr, parm_pHubAddr
                        rdlong  hublen, parm_pHubLen wz
                        rdlong  startaddr, parm_pAddr
                        rdlong  cycletime, parm_pCycleTime
                        
                        ' If nothing to do, return
              if_z      jmp     #CommandDone
              
                        ' Initialize timer
                        min     cycletime, #con_delay_MAINLOOP_MINDELAY

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
                        mov     addr, INA
                        and     addr, mask_ADDR

                        ' Disable address latches                                
                        or      OUTA, mask_AEN

                        ' If the address matches the currently expected
                        ' address, jump to the currently defined state
                        cmp     addr, expectedaddr wz
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
                        add     clock, cycletime
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
                        andn    signals, mask_NMI
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
                        rdbyte  data, hubaddr

                        ' Put data from hub on data bus
                        or      OUTA, data
                        or      DIRA, mask_DATA

                        ' Activate the RAM
                        andn    OUTA, mask_RAMWE

                        ' Wait for RAM to store the data
                        ' Meanwhile, do some housekeeping
                        add     hubaddr, #1
                        sub     hublen, #1 wz
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
                        or      signals, mask_NMI
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


CmdRun
                        ' Read the time that each clock cycle should take
                        ' Store this in the clock counter which is used for
                        ' the waitcnt instructions.
                        ' Make sure the value is at least equal to the
                        ' minimum execution time for the first loop.
                        ' The actual value of the system clock is added as
                        ' last instuction before jumping into the loop.
                        rdlong  cycletime, parm_pCycleTime
                        min     cycletime, #con_delay_MAINLOOP_MINDELAY wc

                        ' If the cycle time is less than the minimum, skip
                        ' the WAITCNT instructions
              if_c      movs    LoopIns, #NoWaitMainLoop
              if_nc     movs    LoopIns, #MainLoop
                        muxnc   DropOutIns, mux_NEVER_TO_ALWAYS

                        ' Initialize the clock to cycle time, but minimize
                        ' this by the minimum time for the first cycle
                        ' Note, CNT is added just before jumping into the
                        ' loop.      
                        mov     clock, cycletime
                        min     clock, #con_delay_MAINLOOP_INIT

                        ' Read the number of clock cycles to execute.
                        ' Depending on whether the count is 0, enable or
                        ' disable the check at the end of the loop.
                        ' In other words, if z=1 here, change the
                        ' if_nc_and_nz condition to if_nc by setting the
                        ' given bits 
                        rdlong  counter, parm_pCounter wz
                        muxz    LoopIns, mux_NCANDNZ_TO_NC

                        ' Initialize return value
                        mov     retval, #0
                        wrlong  retval, parm_pRetVal
                        
                        ' Set the state to Running
                        mov     state, #con_state_RUNNING
                        wrlong  state, parm_pState
                        
                        ' Add the system clock to the local clock. This
                        ' should be done just before jumping into the loop.
                        add     clock, CNT
                        jmp     #NoWaitMainLoop
                        

'============================================================================
' Main loop: generate clock cycles to let the 65C02 run its program

' NOTE: The following code was meticulously constructed to generate a loop
' that executes at 1MHz when the Propeller runs at 80MHz. When the Propeller
' runs at 100MHz, the 65C02 can be run at up to 1.25MHz.
' The timing was based on the 65C02 datasheet from Western Design Center.
' This may NOT run correctly on older (NMOS) 6502s because they may have
' different timing requirements: especially the setup times at the start
' of Phi1 are much longer for the original 6502 than for the 65C02.


MainLoop
't=16..20 on first run
't=16..18 on subsequent runs
                        ' Wait for the end of the requested cycle time
                        ' Initialization may change the JMP at the end of the
                        ' loop so that this instruction is skipped.
                        waitcnt clock, cycletime
NoWaitMainLoop
't>21 after 1 cycle with waitcnt
't>19 on subsequent cycles with waitcnt
't=19 without waitcnt
                        ' Start Phi1 by setting the clock low.
                        ' At the same time, initialize all the other outputs
                        ' so that the RAM is disabled, the clock for the
                        ' signal latches is primed, and all signal bits are
                        ' set to 0 so the signals from the hub can be ORed
                        ' with them.
                        mov     OUTA, out_PHI1
't=0
                        ' The 74*244 bus drivers are also enabled with the
                        ' previous instruction, but we have to wait for the
                        ' 65C02 to generate the address (setup time), and for
                        ' the '244s to forward the address to us (propagation
                        ' delay). We use this time to change the direction of
                        ' the address bus pins and to test if no other cog is
                        ' holding the PINT pin HIGH to interrupt us.
                        ' There may be a short timespan during which both
                        ' the '244s and the Propeller drive the pins, but
                        ' this only happens for a few nanoseconds so it
                        ' shouldn't cause any damage.
                        andn    DIRA, mask_SIGNALS
                        test    INA, mask_PINT wc       ' c=1 for interrupted
              if_c      jmp     #EndMainLoop
't=3
                        ' Deactivate the address latches again and make the
                        ' signal pins outputs again.
                        ' By now, any other cogs that want to read the
                        ' address should have had enough time to do so.
                        or      OUTA, mask_AEN
                        or      DIRA, mask_SIGNALS
't=5
                        ' The signals were retrieved during the previous
                        ' clock cycle. Put them on the output pins now.
                        ' We output the signals first and then we transfer
                        ' the clock on the 74*374 to HIGH to let it forward
                        ' the signals to the 65C02.
                        ' The flipflops need a little bit of time to settle,                                 
                        ' so also check whether the 65C02 is in a read or a
                        ' write operation here.
                        ' Note, the signal pins will stay on the outputs
                        ' for the remainder of the clock cycle, so other
                        ' cogs can inspect those pins instead of reading the
                        ' value from the hub to find out which signals were
                        ' last sent to the 65C02.
                        or      OUTA, signals       
                        test    INA,  mask_RW wc        ' c=0 write, c=1 read                                                                      
                        or      OUTA, mask_SLC                        
't=8
                        ' Enable the RAM depending on the R/!W output of the
                        ' 65C02.
                        ' Any cogs that want to inhibit access to the RAM
                        ' chip (e.g. because they want to read or write
                        ' data directly from/to the 65C02 or they guard the
                        ' ROM area of memory against writing or they map an
                        ' I/O chip into the 65C02's memory) can do so before
                        ' this time, by making their own RAM outputs HIGH.
              if_c      andn    OUTA, mask_RAMOE        ' RAM to 65C02
              if_nc     andn    OUTA, mask_RAMWE        ' 65C02 to RAM
't=10
                        ' Start Phi2 by setting the clock high.
                        ' When running at full speed (no waitcnt) on an 80MHz
                        ' Propeller, Phi1 is about 13*50=650ns; on a 100MHz 
                        ' Propeller, it's about 13*40=520ns. Both are safely
                        ' within the limits of the 65C02 specs.
                        or      OUTA, mask_CLK0
't=11
                        ' There's not a whole lot that we need to do during
                        ' Phi2: this is when the 65C02 does its work.
                        ' We use this time to retrieve the signals from the
                        ' hub so we can send them to the 65C02 during the
                        ' next clock cycle.
                        ' See above for timing analysis
                        rdlong  signals, parm_pSignals
't=13..17 on first cycle
't=13..15 on subsequent cycles with waitcnt
't=16 on subsequent cycles without waitcnt (see timing analysis)
                        ' The signals variable in the hub should only contain
                        ' bits that pertain to the signals (or PINT, see
                        ' below), otherwise unexpected results will occur
                        ' when these are ORed to the outputs during the next
                        ' clock cycle.
                        ' The signals may also have the PINT pseudo-pin set
                        ' to signal to this cog that it needs to stop
                        ' running. This pseudo-pin is not sent to the output
                        ' but is tested here. This mechanism makes it easier
                        ' for cogs running in Spin to interrupt the control
                        ' cog, because they aren't fast enough to set the
                        ' output pin safely (by waiting for us to change
                        ' the CLK0 from LOW to HIGH and then setting it on
                        ' their own outputs, which is what PASM cogs can do)
                        ' Test for the pseudo-pin here and leave the loop if
                        ' necessary
                        test    signals, mask_PINT wc   ' c=1 for interrupt                          
't=14..18(16)/17
                        ' It's possible to run a predetermined number of
                        ' clock cycles and then terminate the loop.
                        ' We decrement and test the counter here.                                                                        
                        sub     counter, #1 wz          ' z=1 for terminated
't=15..19(17)/18
                        ' The JMP instruction conditionally jumps back to
                        ' the beginning, to wait for the system timer.
                        ' If the maximum number of instructions has been
                        ' reached, or another cog set the PINT bit in the
                        ' signals storage in the hub, we bail out.
                        ' The initialization code may override the condition
                        ' bits in the instruction to ignore the counter (it
                        ' will still count, but the main loop will keep going
                        ' even when the counter wraps around).
                        ' The initialization code may also override the
                        ' source part of the instruction to skip over the
                        ' WAITCNT instruction at the beginning of the loop,
                        ' to make the loop run as fast as possible.
LoopIns                         
        if_nc_and_nz    jmp     #MainLoop
't=16..20(18)/19


                        ' We dropped out of the loop
                        ' Make sure the last cycle's duration is the same
                        ' as all other cycles
DropOutIns              waitcnt clock, cycletime
        
EndMainLoop
                        ' Make sure the pins have the correct direction and
                        ' value.
                        ' Because we set AEN at the beginning of Phi1,
                        ' the address latches are enabled for a short time.
                        ' This should not be a problem as long as other cogs
                        ' don't depend on AEN.
                        mov     DIRA, dir_INIT
                        mov     OUTA, out_INIT

                        ' Store the counter back into the hub
                        wrlong  counter, parm_pCounter
                        
                        ' The Z flag was set by the loop if it was terminated
                        ' after a predetermined number of instructions, and
                        ' the C flag was set if the code detected the
                        ' PINT pseudo-interrupt either as a pin held high
                        ' after the end of Phi2, or as a bit set in the
                        ' signals.
                        mov     retval, cmd
                        muxz    retval, #con_result_RUN_TERMINATED
                        muxc    retval, #con_result_RUN_INTERRUPTED
                        wrlong  retval, parm_pRetVal

                        ' Read the return value back and wait until the
                        ' calling cog resets it
:loop                   rdlong  retval, parm_pRetVal wz
              if_nz     jmp     #:loop
                                                                       
                        ' Finally, change the state and receive next command              
                        jmp     #SetStopState                                  


'============================================================================
' Working variables

                        ' Local versions of hub variables                                      
state                   long    0
cmd                     long    0
retval                  long    0
signals                 long    0
addr                    long    0        
data                    long    0
hubaddr                 long    0
hublen                  long    0
clock                   long    0
cycletime               long    0
counter                 long    0

                        ' Download working variables
startaddr               long    0
expectedaddr            long    0
feedbyte                long    0
                        

'============================================================================
' Constants

                        ' Output Initializers
out_INIT                long    con_OUT_INIT    ' Initial
out_PHI1                long    con_OUT_PHI1    ' Start of clock cycle

                        ' Bitmask to change an instruction with an
                        ' "if_nc_and_nz" condition (%0001) to an
                        ' "if_nc" condition (%0011) or vice versa
                        ' using a MUX instruction
mux_NCANDNZ_TO_NC       long    %000000_0000_0010_000000000_000000000

                        ' Bitmask to change an instruction with an
                        ' "if_never" condition (%0000) to an
                        ' "if_always" condition (%1111) or vice versa
                        ' using a MUX instruction
mux_NEVER_TO_ALWAYS     long    %000000_0000_1111_000000000_000000000
                        
                        ' Initial direction registers
dir_INIT                long    con_mask_OUTPUTS | con_mask_SIGNALS
                                                  
                        ' Other bitmasks used in the program
mask_SIGNALS            long    con_mask_SIGNALS     
mask_SLC                long    (|< pin_SLC)
mask_SLC_SIGNALS        long    (|< pin_SLC) | con_mask_SIGNALS
mask_LED                long    con_mask_LED
mask_RAMOE              long    (|< pin_RAMOE)
mask_RAMWE              long    (|< pin_RAMWE)        
mask_RAM                long    (|< pin_RAMOE) | (|< pin_RAMWE)
mask_AEN                long    (|< pin_AEN)
mask_AEN_CLK0           long    (|< pin_AEN) | (|< pin_CLK0)
mask_RW                 long    (|< pin_RW)
mask_CLK0               long    (|< pin_CLK0)
mask_PINT               long    (|< pin_PINT)
mask_RDY                long    (|< pin_RDY)
mask_I2C                long    (|< pin_SCL) | (|< pin_SDA)

                        ' Constants for download
vector_NMI              long    $FFFA
mask_ADDR               long    $FFFF
mask_DATA               long    $FF
mux_Z_TO_ALWAYS         long    %000000_0000_0101_000000000_000000000 ' %1010 to %1111
mask_NMI                long    (|< pin_NMI)        
                                

'============================================================================
' Parameters

parm_pState             long    0               ' Pointer to state
parm_pCmd               long    0               ' Pointer to command
parm_pRetval            long    0               ' Pointer to result
parm_pSignals           long    0               ' Pointer to signals
parm_pAddr              long    0               ' Pointer to 6502 address       
parm_pData              long    0               ' Pointer to 6502 data (bus)
parm_pHubAddr           long    0               ' Pointer to hub address        
parm_pHubLen            long    0               ' Pointer to hub length
parm_pCounter           long    0               ' Pointer to counter
parm_pCycleTime         long    0               ' Pointer to cycle time        


'============================================================================
' End

                        fit

DAT
'============================================================================
' Trace cog starts here

' The optional Trace cog can be used to single-step the 6502 and read the
' address bus and data bus as you go along, or run at full speed and store
' the address and data bus values on hub memory for each clock pulse.
'
' The cog can be started and stopped at any time as long as the control cog
' is active. The parameters have to be filled in before firing up a cog.
' The trace cog doesn't stop by itself.
'
' The data that's stored in the hub has the following format:
' - Bits 31..24 are the original bits 23..16 shifted to the left by 8 bits
' - Bits 23..8  are the address bus
' - Bits 7..0   are the data bus
' - Signal data is not traced here
'
' IMPORTANT! The data is stored with one clock cycle time delay. The first
' clock cycle's information is stored during the second clock cycle.

                        org     0
                        
TraceCog
                        ' Let the caller know we're running
                        wrlong  trace_ffffffff, PAR
                        
                        ' Set the C flag to skip the hub instructions
                        ' during the first iteration
                        sub     trace_zero, #1 nr,wc

                        ' Start by waiting until the clock is high, so
                        ' the next wait gets triggered right at the start
                        ' of the clock going low.
                        waitpeq trace_mask_CLK0, trace_mask_CLK0
TraceLoop
                        ' Wait for the start of Phi1                        
                        waitpeq trace_zero, trace_mask_CLK0

                        ' At this point the control cog has started the
                        ' clock cycle and has enabled the 74*244 address bus
                        ' buffers.
                        ' We need to wait for the setup time of the 65C02
                        ' and the propagation delay of the 74*244s.
                        ' We use this time to update the available hub space
                        cmp     trace_parm_HubLen, #0 wz
        if_nz_and_nc    sub     trace_parm_HubLen, #1

                        ' Now get the address from the 65C02
                        ' The top 16 bits are garbage at this time
                        mov     trace_addr, INA

                        ' Send the data to the hub if necessary
                        ' This may take up to 6 instruction times
                        ' On the first iteration of the loop, the instruction
                        ' is skipped because C=1 
        if_nz_and_nc    wrlong  trace_data, trace_parm_HubAddr
              
                        ' Now wait until the second half of the clock cycle
                        ' In the worst case of the previous hub instruction,
                        ' the following doesn't have to wait.
                        waitpeq trace_mask_CLK0, trace_mask_CLK0

                        ' Wait for a little while before picking up the
                        ' data bus. During that time, shift the result to
                        ' make space
                        shl     trace_addr, #8
                        
                        ' Get the data bus and store it
                        mov     trace_data, INA
                        and     trace_data, trace_mask_DATA
                        or      trace_data, trace_addr

                        ' Increment the hub address to the next long
                        ' Also clear the C flag so the value is stored on
                        ' the next iteration
              if_nz     add     trace_parm_HubAddr, #4 wc ' C=0

                        jmp     #TraceLoop              ' Infinite loop

                        
'============================================================================
' Constants

trace_zero              long    0
trace_ffffffff          long    $FFFF_FFFF
trace_mask_CLK0         long    (|< pin_CLK0)
trace_mask_DATA         long    con_mask_DATA
trace_mask_LED          long    (|< pin_LED)              

'============================================================================
' Working variables

trace_addr              long    0
trace_data              long    0


'============================================================================
' Parameters

trace_parm_HubAddr      long    0
trace_parm_HubLen       long    0

                        fit

DAT
'============================================================================
' RAM Control Cog starts here
'
' The following PASM code can be used to control the on-board RAM. When it
' starts, it builds a table of 256 DWORDS at the start of cog memory, each
' containing 16 two-bit values that are sent to the RAMWR and RAMOE outputs
' depending on the address that's read from the 6502 when AEN is active.
' This makes it possible to divide memory into sections of 16 bytes each.
' Each section can either be designated as RAM, ROM or unmapped. When an
' area is mapped as ROM, the cog makes the RAMWE output HIGH whenever an
' address of that area is used, overriding any other cogs that want to make
' it low, and effectively denying the write. For areas that are marked as
' unmapped, both RAMOE and RAMWR are marked high so no other cogs can access
' the RAM at all. Unmapped memory areas can be used by physical I/O devices
' on the expansion bus or by emulated devices on other cogs of the Propeller.
' The cog can be stopped at any time, which will result in the 6502 accessing
' its entire memory area as RAM.

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
                        
:loop                        
:clearstep              mov     255, #0
                        sub     :clearstep, RAMoned
                        djnz    RAMcounter, #:loop                        

















'============================================================================
' Variables

RAMcounter              long    256
RAMoned                 long    %1_000000000

                                                        
                        ' Let the caller know we're running
                        wrlong  mem_ffffffff, PAR
                        
                        mov     DIRA, mem_dir_INIT
                        
                        mov     mem_hubend, mem_parm_HubLen
                        add     mem_hubend, #1
                        
                        ' Calculate offset from 65C02 address to hub address
                        mov     mem_offset, mem_parm_HubAddr
                        sub     mem_offset, mem_parm_StartAddr
                        
                        ' Start by waiting until the clock is high, so
                        ' the next wait gets triggered right at the start
                        ' of the clock going low.                        
                        waitpeq trace_mask_CLK0, trace_mask_CLK0
MemoryLoop
                        ' Wait until start of Phi1
                        waitpeq mem_zero, trace_mask_CLK0

                        ' We need to wait for the setup time of the 65C02 and
                        ' propagation delay of the 74*244s.
                        ' During that time, reset the direction register
                        ' in case of a previous write to pins, and reset the
                        ' output register. 
                        andn    DIRA, mem_mask_DATA
                        mov     OUTA, #0                ' Most bits are disabled anyway

                        ' Get the address and the R/!W pin, then mask out
                        ' all irrelevant bits
                        mov     mem_addr, INA
                        test    mem_addr, mem_mask_RW wz ' Z=1 read from pins&write to hub                                                                       
                        and     mem_addr, mem_mask_ADDR

                        ' Test if the address is in range. If not, wait for
                        ' the next cycle
                        sub     mem_addr, mem_parm_StartAddr wc
              if_nc     cmp     mem_hubend, mem_addr wc

                        ' Just in time to disable the RAM
              if_nc     or      OUTA, mem_mask_RAM

                        ' Convert the address to a hub address
              if_nc     add     mem_addr, mem_offset

                        ' When writing to pins, change the direction
                        ' register, read the hub byte and send it to the output
                        ' Otherwise, this only takes 3 instruction times
        if_z_and_nc     or      DIRA, mem_mask_DATA
        if_z_and_nc     rdbyte  mem_data, mem_addr
        if_z_and_nc     or      OUTA, mem_data

                        ' When reading from pins, read the byte and store it
                        ' in the hub
                        ' Otherwise, this only takes 2 instruction times
        if_nz_and_nc    mov     mem_data, INA
        if_nz_and_nc    wrbyte  mem_data, mem_addr                        

                        jmp     #MemoryLoop
                                                                                              

'============================================================================
' Constants

mem_zero                long    0
mem_ffffffff            long    $FFFF_FFFF
mem_dir_INIT            long    con_mask_RAM
mem_mask_DATA           long    con_mask_DATA
mem_mask_RW             long    (|< pin_RW)
mem_mask_ADDR           long    con_mask_ADDR
mem_mask_RAM            long    con_mask_RAM


'============================================================================
' Working variables

mem_addr                long    0
mem_offset              long    0
mem_hubend              long    0
mem_data                long    0     

'============================================================================
' Parameters

mem_parm_StartAddr      long    0
mem_parm_HubAddr        long    0
mem_parm_HubLen         long    0

'============================================================================
' End
RAMrelocatedEnd
                        fit
                                                                                                 