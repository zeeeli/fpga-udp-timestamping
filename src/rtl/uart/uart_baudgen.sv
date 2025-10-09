module uart_baudgen #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned BAUD   = 1_000_000
) (
    input  logic clk,
    input  logic rst,
    output logic baud_tick  // Pulse 1-cycle when BAUD rate is reached
);

  localparam int unsigned DIV   = (CLK_HZ / BAUD);  // 100 MHz / 1,000,000 -> tick every 100 cycles
  localparam int unsigned CNT_W = (DIV <= 1) ? 1 : $clog2(DIV);

  // Block level counter for baud counting
  logic [CNT_W-1:0] cnt_q;

  // register
  always_ff @(posedge clk) begin : baud_gen
    if (rst) begin
      cnt_q     <= '0;
      baud_tick <= 1'b0;
    end else if (cnt_q == DIV - 1) begin
      cnt_q     <= '0;
      baud_tick <= 1'b1;
    end else begin
      cnt_q     <= cnt_q + 1;
      baud_tick <= 1'b0;
    end
  end
endmodule
