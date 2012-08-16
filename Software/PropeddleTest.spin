''***************************************************************************
''* Propeddle test program
''* Author: Jac Goudsmit
''* Copyright (C) 2011 Jac Goudsmit
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

  con_tracelen = 30 
OBJ
  text:      "SerInTVOut"
  propeddle: "6502Rev8"

DAT
  tracedump long 0[con_tracelen]

DAT
  ' The module "maps" the following block of ram into the top of the 6502 memory space, regardless
  ' of how big you make it.
  ' 
  '                  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
  romimage    byte  $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
              byte  $EE, $F9, $FF, $4C, $F0, $FF, $00, $00, $00, $00, $F0, $FF, $F0, $FF, $F0, $FF
  romend      byte

  romstart    long $1_0000 - (@romend - @romimage)
      
  signals     long propeddle#con_MASK_SIGNALS

PUB mainProgram | c, i

  Zap(false)  

  Demo
   
  repeat       
    text.rxflush
    text.tx(">")
    c := text.rx    
    text.tx(13)
    case c
      "i","I": InStatus
      "o","O": OutStatus
      "z","Z": Zap(Propeddle.IsStarted)
      "0","1": SetBit(c - "0")
      "t","T": ToggleBit
      "s","S": SetSignal
      "c","C": Clock(true)
      "g","G": Go
      "r","R": ResetSequence(true)
      "p","P": Zap(not Propeddle.IsStarted)
      
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

  propeddle.Stop
  text.stop
  
  repeat i from 0 to 7
    if (cogid <> i)
      cogstop(i)

  text.start 'text.start(31,30,0,115200)

  if (usecontrolcog)
    Propeddle.Start

  if (Propeddle.IsStarted)
    outa := 0
    dira := 0
  else    
    outa := propeddle#con_out_SAFE & !(|< propeddle#pin_LED)
    dira := propeddle#con_mask_OUTPUTS

  signals := propeddle#con_MASK_SIGNALS
  SendSignals

  if (Propeddle.IsStarted)
    text.str(string("Using Propeddle Control Cog (fast)",13))
  else
    text.str(string("Using direct control from Spin (slow)",13))

  
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

  PrintPin(string("SDA            "), n, propeddle#pin_SDA)  
  PrintPin(string("SCL/CLK0       "), n, propeddle#pin_SCL)  ' Useless   
  PrintPin(string("R/!W           "), n, propeddle#pin_RW)
  PrintPin(string("CLK2 (optional)"), n, propeddle#pin_CLK2) ' Useless
  PrintPin(string("SYNC/LED (opt.)"), n, propeddle#pin_SYNC)
  PrintPin(string("SLC            "), n, propeddle#pin_SLC)  ' Kinda useless
  PrintPin(string("!AEN           "), n, propeddle#pin_AEN)
  PrintPin(string("!RAMWE         "), n, propeddle#pin_RAMWE)
  PrintPin(string("!RAMOE         "), n, propeddle#pin_RAMOE)
  text.tx(13)
  if (n & (|< propeddle#pin_AEN))
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
  PrintPin(string("!SO            "), n, propeddle#pin_SO)
  PrintPin(string("!RES           "), n, propeddle#pin_RES)
  PrintPin(string("RDY            "), n, propeddle#pin_RDY)
  PrintPin(string("!IRQ           "), n, propeddle#pin_IRQ)
  PrintPin(string("!NMI           "), n, propeddle#pin_NMI)
  PrintPin(string("RAMA16         "), n, propeddle#pin_RAMA16)
  PrintPin(string("!SEL1          "), n, propeddle#pin_SEL1)
  PrintPin(string("!SEL0          "), n, propeddle#pin_SEL0)
 
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

  if (Propeddle.IsStarted)
    value := Propeddle.GetOuta
  else
    value := outa
    
  text.str(string(13,"OUTA = $"))
  text.hex(value, 8)
  text.str(string(" %"))
  text.bin(value,32)
  text.tx(13)
  
PUB SetBit(newvalue) | pin  

  text.str(string("Setting bit to "))
  text.bin(newvalue, 1)
  text.tx(13)
  
  pin := WhichBit
  if (pin => 0) 
    if (Propeddle.IsStarted)
      Propeddle.SetSignal(pin, newvalue <> 0)
    else
      outa[pin] := newvalue    

  PrintOuta

PUB ToggleBit | pin

  text.str(string("Toggling bit", 13))

  pin := WhichBit
  if (pin => 0)
    if (Propeddle.IsStarted)
      Propeddle.SetSignal(pin, not Propeddle.GetSignal(pin))
    else
      outa[pin] := !outa[pin]

  PrintOuta
      
PRI WhichBit | c,v

  result := -1
  
  repeat until result <> -1
    text.str(string("Which bit? (?=help) "))
    c := text.rx
    case c
      "c","C":  result := propeddle#pin_CLK0
      "s","S":  result := propeddle#pin_SLC
      "a","A":  result := propeddle#pin_AEN
      "o","O":  result := propeddle#pin_RAMOE
      "w","W":  result := propeddle#pin_RAMWE
      "0".."9": return RxNumber(c - "0")
      27:       return ' Esc=Cancel
      other:
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

PUB SetSignal | c, pin 

  repeat
    pin := -1
    if (Propeddle.IsStarted)
      signals := Propeddle.GetSignals
    PrintSignals(signals)
    text.str(string(13,"Which signal to toggle? Enter=send these, Esc=cancel, ?=Help",13))
    text.str(string("*** NOTE: should only send signals with AEN disabled! ***",13,">"))
    c := text.rx
    case c
      "o","O": pin := propeddle#pin_SO
      "r","R": pin := propeddle#pin_RES
      "d","D": pin := propeddle#pin_RDY
      "i","I": pin := propeddle#pin_IRQ
      "n","N": pin := propeddle#pin_NMI
      "6":     pin := propeddle#pin_RAMA16
      "1":     pin := propeddle#pin_SEL1
      "0":     pin := propeddle#pin_SEL0
      "-":     signals := propeddle#con_mask_SIGNALS
      27:
        quit
      13:
        SendSignals
        quit
      other:
        text.str(string(13,"O=!SO (Set Overflow)",13))
        text.str(string("R=!RESET",13))
        text.str(string("D=RDY (Low=stop processor)",13))
        text.str(string("I=!IRQ (Level Triggered)",13))
        text.str(string("N=!NMI (Falling Edge Triggered)",13))
        text.str(string("6=RAM A16 (Bank switching)",13))
        text.str(string("1=SEL1 (reserved)",13))
        text.str(string("0=SEL0 (reserved)",13))
        text.str(string(13,"-=Deactivate All (all high)",13))
    if (pin => 0)
      signals ^= (|< pin)                    

  text.str(string(13,"Back to main menu",13))
  return
      
PUB SendSignals

  text.str(string(13,"Sending signals",13))
  PrintSignals(signals)
  if (Propeddle.IsStarted)
    Propeddle.SetSignals(signals)
  else
    dira[8..15]~~
    outa := (outa & !(propeddle#con_mask_SIGNALS | (|< propeddle#pin_SLC))) | signals
    outa |= (|< propeddle#pin_SLC)
    dira[8..15]~ 
     
PUB Clock(verbose) | mask, addr

  ' Phi1
  ' Start with the default Phi1 outputs but leave the LED unchanged
  outa := propeddle#con_OUT_PHI1 | (outa & (|< propeddle#pin_LED))
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
    text.bin(ina >> propeddle#pin_RW, 1)
    text.tx(13)
     
  ' Take address bus off the Prop
  outa[propeddle#pin_AEN]~~
   
  'Phi2
  'Toggle the clock and the RAM if needed
  if (addr < romstart )
    if (ina[propeddle#pin_RW])
      mask := !(|< propeddle#pin_RAMOE)
    else
      mask := !(|< propeddle#pin_RAMWE)
  else
    if (ina[propeddle#pin_RW]) ' reading
      if (verbose)
        text.str(string("Injecting "))
        text.hex(romimage[addr - romstart],2)
        text.tx(13)
      outa := outa | romimage[addr - romstart]
      dira[0..7]~~
    mask := $FFFFFFFF
            
  outa := (outa | (|< propeddle#pin_CLK0)) & mask

  ' Read the data bus
  if (verbose)
    text.str(string("Data bus=$"))
    text.hex(ina, 2)
    text.tx(13)
     
  if ((addr => romstart) and (ina[propeddle#pin_RW] == 0))
    if (verbose)
      text.str(string("Storing "))
      text.hex(ina & $FF,2)
      text.tx(13)
    romimage[addr - romstart] := (ina & $FF)
    if (verbose)
      text.str(string("Setting LED to "))
      text.bin(ina, 1)
      text.tx(13)
    if (addr == $FFF9)
      outa[propeddle#pin_LED] := (ina & 1)
    text.pokechar(23,addr - romstart,$FE,ina & $FF)
     
  
PUB Go | i,timer

  repeat i from 0 to 10
    text.tx(13)
    
  text.str(string("PROPEDDLE DEMO",13))

'                  1234567890123456789012345678901234567890
  text.str(string("A small part of this TV screen is under",13))
  text.str(string("control of the 65C02 processor on the",13))
  text.str(string("PROPEDDLE board: it runs a small",13))
  text.str(string("program to update the text in a screen",13))
  text.str(string("buffer.",13,13))

  text.str(string("At this time, the Propeller on the",13))
  text.str(string("Propeller Platform motherboard controls",13))
  text.str(string("the 65C02 with software in Spin. It",13))
  text.str(string("generates about 5000 clock cycles per",13))
  text.str(string("second on the 65C02. The Propeller",13))
  text.str(string("Assembler version of the code is able",13))
  text.str(string("to generate the ",34,"full",34," 1MHz of the",13))
  text.str(string("classic 6502.",13,13))
  
  text.str(string("Additional cogs can be launched to add",13))
  text.str(string("emulation for other hardware such as a",13))
  text.str(string("keyboard or a floppy drive",13,13))

  text.str(string("More info will be available soon on the",13))
  text.str(string("website: http://www.propeddle.com",13,13,13))

  timer := cnt

  repeat until (text.rxcheck <> -1)
    Clock(false)
'    waitcnt(timer += clkfreq / 10)
      
PUB ResetSequence(verbose) | i

  signals := propeddle#con_mask_RESET
  SendSignals

  ' Must generate 2 clocks before releasing RESET
  repeat i from 1 to 2
    Clock(verbose)
  
  signals := propeddle#con_mask_SIGNALS
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
  
      