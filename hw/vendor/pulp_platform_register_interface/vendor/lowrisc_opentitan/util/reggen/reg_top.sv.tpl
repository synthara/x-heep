// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Register Top module auto-generated by `reggen`
<%
  from reggen import gen_rtl
  from reggen.access import HwAccess, SwRdAccess, SwWrAccess
  from reggen.lib import get_basename
  from reggen.register import Register
  from reggen.multi_register import MultiRegister
  from reggen.ip_block import IpBlock
  from reggen.bus_interfaces import BusProtocol

  num_wins = len(rb.windows)
  num_wins_width = ((num_wins+1).bit_length()) - 1
  num_reg_dsp = 1 if rb.all_regs else 0
  num_dsp  = num_wins + num_reg_dsp
  regs_flat = rb.flat_regs
  max_regs_char = len("{}".format(len(regs_flat) - 1))
  addr_width = rb.get_addr_width()

  lblock = block.name.lower()
  ublock = lblock.upper()

  u_mod_base = mod_base.upper()

  reg2hw_t = gen_rtl.get_iface_tx_type(block, if_name, False)
  hw2reg_t = gen_rtl.get_iface_tx_type(block, if_name, True)

  # Calculate whether we're going to need an AW parameter. We use it if there
  # are any registers (obviously). We also use it if there are any windows that
  # don't start at zero and end at 1 << addr_width (see the "addr_checks"
  # calculation below for where that comes from).
  needs_aw = (bool(regs_flat) or
              num_wins > 1 or
              rb.windows and (
                rb.windows[0].offset != 0 or
                rb.windows[0].size_in_bytes != (1 << addr_width)))

  # Check if the interface protocol is reg_interface
  use_reg_iface = any([interface['protocol'] == BusProtocol.REG_IFACE and not interface['is_host'] for interface in block.bus_interfaces.interface_list])
  reg_intf_req = "reg_req_t"
  reg_intf_rsp = "reg_rsp_t"

  common_data_intg_gen = 0 if rb.has_data_intg_passthru else 1
  adapt_data_intg_gen = 1 if rb.has_data_intg_passthru else 0
  assert common_data_intg_gen != adapt_data_intg_gen
%>

% if use_reg_iface:
`include "common_cells/assertions.svh"
% else:
`include "prim_assert.sv"
% endif

module ${mod_name} \
% if use_reg_iface:
#(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter int AW = ${addr_width}
) \
% else:
    % if needs_aw:
#(
  parameter int AW = ${addr_width}
) \
    % endif
% endif
(
  input logic clk_i,
  input logic rst_ni,
% if use_reg_iface:
  input  ${reg_intf_req} reg_req_i,
  output ${reg_intf_rsp} reg_rsp_o,
% else:
  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,
% endif
% if num_wins != 0:

  // Output port for window
% if use_reg_iface:
  output ${reg_intf_req} [${num_wins}-1:0] reg_req_win_o,
  input  ${reg_intf_rsp} [${num_wins}-1:0] reg_rsp_win_i,
% else:
  output tlul_pkg::tl_h2d_t tl_win_o  [${num_wins}],
  input  tlul_pkg::tl_d2h_t tl_win_i  [${num_wins}],
% endif

% endif
  // To HW
% if rb.get_n_bits(["q","qe","re"]):
  output ${lblock}_reg_pkg::${reg2hw_t} reg2hw, // Write
% endif
% if rb.get_n_bits(["d","de"]):
  input  ${lblock}_reg_pkg::${hw2reg_t} hw2reg, // Read
% endif

% if not use_reg_iface:
  // Integrity check errors
  output logic intg_err_o,
% endif

  // Config
  input devmode_i // If 1, explicit error return for unmapped register access
);

  import ${lblock}_reg_pkg::* ;

