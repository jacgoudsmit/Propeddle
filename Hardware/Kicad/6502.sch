EESchema Schematic File Version 2
LIBS:jac
LIBS:Propeddle-cache
LIBS:ttl_ieee
LIBS:power
LIBS:propeller
LIBS:crystal
LIBS:conn
LIBS:Propeddle-cache
EELAYER 27 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 4 7
Title "Propeddle"
Date "23 apr 2014"
Rev "11"
Comp "(C) 2014 Jac Goudsmit"
Comment1 "Software-Defined 6502 Computer"
Comment2 "http://www.propeddle.com"
Comment3 ""
Comment4 ""
$EndDescr
$Comp
L GND #PWR027
U 1 1 5339E09A
P 4950 5900
F 0 "#PWR027" H 4950 5900 30  0001 C CNN
F 1 "GND" H 4950 5830 30  0001 C CNN
F 2 "" H 4950 5900 60  0000 C CNN
F 3 "" H 4950 5900 60  0000 C CNN
	1    4950 5900
	1    0    0    -1  
$EndComp
$Comp
L C C401
U 1 1 5339E0A6
P 6900 4900
F 0 "C401" H 6900 5000 40  0000 L CNN
F 1 "100n" H 6906 4815 40  0000 L CNN
F 2 "~" H 6938 4750 30  0000 C CNN
F 3 "~" H 6900 4900 60  0000 C CNN
	1    6900 4900
	1    0    0    -1  
$EndComp
$Comp
L 65(C)02 IC401
U 1 1 5339E0CA
P 4950 4400
F 0 "IC401" H 4600 5750 60  0000 C CNN
F 1 "65[C]02" H 5150 3050 60  0000 C CNN
F 2 "~" H 4950 4400 60  0000 C CNN
F 3 "~" H 4950 4400 60  0000 C CNN
	1    4950 4400
	1    0    0    -1  
$EndComp
Text HLabel 4350 3200 0    50   BiDi ~ 0
D0
Text HLabel 4350 3300 0    50   BiDi ~ 0
D1
Text HLabel 4350 3400 0    50   BiDi ~ 0
D2
Text HLabel 4350 3500 0    50   BiDi ~ 0
D3
Text HLabel 4350 3600 0    50   BiDi ~ 0
D4
Text HLabel 4350 3700 0    50   BiDi ~ 0
D5
Text HLabel 4350 3800 0    50   BiDi ~ 0
D6
Text HLabel 4350 3900 0    50   BiDi ~ 0
D7
Text HLabel 4350 4100 0    50   3State ~ 0
A0
Text HLabel 4350 4200 0    50   3State ~ 0
A1
Text HLabel 4350 4300 0    50   3State ~ 0
A2
Text HLabel 4350 4400 0    50   3State ~ 0
A3
Text HLabel 4350 4500 0    50   3State ~ 0
A4
Text HLabel 4350 4600 0    50   3State ~ 0
A5
Text HLabel 4350 4700 0    50   3State ~ 0
A6
Text HLabel 4350 4800 0    50   3State ~ 0
A7
Text HLabel 4350 4900 0    50   3State ~ 0
A8
Text HLabel 4350 5000 0    50   3State ~ 0
A9
Text HLabel 4350 5100 0    50   3State ~ 0
A10
Text HLabel 4350 5200 0    50   3State ~ 0
A11
Text HLabel 4350 5300 0    50   3State ~ 0
A12
Text HLabel 4350 5400 0    50   3State ~ 0
A13
Text HLabel 4350 5500 0    50   3State ~ 0
A14
Text HLabel 4350 5600 0    50   3State ~ 0
A15
Text HLabel 6550 5400 2    50   Output ~ 0
CLK2
Text HLabel 6550 5300 2    50   Output ~ 0
CLK1
Text HLabel 6550 5200 2    50   Input ~ 0
CLK0
Text HLabel 5550 4700 2    50   UnSpc ~ 0
GND/~VP
Text HLabel 5550 4600 2    50   Input ~ 0
NC/~ML
Text HLabel 6550 4400 2    50   Input ~ 0
BE
Text HLabel 6550 3900 2    50   Output ~ 0
SYNC
Text HLabel 6550 3800 2    50   Output ~ 0
R/~W
Text HLabel 6550 3200 2    50   Input ~ 0
~RESET
Text HLabel 6550 3300 2    50   Input ~ 0
RDY
Text HLabel 6550 3400 2    50   Input ~ 0
~IRQ
Text HLabel 6550 3500 2    50   Input ~ 0
~NMI
Text HLabel 6550 3600 2    50   Input ~ 0
~SO
$Comp
L VCC #PWR028
U 1 1 5346220A
P 4950 2500
F 0 "#PWR028" H 4950 2600 30  0001 C CNN
F 1 "VCC" H 4950 2600 30  0000 C CNN
F 2 "" H 4950 2500 60  0000 C CNN
F 3 "" H 4950 2500 60  0000 C CNN
	1    4950 2500
	1    0    0    -1  
