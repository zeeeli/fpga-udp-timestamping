// Early testbench version to test scoreboard, handshake, 1-cycle output pipeline, and
// hazard control
`timescale 1ns / 1ps

module tb_ev_timer_v1;
  //--------------------------------------------------------------------------------------------------------
  // Parameters
  //--------------------------------------------------------------------------------------------------------
  localparam int ID_W = 3;  // 2^3 => 8 total IDs
  localparam int TS_W = 8;  // 2^8 => 256 cycles


  //--------------------------------------------------------------------------------------------------------
  // DUT Signals
  //--------------------------------------------------------------------------------------------------------
  logic             start_valid, start_ready;
  logic [ID_W-1:0]  start_id;

  logic             end_valid, end_ready;
  logic [ID_W-1:0]  end_id;

  logic             out_valid, out_ready;
  logic [ID_W-1:0]  out_id;
  logic [TS_W-1:0]  out_start_ts, out_end_ts, out_delta;

  //--------------------------------------------------------------------------------------------------------
  // Clock and Reset
  //--------------------------------------------------------------------------------------------------------
  // 200 MHz Clock => 5ns
  logic clk = 0;
  always #2.5 clk = ~clk;

  // Reset (active high)
  logic rst = 0;

  //--------------------------------------------------------------------------------------------------------
  // Instantiate DUT
  //--------------------------------------------------------------------------------------------------------
  event_timestamper #(.ID_W(ID_W), .TS_W(TS_W)) dut (
    .clk(clk),
    .rst(rst),
    .start_valid(start_valid),   .start_ready(start_ready), .start_id(start_id),
    .end_valid(end_valid),       .end_ready(end_ready),     .end_id(end_id),
    .out_valid(out_valid),       .out_ready(out_ready),     .out_id(out_id),
    .out_start_ts(out_start_ts), .out_end_ts(out_end_ts),   .out_ts(out_ts)
  );

  //--------------------------------------------------------------------------------------------------------
  // Testbench Counter
  //--------------------------------------------------------------------------------------------------------
  logic [TS_W-1:0] tb_cnt;
  always_ff @(posedge clk) begin : tb_counter
    if (rst) begin
      tb_cnt <= '0;
    end else begin
      tb_cnt <= dut.cnt_q;
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // Testbench Scoreboard and RAM
  //--------------------------------------------------------------------------------------------------------
  typedef struct packed {
    logic [ID_W-1:0] id;
    logic [ID_W-1:0] start_ts;
    logic [ID_W-1:0] end_ts;
    logic [ID_W-1:0] delta;
  } exp_t;

  // RAM
  logic            tb_id_active [2**ID_W];
  logic [TS_W-1:0] tb_start_ts  [2**ID_W];

  // Queue for expected outputs
  exp_t exp_q[$];

  //--------------------------------------------------------------------------------------------------------
  // Handshake Helper Functions
  //--------------------------------------------------------------------------------------------------------
  task automatic drive_start(input logic [ID_W-1:0] id);
    begin
      start_id    = id;
      start_valid = 1'b1;

      // Hold valid until handshake (ie. when valid AND ready on same edge)
      do @(posedge clk); while (!start_ready);

      // After handshake, update scoreboard
      tb_id_active[id] = 1'b1;
      tb_start_ts[id]  = tb_cnt;
      $display("[%0t] START  id=%0d ts=%0d (valid_at_start==0 so ts accepted)", $time, id, tb_cnt);

      // Reset valid to 0 at next cycle
      start_valid = 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic drive_end(input logic [ID_W-1:0] id);
    begin
      end_id    = id;
      end_valid = 1'b1;

      // Hold valid until handshake (ie. when valid AND ready on same edge)
      do @(posedge clk); while (!end_ready);

      // After handshake, compute output (struct)
      exp_t exp;
      exp.id       = id;
      exp.end_ts   = tb_cnt;  // Timestamp at end
      exp.start_ts = tb_start_ts;  // Pull start from scoreboard
      exp.delta    = exp.end_ts - exp.start_ts;
      $display("[%0t] END    id=%0d  start=%0d end=%0d delta=%0d  (result expected next cycle)",
               $time, id, exp.start_ts, exp.end_ts, exp.delta);

      // Reset valid to 0 at next cycle
      end_valid = 1'b0;
      @(posedge clk);
    end
  endtask


endmodule
