`timescale 1ns / 1ps

// 多通道异常检测封装。
// 每通道固定提供 3 条独立事件源，便于后续事件仲裁器/FIFO 接入：
// lane = channel*3+0：SHORT_HIGH；+1：SHORT_LOW；+2：PULSE_TIMEOUT。
// 所有事件字段均按 lane 展开，不在本模块内仲裁，因此同拍事件不会丢失。
module multi_channel_fault_detector #(
    parameter integer CHANNELS        = 4,
    parameter integer TS_WIDTH        = 64,
    parameter integer CHANNEL_ID_WIDTH = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [TS_WIDTH-1:0]               timestamp,
    input  wire [CHANNELS-1:0]               rise_pulse,
    input  wire [CHANNELS*TS_WIDTH-1:0]      high_ticks,
    input  wire [CHANNELS-1:0]               high_valid,
    input  wire [CHANNELS*TS_WIDTH-1:0]      low_ticks,
    input  wire [CHANNELS-1:0]               low_valid,
    input  wire [CHANNELS*TS_WIDTH-1:0]      min_high_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      min_low_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]      timeout_ticks,

    output wire [CHANNELS*3-1:0]             event_valid,
    output wire [CHANNELS*3*CHANNEL_ID_WIDTH-1:0] event_channel,
    output wire [CHANNELS*3*8-1:0]           event_type,
    output wire [CHANNELS*3*TS_WIDTH-1:0]    event_timestamp,
    output wire [CHANNELS*3*TS_WIDTH-1:0]    event_value
);

    localparam [7:0] EVENT_SHORT_HIGH   = 8'h01;
    localparam [7:0] EVENT_SHORT_LOW    = 8'h02;
    localparam [7:0] EVENT_PULSE_TIMEOUT = 8'h03;

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : gen_fault_channel
            localparam integer LANE_BASE = ch * 3;
            localparam [CHANNEL_ID_WIDTH-1:0] CHANNEL_NUMBER = ch;

            wire                 short_high_valid;
            wire [TS_WIDTH-1:0]  short_high_timestamp;
            wire [TS_WIDTH-1:0]  short_high_value;
            wire                 short_low_valid;
            wire [TS_WIDTH-1:0]  short_low_timestamp;
            wire [TS_WIDTH-1:0]  short_low_value;
            wire                 timeout_valid;
            wire [TS_WIDTH-1:0]  timeout_timestamp;
            wire [TS_WIDTH-1:0]  timeout_value;

            channel_fault_detector #(
                .TS_WIDTH(TS_WIDTH)
            ) u_channel_fault_detector (
                .clk                 (clk),
                .rst_n               (rst_n),
                .timestamp           (timestamp),
                .rise_pulse          (rise_pulse[ch]),
                .high_ticks          (high_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .high_valid          (high_valid[ch]),
                .low_ticks           (low_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .low_valid           (low_valid[ch]),
                .min_high_ticks      (min_high_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .min_low_ticks       (min_low_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .timeout_ticks       (timeout_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .short_high_valid    (short_high_valid),
                .short_high_timestamp(short_high_timestamp),
                .short_high_value    (short_high_value),
                .short_low_valid     (short_low_valid),
                .short_low_timestamp (short_low_timestamp),
                .short_low_value     (short_low_value),
                .timeout_valid       (timeout_valid),
                .timeout_timestamp   (timeout_timestamp),
                .timeout_value       (timeout_value)
            );

            assign event_valid[LANE_BASE+0] = short_high_valid;
            assign event_valid[LANE_BASE+1] = short_low_valid;
            assign event_valid[LANE_BASE+2] = timeout_valid;

            assign event_channel[(LANE_BASE+0)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;
            assign event_channel[(LANE_BASE+1)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;
            assign event_channel[(LANE_BASE+2)*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH] = CHANNEL_NUMBER;

            assign event_type[(LANE_BASE+0)*8 +: 8] = EVENT_SHORT_HIGH;
            assign event_type[(LANE_BASE+1)*8 +: 8] = EVENT_SHORT_LOW;
            assign event_type[(LANE_BASE+2)*8 +: 8] = EVENT_PULSE_TIMEOUT;

            assign event_timestamp[(LANE_BASE+0)*TS_WIDTH +: TS_WIDTH] = short_high_timestamp;
            assign event_timestamp[(LANE_BASE+1)*TS_WIDTH +: TS_WIDTH] = short_low_timestamp;
            assign event_timestamp[(LANE_BASE+2)*TS_WIDTH +: TS_WIDTH] = timeout_timestamp;

            assign event_value[(LANE_BASE+0)*TS_WIDTH +: TS_WIDTH] = short_high_value;
            assign event_value[(LANE_BASE+1)*TS_WIDTH +: TS_WIDTH] = short_low_value;
            assign event_value[(LANE_BASE+2)*TS_WIDTH +: TS_WIDTH] = timeout_value;
        end
    endgenerate

endmodule
