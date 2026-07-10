`timescale 1ns / 1ps

module axi_writer_tb;

parameter AXI_MAX_BURST_SIZE = 128;

parameter DATA_WIDTH = 8;
parameter RAM_SIZE = 128 * 1024; // 256 МБ слишком много для тестбенча.
parameter RAM_ADDR_WIDTH = $clog2(RAM_SIZE);
parameter MAX_PATTERN_SIZE = 10_000;
parameter RANDOM_DATA_REPEAT = 100; // Сколько раз повторять тест со случайными данными.

parameter MAX_READY_DELAY = 10;

//CTRL
logic [7:0] pattern_data;
logic [15:0] pattern_size;
logic pattern_write;

//M_AXI AW
logic [31:0] m_axi_awaddr;
logic [1:0] m_axi_awid;
logic [1:0] m_axi_awburst;
logic [7:0] m_axi_awlen;
logic [2:0] m_axi_awsize;
logic m_axi_awvalid;
logic m_axi_awready;

//M_AXI W
logic [7:0] m_axi_wdata;
logic m_axi_wlast;
logic m_axi_wvalid;
logic m_axi_wready;

//M_AXI B
logic [1:0] m_axi_bid;
logic [1:0] m_axi_bresp;
logic m_axi_bvalid;
logic m_axi_bready;

logic clk = 1'b0;
logic rst = 1'b1;

logic [DATA_WIDTH - 1:0] mem [RAM_SIZE - 1:0];
assign mem = axi_writer_tb.axi_ram_inst.mem;

// Эталонная память.
bit [DATA_WIDTH - 1:0] mem_ref [RAM_SIZE - 1:0];

always #2.5 clk = !clk;

bit [RAM_ADDR_WIDTH - 1:0] ref_addr = 0;

function automatic void ref_write(
  input [DATA_WIDTH - 1:0] data,
  input [15:0] size,
  ref bit [DATA_WIDTH - 1:0] mem_ref [RAM_SIZE - 1:0]
);
  for (int i = 0; i < size; i++) begin
    mem_ref[ref_addr] = data;
    ref_addr = ref_addr + 1;
    if (ref_addr >= RAM_SIZE) ref_addr = 0;
  end
endfunction

task automatic ctrl_write(
  input [DATA_WIDTH - 1:0] data,
  input [15:0] size,
  ref bit [DATA_WIDTH - 1:0] mem_ref [RAM_SIZE - 1:0]
);
  int w_count = 0;

  ref_write(data, size, mem_ref);
  pattern_data = data;
  pattern_size = size;
  pattern_write = 1'b1;
  @(posedge clk);
  pattern_write = 1'b0;

  while (w_count < size) begin
    @(posedge clk);
    if (m_axi_wvalid && m_axi_wready) w_count++;
  end
  while (!(m_axi_bvalid && m_axi_bready)) @(posedge clk);
  @(posedge clk);
endtask

// Проверка подразумевает то, что модуль axi_ram зануляет память при сбросе.
function automatic void compare_mem(
  ref logic [DATA_WIDTH - 1:0] mem_actual[RAM_SIZE - 1:0],
  ref bit [DATA_WIDTH - 1:0] mem_ref[RAM_SIZE - 1:0]
);
  for (int i = 0; i < RAM_SIZE; i++) begin
    if (mem_actual[i] !== mem_ref[i]) begin
      $fatal(1, "Mismatch at addr %0d: actual=%02x, expected=%02x",
             i, mem_actual[i], mem_ref[i]);
    end
  end
  $display("Memory comparison PASSED");
endfunction

always_ff @(posedge clk) begin

end

initial begin
  pattern_data = 8'd0;
  pattern_size = 16'd0;
  pattern_write = 1'b0;
  ref_addr = 0;

  rst = 1'b1;
  repeat(5) @(posedge clk);
  rst = 1'b0;
  repeat(5) @(posedge clk);

  $display("Test: 4KB boundary crossing");
  ctrl_write(8'h11, 16'd4000, mem_ref);
  ctrl_write(8'h22, 16'd100, mem_ref);
  repeat(5) @(posedge clk);
  compare_mem(mem, mem_ref);

  $display("Test: Circular buffer wrap-around");
  repeat(10) ctrl_write(8'h11, 16'd4000, mem_ref);
  ctrl_write(8'h22, 16'd10000, mem_ref);
  ctrl_write(8'h33, 16'd10000, mem_ref);
  ctrl_write(8'h44, 16'd10000, mem_ref);
  repeat(5) @(posedge clk);
  compare_mem(mem, mem_ref);

  $display("Test: Random data");
  repeat(RANDOM_DATA_REPEAT) begin
    ctrl_write($urandom_range(0, (1 << DATA_WIDTH) - 1), $urandom_range(1, MAX_PATTERN_SIZE), mem_ref);
    compare_mem(mem, mem_ref);
  end

  $display("ALL TESTS PASSED");
  $finish;
end

property p_no_4kb_cross;
  @(posedge clk) disable iff (rst)
  (m_axi_awvalid && m_axi_awready) |->
  ((m_axi_awaddr[11:0] + m_axi_awlen + 1) <= 4096);
endproperty

a_no_4kb_cross: assert property(p_no_4kb_cross)
  else $fatal(1, "Burst crosses 4KB boundary! awaddr=%h, awlen=%0d",
              m_axi_awaddr, m_axi_awlen);

axi_writer #(
  .AXI_MAX_BURST_SIZE(AXI_MAX_BURST_SIZE),
  .RAM_SIZE(RAM_SIZE)
) dut (
  // SYSTEM
  .clk(clk),
  .rst(rst),
  // CTRL
  .pattern_data(pattern_data),
  .pattern_size(pattern_size),
  .pattern_write(pattern_write),
  // M_AXI AW
  .m_axi_awaddr(m_axi_awaddr),
  .m_axi_awid(m_axi_awid),
  .m_axi_awburst(m_axi_awburst),
  .m_axi_awlen(m_axi_awlen),
  .m_axi_awsize(m_axi_awsize),
  .m_axi_awvalid(m_axi_awvalid),
  .m_axi_awready(m_axi_awready),
  // M_AXI W
  .m_axi_wdata(m_axi_wdata),
  .m_axi_wlast(m_axi_wlast),
  .m_axi_wvalid(m_axi_wvalid),
  .m_axi_wready(m_axi_wready),
  // M_AXI B
  .m_axi_bid(m_axi_bid),
  .m_axi_bresp(m_axi_bresp),
  .m_axi_bvalid(m_axi_bvalid),
  .m_axi_bready(m_axi_bready)
);

axi_ram #(
  .DATA_WIDTH(8),
  .ADDR_WIDTH(RAM_ADDR_WIDTH),
  .STRB_WIDTH(1),
  .ID_WIDTH(2),
  .PIPELINE_OUTPUT(0)
) axi_ram_inst (
  .clk(clk),
  .rst(rst),

  // AW Channel
  .s_axi_awid(m_axi_awid),
  .s_axi_awaddr(m_axi_awaddr[RAM_ADDR_WIDTH - 1:0]),
  .s_axi_awlen(m_axi_awlen),
  .s_axi_awsize(m_axi_awsize),
  .s_axi_awburst(m_axi_awburst),
  .s_axi_awlock(1'b0),
  .s_axi_awcache(4'b0000),
  .s_axi_awprot(3'b000),
  .s_axi_awvalid(m_axi_awvalid),
  .s_axi_awready(m_axi_awready),

  // W Channel
  .s_axi_wdata(m_axi_wdata),
  .s_axi_wstrb(1'b1),
  .s_axi_wlast(m_axi_wlast),
  .s_axi_wvalid(m_axi_wvalid),
  .s_axi_wready(m_axi_wready),

  // B Channel
  .s_axi_bid(m_axi_bid),
  .s_axi_bresp(m_axi_bresp),
  .s_axi_bvalid(m_axi_bvalid),
  .s_axi_bready(m_axi_bready),

  // AR Channel (не используется)
  .s_axi_arid('0),
  .s_axi_araddr('0),
  .s_axi_arlen(8'h00),
  .s_axi_arsize(3'b000),
  .s_axi_arburst(2'b01),
  .s_axi_arlock(1'b0),
  .s_axi_arcache(4'b0000),
  .s_axi_arprot(3'b000),
  .s_axi_arvalid(1'b0),
  .s_axi_arready(),

  // R Channel (не используется)
  .s_axi_rid(),
  .s_axi_rdata(),
  .s_axi_rresp(),
  .s_axi_rlast(),
  .s_axi_rvalid(),
  .s_axi_rready(1'b0)
);
endmodule
