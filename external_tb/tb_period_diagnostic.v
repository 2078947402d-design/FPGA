`timescale 1ns / 1ps

module tb_period_diagnostic;

    localparam integer CHANNELS = 4;
    localparam integer TS_WIDTH = 64;
    localparam integer LANES    = CHANNELS * 5;

    reg clk;
    reg rst_n;
    reg [TS_WIDTH-1:0] timestamp;
    reg [CHANNELS-1:0] clear_stats;
    reg [CHANNELS*TS_WIDTH-1:0] period_ticks;
    reg [CHANNELS-1:0] period_valid;
    reg [CHANNELS*TS_WIDTH-1:0] period_min_limit;
    reg [CHANNELS*TS_WIDTH-1:0] period_max_limit;
    reg [CHANNELS*TS_WIDTH-1:0] reference_period;
    reg [CHANNELS*TS_WIDTH-1:0] jump_limit_ticks;
    reg [CHANNELS*TS_WIDTH-1:0] drift_limit_ticks;
    reg [CHANNELS*TS_WIDTH-1:0] jitter_limit_ticks;

    wire [LANES-1:0] event_valid;
    wire [LANES*4-1:0] event_channel;
    wire [LANES*8-1:0] event_type;
    wire [LANES*TS_WIDTH-1:0] event_timestamp;
    wire [LANES*TS_WIDTH-1:0] event_value;
    wire [CHANNELS*TS_WIDTH-1:0] min_period;
    wire [CHANNELS*TS_WIDTH-1:0] max_period;
    wire [CHANNELS*TS_WIDTH-1:0] peak_to_peak_jitter;
    wire [CHANNELS*TS_WIDTH-1:0] adjacent_period_diff;
    wire [CHANNELS-1:0] stats_valid;

    integer errors;
    integer lane;
    integer channel_index;
    integer expected_type;
    integer short_count [0:CHANNELS-1];
    integer long_count  [0:CHANNELS-1];
    integer jump_count  [0:CHANNELS-1];
    integer drift_count [0:CHANNELS-1];
    integer jitter_count[0:CHANNELS-1];
    reg [TS_WIDTH-1:0] last_value [0:8];

    multi_channel_period_diagnostic #(
        .CHANNELS(CHANNELS), .TS_WIDTH(TS_WIDTH), .CHANNEL_ID_WIDTH(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear_stats(clear_stats),
        .timestamp(timestamp), .period_ticks(period_ticks),
        .period_valid(period_valid), .period_min_limit(period_min_limit),
        .period_max_limit(period_max_limit), .reference_period(reference_period),
        .jump_limit_ticks(jump_limit_ticks), .drift_limit_ticks(drift_limit_ticks),
        .jitter_limit_ticks(jitter_limit_ticks), .event_valid(event_valid),
        .event_channel(event_channel), .event_type(event_type),
        .event_timestamp(event_timestamp), .event_value(event_value),
        .min_period(min_period), .max_period(max_period),
        .peak_to_peak_jitter(peak_to_peak_jitter),
        .adjacent_period_diff(adjacent_period_diff), .stats_valid(stats_valid)
    );

    initial begin clk = 0; forever #10 clk = ~clk; end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) timestamp <= 0; else timestamp <= timestamp + 1'b1;

    task automatic configure;
        input integer ch;
        input [63:0] pmin, pmax, pref, jump, drift, jitter;
        begin
            period_min_limit[ch*TS_WIDTH +: TS_WIDTH] = pmin;
            period_max_limit[ch*TS_WIDTH +: TS_WIDTH] = pmax;
            reference_period[ch*TS_WIDTH +: TS_WIDTH] = pref;
            jump_limit_ticks[ch*TS_WIDTH +: TS_WIDTH] = jump;
            drift_limit_ticks[ch*TS_WIDTH +: TS_WIDTH] = drift;
            jitter_limit_ticks[ch*TS_WIDTH +: TS_WIDTH] = jitter;
        end
    endtask

    task automatic inject_period;
        input integer ch;
        input [63:0] value;
        begin
            @(negedge clk);
            period_ticks[ch*TS_WIDTH +: TS_WIDTH] = value;
            period_valid[ch] = 1'b1;
            @(negedge clk);
            period_valid[ch] = 1'b0;
            #2;
        end
    endtask

    task automatic pulse_clear;
        input integer ch;
        begin
            @(negedge clk); clear_stats[ch] = 1'b1;
            @(negedge clk); clear_stats[ch] = 1'b0;
            #2;
        end
    endtask

    task automatic reset_dut;
        integer i;
        begin
            @(negedge clk); rst_n = 1'b0;
            period_valid = 0; clear_stats = 0;
            repeat (3) @(posedge clk); #2;
            for (i=0; i<CHANNELS; i=i+1) begin
                short_count[i]=0; long_count[i]=0; jump_count[i]=0;
                drift_count[i]=0; jitter_count[i]=0;
            end
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            for (lane=0; lane<LANES; lane=lane+1) begin
                if (event_valid[lane]) begin
                    channel_index = event_channel[lane*4 +: 4];
                    expected_type = 4 + (lane % 5);
                    if ((channel_index != lane/5) ||
                        (event_type[lane*8 +: 8] != expected_type)) begin
                        $display("ERROR: bad lane metadata lane=%0d ch=%0d type=%0h",
                                 lane, channel_index, event_type[lane*8 +: 8]);
                        errors = errors + 1;
                    end
                    if (^event_timestamp[lane*TS_WIDTH +: TS_WIDTH] === 1'bx) begin
                        $display("ERROR: event timestamp contains X");
                        errors = errors + 1;
                    end
                    last_value[event_type[lane*8 +: 8]] =
                        event_value[lane*TS_WIDTH +: TS_WIDTH];
                    case(event_type[lane*8 +: 8])
                        8'h04: short_count[channel_index]=short_count[channel_index]+1;
                        8'h05: long_count[channel_index]=long_count[channel_index]+1;
                        8'h06: jump_count[channel_index]=jump_count[channel_index]+1;
                        8'h07: drift_count[channel_index]=drift_count[channel_index]+1;
                        8'h08: jitter_count[channel_index]=jitter_count[channel_index]+1;
                        default: begin errors=errors+1; $display("ERROR: unknown type"); end
                    endcase
                end
            end
        end
    end

    initial begin
        errors=0; rst_n=0; timestamp=0; clear_stats=0; period_ticks=0;
        period_valid=0; period_min_limit=0; period_max_limit=0;
        reference_period=0; jump_limit_ticks=0; drift_limit_ticks=0;
        jitter_limit_ticks=0;
        for(lane=0; lane<CHANNELS; lane=lane+1) begin
            short_count[lane]=0; long_count[lane]=0; jump_count[lane]=0;
            drift_count[lane]=0; jitter_count[lane]=0;
        end
        for(lane=0; lane<9; lane=lane+1) last_value[lane]=0;
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;

        // 首周期与所有等于阈值边界：不产生事件。
        configure(0, 8, 12, 10, 4, 2, 4);
        inject_period(0,10);
        inject_period(0,8);
        inject_period(0,12);
        if ((short_count[0]+long_count[0]+jump_count[0]+drift_count[0]+jitter_count[0]) != 0) begin
            $display("ERROR: equality/first-period boundary generated event"); errors=errors+1;
        end
        if ((min_period[0 +: 64] != 8) || (max_period[0 +: 64] != 12) ||
            (peak_to_peak_jitter[0 +: 64] != 4) ||
            (adjacent_period_diff[0 +: 64] != 4)) begin
            $display("ERROR: initial jitter statistics incorrect"); errors=errors+1;
        end

        // 13：过长、漂移3、峰峰值5；抖动首次越限。
        inject_period(0,13);
        if ((long_count[0]!=1) || (drift_count[0]!=1) || (jitter_count[0]!=1) ||
            (last_value[5]!=13) || (last_value[7]!=3) || (last_value[8]!=5)) begin
            $display("ERROR: long/drift/jitter detection failed"); errors=errors+1;
        end

        // 6：过短、相邻差7、漂移4；抖动已报告，不重复。
        inject_period(0,6);
        inject_period(0,7);
        if ((short_count[0]!=2) || (jump_count[0]!=1) ||
            (drift_count[0]!=3) || (jitter_count[0]!=1) ||
            (last_value[6]!=7)) begin
            $display("ERROR: continuous fault/jump behavior failed"); errors=errors+1;
        end

        // 动态将所有阈值置零：报警关闭，但统计继续。
        configure(0,0,0,0,0,0,0);
        inject_period(0,100);
        if ((short_count[0]!=2)||(long_count[0]!=1)||(jump_count[0]!=1)||
            (drift_count[0]!=3)||(jitter_count[0]!=1)||(max_period[0 +:64]!=100)) begin
            $display("ERROR: zero-threshold semantics failed"); errors=errors+1;
        end

        // 清统计后开始新窗口；清除同拍优先，所有状态回到无效。
        pulse_clear(0);
        if (stats_valid[0] || min_period[0 +:64]!=0 || max_period[0 +:64]!=0) begin
            $display("ERROR: clear_stats failed"); errors=errors+1;
        end
        configure(0,9,11,10,2,1,2);
        inject_period(0,10);
        inject_period(0,12); // jump=2、p2p=2 均等于阈值；long+drift
        inject_period(0,15); // jump=3、p2p=5 越限
        if ((long_count[0]!=3)||(jump_count[0]!=2)||(drift_count[0]!=5)||
            (jitter_count[0]!=2)||(min_period[0 +:64]!=10)||
            (max_period[0 +:64]!=15)||(peak_to_peak_jitter[0 +:64]!=5)) begin
            $display("ERROR: dynamic configuration/new window failed"); errors=errors+1;
        end

        // 复位后四通道独立：各通道分别触发不同诊断类型。
        reset_dut();
        configure(0,8,0,0,0,0,0);
        configure(1,0,12,0,0,0,0);
        configure(2,0,0,10,0,2,0);
        configure(3,0,0,0,0,0,1);
        @(negedge clk); rst_n=1;
        fork
            inject_period(0,6);
            inject_period(1,14);
            inject_period(2,14);
            begin inject_period(3,10); inject_period(3,12); end
        join
        if ((short_count[0]!=1)||(long_count[1]!=1)||(drift_count[2]!=1)||
            (jitter_count[3]!=1)) begin
            $display("ERROR: four-channel isolation failed"); errors=errors+1;
        end

        reset_dut();
        if (event_valid!=0 || stats_valid!=0) begin
            $display("ERROR: runtime reset failed"); errors=errors+1;
        end

        if(errors==0) begin
            $display("TEST PASSED: period_diagnostic self-check completed"); $finish;
        end else $fatal(1,"TEST FAILED: %0d error(s)",errors);
    end

    initial begin #200000; $fatal(1,"TEST FAILED: timeout"); end
endmodule