% if rb.all_regs:
  localparam int DW = ${block.regwidth};
  localparam int DBW = DW/8;                    // Byte Width

  // register signals
  logic           reg_we;
  logic           reg_re;
  logic [AW-1:0]  reg_addr;
  logic [DW-1:0]  reg_wdata;
  logic [DBW-1:0] reg_be;
  logic [DW-1:0]  reg_rdata;
  logic           reg_error;

  logic          addrmiss, wr_err;

  logic [DW-1:0] reg_rdata_next;

% if use_reg_iface:
  // Below register interface can be changed
  reg_req_t  reg_intf_req;
  reg_rsp_t  reg_intf_rsp;
% else:
  tlul_pkg::tl_h2d_t tl_reg_h2d;
  tlul_pkg::tl_d2h_t tl_reg_d2h;
% endif
% endif

% if not use_reg_iface:
  // incoming payload check
  logic intg_err;
  tlul_cmd_intg_chk u_chk (
    .tl_i,
    .err_o(intg_err)
  );

  logic intg_err_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      intg_err_q <= '0;
    end else if (intg_err) begin
      intg_err_q <= 1'b1;
    end
  end

  // integrity error output is permanent and should be used for alert generation
  // register errors are transactional
  assign intg_err_o = intg_err_q | intg_err;

  // outgoing integrity generation
  tlul_pkg::tl_d2h_t tl_o_pre;
  tlul_rsp_intg_gen #(
    .EnableRspIntgGen(1),
    .EnableDataIntgGen(${common_data_intg_gen})
  ) u_rsp_intg_gen (
    .tl_i(tl_o_pre),
    .tl_o
  );
% endif

% if num_dsp == 1:
  ## Either no windows (and just registers) or no registers and only
  ## one window.
  % if num_wins == 0:
      % if use_reg_iface:
  assign reg_intf_req = reg_req_i;
  assign reg_rsp_o = reg_intf_rsp;
      % else:
  assign tl_reg_h2d = tl_i;
  assign tl_o_pre   = tl_reg_d2h;
      % endif
  % else:
      % if use_reg_iface:
  assign reg_req_win_o = reg_req_i;
  assign reg_rsp_o = reg_rsp_win_i
      % else:
  assign tl_win_o[0] = tl_i;
  assign tl_o_pre    = tl_win_i[0];
      % endif
  % endif
