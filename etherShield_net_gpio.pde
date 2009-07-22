#include "etherShield.h"

// etherShield_net_gpio
//
// Provide basic general purpose I/O (GPIO) functionality
// over a network connection.  User can remotely read, write
// and set direction (Input or Output) for the free pins on the
// Arduino/EthernetShield combo
//
// Based off the original etherSheild Web demo, modified by
// Hugh Blemings, released under same license as original code which I 
// believe is Public Domain.

// Please modify the following two lines. mac and ip have to be unique
// in your local area network. You can not have the same numbers in
// two devices:
static uint8_t mymac[6] = {0x54,0x55,0x58,0x10,0x00,0x24}; 
static uint8_t myip[4]  = {192,168,31,115};

static uint16_t my_port = 47; // listen port for tcp (max range 1-254)

// Define size and allocate memory used for packets
#define BUFFER_SIZE 500
static uint8_t buf[BUFFER_SIZE+1];

// Create an EthernetShield object
EtherShield es = EtherShield();


// Define the which I/O pins are available - these
// are PD0-7 (Digital 0-7), PB0 and PB1 (Digital 8 & 9 
// respectively).  The remaining pins are used to 
// talk to the Ethernet chip so we don't touch them
#define AVAILABLE_IO_PINS (10)

// Enumerate the pins we can use, others are used to interface
// with the etherShield itself.
static uint8_t io_pin_list[AVAILABLE_IO_PINS] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};


// Store mode (0 = INPUT, 1 = OUTPUT) for the pins we can use
// and the output state if an output.
//
// Arrays are indexed linearly rather than by I/O pin number
static uint8_t io_pin_mode[AVAILABLE_IO_PINS];
static uint8_t io_pin_state[AVAILABLE_IO_PINS];


// Support functions to manage I/O pins
//
// Set the mode of the pins on the basis of the internal 
// array that contains the mode for each.
void set_io_pins_mode()
{
	uint8_t count;
 
	for (count = 0; count < AVAILABLE_IO_PINS; count++) {
		if (io_pin_mode[count] == OUTPUT) {
			pinMode(io_pin_list[count], OUTPUT);
		}
		else {
			pinMode(io_pin_list[count], INPUT);
		}
	}
}

// Update the state of any pins that are configured as 
// outputs on the basis of the internal array that contains
// the required state.
void set_output_pins()
{
	uint8_t count;
 
	for (count = 0; count < AVAILABLE_IO_PINS; count++) {
		if (io_pin_mode[count] == OUTPUT) {
			digitalWrite(io_pin_list[count], io_pin_state[count]);
		}
	}
}

// Initialise the arrays that contain mode and state, and
// then set the physical pins themselves.
void init_io_pins() 
{
	uint8_t count;
 
	// Initialise arrays then configure physical pins
	for (count = 0; count < AVAILABLE_IO_PINS; count++) {
		io_pin_mode[count] = INPUT;
		io_pin_state[count] = LOW;
	}
	set_io_pins_mode();
	set_output_pins(); // For completeness - should all be inputs
}



// Return 1 if pin number is valid, zero otherwise
char validate_pin_number(unsigned char pin)
{
	int i;

	for (i = 0; i <= AVAILABLE_IO_PINS; i++) {
		if (pin == io_pin_list[i]) {
			return 1;
		}
	}
	return 0;
}

// Handle the Config Pin command
void handle_cfg_command(char *cmd, uint16_t *plen)
{
	unsigned int pin;
	char response[11];
	char mode = '-';

	if (sscanf(cmd, "%*c%d%c", &pin, &mode) != 2) {
		sprintf(response, "!PARSE ");
		goto EXIT;
	}
	if (!validate_pin_number(pin)) {
		sprintf(response, "!BADPIN ");
		goto EXIT;
	}
	if (mode == 'I') {
		pinMode(pin, INPUT);
		sprintf(response, "C%dI ", pin);
		goto EXIT;
	}
	if (mode == 'O') {
		pinMode(pin, OUTPUT);
		sprintf(response, "C%dO ", pin);
		goto EXIT;
	}
	sprintf(response, "!PARSE ");

EXIT:
	*plen = es.ES_fill_tcp_data (buf, *plen, response);
}

