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

%for i, bank in enumerate(xheep.iter_ram_banks()):
  sram_wrapper #(
      .NumWords (${bank.size() // 4}),
      .DataWidth(32'd32)
  ) ram${bank.name()}_i (
      .clk_i(clk_cg[${i}]),
      .rst_ni(rst_ni),
      .req_i(ram_req_i[${i}].req),
      .we_i(ram_req_i[${i}].we),
      .addr_i(ram_req_addr_${i}),
      .wdata_i(ram_req_i[${i}].wdata),
      .be_i(ram_req_i[${i}].be),
      .pwrgate_ni(pwrgate_ni[${i}]),
      .pwrgate_ack_no(pwrgate_ack_no[${i}]),
      .set_retentive_ni(set_retentive_ni[${i}]),
      .rdata_o(ram_resp_o[${i}].rdata)
  );

    // xpm_memory_spram: Single Port RAM
    // Xilinx Parameterized Macro, version 2021.2
    xpm_memory_spram#(
        .ADDR_WIDTH_A       (BRAM_ADDR_NUM_BITS),  // DECIMAL
        .AUTO_SLEEP_TIME    (0),  // DECIMAL
        .BYTE_WRITE_WIDTH_A (8),  // DECIMAL
        .CASCADE_HEIGHT     (0),  // DECIMAL
        .ECC_MODE           ("no_ecc"),  // String
        .MEMORY_INIT_FILE   ("none"),  // String
        .MEMORY_INIT_PARAM  ("0"),  // String
        .MEMORY_OPTIMIZATION("true"),  // String
        .MEMORY_PRIMITIVE   ("block"),  // String
        .MEMORY_SIZE        (XPM_MEM_SIZE),  // Specify the total memory array size, in bits. For example, enter 65536 for a 2kx32 RAM.
        .MESSAGE_CONTROL    (0),  // DECIMAL
        .READ_DATA_WIDTH_A  (TB_AXI4_WORD_NUM_BITS),  // DECIMAL
        .READ_LATENCY_A     (1),  // DECIMAL
        .READ_RESET_VALUE_A ("0"),  // String
        .RST_MODE_A         ("ASYNC"),  // String
        .SIM_ASSERT_CHK     (0),  // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .USE_MEM_INIT       (0),  // DECIMAL
        .USE_MEM_INIT_MMI   (0),  // DECIMAL
        .WAKEUP_TIME        ("disable_sleep"),  // String
        .WRITE_DATA_WIDTH_A (TB_AXI4_WORD_NUM_BITS),  // DECIMAL
        .WRITE_MODE_A       ("read_first"),  // String
        .WRITE_PROTECT      (1)  // DECIMAL
    ) xpm_memory_spram_inst_0 (
        .clka (clk_cg[0]),  // 1-bit input: Clock signal for port A.
        .rsta (pos_rst),  // 1-bit input: Reset signal for the final port A output register stage.
        // Synchronously resets output port douta to the value specified by
        // parameter READ_RESET_VALUE_A.
        .ena  (axi_mem_req_o[0]),  // 1-bit input: Memory enable signal for port A. Must be high on clock
        // cycles when read or write operations are initiated. Pipelined internally.
        .addra(axi_mem_addr_10b[0]),  // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
        .dina (axi_mem_wdata_o[0]),  // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .wea  (axi_mem_be_32b[0]),  // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
        // for port A input data port dina. 1 bit wide when word-wide writes are
        // used. In byte-wide write configurations, each bit controls the
        // writing one byte of dina to address addra. For example, to
        // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
        // is 32, wea would be 4'b0010.
        .douta(axi_mem_rdata_i[0]),  // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.

        .dbiterra      (),  // 1-bit output: Status signal to indicate double bit error occurrence
        // on the data output of port A.
        .sbiterra      (),  // 1-bit output: Status signal to indicate single bit error occurrence
        // on the data output of port A.
        .injectdbiterra(1'b0),  // 1-bit input: Controls double bit error injection on input data when
        // ECC enabled (Error injection capability is not available in "decode_only" mode).
        .injectsbiterra(1'b0),  // 1-bit input: Controls single bit error injection on input data when
        // ECC enabled (Error injection capability is not available in "decode_only" mode).
        .regcea        (1'b1),  // 1-bit input: Clock Enable for the last register stage on the output data path.
        .sleep         (1'b0)  // 1-bit input: sleep signal to enable the dynamic power saving feature.
    );

%endfor

endmodule
