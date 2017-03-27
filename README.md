# CanBus_Badge
As we develop a badge for the upcoming event, I will post my eagle files, bill of materials, and source code here.

I developed the board and schematic in Eagle 7.6.0 light.

This board is based on Microchip's AN212 reference design (http://ww1.microchip.com/downloads/en/AppNotes/00212c.pdf)

Overview: The objective of this project is to build a controller area network (CAN) node that can be used during our upcoming hack-a-thon event. Each CAN node is powered by one 9 volt battery. The CAN node has one input and one output. The input is a photoresistor (R12) that is part of a voltage divider. The PIC microcontroller does an analog to digital conversion based on the output of the voltage divider. The CAN node output is a PWM-driven LED (add the part number from the BOM and schematic). The CAN ID of the node is based on the dip switches. The first two switches define the CAN ID when the node transmits the result of the A/D conversion. The last two switches determine which CAN ID the node will receive. The results of A/D conversion are transmitted onto the CAN bus and received by the proper CAN node. The CAN node uses this value to set the pulse width of the on pulse.

5V power regulation:
The current design of the badge uses a 7805 chip to take the 9V battery output and produce 5V for the badge to run. As a note, because the node is powered at 5V, the CAN bus high and low will have a neutral value of 2.5V and the CAN bus high will be 5V and the CAN bus low will be 0V. Added to the power regulation portion of the design is a momentary push button that will indicate whether the badge is on or off. I have not calculated the life of the battery in this application, but during the development of the badge, I've only used one battery and I used one batter to run both nodes that I built. 

PIC 16F876:
The PIC microprocessor is the main chip on the board. The code is (will be) uploaded. The PIC talks to the MCP2515 chip via a SPI interface (pins 3-chip select, 14-SCK, 15-SDI, 16-SDO). Each line of the SPI interface has a test point, which we can use to access the SPI messages during the hack-a-thon. The PIC has one pin (pin 2) for the A/D conversion of the voltage divider. It has one pin (pin 13) as the PWM output. The chip receives a 4 MHz clock signal on pins 9 and 10. Pin 21 on the PIC is connected to the interrupt pin (pin 12) on the MCP2515. Pins 25 and 26 are connected are connected to the receive buffers on the MCP2515. Pins 11, 12, 17, 18 are connected to the DIP switches and are read to determine the transmit CAN ID and which CAN ID will be received. 

MCP2515:
The MCP2515 is the CAN controller chip and handles all CAN messaging. Pins 1 and 2 are connected to the MCP2551. The LEDs off of these lines are used as a visual indication that there is communication between these two chips. There are also test points added to these lines to access the messages being transmitted and received between the two chips. This chip operates with a 16 MHz oscillator on pins 7 and 8. I believe this frequency determines the bit rate on the CAN bus.

MCP2551:
The MCP2551 is a simple chip that interfaces with the CAN bus. This chip is probably not actually needed in this design. I have not tested whether or not it is required. We could probably skip it and connect the MCP2515 directly to another MCP2515 on another node. Pin 6 in the CAN low pin. Pin 7 is the CAN high pin. Pin 8 must be connected to ground via 10K ohm resistor. This pin sets the various modes of the MCP2551 chip. Without this resistor the CAN nodes will not communicate properly. 

CAN Bus:
To build the CAN bus, two 120 ohm resistors are required. These two resistors connect the high and low CAN bus wires at the termination of each end of the bus. At this point, I do not know a limit on the number of nodes that can be added to the bus without significant collisions. I have tested two nodes. If we have more, we could determine the max number that can be added. After trying several different configurations, I've settled on directly connecting the badges. There is no need for the 120 ohm resistors.

I've used the CanaKit UK1300 to program the PICs that I used on my breadboard. The ICSP works on the breadboard I've been developing from. I was not able to test it with Rev 1.0. I used the PICKit 3. 


