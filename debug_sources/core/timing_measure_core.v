`timescale 1ns / 1ps

// 多通道时序测量核心（第一阶段）。
// 输出总线按通道展开：通道 n 位于 [n*TS_WIDTH +: TS_WIDTH]。
module timing_measure_core #(
    parameter integer CHANNELS    = 4,
    parameter integer SYNC_STAGES = 3,
    parameter integer TS_WIDTH    = 64
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [CHANNELS-1:0]          async_ch,
    output reg  [TS_WIDTH-1:0]          timestamp,
    output wire [CHANNELS-1:0]          sync_level,
    output wire [CHANNELS-1:0]          rise_pulse,
    output wire [CHANNELS-1:0]          fall_pulse,
    output wire [CHANNELS*TS_WIDTH-1:0] period_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0] high_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0] low_ticks,
    output wire [CHANNELS-1:0]          period_valid,
    output wire [CHANNELS-1:0]          high_valid,
    output wire [CHANNELS-1:0]          low_valid
);

    // 64 位自由运行全局时间戳。50 MHz 下量化间隔为 20 ns。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timestamp <= {TS_WIDTH{1'b0}};
        else
            timestamp <= timestamp + 1'b1;
    end

    input_sync_edge #(
        .CHANNELS   (CHANNELS),
        .SYNC_STAGES(SYNC_STAGES)
    ) u_input_sync_edge (
        .clk        (clk),
        .rst_n      (rst_n),
        .async_in   (async_ch),
        .sync_level (sync_level),
        .rise_pulse (rise_pulse),
        .fall_pulse (fall_pulse)
    );

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : gen_measure_channel
            channel_time_measure #(
                .TS_WIDTH(TS_WIDTH)
            ) u_channel_time_measure (
                .clk         (clk),
                .rst_n       (rst_n),
                .timestamp   (timestamp),
                .rise_pulse  (rise_pulse[ch]),
                .fall_pulse  (fall_pulse[ch]),
                .period_ticks(period_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .high_ticks  (high_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .low_ticks   (low_ticks[ch*TS_WIDTH +: TS_WIDTH]),
                .period_valid(period_valid[ch]),
                .high_valid  (high_valid[ch]),
                .low_valid   (low_valid[ch])
            );
        end
    endgenerate

endmodule
