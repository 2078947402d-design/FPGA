`timescale 1ns / 1ps

// 多通道异步输入同步与边沿检测。
// SYNC_STAGES 必须不小于 2；默认使用三级同步以提高亚稳态传播余量。
module input_sync_edge #(
    parameter integer CHANNELS    = 4,
    parameter integer SYNC_STAGES = 3
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [CHANNELS-1:0] async_in,
    output wire [CHANNELS-1:0] sync_level,
    output wire [CHANNELS-1:0] rise_pulse,
    output wire [CHANNELS-1:0] fall_pulse
);

    // 复位释放后等待同步链和历史采样值全部稳定，避免把初始高电平
    // 错误解释为一个真实上升沿。
    reg [SYNC_STAGES:0] warmup_shift;
    wire                 edge_detect_enable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            warmup_shift <= {(SYNC_STAGES + 1){1'b0}};
        else
            warmup_shift <= {warmup_shift[SYNC_STAGES-1:0], 1'b1};
    end

    assign edge_detect_enable = warmup_shift[SYNC_STAGES];

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : gen_input_sync
            // 告知综合与实现工具：这些寄存器构成异步输入同步链。
            (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
            reg [SYNC_STAGES-1:0] sync_ff;
            reg                   sync_level_d;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff      <= {SYNC_STAGES{1'b0}};
                    sync_level_d <= 1'b0;
                end
                else begin
                    sync_ff      <= {sync_ff[SYNC_STAGES-2:0], async_in[ch]};
                    sync_level_d <= sync_ff[SYNC_STAGES-1];
                end
            end

            assign sync_level[ch] = sync_ff[SYNC_STAGES-1];
            assign rise_pulse[ch] = edge_detect_enable &
                                    sync_ff[SYNC_STAGES-1] & ~sync_level_d;
            assign fall_pulse[ch] = edge_detect_enable &
                                   ~sync_ff[SYNC_STAGES-1] &  sync_level_d;
        end
    endgenerate

endmodule
