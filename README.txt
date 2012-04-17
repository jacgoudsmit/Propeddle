PROPEDDLE PROJECT README.TXT
Jac Goudsmit
http://www.propeddle.com

Welcome to Propeddle!

The Propeddle project is an Open Source Software Defined 6502 Computer.

It's not really a computer by itself, and it's not an emulation of an existing or new computer either; it's something in between.

There is a real 65C02 processor and a real Static RAM chip in the circuit, but a Parallax Propeller determines how the 65C02 "sees" its environment, and also helps with tasks that are relatively difficult to implement in hardware, such as video.

An expansion bus is provided to connect the 65C02 to other real hardware, such as a high-resolution graphics adapter or mass storage media. All the relevant pins of the 65C02 are available on the expansion port and it should be possible to design a "motherboard" to change the Propeddle into a hardware project that doesn't require the Propeller at all.

The hardware is available as a kit from the website. All the parts are through-hole only so it's also possible to build the system on a breadboard, or design your own circuit board. The schematics, PCB design and software are available under the MIT license (slightly modified to include the hardware design files):

PROPEDDLE MIT LICENSE:

********************************************************************************

Propeddle, Copyright (C) 2011-2012 by The Propeddle Project (Jac Goudsmit)
Based on the PROP-6502 project, Copyright (C) 2008 by Dennis Ferron.

Permission is hereby granted, free of charge, to any person obtaining a copy of the software, schematics and PCB design and the associated documentation files (the "Project"), to deal in the Project without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Project, and to permit persons to whom the Project is furnished to do so, subject to the following conditions:

The above Copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE PROJECT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

********************************************************************************

