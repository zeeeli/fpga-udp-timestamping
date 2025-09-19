`timescale 1ns / 1ps
module event_timestamper #(
    parameter int unsigned ID_W = 4,      // Width of event IDs
    parameter int unsigned TS_W = 64      // Width of timestamp counter
) (
    input logic clk,
    input logic rst,

    // Event Start
    input  logic            start_valid,  // Pulse: High while start is pending
    output logic            start_ready,  // Hold:  Unit is ready to start counting
    input  logic [ID_W-1:0] start_id,     // Hold:  ID of event

    // Event End
    input  logic            end_valid,    // Pulse: High while timestamp end is pending
    output logic            end_ready,    // Hold:  Unit is ready to end counting
    input  logic [ID_W-1:0] end_id,       // Hold:  ID of event (meant to match start)

    // Output Record
    output logic            out_valid,    // Pulse: High when results is ready
    input  logic            out_ready,    // Hold:  Tells downstream it can get timestamp
    output logic [ID_W-1:0] out_id,       // Hold:  ID of event
    output logic [TS_W-1:0] out_start_ts, // Hold:  Timestamp caputred at the start
    output logic [TS_W-1:0] out_end_ts,   // Hold:  Timestamp caputred at the end
    output logic [TS_W-1:0] out_ts        // Hold:  True timestamp (end - start)
);

  //--------------------------------------------------------------------------------------------------------
  //Free Running Counter
  //--------------------------------------------------------------------------------------------------------
  logic [TS_W-1:0] cnt_q;
  always_ff @(posedge clk) begin : timestamp
    if (rst) cnt_q <= '0;
    else     cnt_q <= cnt_q + 1'b1;
  end

  //--------------------------------------------------------------------------------------------------------
  // Scoreboard Storage
  //--------------------------------------------------------------------------------------------------------
  // NOTE: Need to track start timestamps by id and ids in use
  localparam int unsigned DEPTH = (2**ID_W);   // RAM is as deep as different id values

  // Per-ID start timestamp
  logic [TS_W-1:0] start_ts_mem [DEPTH];       // Stores the timestamp caputred at start of ID event
  logic            valid_mem    [DEPTH];       // Flag: if valid_mem[id] == 1 then id is "active"

  // Clearing RAM
  always_ff @(posedge clk) begin : valid_mem_clear
    if (rst) begin
      for (int i = 0; i < DEPTH; i++) begin
        valid_mem[i] <= '0;
      end
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // Hazards
  //--------------------------------------------------------------------------------------------------------
  // Current scoreboard state @ ID request
  logic valid_at_start, valid_at_end;
  assign valid_at_start = valid_mem[start_id];    // Check if ID already in flight
  assign valid_at_end   = valid_mem[end_id];      // Check if ID has already started

  // Same-cycle and Same-ID Hazard
  logic hazard_same_id;
  assign hazard_same_id = start_valid && end_valid && (start_id == end_id);

  //--------------------------------------------------------------------------------------------------------
  // Handshakes and Output Hold Registers
  //--------------------------------------------------------------------------------------------------------
  // Output holding registers
  logic                 out_valid_q;
  logic [ID_W-1:0]      out_id_q;
  logic [TS_W-1:0]      out_start_q, out_end_q, out_ts_q;

  assign out_valid    = out_valid_q;
  assign out_id       = out_id_q;
  assign out_start_ts = out_start_q;
  assign out_end_ts   = out_end_q;
  assign out_ts       = out_ts_q;

  // === Checking for backpressure ===
  // Check output hold reg being full (1=reg empty, 0=reg not popped yet)
  // register also emptys when the data is popped this cycle (normal operation)
  logic  outq_can_accept;
  assign outq_can_accept = (!out_valid_q) || (out_valid && out_ready);

  // === End Handshake ===
  // Internal signal to notify cycle can END
  logic  end_can_fire;
  assign end_can_fire = valid_at_end      && outq_can_accept;

  // Port level
  assign end_ready    = end_can_fire;
  assign end_fire     = end_valid         && end_ready;

  // === Start Handshake ===
  // start_ready -> block start if END wants to and it can fire
  logic start_fire;
  assign start_ready  = (!valid_at_start) && !(hazard_same_id && end_valid && end_can_fire);
  assign start_fire   = start_valid       && start_ready;

  //--------------------------------------------------------------------------------------------------------
  // Writing Into Scoreboard
  //--------------------------------------------------------------------------------------------------------
  // On start fire, keep current timestamp and ID active
  always_ff @(posedge clk) begin : write_start_to_scoreboard
    if (start_fire) begin
      start_ts_mem[start_id] <= cnt_q;
      valid_mem[start_id]    <= 1'b1;
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // End Path Pipeline (out_valid Holds until out_ready)
  //--------------------------------------------------------------------------------------------------------
  // pipeline registers
  logic                 end_fire_q;  // end_fire delayed 1 cycle
  logic [ID_W-1:0]      end_id_q;
  logic [TS_W-1:0]      end_ts_q;    // Timestamp at the end
  logic [TS_W-1:0]      start_ts_q;  // Fetched start timestamp

  always_ff @(posedge clk) begin : end_pipeline
    if (rst) begin
      end_fire_q  <= 1'b0;
      end_id_q    <= '0;
      end_ts_q    <= '0;
      start_ts_q  <= '0;
    end else begin
      end_fire_q  <= end_fire;
      if (end_fire) begin
        end_id_q          <= end_id;
        end_ts_q          <= cnt_q;                  // Capturing end time
        start_ts_q        <= start_ts_mem[end_id];   // Comb. read of start time
        valid_mem[end_id] <= 1'b0;                   // Make ID free again
      end
    end
  end

  // Output w/ out_valid held
  always_ff @(posedge clk) begin : held_output
    if (rst) begin
      out_valid_q   <= 1'b0;
      out_id_q      <= '0;
      out_start_q   <= '0;
      out_end_q     <= '0;
      out_ts_q      <= '0;
    end else begin
      // POP: Consumer took current registered output
      if (out_valid && out_ready) begin
        out_valid_q <= 1'b0;
      end

      // PUSH: New item in pipeline to load into holding output register
      // Works because end_ready is gated by outq_can_accept
      if (end_fire_q) begin
        out_valid_q <= 1'b1;                     // NOTE: Holding out_valid
        out_id_q    <= end_id_q;
        out_start_q <= start_ts_q;
        out_end_q   <= end_ts_q;
        out_ts_q    <= end_ts_q - start_ts_q;
      end
    end
  end
endmodule
