`timescale 1ns / 1ps

// 第四阶段 AXI4-Lite 寄存器层。
// AXI 与测量核心使用同一时钟域；本模块只提供寄存器、快照和单拍命令，
// 不改变 timing_diagnostic_core_v3 及其下级模块。
module timing_diagnostic_axi_regs #(
    parameter integer CHANNELS       = 4,
    parameter integer TS_WIDTH       = 64,
    parameter integer AXI_ADDR_WIDTH = 12,
    parameter [31:0]  SAMPLE_FREQ_HZ = 32'd50_000_000
) (
    input  wire                           s_axi_aclk,
    input  wire                           s_axi_aresetn,

    input  wire [AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire [2:0]                     s_axi_awprot,
    input  wire                           s_axi_awvalid,
    output wire                           s_axi_awready,
    input  wire [31:0]                    s_axi_wdata,
    input  wire [3:0]                     s_axi_wstrb,
    input  wire                           s_axi_wvalid,
    output wire                           s_axi_wready,
    output reg  [1:0]                     s_axi_bresp,
    output reg                            s_axi_bvalid,
    input  wire                           s_axi_bready,

    input  wire [AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire [2:0]                     s_axi_arprot,
    input  wire                           s_axi_arvalid,
    output wire                           s_axi_arready,
    output reg  [31:0]                    s_axi_rdata,
    output reg  [1:0]                     s_axi_rresp,
    output reg                            s_axi_rvalid,
    input  wire                           s_axi_rready,

    input  wire [TS_WIDTH-1:0]            core_timestamp,
    input  wire [CHANNELS-1:0]            core_sync_level,
    input  wire [CHANNELS*TS_WIDTH-1:0]   core_period_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]   core_high_ticks,
    input  wire [CHANNELS*TS_WIDTH-1:0]   core_low_ticks,
    input  wire [CHANNELS-1:0]            core_period_valid,
    input  wire [CHANNELS-1:0]            core_high_valid,
    input  wire [CHANNELS-1:0]            core_low_valid,
    input  wire [CHANNELS*TS_WIDTH-1:0]   core_min_period,
    input  wire [CHANNELS*TS_WIDTH-1:0]   core_max_period,
    input  wire [CHANNELS*TS_WIDTH-1:0]   core_peak_to_peak,
    input  wire [CHANNELS-1:0]            core_stats_valid,

    input  wire                           fifo_event_valid,
    input  wire [3:0]                     fifo_event_channel,
    input  wire [7:0]                     fifo_event_type,
    input  wire [TS_WIDTH-1:0]            fifo_event_timestamp,
    input  wire [TS_WIDTH-1:0]            fifo_event_value,
    input  wire                           event_pop_ack,
    input  wire                           event_fifo_empty,
    input  wire                           event_fifo_full,
    input  wire [15:0]                    event_fifo_level,
    input  wire [15:0]                    event_pending_level,
    input  wire                           event_overflow,
    input  wire [31:0]                    event_dropped_count,

    output reg                            global_enable,
    output reg  [CHANNELS-1:0]            channel_enable,
    output reg  [CHANNELS-1:0]            clear_period_stats,
    output reg                            clear_event_fifo,
    output reg                            event_pop,
    output wire [CHANNELS*TS_WIDTH-1:0]   min_high_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]   min_low_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]   timeout_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]   period_min_limit,
    output wire [CHANNELS*TS_WIDTH-1:0]   period_max_limit,
    output wire [CHANNELS*TS_WIDTH-1:0]   reference_period,
    output wire [CHANNELS*TS_WIDTH-1:0]   jump_limit_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]   drift_limit_ticks,
    output wire [CHANNELS*TS_WIDTH-1:0]   jitter_limit_ticks
);

    localparam integer CFG_COUNT = 9;
    localparam integer CFG_MIN_HIGH = 0;
    localparam integer CFG_MIN_LOW  = 1;
    localparam integer CFG_TIMEOUT  = 2;
    localparam integer CFG_PER_MIN  = 3;
    localparam integer CFG_PER_MAX  = 4;
    localparam integer CFG_REF      = 5;
    localparam integer CFG_JUMP     = 6;
    localparam integer CFG_DRIFT    = 7;
    localparam integer CFG_JITTER   = 8;

    localparam [1:0] AXI_OKAY   = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;

    reg [AXI_ADDR_WIDTH-1:0] awaddr_hold;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;
    reg        aw_hold_valid;
    reg        w_hold_valid;

    reg [TS_WIDTH-1:0] cfg_active [0:CHANNELS*CFG_COUNT-1];
    // AXI 写事务串行，因此一组带目标标签的 staging 即可保证 64 位原子提交，
    // 避免为 36 组阈值复制一套影子寄存器和宽动态选择网络。
    reg [TS_WIDTH-1:0] cfg_stage_value;
    reg [1:0]          cfg_stage_channel;
    reg [3:0]          cfg_stage_id;
    reg                cfg_stage_valid;

    reg [TS_WIDTH-1:0] snapshot_timestamp;
    reg [31:0]         snapshot_sequence;
    reg                snapshot_valid;
    reg [TS_WIDTH-1:0] snapshot_period [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] snapshot_high   [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] snapshot_low    [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] snapshot_min    [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] snapshot_max    [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] snapshot_p2p    [0:CHANNELS-1];
    reg [7:0]          snapshot_status [0:CHANNELS-1];
    reg                config_error;

    reg [31:0] read_data_mux;
    reg [1:0]  read_resp_mux;
    integer read_ch;
    integer read_off;
    integer reset_index;
    integer snapshot_index;
    integer commit_index;

    wire [1:0] write_main_channel;
    wire [6:0] write_main_offset;
    wire [1:0] write_ext_channel;
    wire [5:0] write_ext_offset;
    assign write_main_channel = (awaddr_hold - 12'h100) >> 7;
    assign write_main_offset  = (awaddr_hold - 12'h100) & 12'h07f;
    assign write_ext_channel  = (awaddr_hold - 12'h300) >> 6;
    assign write_ext_offset   = (awaddr_hold - 12'h300) & 12'h03f;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_enable;
        integer byte_index;
        begin
            apply_wstrb = old_value;
            for (byte_index=0; byte_index<4; byte_index=byte_index+1)
                if (byte_enable[byte_index])
                    apply_wstrb[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
        end
    endfunction

    function writable_address;
        input [AXI_ADDR_WIDTH-1:0] address;
        integer address_channel;
        integer address_offset;
        begin
            writable_address = 1'b0;
            if ((address == 12'h00C) || (address == 12'h044)) begin
                writable_address = 1'b1;
            end else if ((address >= 12'h100) && (address < 12'h300)) begin
                address_channel = (address - 12'h100) >> 7;
                address_offset  = (address - 12'h100) & 12'h07f;
                if ((address_channel < CHANNELS) &&
                    ((address_offset == 7'h00) ||
                     ((address_offset >= 7'h20) && (address_offset <= 7'h50))))
                    writable_address = 1'b1;
            end else if ((address >= 12'h300) && (address < 12'h400)) begin
                address_channel = (address - 12'h300) >> 6;
                address_offset  = (address - 12'h300) & 12'h03f;
                if ((address_channel < CHANNELS) &&
                    ((address_offset <= 6'h14) && (address_offset[1:0] == 2'b00)))
                    writable_address = 1'b1;
            end
        end
    endfunction

    task stage_threshold_word;
        input integer target_channel;
        input integer target_id;
        input integer high_word;
        reg [TS_WIDTH-1:0] base_value;
        begin
            if (cfg_stage_valid && (cfg_stage_channel == target_channel) &&
                (cfg_stage_id == target_id))
                base_value = cfg_stage_value;
            else
                base_value = cfg_active[target_channel*CFG_COUNT+target_id];

            cfg_stage_channel <= target_channel;
            cfg_stage_id      <= target_id;
            cfg_stage_valid   <= 1'b1;
            if (high_word != 0) begin
                cfg_stage_value[31:0]  <= base_value[31:0];
                cfg_stage_value[63:32] <= apply_wstrb(base_value[63:32],wdata_hold,wstrb_hold);
            end else begin
                cfg_stage_value[31:0]  <= apply_wstrb(base_value[31:0],wdata_hold,wstrb_hold);
                cfg_stage_value[63:32] <= base_value[63:32];
            end
        end
    endtask

    assign s_axi_awready = !aw_hold_valid && !s_axi_bvalid;
    assign s_axi_wready  = !w_hold_valid  && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    genvar output_ch;
    generate
        for (output_ch=0; output_ch<CHANNELS; output_ch=output_ch+1) begin : gen_cfg_outputs
            assign min_high_ticks   [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_MIN_HIGH];
            assign min_low_ticks    [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_MIN_LOW];
            assign timeout_ticks    [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_TIMEOUT];
            assign period_min_limit [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_PER_MIN];
            assign period_max_limit [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_PER_MAX];
            assign reference_period [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_REF];
            assign jump_limit_ticks [output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_JUMP];
            assign drift_limit_ticks[output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_DRIFT];
            assign jitter_limit_ticks[output_ch*TS_WIDTH +: TS_WIDTH] = cfg_active[output_ch*CFG_COUNT+CFG_JITTER];
        end
    endgenerate

    // 读通道译码。未实现、未对齐或超出当前 4 通道范围的地址返回 SLVERR。
    always @* begin
        read_data_mux = 32'd0;
        read_resp_mux = AXI_SLVERR;
        read_ch = 0;
        read_off = 0;
        if (s_axi_araddr[1:0] == 2'b00) begin
            case (s_axi_araddr)
                12'h000: begin read_data_mux=32'h5444_4731; read_resp_mux=AXI_OKAY; end
                12'h004: begin read_data_mux=32'h0001_0000; read_resp_mux=AXI_OKAY; end
                12'h008: begin read_data_mux={8'd0,8'd3,8'd64,CHANNELS[7:0]}; read_resp_mux=AXI_OKAY; end
                12'h00C: begin read_data_mux={31'd0,global_enable}; read_resp_mux=AXI_OKAY; end
                12'h010: begin
                    read_data_mux={26'd0,config_error,event_overflow,event_fifo_full,
                                   fifo_event_valid,snapshot_valid,global_enable};
                    read_resp_mux=AXI_OKAY;
                end
                12'h014: begin read_data_mux=SAMPLE_FREQ_HZ; read_resp_mux=AXI_OKAY; end
                12'h018: begin read_data_mux=snapshot_sequence; read_resp_mux=AXI_OKAY; end
                12'h01C: begin read_data_mux=snapshot_timestamp[31:0]; read_resp_mux=AXI_OKAY; end
                12'h020: begin read_data_mux=snapshot_timestamp[63:32]; read_resp_mux=AXI_OKAY; end
                12'h02C: begin
                    read_data_mux={12'd0,event_pop_ack,event_overflow,event_fifo_full,event_fifo_empty,event_fifo_level};
                    read_resp_mux=AXI_OKAY;
                end
                12'h030: begin
                    read_data_mux={15'd0,fifo_event_valid,4'd0,fifo_event_channel,fifo_event_type};
                    read_resp_mux=AXI_OKAY;
                end
                12'h034: begin read_data_mux=fifo_event_timestamp[31:0]; read_resp_mux=AXI_OKAY; end
                12'h038: begin read_data_mux=fifo_event_timestamp[63:32]; read_resp_mux=AXI_OKAY; end
                12'h03C: begin read_data_mux=fifo_event_value[31:0]; read_resp_mux=AXI_OKAY; end
                12'h040: begin read_data_mux=fifo_event_value[63:32]; read_resp_mux=AXI_OKAY; end
                12'h048: begin read_data_mux=event_dropped_count; read_resp_mux=AXI_OKAY; end
                12'h04C: begin read_data_mux={16'd0,event_pending_level}; read_resp_mux=AXI_OKAY; end
                12'h050: begin
                    read_data_mux={event_pending_level,event_fifo_level};
                    read_resp_mux=AXI_OKAY;
                end
                default: begin
                    if ((s_axi_araddr >= 12'h100) && (s_axi_araddr < 12'h300)) begin
                        read_ch  = (s_axi_araddr - 12'h100) >> 7;
                        read_off = (s_axi_araddr - 12'h100) & 12'h07f;
                        if (read_ch < CHANNELS) begin
                            case (read_off)
                                7'h00: begin read_data_mux={31'd0,channel_enable[read_ch]}; read_resp_mux=AXI_OKAY; end
                                7'h04: begin read_data_mux={24'd0,snapshot_status[read_ch]}; read_resp_mux=AXI_OKAY; end
                                7'h08: begin read_data_mux=snapshot_period[read_ch][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h0C: begin read_data_mux=snapshot_period[read_ch][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h10: begin read_data_mux=snapshot_high[read_ch][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h14: begin read_data_mux=snapshot_high[read_ch][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h18: begin read_data_mux=snapshot_low[read_ch][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h1C: begin read_data_mux=snapshot_low[read_ch][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h20: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_MIN_HIGH][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h24: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_MIN_LOW][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h28: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_TIMEOUT][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h2C: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_TIMEOUT][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h30: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_PER_MIN][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h34: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_PER_MIN][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h38: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_PER_MAX][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h3C: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_PER_MAX][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h40: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_REF][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h44: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_REF][63:32]; read_resp_mux=AXI_OKAY; end
                                7'h48: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_JUMP][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h4C: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_DRIFT][31:0]; read_resp_mux=AXI_OKAY; end
                                7'h50: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_JITTER][31:0]; read_resp_mux=AXI_OKAY; end
                                default: begin read_data_mux=32'd0; read_resp_mux=AXI_SLVERR; end
                            endcase
                        end
                    end else if ((s_axi_araddr >= 12'h300) && (s_axi_araddr < 12'h400)) begin
                        read_ch  = (s_axi_araddr - 12'h300) >> 6;
                        read_off = (s_axi_araddr - 12'h300) & 12'h03f;
                        if (read_ch < CHANNELS) begin
                            case (read_off)
                                6'h00: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_MIN_HIGH][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h04: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_MIN_LOW][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h08: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_JUMP][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h0C: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_DRIFT][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h10: begin read_data_mux=cfg_active[read_ch*CFG_COUNT+CFG_JITTER][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h18: begin read_data_mux=snapshot_min[read_ch][31:0]; read_resp_mux=AXI_OKAY; end
                                6'h1C: begin read_data_mux=snapshot_min[read_ch][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h20: begin read_data_mux=snapshot_max[read_ch][31:0]; read_resp_mux=AXI_OKAY; end
                                6'h24: begin read_data_mux=snapshot_max[read_ch][63:32]; read_resp_mux=AXI_OKAY; end
                                6'h28: begin read_data_mux=snapshot_p2p[read_ch][31:0]; read_resp_mux=AXI_OKAY; end
                                6'h2C: begin read_data_mux=snapshot_p2p[read_ch][63:32]; read_resp_mux=AXI_OKAY; end
                                default: begin read_data_mux=32'd0; read_resp_mux=AXI_SLVERR; end
                            endcase
                        end
                    end
                end
            endcase
        end
    end

    // AXI read data/response remains stable until RREADY。
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
            s_axi_rresp  <= AXI_OKAY;
        end else begin
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= read_data_mux;
                s_axi_rresp  <= read_resp_mux;
            end
        end
    end

    // AW/W 分别缓存；只有两者均已收到且没有未完成 B 响应时才执行一次写事务。
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            awaddr_hold       <= {AXI_ADDR_WIDTH{1'b0}};
            wdata_hold        <= 32'd0;
            wstrb_hold        <= 4'd0;
            aw_hold_valid     <= 1'b0;
            w_hold_valid      <= 1'b0;
            s_axi_bvalid      <= 1'b0;
            s_axi_bresp       <= AXI_OKAY;
            global_enable     <= 1'b0;
            channel_enable    <= {CHANNELS{1'b0}};
            clear_period_stats<= {CHANNELS{1'b0}};
            clear_event_fifo  <= 1'b0;
            event_pop         <= 1'b0;
            snapshot_timestamp<= {TS_WIDTH{1'b0}};
            snapshot_sequence <= 32'd0;
            snapshot_valid    <= 1'b0;
            config_error      <= 1'b0;
            cfg_stage_value   <= {TS_WIDTH{1'b0}};
            cfg_stage_channel <= 2'd0;
            cfg_stage_id      <= 4'd0;
            cfg_stage_valid   <= 1'b0;
            for (reset_index=0; reset_index<CHANNELS*CFG_COUNT; reset_index=reset_index+1) begin
                cfg_active[reset_index] <= {TS_WIDTH{1'b0}};
            end
            for (reset_index=0; reset_index<CHANNELS; reset_index=reset_index+1) begin
                snapshot_period[reset_index] <= {TS_WIDTH{1'b0}};
                snapshot_high[reset_index]   <= {TS_WIDTH{1'b0}};
                snapshot_low[reset_index]    <= {TS_WIDTH{1'b0}};
                snapshot_min[reset_index]    <= {TS_WIDTH{1'b0}};
                snapshot_max[reset_index]    <= {TS_WIDTH{1'b0}};
                snapshot_p2p[reset_index]    <= {TS_WIDTH{1'b0}};
                snapshot_status[reset_index] <= 8'd0;
            end
        end else begin
            clear_period_stats <= {CHANNELS{1'b0}};
            clear_event_fifo   <= 1'b0;
            event_pop          <= 1'b0;

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_hold   <= s_axi_awaddr;
                aw_hold_valid <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_hold   <= s_axi_wdata;
                wstrb_hold   <= s_axi_wstrb;
                w_hold_valid <= 1'b1;
            end

            if (aw_hold_valid && w_hold_valid && !s_axi_bvalid) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= AXI_OKAY;

                if (awaddr_hold[1:0] != 2'b00) begin
                    s_axi_bresp <= AXI_SLVERR;
                end else if (!(|wstrb_hold)) begin
                    // WSTRB=0 是合法空写；仍对只读或非法地址报告 SLVERR。
                    if (!writable_address(awaddr_hold))
                        s_axi_bresp <= AXI_SLVERR;
                end else if (awaddr_hold == 12'h00C) begin
                    if (wstrb_hold[0]) begin
                        global_enable <= wdata_hold[0];
                        if (wdata_hold[1]) begin
                            snapshot_timestamp <= core_timestamp;
                            snapshot_sequence  <= snapshot_sequence + 1'b1;
                            snapshot_valid     <= 1'b1;
                            for (snapshot_index=0; snapshot_index<CHANNELS; snapshot_index=snapshot_index+1) begin
                                snapshot_period[snapshot_index] <= core_period_ticks[snapshot_index*TS_WIDTH +: TS_WIDTH];
                                snapshot_high[snapshot_index]   <= core_high_ticks[snapshot_index*TS_WIDTH +: TS_WIDTH];
                                snapshot_low[snapshot_index]    <= core_low_ticks[snapshot_index*TS_WIDTH +: TS_WIDTH];
                                snapshot_min[snapshot_index]    <= core_min_period[snapshot_index*TS_WIDTH +: TS_WIDTH];
                                snapshot_max[snapshot_index]    <= core_max_period[snapshot_index*TS_WIDTH +: TS_WIDTH];
                                snapshot_p2p[snapshot_index]    <= core_peak_to_peak[snapshot_index*TS_WIDTH +: TS_WIDTH];
                                snapshot_status[snapshot_index] <= {2'd0,core_stats_valid[snapshot_index],
                                    core_low_valid[snapshot_index],core_high_valid[snapshot_index],
                                    core_period_valid[snapshot_index],1'b0,
                                    core_sync_level[snapshot_index]};
                            end
                        end
                        if (wdata_hold[2])
                            config_error <= 1'b0;
                        if (wdata_hold[3])
                            clear_period_stats <= {CHANNELS{1'b1}};
                        if (wdata_hold[4])
                            clear_event_fifo <= 1'b1;
                    end
                end else if (awaddr_hold == 12'h044) begin
                    if (wstrb_hold[0] && wdata_hold[0])
                        event_pop <= fifo_event_valid;
                end else if ((awaddr_hold >= 12'h100) && (awaddr_hold < 12'h300)) begin
                    if (write_main_channel >= CHANNELS) begin
                        s_axi_bresp <= AXI_SLVERR;
                    end else begin
                        case (write_main_offset)
                            7'h00: begin
                                if (wstrb_hold[0]) begin
                                    channel_enable[write_main_channel] <= wdata_hold[0];
                                    if (wdata_hold[2])
                                        clear_period_stats[write_main_channel] <= 1'b1;
                                end
                            end
                            7'h20: stage_threshold_word(write_main_channel,CFG_MIN_HIGH,0);
                            7'h24: stage_threshold_word(write_main_channel,CFG_MIN_LOW,0);
                            7'h28: stage_threshold_word(write_main_channel,CFG_TIMEOUT,0);
                            7'h2C: stage_threshold_word(write_main_channel,CFG_TIMEOUT,1);
                            7'h30: stage_threshold_word(write_main_channel,CFG_PER_MIN,0);
                            7'h34: stage_threshold_word(write_main_channel,CFG_PER_MIN,1);
                            7'h38: stage_threshold_word(write_main_channel,CFG_PER_MAX,0);
                            7'h3C: stage_threshold_word(write_main_channel,CFG_PER_MAX,1);
                            7'h40: stage_threshold_word(write_main_channel,CFG_REF,0);
                            7'h44: stage_threshold_word(write_main_channel,CFG_REF,1);
                            7'h48: stage_threshold_word(write_main_channel,CFG_JUMP,0);
                            7'h4C: stage_threshold_word(write_main_channel,CFG_DRIFT,0);
                            7'h50: stage_threshold_word(write_main_channel,CFG_JITTER,0);
                            default: s_axi_bresp <= AXI_SLVERR;
                        endcase
                    end
                end else if ((awaddr_hold >= 12'h300) && (awaddr_hold < 12'h400)) begin
                    if (write_ext_channel >= CHANNELS) begin
                        s_axi_bresp <= AXI_SLVERR;
                    end else begin
                        case (write_ext_offset)
                            6'h00: stage_threshold_word(write_ext_channel,CFG_MIN_HIGH,1);
                            6'h04: stage_threshold_word(write_ext_channel,CFG_MIN_LOW,1);
                            6'h08: stage_threshold_word(write_ext_channel,CFG_JUMP,1);
                            6'h0C: stage_threshold_word(write_ext_channel,CFG_DRIFT,1);
                            6'h10: stage_threshold_word(write_ext_channel,CFG_JITTER,1);
                            6'h14: begin
                                if (cfg_stage_valid && wstrb_hold[cfg_stage_id[3]] &&
                                    (cfg_stage_channel == write_ext_channel) &&
                                    wdata_hold[cfg_stage_id]) begin
                                    cfg_active[write_ext_channel*CFG_COUNT+cfg_stage_id] <= cfg_stage_value;
                                    cfg_stage_valid <= 1'b0;
                                end
                            end
                            default: s_axi_bresp <= AXI_SLVERR;
                        endcase
                    end
                end else begin
                    s_axi_bresp <= AXI_SLVERR;
                end
            end

            // 非法的周期上下限被标记，但不在硬件中静默改写软件提交值。
            for (commit_index=0; commit_index<CHANNELS; commit_index=commit_index+1)
                if ((cfg_active[commit_index*CFG_COUNT+CFG_PER_MIN] != 0) &&
                    (cfg_active[commit_index*CFG_COUNT+CFG_PER_MAX] != 0) &&
                    (cfg_active[commit_index*CFG_COUNT+CFG_PER_MIN] >
                     cfg_active[commit_index*CFG_COUNT+CFG_PER_MAX]))
                    config_error <= 1'b1;
        end
    end

    // 仅支持当前系统规定的 64 位时间量。
    initial begin
        if (TS_WIDTH != 64)
            $error("timing_diagnostic_axi_regs requires TS_WIDTH=64");
        if (CHANNELS > 4)
            $error("current AXI register map supports at most four channels");
    end

endmodule
