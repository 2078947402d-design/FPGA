`timescale 1ns / 1ps

module tb_event_arbiter_fifo;
    localparam integer CHANNELS = 4;
    localparam integer TYPES = 8;
    localparam integer LANES = CHANNELS*TYPES;
    localparam integer W = 64;

    reg clk;
    reg rst_n;
    reg clear;
    reg [LANES-1:0] event_valid_in;
    reg [LANES*W-1:0] event_timestamp_in;
    reg [LANES*W-1:0] event_value_in;
    reg event_pop;

    wire event_pop_ack;
    wire event_valid;
    wire [3:0] event_channel;
    wire [7:0] event_type;
    wire [W-1:0] event_timestamp;
    wire [W-1:0] event_value;
    wire fifo_empty;
    wire fifo_full;
    wire [15:0] fifo_level;
    wire [15:0] pending_level;
    wire overflow;
    wire [7:0] dropped_count;

    integer errors;
    integer i;
    integer timeout;
    reg [7:0] drop_snapshot;

    event_arbiter_fifo #(
        .CHANNELS(CHANNELS), .EVENT_TYPES(TYPES), .TS_WIDTH(W),
        .CHANNEL_ID_WIDTH(4), .FIFO_DEPTH(64),
        .DROP_COUNT_WIDTH(8)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .event_valid_in(event_valid_in),
        .event_timestamp_in(event_timestamp_in), .event_value_in(event_value_in),
        .event_pop(event_pop), .event_pop_ack(event_pop_ack),
        .event_valid(event_valid), .event_channel(event_channel),
        .event_type(event_type), .event_timestamp(event_timestamp),
        .event_value(event_value), .fifo_empty(fifo_empty), .fifo_full(fifo_full),
        .fifo_level(fifo_level), .pending_level(pending_level),
        .overflow(overflow), .dropped_count(dropped_count)
    );

    initial begin clk=1'b0; forever #10 clk=~clk; end

    task automatic set_lane;
        input integer lane_number;
        input [63:0] timestamp_value;
        input [63:0] associated_value;
        begin
            event_timestamp_in[lane_number*W +: W] = timestamp_value;
            event_value_in[lane_number*W +: W] = associated_value;
        end
    endtask

    task automatic pulse_clear;
        begin
            @(negedge clk); clear=1'b1; event_valid_in=0; event_pop=0;
            @(negedge clk); clear=1'b0;
            repeat(2) @(posedge clk); #1;
            if (!fifo_empty || fifo_level!=0 || pending_level!=0 || overflow || dropped_count!=0) begin
                $display("ERROR: clear did not empty all event state"); errors=errors+1;
            end
        end
    endtask

    task automatic inject_mask;
        input [LANES-1:0] mask;
        input [63:0] timestamp_base;
        input [63:0] value_base;
        integer k;
        begin
            @(negedge clk);
            for(k=0;k<LANES;k=k+1)
                if(mask[k]) set_lane(k,timestamp_base+k,value_base+k);
            event_valid_in=mask;
            @(negedge clk); event_valid_in=0;
        end
    endtask

    task automatic pop_expect;
        input integer lane_number;
        input [63:0] expected_timestamp;
        input [63:0] expected_value;
        begin
            timeout=0;
            while(!event_valid && timeout<300) begin @(negedge clk); timeout=timeout+1; end
            if(!event_valid) begin
                $display("ERROR: timeout waiting for event lane %0d",lane_number); errors=errors+1;
            end else begin
                if(event_channel !== lane_number/8 || event_type !== (lane_number%8)+1 ||
                   event_timestamp !== expected_timestamp || event_value !== expected_value) begin
                    $display("ERROR: event mismatch lane=%0d got ch/type/ts/value=%0d/%0d/%0d/%0h",
                             lane_number,event_channel,event_type,event_timestamp,event_value);
                    errors=errors+1;
                end
                event_pop=1'b1; #1;
                if(!event_pop_ack) begin $display("ERROR: pop handshake missing"); errors=errors+1; end
                @(negedge clk); event_pop=1'b0;
            end
        end
    endtask

    task automatic drive_lane0_cycles;
        input integer cycles;
        input [63:0] first_timestamp;
        integer k;
        begin
            @(negedge clk);
            event_valid_in=0; event_valid_in[0]=1'b1;
            for(k=0;k<cycles;k=k+1) begin
                set_lane(0,first_timestamp+k,64'hF000_0000_0000_0000+k);
                @(negedge clk);
            end
            event_valid_in=0;
        end
    endtask

    initial begin
        errors=0; rst_n=0; clear=0; event_valid_in=0;
        event_timestamp_in=0; event_value_in=0; event_pop=0;
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;

        // 32 条同拍全部捕获，并按 channel/type 固定顺序输出。
        inject_mask({LANES{1'b1}},64'd1000,64'hA000_0000_0000_0000);
        for(i=0;i<LANES;i=i+1)
            pop_expect(i,64'd1000+i,64'hA000_0000_0000_0000+i);
        repeat(3) @(posedge clk); #1;
        if(!fifo_empty || pending_level!=0 || overflow || dropped_count!=0) begin
            $display("ERROR: 32-event burst was not lossless"); errors=errors+1;
        end

        // 两批不重叠 lane 先后积压，验证固定优先级仲裁和元数据保持。
        pulse_clear();
        inject_mask(32'h0000_FFFF,64'd2000,64'hB000_0000_0000_0000);
        inject_mask(32'hFFFF_0000,64'd3000,64'hC000_0000_0000_0000);
        for(i=0;i<16;i=i+1)
            pop_expect(i,64'd2000+i,64'hB000_0000_0000_0000+i);
        for(i=16;i<32;i=i+1)
            pop_expect(i,64'd3000+i,64'hC000_0000_0000_0000+i);
        if(overflow || dropped_count!=0) begin
            $display("ERROR: backlog test unexpectedly overflowed"); errors=errors+1;
        end

        // 不读出，以单源持续流填满主 FIFO并留 1 条待处理，再填满其余 31 个源槽。
        pulse_clear();
        drive_lane0_cycles(65,64'd4000);
        inject_mask(32'hFFFF_FFFE,64'd4500,64'hE000_0000_0000_0000);
        repeat(3) @(posedge clk); #1;
        if(!fifo_full || fifo_level!=64 || pending_level!=32 || overflow || dropped_count!=0) begin
            $display("ERROR: full-state fill failed fifo=%0d pending=%0d full=%b overflow=%b dropped=%0d",
                     fifo_level,pending_level,fifo_full,overflow,dropped_count); errors=errors+1;
        end

        // 满状态下同时 pop、内部 FIFO 写、对应源槽补充：容量保持且不能丢失。
        drop_snapshot=dropped_count;
        @(negedge clk); event_pop=1'b1;
        for(i=1;i<=10;i=i+1) begin
            event_valid_in=1;
            set_lane(0,64'd9000+i,64'hD000+i); #1;
            if(!event_pop_ack) begin $display("ERROR: full-state simultaneous pop not acknowledged"); errors=errors+1; end
            @(negedge clk);
        end
        event_pop=1'b0; event_valid_in=0; #1;
        if(dropped_count!=drop_snapshot || fifo_level!=64 || pending_level!=32) begin
            $display("ERROR: simultaneous read/write changed capacity or loss count"); errors=errors+1;
        end

        // 持续过载：每一个无法接收的事件均计数，8 位测试配置最终饱和到 255。
        drive_lane0_cycles(300,64'd5000);
        #1;
        if(!overflow || dropped_count!=8'hff) begin
            $display("ERROR: overflow/saturation failed overflow=%b dropped=%0d",overflow,dropped_count);
            errors=errors+1;
        end

        // 排空主 FIFO 和积压缓存，验证空标志及空时 pop 不应答。
        @(negedge clk); event_pop=1'b1;
        timeout=0;
        while((!fifo_empty || pending_level!=0) && timeout<400) begin
            @(negedge clk); timeout=timeout+1;
        end
        event_pop=1'b0; #1;
        if(timeout>=400 || !fifo_empty || fifo_level!=0 || pending_level!=0) begin
            $display("ERROR: drain/empty failed"); errors=errors+1;
        end
        event_pop=1'b1; #1;
        if(event_pop_ack) begin $display("ERROR: empty FIFO acknowledged pop"); errors=errors+1; end
        event_pop=1'b0;

        // 运行中异步低有效复位清除 FIFO、缓存和溢出统计。
        @(negedge clk); rst_n=1'b0;
        repeat(3) @(posedge clk); #1;
        if(!fifo_empty || fifo_level!=0 || pending_level!=0 || overflow || dropped_count!=0 || event_valid) begin
            $display("ERROR: runtime reset failed"); errors=errors+1;
        end
        @(negedge clk); rst_n=1'b1;

        if(errors==0) begin
            $display("TEST PASSED: event_arbiter_fifo self-check completed"); $finish;
        end else begin
            $fatal(1,"TEST FAILED: event_arbiter_fifo has %0d error(s)",errors);
        end
    end

    initial begin #1000000; $fatal(1,"TEST FAILED: timeout"); end
endmodule
