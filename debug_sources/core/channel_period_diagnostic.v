`timescale 1ns / 1ps

// 单通道周期异常、频率漂移与抖动诊断。
// period_valid/period_ticks 直接连接 channel_time_measure 的寄存输出。
// 所有阈值均为 0 时关闭对应报警；统计功能不因阈值为 0 而停止。
module channel_period_diagnostic #(
    parameter integer TS_WIDTH = 64
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                clear_stats,
    input  wire [TS_WIDTH-1:0] timestamp,
    input  wire [TS_WIDTH-1:0] period_ticks,
    input  wire                period_valid,
    input  wire [TS_WIDTH-1:0] period_min_limit,
    input  wire [TS_WIDTH-1:0] period_max_limit,
    input  wire [TS_WIDTH-1:0] reference_period,
    input  wire [TS_WIDTH-1:0] jump_limit_ticks,
    input  wire [TS_WIDTH-1:0] drift_limit_ticks,
    input  wire [TS_WIDTH-1:0] jitter_limit_ticks,

    output reg                 period_too_short_valid,
    output reg  [TS_WIDTH-1:0] period_too_short_timestamp,
    output reg  [TS_WIDTH-1:0] period_too_short_value,
    output reg                 period_too_long_valid,
    output reg  [TS_WIDTH-1:0] period_too_long_timestamp,
    output reg  [TS_WIDTH-1:0] period_too_long_value,
    output reg                 period_jump_valid,
    output reg  [TS_WIDTH-1:0] period_jump_timestamp,
    output reg  [TS_WIDTH-1:0] period_jump_value,
    output reg                 frequency_drift_valid,
    output reg  [TS_WIDTH-1:0] frequency_drift_timestamp,
    output reg  [TS_WIDTH-1:0] frequency_drift_value,
    output reg                 jitter_exceeded_valid,
    output reg  [TS_WIDTH-1:0] jitter_exceeded_timestamp,
    output reg  [TS_WIDTH-1:0] jitter_exceeded_value,

    output reg  [TS_WIDTH-1:0] min_period,
    output reg  [TS_WIDTH-1:0] max_period,
    output reg  [TS_WIDTH-1:0] peak_to_peak_jitter,
    output reg  [TS_WIDTH-1:0] adjacent_period_diff,
    output reg                 stats_valid
);

    reg [TS_WIDTH-1:0] previous_period;
    reg                have_previous_period;
    reg                jitter_reported;

    wire [TS_WIDTH-1:0] measurement_timestamp;
    wire [TS_WIDTH-1:0] adjacent_diff_calc;
    wire [TS_WIDTH-1:0] drift_diff_calc;
    wire [TS_WIDTH-1:0] candidate_min_period;
    wire [TS_WIDTH-1:0] candidate_max_period;
    wire [TS_WIDTH-1:0] candidate_peak_to_peak;

    // period_valid 在测量边沿后一拍被本模块采样，因此事件时间为 timestamp-1。
    assign measurement_timestamp = timestamp - 1'b1;

    assign adjacent_diff_calc = (period_ticks >= previous_period) ?
                                (period_ticks - previous_period) :
                                (previous_period - period_ticks);

    assign drift_diff_calc = (period_ticks >= reference_period) ?
                             (period_ticks - reference_period) :
                             (reference_period - period_ticks);

    assign candidate_min_period = !stats_valid ? period_ticks :
                                  ((period_ticks < min_period) ? period_ticks : min_period);
    assign candidate_max_period = !stats_valid ? period_ticks :
                                  ((period_ticks > max_period) ? period_ticks : max_period);
    assign candidate_peak_to_peak = candidate_max_period - candidate_min_period;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_period               <= {TS_WIDTH{1'b0}};
            have_previous_period          <= 1'b0;
            jitter_reported               <= 1'b0;
            min_period                    <= {TS_WIDTH{1'b0}};
            max_period                    <= {TS_WIDTH{1'b0}};
            peak_to_peak_jitter           <= {TS_WIDTH{1'b0}};
            adjacent_period_diff          <= {TS_WIDTH{1'b0}};
            stats_valid                   <= 1'b0;
            period_too_short_valid        <= 1'b0;
            period_too_short_timestamp    <= {TS_WIDTH{1'b0}};
            period_too_short_value        <= {TS_WIDTH{1'b0}};
            period_too_long_valid         <= 1'b0;
            period_too_long_timestamp     <= {TS_WIDTH{1'b0}};
            period_too_long_value         <= {TS_WIDTH{1'b0}};
            period_jump_valid             <= 1'b0;
            period_jump_timestamp         <= {TS_WIDTH{1'b0}};
            period_jump_value             <= {TS_WIDTH{1'b0}};
            frequency_drift_valid         <= 1'b0;
            frequency_drift_timestamp     <= {TS_WIDTH{1'b0}};
            frequency_drift_value         <= {TS_WIDTH{1'b0}};
            jitter_exceeded_valid         <= 1'b0;
            jitter_exceeded_timestamp     <= {TS_WIDTH{1'b0}};
            jitter_exceeded_value         <= {TS_WIDTH{1'b0}};
        end
        else begin
            period_too_short_valid <= 1'b0;
            period_too_long_valid  <= 1'b0;
            period_jump_valid      <= 1'b0;
            frequency_drift_valid  <= 1'b0;
            jitter_exceeded_valid  <= 1'b0;

            // 清统计优先于同拍新周期，便于未来 AXI W1P 命令得到确定行为。
            if (clear_stats) begin
                previous_period      <= {TS_WIDTH{1'b0}};
                have_previous_period <= 1'b0;
                jitter_reported      <= 1'b0;
                min_period           <= {TS_WIDTH{1'b0}};
                max_period           <= {TS_WIDTH{1'b0}};
                peak_to_peak_jitter  <= {TS_WIDTH{1'b0}};
                adjacent_period_diff <= {TS_WIDTH{1'b0}};
                stats_valid          <= 1'b0;
            end
            else if (period_valid) begin
                // 周期上下限：严格越界才报警，等于边界合法。
                if ((period_min_limit != {TS_WIDTH{1'b0}}) &&
                    (period_ticks < period_min_limit)) begin
                    period_too_short_valid     <= 1'b1;
                    period_too_short_timestamp <= measurement_timestamp;
                    period_too_short_value     <= period_ticks;
                end

                if ((period_max_limit != {TS_WIDTH{1'b0}}) &&
                    (period_ticks > period_max_limit)) begin
                    period_too_long_valid     <= 1'b1;
                    period_too_long_timestamp <= measurement_timestamp;
                    period_too_long_value     <= period_ticks;
                end

                // 第一个有效周期只建立 previous_period，不做相邻突变判断。
                if (have_previous_period) begin
                    adjacent_period_diff <= adjacent_diff_calc;
                    if ((jump_limit_ticks != {TS_WIDTH{1'b0}}) &&
                        (adjacent_diff_calc > jump_limit_ticks)) begin
                        period_jump_valid     <= 1'b1;
                        period_jump_timestamp <= measurement_timestamp;
                        period_jump_value     <= adjacent_diff_calc;
                    end
                end
                else begin
                    adjacent_period_diff <= {TS_WIDTH{1'b0}};
                end

                // reference_period=0 或 drift_limit=0 均表示漂移检测关闭。
                if ((reference_period != {TS_WIDTH{1'b0}}) &&
                    (drift_limit_ticks != {TS_WIDTH{1'b0}}) &&
                    (drift_diff_calc > drift_limit_ticks)) begin
                    frequency_drift_valid     <= 1'b1;
                    frequency_drift_timestamp <= measurement_timestamp;
                    frequency_drift_value     <= drift_diff_calc;
                end

                min_period           <= candidate_min_period;
                max_period           <= candidate_max_period;
                peak_to_peak_jitter  <= candidate_peak_to_peak;
                stats_valid          <= 1'b1;
                previous_period      <= period_ticks;
                have_previous_period <= 1'b1;

                // 最终抖动判据：当前统计窗口峰峰值严格大于阈值。
                // 每个统计窗口最多报告一次；clear_stats 开始新窗口。
                if (stats_valid && (jitter_limit_ticks != {TS_WIDTH{1'b0}})) begin
                    if (candidate_peak_to_peak > jitter_limit_ticks) begin
                        if (!jitter_reported) begin
                            jitter_exceeded_valid     <= 1'b1;
                            jitter_exceeded_timestamp <= measurement_timestamp;
                            jitter_exceeded_value     <= candidate_peak_to_peak;
                        end
                        jitter_reported <= 1'b1;
                    end
                    else begin
                        // 支持阈值动态调大后重新武装。
                        jitter_reported <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
