`timescale 1ns / 1ps

// 第二阶段完整诊断顶层。复用既有 timing_diagnostic_core，新增周期诊断。
// 对外每通道 8 条事件 lane，lane=channel*8+(event_type-1)。
module timing_diagnostic_core_v2 #(
    parameter integer CHANNELS         = 4,
    parameter integer SYNC_STAGES      = 3,
    parameter integer TS_WIDTH         = 64,
    parameter integer CHANNEL_ID_WIDTH = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [CHANNELS-1:0]               async_ch,
    input  wire [CHANNELS-1:0]               clear_period_stats,
    input  wire [CHANNELS*TS_WIDTH-1:0]      min_high_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      min_low_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      timeout_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      period_min_limit,
    input  wire [CHANNELS*TS_WIDTH-1:0]      period_max_limit,
    input  wire [CHANNELS*TS_WIDTH-1:0]      reference_period,
    input  wire [CHANNELS*TS_WIDTH-1:0]      jump_limit_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      drift_limit_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      jitter_limit_ticks,

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
    output wire [CHANNELS*TS_WIDTH-1:0]      min_period,
    output wire [CHANNELS*TS_WIDTH-1:0]      max_period,
    output wire [CHANNELS*TS_WIDTH-1:0]      peak_to_peak_jitter,
    output wire [CHANNELS*TS_WIDTH-1:0]      adjacent_period_diff,
    output wire [CHANNELS-1:0]               period_stats_valid,

    output wire [CHANNELS*8-1:0]             event_valid,
    output wire [CHANNELS*8*CHANNEL_ID_WIDTH-1:0] event_channel,
    output wire [CHANNELS*8*8-1:0]           event_type,
    output wire [CHANNELS*8*TS_WIDTH-1:0]    event_timestamp,
    output wire [CHANNELS*8*TS_WIDTH-1:0]    event_value
);

    wire [CHANNELS*3-1:0]                     base_event_valid;
    wire [CHANNELS*3*CHANNEL_ID_WIDTH-1:0]    base_event_channel;
    wire [CHANNELS*3*8-1:0]                   base_event_type;
    wire [CHANNELS*3*TS_WIDTH-1:0]            base_event_timestamp;
    wire [CHANNELS*3*TS_WIDTH-1:0]            base_event_value;
    wire [CHANNELS*5-1:0]                     period_event_valid;
    wire [CHANNELS*5*CHANNEL_ID_WIDTH-1:0]    period_event_channel;
    wire [CHANNELS*5*8-1:0]                   period_event_type;
    wire [CHANNELS*5*TS_WIDTH-1:0]            period_event_timestamp;
    wire [CHANNELS*5*TS_WIDTH-1:0]            period_event_value;

    timing_diagnostic_core #(
        .CHANNELS        (CHANNELS),
        .SYNC_STAGES     (SYNC_STAGES),
        .TS_WIDTH        (TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH)
    ) u_timing_diagnostic_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .async_ch       (async_ch),
        .min_high_ticks (min_high_ticks),
        .min_low_ticks  (min_low_ticks),
        .timeout_ticks  (timeout_ticks),
        .timestamp      (timestamp),
        .sync_level     (sync_level),
        .rise_pulse     (rise_pulse),
        .fall_pulse     (fall_pulse),
        .period_ticks   (period_ticks),
        .high_ticks     (high_ticks),
        .low_ticks      (low_ticks),
        .period_valid   (period_valid),
        .high_valid     (high_valid),
        .low_valid      (low_valid),
        .event_valid    (base_event_valid),
        .event_channel  (base_event_channel),
        .event_type     (base_event_type),
        .event_timestamp(base_event_timestamp),
        .event_value    (base_event_value)
    );

    multi_channel_period_diagnostic #(
        .CHANNELS        (CHANNELS),
        .TS_WIDTH        (TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH)
    ) u_multi_channel_period_diagnostic (
        .clk                 (clk),
        .rst_n               (rst_n),
        .clear_stats         (clear_period_stats),
        .timestamp           (timestamp),
        .period_ticks        (period_ticks),
        .period_valid        (period_valid),
        .period_min_limit    (period_min_limit),
        .period_max_limit    (period_max_limit),
        .reference_period    (reference_period),
        .jump_limit_ticks    (jump_limit_ticks),
        .drift_limit_ticks   (drift_limit_ticks),
        .jitter_limit_ticks  (jitter_limit_ticks),
        .event_valid         (period_event_valid),
        .event_channel       (period_event_channel),
        .event_type          (period_event_type),
        .event_timestamp     (period_event_timestamp),
        .event_value         (period_event_value),
        .min_period          (min_period),
        .max_period          (max_period),
        .peak_to_peak_jitter (peak_to_peak_jitter),
        .adjacent_period_diff(adjacent_period_diff),
        .stats_valid         (period_stats_valid)
    );

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : gen_event_merge
            // 0x01～0x03 来自既有异常检测器。
            assign event_valid[ch*8 +: 3] = base_event_valid[ch*3 +: 3];
            assign event_channel[(ch*8)*CHANNEL_ID_WIDTH +: 3*CHANNEL_ID_WIDTH] =
                   base_event_channel[(ch*3)*CHANNEL_ID_WIDTH +: 3*CHANNEL_ID_WIDTH];
            assign event_type[(ch*8)*8 +: 3*8] = base_event_type[(ch*3)*8 +: 3*8];
            assign event_timestamp[(ch*8)*TS_WIDTH +: 3*TS_WIDTH] =
                   base_event_timestamp[(ch*3)*TS_WIDTH +: 3*TS_WIDTH];
            assign event_value[(ch*8)*TS_WIDTH +: 3*TS_WIDTH] =
                   base_event_value[(ch*3)*TS_WIDTH +: 3*TS_WIDTH];

            // 0x04～0x08 来自周期诊断器。
            assign event_valid[ch*8+3 +: 5] = period_event_valid[ch*5 +: 5];
            assign event_channel[(ch*8+3)*CHANNEL_ID_WIDTH +: 5*CHANNEL_ID_WIDTH] =
                   period_event_channel[(ch*5)*CHANNEL_ID_WIDTH +: 5*CHANNEL_ID_WIDTH];
            assign event_type[(ch*8+3)*8 +: 5*8] = period_event_type[(ch*5)*8 +: 5*8];
            assign event_timestamp[(ch*8+3)*TS_WIDTH +: 5*TS_WIDTH] =
                   period_event_timestamp[(ch*5)*TS_WIDTH +: 5*TS_WIDTH];
            assign event_value[(ch*8+3)*TS_WIDTH +: 5*TS_WIDTH] =
                   period_event_value[(ch*5)*TS_WIDTH +: 5*TS_WIDTH];
        end
    endgenerate

endmodule