// Handle the Set Pin command
void handle_set_command(char *cmd, uint16_t *plen)
{
	uint8_t pin, state;
	char response[11];

	if (sscanf(cmd, "%*c%d=%d", &pin, &state) != 2) {
		sprintf(response, "!PARSE ");
		goto EXIT;
	}
	if (!validate_pin_number(pin)) {
		sprintf(response, "!BADPIN ");
		goto EXIT;
	}
	if (state == 1) {
		digitalWrite(pin, HIGH);
		sprintf(response, "S%d=1 ", pin);
	}
	else {
		digitalWrite(pin, LOW);
		sprintf(response, "S%d=0 ", pin);
	}

EXIT:
	*plen = es.ES_fill_tcp_data (buf, *plen, response);

}

// Handle the Read command
void handle_read_command(uint16_t *plen) 
{
	uint8_t count;
	char response[8];
	uint8_t pin, state;

	for (count = 0; count < AVAILABLE_IO_PINS; count++) {
		pin = io_pin_list[count];
		state = 0;
		if (io_pin_mode[count] == INPUT) {
			if (digitalRead(pin) == HIGH) {
				state = 1;
			}
 			sprintf(response, "R%dI%d ", pin, state);
		}
		else {
			state = io_pin_state[count];
 			sprintf(response, "R%dO%d ", pin, state);
		}
		*plen = es.ES_fill_tcp_data (buf, *plen, response);
	}

}


// Here are the commands supported, case sensitive
//
// Multiple commands per line, separated by a space  are accepted
// but only one read command will be responded to per line.
//
// An unrecognised command will abort processing of any remaining
// commands.
//
// Maximum length of a single command string is 255 characters
// including terminating CRLF and NULL.
//
// Cnm  - Configure I/O line 'n' to mode 'm'
//        C7I - Digital I/O 7 Input
//        C9O - Digital I/O 9 Output - pin is set low to begin with
//
//        Response OK, ERROR
//
// R    - Read I/Os  - returns state of all the pins in 
//        form 'Rnms' where n is pin number, m is mode (I or O)
//        and s is the state (0 or 1) eg.
//        R0I1 R1I0 ... R9O0
//
// Sn=s - Set digitial I/O 'n' to state 's'
//        S1=1 - Set I/O 1 to HIGH
//        S9=0 - Set I/O 9 to LOW
//
//        Response OK, ERROR

// Define and allocate buffer used for commands themselves
// doesn't need to be global, but having it so saves
// continually allocating/freeing space on stack.
#define MAX_COMMAND_LENGTH (80)
char cmd_buf[MAX_COMMAND_LENGTH];

uint16_t parse_commands(uint16_t dat_p, unsigned char len) 
{
	unsigned char i = 0;

	uint16_t plen = 0;

	// First we make a copy off the command out of the main TCP buffer
	// as buf[] is re-used to generate the return message
	while ((i < len) && (i < MAX_COMMAND_LENGTH) && (buf[dat_p + i]) != 0) {
		cmd_buf[i] = (char) buf[dat_p + i];
		i++;
	}

	i = 0;

	while ((i < len) && (cmd_buf[i] != 0)) {
		switch(cmd_buf[i]) {
			/* Skip any space or CRLF characters */
		case ' ': 
		case '\n':
		case '\r':
			i ++;
			break;
			
		case 'C' :
			handle_cfg_command(cmd_buf + i, &plen);

			// Skip over command which is 3 or 4 chars
			// parser will just ignore extras
			i += 3;
			break;

		case 'S' :
			handle_set_command(cmd_buf + i, &plen);

			i += 4; // 4 or 5 for a S command
			break;

		case 'R' :
			handle_read_command(&plen);
			i++;
			break;

		default:
			i++;
			break;
		}
	}

	return plen;

}


