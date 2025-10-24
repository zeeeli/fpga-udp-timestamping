module logger_fifo_xpm #(
    parameter int DEPTH            = 256,
    parameter int PROG_FULL_THRESH = DEPTH - 57,  // Depth - length of LINE_BYTE
    parameter bit FWFT             = 1            // First word fall through
) (
    input logic clk,
    input logic rst,

    // Write side
    input  logic       wr_en,
    input  logic [7:0] din,
    output logic       full,
    output logic       prog_full,

    // Read side
    input  logic       rd_en,
    output logic [7:0] dout,
    output logic       empty,

    // Busy flags
    output logic wr_rst_busy,
    output logic rd_rst_busy
);

  xpm_fifo_sync #(
      .FIFO_MEMORY_TYPE ("auto"),
      .ECC_MODE         ("no_ecc"),
      .FIFO_WRITE_DEPTH (DEPTH),
      .WRITE_DATA_WIDTH (8),
      .READ_DATA_WIDTH  (8),
      .READ_MODE        (FWFT ? "fwft" : "std"),
      .FIFO_READ_LATENCY(FWFT ? 0 : 1),
      .PROG_FULL_THRESH (PROG_FULL_THRESH)
  ) u_fifo (
      .rst        (rst),
      .wr_clk     (clk),
      .din        (din),
      .wr_en      (wr_en),
      .full       (full),
      .prog_full  (prog_full),
      .dout       (dout),
      .rd_en      (rd_en),
      .empty      (empty),
      .data_valid (),
      .wr_rst_busy(wr_rst_busy),
      .rd_rst_busy(rd_rst_busy),
      .sleep      (1'b0)
  );
endmodule
