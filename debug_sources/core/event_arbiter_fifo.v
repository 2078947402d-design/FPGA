`timescale 1ns / 1ps

// 4 通道 x 8 类型并行事件的固定优先级仲裁、每源临时缓存及同步事件 FIFO。
// lane = channel*EVENT_TYPES + event_type-1。
module event_arbiter_fifo #(
    parameter integer CHANNELS         = 4,
    parameter integer EVENT_TYPES      = 8,
    parameter integer TS_WIDTH         = 64,
    parameter integer CHANNEL_ID_WIDTH = 4,
    parameter integer FIFO_DEPTH       = 64,
    parameter integer DROP_COUNT_WIDTH = 32
) (
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  clear,
    input  wire [CHANNELS*EVENT_TYPES-1:0]       event_valid_in,
    input  wire [CHANNELS*EVENT_TYPES*TS_WIDTH-1:0] event_timestamp_in,
    input  wire [CHANNELS*EVENT_TYPES*TS_WIDTH-1:0] event_value_in,
    input  wire                                  event_pop,
    output wire                                  event_pop_ack,
    output wire                                  event_valid,
    output wire [CHANNEL_ID_WIDTH-1:0]           event_channel,
    output wire [7:0]                            event_type,
    output wire [TS_WIDTH-1:0]                   event_timestamp,
    output wire [TS_WIDTH-1:0]                   event_value,
    output wire                                  fifo_empty,
    output wire                                  fifo_full,
    output wire [15:0]                           fifo_level,
    output wire [15:0]                           pending_level,
    output wire                                  overflow,
    output wire [DROP_COUNT_WIDTH-1:0]           dropped_count
);

    localparam integer LANES        = CHANNELS * EVENT_TYPES;
    localparam integer LANE_WIDTH   = (LANES <= 2) ? 1 : $clog2(LANES);
    localparam integer RECORD_WIDTH = LANE_WIDTH + 2*TS_WIDTH;
    localparam integer PEND_WIDTH   = (LANES <= 1) ? 1 : $clog2(LANES+1);

    // 固定源固定槽：入口没有宽交叉开关。通道号和类型由 lane 推导，不重复存储。
    reg [LANES-1:0] pending_valid;
    reg [TS_WIDTH-1:0] pending_timestamp [0:LANES-1];
    reg [TS_WIDTH-1:0] pending_value [0:LANES-1];
    reg [PEND_WIDTH-1:0] pending_count;
    reg pending_overflow;
    reg [DROP_COUNT_WIDTH-1:0] pending_dropped_count;

    reg selected_valid;
    reg [LANE_WIDTH-1:0] selected_lane;
    reg [TS_WIDTH-1:0] selected_timestamp;
    reg [TS_WIDTH-1:0] selected_value;
    integer select_lane_index;
    integer capture_lane_index;
    integer payload_lane_index;
    integer new_slot_count;
    integer dropped_this_cycle;
    reg [DROP_COUNT_WIDTH:0] drop_sum;

    wire [RECORD_WIDTH-1:0] fifo_head_data;
    wire [RECORD_WIDTH-1:0] fifo_write_data;
    wire fifo_write_ready;
    wire fifo_transfer;
    wire fifo_overflow;
    wire [DROP_COUNT_WIDTH-1:0] fifo_dropped_count;
    wire [LANES-1:0] selected_onehot;

    // 最低 lane 优先：CH0/type1 到 CH3/type8。one-hot 编码避免宽旋转选择网络。
    assign selected_onehot = pending_valid & (~pending_valid + 1'b1);
    always @* begin
        selected_valid     = |pending_valid;
        selected_lane      = {LANE_WIDTH{1'b0}};
        selected_timestamp = {TS_WIDTH{1'b0}};
        selected_value     = {TS_WIDTH{1'b0}};
        for (select_lane_index=0; select_lane_index<LANES; select_lane_index=select_lane_index+1) begin
            selected_lane = selected_lane |
                            ({LANE_WIDTH{selected_onehot[select_lane_index]}} & select_lane_index[LANE_WIDTH-1:0]);
            selected_timestamp = selected_timestamp |
                                 ({TS_WIDTH{selected_onehot[select_lane_index]}} & pending_timestamp[select_lane_index]);
            selected_value = selected_value |
                             ({TS_WIDTH{selected_onehot[select_lane_index]}} & pending_value[select_lane_index]);
        end
    end

    assign fifo_write_data = {selected_lane, selected_timestamp, selected_value};
    assign fifo_transfer   = selected_valid && fifo_write_ready;
    assign pending_level   = pending_count;

    assign event_valid     = !fifo_empty;
    assign event_pop_ack   = event_pop && !fifo_empty;
    assign event_value     = fifo_empty ? {TS_WIDTH{1'b0}} : fifo_head_data[0 +: TS_WIDTH];
    assign event_timestamp = fifo_empty ? {TS_WIDTH{1'b0}} : fifo_head_data[TS_WIDTH +: TS_WIDTH];
    assign event_channel   = fifo_empty ? {CHANNEL_ID_WIDTH{1'b0}} :
                             fifo_head_data[2*TS_WIDTH +: LANE_WIDTH] / EVENT_TYPES;
    assign event_type      = fifo_empty ? 8'h00 :
                             (fifo_head_data[2*TS_WIDTH +: LANE_WIDTH] % EVENT_TYPES) + 1'b1;
    assign overflow        = pending_overflow | fifo_overflow;
    assign dropped_count   = (pending_dropped_count > ({DROP_COUNT_WIDTH{1'b1}} - fifo_dropped_count)) ?
                             {DROP_COUNT_WIDTH{1'b1}} :
                             pending_dropped_count + fifo_dropped_count;

    sync_event_fifo #(
        .DATA_WIDTH(RECORD_WIDTH), .DEPTH(FIFO_DEPTH), .DROP_COUNT_WIDTH(DROP_COUNT_WIDTH)
    ) u_event_fifo (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        // 只有 ready 时才向单写口提交；阻塞在 pending 槽中的记录不算丢失。
        .write_valid(fifo_transfer), .write_ready(fifo_write_ready),
        .write_data(fifo_write_data), .pop(event_pop), .pop_ack(),
        .head_data(fifo_head_data), .empty(fifo_empty), .full(fifo_full),
        .level(fifo_level), .overflow(fifo_overflow), .dropped_count(fifo_dropped_count)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_valid         <= {LANES{1'b0}};
            pending_count         <= {PEND_WIDTH{1'b0}};
            pending_overflow      <= 1'b0;
            pending_dropped_count <= {DROP_COUNT_WIDTH{1'b0}};
        end else if (clear) begin
            pending_valid         <= {LANES{1'b0}};
            pending_count         <= {PEND_WIDTH{1'b0}};
            pending_overflow      <= 1'b0;
            pending_dropped_count <= {DROP_COUNT_WIDTH{1'b0}};
        end else begin
            new_slot_count     = 0;
            dropped_this_cycle = 0;

            for (capture_lane_index=0; capture_lane_index<LANES; capture_lane_index=capture_lane_index+1) begin
                if (event_valid_in[capture_lane_index]) begin
                    if (!pending_valid[capture_lane_index]) begin
                        pending_valid[capture_lane_index] <= 1'b1;
                        new_slot_count = new_slot_count + 1;
                    end else if (fifo_transfer && selected_lane == capture_lane_index) begin
                        // 旧记录同拍离开，直接以新记录补位，支持单源持续 1 条/拍。
                        pending_valid[capture_lane_index] <= 1'b1;
                    end else begin
                        dropped_this_cycle = dropped_this_cycle + 1;
                    end
                end else if (fifo_transfer && selected_lane == capture_lane_index) begin
                    pending_valid[capture_lane_index] <= 1'b0;
                end
            end

            pending_count <= pending_count + new_slot_count -
                             (fifo_transfer && !event_valid_in[selected_lane]);

            if (dropped_this_cycle != 0) begin
                pending_overflow <= 1'b1;
                drop_sum = {1'b0,pending_dropped_count} + dropped_this_cycle;
                if (drop_sum[DROP_COUNT_WIDTH])
                    pending_dropped_count <= {DROP_COUNT_WIDTH{1'b1}};
                else
                    pending_dropped_count <= drop_sum[DROP_COUNT_WIDTH-1:0];
            end
        end
    end

    // 载荷寄存器无需复位；pending_valid=0 时内容无效。独立无异步复位写法避免额外控制集。
    always @(posedge clk) begin
        if (rst_n && !clear) begin
            for (payload_lane_index=0; payload_lane_index<LANES; payload_lane_index=payload_lane_index+1) begin
                if (event_valid_in[payload_lane_index] &&
                    (!pending_valid[payload_lane_index] || (fifo_transfer && selected_lane == payload_lane_index))) begin
                    pending_timestamp[payload_lane_index] <= event_timestamp_in[payload_lane_index*TS_WIDTH +: TS_WIDTH];
                    pending_value[payload_lane_index] <= event_value_in[payload_lane_index*TS_WIDTH +: TS_WIDTH];
                end
            end
        end
    end

endmodule
