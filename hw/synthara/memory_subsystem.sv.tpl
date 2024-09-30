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

% for i, bank in enumerate(xheep.iter_ram_banks()):
  logic [${bank.size().bit_length()-1 -2}-1:0] ram_req_addr_${i};
% endfor

% for i, bank in enumerate(xheep.iter_ram_banks()):
<%
  p1 = bank.size().bit_length()-1 + bank.il_level()
  p2 = 2 + bank.il_level()
%>
  assign ram_req_addr_${i} = ram_req_i[${i}].addr[${p1}-1:${p2}];
% endfor

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

%for i, bank in enumerate(xheep.iter_ram_banks()):

  cxr_ssm ram${i}_i(
      // Connect ports using the specified format
      .CLK(clk_cg[${i}]),
      .RSTN(rst_ni),
      .D(axi_mem_wdata_o[${i}]),  // write data
      .A(axi_mem_addr_14b[${i}]),  // address common for read and write
      .BW(axi_mem_be_32b[${i}]),  // byte write enable
      .RDWEN(!axi_mem_we_o[${i}]),  // read-write enable read=1 write=0
      .CEN(!axi_mem_req_o[${i}]),  // chip enable active low
      .Q(axi_mem_rdata_i[${i}]),  // read data
      .IRQ(IRQ[${i}])
  );

  always_comb begin
    // Extend the mem_strb_o from 4 bits to 32 bits, each bit must be extended 8 times
    for (int bit_idx = 0; bit_idx < TB_AXI4_WORD_NUM_BITS; bit_idx++) begin
        axi_mem_be_32b[${i}][bit_idx] = axi_mem_strb_o[${i}][bit_idx / 8];
    end
    // axi_mem_be_32b[${i}] = 32'hffffffff;

    for (int bit_idx = 0; bit_idx < TB_AXI4_WORD_NUM_BITS; bit_idx++) begin
        if (axi_mem_rdata_i[${i}][bit_idx] !== 1'bx) begin
            masked_axi_mem_rdata_i[${i}][bit_idx] = axi_mem_rdata_i[${i}][bit_idx];
        end else begin
            masked_axi_mem_rdata_i[${i}][bit_idx] = axi_mem_rdata_i[${i}][bit_idx] && r_axi_mem_be_32b[${i}][bit_idx];
        end
    end

    /* Conversion from 32bit byte address to 14b word address of ComputeRAM 
        axi_mem_addr_14b = ( axi_mem_addr_o - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * ${i} ) >> shift
        common_offset = ADDR_MAP_0_START
        specific_offset = STORAGE_SPACE_BYTE_SIZE 
        shift = 2 to pass from byte addr to word addr
    */
    axi_mem_addr_14b[${i}] =  ( axi_mem_addr_o[${i}] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * ${i}  )  >> 2;
    /* axi_mem_we_o = !RDWEN    AND   axi_mem_req_o = !CE  means a read in this clock cycle */
    axi_mem_rvalid_n[${i}] =  /* axi_mem_we_o[${i}] && */ axi_mem_req_o[${i}];
    /* memory always responds after 1 clock cycle for write and read so, if we just delay the reuqest signal to have the gnt */
    axi_mem_gnt_i[${i}] = axi_mem_req_o[${i}];
  end

  always_ff@(posedge clk_cg[${i}] or negedge rst_ni) begin
    if (rst_ni == 0) begin
        axi_mem_rvalid_i[${i}] <= '0;
        // axi_mem_gnt_i[${i}] <= '0;
        r_axi_mem_be_32b[${i}] <= '0;
    end else begin
        axi_mem_rvalid_i[${i}] <= axi_mem_rvalid_n[${i}];
        // axi_mem_gnt_i[${i}] <= axi_mem_gnt_n[${i}];
        r_axi_mem_be_32b[${i}] <= axi_mem_be_32b[${i}];
    end
  end

%endfor

endmodule
