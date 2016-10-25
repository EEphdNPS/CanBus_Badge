# CanBus_Badge
As we develop a badge for the upcoming event, I will post my eagle files, bill of materials, and source code here.

I developed the board and schematic in Eagle 7.6.0 light.

This board is based on Microchip's AN212 reference design (http://ww1.microchip.com/downloads/en/AppNotes/00212c.pdf)

Overview: The photoresitor is the input on one node and the PWM-controlled LED on another node is the output. The transmitter CAN ID and recieve CAN ID are based on the position of the DIP switches. The first two switches set the CAN ID of the node and the second two set the CAN ID it will receive from. Setting the first two switches to 0 results in no transmissions from the node. Each node actually has two CAN IDs and will transmit both. Only one of the transmissions is received on the other end. 

I will continue to upload the code soon.