% else:
  logic [${num_wins_width-1}:0] reg_steer;

  % if use_reg_iface:
  ${reg_intf_req} [${num_dsp}-1:0] reg_intf_demux_req;
  ${reg_intf_rsp} [${num_dsp}-1:0] reg_intf_demux_rsp;

  // demux connection
  assign reg_intf_req = reg_intf_demux_req[${num_wins}];
  assign reg_intf_demux_rsp[${num_wins}] = reg_intf_rsp;

    % for i in range(num_wins):
  assign reg_req_win_o[${i}] = reg_intf_demux_req[${i}];
  assign reg_intf_demux_rsp[${i}] = reg_rsp_win_i[${i}];
    % endfor

  // Create Socket_1n
  reg_demux #(
    .NoPorts  (${num_dsp}),
    .req_t    (${reg_intf_req}),
    .rsp_t    (${reg_intf_rsp})
  ) i_reg_demux (
    .clk_i,
    .rst_ni,
    .in_req_i (reg_req_i),
    .in_rsp_o (reg_rsp_o),
    .out_req_o (reg_intf_demux_req),
    .out_rsp_i (reg_intf_demux_rsp),
    .in_select_i (reg_steer)
  );

  % else:
  tlul_pkg::tl_h2d_t tl_socket_h2d [${num_dsp}];
  tlul_pkg::tl_d2h_t tl_socket_d2h [${num_dsp}];

  // socket_1n connection
  % if rb.all_regs:
  assign tl_reg_h2d = tl_socket_h2d[${num_wins}];
  assign tl_socket_d2h[${num_wins}] = tl_reg_d2h;

  % endif
  % for i,t in enumerate(rb.windows):
  assign tl_win_o[${i}] = tl_socket_h2d[${i}];
    % if common_data_intg_gen == 0 and rb.windows[i].data_intg_passthru == False:
    ## If there are multiple windows, and not every window has data integrity
    ## passthrough, we must generate data integrity for it here.
  tlul_rsp_intg_gen #(
    .EnableRspIntgGen(0),
    .EnableDataIntgGen(1)
  ) u_win${i}_data_intg_gen (
    .tl_i(tl_win_i[${i}]),
    .tl_o(tl_socket_d2h[${i}])
  );
    % else:
  assign tl_socket_d2h[${i}] = tl_win_i[${i}];
    % endif
  % endfor

  // Create Socket_1n
  tlul_socket_1n #(
    .N          (${num_dsp}),
    .HReqPass   (1'b1),
    .HRspPass   (1'b1),
    .DReqPass   ({${num_dsp}{1'b1}}),
    .DRspPass   ({${num_dsp}{1'b1}}),
    .HReqDepth  (4'h0),
    .HRspDepth  (4'h0),
    .DReqDepth  ({${num_dsp}{4'h0}}),
    .DRspDepth  ({${num_dsp}{4'h0}})
  ) u_socket (
    .clk_i,
    .rst_ni,
    .tl_h_i (tl_i),
    .tl_h_o (tl_o_pre),
    .tl_d_o (tl_socket_h2d),
    .tl_d_i (tl_socket_d2h),
    .dev_select_i (reg_steer)
  );
  % endif

  // Create steering logic
  always_comb begin
    reg_steer = ${num_dsp-1};       // Default set to register

    // TODO: Can below codes be unique case () inside ?
  % for i,w in enumerate(rb.windows):
<%
      base_addr = w.offset
      limit_addr = w.offset + w.size_in_bytes
      if use_reg_iface:
        hi_check = 'reg_req_i.addr[AW-1:0] < {}'.format(limit_addr)
      else:
        hi_check = 'tl_i.a_address[AW-1:0] < {}'.format(limit_addr)
      addr_checks = []
      if base_addr > 0:
        if use_reg_iface:
          addr_checks.append('reg_req_i.addr[AW-1:0] >= {}'.format(base_addr))
        else:
          addr_checks.append('tl_i.a_address[AW-1:0] >= {}'.format(base_addr))
      if limit_addr < 2**addr_width:
        if use_reg_iface:
          addr_checks.append('reg_req_i.addr[AW-1:0] < {}'.format(limit_addr))
        else:
          addr_checks.append('tl_i.a_address[AW-1:0] < {}'.format(limit_addr))

      addr_test = ' && '.join(addr_checks)
%>\
      % if addr_test:
    if (${addr_test}) begin
      % endif
      reg_steer = ${i};
      % if addr_test:
    end
      % endif
  % endfor
  % if not use_reg_iface:
    if (intg_err) begin
      reg_steer = ${num_dsp-1};
    end
  % endif
  end
% endif
% if rb.all_regs:


% if use_reg_iface:
  assign reg_we = reg_intf_req.valid & reg_intf_req.write;
  assign reg_re = reg_intf_req.valid & ~reg_intf_req.write;
  assign reg_addr = reg_intf_req.addr;
  assign reg_wdata = reg_intf_req.wdata;
  assign reg_be = reg_intf_req.wstrb;
  assign reg_intf_rsp.rdata = reg_rdata;
  assign reg_intf_rsp.error = reg_error;
  assign reg_intf_rsp.ready = 1'b1;
% else:
  tlul_adapter_reg #(
    .RegAw(AW),
    .RegDw(DW),
    .EnableDataIntgGen(${adapt_data_intg_gen})
  ) u_reg_if (
    .clk_i,
    .rst_ni,

    .tl_i (tl_reg_h2d),
    .tl_o (tl_reg_d2h),

    .we_o    (reg_we),
    .re_o    (reg_re),
    .addr_o  (reg_addr),
    .wdata_o (reg_wdata),
    .be_o    (reg_be),
    .rdata_i (reg_rdata),
    .error_i (reg_error)
  );
% endif

  assign reg_rdata = reg_rdata_next ;
% if use_reg_iface:
  assign reg_error = (devmode_i & addrmiss) | wr_err;
% else:
  assign reg_error = (devmode_i & addrmiss) | wr_err | intg_err;
% endif


  // Define SW related signals
  // Format: <reg>_<field>_{wd|we|qs}
  //        or <reg>_{wd|we|qs} if field == 1 or 0
  % for r in regs_flat:
    % if len(r.fields) == 1:
${sig_gen(r.fields[0], r.name.lower(), r.hwext, r.shadowed)}\
    % else:
      % for f in r.fields:
${sig_gen(f, r.name.lower() + "_" + f.name.lower(), r.hwext, r.shadowed)}\
      % endfor
    % endif
  % endfor

  // Register instances
  % for r in rb.all_regs:
  ######################## multiregister ###########################
    % if isinstance(r, MultiRegister):
<%
      k = 0
%>
      % for sr in r.regs:
  // Subregister ${k} of Multireg ${r.reg.name.lower()}
  // R[${sr.name.lower()}]: V(${str(sr.hwext)})
        % if len(sr.fields) == 1:
<%
          f = sr.fields[0]
          finst_name = sr.name.lower()
          fsig_name = r.reg.name.lower() + "[%d]" % k
          k = k + 1
%>
${finst_gen(f, finst_name, fsig_name, sr.hwext, sr.regwen, sr.shadowed)}
        % else:
          % for f in sr.fields:
<%
            finst_name = sr.name.lower() + "_" + f.name.lower()
            if r.is_homogeneous():
              fsig_name = r.reg.name.lower() + "[%d]" % k
              k = k + 1
            else:
              fsig_name = r.reg.name.lower() + "[%d]" % k + "." + get_basename(f.name.lower())
%>
  // F[${f.name.lower()}]: ${f.bits.msb}:${f.bits.lsb}
${finst_gen(f, finst_name, fsig_name, sr.hwext, sr.regwen, sr.shadowed)}
          % endfor
<%
          if not r.is_homogeneous():
            k += 1
%>
        % endif
        ## for: mreg_flat
      % endfor
######################## register with single field ###########################
    % elif len(r.fields) == 1:
  // R[${r.name.lower()}]: V(${str(r.hwext)})
<%
        f = r.fields[0]
        finst_name = r.name.lower()
        fsig_name = r.name.lower()
%>
${finst_gen(f, finst_name, fsig_name, r.hwext, r.regwen, r.shadowed)}
######################## register with multiple fields ###########################
    % else:
  // R[${r.name.lower()}]: V(${str(r.hwext)})
      % for f in r.fields:
<%
        finst_name = r.name.lower() + "_" + f.name.lower()
        fsig_name = r.name.lower() + "." + f.name.lower()
%>
  //   F[${f.name.lower()}]: ${f.bits.msb}:${f.bits.lsb}
${finst_gen(f, finst_name, fsig_name, r.hwext, r.regwen, r.shadowed)}
      % endfor
    % endif

  ## for: rb.all_regs
  % endfor


  logic [${len(regs_flat)-1}:0] addr_hit;
  always_comb begin
    addr_hit = '0;
    % for i,r in enumerate(regs_flat):
    addr_hit[${"{}".format(i).rjust(max_regs_char)}] = (reg_addr == ${ublock}_${r.name.upper()}_OFFSET);
    % endfor
  end

  assign addrmiss = (reg_re || reg_we) ? ~|addr_hit : 1'b0 ;

% if regs_flat:
<%
    # We want to signal wr_err if reg_be (the byte enable signal) is true for
    # any bytes that aren't supported by a register. That's true if a
    # addr_hit[i] and a bit is set in reg_be but not in *_PERMIT[i].

    wr_err_terms = ['(addr_hit[{idx}] & (|({mod}_PERMIT[{idx}] & ~reg_be)))'
                    .format(idx=str(i).rjust(max_regs_char),
                            mod=u_mod_base)
                    for i in range(len(regs_flat))]
    wr_err_expr = (' |\n' + (' ' * 15)).join(wr_err_terms)
%>\
  // Check sub-word write is permitted
  always_comb begin
    wr_err = (reg_we &
              (${wr_err_expr}));
  end
% else:
  assign wr_error = 1'b0;
% endif\

  % for i, r in enumerate(regs_flat):
    % if len(r.fields) == 1:
${we_gen(r.fields[0], r.name.lower(), r.hwext, r.shadowed, i)}\
    % else:
      % for f in r.fields:
${we_gen(f, r.name.lower() + "_" + f.name.lower(), r.hwext, r.shadowed, i)}\
      % endfor
    % endif
  % endfor

  // Read data return
  always_comb begin
    reg_rdata_next = '0;
    unique case (1'b1)
      % for i, r in enumerate(regs_flat):
        % if len(r.fields) == 1:
      addr_hit[${i}]: begin
${rdata_gen(r.fields[0], r.name.lower())}\
      end

        % else:
      addr_hit[${i}]: begin
          % for f in r.fields:
${rdata_gen(f, r.name.lower() + "_" + f.name.lower())}\
          % endfor
      end

        % endif
      % endfor
      default: begin
        reg_rdata_next = '1;
      end
    endcase
  end
% endif

  // Unused signal tieoff
% if rb.all_regs:

  // wdata / byte enable are not always fully used
  // add a blanket unused statement to handle lint waivers
  logic unused_wdata;
  logic unused_be;
  assign unused_wdata = ^reg_wdata;
  assign unused_be = ^reg_be;
% else:
  // devmode_i is not used if there are no registers
  logic unused_devmode;
  assign unused_devmode = ^devmode_i;
% endif
% if rb.all_regs:

  // Assertions for Register Interface
% if not use_reg_iface:
  `ASSERT_PULSE(wePulse, reg_we)
  `ASSERT_PULSE(rePulse, reg_re)

  `ASSERT(reAfterRv, $rose(reg_re || reg_we) |=> tl_o.d_valid)

  // this is formulated as an assumption such that the FPV testbenches do disprove this
  // property by mistake
  //`ASSUME(reqParity, tl_reg_h2d.a_valid |-> tl_reg_h2d.a_user.chk_en == tlul_pkg::CheckDis)
% endif
  `ASSERT(en2addrHit, (reg_we || reg_re) |-> $onehot0(addr_hit))

% endif
endmodule

% if use_reg_iface:
module ${mod_name}_intf
#(
  parameter int AW = ${addr_width},
  localparam int DW = ${block.regwidth}
) (
  input logic clk_i,
  input logic rst_ni,
  REG_BUS.in  regbus_slave,
% if num_wins != 0:
  REG_BUS.out  regbus_win_mst[${num_wins}-1:0],
% endif
  // To HW
% if rb.get_n_bits(["q","qe","re"]):
  output ${lblock}_reg_pkg::${reg2hw_t} reg2hw, // Write
% endif
% if rb.get_n_bits(["d","de"]):
  input  ${lblock}_reg_pkg::${hw2reg_t} hw2reg, // Read
% endif
  // Config
  input devmode_i // If 1, explicit error return for unmapped register access
);
 localparam int unsigned STRB_WIDTH = DW/8;

`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

  // Define structs for reg_bus
  typedef logic [AW-1:0] addr_t;
  typedef logic [DW-1:0] data_t;
  typedef logic [STRB_WIDTH-1:0] strb_t;
  `REG_BUS_TYPEDEF_ALL(reg_bus, addr_t, data_t, strb_t)

  reg_bus_req_t s_reg_req;
  reg_bus_rsp_t s_reg_rsp;
  
  // Assign SV interface to structs
  `REG_BUS_ASSIGN_TO_REQ(s_reg_req, regbus_slave)
  `REG_BUS_ASSIGN_FROM_RSP(regbus_slave, s_reg_rsp)

% if num_wins != 0:
  reg_bus_req_t s_reg_win_req[${num_wins}-1:0];
  reg_bus_rsp_t s_reg_win_rsp[${num_wins}-1:0];
  for (genvar i = 0; i < ${num_wins}; i++) begin : gen_assign_window_structs
    `REG_BUS_ASSIGN_TO_REQ(s_reg_win_req[i], regbus_win_mst[i])
    `REG_BUS_ASSIGN_FROM_RSP(regbus_win_mst[i], s_reg_win_rsp[i])
  end
  
% endif
  

  ${mod_name} #(
    .reg_req_t(reg_bus_req_t),
    .reg_rsp_t(reg_bus_rsp_t),
    .AW(AW)
  ) i_regs (
    .clk_i,
    .rst_ni,
    .reg_req_i(s_reg_req),
    .reg_rsp_o(s_reg_rsp),
% if num_wins != 0:
    .reg_req_win_o(s_reg_win_req),
    .reg_rsp_win_i(s_reg_win_rsp),
% endif
% if rb.get_n_bits(["q","qe","re"]):
    .reg2hw, // Write
% endif
% if rb.get_n_bits(["d","de"]):
    .hw2reg, // Read
% endif
    .devmode_i
  );
  
endmodule

% endif

<%def name="str_bits_sv(bits)">\
% if bits.msb != bits.lsb:
${bits.msb}:${bits.lsb}\
% else:
${bits.msb}\
% endif
</%def>\
<%def name="str_arr_sv(bits)">\
% if bits.msb != bits.lsb:
[${bits.msb-bits.lsb}:0] \
% endif
</%def>\
<%def name="sig_gen(field, sig_name, hwext, shadowed)">\
  % if field.swaccess.allows_read():
  logic ${str_arr_sv(field.bits)}${sig_name}_qs;
  % endif
  % if field.swaccess.allows_write():
  logic ${str_arr_sv(field.bits)}${sig_name}_wd;
  logic ${sig_name}_we;
  % endif
  % if (field.swaccess.allows_read() and hwext) or shadowed:
  logic ${sig_name}_re;
  % endif
</%def>\
<%def name="finst_gen(field, finst_name, fsig_name, hwext, regwen, shadowed)">\
  % if hwext:       ## if hwext, instantiate prim_subreg_ext
  prim_subreg_ext #(
    .DW    (${field.bits.width()})
  ) u_${finst_name} (
    % if field.swaccess.allows_read():
    .re     (${finst_name}_re),
    % else:
    .re     (1'b0),
    % endif
    % if field.swaccess.allows_write():
      % if regwen:
    // qualified with register enable
    .we     (${finst_name}_we & ${regwen.lower()}_qs),
      % else:
    .we     (${finst_name}_we),
      % endif
    .wd     (${finst_name}_wd),
    % else:
    .we     (1'b0),
    .wd     ('0),
    % endif
    % if field.hwaccess.allows_write():
    .d      (hw2reg.${fsig_name}.d),
    % else:
    .d      ('0),
    % endif
    % if field.hwre or shadowed:
    .qre    (reg2hw.${fsig_name}.re),
    % else:
    .qre    (),
    % endif
    % if not field.hwaccess.allows_read():
    .qe     (),
    .q      (),
    % else:
      % if field.hwqe:
    .qe     (reg2hw.${fsig_name}.qe),
      % else:
    .qe     (),
      % endif
    .q      (reg2hw.${fsig_name}.q ),
    % endif
    % if field.swaccess.allows_read():
    .qs     (${finst_name}_qs)
    % else:
    .qs     ()
    % endif
  );
  % else:       ## if not hwext, instantiate prim_subreg, prim_subreg_shadow or constant assign
    % if ((not field.hwaccess.allows_read() and\
           not field.hwaccess.allows_write() and\
           field.swaccess.swrd() == SwRdAccess.RD and\
           not field.swaccess.allows_write())):
  // constant-only read
  assign ${finst_name}_qs = ${field.bits.width()}'h${"%x" % (field.resval or 0)};
    % else:     ## not hwext not constant
      % if not shadowed:
  prim_subreg #(
      % else:
  prim_subreg_shadow #(
      % endif
    .DW      (${field.bits.width()}),
    .SWACCESS("${field.swaccess.value[1].name.upper()}"),
    .RESVAL  (${field.bits.width()}'h${"%x" % (field.resval or 0)})
  ) u_${finst_name} (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

      % if shadowed:
    .re     (${finst_name}_re),
      % endif
      % if field.swaccess.allows_write(): ## non-RO types
        % if regwen:
    // from register interface (qualified with register enable)
    .we     (${finst_name}_we & ${regwen.lower()}_qs),
        % else:
    // from register interface
    .we     (${finst_name}_we),
        % endif
    .wd     (${finst_name}_wd),
      % else:                             ## RO types
    .we     (1'b0),
    .wd     ('0  ),
      % endif

    // from internal hardware
      % if field.hwaccess.allows_write():
    .de     (hw2reg.${fsig_name}.de),
    .d      (hw2reg.${fsig_name}.d ),
      % else:
    .de     (1'b0),
    .d      ('0  ),
      % endif

    // to internal hardware
      % if not field.hwaccess.allows_read():
    .qe     (),
    .q      (),
      % else:
        % if field.hwqe:
    .qe     (reg2hw.${fsig_name}.qe),
        % else:
    .qe     (),
        % endif
    .q      (reg2hw.${fsig_name}.q ),
      % endif

      % if not shadowed:
        % if field.swaccess.allows_read():
    // to register interface (read)
    .qs     (${finst_name}_qs)
        % else:
    .qs     ()
        % endif
      % else:
        % if field.swaccess.allows_read():
    // to register interface (read)
    .qs     (${finst_name}_qs),
        % else:
    .qs     (),
        % endif

    // Shadow register error conditions
    .err_update  (reg2hw.${fsig_name}.err_update ),
    .err_storage (reg2hw.${fsig_name}.err_storage)
      % endif
  );
    % endif  ## end non-constant prim_subreg
  % endif
</%def>\
<%def name="we_gen(field, sig_name, hwext, shadowed, idx)">\
<%
    needs_we = field.swaccess.allows_write()
    needs_re = (field.swaccess.allows_read() and hwext) or shadowed
    space = '\n' if needs_we or needs_re else ''
%>\
${space}\
% if needs_we:
  % if field.swaccess.swrd() != SwRdAccess.RC:
  assign ${sig_name}_we = addr_hit[${idx}] & reg_we & !reg_error;
  assign ${sig_name}_wd = reg_wdata[${str_bits_sv(field.bits)}];
  % else:
  ## Generate WE based on read request, read should clear
  assign ${sig_name}_we = addr_hit[${idx}] & reg_re & !reg_error;
  assign ${sig_name}_wd = '1;
  % endif
% endif
% if needs_re:
  assign ${sig_name}_re = addr_hit[${idx}] & reg_re & !reg_error;
% endif
</%def>\
<%def name="rdata_gen(field, sig_name)">\
% if field.swaccess.allows_read():
        reg_rdata_next[${str_bits_sv(field.bits)}] = ${sig_name}_qs;
% else:
        reg_rdata_next[${str_bits_sv(field.bits)}] = '0;
% endif
</%def>\
