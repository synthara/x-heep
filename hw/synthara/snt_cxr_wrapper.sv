// ---------------------------------------------------------------------------- -
//  Copyright (C) Synthara. All rights reserved.                              - -
//  Developed at Synthara, Zurich, Switzerland                                - -
//  All rights reserved. Reproduction in whole or part is prohibited without  - -
//  The written permission of the copyright owner.                            - -
// ---------------------------------------------------------------------------- -

module snt_cxr_wrapper#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BE_WIDTH = 4,
    parameter int unsigned NumWords  = 32'd1024,  // Number of Words in data array
    parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1
) (
    input logic clk_i,
    input logic rst_ni,
    input logic req_i,
    input logic we_i,
    input logic [AddrWidth-1:0] addr_i,
    input logic [DATA_WIDTH-1:0] wdata_i,
    input logic [BE_WIDTH-1:0] be_i,
    input logic pwrgate_ni,
    output logic pwrgate_ack_no,
    input logic set_retentive_ni,
    output logic [DATA_WIDTH-1:0] rdata_o
);
    // Parameters
    parameter NUM_BYTES = DATA_WIDTH/BE_WIDTH;

    // Internal signals
    logic ME;
    logic [DATA_WIDTH-1:0] ram_rdata;
    logic [DATA_WIDTH-1:0] wem;

    // Assignments
    assign ME = req_i;
    assign rdata_o = ram_rdata;
    // Generate write enable mask based on byte enable and data width
    always_comb begin
        for (int i = 0; i < NUM_BYTES; i++) begin
            wem[i*8 +: 8] = {8{be_i[i]}};
        end
    end

    // Instantiate the memory
    cxr_ssm cxr_bank_i (
        .CLK(clk_i),
        .RSTN(rst_ni),  
        .D(wdata_i),
        .A(addr_i),
        .BW(wem),
        .RDWEN(we_i),
        .CEN(ME),
        .Q(ram_rdata),
        .IRQ()
    );

    // Power gating logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pwrgate_ack_no <= 1'b0;
        end else begin
            pwrgate_ack_no <= !pwrgate_ni;
        end
    end

endmodule

