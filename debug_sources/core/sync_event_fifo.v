`timescale 1ns / 1ps

// 参数化同步、show-ahead FIFO。支持满状态下同拍 pop+push，持续吞吐为 1 条/拍。
module sync_event_fifo #(
    parameter integer DATA_WIDTH       = 133,
    parameter integer DEPTH            = 64,
    parameter integer DROP_COUNT_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        clear,

    input  wire                        write_valid,
    output wire                        write_ready,
    input  wire [DATA_WIDTH-1:0]       write_data,

    input  wire                        pop,
    output wire                        pop_ack,
    output wire [DATA_WIDTH-1:0]       head_data,
    output wire                        empty,
    output wire                        full,
    output wire [15:0]                 level,
    output reg                         overflow,
    output reg  [DROP_COUNT_WIDTH-1:0] dropped_count
);

    localparam integer PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer CNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    // 64x133 属于浅而宽的存储，7 系列器件上分布式 RAM 比强制占用多个 BRAM 更合适。
    // 存储体本身不复位；empty 时输出被屏蔽，清指针/计数即可完成逻辑清空。
    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [CNT_WIDTH-1:0] count;

    wire read_fire;
    wire write_fire;
    wire write_rejected;

    assign empty       = (count == 0);
    assign full        = (count == DEPTH);
    assign pop_ack     = pop && !empty;
    assign read_fire   = pop_ack;
    // 满时若同拍弹出，写端仍可接收，容量不会下降。
    assign write_ready = !full || read_fire;
    assign write_fire  = write_valid && write_ready;
    assign write_rejected = write_valid && !write_ready;
    assign head_data   = empty ? {DATA_WIDTH{1'b0}} : memory[read_ptr];
    assign level       = count;

    function [PTR_WIDTH-1:0] next_ptr;
        input [PTR_WIDTH-1:0] ptr;
        begin
            if (ptr == DEPTH-1)
                next_ptr = {PTR_WIDTH{1'b0}};
            else
                next_ptr = ptr + 1'b1;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr      <= {PTR_WIDTH{1'b0}};
            write_ptr     <= {PTR_WIDTH{1'b0}};
            count         <= {CNT_WIDTH{1'b0}};
            overflow      <= 1'b0;
            dropped_count <= {DROP_COUNT_WIDTH{1'b0}};
        end else if (clear) begin
            read_ptr      <= {PTR_WIDTH{1'b0}};
            write_ptr     <= {PTR_WIDTH{1'b0}};
            count         <= {CNT_WIDTH{1'b0}};
            overflow      <= 1'b0;
            dropped_count <= {DROP_COUNT_WIDTH{1'b0}};
        end else begin
            if (write_fire) begin
                write_ptr <= next_ptr(write_ptr);
            end
            if (read_fire)
                read_ptr <= next_ptr(read_ptr);

            case ({write_fire, read_fire})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase

            if (write_rejected) begin
                overflow <= 1'b1;
                if (dropped_count != {DROP_COUNT_WIDTH{1'b1}})
                    dropped_count <= dropped_count + 1'b1;
            end
        end
    end

    // 将存储写口从异步复位时序块中分离，允许 Vivado 推断 LUTRAM。
    always @(posedge clk) begin
        if (rst_n && !clear && write_fire)
            memory[write_ptr] <= write_data;
    end

    initial begin
        if (DEPTH < 2)
            $error("sync_event_fifo DEPTH must be at least 2");
    end

endmodule