$EndComp
$Comp
L 00JG-RPACK_ISOLATED R401
U 1 1 53478D3C
P 5950 2850
F 0 "R401" H 5950 2400 60  0000 C CNN
F 1 "8x 2K7" H 5950 3300 60  0000 C CNN
F 2 "" H 5950 2850 60  0000 C CNN
F 3 "" H 5950 2850 60  0000 C CNN
	1    5950 2850
	0    -1   -1   0   
$EndComp
Text HLabel 6100 2500 1    50   Output ~ 0
RR/~W
Text HLabel 6300 2500 1    50   Output ~ 0
RDEBUG
$Comp
L CONN_3 P401
U 1 1 53483773
P 6300 6250
F 0 "P401" V 6250 6250 50  0000 C CNN
F 1 "SYNC DEBUG CLK2" V 6350 6250 40  0000 C CNN
F 2 "~" H 6300 6250 60  0000 C CNN
F 3 "~" H 6300 6250 60  0000 C CNN
	1    6300 6250
	0    -1   1    0   
$EndComp
Wire Wire Line
	4950 2500 4950 3100
Wire Wire Line
	4950 5700 4950 5900
Connection ~ 4950 5800
Wire Wire Line
	6900 5800 6900 5100
Wire Wire Line
	4950 2550 6900 2550
Connection ~ 4950 2550
Wire Wire Line
	5550 3200 6550 3200
Wire Wire Line
	5550 4400 6550 4400
Wire Wire Line
	5550 3300 6550 3300
Wire Wire Line
	5550 3400 6550 3400
Wire Wire Line
	5550 3500 6550 3500
Wire Wire Line
	5550 3600 6550 3600
Wire Wire Line
	5550 3800 6550 3800
Wire Wire Line
	4950 5800 6900 5800
Wire Wire Line
	5550 3900 6550 3900
Wire Wire Line
	5600 2600 5600 2550
Connection ~ 5600 2550
Wire Wire Line
	5700 2600 5700 2550
Connection ~ 5700 2550
Wire Wire Line
	5800 2600 5800 2550
Connection ~ 5800 2550
Wire Wire Line
	5900 2600 5900 2550
Connection ~ 5900 2550
Wire Wire Line
	6900 2550 6900 4700
Wire Wire Line
	6000 2600 6000 2550
Connection ~ 6000 2550
Wire Wire Line
	5600 3100 5600 3300
Connection ~ 5600 3300
Wire Wire Line
	5700 3100 5700 3400
Connection ~ 5700 3400
Wire Wire Line
	5800 3100 5800 3500
Connection ~ 5800 3500
Wire Wire Line
	6300 2600 6300 2500
Wire Wire Line
	6300 3100 6300 5900
Wire Wire Line
	5550 5200 6550 5200
Wire Wire Line
	5550 5300 6550 5300
Wire Wire Line
	5550 5400 6550 5400
Connection ~ 6000 3600
Wire Wire Line
	6000 3100 6000 3600
Connection ~ 5900 4400
Wire Wire Line
	5900 3100 5900 4400
Wire Wire Line
	6100 3100 6100 3800
Connection ~ 6100 3800
Wire Wire Line
	6200 3100 6200 3200
Connection ~ 6200 3200
Wire Wire Line
	6200 2600 6200 2550
Connection ~ 6200 2550
Wire Wire Line
	6100 2500 6100 2600
Wire Wire Line
	6200 3900 6200 5900
Connection ~ 6200 3900
Wire Wire Line
	6400 5900 6400 5400
Connection ~ 6400 5400
$Comp
L 00JG-SHORT U401
U 1 1 534C5202
P 8150 2900
F 0 "U401" H 8000 2950 60  0000 C CNN
F 1 "~" H 8150 2700 60  0000 C CNN
F 2 "" H 8150 2900 60  0000 C CNN
F 3 "" H 8150 2900 60  0000 C CNN
	1    8150 2900
	1    0    0    -1  
$EndComp
$Comp
L 00JG-SHORT U402
U 1 1 534C520F
P 8150 3000
F 0 "U402" H 8000 3050 60  0000 C CNN
F 1 "~" H 8150 2800 60  0000 C CNN
F 2 "" H 8150 3000 60  0000 C CNN
F 3 "" H 8150 3000 60  0000 C CNN
	1    8150 3000
	1    0    0    -1  
$EndComp
Text HLabel 8350 2900 2    50   Output ~ 0
RR/~W
Text HLabel 8350 3000 2    50   Output ~ 0
RDEBUG
Text HLabel 7950 2900 0    50   Output ~ 0
R/~W
Text Notes 7650 3250 0    50   ~ 0
Cut shorts for operation on 5V
Text Label 6300 5700 1    50   ~ 0
DEBUG
Text Label 7950 3000 2    50   ~ 0
DEBUG
$EndSCHEMATC
