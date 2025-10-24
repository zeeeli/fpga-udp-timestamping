// Demo event generator to test Logger + UART subsystem
// Generates event very 0.5 seconds (incremental not random)
module logger_demo_ev #(
    parameter int ID_W          = 16,
    parameter int TS_W          = 64,
    parameter int PERIOD_CYCLES = 50_000_000
) (
    input  logic            clk,
    input  logic            rst,
    output logic            out_valid,
    input  logic            out_ready,
    output logic [ID_W-1:0] out_id,
    output logic [TS_W-1:0] out_start_ts,
    output logic [TS_W-1:0] out_end_ts,
    output logic [TS_W-1:0] out_delta
);

  // Free running counter for timestamps
  logic [TS_W-1:0] cnt_q;
  always_ff @(posedge clk) begin : counter
    if (rst) cnt_q <= '0;
    else cnt_q <= cnt_q + 1;
  end

  // holding registers for event generation
  logic [    31:0] time_gen_q;  // timer for event generation
  logic            out_valid_q;
  logic [ID_W-1:0] out_id_q;
  logic [TS_W-1:0] out_start_q, out_end_q, out_delta_q;

  assign out_valid    = out_valid_q;
  assign out_id       = out_id_q;
  assign out_start_ts = out_start_q;
  assign out_end_ts   = out_end_q;
  assign out_delta    = out_delta_q;

  always_ff @(posedge clk) begin : ev_builder
    if (rst) begin
      time_gen_q  <= PERIOD_CYCLES;
      out_valid_q <= 1'b0;
      out_id_q    <= '0;
    end else begin
      // build event when timer expires and out_valid is low
      if (!out_valid_q) begin
        if (time_gen_q == 0) begin
          out_valid_q <= 1'b1;
          time_gen_q  <= PERIOD_CYCLES;

          out_start_q <= cnt_q;  // set start_ts to counter value
          out_end_q   <= cnt_q + 64'd1000;  // add 1000 to start to demonstrate end_ts
          out_delta_q <= 64'd1000;  // calculate end - start (should always be 1000)

          out_id_q    <= out_id_q + 1'b1;
        end else begin
          time_gen_q <= time_gen_q - 1;
        end
      end

      // handshake for the logger ready
      if (out_valid_q && out_ready) out_valid_q <= 1'b0;
    end
  end
endmodule
