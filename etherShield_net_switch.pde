#include "etherShield.h"

// etherShield_net_switch 
//
// Control a LED by sending text ON/OFF commands to a particular TCP PORT
// Based off the original etherSheild Web demo, modified by
// Hugh Blemings, released under same license as original code which I 
// believe is Public Domain.

// Please modify the following two lines. mac and ip have to be unique
// in your local area network. You can not have the same numbers in
// two devices:
static uint8_t mymac[6] = {0x54,0x55,0x58,0x10,0x00,0x24}; 
static uint8_t myip[4]  = {192,168,31,115};

static uint16_t my_port = 47; // listen port for tcp (max range 1-254)

#define BUFFER_SIZE 500
static uint8_t buf[BUFFER_SIZE+1];

EtherShield es = EtherShield();


// LED anode connects to Pin4 through a 470R to 1k resistor, cathode to ground
#define LED_PIN  4


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

  // Setup the pin for the LED 
  pinMode (LED_PIN, OUTPUT); 
  digitalWrite (LED_PIN, HIGH);  // switch on LED
}


void loop() {
  uint16_t plen, dat_p;
  int8_t cmd;
  byte on_off = 1;

  plen = es.ES_enc28j60PacketReceive (BUFFER_SIZE, buf);

  /* plen will be unequal to zero if there is a valid packet (without crc error) */
  if (plen != 0) {
    // arp is broadcast if unknown but a host may also verify the mac address by sending it to a unicast address.
    if (es.ES_eth_type_is_arp_and_my_ip (buf, plen)) {
      es.ES_make_arp_answer_from_request (buf);
      return;
    }

    // check if ip packets are for us:
    if (es.ES_eth_type_is_ip_and_my_ip(buf,plen) == 0) {
      return;
    }
  
    // Respond to an ICMP (aka ping) packet
    if (buf[IP_PROTO_P] == IP_PROTO_ICMP_V && buf[ICMP_TYPE_P] == ICMP_TYPE_ECHOREQUEST_V) {
      es.ES_make_echo_reply_from_request (buf, plen);
      return;
    }

    // tcp port start, compare only the lower byte
    if (buf[IP_PROTO_P] == IP_PROTO_TCP_V && buf[TCP_DST_PORT_H_P] == 0 && buf[TCP_DST_PORT_L_P] == my_port) {
      if (buf[TCP_FLAGS_P] & TCP_FLAGS_SYN_V) {
        es.ES_make_tcp_synack_from_syn (buf); // make_tcp_synack_from_syn does already send the syn,ack
        return;
      }
      if (buf[TCP_FLAGS_P] & TCP_FLAGS_ACK_V) {
        es.ES_init_len_info(buf); // init some data structures
        dat_p = es.ES_get_tcp_data_pointer();
        if (dat_p == 0) { // we can possibly have no data, just ack:
          if (buf[TCP_FLAGS_P] & TCP_FLAGS_FIN_V) {
            es.ES_make_tcp_ack_from_any (buf);
          }
          return;
        }
        if (strncmp ("ON", (char *) & (buf[dat_p]), 2) == 0) {
          plen = es.ES_fill_tcp_data_p (buf, 0, PSTR("LED ON\n\r"));
          digitalWrite (LED_PIN, HIGH);  // switch on LED
          goto SENDTCP;
        }
        if (strncmp ("OFF", (char *) & (buf[dat_p]), 3) == 0) {
          plen = es.ES_fill_tcp_data_p (buf, 0, PSTR("LED OFF\n\r"));
          digitalWrite (LED_PIN, LOW);  // switch off LED
          goto SENDTCP;
        }

        /* Didn't understand the command */
        plen = es.ES_fill_tcp_data_p (buf, 0, PSTR("WHAT?\n\r"));

SENDTCP: es.ES_make_tcp_ack_from_any (buf); // send ack
         es.ES_make_tcp_ack_with_data (buf,plen); // send data
      }
    }
  }
}

