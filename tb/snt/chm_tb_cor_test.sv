/*
Synthara's cortem test extends uvmt_cv32e20_base_test_c
*/
class xhp_tb_cor_test extends uvmt_cv32e20_base_test_c;

    // Here it will be included the environment of the axi-valid_ready component,
    // and the ComputeRAM environment, together with whatever environment is needed

    // Class methods
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    // Class properties
    `uvm_component_utils(xhp_tb_cor_test)

endclass
