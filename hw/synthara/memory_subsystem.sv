// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

/* verilator lint_off UNUSED */
/* verilator lint_off MULTIDRIVEN */

module memory_subsystem
  import obi_pkg::*;
#(
    parameter NUM_BANKS = 2
) (
    input logic clk_i,
    input logic rst_ni,

    // Clock-gating signal
    input logic [NUM_BANKS-1:0] clk_gate_en_ni,

    input  obi_req_t  [NUM_BANKS-1:0] ram_req_i,
    output obi_resp_t [NUM_BANKS-1:0] ram_resp_o,

    // power manager signals that goes to the ASIC macros
    input logic [core_v_mini_mcu_pkg::NUM_BANKS-1:0] pwrgate_ni,
    output logic [core_v_mini_mcu_pkg::NUM_BANKS-1:0] pwrgate_ack_no,
    input logic [core_v_mini_mcu_pkg::NUM_BANKS-1:0] set_retentive_ni
);

  logic [NUM_BANKS-1:0] ram_valid_q;
  // Clock-gating
  logic [NUM_BANKS-1:0] clk_cg;

  logic [13-1:0] ram_req_addr_0;
  logic [13-1:0] ram_req_addr_1;


  assign ram_req_addr_0 = ram_req_i[0].addr[15-1:2];

  assign ram_req_addr_1 = ram_req_i[1].addr[15-1:2];

  for (genvar i = 0; i < NUM_BANKS; i++) begin : gen_sram

    tc_clk_gating clk_gating_cell_i (
        .clk_i,
        .en_i(clk_gate_en_ni[i]),
        .test_en_i(1'b0),
        .clk_o(clk_cg[i])
    );

    always_ff @(posedge clk_cg[i] or negedge rst_ni) begin
      if (!rst_ni) begin
        ram_valid_q[i] <= '0;
      end else begin
        ram_valid_q[i] <= ram_resp_o[i].gnt;
      end
    end

    assign ram_resp_o[i].gnt = ram_req_i[i].req;
    assign ram_resp_o[i].rvalid = ram_valid_q[i];
  end

  // TODO: temp parameters to allow compilation
  parameter TB_AXI4_WORD_NUM_BITS = 32;
  parameter TB_AXI4_ADDRESS_NUM_BITS = 32;
  // Create the rule for the address map: start address is the staring address as per linker script
  // The addr_length defines the addressable storage space in each slave ComputeRAM
  parameter longint unsigned ADDR_MAP_0_START = 32'h80000000;
  // 12 bits used to address the 32bits word in the storage part of the ComputeRAM
  // 14 bits used to address the 1byte word in the storage part of the ComputeRAM
  parameter longint unsigned STORAGE_SPACE_BYTE_SIZE = (4096 - 0) * 4;

  logic[NUM_BANKS-1:0][TB_AXI4_WORD_NUM_BITS-1:0] axi_mem_wdata_o;
  logic[NUM_BANKS-1:0][14-1:0]                    axi_mem_addr_14b;
  logic[NUM_BANKS-1:0][TB_AXI4_WORD_NUM_BITS-1:0] axi_mem_be_32b, r_axi_mem_be_32b;
  logic[NUM_BANKS-1:0]                            axi_mem_we_o;
  logic[NUM_BANKS-1:0]                            axi_mem_req_o;
  logic[NUM_BANKS-1:0][TB_AXI4_WORD_NUM_BITS-1:0] axi_mem_rdata_i, masked_axi_mem_rdata_i;
  logic[NUM_BANKS-1:0] IRQ;  // irq from the memory banks

  logic[NUM_BANKS-1:0][TB_AXI4_WORD_NUM_BITS/8-1:0] axi_mem_strb_o;
  logic[NUM_BANKS-1:0][TB_AXI4_ADDRESS_NUM_BITS-1:0] axi_mem_addr_o;
  logic[NUM_BANKS-1:0] axi_mem_rvalid_n, axi_mem_gnt_n;  // delayed read valid signal
  logic[NUM_BANKS-1:0] axi_mem_gnt_i;
  logic[NUM_BANKS-1:0] axi_mem_rvalid_i;


  cxr_ssm ram0_i(
      // Connect ports using the specified format
      .CLK(clk_cg[0]),
      .RSTN(rst_ni),
      .D(axi_mem_wdata_o[0]),  // write data
      .A(axi_mem_addr_14b[0]),  // address common for read and write
      .BW(axi_mem_be_32b[0]),  // byte write enable
      .RDWEN(!axi_mem_we_o[0]),  // read-write enable read=1 write=0
      .CEN(!axi_mem_req_o[0]),  // chip enable active low
      .Q(axi_mem_rdata_i[0]),  // read data
      .IRQ(IRQ[0])
  );

  always_comb begin
    // Extend the mem_strb_o from 4 bits to 32 bits, each bit must be extended 8 times
    for (int bit_idx = 0; bit_idx < TB_AXI4_WORD_NUM_BITS; bit_idx++) begin
        axi_mem_be_32b[0][bit_idx] = axi_mem_strb_o[0][bit_idx / 8];
    end
    // axi_mem_be_32b[0] = 32'hffffffff;

    for (int bit_idx = 0; bit_idx < TB_AXI4_WORD_NUM_BITS; bit_idx++) begin
        if (axi_mem_rdata_i[0][bit_idx] !== 1'bx) begin
            masked_axi_mem_rdata_i[0][bit_idx] = axi_mem_rdata_i[0][bit_idx];
        end else begin
            masked_axi_mem_rdata_i[0][bit_idx] = axi_mem_rdata_i[0][bit_idx] && r_axi_mem_be_32b[0][bit_idx];
        end
    end

    /* Conversion from 32bit byte address to 14b word address of ComputeRAM 
        axi_mem_addr_14b = ( axi_mem_addr_o - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 0 ) >> shift
        common_offset = ADDR_MAP_0_START
        specific_offset = STORAGE_SPACE_BYTE_SIZE 
        shift = 2 to pass from byte addr to word addr
    */
    axi_mem_addr_14b[0] =  ( axi_mem_addr_o[0] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 0  )  >> 2;
    /* axi_mem_we_o = !RDWEN    AND   axi_mem_req_o = !CE  means a read in this clock cycle */
    axi_mem_rvalid_n[0] =  /* axi_mem_we_o[0] && */ axi_mem_req_o[0];
    /* memory always responds after 1 clock cycle for write and read so, if we just delay the reuqest signal to have the gnt */
    axi_mem_gnt_i[0] = axi_mem_req_o[0];
  end

  always_ff@(posedge clk_cg[0] or negedge rst_ni) begin
    if (rst_ni == 0) begin
        axi_mem_rvalid_i[0] <= '0;
        // axi_mem_gnt_i[0] <= '0;
        r_axi_mem_be_32b[0] <= '0;
    end else begin
        axi_mem_rvalid_i[0] <= axi_mem_rvalid_n[0];
        // axi_mem_gnt_i[0] <= axi_mem_gnt_n[0];
        r_axi_mem_be_32b[0] <= axi_mem_be_32b[0];
    end
  end


  cxr_ssm ram1_i(
      // Connect ports using the specified format
      .CLK(clk_cg[1]),
      .RSTN(rst_ni),
      .D(axi_mem_wdata_o[1]),  // write data
      .A(axi_mem_addr_14b[1]),  // address common for read and write
      .BW(axi_mem_be_32b[1]),  // byte write enable
      .RDWEN(!axi_mem_we_o[1]),  // read-write enable read=1 write=0
      .CEN(!axi_mem_req_o[1]),  // chip enable active low
      .Q(axi_mem_rdata_i[1]),  // read data
      .IRQ(IRQ[1])
  );

  always_comb begin
    // Extend the mem_strb_o from 4 bits to 32 bits, each bit must be extended 8 times
    for (int bit_idx = 0; bit_idx < TB_AXI4_WORD_NUM_BITS; bit_idx++) begin
        axi_mem_be_32b[1][bit_idx] = axi_mem_strb_o[1][bit_idx / 8];
    end
    // axi_mem_be_32b[1] = 32'hffffffff;

    for (int bit_idx = 0; bit_idx < TB_AXI4_WORD_NUM_BITS; bit_idx++) begin
        if (axi_mem_rdata_i[1][bit_idx] !== 1'bx) begin
            masked_axi_mem_rdata_i[1][bit_idx] = axi_mem_rdata_i[1][bit_idx];
        end else begin
            masked_axi_mem_rdata_i[1][bit_idx] = axi_mem_rdata_i[1][bit_idx] && r_axi_mem_be_32b[1][bit_idx];
        end
    end

    /* Conversion from 32bit byte address to 14b word address of ComputeRAM 
        axi_mem_addr_14b = ( axi_mem_addr_o - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 1 ) >> shift
        common_offset = ADDR_MAP_0_START
        specific_offset = STORAGE_SPACE_BYTE_SIZE 
        shift = 2 to pass from byte addr to word addr
    */
    axi_mem_addr_14b[1] =  ( axi_mem_addr_o[1] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 1  )  >> 2;
    /* axi_mem_we_o = !RDWEN    AND   axi_mem_req_o = !CE  means a read in this clock cycle */
    axi_mem_rvalid_n[1] =  /* axi_mem_we_o[1] && */ axi_mem_req_o[1];
    /* memory always responds after 1 clock cycle for write and read so, if we just delay the reuqest signal to have the gnt */
    axi_mem_gnt_i[1] = axi_mem_req_o[1];
  end

  always_ff@(posedge clk_cg[1] or negedge rst_ni) begin
    if (rst_ni == 0) begin
        axi_mem_rvalid_i[1] <= '0;
        // axi_mem_gnt_i[1] <= '0;
        r_axi_mem_be_32b[1] <= '0;
    end else begin
        axi_mem_rvalid_i[1] <= axi_mem_rvalid_n[1];
        // axi_mem_gnt_i[1] <= axi_mem_gnt_n[1];
        r_axi_mem_be_32b[1] <= axi_mem_be_32b[1];
    end
  end


endmodule
