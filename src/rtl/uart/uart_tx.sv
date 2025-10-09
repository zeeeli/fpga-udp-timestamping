module uart_tx #(
    parameter int unsigned DATA_BITS = 8,  // ASCII needs 1 byte to send letter
    parameter int unsigned STOP_BITS = 1   // Stop bits for 8N1 UART
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 baud_tick, // 1-cycle enable at bit rate (from baud_gen)

    input  logic                 tx_valid,  // Flag to send byte
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

  logic [  DATA_BITS-1:0] data_q, data_d; // Latched byte
  logic [DATA_BITS_W-1:0] bit_q, bit_d;   // Data bit index (0...DATA_BITS-1)
  logic                   stop_q, stop_d; // Remaining stop bits to transmit (STOP_BITS...0)
  logic                   tx_d;           // registered value for TX Line

  //--------------------------------------------------------------------------------------------------------
  // FSMD Registers
  //--------------------------------------------------------------------------------------------------------
  always_ff @(posedge clk) begin : registers
    if (rst) begin
      state_reg <= IDLE;
      data_q    <= '0;
      bit_q     <= '0;
      stop_q    <= '0;
      tx        <=  0;
    end else begin
      state_reg <= state_next;
      data_q    <= data_d;
      bit_q     <= bit_d;
      stop_q    <= stop_d;
      tx        <= tx_d;
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // Next State Logic
  //--------------------------------------------------------------------------------------------------------
  always_comb begin : next_state_logic
    // Default (holding) values
    state_next = state_reg;
    data_d     = data_q;
    bit_d      = bit_q;
    stop_d     = stop_q;
    tx_d       = tx;
    case (state_reg)
      IDLE: begin                         // Line idles high and byte is accepted at tx_valid=1
        tx_d = 1'b1;
        if (tx_valid) begin
          data_d     = tx_data;
          bit_d      = '0;
          state_next = START;
        end
      end

      START: begin                        // @ next baud tick, drive start bit for exactly 1 bit time
        if (baud_tick) begin
          tx_d       = 1'b0;              // signals the start of transmission
          state_next = DATA;
        end
      end

      DATA: begin                         // @ each tick, drive current LSB and advance bit index
        if (baud_tick) begin
          tx_d = data_q[bit_q];           // LSB transmitted first
          if (bit_q == DATA_BITS-1) begin // bit index has reached end of data
            state_next = STOP;
          end else begin
            bit_d = bit_q + 1;
          end
        end
      end

      STOP: begin                         // Set line back to IDLE
        if (baud_tick) begin
          tx_d = 1'b1;                    // No stop bit needed in 8N1 UART
          state_next = IDLE;
        end
      end

      default : state_next = IDLE;
    endcase
  end

  //--------------------------------------------------------------------------------------------------------
  // Output Logic
  //--------------------------------------------------------------------------------------------------------
  assign tx_ready = (state_reg == IDLE);
endmodule
