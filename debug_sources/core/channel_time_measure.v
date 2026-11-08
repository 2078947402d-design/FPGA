`timescale 1ns / 1ps

// 单通道时间测量单元。
// 所有减法均按无符号模 2^TS_WIDTH 运算；只要相邻事件间隔小于一个
// 完整计数器回绕周期，跨越一次回绕仍能得到正确差值。
module channel_time_measure #(
    parameter integer TS_WIDTH = 64
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [TS_WIDTH-1:0] timestamp,
    input  wire                rise_pulse,
    input  wire                fall_pulse,
    output reg  [TS_WIDTH-1:0] period_ticks,
    output reg  [TS_WIDTH-1:0] high_ticks,
    output reg  [TS_WIDTH-1:0] low_ticks,
    output reg                 period_valid,
    output reg                 high_valid,
    output reg                 low_valid
);

    reg [TS_WIDTH-1:0] last_rise_timestamp;
    reg [TS_WIDTH-1:0] last_fall_timestamp;
    reg                have_rise;
    reg                have_fall;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_rise_timestamp <= {TS_WIDTH{1'b0}};
            last_fall_timestamp <= {TS_WIDTH{1'b0}};
            period_ticks        <= {TS_WIDTH{1'b0}};
            high_ticks          <= {TS_WIDTH{1'b0}};
            low_ticks           <= {TS_WIDTH{1'b0}};
            have_rise           <= 1'b0;
            have_fall           <= 1'b0;
            period_valid        <= 1'b0;
            high_valid          <= 1'b0;
            low_valid           <= 1'b0;
        end
        else begin
            // valid 是单时钟脉冲，只在对应结果刚更新时有效。
            period_valid <= 1'b0;
            high_valid   <= 1'b0;
            low_valid    <= 1'b0;

            if (rise_pulse) begin
                if (have_rise) begin
                    period_ticks <= timestamp - last_rise_timestamp;
                    period_valid <= 1'b1;
                end

                if (have_fall) begin
                    low_ticks <= timestamp - last_fall_timestamp;
                    low_valid <= 1'b1;
                end

                last_rise_timestamp <= timestamp;
                have_rise           <= 1'b1;
            end

            if (fall_pulse) begin
                if (have_rise) begin
                    high_ticks <= timestamp - last_rise_timestamp;
                    high_valid <= 1'b1;
                end

                last_fall_timestamp <= timestamp;
                have_fall           <= 1'b1;
            end
        end
    end

endmodule
