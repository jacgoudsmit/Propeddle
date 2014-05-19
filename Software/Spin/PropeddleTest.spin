''***************************************************************************
''* Propeddle test program
''* Author: Jac Goudsmit
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
  _clkmode = XTAL1 + PLL16X
  _xinfreq = 6_250_000

  con_tracelen = 125
  
OBJ
  text:         "FullDuplexSerial" {{"SerInTVOut"}}
  ctrl:         "PropeddleControl"
  hw:           "PropeddleHardware"
'  ram:          "PropeddleRAM"
  hub:          "PropeddleHub"
  trace:        "PropeddleTrace"
  term:         "PropeddleTerm"
  
DAT
  tracedump long 0[con_tracelen]

DAT
  ' The module "maps" the following block of ram into the top of the 6502 memory space, regardless
  ' of how big you make it.
  ' 
  '                  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
  romimage    'byte  $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

              ' On-screen counter
'              byte  $EE, $F9, $80, $EE, $F9, $FF, $4C, $F0, $FF, $00, $F0, $FF, $F0, $FF, $F0, $FF

              ' Terminal test 1: Writes all printable characters to terminal repetitively 
  '                  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
              byte   $A9, $20, $AA, $C9, $7F, $F0, $F9, $20, $EF, $FF, $E8, $8A, $4C, $E2, $FF, $2C
              byte   $12, $D0, $30, $FB, $8D, $12, $D0, $60, $00, $00, $00, $00, $E0, $FF, $00, $00

  romend

  romstart    long $1_0000 - (@romend - @romimage)
      
  signals     long 0

  clkcount    long 0
       
PUB testmain | i

  text.Start(31,30,0,115200)
  'text.Start
  
  waitcnt(clkfreq + cnt)

  text.str(string("Hello", 13))
  
  repeat
    DemoDump


PUB DemoDump | i
      
  ctrl.Start
  term.Start($D010)

  ' Hub access cog must be started after control cog
  text.str(string("Starting hub cog: "))
  text.hex(@romimage, 4)
  text.tx(32)
