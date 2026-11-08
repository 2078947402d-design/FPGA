`timescale 1ns / 1ps

module tb_timing_measure_core;

    localparam integer CHANNELS = 4;
    localparam integer TS_WIDTH = 64;

    reg                         clk;
    reg                         rst_n;
    reg  [CHANNELS-1:0]         async_ch;
    wire [TS_WIDTH-1:0]         timestamp;
    wire [CHANNELS-1:0]         sync_level;
    wire [CHANNELS-1:0]         rise_pulse;
    wire [CHANNELS-1:0]         fall_pulse;
    wire [CHANNELS*TS_WIDTH-1:0] period_ticks;
    wire [CHANNELS*TS_WIDTH-1:0] high_ticks;
    wire [CHANNELS*TS_WIDTH-1:0] low_ticks;
    wire [CHANNELS-1:0]         period_valid;
    wire [CHANNELS-1:0]         high_valid;
    wire [CHANNELS-1:0]         low_valid;

    integer errors;
    integer ch;
    integer period_count [0:CHANNELS-1];
    integer high_count   [0:CHANNELS-1];
    integer low_count    [0:CHANNELS-1];
    integer expected_period [0:CHANNELS-1];
    integer expected_high   [0:CHANNELS-1];
    integer expected_low    [0:CHANNELS-1];

    timing_measure_core #(
        .CHANNELS   (CHANNELS),
        .SYNC_STAGES(3),
        .TS_WIDTH   (TS_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .async_ch    (async_ch),
        .timestamp   (timestamp),
        .sync_level  (sync_level),
        .rise_pulse  (rise_pulse),
        .fall_pulse  (fall_pulse),
        .period_ticks(period_ticks),
        .high_ticks  (high_ticks),
        .low_ticks   (low_ticks),
        .period_valid(period_valid),
        .high_valid  (high_valid),
        .low_valid   (low_valid)
    );

    // 50 MHz：周期 20 ns。
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // 在时钟下降沿改变异步激励，避免 Testbench 与 DUT 在同一仿真时隙竞争。
    task automatic drive_pulse_train;
        input integer channel_index;
        input integer high_cycles;
        input integer low_cycles;
        input integer pulse_number;
        integer pulse_index;
        begin
            for (pulse_index = 0; pulse_index < pulse_number;
                 pulse_index = pulse_index + 1) begin
                repeat (low_cycles) @(negedge clk);
                async_ch[channel_index] = 1'b1;
                repeat (high_cycles) @(negedge clk);
                async_ch[channel_index] = 1'b0;
            end
        end
    endtask

    // 对每次更新的测量值自动判定。
    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                if (period_valid[ch]) begin
                    period_count[ch] = period_count[ch] + 1;
                    if (period_ticks[ch*TS_WIDTH +: TS_WIDTH] !== expected_period[ch]) begin
                        $display("ERROR: CH%0d period=%0d, expected=%0d, time=%0t",
                                 ch, period_ticks[ch*TS_WIDTH +: TS_WIDTH],
                                 expected_period[ch], $time);
                        errors = errors + 1;
                    end
                end

                if (high_valid[ch]) begin
                    high_count[ch] = high_count[ch] + 1;
                    if (high_ticks[ch*TS_WIDTH +: TS_WIDTH] !== expected_high[ch]) begin
                        $display("ERROR: CH%0d high=%0d, expected=%0d, time=%0t",
                                 ch, high_ticks[ch*TS_WIDTH +: TS_WIDTH],
                                 expected_high[ch], $time);
                        errors = errors + 1;
                    end
                end

                if (low_valid[ch]) begin
                    low_count[ch] = low_count[ch] + 1;
                    if (low_ticks[ch*TS_WIDTH +: TS_WIDTH] !== expected_low[ch]) begin
                        $display("ERROR: CH%0d low=%0d, expected=%0d, time=%0t",
                                 ch, low_ticks[ch*TS_WIDTH +: TS_WIDTH],
                                 expected_low[ch], $time);
                        errors = errors + 1;
                    end
                end
            end
        end
    end

    initial begin
        errors   = 0;
        rst_n    = 1'b0;
        async_ch = {CHANNELS{1'b0}};

        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
            period_count[ch]   = 0;
            high_count[ch]     = 0;
            low_count[ch]      = 0;
            expected_period[ch] = 1;
            expected_high[ch]   = 1;
            expected_low[ch]    = 1;
        end

        // 复位期间所有状态和输出必须为零。
        repeat (4) @(posedge clk);
        #1;
        if ((timestamp !== 0) || (period_valid !== 0) ||
            (high_valid !== 0) || (low_valid !== 0)) begin
            $display("ERROR: reset state is not zero");
            errors = errors + 1;
        end

        @(negedge clk);
        rst_n = 1'b1;

        // 三个通道以不同周期并行工作，CH3 保持静止。
        // CH0: 周期10、高4、低6；CH1: 周期17、高7、低10；
        // CH2: 周期7、高2、低5。
        expected_period[0] = 10;
        expected_high[0]   = 4;
        expected_low[0]    = 6;
        expected_period[1] = 17;
        expected_high[1]   = 7;
        expected_low[1]    = 10;
        expected_period[2] = 7;
        expected_high[2]   = 2;
        expected_low[2]    = 5;

        fork
            drive_pulse_train(0, 4,  6, 4);
            drive_pulse_train(1, 7, 10, 3);
            drive_pulse_train(2, 2,  5, 2);
        join

        repeat (10) @(posedge clk);
        #1;

        if ((period_count[0] != 3) || (high_count[0] != 4) || (low_count[0] != 3)) begin
            $display("ERROR: CH0 event counts P/H/L=%0d/%0d/%0d",
                     period_count[0], high_count[0], low_count[0]);
            errors = errors + 1;
        end
        if ((period_count[1] != 2) || (high_count[1] != 3) || (low_count[1] != 2)) begin
            $display("ERROR: CH1 event counts P/H/L=%0d/%0d/%0d",
                     period_count[1], high_count[1], low_count[1]);
            errors = errors + 1;
        end
        if ((period_count[2] != 1) || (high_count[2] != 2) || (low_count[2] != 1)) begin
            $display("ERROR: CH2 event counts P/H/L=%0d/%0d/%0d",
                     period_count[2], high_count[2], low_count[2]);
            errors = errors + 1;
        end
        if ((period_count[3] != 0) || (high_count[3] != 0) || (low_count[3] != 0)) begin
            $display("ERROR: inactive CH3 generated an event");
            errors = errors + 1;
        end

        // 数据产生后再次复位，验证测量值、有效脉冲和首次边沿历史被清除。
        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        if ((timestamp !== 0) || (period_ticks !== 0) ||
            (high_ticks !== 0) || (low_ticks !== 0) ||
            (period_valid !== 0) || (high_valid !== 0) || (low_valid !== 0)) begin
            $display("ERROR: runtime reset did not clear measurement state");
            errors = errors + 1;
        end

        @(negedge clk);
        rst_n = 1'b1;

        // 复位后只启动 CH3，验证通道独立性与首次上升沿不产生周期结果。
        expected_period[3] = 9;
        expected_high[3]   = 3;
        expected_low[3]    = 6;
        drive_pulse_train(3, 3, 6, 3);
        repeat (10) @(posedge clk);
        #1;

        if ((period_count[3] != 2) || (high_count[3] != 3) || (low_count[3] != 2)) begin
            $display("ERROR: CH3 event counts P/H/L=%0d/%0d/%0d",
                     period_count[3], high_count[3], low_count[3]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TEST PASSED: timing_measure_core self-check completed");
            $finish;
        end
        else begin
            $fatal(1, "TEST FAILED: %0d error(s)", errors);
        end
    end

    // 防止错误导致仿真永久运行。
    initial begin
        #100000;
        $fatal(1, "TEST FAILED: simulation timeout");
    end

endmodule
