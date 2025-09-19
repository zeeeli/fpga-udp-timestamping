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
    .out_start_ts(out_start_ts), .out_end_ts(out_end_ts),   .out_ts(out_delta)
  );

  //--------------------------------------------------------------------------------------------------------
  // Misc. signals
  //--------------------------------------------------------------------------------------------------------
  // For post collision-hazard test (where queue is empty)
  bit              skip_one_output;
  logic [ID_W-1:0] skip_id;

  //--------------------------------------------------------------------------------------------------------
  // Backpressure Generator (To test out_ready holding)
  //--------------------------------------------------------------------------------------------------------
  // always_ff @(posedge clk) begin : gen_backpressure
  //   if (!rst) begin
  //     out_ready <= ($urandom_range(0,4) != 0);  // 80% chance of being high
  //   end
  // end
  // bit bp_enable;
  // always_ff @(posedge clk) begin : gen_backpressure
  //   if (rst) begin
  //     out_ready <= 1'b0;
  //     bp_enable <= 1'b0;
  //   end else begin
  //     if (!bp_enable) begin
  //       // enable only when there's > 0 expected items to pop
  //       if (exp_q.size() != 0) begin
  //         bp_enable <= 1'b1;
  //         out_ready <= 1'b1;          // first handshake can occur now
  //       end else begin
  //         out_ready <= 1'b0;          // Hold low until queue has struct
  //       end
  //     end else begin
  //       // Randomize out_ready when Backpressure is active
  //       out_ready <= ($urandom_range(0,4) != 0);    // 80% chance of being high
  //     end
  //   end
  // end

  //--------------------------------------------------------------------------------------------------------
  // Testbench Scoreboard and RAM
  //--------------------------------------------------------------------------------------------------------
  typedef struct packed {
    logic [ID_W-1:0] id;
    logic [TS_W-1:0] start_ts;
    logic [TS_W-1:0] end_ts;
    logic [TS_W-1:0] delta;
  } exp_t;

  exp_t exp_rec;  // for handshake task (xvlog likes it outside task scope)
  exp_t exp_comp; // for DUT vs expected comparison

  // Queue for expected outputs
  exp_t exp_q[$];

  // RAM
  logic            tb_id_active [2**ID_W];
  logic [TS_W-1:0] tb_start_ts  [2**ID_W];

  // Initializing values
  initial begin
    foreach (tb_id_active[i]) tb_id_active[i] = 1'b0;
    foreach (tb_start_ts[i])  tb_start_ts[i]  =   '0;
  end

  //--------------------------------------------------------------------------------------------------------
  // Drivers (Handshake Helper Functions)
  //--------------------------------------------------------------------------------------------------------
  task automatic drive_start(input logic [ID_W-1:0] id);
    begin
      start_id    = id;
      start_valid = 1'b1;

      // Hold valid until handshake (ie. when valid AND ready on same edge)
      do @(posedge clk); while (!start_ready);

      // After handshake, update scoreboard
      tb_id_active[id] = 1'b1;
      tb_start_ts[id]  = dut.cnt_q;
      $display("[%0t] START  id=%0d ts=%0d (valid_at_start==0 so ts accepted)", $time, id, dut.cnt_q);

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
      exp_rec          = '{default:'0};
      exp_rec.id       = id;
      exp_rec.start_ts = tb_start_ts[id];  // Pull start from scoreboard
      exp_rec.end_ts   = dut.cnt_q;  // Timestamp at end
      exp_rec.delta    = exp_rec.end_ts - exp_rec.start_ts;
      $display("[%0t] PUSH exp: id=%0d start=%0d end=%0d delta=%0d",
                $time, exp_rec.id, exp_rec.start_ts, exp_rec.end_ts, exp_rec.delta);

      exp_q.push_back(exp_rec);   // push expected result onto queue

      tb_id_active[id] = 0;   // clear id from scoreboard
      $display("[%0t] END    id=%0d  start=%0d end=%0d delta=%0d  (result expected next cycle)",
               $time, id, exp_rec.start_ts, exp_rec.end_ts, exp_rec.delta);

      // Reset valid to 0 at next cycle
      end_valid = 1'b0;
      @(posedge clk);
    end
  endtask

  //--------------------------------------------------------------------------------------------------------
  // Checker
  //--------------------------------------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      skip_one_output <= 0;
    end else if (out_valid && out_ready) begin
      // NOTE: For Collision-hazard END state that never pushes to queue
      if (skip_one_output) begin
        // Checks to permit skipping the queue pop
        if (out_id !== skip_id) $fatal("Collision output ID mismatch. Got %0d expected %0d", out_id, skip_id);
        $display("[%0t] NOTE: Skipping compare for manual collision END on id=%0d", $time, skip_id);
        skip_one_output <= 1'b0;
      end else begin
        if (exp_q.size() == 0) $fatal("ERROR: DUT produced no results!");
        exp_comp = exp_q.pop_front();  // Blocking fine because only temp variable

        // sanity check of popped struct
        $display("[%0t] POP exp: id=%0d start=%0d end=%0d delta=%0d", $time, exp_comp.id,
                 exp_comp.start_ts, exp_comp.end_ts, exp_comp.delta);

        // compare expected vs outputs individual fields
        if (out_id       !== exp_comp.id)       $fatal("ID mismatch: got %0d, exp %0d", out_id, exp_comp.id);
        if (out_start_ts !== exp_comp.start_ts) $fatal("start_ts mismatch: got %0d, exp %0d", out_start_ts, exp_comp.start_ts);
        if (out_end_ts   !== exp_comp.end_ts)   $fatal("end_ts mismatch: got %0d, exp %0d", out_end_ts, exp_comp.end_ts);
        if (out_delta    !== exp_comp.delta)    $fatal("delta mismatch: got %0d, exp %0d", out_delta, exp_comp.delta);
        $display("[%0t] OUT    id=%0d  start=%0d end=%0d delta=%0d  (OK)", $time, out_id,
                 out_start_ts, out_end_ts, out_delta);
      end
    end
  end

  //--------------------------------------------------------------------------------------------------------
  // Handling out_valid Hold Race condition (delay out_ready by one cycle)
  //--------------------------------------------------------------------------------------------------------
  bit next_ready;

  initial begin
    out_ready  = 1'b0;  // held low during reset; change if you want always-ready
    next_ready = 1'b1;  // or randomize this later
  end

  always @(negedge clk) begin
    if (rst) out_ready <= 1'b0;
    else out_ready <= next_ready;  // decide next_ready anywhere you like
  end

  //--------------------------------------------------------------------------------------------------------
  // Stimulus
  //--------------------------------------------------------------------------------------------------------
  initial begin
    // default values
    start_valid = 0; start_id = '0;
    end_valid   = 0; end_id   = '0;
    // out_ready   = 1; // NOTE: Commented so out_ready holds not pulse

    // dumpfile if needed
    $dumpfile("tb_ev_timer_v1.vcd"); $dumpvars(0, tb_ev_timer_v1);

    // reset for 4 clock cycles
    repeat (4) @(posedge clk);
    rst = 0;
    @(posedge clk);

    // Scenario 1 => Start to end datapath with ID = 3
    drive_start(3);
    repeat (5) @(posedge clk);
    drive_end(3);
    out_ready = 1'b0;
    repeat (5) @(posedge clk); // Out here
    out_ready = 1'b1;

    // Scenario 2 => Burst -> start 0,1,2 then end 1,0,2 (out of order)
    drive_start(0); drive_start(1); drive_start(2);
    repeat (3) @(posedge clk);
    drive_end(1); drive_end(0); drive_end(2);

    // Scenario 3 => same-ID, same-cycle: Testing end-wins hazard control
    drive_start(5); repeat (2) @(posedge clk);
    // assert both in same cycle
    start_id = 5; start_valid = 1;
    end_id   = 5; end_valid   = 1;
    @(posedge clk);
    if (end_ready && end_valid) begin
      $display("[%0t] COLLISION: END fired (wins); START will retry next", $time);
      // Notify Checker that an END was created with the queue empty so skip
      // output
      skip_one_output = 1'b1;
      skip_id         = 5;      // Same id in this test
    end
    end_valid = 0;
    do @(posedge clk); while (!start_ready);  // start succeeds after end clears
    tb_id_active[5] = 1; tb_start_ts[5] = dut.cnt_q; start_valid = 0;
    repeat (4) @(posedge clk); drive_end(5);

    repeat(10) @(posedge clk);
    $display("All Checks Passed.");
    $finish;
  end
endmodule
