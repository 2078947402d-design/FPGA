`timescale 1ns / 1ps

module tb_timing_diagnostic_axi;
    localparam integer CHANNELS = 4;
    localparam integer W = 64;
    localparam [1:0] OKAY = 2'b00;
    localparam [1:0] SLVERR = 2'b10;

    reg clk;
    reg rst_n;
    reg [11:0] awaddr;
    reg [2:0] awprot;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wvalid;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;
    reg [11:0] araddr;
    reg [2:0] arprot;
    reg arvalid;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready;

    reg [W-1:0] core_timestamp;
    reg [CHANNELS-1:0] core_sync_level;
    reg [CHANNELS*W-1:0] core_period_ticks;
    reg [CHANNELS*W-1:0] core_high_ticks;
    reg [CHANNELS*W-1:0] core_low_ticks;
    reg [CHANNELS-1:0] core_period_valid;
    reg [CHANNELS-1:0] core_high_valid;
    reg [CHANNELS-1:0] core_low_valid;
    reg [CHANNELS*W-1:0] core_min_period;
    reg [CHANNELS*W-1:0] core_max_period;
    reg [CHANNELS*W-1:0] core_peak_to_peak;
    reg [CHANNELS-1:0] core_stats_valid;

    reg fifo_event_valid;
    reg [3:0] fifo_event_channel;
    reg [7:0] fifo_event_type;
    reg [W-1:0] fifo_event_timestamp;
    reg [W-1:0] fifo_event_value;
    reg event_pop_ack;
    reg event_fifo_empty;
    reg event_fifo_full;
    reg [15:0] event_fifo_level;
    reg [15:0] event_pending_level;
    reg event_overflow;
    reg [31:0] event_dropped_count;

    wire global_enable;
    wire [CHANNELS-1:0] channel_enable;
    wire [CHANNELS-1:0] clear_period_stats;
    wire clear_event_fifo;
    wire event_pop;
    wire [CHANNELS*W-1:0] min_high_ticks;
    wire [CHANNELS*W-1:0] min_low_ticks;
    wire [CHANNELS*W-1:0] timeout_ticks;
    wire [CHANNELS*W-1:0] period_min_limit;
    wire [CHANNELS*W-1:0] period_max_limit;
    wire [CHANNELS*W-1:0] reference_period;
    wire [CHANNELS*W-1:0] jump_limit_ticks;
    wire [CHANNELS*W-1:0] drift_limit_ticks;
    wire [CHANNELS*W-1:0] jitter_limit_ticks;

    integer errors;
    integer pop_count;
    integer pop_pulse_cycles;
    integer i;
    reg previous_event_pop;
    reg [31:0] rd;
    reg [1:0] rr;

    timing_diagnostic_axi_regs #(.CHANNELS(CHANNELS),.TS_WIDTH(W),.AXI_ADDR_WIDTH(12)) dut (
        .s_axi_aclk(clk),.s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),.s_axi_awprot(awprot),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(arprot),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .core_timestamp(core_timestamp),.core_sync_level(core_sync_level),
        .core_period_ticks(core_period_ticks),.core_high_ticks(core_high_ticks),.core_low_ticks(core_low_ticks),
        .core_period_valid(core_period_valid),.core_high_valid(core_high_valid),.core_low_valid(core_low_valid),
        .core_min_period(core_min_period),.core_max_period(core_max_period),
        .core_peak_to_peak(core_peak_to_peak),.core_stats_valid(core_stats_valid),
        .fifo_event_valid(fifo_event_valid),.fifo_event_channel(fifo_event_channel),
        .fifo_event_type(fifo_event_type),.fifo_event_timestamp(fifo_event_timestamp),
        .fifo_event_value(fifo_event_value),.event_pop_ack(event_pop_ack),
        .event_fifo_empty(event_fifo_empty),.event_fifo_full(event_fifo_full),
        .event_fifo_level(event_fifo_level),.event_pending_level(event_pending_level),
        .event_overflow(event_overflow),.event_dropped_count(event_dropped_count),
        .global_enable(global_enable),.channel_enable(channel_enable),
        .clear_period_stats(clear_period_stats),.clear_event_fifo(clear_event_fifo),.event_pop(event_pop),
        .min_high_ticks(min_high_ticks),.min_low_ticks(min_low_ticks),.timeout_ticks(timeout_ticks),
        .period_min_limit(period_min_limit),.period_max_limit(period_max_limit),
        .reference_period(reference_period),.jump_limit_ticks(jump_limit_ticks),
        .drift_limit_ticks(drift_limit_ticks),.jitter_limit_ticks(jitter_limit_ticks)
    );

    initial begin clk=1'b0; forever #10 clk=~clk; end

    task automatic report_error;
        input [8*160-1:0] message;
        begin
            $display("ERROR: %0s",message);
            errors=errors+1;
        end
    endtask

    task automatic axi_write;
        input [11:0] address;
        input [31:0] data;
        input [3:0] strobes;
        input integer aw_delay;
        input integer w_delay;
        input integer response_stall;
        input [1:0] expected_response;
        integer k;
        reg [1:0] held_response;
        begin
            fork
                begin
                    repeat(aw_delay) @(negedge clk);
                    awaddr=address; awvalid=1'b1;
                    while(!awready) @(negedge clk);
                    @(negedge clk); awvalid=1'b0;
                end
                begin
                    repeat(w_delay) @(negedge clk);
                    wdata=data; wstrb=strobes; wvalid=1'b1;
                    while(!wready) @(negedge clk);
                    @(negedge clk); wvalid=1'b0;
                end
            join
            while(!bvalid) @(negedge clk);
            held_response=bresp;
            for(k=0;k<response_stall;k=k+1) begin
                @(negedge clk);
                if(!bvalid || bresp!==held_response)
                    report_error("B channel changed under backpressure");
            end
            if(bresp!==expected_response) begin
                $display("ERROR: write addr %03h response %b expected %b",address,bresp,expected_response);
                errors=errors+1;
            end
            bready=1'b1;
            @(negedge clk); bready=1'b0;
        end
    endtask

    task automatic axi_read;
        input [11:0] address;
        input integer response_stall;
        output [31:0] data_out;
        output [1:0] response_out;
        integer k;
        reg [31:0] held_data;
        reg [1:0] held_response;
        begin
            araddr=address; arvalid=1'b1;
            while(!arready) @(negedge clk);
            @(negedge clk); arvalid=1'b0;
            while(!rvalid) @(negedge clk);
            held_data=rdata; held_response=rresp;
            for(k=0;k<response_stall;k=k+1) begin
                @(negedge clk);
                if(!rvalid || rdata!==held_data || rresp!==held_response)
                    report_error("R channel changed under backpressure");
            end
            data_out=rdata; response_out=rresp;
            rready=1'b1;
            @(negedge clk); rready=1'b0;
        end
    endtask

    task automatic read_expect;
        input [11:0] address;
        input [31:0] expected_data;
        input [1:0] expected_response;
        input integer stall_cycles;
        reg [31:0] got_data;
        reg [1:0] got_response;
        begin
            axi_read(address,stall_cycles,got_data,got_response);
            if(got_response!==expected_response ||
               ((expected_response==OKAY) && (got_data!==expected_data))) begin
                $display("ERROR: read addr %03h data/resp %08h/%b expected %08h/%b",
                         address,got_data,got_response,expected_data,expected_response);
                errors=errors+1;
            end
        end
    endtask

    // 简单 FIFO 消费模型：仅有效队首上的单拍 pop 才改变队列。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pop_count<=0;
            pop_pulse_cycles<=0;
            previous_event_pop<=1'b0;
            event_pop_ack<=1'b0;
        end else begin
            event_pop_ack<=1'b0;
            previous_event_pop<=event_pop;
            if(event_pop) begin
                pop_pulse_cycles<=pop_pulse_cycles+1;
                if(previous_event_pop)
                    report_error("EVENT_POP lasted more than one clock");
                if(fifo_event_valid) begin
                    pop_count<=pop_count+1;
                    event_pop_ack<=1'b1;
                    fifo_event_valid<=1'b0;
                    event_fifo_empty<=1'b1;
                    event_fifo_level<=16'd0;
                end
            end
            if(clear_event_fifo) begin
                fifo_event_valid<=1'b0;
                event_fifo_empty<=1'b1;
                event_fifo_full<=1'b0;
                event_fifo_level<=16'd0;
                event_pending_level<=16'd0;
                event_overflow<=1'b0;
                event_dropped_count<=32'd0;
            end
        end
    end

    initial begin
        errors=0;
        rst_n=0;
        awaddr=0; awprot=0; awvalid=0;
        wdata=0; wstrb=0; wvalid=0; bready=0;
        araddr=0; arprot=0; arvalid=0; rready=0;
        core_timestamp=0; core_sync_level=0;
        core_period_ticks=0; core_high_ticks=0; core_low_ticks=0;
        core_period_valid=0; core_high_valid=0; core_low_valid=0;
        core_min_period=0; core_max_period=0; core_peak_to_peak=0; core_stats_valid=0;
        fifo_event_valid=0; fifo_event_channel=0; fifo_event_type=0;
        fifo_event_timestamp=0; fifo_event_value=0; event_pop_ack=0;
        event_fifo_empty=1; event_fifo_full=0; event_fifo_level=0;
        event_pending_level=0; event_overflow=0; event_dropped_count=0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;

        // 1/2. 标识、版本和复位值。
        read_expect(12'h000,32'h5444_4731,OKAY,0);
        read_expect(12'h004,32'h0001_0000,OKAY,0);
        read_expect(12'h00C,32'd0,OKAY,0);
        read_expect(12'h018,32'd0,OKAY,0);
        read_expect(12'h100,32'd0,OKAY,0);
        read_expect(12'h128,32'd0,OKAY,0);

        // 3/5. AW 先到、W 后到；再反向到达，并检查响应。
        axi_write(12'h00C,32'h0000_0001,4'hf,0,3,0,OKAY);
        read_expect(12'h00C,32'h0000_0001,OKAY,0);
        axi_write(12'h100,32'h0000_0001,4'hf,3,0,0,OKAY);
        read_expect(12'h100,32'h0000_0001,OKAY,0);

        // 4. WSTRB：未选中的 byte0 不得改变全局使能；阈值 staging 支持逐字节更新。
        axi_write(12'h00C,32'h0000_0000,4'b0010,0,0,0,OKAY);
        read_expect(12'h00C,32'h0000_0001,OKAY,0);
        axi_write(12'h128,32'hAABB_CCDD,4'b0101,0,0,0,OKAY);
        axi_write(12'h12C,32'h1122_3344,4'hf,0,0,0,OKAY);
        if(timeout_ticks[63:0]!==64'd0)
            report_error("64-bit threshold changed before commit");
        axi_write(12'h314,32'h0000_0004,4'hf,0,0,0,OKAY);
        if(timeout_ticks[63:0]!==64'h1122_3344_00BB_00DD)
            report_error("WSTRB or atomic timeout commit failed");
        read_expect(12'h128,32'h00BB_00DD,OKAY,0);
        read_expect(12'h12C,32'h1122_3344,OKAY,0);
        // 全零 WSTRB 是空写，不能丢弃另一阈值已经准备的 staging。
        axi_write(12'h138,32'h1357_9BDF,4'hf,0,0,0,OKAY);
        axi_write(12'h250,32'hFFFF_FFFF,4'h0,0,0,0,OKAY);
        axi_write(12'h13C,32'h2468_ACE0,4'hf,0,0,0,OKAY);
        axi_write(12'h314,32'h0000_0010,4'hf,0,0,0,OKAY);
        if(period_max_limit[63:0]!==64'h2468_ACE0_1357_9BDF)
            report_error("zero-WSTRB write changed threshold staging state");

        // 6. B/R 背压；响应必须保持，连续事务仍可完成。
        axi_write(12'h180,32'h1,4'hf,0,0,4,OKAY);
        read_expect(12'h180,32'h1,OKAY,4);
        axi_write(12'h200,32'h1,4'hf,0,0,0,OKAY);
        axi_write(12'h280,32'h1,4'hf,0,0,0,OKAY);
        read_expect(12'h200,32'h1,OKAY,0);
        read_expect(12'h280,32'h1,OKAY,0);

        // 7/8. 每通道 staging/active 独立，显式提交前 active 值不改变。
        axi_write(12'h1B0,32'h5566_7788,4'hf,0,0,0,OKAY);
        axi_write(12'h1B4,32'h99AA_BBCC,4'hf,0,0,0,OKAY);
        if(period_min_limit[1*W +: W]!==64'd0)
            report_error("period min changed before commit");
        axi_write(12'h354,32'h0000_0008,4'hf,0,0,0,OKAY);
        if(period_min_limit[1*W +: W]!==64'h99AA_BBCC_5566_7788)
            report_error("channel 1 period min commit failed");
        if(period_min_limit[0*W +: W]!==64'd0 || period_min_limit[2*W +: W]!==64'd0)
            report_error("channel configurations interfered");
        // bit8 位于提交寄存器 byte1，验证提交命令同样遵守 WSTRB。
        axi_write(12'h250,32'h7654_3210,4'hf,0,0,0,OKAY);
        axi_write(12'h390,32'hFEDC_BA98,4'hf,0,0,0,OKAY);
        axi_write(12'h394,32'h0000_0100,4'b0010,0,0,0,OKAY);
        if(jitter_limit_ticks[2*W +: W]!==64'hFEDC_BA98_7654_3210)
            report_error("byte1 WSTRB commit for jitter threshold failed");

        // 9. 一次全局快照同时冻结四通道和 64 位统计；随后 live 改变不影响读值。
        @(negedge clk);
        core_timestamp=64'h0102_0304_0506_0708;
        core_period_ticks[0*W +: W]=64'h1111_2222_3333_4444;
        core_high_ticks[0*W +: W]=64'h5555_6666_7777_8888;
        core_low_ticks[0*W +: W]=64'h9999_AAAA_BBBB_CCCC;
        core_min_period[0*W +: W]=64'h0000_0001_0000_0002;
        core_max_period[0*W +: W]=64'h0000_0003_0000_0004;
        core_peak_to_peak[0*W +: W]=64'h0000_0002_0000_0002;
        core_sync_level[0]=1; core_period_valid[0]=1; core_high_valid[0]=1;
        core_low_valid[0]=1; core_stats_valid[0]=1;
        core_period_ticks[3*W +: W]=64'hDEAD_BEEF_CAFE_1234;
        axi_write(12'h00C,32'h0000_0003,4'hf,0,0,0,OKAY);
        @(negedge clk);
        core_timestamp=64'hFFFF_FFFF_FFFF_FFFF;
        core_period_ticks=0; core_high_ticks=0; core_low_ticks=0;
        core_min_period=0; core_max_period=0; core_peak_to_peak=0;
        read_expect(12'h018,32'd1,OKAY,0);
        read_expect(12'h01C,32'h0506_0708,OKAY,0);
        read_expect(12'h020,32'h0102_0304,OKAY,0);
        read_expect(12'h108,32'h3333_4444,OKAY,0);
        read_expect(12'h10C,32'h1111_2222,OKAY,0);
        read_expect(12'h288,32'hCAFE_1234,OKAY,0);
        read_expect(12'h318,32'h0000_0002,OKAY,0);
        read_expect(12'h31C,32'h0000_0001,OKAY,0);
        read_expect(12'h320,32'h0000_0004,OKAY,0);
        read_expect(12'h324,32'h0000_0003,OKAY,0);
        read_expect(12'h328,32'h0000_0002,OKAY,0);
        read_expect(12'h32C,32'h0000_0002,OKAY,0);

        // 10. show-ahead FIFO 队首字段、主 FIFO/暂存数量、溢出和丢失计数。
        @(negedge clk);
        fifo_event_valid=1; fifo_event_channel=4'd2; fifo_event_type=8'h07;
        fifo_event_timestamp=64'h1234_5678_9ABC_DEF0;
        fifo_event_value=64'h0FED_CBA9_8765_4321;
        event_fifo_empty=0; event_fifo_full=1; event_fifo_level=16'd64;
        event_pending_level=16'd9; event_overflow=1; event_dropped_count=32'd17;
        read_expect(12'h02C,{13'd0,1'b1,1'b1,1'b0,16'd64},OKAY,0);
        read_expect(12'h030,32'h0001_0207,OKAY,0);
        read_expect(12'h034,32'h9ABC_DEF0,OKAY,0);
        read_expect(12'h038,32'h1234_5678,OKAY,0);
        read_expect(12'h03C,32'h8765_4321,OKAY,0);
        read_expect(12'h040,32'h0FED_CBA9,OKAY,0);
        read_expect(12'h048,32'd17,OKAY,0);
        read_expect(12'h04C,32'd9,OKAY,0);
        read_expect(12'h050,{16'd9,16'd64},OKAY,0);

        // 11. 一个 EVENT_POP 写事务在 B 背压期间也只产生一个脉冲和一次消费。
        i=pop_count;
        axi_write(12'h044,32'h1,4'hf,0,2,5,OKAY);
        repeat(3) @(negedge clk);
        if(pop_count!==i+1)
            report_error("one EVENT_POP command did not consume exactly one event");

        // 12. 空 FIFO 的命令不向核心产生 pop，不应答、不改变消费数。
        i=pop_count;
        axi_write(12'h044,32'h1,4'hf,0,0,0,OKAY);
        repeat(2) @(negedge clk);
        if(pop_count!==i || event_pop_ack)
            report_error("empty FIFO was incorrectly popped");

        // 13. clear FIFO 命令是单拍并清除模型中的溢出/丢失状态。
        event_overflow=1; event_dropped_count=32'd99; event_pending_level=16'd3;
        axi_write(12'h00C,32'h0000_0011,4'hf,0,0,3,OKAY);
        repeat(2) @(negedge clk);
        read_expect(12'h048,32'd0,OKAY,0);
        read_expect(12'h04C,32'd0,OKAY,0);

        // 15. 只读地址写入、未定义地址、未对齐地址均返回 SLVERR。
        axi_write(12'h000,32'hDEAD_BEEF,4'hf,0,0,0,SLVERR);
        read_expect(12'h0FC,32'd0,SLVERR,0);
        read_expect(12'h001,32'd0,SLVERR,0);
        axi_write(12'h101,32'h1,4'hf,0,0,0,SLVERR);

        // 14. 运行中异步复位清除 AXI 状态、使能、配置、快照和命令。
        @(negedge clk); rst_n=0;
        #1;
        if(global_enable || channel_enable!=0 || timeout_ticks!=0 || bvalid || rvalid || event_pop)
            report_error("runtime reset values incorrect");
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1;
        read_expect(12'h00C,32'd0,OKAY,0);
        read_expect(12'h018,32'd0,OKAY,0);
        read_expect(12'h128,32'd0,OKAY,0);

        if(errors==0) begin
            $display("TEST PASSED: AXI4-Lite register interface self-check completed");
            $finish;
        end else begin
            $fatal(1,"TEST FAILED: AXI4-Lite register interface has %0d error(s)",errors);
        end
    end

    initial begin
        #3000000;
        $fatal(1,"TEST FAILED: AXI4-Lite register interface timeout");
    end
endmodule
