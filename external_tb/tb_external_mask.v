`timescale 1ns/1ps
module tb_external_mask;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    reg [3:0] external_ch=4'bzzz1;
    integer updates=0;
    timing_diagnostic_axi_bd_wrapper #(.EXTERNAL_MODE(1),.EXTERNAL_ENABLE_MASK(4'b0001)) dut (
        .s_axi_aclk(clk),.s_axi_aresetn(rst_n),.external_ch(external_ch),
        .s_axi_awaddr(12'b0),.s_axi_awprot(3'b0),.s_axi_awvalid(1'b0),
        .s_axi_wdata(32'b0),.s_axi_wstrb(4'b0),.s_axi_wvalid(1'b0),.s_axi_bready(1'b0),
        .s_axi_araddr(12'b0),.s_axi_arprot(3'b0),.s_axi_arvalid(1'b0),.s_axi_rready(1'b0)
    );
    always @(posedge clk) begin
        #1;
        if(dut.selected_ch[3:1] !== 0) $fatal(1,"TEST FAILED: floating disabled inputs propagated");
        if(rst_n && dut.u_timing_diagnostic_axi_top.period_valid[0]) begin
            if(dut.u_timing_diagnostic_axi_top.period_ticks[63:0] !== 50) $fatal(1,"TEST FAILED: masked CH0 period");
            updates=updates+1;
        end
        if(dut.u_timing_diagnostic_axi_top.rise_pulse[3:1] !== 0 || dut.u_timing_diagnostic_axi_top.fall_pulse[3:1] !== 0)
            if(rst_n) $fatal(1,"TEST FAILED: disabled input edge");
    end
    initial begin
        repeat(8) @(negedge clk);rst_n=1;
        repeat(6) begin @(negedge clk);
            if(dut.u_timing_diagnostic_axi_top.rise_pulse !== 0) $fatal(1,"TEST FAILED: initial high edge");
        end
        #7;
        repeat(12) begin external_ch[0]=0;#750;external_ch[0]=1;#250;end
        if(updates<8) $fatal(1,"TEST FAILED: no CH0 measurements");
        $display("TEST PASSED: masked floating Z inputs, startup high, CH0 measurement");$finish;
    end
    initial begin #50000;$fatal(1,"TEST FAILED: watchdog");end
endmodule
