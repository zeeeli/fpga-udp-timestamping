module uart_tx #(
    parameter int unsigned DATA_BITS = 8,  // ASCII needs 1 byte to send letter
    parameter int unsigned STOP_BITS = 1   // Stop bits for 8N1 UART
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 baud_tick, // 1-cycle enable at bit rate (from baud_gen)

    input  logic                 tx_valid,  // Flag to send by when tx_ready = 1
    input  logic [DATA_BITS-1:0] tx_data,
    output logic                 tx_ready,  // Pulse: when idle state and ready for new byte

    output logic                 tx         // Serial line (idle high)
);

  //--------------------------------------------------------------------------------------------------------
  // FSM State Declaration
  //--------------------------------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;
  state_t state_reg, state_next;

  //--------------------------------------------------------------------------------------------------------
  // Internal Registers (Datapath)
  //--------------------------------------------------------------------------------------------------------
  localparam int unsigned DATA_BITS_W = $clog2(DATA_BITS);
  localparam int unsigned STOP_BITS_W = $clog2(STOP_BITS+1);

  logic [  DATA_BITS-1:0] data_q, data_d; // Latched byte
  logic [DATA_BITS_W-1:0] bit_q, bit_d;   // Data bit index (0...DATA_BITS-1)
  logic [STOP_BITS_W-1:0] stop_q, stop_d; // Remaining stop bits to transmit (STOP_BITS...0)

  //--------------------------------------------------------------------------------------------------------
  // TODO: FSMD Registers, State-Transition Logic, and Output-Logic
  //--------------------------------------------------------------------------------------------------------

endmodule
