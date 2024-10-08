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
  
  localparam BRAM_ADDR_NUM_BITS = 10;

  localparam XPM_MEM_SIZE = 2**BRAM_ADDR_NUM_BITS * TB_AXI4_WORD_NUM_BITS;

  // Create the rule for the address map: start address is the staring address as per linker script
  // The addr_length defines the addressable storage space in each slave ComputeRAM
  parameter longint unsigned ADDR_MAP_0_START = 32'h80000000;
  // 12 bits used to address the 32bits word in the storage part of the ComputeRAM
  // 14 bits used to address the 1byte word in the storage part of the ComputeRAM
  parameter longint unsigned STORAGE_SPACE_BYTE_SIZE = (1024 - 0) * 4;

  logic[NUM_BANKS-1:0][TB_AXI4_WORD_NUM_BITS-1:0] axi_mem_wdata_o;
  // logic[NUM_BANKS-1:0][14-1:0]                    axi_mem_addr_14b;
  logic[NUM_BANKS-1:0][BRAM_ADDR_NUM_BITS-1:0]                    axi_mem_addr_10b;
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

  logic pos_rst;

  always_comb pos_rst = !rst_ni;
  always_comb IRQ = '0;


  // cxr_ssm ram0_i(
  //     // Connect ports using the specified format
  //     .CLK(clk_cg[0]),
  //     .RSTN(rst_ni),
  //     .D(axi_mem_wdata_o[0]),  // write data
  //     .A(axi_mem_addr_14b[0]),  // address common for read and write
  //     .BW(axi_mem_be_32b[0]),  // byte write enable
  //     .RDWEN(!axi_mem_we_o[0]),  // read-write enable read=1 write=0
  //     .CEN(!axi_mem_req_o[0]),  // chip enable active low
  //     .Q(axi_mem_rdata_i[0]),  // read data
  //     .IRQ(IRQ[0])
  // );

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
    // axi_mem_addr_14b[0] =  ( axi_mem_addr_o[0] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 0  )  >> 2;
    axi_mem_addr_10b[0] =  ( axi_mem_addr_o[0] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 0  )  >> 2;
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


  // cxr_ssm ram1_i(
  //     // Connect ports using the specified format
  //     .CLK(clk_cg[1]),
  //     .RSTN(rst_ni),
  //     .D(axi_mem_wdata_o[1]),  // write data
  //     .A(axi_mem_addr_14b[1]),  // address common for read and write
  //     .BW(axi_mem_be_32b[1]),  // byte write enable
  //     .RDWEN(!axi_mem_we_o[1]),  // read-write enable read=1 write=0
  //     .CEN(!axi_mem_req_o[1]),  // chip enable active low
  //     .Q(axi_mem_rdata_i[1]),  // read data
  //     .IRQ(IRQ[1])
  // );

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
    ) xpm_memory_spram_inst_1 (
        .clka (clk_cg[1]),  // 1-bit input: Clock signal for port A.
        .rsta (pos_rst),  // 1-bit input: Reset signal for the final port A output register stage.
        // Synchronously resets output port douta to the value specified by
        // parameter READ_RESET_VALUE_A.
        .ena  (axi_mem_req_o[1]),  // 1-bit input: Memory enable signal for port A. Must be high on clock
        // cycles when read or write operations are initiated. Pipelined internally.
        .addra(axi_mem_addr_10b[1]),  // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
        .dina (axi_mem_wdata_o[1]),  // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .wea  (axi_mem_be_32b[1]),  // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
        // for port A input data port dina. 1 bit wide when word-wide writes are
        // used. In byte-wide write configurations, each bit controls the
        // writing one byte of dina to address addra. For example, to
        // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
        // is 32, wea would be 4'b0010.
        .douta(axi_mem_rdata_i[1]),  // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.

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
    // axi_mem_addr_14b[1] =  ( axi_mem_addr_o[1] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 1  )  >> 2;
    axi_mem_addr_10b[1] =  ( axi_mem_addr_o[1] - ADDR_MAP_0_START - STORAGE_SPACE_BYTE_SIZE * 1  )  >> 2;
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
