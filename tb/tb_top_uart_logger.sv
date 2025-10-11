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
      .out_delta(out_delta),
      .tx(tx)
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
  task automatic recv_uart_byte(output byte b);
    bit [7:0] data;

    // Wait for falling edge (start bit)
    @(negedge tx);
    // Sample at bit centers
    wait_cycles(BIT_CYCLES/2);
    assert (tx==1'b0) else $error("Start bit not low at center");
    for (int i = 0; i < 8; i++) begin
      wait_cycles(BIT_CYCLES);
      data[i] = tx; // LSB first
    end
    // Stop bit
    wait_cycles(BIT_CYCLES);
    assert (tx == 1'b1) else $error("Stop bit not high");
    b = data;
  endtask

  // concatenating the recieved bytes into an output string
  task automatic recv_n_bytes(
    output string s,
    input int n);
    s = "";
    for (int i = 0; i < n; i++) begin
      byte tmp;
      recv_uart_byte(tmp);
      s = {s, tmp};
    end
  endtask

  string recv, exp;
  // Event Tests
  initial begin
    // default values
    out_valid = 0; out_id = 0; out_start_ts = 0; out_end_ts = 0; out_delta = 0;

    // reset
    wait_cycles(6); rst = 1'b0;

    // Wait for fifo busy to finish
    wait(!dut.u_lfifo.wr_rst_busy && !dut.u_lfifo.rd_rst_busy);
    repeat(2) @(posedge clk);

    // NOTE: Test Event 1

    push_event(16'h0012, 64'h0123_4567_89AB_CDEF,
               64'h0000_0000_0000_00A5, 64'h0000_0000_FEDC_BA98);
    recv_n_bytes(recv, LINE_BYTES);
    exp = "0012,0123456789ABCDEF,00000000000000A5,00000000FEDCBA98\n";
    if (recv != exp) begin
      $display("FAIL E1:\n got: %s\n exp: %s", recv, exp); $fatal;
    end else $display("PASS E1: %s", recv);

    // NOTE: Event 2
    push_event(16'hABCD, 64'hDEAD_BEEF_CAFE_BABE,
               64'h0000_0000_0000_0001, 64'h1122_3344_5566_7788);
    recv_n_bytes(recv, LINE_BYTES);
    exp = "ABCD,DEADBEEFCAFEBABE,0000000000000001,1122334455667788\n";
    if (recv != exp) begin
      $display("FAIL E2:\n got: %s\n exp: %s", recv, exp); $fatal;
    end else $display("PASS E2: %s", recv);

    $display("PASS: top-level logger+UART functional.");
    wait_cycles(200); $finish;
  end
endmodule
