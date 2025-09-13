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
  logic rst = 1;

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
      exp_q.push_back(exp);   // push expected result onto queue
      tb_id_active[id] = 0;   // clear id from scoreboard
      $display("[%0t] END    id=%0d  start=%0d end=%0d delta=%0d  (result expected next cycle)",
               $time, id, exp.start_ts, exp.end_ts, exp.delta);

      // Reset valid to 0 at next cycle
      end_valid = 1'b0;
      @(posedge clk);
    end
  endtask

  //--------------------------------------------------------------------------------------------------------
  // Comparing DUT vs Queue Outputs
  //--------------------------------------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (out_valid) begin
      if (exp_q.size()==0) $fatal("ERROR: DUT produced no results!");
      exp_t exp = exp_q.pop_front();

      // compare expected vs outputs individual fields
      if (out_id       !== exp.id)       $fatal("ID mismatch: got %0d, exp %0d", out_id, exp.id);
      if (out_start_ts !== exp.start_ts) $fatal("start_ts mismatch: got %0d, exp %0d", out_start_ts, exp.start_ts);
      if (out_end_ts   !== exp.end_ts)   $fatal("end_ts mismatch: got %0d, exp %0d", out_end_ts, exp.end_ts);
      if (out_delta    !== exp.delta)    $fatal("delta mismatch: got %0d, exp %0d", out_delta, exp.delta);
      $display("[%0t] OUT    id=%0d  start=%0d end=%0d delta=%0d  (OK)", $time, out_id, out_start_ts, out_end_ts, out_delta);
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // Stimulus
  //--------------------------------------------------------------------------------------------------------
  initial begin
    // default values
    start_valid = 0; start_id = 0; end_valid = 0; end_id = '0; out_ready = 1; // ready stays high for pulse

    // dumpfile if needed
    $dumpfile("tb_ev_timer_v1.vcd"); $dumpvars(0, tb_ev_timer_v1);

    // reset
    repeat (4) @(posedge clk);
    rst = 0;
    @(posedge clk);

    // Scenario 1 => Start to end datapath with ID = 3
    drive_start(3);
    repeat (5) @(posedge clk);
    drive_end(3);
    @(posedge clk); // Out here

    // Scenario 2 => Burst -> start 0,1,2 then end 1,0,2 (out of order)
    drive_start(0); drive_start(1); drive_start(2);
    repeat (3) @(posedge clk);
    drive_end(1); drive_end(0); drive_end(2);

    // Scenario 3 => same-ID, same-cycle: Testing end-wins hazard control
    drive_start(5); repeat (2) @(posedge clk);
    // assert both in same cycle
    start_id = 5; start_valid = 1; end_id = 5; end_valid = 1;
    @(posedge clk);
    if (end_ready && end_valid) begin
      $display("[%0t] COLLISION: END fired (wins); START will retry next", $time);
    end
    end_valid = 0;
    do @(posedge clk); while (!start_ready);  // start succeeds after end clears
    tb_id_active[5] = 1; tb_start_ts[5] = tb_cnt; start_valid = 0;
    repeat (4) @(posedge clk); drive_end(5);

    repeat(10) @(posedge clk);
    $display("All Checks Passed.");
    $finish;
  end
endmodule
