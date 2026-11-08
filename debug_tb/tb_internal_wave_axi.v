`timescale 1ns / 1ps
module tb_internal_wave_axi;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0;
    reg [11:0] awaddr=0, araddr=0;
    reg [31:0] wdata=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    integer errors=0, cycle=0, ch;
    integer half_period[0:3];
    integer last_edge[0:3], last_rise[0:3], wave_rises[0:3];
    integer period_count[0:3], high_count[0:3], low_count[0:3];
    reg [3:0] previous=0;
    reg [31:0] held[0:3][0:12];
    reg [31:0] value,seq,tslo,tshi;
    reg [63:0] first_timestamp, next_timestamp;
    integer epoch,k,i;

    timing_diagnostic_axi_bd_wrapper #(.EXTERNAL_MODE(0)) dut (
        .external_ch(4'b0),
        .s_axi_aclk(clk),.s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(4'hf),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready)
    );
    task fail;
        input [8*160-1:0] msg;
        begin $display("ERROR: %0s time=%0t",msg,$time); errors=errors+1; end
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
            rready=1;
            @(negedge clk); rready=0;
        end
    endtask
    task write32;
        input [11:0] addr;
        input [31:0] data;
        begin
            @(negedge clk); awaddr=addr;awvalid=1;
            @(posedge clk); while(!awready) @(posedge clk);
            @(negedge clk); awvalid=0;wdata=data;wvalid=1;
            @(posedge clk); while(!wready) @(posedge clk);
            @(negedge clk); wvalid=0;
            while(!bvalid) @(negedge clk);
            if(bresp!==0) fail("AXI write response");
            bready=1;
            @(negedge clk); bready=0;
        end
    endtask
    task expect32;
        input [11:0] addr;
        input [31:0] expected;
        reg [31:0] got;
        begin
            read32(addr,got);
            if(got!==expected) begin
                $display("ERROR: addr=%03h got=%08h expected=%08h",addr,got,expected);
                errors=errors+1;
            end
        end
    endtask
    task snapshot;
        begin
            read32(12'h018,seq);
            write32(12'h00c,2);
            expect32(12'h018,seq+1);
        end
    endtask

    // Monitor every waveform transition and every genuine core update,
    // independently of AXI snapshots. Sample after NBA, count FCLK cycles.
    always @(posedge clk) begin
        #1;
        if(!rst_n) begin
            cycle=0; previous=0;
            if(dut.test_ch!==0) fail("generator nonzero during reset");
            for(ch=0;ch<4;ch=ch+1) begin
                last_edge[ch]=0;last_rise[ch]=0;wave_rises[ch]=0;
                period_count[ch]=0;high_count[ch]=0;low_count[ch]=0;
            end
        end else begin
            cycle=cycle+1;
            if(dut.u_timing_diagnostic_axi_top.fifo_event_valid !== 1'b0 ||
               dut.u_timing_diagnostic_axi_top.event_fifo_level !== 0 ||
               dut.u_timing_diagnostic_axi_top.event_pending_level !== 0 ||
               dut.u_timing_diagnostic_axi_top.event_overflow !== 0 ||
               dut.u_timing_diagnostic_axi_top.event_dropped_count !== 0)
                fail("unexpected FIFO event/overflow while diagnostic disabled");
            for(ch=0;ch<4;ch=ch+1) begin
                if(dut.test_ch[ch] !== previous[ch]) begin
                    if(cycle-last_edge[ch] != half_period[ch]) fail("wave half period off by one");
                    last_edge[ch]=cycle;
                    if(dut.test_ch[ch]) begin
                        if(wave_rises[ch]>0 && cycle-last_rise[ch]!=2*half_period[ch]) fail("wave full period");
                        last_rise[ch]=cycle;wave_rises[ch]=wave_rises[ch]+1;
                    end
                end
                if(dut.u_timing_diagnostic_axi_top.period_valid[ch]) begin
                    if(dut.u_timing_diagnostic_axi_top.period_ticks[ch*64+:64] !== 2*half_period[ch]) fail("core period off by one");
                    period_count[ch]=period_count[ch]+1;
                end
                if(dut.u_timing_diagnostic_axi_top.high_valid[ch]) begin
                    if(dut.u_timing_diagnostic_axi_top.high_ticks[ch*64+:64] !== half_period[ch]) fail("core high width off by one");
                    high_count[ch]=high_count[ch]+1;
                end
                if(dut.u_timing_diagnostic_axi_top.low_valid[ch]) begin
                    if(dut.u_timing_diagnostic_axi_top.low_ticks[ch*64+:64] !== half_period[ch]) fail("core low width off by one");
                    low_count[ch]=low_count[ch]+1;
                end
            end
            previous=dut.test_ch;
        end
    end

    task capture_and_check;
        integer c,j;
        reg [31:0] status;
        begin
            snapshot;
            read32(12'h01c,tslo);read32(12'h020,tshi);
            for(c=0;c<4;c=c+1) begin
                read32(12'h104+c*128,status);held[c][0]=status;
                if(!status[5]) fail("statistics not valid");
                expect32(12'h108+c*128,2*half_period[c]);
                expect32(12'h10c+c*128,0);
                expect32(12'h110+c*128,half_period[c]);
                expect32(12'h114+c*128,0);
                expect32(12'h118+c*128,half_period[c]);
                expect32(12'h11c+c*128,0);
                expect32(12'h318+c*64,2*half_period[c]);expect32(12'h31c+c*64,0);
                expect32(12'h320+c*64,2*half_period[c]);expect32(12'h324+c*64,0);
                expect32(12'h328+c*64,0);expect32(12'h32c+c*64,0);
                for(j=0;j<6;j=j+1) read32(12'h108+c*128+j*4,held[c][j+1]);
                for(j=0;j<6;j=j+1) read32(12'h318+c*64+j*4,held[c][j+7]);
                $display("MEASURE epoch=%0d CH%0d period=%0d high=%0d low=%0d min=%0d max=%0d p2p=0",epoch,c,2*half_period[c],half_period[c],half_period[c],2*half_period[c],2*half_period[c]);
            end
            expect32(12'h00c,0);expect32(12'h010,2);
            expect32(12'h02c,32'h10000);expect32(12'h030,0);
            expect32(12'h048,0);expect32(12'h04c,0);expect32(12'h050,0);
        end
    endtask

    initial begin
        half_period[0]=25000;half_period[1]=12500;half_period[2]=5000;half_period[3]=2500;
        repeat(8) @(negedge clk);
        for(epoch=0;epoch<2;epoch=epoch+1) begin
            rst_n=1;
            expect32(0,32'h54444731);expect32(4,32'h10000);expect32(8,32'h34004);
            expect32(12'h018,0);expect32(12'h01c,0);expect32(12'h020,0);
            for(i=0;i<4;i=i+1) begin
                expect32(12'h100+i*128,0);
                for(k=8;k<=28;k=k+4) expect32(12'h100+i*128+k,0);
            end
            // Default real divider values, no simulation acceleration.
            repeat(260000) @(negedge clk); // 5.2 ms uninterrupted per epoch
            capture_and_check;
            first_timestamp={tshi,tslo};
            repeat(60001) @(negedge clk); // live inputs continue while snapshot holds
            expect32(12'h01c,tslo);expect32(12'h020,tshi);
            expect32(12'h018,seq+1);
            for(i=0;i<4;i=i+1) begin
                expect32(12'h104+i*128,held[i][0]);
                for(k=0;k<6;k=k+1) expect32(12'h108+i*128+k*4,held[i][k+1]);
                for(k=0;k<6;k=k+1) expect32(12'h318+i*64+k*4,held[i][k+7]);
                if(period_count[i]<4 || high_count[i]<4 || low_count[i]<4) fail("insufficient genuine measurements");
                $display("COUNTS epoch=%0d CH%0d rises=%0d period=%0d high=%0d low=%0d",epoch,i,wave_rises[i],period_count[i],high_count[i],low_count[i]);
            end
            capture_and_check;
            next_timestamp={tshi,tslo};
            if(next_timestamp<=first_timestamp) fail("snapshot timestamp did not advance");
            if(epoch==0) begin
                // Reassert reset while all four channels are running.
                @(negedge clk);rst_n=0;
                repeat(8) @(negedge clk);
            end
        end
        if(errors==0) $display("TEST PASSED: internal wave AXI integration, two reset epochs, >12ms");
        else $fatal(1,"TEST FAILED: %0d errors",errors);
        $finish;
    end
    initial begin #15000000; $fatal(1,"TEST FAILED: AXI/simulation watchdog timeout"); end
endmodule
