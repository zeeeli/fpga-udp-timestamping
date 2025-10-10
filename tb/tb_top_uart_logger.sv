`timescale 1ns / 1ps
module tb_top_uart_logger;
  logic        clk;
  logic        rst;
  logic        out_valid;
  logic        out_ready;
  logic [15:0] out_id;
  logic [63:0] out_start_ts;
  logic [63:0] out_end_ts;
  logic [63:0] out_delta;
  logic        tx;

  // Top instantiation
  top_uart_logger #(
      .CLK_HZ(100_000_000),
      .BAUD  (1_000_000)
  ) dut (
      .clk(clk),
      .rst(rst),
      .out_valid(out_valid),
      .out_ready(out_ready),
      .out_id(out_id),
      .out_start_ts(out_start_ts),
      .out_end_ts(out_end_ts),
      .out_delta(out_delta)
  );

  // initializes clock and reset
  initial begin
    clk = 0;
    rst = 1;
  end

  always #5 clk = ~clk;  // 100 Hz = 10 ns period

  // UART sampling local params
  localparam int BIT_CYCLES = 100;  // 100 MHz / 1 Mbps
  localparam int LINE_BYTES = 56;  // Size of outputted packet

  // Helper Functions
  task automatic wait_cycles(input int n);
    repeat (n) begin
      @(posedge clk);
    end
  endtask

  // ready valid handshake and event generation
  task automatic push_event(
    input logic [15:0] id,
    input logic [63:0] start,
    input logic [63:0] en,
    input logic [63:0] delta);

    @(posedge clk); wait (out_ready);
    out_id         <= id;
    out_start_ts   <= start;
    out_end_ts     <= en;
    out_delta      <= delta;
    out_valid      <= 1'b1;
    @(posedge clk);
    out_valid      <= 1'b0;
  endtask

  // UART Rx to monitor tx line
  function automatic byte recv_uart_byte ();
    byte b;

    // Wait for falling edge (start bit)
    @(negedge tx);
    // Sample at bit centers
    wait_cycles(BIT_CYCLES/2);
    assert (tx==1'b0) else $error("Start bit not low at center");
    for (int i = 0; i < 8; i++) begin
      wait_cycles(BIT_CYCLES);
      b[i] = tx; // LSB first
    end
    // Stop bit
    wait_cycles(BIT_CYCLES);
    assert (tx == 1'b1) else $error("Stop bit not high");
    return b;
  endfunction

  task automatic recv_n_bytes(
    output string s,
    input int n);
    s = "";
    for (int i = 0; i < n; i++) begin
      s = {s, recv_uart_byte()};
    end
  endtask
endmodule
