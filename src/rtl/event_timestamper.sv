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

  //--------------------------
  //Free Running Counter
  //--------------------------
  logic [TS_W-1:0] cnt_q;
  always_ff @(posedge clk) begin : timestamp
    if (rst) cnt_q <= '0;
    else     cnt_q <= cnt_q + 1'b1;
  end

  // TODO: Scoreboard, handshakes, data pipelining, and outputs

  //--------------------------
  // Scoreboard Storage
  //--------------------------
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

  //--------------------------
  // Handshakes and Hazards
  //--------------------------
  // Current scoreboard state @ ID request
  logic valid_at_start, valid_at_end;
  assign valid_at_start = valid_mem[start_id];    // Check if ID already in flight
  assign valid_at_end   = valid_mem[end_id];      // Check if ID has already started

  // Same-cycle and Same-ID Hazard
  logic hazard_same_id;
  assign hazard_same_id = start_valid && end_valid && (start_id == end_id);
endmodule
