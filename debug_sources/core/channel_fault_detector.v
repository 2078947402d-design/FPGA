`timescale 1ns / 1ps

// 单通道毛刺与丢脉冲检测器。
//
// 接口时序约定：
// 1. rise_pulse 与 timestamp 同拍，表示当前 timestamp 处捕获到上升沿；
// 2. high_valid/low_valid 及测量值来自 channel_time_measure；
// 3. 由于测量模块使用寄存输出，检测器看到 valid 时，完成该次测量的
//    边沿时间戳为 timestamp-1。此约定保持第一阶段测量语义不变。
//
// 判定边界：毛刺使用“测量值 < 阈值”，超时使用“间隔 > 阈值”；
// 等于阈值均不报警，阈值为 0 时关闭对应检测。
module channel_fault_detector #(
    parameter integer TS_WIDTH = 64
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [TS_WIDTH-1:0] timestamp,
    input  wire                rise_pulse,
    input  wire [TS_WIDTH-1:0] high_ticks,
    input  wire                high_valid,
    input  wire [TS_WIDTH-1:0] low_ticks,
    input  wire                low_valid,
    input  wire [TS_WIDTH-1:0] min_high_ticks,
    input  wire [TS_WIDTH-1:0] min_low_ticks,
    input  wire [TS_WIDTH-1:0] timeout_ticks,

    output reg                 short_high_valid,
    output reg  [TS_WIDTH-1:0] short_high_timestamp,
    output reg  [TS_WIDTH-1:0] short_high_value,
    output reg                 short_low_valid,
    output reg  [TS_WIDTH-1:0] short_low_timestamp,
    output reg  [TS_WIDTH-1:0] short_low_value,
    output reg                 timeout_valid,
    output reg  [TS_WIDTH-1:0] timeout_timestamp,
    output reg  [TS_WIDTH-1:0] timeout_value
);

    reg [TS_WIDTH-1:0] last_rise_timestamp;
    reg                have_rise;
    reg                timeout_reported;

    wire [TS_WIDTH-1:0] elapsed_since_rise;
    wire [TS_WIDTH-1:0] measurement_timestamp;

    // 无符号模 2^TS_WIDTH 减法天然支持一次时间戳回绕。
    assign elapsed_since_rise   = timestamp - last_rise_timestamp;
    assign measurement_timestamp = timestamp - 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_rise_timestamp  <= {TS_WIDTH{1'b0}};
            have_rise            <= 1'b0;
            timeout_reported     <= 1'b0;
            short_high_valid     <= 1'b0;
            short_high_timestamp <= {TS_WIDTH{1'b0}};
            short_high_value     <= {TS_WIDTH{1'b0}};
            short_low_valid      <= 1'b0;
            short_low_timestamp  <= {TS_WIDTH{1'b0}};
            short_low_value      <= {TS_WIDTH{1'b0}};
            timeout_valid        <= 1'b0;
            timeout_timestamp    <= {TS_WIDTH{1'b0}};
            timeout_value        <= {TS_WIDTH{1'b0}};
        end
        else begin
            short_high_valid <= 1'b0;
            short_low_valid  <= 1'b0;
            timeout_valid    <= 1'b0;

            if (high_valid && (min_high_ticks != {TS_WIDTH{1'b0}}) &&
                (high_ticks < min_high_ticks)) begin
                short_high_valid     <= 1'b1;
                short_high_timestamp <= measurement_timestamp;
                short_high_value     <= high_ticks;
            end

            if (low_valid && (min_low_ticks != {TS_WIDTH{1'b0}}) &&
                (low_ticks < min_low_ticks)) begin
                short_low_valid     <= 1'b1;
                short_low_timestamp <= measurement_timestamp;
                short_low_value     <= low_ticks;
            end

            // 新上升沿优先于超时判定：它既建立/更新历史，也表示信号恢复。
            if (rise_pulse) begin
                last_rise_timestamp <= timestamp;
                have_rise           <= 1'b1;
                timeout_reported    <= 1'b0;
            end
            else if ((timeout_ticks != {TS_WIDTH{1'b0}}) &&
                     have_rise && !timeout_reported &&
                     (elapsed_since_rise > timeout_ticks)) begin
                timeout_valid     <= 1'b1;
                timeout_timestamp <= timestamp;
                timeout_value     <= elapsed_since_rise;
                timeout_reported  <= 1'b1;
            end
        end
    end

endmodule
