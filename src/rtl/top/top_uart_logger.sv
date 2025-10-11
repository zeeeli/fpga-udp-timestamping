module top_uart_logger #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD   = 1_000_000,
    parameter int ID_W   = 16,
    parameter int TS_W   = 64
) (
    input logic clk,
    input logic rst,

    // Timestamper ports
    input  logic            out_valid,
    output logic            out_ready,
    input  logic [ID_W-1:0] out_id,
    input  logic [TS_W-1:0] out_start_ts,
    input  logic [TS_W-1:0] out_end_ts,
    input  logic [TS_W-1:0] out_delta,

    output logic tx
);

  // TODO: Parametrize everything
  localparam int ID_NIB     = (ID_W + 3) / 4;
  localparam int TS_NIB     = (TS_W + 3) / 4;
  localparam int LINE_BYTES = ID_NIB + 3*TS_NIB + 4; // ID Bytes + 3 TS Bytes + 3 commas + '\n'

  //--------------------------------------------------------------------------------------------------------
  // Internal Registers
  //--------------------------------------------------------------------------------------------------------
  // Packer -> Fifo Registers
  logic       pack_wr_en;
  logic [7:0] pack_din;
  logic       fifo_full;
  logic       fifo_pfull;

  // FIFO -> UART Registers
  logic       baud_tick;
  logic       tx_valid;
  logic [7:0] tx_data;
  logic       tx_ready;
  logic       fifo_empty;

  // Fifo busy flags + a gated rd_en
  logic wr_busy, rd_busy;
  wire  fifo_ready = ~wr_busy & ~rd_busy;

  //--------------------------------------------------------------------------------------------------------
  // Packer -> FIFO
  //--------------------------------------------------------------------------------------------------------
  logger_ev_packer #(
      .TS_W(TS_W),
      .ID_W(ID_W)
  ) u_pack (
      .clk           (clk),
      .rst           (rst),
      .ev_valid      (out_valid),
      .ev_ready      (out_ready),
      .ev_id         (out_id),
      .ev_start      (out_start_ts),
      .ev_end        (out_end_ts),
      .ev_delta      (out_delta),
      .fifo_wr_en    (pack_wr_en),
      .fifo_din      (pack_din),
      .fifo_full     (fifo_full),
      .fifo_prog_full(fifo_pfull)
  );

  logger_fifo_xpm #(
      .DEPTH(256),
      .PROG_FULL_THRESH(256 - LINE_BYTES),
      .FWFT(1)
  ) u_lfifo (
      .clk        (clk),
      .rst        (rst),
      .wr_en      (pack_wr_en),
      .din        (pack_din),
      .full       (fifo_full),
      .prog_full  (fifo_pfull),
      .rd_en      (tx_ready & ~fifo_empty),
      .dout       (tx_data),
      .empty      (fifo_empty),
      .wr_rst_busy(wr_busy),
      .rd_rst_busy(rd_busy)
  );

  assign tx_valid  = fifo_ready ? ~fifo_empty : 1'b0;

  //--------------------------------------------------------------------------------------------------------
  // FIFO -> UART
  //--------------------------------------------------------------------------------------------------------
  uart_tx u_tx (
      .clk      (clk),
      .rst      (rst),
      .baud_tick(baud_tick),
      .tx_valid (tx_valid),
      .tx_data  (tx_data),
      .tx_ready (tx_ready),
      .tx       (tx)
  );

  uart_baudgen #(
      .CLK_HZ(CLK_HZ),
      .BAUD  (BAUD)
  ) u_bg (
      .clk      (clk),
      .rst      (rst),
      .baud_tick(baud_tick)
  );
endmodule
