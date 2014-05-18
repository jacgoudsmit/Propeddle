''
'' Serial In TV Out
'' Helper module for Propeddle debugging
''

OBJ
  ser:          "FullDuplexSerial"
  tv:           "AiGeneric_Driver"
  kb:           "Keyboard"
  
PUB Start

  ser.Start(31,30,0,115200)
  tv.Start(16)
  tv.Color(tv#RGB_GREEN)
  kb.Start(26, 27)
  
PUB str(s)

  ser.str(s)
  tv.str(s)

PUB dec(v)

  ser.dec(v)
  tv.dec(v)

PUB rxtime(ms) | t, rxbyte

  t := cnt
  repeat until (cnt - t) / (clkfreq / 1000) > ms
    rxbyte := ser.rxcheck
    if rxbyte <> -1
      return rxbyte
    if kb.gotkey<>0
      return kb.getkey
    
  return 0

PUB rxflush

  ser.rxflush
  kb.clearkeys

PUB tx(c)

  ser.tx(c)
  tv.out(c)

PUB rx | rxbyte

  repeat
    rxbyte := ser.rxcheck
    if rxbyte <> -1
      return rxbyte
    if kb.gotkey <> 0
      return kb.getkey

PUB stop

  kb.stop
  tv.close
  ser.stop

PUB bin(v,n)

  ser.bin(v,n)
  tv.bin(v,n)

PUB hex(v,n)

  ser.hex(v,n)
  tv.hex(v,n)

PUB rxcheck | c

  c := ser.rxcheck
  if c <> -1
    return c

  if kb.gotkey <> 0
    return kb.getkey

  return -1

PUB pokechar(row,col,colorr,c)

  tv.pokechar(row,col,colorr,c)

PUB cls

  tv.cls

PUB color(c)

  tv.color(c)