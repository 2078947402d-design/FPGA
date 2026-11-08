`timescale 1ns / 1ps

// 第一阶段测量核心与第二阶段异常检测器的非侵入式集成顶层。
// 现有 timing_measure_core 接口和测量语义保持不变。
module timing_diagnostic_core #(
    parameter integer CHANNELS         = 4,
    parameter integer SYNC_STAGES      = 3,
    parameter integer TS_WIDTH         = 64,
    parameter integer CHANNEL_ID_WIDTH = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [CHANNELS-1:0]               async_ch,
    input  wire [CHANNELS*TS_WIDTH-1:0]      min_high_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      min_low_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      timeout_ticks,

    output wire [TS_WIDTH-1:0]               timestamp,
    output wire [CHANNELS-1:0]               sync_level,
    output wire [CHANNELS-1:0]               rise_pulse,
    output wire [CHANNELS-1:0]               fall_pulse,
    output wire [CHANNELS*TS_WIDTH-1:0]      period_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]      high_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]      low_ticks,
    output wire [CHANNELS-1:0]               period_valid,
    output wire [CHANNELS-1:0]               high_valid,
    output wire [CHANNELS-1:0]               low_valid,

    output wire [CHANNELS*3-1:0]             event_valid,
    output wire [CHANNELS*3*CHANNEL_ID_WIDTH-1:0] event_channel,
    output wire [CHANNELS*3*8-1:0]           event_type,
    output wire [CHANNELS*3*TS_WIDTH-1:0]    event_timestamp,
    output wire [CHANNELS*3*TS_WIDTH-1:0]    event_value
);

    timing_measure_core #(
        .CHANNELS   (CHANNELS),
        .SYNC_STAGES(SYNC_STAGES),
        .TS_WIDTH   (TS_WIDTH)
    ) u_timing_measure_core (
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

    multi_channel_fault_detector #(
        .CHANNELS        (CHANNELS),
        .TS_WIDTH        (TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH)
    ) u_multi_channel_fault_detector (
        .clk            (clk),
        .rst_n          (rst_n),
        .timestamp      (timestamp),
        .rise_pulse     (rise_pulse),
        .high_ticks     (high_ticks),
        .high_valid     (high_valid),
        .low_ticks      (low_ticks),
        .low_valid      (low_valid),
        .min_high_ticks (min_high_ticks),
        .min_low_ticks  (min_low_ticks),
        .timeout_ticks  (timeout_ticks),
        .event_valid    (event_valid),
        .event_channel  (event_channel),
        .event_type     (event_type),
        .event_timestamp(event_timestamp),
        .event_value    (event_value)
    );

endmodule
