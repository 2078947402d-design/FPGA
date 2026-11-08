`timescale 1ns / 1ps
// New testbench only; instantiates the unchanged Vivado debug wrapper/RTL.
module tb_external_axi;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0;
    reg [3:0] external_ch=4'b1111;
    integer periods[0:3], highs[0:3];
    integer measures[0:3];
    integer c;
    task automatic wave(input integer lane, input integer phase, input integer hi_ns, input integer lo_ns);
        begin
            #(phase);
            forever begin external_ch[lane]=1; #(hi_ns); external_ch[lane]=0; #(lo_ns); end
        end
    endtask
    initial begin
        #400;
        fork
            wave(0,3,500000,500000);
            wave(1,7,150000,350000);
            wave(2,11,14000,186000);
            wave(3,17,73001,27006);
        join
    end
    always @(posedge clk) begin
        #1;
        if(rst_n) for(integer lane=0;lane<4;lane=lane+1) begin
            if(dut.u_timing_diagnostic_axi_top.period_valid[lane]) begin
                if(dut.u_timing_diagnostic_axi_top.period_ticks[lane*64+:64] < periods[lane] ||
                   dut.u_timing_diagnostic_axi_top.period_ticks[lane*64+:64] > periods[lane]+((lane==3)?1:0)) fail("external period");
                measures[lane]=measures[lane]+1;
            end
        end
    end
    reg [11:0] awaddr=0,araddr=0;
    reg [31:0] wdata=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    integer errors=0,passed=0;
    integer ch,k,i,p,typ,index,threshold,expected,reference;
    integer types[0:5];
    reg [31:0] value,info,lo,hi,seq;
    reg [63:0] start_ts,end_ts,event_ts,event_value,previous_ts;
    reg [63:0] saved_cfg[0:8];
    integer count;
    timing_diagnostic_axi_bd_wrapper #(.EXTERNAL_MODE(1)) dut (.external_ch(external_ch),
        .s_axi_aclk(clk),.s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(4'hf),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready)
    );
    task fail;
        input [8*160-1:0] msg;
        begin $display("ERROR: CH%0d type=%0d %0s t=%0t",ch,typ,msg,$time); errors=errors+1; end
    endtask
    task read32;
        input [11:0] addr;
        output [31:0] data;
        begin
            @(negedge clk); araddr=addr; arvalid=1;
            @(posedge clk); while(!arready) @(posedge clk);
            @(negedge clk); arvalid=0;
            while(!rvalid) @(negedge clk);
            data=rdata;
            if(rresp!==0) fail("AXI read response");
            rready=1; @(negedge clk); rready=0;
        end
    endtask
    task write32;
        input [11:0] addr;
        input [31:0] data;
        begin
            @(negedge clk); awaddr=addr; awvalid=1;
            @(posedge clk); while(!awready) @(posedge clk);
            @(negedge clk); awvalid=0; wdata=data; wvalid=1;
            @(posedge clk); while(!wready) @(posedge clk);
            @(negedge clk); wvalid=0;
            while(!bvalid) @(negedge clk);
            if(bresp!==0) fail("AXI write response");
            bready=1; @(negedge clk); bready=0;
        end
    endtask
    function integer cfg_addr;
        input integer channel,field,high;
        integer b,e;
        begin
            b='h100+channel*'h80; e='h300+channel*'h40;
            case(field)
                0: cfg_addr=high ? e:b+'h20;
                1: cfg_addr=high ? e+4:b+'h24;
                2: cfg_addr=b+'h28+high*4;
                3: cfg_addr=b+'h30+high*4;
                4: cfg_addr=b+'h38+high*4;
                5: cfg_addr=b+'h40+high*4;
                6: cfg_addr=high ? e+8:b+'h48;
                7: cfg_addr=high ? e+'hc:b+'h4c;
                8: cfg_addr=high ? e+'h10:b+'h50;
            endcase
        end
    endfunction
    task config64;
        input integer channel,field;
        input [63:0] data;
        begin
            write32(cfg_addr(channel,field,0),data[31:0]);
            write32(cfg_addr(channel,field,1),data[63:32]);
            write32('h314+channel*'h40,1<<field);
            read32(cfg_addr(channel,field,0),value); if(value!==data[31:0]) fail("config low readback");
            read32(cfg_addr(channel,field,1),value); if(value!==data[63:32]) fail("config high readback");
        end
    endtask
    task timestamp_snapshot;
        output [63:0] stamp;
        begin
            read32('h18,seq); write32('hc,2); read32('h18,value);
            if(value!==seq+1) fail("snapshot sequence");
            read32('h1c,lo); read32('h20,hi); stamp={hi,lo};
        end
    endtask
    task clean_fifo;
        begin
            read32('h50,value); if(value!==0) fail("FIFO/pending not empty");
            read32('h4c,value); if(value!==0) fail("pending not empty");
            read32('h2c,value); if(value!==32'h10000) fail("FIFO status not clean");
            read32('h48,value); if(value!==0) fail("dropped events");
            read32('hc,value); if(value!==0) fail("global not disabled");
            read32('h10,value); if(value[5]) fail("config error");
        end
    endtask
    initial begin
        periods[0]=50000; periods[1]=25000; periods[2]=10000; periods[3]=5000;
        highs[0]=25000; highs[1]=7500; highs[2]=700; highs[3]=3650;
        for(c=0;c<4;c=c+1) measures[c]=0;
        repeat(8) @(negedge clk); rst_n=1;
        // Initial high inputs must not produce an artificial rising edge.
        repeat(6) begin
            @(negedge clk);
            if(dut.u_timing_diagnostic_axi_top.rise_pulse !== 0) fail("startup high caused false rising edge");
        end
        repeat(160000) @(negedge clk);
        clean_fifo;
        timestamp_snapshot(start_ts);
        for(ch=0;ch<4;ch=ch+1) begin
            if(measures[ch]<2) fail("insufficient measurement updates");
            read32('h104+ch*'h80,value); if(!value[5]) fail("statistics invalid");
            read32('h108+ch*'h80,value); if(value<periods[ch] || value>periods[ch]+((ch==3)?1:0)) fail("snapshot period");
            read32('h110+ch*'h80,value); if(value<highs[ch] || value>highs[ch]+((ch==3)?1:0)) fail("snapshot duty");
            read32('h118+ch*'h80,value); if(value<periods[ch]-highs[ch] || value>periods[ch]-highs[ch]+((ch==3)?1:0)) fail("snapshot low");
            // Explicit simulation-only fault injection through the real AXI/FIFO path.
            config64(ch,0,highs[ch]+100);
            write32('h100+ch*'h80,1); write32('hc,1);
            repeat(2*periods[ch]) @(negedge clk);
            write32('hc,0);
            read32('h30,info); count=0;
            while(info[16] && count<16) begin
                if(info[11:8]!==ch || info[7:0]!==1) fail("external event channel/type");
                read32('h3c,lo);read32('h40,hi); if({hi,lo}<highs[ch] || {hi,lo}>highs[ch]+((ch==3)?1:0)) fail("external event value");
                write32('h44,1); count=count+1; read32('h30,info);
            end
            if(count<1 || info[16]) fail("external FIFO count");
            write32('h100+ch*'h80,0); config64(ch,0,0); clean_fifo;
        end
        // Reset while signals keep running, then reacquire all channels.
        @(negedge clk); rst_n=0; repeat(8) @(negedge clk); rst_n=1;
        repeat(160000) @(negedge clk); clean_fifo;
        if(errors==0) $display("TEST PASSED: external four-channel asynchronous phase/duty/reset/AXI/fault/FIFO");
        else $fatal(1,"TEST FAILED: external errors=%0d",errors);
        $finish;
    end
    initial begin #20000000; $fatal(1,"TEST FAILED: external watchdog"); end
endmodule
