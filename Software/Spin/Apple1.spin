''***************************************************************************
''* Apple 1 emulator
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
''
'' This is the top module of an Apple-1 emulator using the Propeddle system.
'' As ROM we use Krusader: an 8K ROM image intended for the Replica 1 by
'' Briel Computers.
'' See http://school.anhb.uwa.edu.au/personalpages/kwessen/apple1/Krusader.htm

CON
  _clkmode = XTAL1 + PLL16X
  _xinfreq = 6_250_000

  con_speed = 100


OBJ
  text:         "SerInTVOut" {{"FullDuplexSerial"}}
  ctrl:         "PropeddleControl"
  hw:           "PropeddleHardware"
  hub:          "PropeddleHub"
  term:         "PropeddleTerm"

  
DAT
  ' The module "maps" the following block of ram into the top of the 6502 memory space, regardless
  ' of how big you make it.
  romimage
              ' Krusader 1.3
              file "6502.rom.bin"
  romend      

  romstart    long $1_0000 - (@romend - @romimage)

      
PUB Main | i

  ' Initialize serial port and video
  'text.Start(31,30,0,115200)
  text.Start
  waitcnt(clkfreq + cnt)

  text.str(string(13, "Propeddle Initializing", 13))
  
  text.str(string("Starting control cog",13))
  ctrl.Start

  text.str(string("Starting terminal cog",13))
  term.Start($D010)

{{
  ' Hub access cog must be started after control cog
  text.str(string("Starting hub cog. ROM image at $"))
  text.hex(romstart, 4)
  text.str(string(13,"ROM image length is $"))
  text.hex(@romend - @romimage, 4)
  text.tx(13)
  hub.Start(@romimage, romstart, @romend - @romimage, TRUE)
}}
  text.str(string("Downloading",13))
  ctrl.Download(con_speed * 2, @romimage, romstart, @romend - @romimage)

  text.str(string("Resetting",13))
  ctrl.SetSignal(hw#pin_CRES, TRUE)
  
  repeat 2
    'starttrace1
    ctrl.Run(con_speed, 1)
    ctrl.RunWait(clkfreq + cnt)
    'dumptrace0

  ctrl.SetSignal(hw#pin_CRES, FALSE)

  text.str(string("Running",13))
  ctrl.Run(con_speed, 0)
  
  repeat
    i := text.rxcheck
    if i <> -1
      term.SendKey(i)
      result := (i == 27)
      
    i := term.RcvDisp
    if i => 0
      if (i < 32) or (i > 126)
        text.str(string(32,8))
      text.tx(i)
      text.str(string(64,8))
               

{{>>START TRACE CODE}}
CON
  con_tracelen = 125

OBJ
  trace:        "PropeddleTrace"

DAT
  tracedump long 0[con_tracelen]

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
    if tracedump[i] <> 0
      text.hex(i, 4)
      text.str(string(": "))
      dumptrace1(i)
    else
      quit

PUB starttrace

  trace.Start(@tracedump, con_tracelen)

PUB starttrace1

  trace.Start(@tracedump, 1)
  
{{<<END TRACE CODE}}      