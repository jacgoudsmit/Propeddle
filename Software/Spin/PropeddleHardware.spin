''***************************************************************************
''* Propeddle hardware module (Hardware Revision 8)
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
''
'' (Note: documentation under construction, this may not be accurate)
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
  - Vince Briel (MicroKim, PockeTerm, Superboard III and many others)
    http://www.brielcomputers.com  
  - Chris Savage and everyone else at Parallax and SavageCircuits.com and
    the #savagecircuits IRC channel. 
    http://www.parallax.com
    http://www.savagecircuits.com
  - Jeff Ledger (OldBitCollector) at propellerpowered.com (and savagecircuits
    and GadgetGangster).
    http://www.propellerpowered.com
  - James Neal (@laen) at OSHPark for getting the circuit boards made.
    http://www.oshpark.com
  - Gadget Gangster for the Propeller Platform boards
    http://www.gadgetgangster.com
  - Emile Petrone at Tindie
    http://www.tindie.com
  - Brian Riley at The Shoppe at Wulfden and Steve Denson ("jazzed"), for the
    Propalyzer PPLA Digital Logic Analyzer.  
    http://www.wulfden.org/TheShoppe/prop/ppla/index.shtml
    http://forums.parallax.com/showthread.php?110762
  - Addy and Whisker at Toymakers for the mutual "promotional considerations"
    http://www.tymkrs.com
}

CON

  '==========================================================================
  ' Pin Assignments

  ' Data bus, during CLK0=1 only
  ' Do not change
  pin_D0     = 0
  pin_D1     = 1
  pin_D2     = 2
  pin_D3     = 3
  pin_D4     = 4
  pin_D5     = 5
  pin_D6     = 6
  pin_D7     = 7

  ' Address bus, when AEN=0 (on), during CLK0=0 only
  ' Do not change
  pin_A0     = 0
  pin_A1     = 1
  pin_A2     = 2
  pin_A3     = 3
  pin_A4     = 4
  pin_A5     = 5
  pin_A6     = 6
  pin_A7     = 7
  pin_A8     = 8
  pin_A9     = 9
  pin_A10    = 10 
  pin_A11    = 11 
  pin_A12    = 12 
  pin_A13    = 13 
  pin_A14    = 14 
  pin_A15    = 15

  ' Latch outputs, when AEN=1 (off) and SLC transitions L->H
  pin_CRES   = 8  ' 1=reset the 6502, Reset sequence starts 6 cycles after negative edge
  pin_CNRDY  = 9  ' 1=hold the 6502 (read cycle only) for slow devices
  pin_CSO    = 10 ' 1=set the V flag in the 6502 status register
  pin_CIRQ   = 11 ' 1=interrupt request on 6502
  pin_CNBE   = 12 ' 1=disconnect the CPU from the bus (WDC only!)
  pin_CNMI   = 13 ' Positive edge during CLK0=0 triggers non-maskable interrupt on 6502
  pin_CSETUP = 14 ' I/O setup pin on expansion bus   
  pin_CRAMA16= 15 ' Extra address line for 128K RAM chip
  
  ' Direct Outputs
  pin_LED    = 20 ' May also be used for VGA or as debug input, depending on jumpers
  pin_RAMOE  = 21 ' 0=RAM reads to databus
  pin_RAMWE  = 22 ' 0=RAM written from databus
  pin_AEN    = 24 ' 0=Enables address bus on P0-P15, during CLK0=0 only
  pin_SLC    = 25 ' Signal Latch Clock (during CLK0=0 only); P8-P15 loaded on low-to-high transition
  pin_SCL    = 28 ' SCL output to EEPROM
  pin_CLK0   = pin_SCL ' EEPROM clock shared with 65C02 clock
  pin_SDA    = 29 ' SDA output to EEPROM, held HIGH to prevent interference
  
  ' Direct Inputs
  pin_DEBUG  = pin_LED ' SYNC or CLK2 can be jumpered here; also used for LED or VGA
  pin_RW     = 23 ' 1=6502 reads from databus, 0=6502 writes to databus   

  ' Pseudo-pin that can be used to "interrupt" the control cog when it's
  ' running at full speed:
  ' Any cog can set this bit in the global signals to stop the control cog.
  ' The bit will be reset after the cog stops, before it resets the command.
  ' Setting the bit in the global signals will not set the bit on the outputs
  ' but other cogs that execute assembler can interrupt the control cog by
  ' keeping this pin high at the end of Phi2.  
'  pin_PINT   = pin_CLK0
  
  ' Pins reserved for other devices:
  ' VGA: 16, 17, 18, 19, 20 (VSync, HSync, Blue, Green, Red; 3 bit colors only), depending on jumpers 
  ' TV: 16, 17, 18, 19 
  ' PS/2 keyboard: 26, 27
  ' EEPROM: 28, 29
  ' Serial port: 30, 31
  '
  ' Note that no pins between 24 and 31 are used by the 6502 circuitry.
  ' Thanks to this, the trace cog can discard these bits and replace them
  ' with the values of the data bus.
  

  '==========================================================================
  ' Masks for pins
'{{LED
  con_mask_LED     = (|< pin_LED)
'LED}}
{{!LED
  con_mask_LED     = 0
!LED}}

  con_mask_DATA    = (|< pin_D0)     | (|< pin_D1)     | (|< pin_D2)     | (|< pin_D3)     | (|< pin_D4)     | (|< pin_D5)     | (|< pin_D6)     | (|< pin_D7)
  con_mask_ADDRL   = (|< pin_A0)     | (|< pin_A1)     | (|< pin_A2)     | (|< pin_A3)     | (|< pin_A4)     | (|< pin_A5)     | (|< pin_A6)     | (|< pin_A7)
  con_mask_ADDRH   = (|< pin_A8)     | (|< pin_A9)     | (|< pin_A10)    | (|< pin_A11)    | (|< pin_A12)    | (|< pin_A13)    | (|< pin_A14)    | (|< pin_A15)
  con_mask_ADDR    = con_mask_ADDRL  | con_mask_ADDRH
  con_mask_OUTPUTS = con_mask_LED    | (|< pin_RAMOE)  | (|< pin_RAMWE)  | (|< pin_AEN)    | (|< pin_SLC)    | (|< pin_CLK0)   | (|< pin_SDA)
  con_mask_SIGNALS = (|< pin_CRES)   | (|< pin_CNRDY)  | (|< pin_CSO)    | (|< pin_CIRQ)   | (|< pin_CNBE)   | (|< pin_CNMI)   | (|< pin_CSETUP) | (|< pin_CRAMA16)
  con_mask_HALT    = (|< pin_CNRDY)
  con_mask_RESET   = (|< pin_CRES)
  con_mask_RAM     = (|< pin_RAMOE)  | (|< pin_RAMWE)
  con_mask_I2C     = (|< pin_SDA)    | (|< pin_SCL)


  '==========================================================================
  ' Output bit patterns
              
  
  ' Initial values of output pins at Beginning Of World:
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
   
PUB dummy
'' Dummy public routine, otherwise this won't compile.                                                                                                 