void setup() {
	/*initialize enc28j60*/
	es.ES_enc28j60Init (mymac);
	es.ES_enc28j60clkout (2); // change clkout from 6.25MHz to 12.5MHz
	delay (10);

	/* Magjack leds configuration, see enc28j60 datasheet, page 11 */
	// LEDA=greed LEDB=yellow

	// 0x880 is PHLCON LEDB=on, LEDA=on
	// enc28j60PhyWrite(PHLCON,0b0000 1000 1000 00 00);
	es.ES_enc28j60PhyWrite (PHLCON,0x880);
	delay (500);

	// 0x990 is PHLCON LEDB=off, LEDA=off
	// enc28j60PhyWrite(PHLCON,0b0000 1001 1001 00 00);
	es.ES_enc28j60PhyWrite (PHLCON,0x990);
	delay (500);

	// 0x880 is PHLCON LEDB=on, LEDA=on
	// enc28j60PhyWrite(PHLCON,0b0000 1000 1000 00 00);
	es.ES_enc28j60PhyWrite (PHLCON,0x880);
	delay (500);

	// 0x990 is PHLCON LEDB=off, LEDA=off
	// enc28j60PhyWrite(PHLCON,0b0000 1001 1001 00 00);
	es.ES_enc28j60PhyWrite (PHLCON,0x990);
	delay (500);

	// 0x476 is PHLCON LEDA=links status, LEDB=receive/transmit
	// enc28j60PhyWrite(PHLCON,0b0000 0100 0111 01 10);
	es.ES_enc28j60PhyWrite (PHLCON,0x476);
	delay (100);

	//init the ethernet/ip layer:
	es.ES_init_ip_arp_udp_tcp (mymac, myip, my_port);

}



void loop() {
	uint16_t plen, dat_p;
	int8_t cmd;
	byte on_off = 1;

	plen = es.ES_enc28j60PacketReceive (BUFFER_SIZE, buf);

	// plen will be non-zero if there is a valid packet (without crc error)
	if (plen != 0) {
		// arp is broadcast if unknown but a host may also verify
		// the mac address by sending it to a unicast address.
		if (es.ES_eth_type_is_arp_and_my_ip (buf, plen)) {
			es.ES_make_arp_answer_from_request (buf);
			return;
		}

		// check if ip packets are for us:
		if (es.ES_eth_type_is_ip_and_my_ip(buf,plen) == 0) {
			return;
		}
  
		// Respond to an ICMP (aka ping) packet
		if (buf[IP_PROTO_P] == IP_PROTO_ICMP_V &&
		    buf[ICMP_TYPE_P] == ICMP_TYPE_ECHOREQUEST_V) {
			es.ES_make_echo_reply_from_request (buf, plen);
			return;
		}

		// tcp port start, compare only the lower byte
		if (buf[IP_PROTO_P] == IP_PROTO_TCP_V && 
		    buf[TCP_DST_PORT_H_P] == 0 &&
		    buf[TCP_DST_PORT_L_P] == my_port) {
			if (buf[TCP_FLAGS_P] & TCP_FLAGS_SYN_V) {
				// make_tcp_synack_from_syn sends the syn,ack
				es.ES_make_tcp_synack_from_syn (buf);
				return;
			}
			if (buf[TCP_FLAGS_P] & TCP_FLAGS_ACK_V) {
				// init some data structures
				es.ES_init_len_info(buf);
				dat_p = es.ES_get_tcp_data_pointer();

				// Check if it's just an ack (no data)
				if (dat_p == 0) {
					if (buf[TCP_FLAGS_P] & TCP_FLAGS_FIN_V) {
						es.ES_make_tcp_ack_from_any (buf);
					}
					return;
				}

				// We've got some data so parse it for commands
				// each command function is responsible for
				// building the return string and updating
				// plen accordingly.
				plen = parse_commands(dat_p, BUFFER_SIZE);

				// Now terminate with CRLF
				plen = es.ES_fill_tcp_data_p (buf, plen, PSTR("\n\r"));
				es.ES_make_tcp_ack_from_any (buf); // send ack
				es.ES_make_tcp_ack_with_data (buf,plen); // send data
			}
		}
	}
}