'  text.hex(byte[@romimage], 2)
'  text.tx(32)
  text.hex(romstart, 4)
  text.tx(32)
  text.hex(@romend - @romimage, 4)
  text.tx(13)
  hub.Start(@romimage, romstart, @romend - @romimage, TRUE)

  ' Give us a wink to show you're there
  'ctrl.LedOn

  text.str(string("Reset On",13))
  ctrl.SetSignal(hw#pin_CRES, TRUE)
  
  repeat 2
    trace.Start(@tracedump, 1)
    ctrl.Run(40_000_000, 1)
    ctrl.RunWait(clkfreq + cnt)

    dumptrace0

  ctrl.SetSignal(hw#pin_CRES, FALSE)
  text.str(string("Reset Off",13))

  trace.Start(@tracedump, con_tracelen)
  ctrl.Run(100, 0) 'con_tracelen)
  
  repeat
    PumpTerminal
    if text.rxcheck <> -1
      text.str(string("Ending",13))
      ctrl.runend
      quit

'    i := ctrl.RunWait(clkfreq + cnt)
'    'text.dec(i)
'    'text.tx(13)
'    if i <> ctrl#con_RESULT_RUN_RUNNING
'      quit

  dumptrace
  
  repeat
    waitcnt(clkfreq + cnt)
    ctrl.LedToggle


PUB PumpTerminal | i

    i := term.RecvChar
    if (i & $80) <> 0
      'text.hex(i, 2)
      'text.tx($20)
      text.tx(i & $7F)


PUB dumptrace1(i) | t

  t := tracedump[i]
  result := t <> 0
  if result
    if (t & $80000000) <> 0
      text.tx("R")
    else
      text.tx("W")
    text.tx(32)
    text.hex((t & $FFFF00) >> 8, 4)
    text.tx(32)
    text.hex((t & $FF), 2) 
    text.tx(13)
  else
    text.str(string("- ---- --", 13))  

PUB dumptrace0

  dumptrace1(0)
  
PUB dumptrace | i

  repeat i from 0 to con_tracelen - 1
    if tracedump[i]
      text.hex(i, 4)
      text.str(string(": "))
      dumptrace1(i)
    else
      quit

  
PUB DemoInteractive | c, i

  waitcnt(clkfreq + cnt)

  Zap(true)  

  'Demo
   
  repeat       
    text.rxflush
    text.tx(">")
    c := text.rx
    text.tx(c)    
    text.tx(13)
    case c
      "i","I": InStatus
      "o","O": OutStatus
      "z","Z": Zap(ctrl.IsStarted)
      "0","1": SetBit(c - "0")
      "t","T": ToggleBit
      "s","S": SetSignal
      "c","C": Clock(true)
      "g","G": Go
      "r","R": ResetSequence(true)
      "p","P": Zap(not ctrl.IsStarted)

      ' @@@ delete me
      "Q"    : ctrl.Stop
      "q"    : hub.Stop
            
      other:   Help
                        

PUB Help

  text.str(string("HELP:",13))
  text.str(string("?=This help",13))
  text.str(string("i=Current input pin status",13))
  text.str(string("o=Current output pin status", 13))
  text.str(string("z=Zap all cogs except this one (in case of panic)",13))
  text.str(string("0/1=Set a bit to given value",13))
  text.str(string("T=Toggle a bit",13))
  text.str(string("S=Change signals",13))
  text.str(string("C=Generate a clock cycle, enable RAM as needed",13))
  text.str(string("G=Go (continuous clocks until character received on serial",13))
  text.str(string("R=Reset sequence",13))
  text.str(string("P=Toggle direct (spin, slow) vs Control Cog (pasm, fast) mode",13))

                   
PUB Zap(usecontrolcog) | i

  ctrl.Stop
  text.stop
  
  repeat i from 0 to 7
    if (cogid <> i)
      cogstop(i)

  text.Start(31,30,0,115200)
'  text.start

  if (usecontrolcog)
    ctrl.Start

  if (ctrl.IsStarted)
    SetOuta(0)
    dira := 0
  else    
    SetOuta(hw#con_out_SAFE & !(|< hw#pin_LED))
    dira := hw#con_mask_OUTPUTS

  signals := 0
  SendSignals

  if (ctrl.IsStarted)
    text.str(string("Using Propeddle Control Cog (fast)",13))
  else
    text.str(string("Using direct control from Spin (slow)",13))

  clkcount := 0
  
  
PUB InStatus

  text.str(string("INA status:",13))
  Status(ina)

   
PUB OutStatus

  text.str(string("OUTA status:",13))
  Status(outa)


PRI Status(n)

  text.str(string("Register            = $"))
  text.hex(n, 8)
  text.str(string(" %"))
  text.bin(n, 32)
  text.tx(13)

  PrintPin(string("SDA      "), n, hw#pin_SDA)  
  PrintPin(string("SCL/CLK0 "), n, hw#pin_SCL)  ' Useless   
  PrintPin(string("R/!W     "), n, hw#pin_RW)
  PrintPin(string("DEBUG    "), n, hw#pin_DEBUG)
  PrintPin(string("SLC      "), n, hw#pin_SLC)  ' Kinda useless
  PrintPin(string("!AEN     "), n, hw#pin_AEN)
  PrintPin(string("!RAMWE   "), n, hw#pin_RAMWE)
  PrintPin(string("!RAMOE   "), n, hw#pin_RAMOE)
  text.tx(13)
  if (n & (|< hw#pin_AEN))
    PrintSignals(n)
    text.str(string(13, "Databus:            = $"))
    text.hex(n, 2)
    text.str(string(" %"))
    text.bin(n, 8)
  else
    text.str(string("Address bus:        = $"))
    text.hex(n, 4)
    text.str(string(" %"))
    text.bin(n, 16)

  text.tx(13)


PRI PrintSignals(n)

  text.str(string("Signals (out only): = $"))
  text.hex(n >> 8, 2)
  text.str(string(" %"))
  text.bin(n >> 8, 8)
  text.tx(13) 
  PrintPin(string("CSO            "), n, hw#pin_CSO)
  PrintPin(string("CRES           "), n, hw#pin_CRES)
  PrintPin(string("CNRDY          "), n, hw#pin_CNRDY)
  PrintPin(string("CIRQ           "), n, hw#pin_CIRQ)
  PrintPin(string("CNMI           "), n, hw#pin_CNMI)
  PrintPin(string("CRAMA16        "), n, hw#pin_CRAMA16)
  PrintPin(string("CNBE           "), n, hw#pin_CNBE)
  PrintPin(string("CSETUP         "), n, hw#pin_CSETUP)

 
PRI PrintPin(s, value, pin)

  text.str(s)
  text.tx("[")
  if (pin < 10)
    text.tx(" ")
  text.dec(pin)
  text.str(string("] = "))
  text.bin(value >> pin, 1)
  text.tx(13)


PRI PrintOuta | value

  if (ctrl.IsStarted)
    value := ctrl.GetOuta
  else
    value := outa

  text.str(string(13,"OUTA = "))
  PrintValue(value)


PRI PrintValue(value)
    
  text.str(string(13,"$"))
  text.hex(value, 8)
  text.str(string(" %"))
  text.bin(value,32)
  text.tx(13)


PRI SetOuta(newvalue)

  'text.str(string("Setting outa to: "))
  'PrintValue(newvalue)

  'Status(newvalue)
  'Wait
  outa := newvalue
  'Wait


PRI SetOutaBit(bit, onoff) | mask, value

  mask := (|< bit)
  value := outa & !mask
  if onoff <> 0
    value |= mask
  SetOuta(value)    

  
PRI SetBit(newvalue) | pin  

  text.str(string("Setting bit to "))
  text.bin(newvalue, 1)
  text.tx(13)
  
  pin := WhichBit
  if (pin => 0) 
    if (ctrl.IsStarted)
      ctrl.SetSignal(pin, newvalue <> 0)
    else
      SetOutaBit(pin, newvalue <> 0)

  PrintOuta


PRI ToggleBit | pin

  text.str(string("Toggling bit", 13))

  pin := WhichBit
  if (pin => 0)
    if (ctrl.IsStarted)
      ctrl.SetSignal(pin, not ctrl.GetSignal(pin))
    else
      SetOutaBit(pin, !outa[pin])

  PrintOuta

      
PRI WhichBit | c,v

  result := -1
  
  repeat until result <> -1
    text.str(string("Which bit? (?=help) "))
    c := text.rx
    case c
      "c","C":  result := hw#pin_CLK0
      "s","S":  result := hw#pin_SLC
      "a","A":  result := hw#pin_AEN
      "o","O":  result := hw#pin_RAMOE
      "w","W":  result := hw#pin_RAMWE
      "0".."9": return RxNumber(c - "0")
      27:       return ' Esc=Cancel
      other:
        text.tx(13)
        text.str(string("C=CLK0",13))
        text.str(string("S=SLC (Signal Latch Clock)",13))
        text.str(string("A=AEN (Address latch enable, active low)",13))
        text.str(string("O=RAMOE (Read from RAM, active low)", 13))
        text.str(string("W=RAMWE (Write to RAM, active low)", 13))
        text.str(string(13,"You can also enter a number followed by Enter",13))
        text.str(string(13,"Esc=cancel",13))
        text.str(string(13,"*** NOTE: some combinations make output collide, study the docs! ***",13))

      
PRI RxNumber(init) | v, c

  v := init

  ' TODO: improve editing and check for range, allow canceling
  repeat
    c := text.rx
    case c
      "0".."9":
        v := 10 * v + (c - "0")
      8:
        v /= 10
      13:
        return v


PRI Wait

  text.str(string("Ready?",13))
  text.rx

  
PUB SetSignal | c, pin 

  repeat
    pin := -1
    if (ctrl.IsStarted)
      signals := ctrl.GetSignals
    PrintSignals(signals)
    text.str(string(13,"Which signal to toggle? Enter=send these, Esc=cancel, ?=Help",13))
    text.str(string("*** NOTE: should only send signals with AEN disabled! ***",13,">"))
    c := text.rx
    case c
      "o","O": pin := hw#pin_CSO
      "r","R": pin := hw#pin_CRES
      "d","D": pin := hw#pin_CNRDY
      "i","I": pin := hw#pin_CIRQ
      "n","N": pin := hw#pin_CNMI
      "6":     pin := hw#pin_CRAMA16
      "b","B": pin := hw#pin_CNBE
      "s","S": pin := hw#pin_CSETUP
      "-":     signals := 0
      27:
        quit
      13:
        SendSignals
        quit
      other:
        text.str(string(13,"HELP: (note: signals on 6502 are inverted)",13))
        text.str(string("O=SO (High=Set Overflow)",13))
        text.str(string("R=RESET (High=restart 6502; keep high for 2 cycles)",13))
        text.str(string("D=!RDY (High=stop processor)",13))
        text.str(string("I=IRQ (Level Triggered)",13))
        text.str(string("N=NMI (Rising Edge Triggered)",13))
        text.str(string("6=RAM A16 (Bank switching)",13))
        text.str(string("B=!BE (High=disconnect WDC 65C02S from bus)",13))
        text.str(string("S=SETUP (Reserved for I/O expansion)",13))
        text.str(string(13,"-=Deactivate All (all low)",13))
    if (pin => 0)
      signals ^= (|< pin)                    

  text.str(string(13,"Back to main menu",13))
  return

      
PUB SendSignals

  text.str(string(13,"Sending signals",13))
  PrintSignals(signals)
  if (ctrl.IsStarted)
    ctrl.SetSignals(signals)
  else
    dira[8..15]~~
    SetOuta((outa & !(hw#con_mask_SIGNALS | (|< hw#pin_SLC))) | signals)
    SetOutaBit(hw#pin_SLC, 1)
    dira[8..15]~ 


PUB Clock(verbose) | mask, addr, b

  if (verbose)
    text.str(string(13, "Clock #"))
    text.dec(clkcount)
    text.tx(13)
  clkcount++

  if ctrl.IsStarted
    trace.Start(@tracedump, 1)
    ctrl.Run(clkfreq / 8, 1)
    ctrl.RunWait(clkfreq / 4 + cnt)
    dumptrace0
  else  
    ' Phi1
    ' Start by setting the clock low. If we're injecting data, it needs to
    ' remain on the data bus until after the clock goes low.
    SetOutaBit(hw#pin_CLK0, 0)
     
    ' Now set the output to the default Phi1 outputs but leave the LED unchanged
    SetOuta(hw#con_OUT_PHI1 | (outa & (|< hw#pin_LED)))
    dira[0..7]~
     
    ' Read the address bus and R/!W
    addr := ina & $FFFF
    if (verbose)
      text.str(string("Phi1: Got address $"))
      text.hex(addr, 4)
      if (addr => romstart)
        text.str(string(" (ROM)"))
      text.tx(13)
      text.str(string("R/!W = "))
      text.bin(ina >> hw#pin_RW, 1)
      text.tx(13)
       
    ' Take address bus off the Prop
    SetOutaBit(hw#pin_AEN, 1)
     
    'Phi2
    'Toggle the clock and the RAM if needed
    if (addr < romstart )
      if (ina[hw#pin_RW])
        mask := !(|< hw#pin_RAMOE)
      else
        mask := !(|< hw#pin_RAMWE)
    else
      if (ina[hw#pin_RW]) ' reading
        b := romimage.byte[addr - romstart]
        if (verbose)
          text.str(string(13,"Injecting "))
          text.hex(b,2)
          text.tx(13)
        SetOuta(outa | b) 
        dira[0..7]~~
      mask := $FFFFFFFF
              
    SetOuta((outa | (|< hw#pin_CLK0)) & mask)
     
    ' Read the data bus
    if (verbose)
      text.str(string("Data bus=$"))
      text.hex(ina, 2)
      text.tx(13)
       
    if ((addr => romstart) and (ina[hw#pin_RW] == 0))
      if (verbose)
        text.str(string("Storing "))
        text.hex(ina & $FF,2)
        text.tx(13)
      romimage.byte[addr - romstart] := (ina & $FF)
      if (verbose)
        text.str(string("Setting LED to "))
        text.bin(ina, 1)
        text.tx(13)
      if (addr == $FFF9)
        SetOutaBit(hw#pin_LED, ina & $80)
      text.tx(ina & $FF)
      'text.pokechar(23,addr - romstart,$FE,ina & $FF)
       
  
PUB Go | i,timer

  repeat i from 0 to 10
    text.tx(13)
    
  text.str(string("PROPEDDLE SOFTWARE-DEFINED 6502 COMPUTER",13))

'                  1234567890123456789012345678901234567890
  text.str(string("A small part of this TV screen is under",13))
  text.str(string("control of a 6502 processor on the",13))
  text.str(string("PROPEDDLE board. A Propeller controls",13))
  text.str(string("the 6502 and simulates a ROM with a",13))
  text.str(string("small program that updates a location",13))
  text.str(string("in the screen buffer (see bottom right).",13,13))

  text.str(string("The demo uses the Spin language to",13))
  text.str(string("control the 6502 and reaches a clock",13))
  text.str(string("frequency of about 5000 clock cycles",13))
  text.str(string("per second. The Assembler version of",13))
  text.str(string("the software can generate the ",34,"full",34,13))
  text.str(string("1MHz clock of the classic 6502, but",13))
  text.str(string("is not done yet.",13,13))
  
  text.str(string("The project will be for sale as a kit.",13))
  text.str(string("It will be able to emulate early 6502",13))
  text.str(string("computers such as the Commodore PET,",13))
  text.str(string("or you can design your own.",13))
  text.str(string("More info http://www.propeddle.com",13,13,13))

  timer := cnt

  repeat until (text.rxcheck <> -1)
    Clock(false)
'    waitcnt(timer += clkfreq / 10)

      
PUB ResetSequence(verbose) | i

  signals := hw#con_mask_RESET
  SendSignals

  ' Must generate 2 clocks before releasing RESET
  repeat i from 1 to 2
    Clock(verbose)
  
  signals := 0
  SendSignals

  if(verbose)
    InStatus

  repeat i from 1 to 6 
    Clock(verbose)
  ' 65C02 will pick up reset vector in next clock cycle


PUB Demo

  text.str(string("Starting Demo",13))
  text.str(string("Send any character to interrupt",13))
  ResetSequence(false)
  Go
  
      