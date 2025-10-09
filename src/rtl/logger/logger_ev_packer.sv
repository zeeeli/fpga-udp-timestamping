// Accept event from timestamper -> pack data into 56 ASCII bytes -> Write
// into FIFO
//  => (ID(4 bytes), ',', START_TS(16), ',', END(16), ',', DELTA(16),'\n')
//  => comma delimiter and line break escape char are included in packet
module logger_ev_packer#(
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
  // Helper Functions
  //--------------------------------------------------------------------------------------------------------
  // Turn a 4-bit nibble (1 hex digit) into ASCII character
  // Example: ID = 16'h12AB =>
  //          ID[3] = 1 = 8'h31 -> char('1')
  //          ID[2] = 2 = 8'h32 -> char('2')
  //          ID[1] = A = 8'h41 -> char('A')
  //          ID[0] = B = 8'h42 -> char('B')
  function automatic [7:0] nib2hex(input logic [3:0] n);
    if (n<10) begin
      hex8 = 8'h30 + n;          // Numbers => 0,1,2,...9
    end else begin
      hex8 = 8'h41 + (n-10);     // Letters => A, B, C,...
    end
  endfunction

  // Extracting 4-bit Nibbles from ID from MSB -> LSB (left -> right)
  // idx*4 is the bit offset of the nibble (eg. idx=3 => shift by 12)
  // w >> (idx*4) => shifts the nibble to extract to bit[3:0]
  // & 4'hF       => masks all other bits but bit[3:0]
  // Example: w = 16'h12AB
  //          idx=3 -> Shift by 12 -> 0x0001 -> nibble(1)
  //          idx=2 -> Shift by 8  -> 0x0012 -> nibble(2)
  //          idx=1 -> Shift by 4  -> 0x012A -> nibble(A)
  //          idx=0 -> Shift by 0  -> 0x12AB -> nibble(B)
  function automatic [3:0] pickNib16(input logic [15:0] w, input logic [3:0] idx);
    pickNib16 = (w >> (idx*4)) & 4'hF;
  endfunction

  // Similar to pickNib16 but for 64 bit (Timestamps)
  function automatic [3:0] pickNib64(input logic [63:0] w, input logic [3:0] idx);
    pickNib64 = (w >> (idx*4)) & 4'hF;
  endfunction

  // Hex for comma and linebreak
  localparam logic [7:0] COMMA = 8'h2C;
  localparam logic [7:0] NEWLINE    = 8'h0A;

  //--------------------------------------------------------------------------------------------------------
  // FSMD Registers
  //--------------------------------------------------------------------------------------------------------
  always_ff @(posedge clk) begin : state_registers
    if (rst) begin
      state_reg <= IDLE;
      nib_q     <= '0;
      id_q      <= '0;
      start_q   <= '0;
      end_q     <= '0;
      delta_q   <= '0;
      char_q    <= 8'h00;
    end else begin
      state_reg <= state_next;
      nib_q     <= nib_d;
      char_q    <= char_d;
      // Latch the record once when ev handshake occurs
      if (state_reg == IDLE && ev_valid && ev_ready) begin
        id_q    <= ev_id;
        start_q <= ev_start;
        end_q   <= ev_end;
        delta_q <= ev_delta;
      end
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // Next-state Logic
  //--------------------------------------------------------------------------------------------------------
  always_comb begin : next_state_logic
    // default
    state_next = state_reg;
    nib_d      = nib_q;
    char_d     = char_q;

    // We dont write to FIFO by default
    fifo_wr_en = 1'b0;
    fifo_din   = char_q;

    case (state_reg)
      // Handshake event then initialize hex index nibble
      IDLE: begin
        if (ev_valid && ev_ready) begin
          state_next = IDLE;
          nib_d      = 4'd3; // MSB of hex index
        end
      end

      ID: begin
        char_d = nib2hex(pickNib16(id_q , nib_q));  // Convert ID nibble into Hex char for ASCII output
        // Write ID char to FIFO
        if (can_write) begin
          fifo_wr_en = 1'b1;
          fifo_din   = char_d;
          if (nib_q == 4'd0) begin  // whole ID chars has been stored
            state_next = C1;
          end else begin
            nib_d = nib_q - 1;
          end
        end
      end

      C1: begin
        char_d = COMMA;
        if (can_write) begin
          fifo_wr_en = 1'b1;
          fifo_din   = char_d;
          state_next = START;
          nib_d      = 4'd15;   // Preparing nibble idx for TS (16 nibbles in 64 bits)
        end
      end

      START: begin
        char_d = nib2hex(pickNib64(start_q, nib_q));
        if (can_write) begin
          fifo_wr_en = 1'd1;
          fifo_din   = char_d;
          if (nib_q == 4'd0) begin
            state_next = C2;
          end else begin
            nib_d    = nib_q - 1;
          end
        end
      end

      C2: begin
        char_d = COMMA;
        if (can_write) begin
          fifo_wr_en = 1'b1;
          fifo_din   = char_d;
          state_next = END;
          nib_d      = 4'd15;
        end
      end

      END: begin
        char_d = nib2hex(pickNib64(end_q, nib_q));
        if (can_write) begin
          fifo_wr_en = 1'd1;
          fifo_din   = char_d;
          if (nib_q == 4'd0) begin
            state_next = C3;
          end else begin
            nib_d    = nib_q - 1;
          end
        end
      end

      C3: begin
        char_d = COMMA;
        if (can_write) begin
          fifo_wr_en = 1'b1;
          fifo_din   = char_d;
          state_next = DELTA;
          nib_d      = 4'd15;
        end
      end

      DELTA: begin
        char_d = nib2hex(pickNib64(delta_q, nib_q));
        if (can_write) begin
          fifo_wr_en = 1'd1;
          fifo_din   = char_d;
          if (nib_q == 4'd0) begin
            state_next = NL;
          end else begin
            nib_d    = nib_q - 1;
          end
        end
      end

      NL: begin
        char_d = NEWLINE;
        if (can_write) begin
          fifo_wr_en = 1'b1;
          fifo_din   = char_d;
          state_next = IDLE;
        end
      end
      default : state_next = IDLE;
    endcase
  end

  //--------------------------------------------------------------------------------------------------------
  // Output Logic
  //--------------------------------------------------------------------------------------------------------
  assign ev_ready = (state_reg == IDLE) && ~fifo_prog_full;
endmodule
