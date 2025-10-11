// Top for full design
// - Includes Board interfacing ports
// - Part #: xc7a100tcsg324-1
module top_fpga (
  input  logic clk,            // 100 MHz board clock
  input  logic CPU_RESETN,     // active-low board reset
  input  logic BTNC,           // Back up reset (active high)
  output logic tx              // UART TX line
);

  //--------------------------------------------------------------------------------------------------------
  // Reset Synchronizer (2FF)
  //--------------------------------------------------------------------------------------------------------
  wire rst_async = (~CPU_RESETN) | BTNC;
  logic [1:0] rst_sync;
  always_ff @(posedge clk or posedge rst_async) begin : ff2synch
    if (rst_async) rst_sync <= 2'b11;
    else           rst_sync <= {1'b0, rst_sync[1]};
  end
  wire rst = rst_sync[0]; // NOTE: reset used for RTL hooking up

  //--------------------------------------------------------------------------------------------------------
  // TODO: Add full event time stamper.
  // NOTE: Demo event generator for now
  //--------------------------------------------------------------------------------------------------------
  // Signals for Demo event generation
  logic        out_valid, out_ready;
  logic [15:0] out_id;
  logic [63:0] out_start_ts, out_end_ts, out_delta;

  logger_demo_ev u_demo_ev (
    .clk          (clk),
    .rst          (rst),
    .out_valid    (out_valid),
    .out_ready    (out_ready),
    .out_id       (out_id),
    .out_start_ts (out_start_ts),
    .out_end_ts   (out_end_ts),
    .out_delta    (out_delta)
    );

  //--------------------------------------------------------------------------------------------------------
  // UART + Logger Instantiation
  //--------------------------------------------------------------------------------------------------------
  top_uart_logger #(
    .CLK_HZ       (100_000_000),
    .BAUD         (1_000_000),
    .ID_W         (16),
    .TS_W         (64)
  ) u_uart(
    .clk          (clk),
    .rst          (rst),
    .out_valid    (out_valid),
    .out_ready    (out_ready),
    .out_id       (out_id),
    .out_start_ts (out_start_ts),
    .out_end_ts   (out_end_ts),
    .out_delta    (out_delta),
    .tx           (tx)
    );
endmodule
