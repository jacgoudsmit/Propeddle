''
'' Serial In TV Out
'' Helper module for Propeddle debugging
''

OBJ
  ser: "FullDuplexSerial"
  tv: "AiGeneric_Driver"

PUB Start

  ser.Start(31,30,0,115200)
  tv.Start(16)
  tv.Color(tv#RGB_GREEN)

PUB str(s)

  ser.str(s)
  tv.str(s)

PUB dec(v)

  ser.dec(v)
  tv.dec(v)

PUB rxtime(ms)

  return ser.rxtime(ms)

PUB rxflush

  ser.rxflush

PUB tx(c)

  ser.tx(c)
  tv.out(c)

PUB rx

  return ser.rx

PUB stop

  tv.close
  ser.stop

PUB bin(v,n)

  ser.bin(v,n)
  tv.bin(v,n)

PUB hex(v,n)

  ser.hex(v,n)
  tv.hex(v,n)

PUB rxcheck

  return ser.rxcheck

PUB pokechar(row,col,colorr,c)

  tv.pokechar(row,col,colorr,c)

PUB cls

  tv.cls

PUB color(c)

  tv.color(c)