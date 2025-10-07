// Accept event from timestamper -> pack data into 56 ASCII bytes -> Write
// into FIFO
//  => (ID(4 bytes), ',', START_TS(16), ',', END(16), ',', DELTA(16),'\n')
//  => comma delimiter and line break escape char are included in packet
module uart_ev_packer #(
    parameter int unsigned TS_W = 64,
    parameter int unsigned ID_W = 16
) (
    input logic             clk,
    input logic             rst,

    // Event ports
    input  logic            ev_valid,
    output logic            ev_ready,
    input  logic [ID_W-1:0] ev_id,
    input  logic [TS_W-1:0] ev_start,
    input  logic [TS_W-1:0] ev_end,
    input  logic [TS_W-1:0] ev_delta,

    // Synch FIFO Write ports
    output logic            fifo_wr_en,      // Pules: to write tp fifo
    output logic [     7:0] fifo_din,
    input  logic            fifo_full,       // Fifo backpressure handler
    input  logic            fifo_prog_full   // FIFO near full (reserve 56 bytes)
);

  //--------------------------------------------------------------------------------------------------------
  // Internal Registers, Parameters and FSM
  //--------------------------------------------------------------------------------------------------------
  localparam int LINE_BYTES = 56;  // Size of data packet being sent on the line

  // registers for event data
  logic [ID_W-1:0] id_q;
  logic [TS_W-1:0] start_q;
  logic [TS_W-1:0] end_q;
  logic [TS_W-1:0] delta_q;

  // FSM
  typedef enum logic [3:0] {
    IDLE,
    ID,
    C1,     // First comma delimiter
    START,
    C2,     // Second comma delimiter
    END,
    C3,     // Thirs comma delimiter
    DELTA,
    NL      // New line escape char '\n'
  } state_t;

  state_t state_reg, state_next;

  // ASCII Char output register
  logic [7:0] char_d, char_q;

  // Nibble counter to index each hex digit from MSB -> LSB (left to right)
  // ie. 4 nibbles for ID
  logic [3:0] nib_q, nib_d;

  // FIFO handshake => write only when FIFO has space
  logic can_write = ~fifo_full;

  //--------------------------------------------------------------------------------------------------------
  // TODO: Helper Functions
  //--------------------------------------------------------------------------------------------------------
   
endmodule
