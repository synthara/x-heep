// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

`ifndef SYNTHESIS
// Task for loading 'mem' with SystemVerilog system task $readmemh()
export "DPI-C" task tb_readHEX;
export "DPI-C" task tb_loadHEX;
%for bank in list(xheep.iter_ram_banks())[:xheep.ram_numbanks() - xheep.cxr_numbanks()]:
export "DPI-C" task tb_writetoSram${bank.name()};
% endfor

% for i, bank in enumerate(list(xheep.iter_ram_banks())[xheep.ram_numbanks() - xheep.cxr_numbanks():]):
export "DPI-C" task tb_writetoCXR${i};
% endfor
export "DPI-C" task tb_getMemSize;
export "DPI-C" task tb_set_exit_loop;

import core_v_mini_mcu_pkg::*;

task tb_getMemSize;
  output int mem_size;
  mem_size  = core_v_mini_mcu_pkg::MEM_SIZE;
endtask

task tb_readHEX;
  input string file;
  output logic [7:0] stimuli[core_v_mini_mcu_pkg::MEM_SIZE];
  $readmemh(file, stimuli);
endtask

task tb_loadHEX;
  input string file;
  //whether to use debug to write to memories
  logic [7:0] stimuli[core_v_mini_mcu_pkg::MEM_SIZE];
  int i, stimuli_base, w_addr, NumBytes;
  logic [31:0] addr;

  tb_readHEX(file, stimuli);
  tb_getMemSize(NumBytes);

`ifndef VERILATOR
  for (i = 0; i < NumBytes; i = i + 4) begin

    @(posedge x_heep_system_i.core_v_mini_mcu_i.clk_i);
    addr = i;
    #1;
    // write to memory
    force x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_req_o = 1'b1;
    force x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_addr_o = addr;
    force x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_we_o = 1'b1;
    force x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_be_o = 4'b1111;
    force x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_wdata_o = {
      stimuli[i+3], stimuli[i+2], stimuli[i+1], stimuli[i]
    };

    while(!x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_gnt_i)
      @(posedge x_heep_system_i.core_v_mini_mcu_i.clk_i);

    #1;
    force x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_req_o = 1'b0;

    wait (x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_rvalid_i);

    #1;

  end

  release x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_req_o;
  release x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_addr_o;
  release x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_we_o;
  release x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_be_o;
  release x_heep_system_i.core_v_mini_mcu_i.debug_subsystem_i.dm_obi_top_i.master_wdata_o;

`else
%for bank in list(xheep.iter_ram_banks())[:xheep.ram_numbanks() - xheep.cxr_numbanks()]:
  for (i=${bank.start_address()}; i < ${bank.end_address()}; i = i + 4) begin
    if (((i/4) & ${2**bank.il_level()-1}) == ${bank.il_offset()}) begin
      w_addr = ((i/4) >> ${bank.il_level()}) % ${bank.size()//4};
      tb_writetoSram${bank.name()}(w_addr, stimuli[i+3], stimuli[i+2],
                                          stimuli[i+1], stimuli[i]);
    end
  end
% endfor

% for j, bank in enumerate(list(xheep.iter_ram_banks())[xheep.ram_numbanks() - xheep.cxr_numbanks():]):
  for (i=${bank.start_address()}; i < ${bank.end_address()}; i = i + 4) begin
    if (((i/4) & ${2**bank.il_level()-1}) == ${bank.il_offset()}) begin
      w_addr = ((i/4) >> ${bank.il_level()}) % ${bank.size()//4};
      tb_writetoCXR${j}(w_addr, stimuli[i+3], stimuli[i+2],
                                           stimuli[i+1], stimuli[i]);
    end
  end
% endfor

`endif

endtask

%for bank in list(xheep.iter_ram_banks())[:xheep.ram_numbanks() - xheep.cxr_numbanks()]:
task tb_writetoSram${bank.name()};
  input int addr;
  input [7:0] val3;
  input [7:0] val2;
  input [7:0] val1;
  input [7:0] val0;
`ifdef VCS
  force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.ram${bank.name()}_i.ram_bank_i.uut.mem_core_array[addr] = {
    val3, val2, val1, val0
  };
  release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.ram${bank.name()}_i.ram_bank_i.uut.mem_core_array[addr];
`else
  x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.ram${bank.name()}_i.ram_bank_i.uut.mem_core_array[addr] = {
    val3, val2, val1, val0
  };
`endif
endtask

% endfor

% for i, bank in enumerate(list(xheep.iter_ram_banks())[xheep.ram_numbanks() - xheep.cxr_numbanks():]):
task tb_writetoCXR${i};
  input int addr;
  input [7:0] val3;
  input [7:0] val2;
  input [7:0] val1;
  input [7:0] val0;
`ifdef VCS
  case(addr[12:11]) 
    2'b00: begin
          case(addr[10:9]) 
            2'b00: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b01: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b10: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b11: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
          endcase
        end
    2'b01: begin
          case(addr[10:9]) 
            2'b00: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b01: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b10: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b11: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
          endcase
        end
    2'b10: begin
          case(addr[10:9]) 
            2'b00: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b01: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b10: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b11: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
          endcase
        end
    2'b11: begin
          case(addr[10:9]) 
            2'b00: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b01: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b10: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
            2'b11: begin
              force x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
                val3, val2, val1, val0
              };
              release x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]];
            end
          endcase
        end
  endcase
`else
  case(addr[12:11])
    2'b00: begin
          case(addr[10:9]) 
            2'b00: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b01: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b10: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b11: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[0].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
          endcase
        end
    2'b01: begin
          case(addr[10:9]) 
            2'b00: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b01: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b10: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b11: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[1].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
          endcase
        end
    2'b10: begin
          case(addr[10:9]) 
            2'b00: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b01: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b10: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b11: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[2].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
          endcase
        end
    2'b11: begin
          case(addr[10:9]) 
            2'b00: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[0].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b01: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[1].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b10: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[2].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
            2'b11: begin
              x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.cxr${i}_i.cxr_bank_i.i_cxr_ssm_ops.g_ops_blocks[3].g_ops_banks[3].i_cxr_ssm_ops_bnk.mem_array[addr[8:0]] = {
              val3, val2, val1, val0
              };
            end
          endcase
        end
  endcase

`endif
endtask

% endfor

task tb_set_exit_loop;
`ifdef VCS
  force x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i.testbench_set_exit_loop[0] = 1'b1;
  release x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i.testbench_set_exit_loop[0];
`else
  x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i.testbench_set_exit_loop[0] = 1'b1;
`endif
endtask
`endif
