`timescale 1ns / 1ps

// 多通道周期诊断封装，每通道 5 条独立事件 lane：
// +0 PERIOD_TOO_SHORT, +1 PERIOD_TOO_LONG, +2 PERIOD_JUMP,
// +3 FREQUENCY_DRIFT, +4 JITTER_EXCEEDED。
module multi_channel_period_diagnostic #(
    parameter integer CHANNELS         = 4,
    parameter integer TS_WIDTH         = 64,
    parameter integer CHANNEL_ID_WIDTH = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [CHANNELS-1:0]               clear_stats,
    input  wire [TS_WIDTH-1:0]               timestamp,
    input  wire [CHANNELS*TS_WIDTH-1:0]      period_ticks,
    input  wire [CHANNELS-1:0]               period_valid,
    input  wire [CHANNELS*TS_WIDTH-1:0]      period_min_limit,
    input  wire [CHANNELS*TS_WIDTH-1:0]      period_max_limit,
    input  wire [CHANNELS*TS_WIDTH-1:0]      reference_period,
    input  wire [CHANNELS*TS_WIDTH-1:0]      jump_limit_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      drift_limit_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      jitter_limit_ticks,

    output wire [CHANNELS*5-1:0]             event_valid,
    output wire [CHANNELS*5*CHANNEL_ID_WIDTH-1:0] event_channel,
    output wire [CHANNELS*5*8-1:0]           event_type,
    output wire [CHANNELS*5*TS_WIDTH-1:0]    event_timestamp,
    output wire [CHANNELS*5*TS_WIDTH-1:0]    event_value,
    output wire [CHANNELS*TS_WIDTH-1:0]      min_period,
    output wire [CHANNELS*TS_WIDTH-1:0]      max_period,
    output wire [CHANNELS*TS_WIDTH-1:0]      peak_to_peak_jitter,
    output wire [CHANNELS*TS_WIDTH-1:0]      adjacent_period_diff,
    output wire [CHANNELS-1:0]               stats_valid
);

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : gen_period_channel
            localparam integer LANE_BASE = ch * 5;
            localparam [CHANNEL_ID_WIDTH-1:0] CHANNEL_NUMBER = ch;

            wire [4:0]                 ch_event_valid;
            wire [5*TS_WIDTH-1:0]      ch_event_timestamp;
            wire [5*TS_WIDTH-1:0]      ch_event_value;

            channel_period_diagnostic #(
                .TS_WIDTH(TS_WIDTH)
            ) u_channel_period_diagnostic (
                .clk                       (clk),
                .rst_n                     (rst_n),
                .clear_stats               (clear_stats[ch]),
                .timestamp                 (timestamp),
                .period_ticks              (period_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .period_valid              (period_valid[ch]),
                .period_min_limit          (period_min_limit[ch*TS_WIDTH +: TS_WIDTH]),
                .period_max_limit          (period_max_limit[ch*TS_WIDTH +: TS_WIDTH]),
                .reference_period          (reference_period[ch*TS_WIDTH +: TS_WIDTH]),
                .jump_limit_ticks          (jump_limit_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .drift_limit_ticks         (drift_limit_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .jitter_limit_ticks        (jitter_limit_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .period_too_short_valid    (ch_event_valid[0]),
                .period_too_short_timestamp(ch_event_timestamp[0*TS_WIDTH +: TS_WIDTH]),
                .period_too_short_value    (ch_event_value[0*TS_WIDTH +: TS_WIDTH]),
                .period_too_long_valid     (ch_event_valid[1]),
                .period_too_long_timestamp (ch_event_timestamp[1*TS_WIDTH +: TS_WIDTH]),
                .period_too_long_value     (ch_event_value[1*TS_WIDTH +: TS_WIDTH]),
                .period_jump_valid         (ch_event_valid[2]),
                .period_jump_timestamp     (ch_event_timestamp[2*TS_WIDTH +: TS_WIDTH]),
                .period_jump_value         (ch_event_value[2*TS_WIDTH +: TS_WIDTH]),
                .frequency_drift_valid     (ch_event_valid[3]),
                .frequency_drift_timestamp (ch_event_timestamp[3*TS_WIDTH +: TS_WIDTH]),
                .frequency_drift_value     (ch_event_value[3*TS_WIDTH +: TS_WIDTH]),
                .jitter_exceeded_valid     (ch_event_valid[4]),
                .jitter_exceeded_timestamp (ch_event_timestamp[4*TS_WIDTH +: TS_WIDTH]),
                .jitter_exceeded_value     (ch_event_value[4*TS_WIDTH +: TS_WIDTH]),
                .min_period                (min_period[ch*TS_WIDTH +: TS_WIDTH]),
                .max_period                (max_period[ch*TS_WIDTH +: TS_WIDTH]),
                .peak_to_peak_jitter       (peak_to_peak_jitter[ch*TS_WIDTH +: TS_WIDTH]),
                .adjacent_period_diff      (adjacent_period_diff[ch*TS_WIDTH +: TS_WIDTH]),
                .stats_valid               (stats_valid[ch])
            );

            assign event_valid[LANE_BASE +: 5] = ch_event_valid;

            assign event_channel[(LANE_BASE+0)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;
            assign event_channel[(LANE_BASE+1)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;
            assign event_channel[(LANE_BASE+2)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;
            assign event_channel[(LANE_BASE+3)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;
            assign event_channel[(LANE_BASE+4)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;

            assign event_type[(LANE_BASE+0)*8 +: 8] = 8'h04;
            assign event_type[(LANE_BASE+1)*8 +: 8] = 8'h05;
            assign event_type[(LANE_BASE+2)*8 +: 8] = 8'h06;
            assign event_type[(LANE_BASE+3)*8 +: 8] = 8'h07;
            assign event_type[(LANE_BASE+4)*8 +: 8] = 8'h08;

            assign event_timestamp[LANE_BASE*TS_WIDTH +: 5*TS_WIDTH] = ch_event_timestamp;
            assign event_value[LANE_BASE*TS_WIDTH +: 5*TS_WIDTH] = ch_event_value;
        end
    endgenerate

endmodule
