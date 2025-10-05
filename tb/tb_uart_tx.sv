`timescale 1ns / 1ps
module tb_uart_tx;
  logic       clk;
  logic       rst;
  logic       baud_tick;
  logic       tx_valid;
  logic [7:0] tx_data;

  logic       tx_ready;
  logic       tx;

  // Instantiate baud_gen and dut
  uart_baudgen #(
      .CLK_HZ(100_000_000),
      .BAUD  (1_000_000)
  ) baud (
      .clk(clk),
      .rst(rst),
      .baud_tick(baud_tick)
  );

  uart_tx #(
      .DATA_BITS(8),
      .STOP_BITS(1)
  ) dut (
      .clk(clk),
      .rst(rst),
      .baud_tick(baud_tick),
      .tx_valid(tx_valid),
      .tx_data(tx_data),
      .tx_ready(tx_ready),
      .tx(tx)
  );

  // initialize clock and reset
  initial begin
    clk = 0;
    rst = 1;
  end

  always #5 clk = ~clk;  // 100 MHz = 10 ns period

  // Simple test of 1 frame
  initial begin
    repeat (4) @(posedge clk);
    rst = 0;

    // sending byte when system is IDLE (ie. tx_ready = 1)
    @(posedge clk);
    wait (tx_ready);
    tx_data  = 8'h7b;
    tx_valid = 1'b1;
    @(posedge clk);
    tx_valid = 1'b0;

    // capture exactly 10 frame bits at baud boundaries
    $display("Frame (start..D7..stop): ");
    for (int i = 0; i < 10; i++) begin
      @(posedge baud_tick);
      #1step;  // sample after DUT updates
      $display("%0d", tx);
    end
    $display("\n");

    #1000 $finish;
  end
endmodule
