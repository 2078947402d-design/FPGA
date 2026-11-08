`timescale 1ns / 1ps

// AXI 系统封装顶层：AXI4-Lite 寄存器层与已验证的 timing_diagnostic_core_v3
// 共用 s_axi_aclk/s_axi_aresetn，不引入内部 CDC。
module timing_diagnostic_axi_top #(
    parameter integer CHANNELS         = 4,
    parameter integer SYNC_STAGES      = 3,
    parameter integer TS_WIDTH         = 64,
    parameter integer CHANNEL_ID_WIDTH = 4,
    parameter integer FIFO_DEPTH       = 64,
    parameter integer AXI_ADDR_WIDTH    = 12
) (
    input  wire                           s_axi_aclk,
    input  wire                           s_axi_aresetn,
    input  wire [CHANNELS-1:0]            async_ch,

    input  wire [AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire [2:0]                     s_axi_awprot,
    input  wire                           s_axi_awvalid,
    output wire                           s_axi_awready,
    input  wire [31:0]                    s_axi_wdata,
    input  wire [3:0]                     s_axi_wstrb,
    input  wire                           s_axi_wvalid,
    output wire                           s_axi_wready,
    output wire [1:0]                     s_axi_bresp,
    output wire                           s_axi_bvalid,
    input  wire                           s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire [2:0]                     s_axi_arprot,
    input  wire                           s_axi_arvalid,
    output wire                           s_axi_arready,
    output wire [31:0]                    s_axi_rdata,
    output wire [1:0]                     s_axi_rresp,
    output wire                           s_axi_rvalid,
    input  wire                           s_axi_rready
);

    wire global_enable;
    wire [CHANNELS-1:0] channel_enable;
    wire [CHANNELS-1:0] enabled_mask;
    wire [CHANNELS-1:0] core_async_ch;
    wire [CHANNELS-1:0] clear_period_stats;
    wire clear_event_fifo;
    wire event_pop;

    wire [CHANNELS*TS_WIDTH-1:0] cfg_min_high;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_min_low;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_timeout;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_period_min;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_period_max;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_reference;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_jump;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_drift;
    wire [CHANNELS*TS_WIDTH-1:0] cfg_jitter;
    wire [CHANNELS*TS_WIDTH-1:0] effective_min_high;
    wire [CHANNELS*TS_WIDTH-1:0] effective_min_low;
    wire [CHANNELS*TS_WIDTH-1:0] effective_timeout;
    wire [CHANNELS*TS_WIDTH-1:0] effective_period_min;
    wire [CHANNELS*TS_WIDTH-1:0] effective_period_max;
    wire [CHANNELS*TS_WIDTH-1:0] effective_reference;
    wire [CHANNELS*TS_WIDTH-1:0] effective_jump;
    wire [CHANNELS*TS_WIDTH-1:0] effective_drift;
    wire [CHANNELS*TS_WIDTH-1:0] effective_jitter;

    wire [TS_WIDTH-1:0] timestamp;
    wire [CHANNELS-1:0] sync_level;
    wire [CHANNELS-1:0] rise_pulse;
    wire [CHANNELS-1:0] fall_pulse;
    wire [CHANNELS*TS_WIDTH-1:0] period_ticks;
    wire [CHANNELS*TS_WIDTH-1:0] high_ticks;
    wire [CHANNELS*TS_WIDTH-1:0] low_ticks;
    wire [CHANNELS-1:0] period_valid;
    wire [CHANNELS-1:0] high_valid;
    wire [CHANNELS-1:0] low_valid;
    wire [CHANNELS*TS_WIDTH-1:0] min_period;
    wire [CHANNELS*TS_WIDTH-1:0] max_period;
    wire [CHANNELS*TS_WIDTH-1:0] peak_to_peak_jitter;
    wire [CHANNELS*TS_WIDTH-1:0] adjacent_period_diff;
    wire [CHANNELS-1:0] period_stats_valid;
    wire fifo_event_valid;
    wire [CHANNEL_ID_WIDTH-1:0] fifo_event_channel;
    wire [7:0] fifo_event_type;
    wire [TS_WIDTH-1:0] fifo_event_timestamp;
    wire [TS_WIDTH-1:0] fifo_event_value;
    wire event_pop_ack;
    wire event_fifo_empty;
    wire event_fifo_full;
    wire [15:0] event_fifo_level;
    wire [15:0] event_pending_level;
    wire event_overflow;
    wire [31:0] event_dropped_count;

    assign enabled_mask = channel_enable & {CHANNELS{global_enable}};
    // 使能位控制诊断阈值，不切断原始测量链，避免启停时制造人工边沿。
    // 禁用期间仍可读取测量值和累计周期统计，但不会产生阈值类故障事件。
    assign core_async_ch = async_ch;

    genvar ch;
    generate
        for (ch=0; ch<CHANNELS; ch=ch+1) begin : gen_enable_gate
            assign effective_min_high[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_min_high[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_min_low[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_min_low[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_timeout[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_timeout[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_period_min[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_period_min[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_period_max[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_period_max[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_reference[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_reference[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_jump[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_jump[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_drift[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_drift[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
            assign effective_jitter[ch*TS_WIDTH +: TS_WIDTH] = enabled_mask[ch] ? cfg_jitter[ch*TS_WIDTH +: TS_WIDTH] : {TS_WIDTH{1'b0}};
        end
    endgenerate

    timing_diagnostic_core_v3 #(
        .CHANNELS(CHANNELS), .SYNC_STAGES(SYNC_STAGES), .TS_WIDTH(TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)
    ) u_core_v3 (
        .clk(s_axi_aclk), .rst_n(s_axi_aresetn), .async_ch(core_async_ch),
        .clear_period_stats(clear_period_stats), .clear_event_fifo(clear_event_fifo),
        .event_pop(event_pop), .min_high_ticks(effective_min_high),
        .min_low_ticks(effective_min_low), .timeout_ticks(effective_timeout),
        .period_min_limit(effective_period_min), .period_max_limit(effective_period_max),
        .reference_period(effective_reference), .jump_limit_ticks(effective_jump),
        .drift_limit_ticks(effective_drift), .jitter_limit_ticks(effective_jitter),
        .timestamp(timestamp), .sync_level(sync_level), .rise_pulse(rise_pulse),
        .fall_pulse(fall_pulse), .period_ticks(period_ticks), .high_ticks(high_ticks),
        .low_ticks(low_ticks), .period_valid(period_valid), .high_valid(high_valid),
        .low_valid(low_valid), .min_period(min_period), .max_period(max_period),
        .peak_to_peak_jitter(peak_to_peak_jitter),
        .adjacent_period_diff(adjacent_period_diff), .period_stats_valid(period_stats_valid),
        .fifo_event_valid(fifo_event_valid), .fifo_event_channel(fifo_event_channel),
        .fifo_event_type(fifo_event_type), .fifo_event_timestamp(fifo_event_timestamp),
        .fifo_event_value(fifo_event_value), .event_pop_ack(event_pop_ack),
        .event_fifo_empty(event_fifo_empty), .event_fifo_full(event_fifo_full),
        .event_fifo_level(event_fifo_level), .event_pending_level(event_pending_level),
        .event_overflow(event_overflow), .event_dropped_count(event_dropped_count)
    );

    timing_diagnostic_axi_regs #(
        .CHANNELS(CHANNELS), .TS_WIDTH(TS_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) u_axi_regs (
        .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .core_timestamp(timestamp), .core_sync_level(sync_level),
        .core_period_ticks(period_ticks), .core_high_ticks(high_ticks), .core_low_ticks(low_ticks),
        .core_period_valid(period_valid), .core_high_valid(high_valid), .core_low_valid(low_valid),
        .core_min_period(min_period), .core_max_period(max_period),
        .core_peak_to_peak(peak_to_peak_jitter), .core_stats_valid(period_stats_valid),
        .fifo_event_valid(fifo_event_valid), .fifo_event_channel(fifo_event_channel),
        .fifo_event_type(fifo_event_type), .fifo_event_timestamp(fifo_event_timestamp),
        .fifo_event_value(fifo_event_value), .event_pop_ack(event_pop_ack),
        .event_fifo_empty(event_fifo_empty), .event_fifo_full(event_fifo_full),
        .event_fifo_level(event_fifo_level), .event_pending_level(event_pending_level),
        .event_overflow(event_overflow), .event_dropped_count(event_dropped_count),
        .global_enable(global_enable), .channel_enable(channel_enable),
        .clear_period_stats(clear_period_stats), .clear_event_fifo(clear_event_fifo),
        .event_pop(event_pop), .min_high_ticks(cfg_min_high), .min_low_ticks(cfg_min_low),
        .timeout_ticks(cfg_timeout), .period_min_limit(cfg_period_min),
        .period_max_limit(cfg_period_max), .reference_period(cfg_reference),
        .jump_limit_ticks(cfg_jump), .drift_limit_ticks(cfg_drift),
        .jitter_limit_ticks(cfg_jitter)
    );

endmodule
