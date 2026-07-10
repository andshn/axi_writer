`timescale 1ns / 1ps

module axi_writer #(
  parameter AXI_MAX_BURST_SIZE = 128,
  parameter RAM_SIZE = 256 * 1024 * 1024
) (
  //SYSTEM
  input  logic clk,
  input  logic rst,
  //CTRL
  input  logic [7:0] pattern_data,
  input  logic [15:0] pattern_size,
  input  logic pattern_write,
  //M_AXI AW
  output logic [31:0] m_axi_awaddr,
  output logic [1:0] m_axi_awid,
  output logic [1:0] m_axi_awburst,
  output logic [7:0] m_axi_awlen,
  output logic [2:0] m_axi_awsize,
  output logic m_axi_awvalid,
  input  logic m_axi_awready,
  //M_AXI W
  output logic [7:0] m_axi_wdata,
  output logic m_axi_wlast,
  output logic m_axi_wvalid,
  input  logic m_axi_wready,
  //M_AXI B
  input  logic [1:0] m_axi_bid,
  input  logic [1:0] m_axi_bresp,
  input  logic m_axi_bvalid,
  output logic m_axi_bready
);

`define MIN(a, b) ((a) < (b) ? (a) : (b))
`define MIN3(a, b, c) `MIN(`MIN(a, b), c)

localparam RAM_ADDR_WIDTH = $clog2(RAM_SIZE);
localparam AXI_4KB_BOUNDARY = 4096;
localparam AXI_4KB_BOUNDARY_WIDTH = $clog2(AXI_4KB_BOUNDARY) + 1;
localparam AXI_4KB_BOUNDARY_MASK = AXI_4KB_BOUNDARY - 1;

assign m_axi_awid = '0;
assign m_axi_awburst = 2'b01;
assign m_axi_awsize = 3'b000;  // 1 байт на трансфер

logic [7:0] pattern_data_buf;
logic [15:0] pattern_size_buf;

logic [7:0] pattern_data_buf_next;
logic [15:0] pattern_size_buf_next;

logic [RAM_ADDR_WIDTH - 1:0] ram_addr;
logic [RAM_ADDR_WIDTH - 1:0] ram_addr_next;

logic [AXI_4KB_BOUNDARY_WIDTH - 1:0] bytes_to_boundary;
logic [AXI_4KB_BOUNDARY_WIDTH - 1:0] bytes_to_boundary_next;

logic [$clog2(AXI_MAX_BURST_SIZE) - 1:0] w_cnt;
logic [$clog2(AXI_MAX_BURST_SIZE) - 1:0] w_cnt_next;

typedef enum {STATE_IDLE,
              STATE_AW,
              STATE_WDATA,
              STATE_WAIT_B} state_typedef;
state_typedef state, state_next;

always_ff @(posedge clk) begin
  if (rst) begin
    state <= STATE_IDLE;
  end else begin
    state <= state_next;
  end
end

always_ff @(posedge clk) begin
  if (rst) begin
    pattern_data_buf <= '0;
    pattern_size_buf <= '0;
    ram_addr <= '0;
    bytes_to_boundary <= AXI_4KB_BOUNDARY;
    w_cnt <= '0;
  end else begin
    pattern_data_buf <= pattern_data_buf_next;
    pattern_size_buf <= pattern_size_buf_next;
    ram_addr <= ram_addr_next;
    bytes_to_boundary <= bytes_to_boundary_next;
    w_cnt <= w_cnt_next;
  end
end

always_comb begin
  state_next = state;

  case (state)
    STATE_IDLE: begin
      if (pattern_write && (pattern_size != 0)) state_next = STATE_AW;
    end
    STATE_AW: begin
      if (m_axi_awready && m_axi_awvalid) state_next = STATE_WDATA;
    end
    STATE_WDATA: begin
      if (m_axi_wready && m_axi_wvalid && m_axi_wlast) state_next = STATE_WAIT_B;
    end
    STATE_WAIT_B: begin
      if (m_axi_bready && m_axi_bvalid) begin
        state_next = (pattern_size_buf == 0) ? STATE_IDLE : STATE_AW;
      end
    end
  endcase
end

always_comb begin
  automatic logic [$clog2(AXI_MAX_BURST_SIZE):0] burst_bytes;

  pattern_data_buf_next = '0;
  pattern_size_buf_next = '0;
  ram_addr_next = ram_addr;
  bytes_to_boundary_next = bytes_to_boundary;
  // Самое узкое место по таймингам. Но 100 МГц позволяет.
  burst_bytes = `MIN3(bytes_to_boundary, AXI_MAX_BURST_SIZE, pattern_size_buf);

  m_axi_awvalid = 1'b0;
  m_axi_awlen = burst_bytes - 1'b1;
  m_axi_awaddr = ram_addr;

  m_axi_wdata = pattern_data_buf;
  m_axi_wlast = 1'b0;
  m_axi_wvalid = 1'b0;
  w_cnt_next = '0;

  m_axi_bready = 1'b0;

  case (state)
    STATE_IDLE: begin
      pattern_data_buf_next = pattern_data;
      pattern_size_buf_next = pattern_size;
    end
    STATE_AW: begin
      pattern_data_buf_next = pattern_data_buf;
      pattern_size_buf_next = pattern_size_buf;
      m_axi_awvalid = 1'b1;

      if (m_axi_awready) begin
        pattern_size_buf_next = pattern_size_buf - burst_bytes;
        ram_addr_next = ram_addr + burst_bytes;
        w_cnt_next = burst_bytes - 1'b1;
      end
    end
    STATE_WDATA: begin
      w_cnt_next = w_cnt;
      pattern_data_buf_next = pattern_data_buf;
      pattern_size_buf_next = pattern_size_buf;

      m_axi_wvalid = 1'b1;
      m_axi_wlast = (w_cnt == 0);
      if (m_axi_wready) begin
        bytes_to_boundary_next = bytes_to_boundary - 1'b1;
        w_cnt_next = w_cnt - 1'b1;
      end
    end
    STATE_WAIT_B: begin
      pattern_data_buf_next = pattern_data_buf;
      pattern_size_buf_next = pattern_size_buf;

      m_axi_bready = 1'b1;

      if (m_axi_bready && m_axi_bvalid && (bytes_to_boundary == 0)) begin
        bytes_to_boundary_next = AXI_4KB_BOUNDARY;
      end
    end
  endcase
end

endmodule
