`timescale 1ns / 1ps
// New testbench only; instantiates the unchanged Vivado debug wrapper/RTL.
module tb_phase2_internal_faults;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0;
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
    timing_diagnostic_axi_bd_wrapper #(.EXTERNAL_MODE(0)) dut (.external_ch(4'b0),
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
        types[0]=1;types[1]=2;types[2]=3;types[3]=4;types[4]=5;types[5]=7;
        repeat(8) @(negedge clk); rst_n=1;
        repeat(160000) @(negedge clk); // Establish measurements, fixed real dividers.
        for(ch=0;ch<4;ch=ch+1) begin
            p=(ch==0)?50000:(ch==1)?25000:(ch==2)?10000:5000;
            for(k=0;k<6;k=k+1) begin
                typ=types[k]; clean_fifo;
                timestamp_snapshot(start_ts);
                read32('h108+ch*'h80,value); if(value!==p) fail("baseline period");
                read32('h110+ch*'h80,value); if(value!==p/2) fail("baseline high");
                read32('h118+ch*'h80,value); if(value!==p/2) fail("baseline low");
                reference=0;
                for(i=0;i<9;i=i+1) saved_cfg[i]=0;
                // Exercise restoration of legal nonzero period intervals.
                if(typ==5) begin
                    saved_cfg[3]=p; saved_cfg[4]=p+p/5;
                    config64(ch,3,saved_cfg[3]); config64(ch,4,saved_cfg[4]);
                end
                case(typ)
                    1: begin index=0; threshold=p/2+p/10; expected=p/2; end
                    2: begin index=1; threshold=p/2+p/10; expected=p/2; end
                    3: begin index=2; threshold=p/2; expected=p/2+1; end
                    4: begin index=3; threshold=p+p/5; expected=p; end
                    5: begin index=4; threshold=p-p/5; expected=p; end
                    7: begin index=7; threshold=p/10; reference=p+p/5; expected=p/5; end
                endcase
                for(i=0;i<9;i=i+1) config64(ch,i,(i==index)?threshold:(i==5)?reference:0);
                write32('h100+ch*'h80,1);
                timestamp_snapshot(start_ts);
                write32('hc,1);
                repeat(2*p) @(negedge clk);
                write32('hc,0);
                timestamp_snapshot(end_ts);
                // Restore and verify BEFORE reading/popping event records.
                write32('h100+ch*'h80,0);
                config64(ch,3,0); config64(ch,4,0);
                for(i=0;i<9;i=i+1) config64(ch,i,saved_cfg[i]);
                count=0; previous_ts=0;
                read32('h30,info);
                while(info[16] && count<32) begin
                    read32('h34,lo);read32('h38,hi);event_ts={hi,lo};
                    read32('h3c,lo);read32('h40,hi);event_value={hi,lo};
                    if(info[11:8]!==ch || info[7:0]!==typ) fail("event type/channel mismatch");
                    if(event_ts<start_ts || event_ts>end_ts || (count && event_ts<=previous_ts)) fail("timestamp range/order");
                    if(typ==3) begin
                        if(event_value<expected || event_value>=p || (count && event_value!==expected)) fail("timeout value");
                    end else begin
                        if(event_value!==expected) fail("event value mismatch");
                        if(count && event_ts-previous_ts!==p) fail("timestamp spacing");
                    end
                    previous_ts=event_ts; count=count+1;
                    write32('h44,1);read32('h2c,value);read32('h30,info);
                end
                if(count<((typ==3)?1:2) || count>4 || info[16]) fail("event count/backlog");
                clean_fifo;
                $display("RTL CASE: CH%0d TYPE=%02h threshold=%0d expected=%0d events=%0d restored=1",ch,typ,threshold,expected,count);
                passed=passed+1;
                config64(ch,3,0); config64(ch,4,0); // Leave next case's baseline clean.
            end
        end
        if(errors==0 && passed==24) $display("TEST PASSED: phase2 24 internal-wave AXI fault cases, channel/type/value/timestamp/FIFO/restore");
        else $fatal(1,"TEST FAILED: errors=%0d cases=%0d",errors,passed);
        $finish;
    end
    initial begin #50000000; $fatal(1,"TEST FAILED: simulation watchdog timeout"); end
endmodule
