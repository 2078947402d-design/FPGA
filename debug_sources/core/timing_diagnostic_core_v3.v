`timescale 1ns / 1ps

// 第三阶段无侵入集成顶层：保留 v2 实例及其全部测量功能，在其事件 lane 后增加仲裁/FIFO。
module timing_diagnostic_core_v3 #(
    parameter integer CHANNELS         = 4,
    parameter integer SYNC_STAGES      = 3,
    parameter integer TS_WIDTH         = 64,
    parameter integer CHANNEL_ID_WIDTH = 4,
    parameter integer FIFO_DEPTH       = 64
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [CHANNELS-1:0]               async_ch,
    input  wire [CHANNELS-1:0]               clear_period_stats,
    input  wire                              clear_event_fifo,
    input  wire                              event_pop,
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

    output wire                              fifo_event_valid,
    output wire [CHANNEL_ID_WIDTH-1:0]       fifo_event_channel,
    output wire [7:0]                        fifo_event_type,
    output wire [TS_WIDTH-1:0]               fifo_event_timestamp,
    output wire [TS_WIDTH-1:0]               fifo_event_value,
    output wire                              event_pop_ack,
    output wire                              event_fifo_empty,
    output wire                              event_fifo_full,
    output wire [15:0]                       event_fifo_level,
    output wire [15:0]                       event_pending_level,
    output wire                              event_overflow,
    output wire [31:0]                       event_dropped_count
);

    localparam integer LANES = CHANNELS * 8;
    wire [LANES-1:0] event_lane_valid;
    wire [LANES*CHANNEL_ID_WIDTH-1:0] event_lane_channel;
    wire [LANES*8-1:0] event_lane_type;
    wire [LANES*TS_WIDTH-1:0] event_lane_timestamp;
    wire [LANES*TS_WIDTH-1:0] event_lane_value;

    timing_diagnostic_core_v2 #(
        .CHANNELS        (CHANNELS),
        .SYNC_STAGES     (SYNC_STAGES),
        .TS_WIDTH        (TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH)
    ) u_timing_diagnostic_core_v2 (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .async_ch               (async_ch),
        .clear_period_stats     (clear_period_stats),
        .min_high_ticks         (min_high_ticks),
        .min_low_ticks          (min_low_ticks),
        .timeout_ticks          (timeout_ticks),
        .period_min_limit       (period_min_limit),
        .period_max_limit       (period_max_limit),
        .reference_period       (reference_period),
        .jump_limit_ticks       (jump_limit_ticks),
        .drift_limit_ticks      (drift_limit_ticks),
        .jitter_limit_ticks     (jitter_limit_ticks),
        .timestamp              (timestamp),
        .sync_level             (sync_level),
        .rise_pulse             (rise_pulse),
        .fall_pulse             (fall_pulse),
        .period_ticks           (period_ticks),
        .high_ticks             (high_ticks),
        .low_ticks              (low_ticks),
        .period_valid           (period_valid),
        .high_valid             (high_valid),
        .low_valid              (low_valid),
        .min_period             (min_period),
        .max_period             (max_period),
        .peak_to_peak_jitter    (peak_to_peak_jitter),
        .adjacent_period_diff   (adjacent_period_diff),
        .period_stats_valid     (period_stats_valid),
        .event_valid            (event_lane_valid),
        .event_channel          (event_lane_channel),
        .event_type             (event_lane_type),
        .event_timestamp        (event_lane_timestamp),
        .event_value            (event_lane_value)
    );

    // lane 已由 v2 固定定义，通道/类型不重复写入缓存；上方两条常量元数据总线仅作接口兼容。
    event_arbiter_fifo #(
        .CHANNELS        (CHANNELS),
        .EVENT_TYPES     (8),
        .TS_WIDTH        (TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH),
        .FIFO_DEPTH      (FIFO_DEPTH),
        .DROP_COUNT_WIDTH(32)
    ) u_event_arbiter_fifo (
        .clk               (clk),
        .rst_n             (rst_n),
        .clear             (clear_event_fifo),
        .event_valid_in    (event_lane_valid),
        .event_timestamp_in(event_lane_timestamp),
        .event_value_in    (event_lane_value),
        .event_pop         (event_pop),
        .event_pop_ack     (event_pop_ack),
        .event_valid       (fifo_event_valid),
        .event_channel     (fifo_event_channel),
        .event_type        (fifo_event_type),
        .event_timestamp   (fifo_event_timestamp),
        .event_value       (fifo_event_value),
        .fifo_empty        (event_fifo_empty),
        .fifo_full         (event_fifo_full),
        .fifo_level        (event_fifo_level),
        .pending_level     (event_pending_level),
        .overflow          (event_overflow),
        .dropped_count     (event_dropped_count)
    );

endmodule
