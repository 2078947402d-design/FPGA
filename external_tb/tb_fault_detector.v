`timescale 1ns / 1ps

module tb_fault_detector;

    localparam integer CHANNELS         = 4;
    localparam integer TS_WIDTH         = 64;
    localparam integer CHANNEL_ID_WIDTH = 4;
    localparam integer EVENT_LANES      = CHANNELS * 3;

    reg                              clk;
    reg                              rst_n;
    reg  [TS_WIDTH-1:0]              timestamp;
    reg  [CHANNELS-1:0]              rise_pulse;
    reg  [CHANNELS*TS_WIDTH-1:0]     high_ticks;
    reg  [CHANNELS-1:0]              high_valid;
    reg  [CHANNELS*TS_WIDTH-1:0]     low_ticks;
    reg  [CHANNELS-1:0]              low_valid;
    reg  [CHANNELS*TS_WIDTH-1:0]     min_high_ticks;
    reg  [CHANNELS*TS_WIDTH-1:0]     min_low_ticks;
    reg  [CHANNELS*TS_WIDTH-1:0]     timeout_ticks;

    wire [EVENT_LANES-1:0]           event_valid;
    wire [EVENT_LANES*CHANNEL_ID_WIDTH-1:0] event_channel;
    wire [EVENT_LANES*8-1:0]         event_type;
    wire [EVENT_LANES*TS_WIDTH-1:0]  event_timestamp;
    wire [EVENT_LANES*TS_WIDTH-1:0]  event_value;

    integer errors;
    integer lane;
    integer decoded_channel;
    integer expected_type;
    integer short_high_count [0:CHANNELS-1];
    integer short_low_count  [0:CHANNELS-1];
    integer timeout_count    [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] last_short_high_value [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] last_short_low_value  [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] last_timeout_value    [0:CHANNELS-1];
    reg [TS_WIDTH-1:0] last_event_timestamp [0:CHANNELS-1];

    // 小位宽实例专门验证时间戳回绕。
    reg        wrap_rst_n;
    reg  [7:0] wrap_timestamp;
    reg        wrap_rise_pulse;
    reg  [7:0] wrap_high_ticks;
    reg        wrap_high_valid;
    reg  [7:0] wrap_low_ticks;
    reg        wrap_low_valid;
    wire       wrap_short_high_valid;
    wire [7:0] wrap_short_high_timestamp;
    wire [7:0] wrap_short_high_value;
    wire       wrap_short_low_valid;
    wire [7:0] wrap_short_low_timestamp;
    wire [7:0] wrap_short_low_value;
    wire       wrap_timeout_valid;
    wire [7:0] wrap_timeout_timestamp;
    wire [7:0] wrap_timeout_value;
    integer    wrap_timeout_count;
    integer    wrap_step;

    multi_channel_fault_detector #(
        .CHANNELS        (CHANNELS),
        .TS_WIDTH        (TS_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .timestamp      (timestamp),
        .rise_pulse     (rise_pulse),
        .high_ticks     (high_ticks),
        .high_valid     (high_valid),
        .low_ticks      (low_ticks),
        .low_valid      (low_valid),
        .min_high_ticks (min_high_ticks),
        .min_low_ticks  (min_low_ticks),
        .timeout_ticks  (timeout_ticks),
        .event_valid    (event_valid),
        .event_channel  (event_channel),
        .event_type     (event_type),
        .event_timestamp(event_timestamp),
        .event_value    (event_value)
    );

    channel_fault_detector #(
        .TS_WIDTH(8)
    ) wrap_dut (
        .clk                 (clk),
        .rst_n               (wrap_rst_n),
        .timestamp           (wrap_timestamp),
        .rise_pulse          (wrap_rise_pulse),
        .high_ticks          (wrap_high_ticks),
        .high_valid          (wrap_high_valid),
        .low_ticks           (wrap_low_ticks),
        .low_valid           (wrap_low_valid),
        .min_high_ticks      (8'd0),
        .min_low_ticks       (8'd0),
        .timeout_ticks       (8'd8),
        .short_high_valid    (wrap_short_high_valid),
        .short_high_timestamp(wrap_short_high_timestamp),
        .short_high_value    (wrap_short_high_value),
        .short_low_valid     (wrap_short_low_valid),
        .short_low_timestamp (wrap_short_low_timestamp),
        .short_low_value     (wrap_short_low_value),
        .timeout_valid       (wrap_timeout_valid),
        .timeout_timestamp   (wrap_timeout_timestamp),
        .timeout_value       (wrap_timeout_value)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timestamp <= {TS_WIDTH{1'b0}};
        else
            timestamp <= timestamp + 1'b1;
    end

    task automatic set_thresholds;
        input integer channel_index;
        input [TS_WIDTH-1:0] min_high;
        input [TS_WIDTH-1:0] min_low;
        input [TS_WIDTH-1:0] timeout;
        begin
            min_high_ticks[channel_index*TS_WIDTH +: TS_WIDTH] = min_high;
            min_low_ticks[channel_index*TS_WIDTH +: TS_WIDTH]  = min_low;
            timeout_ticks[channel_index*TS_WIDTH +: TS_WIDTH]  = timeout;
        end
    endtask

    task automatic pulse_rise;
        input integer channel_index;
        begin
            @(negedge clk);
            rise_pulse[channel_index] = 1'b1;
            @(negedge clk);
            rise_pulse[channel_index] = 1'b0;
        end
    endtask

    task automatic emit_high_measurement;
        input integer channel_index;
        input [TS_WIDTH-1:0] value;
        begin
            @(negedge clk);
            high_ticks[channel_index*TS_WIDTH +: TS_WIDTH] = value;
            high_valid[channel_index] = 1'b1;
            @(negedge clk);
            high_valid[channel_index] = 1'b0;
        end
    endtask

    task automatic emit_low_measurement;
        input integer channel_index;
        input [TS_WIDTH-1:0] value;
        begin
            @(negedge clk);
            low_ticks[channel_index*TS_WIDTH +: TS_WIDTH] = value;
            low_valid[channel_index] = 1'b1;
            @(negedge clk);
            low_valid[channel_index] = 1'b0;
        end
    endtask

    task automatic wait_clocks;
        input integer count;
        begin
            repeat (count) @(posedge clk);
            // 事件监视器在时钟沿后 #1 采样；主线程再延后一拍仿真时间，
            // 避免两者位于同一 time slot 造成记分板读取竞争。
            #2;
        end
    endtask

    task automatic assert_main_reset;
        integer reset_index;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            rise_pulse = {CHANNELS{1'b0}};
            high_valid = {CHANNELS{1'b0}};
            low_valid  = {CHANNELS{1'b0}};
            repeat (3) @(posedge clk);
            #1;
            if (event_valid !== {EVENT_LANES{1'b0}}) begin
                $display("ERROR: event_valid not clear during reset");
                errors = errors + 1;
            end
            // 每个独立场景从干净的测试侧记分板开始。
            for (reset_index = 0; reset_index < CHANNELS;
                 reset_index = reset_index + 1) begin
                short_high_count[reset_index] = 0;
                short_low_count[reset_index]  = 0;
                timeout_count[reset_index]    = 0;
                last_short_high_value[reset_index] = 0;
                last_short_low_value[reset_index]  = 0;
                last_timeout_value[reset_index]    = 0;
                last_event_timestamp[reset_index]  = 0;
            end
        end
    endtask

    // 通用事件总线检查，同时验证 lane、通道号和事件类型的固定映射。
    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            for (lane = 0; lane < EVENT_LANES; lane = lane + 1) begin
                if (event_valid[lane]) begin
                    decoded_channel = event_channel[lane*CHANNEL_ID_WIDTH +: CHANNEL_ID_WIDTH];
                    expected_type   = (lane % 3) + 1;

                    if (decoded_channel != (lane / 3)) begin
                        $display("ERROR: lane %0d reports channel %0d", lane, decoded_channel);
                        errors = errors + 1;
                    end
                    if (event_type[lane*8 +: 8] != expected_type) begin
                        $display("ERROR: lane %0d reports type 0x%0h, expected 0x%0h",
                                 lane, event_type[lane*8 +: 8], expected_type);
                        errors = errors + 1;
                    end
                    if (^event_timestamp[lane*TS_WIDTH +: TS_WIDTH] === 1'bx) begin
                        $display("ERROR: lane %0d timestamp contains X", lane);
                        errors = errors + 1;
                    end

                    last_event_timestamp[decoded_channel] =
                        event_timestamp[lane*TS_WIDTH +: TS_WIDTH];

                    case (event_type[lane*8 +: 8])
                        8'h01: begin
                            short_high_count[decoded_channel] =
                                short_high_count[decoded_channel] + 1;
                            last_short_high_value[decoded_channel] =
                                event_value[lane*TS_WIDTH +: TS_WIDTH];
                        end
                        8'h02: begin
                            short_low_count[decoded_channel] =
                                short_low_count[decoded_channel] + 1;
                            last_short_low_value[decoded_channel] =
                                event_value[lane*TS_WIDTH +: TS_WIDTH];
                        end
                        8'h03: begin
                            timeout_count[decoded_channel] =
                                timeout_count[decoded_channel] + 1;
                            last_timeout_value[decoded_channel] =
                                event_value[lane*TS_WIDTH +: TS_WIDTH];
                        end
                        default: begin
                            $display("ERROR: unknown event type");
                            errors = errors + 1;
                        end
                    endcase
                end
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (wrap_rst_n && wrap_timeout_valid)
            wrap_timeout_count = wrap_timeout_count + 1;
    end

    initial begin
        errors          = 0;
        rst_n           = 1'b0;
        timestamp       = {TS_WIDTH{1'b0}};
        rise_pulse      = {CHANNELS{1'b0}};
        high_ticks      = {(CHANNELS*TS_WIDTH){1'b0}};
        high_valid      = {CHANNELS{1'b0}};
        low_ticks       = {(CHANNELS*TS_WIDTH){1'b0}};
        low_valid       = {CHANNELS{1'b0}};
        min_high_ticks  = {(CHANNELS*TS_WIDTH){1'b0}};
        min_low_ticks   = {(CHANNELS*TS_WIDTH){1'b0}};
        timeout_ticks   = {(CHANNELS*TS_WIDTH){1'b0}};

        wrap_rst_n      = 1'b0;
        wrap_timestamp  = 8'd0;
        wrap_rise_pulse = 1'b0;
        wrap_high_ticks = 8'd0;
        wrap_high_valid = 1'b0;
        wrap_low_ticks  = 8'd0;
        wrap_low_valid  = 1'b0;
        wrap_timeout_count = 0;

        for (lane = 0; lane < CHANNELS; lane = lane + 1) begin
            short_high_count[lane] = 0;
            short_low_count[lane]  = 0;
            timeout_count[lane]    = 0;
            last_short_high_value[lane] = 0;
            last_short_low_value[lane]  = 0;
            last_timeout_value[lane]    = 0;
            last_event_timestamp[lane]  = 0;
        end

        // 初始复位。
        repeat (4) @(posedge clk);
        #1;
        if (event_valid !== 0) begin
            $display("ERROR: initial reset generated event");
            errors = errors + 1;
        end
        @(negedge clk);
        rst_n = 1'b1;

        // 正常脉冲等价测量：所有宽度均大于阈值，周期内持续恢复上升沿。
        set_thresholds(0, 64'd3, 64'd3, 64'd12);
        repeat (3) begin
            pulse_rise(0);
            emit_high_measurement(0, 64'd4);
            emit_low_measurement(0, 64'd4);
        end
        wait_clocks(2);
        if ((short_high_count[0] != 0) || (short_low_count[0] != 0) ||
            (timeout_count[0] != 0)) begin
            $display("ERROR: normal pulse generated a fault");
            errors = errors + 1;
        end

        // 短高：2 < 3 报警；边界 3 == 3 不报警。
        emit_high_measurement(0, 64'd2);
        wait_clocks(1);
        if ((short_high_count[0] != 1) || (last_short_high_value[0] != 2)) begin
            $display("ERROR: SHORT_HIGH strict-less-than test failed");
            errors = errors + 1;
        end
        emit_high_measurement(0, 64'd3);
        wait_clocks(1);
        if (short_high_count[0] != 1) begin
            $display("ERROR: high width equal to threshold was reported");
            errors = errors + 1;
        end

        // 短低：2 < 3 报警；边界 3 == 3 不报警。
        emit_low_measurement(0, 64'd2);
        wait_clocks(1);
        if ((short_low_count[0] != 1) || (last_short_low_value[0] != 2)) begin
            $display("ERROR: SHORT_LOW strict-less-than test failed");
            errors = errors + 1;
        end
        emit_low_measurement(0, 64'd3);
        wait_clocks(1);
        if (short_low_count[0] != 1) begin
            $display("ERROR: low width equal to threshold was reported");
            errors = errors + 1;
        end

        // 毛刺阈值为 0 时关闭检测。
        set_thresholds(0, 64'd0, 64'd0, 64'd0);
        emit_high_measurement(0, 64'd1);
        emit_low_measurement(0, 64'd1);
        wait_clocks(2);
        if ((short_high_count[0] != 1) || (short_low_count[0] != 1)) begin
            $display("ERROR: zero glitch threshold did not disable detection");
            errors = errors + 1;
        end

        // 超时阈值为 0 时，即使已有上升沿历史也不报警。
        assert_main_reset();
        set_thresholds(0, 64'd0, 64'd0, 64'd0);
        @(negedge clk);
        rst_n = 1'b1;
        pulse_rise(0);
        wait_clocks(10);
        if (timeout_count[0] != 0) begin
            $display("ERROR: zero timeout threshold did not disable detection");
            errors = errors + 1;
        end

        // 非零超时阈值但从未见到上升沿：无输入不能误报。
        assert_main_reset();
        set_thresholds(0, 64'd0, 64'd0, 64'd5);
        @(negedge clk);
        rst_n = 1'b1;
        wait_clocks(10);
        if (timeout_count[0] != 0) begin
            $display("ERROR: timeout reported without valid rise history");
            errors = errors + 1;
        end

        // 运行后停止：间隔等于 5 不报警，第 6 tick 报警且只报一次。
        pulse_rise(0);
        wait_clocks(5);
        if (timeout_count[0] != 0) begin
            $display("ERROR: timeout reported at equality boundary");
            errors = errors + 1;
        end
        wait_clocks(1);
        if ((timeout_count[0] != 1) || (last_timeout_value[0] != 6)) begin
            $display("ERROR: first timeout event/value incorrect");
            errors = errors + 1;
        end
        wait_clocks(10);
        if (timeout_count[0] != 1) begin
            $display("ERROR: sustained timeout generated repeated events");
            errors = errors + 1;
        end

        // 信号恢复后重新武装；再次停止应产生第二次超时。
        pulse_rise(0);
        wait_clocks(6);
        if ((timeout_count[0] != 2) || (last_timeout_value[0] != 6)) begin
            $display("ERROR: recovery did not re-arm timeout detection");
            errors = errors + 1;
        end

        // 四通道并行独立工作：CH0 短高、CH1 短低、CH2 超时、CH3 正常。
        assert_main_reset();
        set_thresholds(0, 64'd3, 64'd0, 64'd0);
        set_thresholds(1, 64'd0, 64'd3, 64'd0);
        set_thresholds(2, 64'd0, 64'd0, 64'd4);
        set_thresholds(3, 64'd3, 64'd3, 64'd0);
        @(negedge clk);
        rst_n = 1'b1;
        fork
            emit_high_measurement(0, 64'd1);
            emit_low_measurement (1, 64'd1);
            pulse_rise(2);
            begin
                emit_high_measurement(3, 64'd4);
                emit_low_measurement (3, 64'd4);
            end
        join
        wait_clocks(6);

        if ((short_high_count[0] != 1) || (short_low_count[0] != 0) ||
            (timeout_count[0] != 0)) begin
            $display("ERROR: CH0 parallel isolation failed");
            errors = errors + 1;
        end
        if ((short_high_count[1] != 0) || (short_low_count[1] != 1) ||
            (timeout_count[1] != 0)) begin
            $display("ERROR: CH1 parallel isolation failed");
            errors = errors + 1;
        end
        if ((short_high_count[2] != 0) || (short_low_count[2] != 0) ||
            (timeout_count[2] != 1)) begin
            $display("ERROR: CH2 parallel isolation failed");
            errors = errors + 1;
        end
        if ((short_high_count[3] != 0) || (short_low_count[3] != 0) ||
            (timeout_count[3] != 0)) begin
            $display("ERROR: normal CH3 generated a fault");
            errors = errors + 1;
        end

        // 运行中复位清除检测器历史；复位后无新上升沿不能再次超时。
        assert_main_reset();
        @(negedge clk);
        rst_n = 1'b1;
        wait_clocks(8);
        if (timeout_count[2] != 0) begin
            $display("ERROR: runtime reset did not clear timeout history");
            errors = errors + 1;
        end

        // 8 位时间戳从 250 跨越 255->0；阈值 8，在差值 9 时报警。
        @(negedge clk);
        wrap_timestamp  = 8'd250;
        wrap_rise_pulse = 1'b1;
        wrap_rst_n      = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        wrap_rise_pulse = 1'b0;
        for (wrap_step = 251; wrap_step <= 259; wrap_step = wrap_step + 1) begin
            wrap_timestamp = wrap_step[7:0];
            @(posedge clk);
            #1;
            @(negedge clk);
        end
        if ((wrap_timeout_count != 1) || (wrap_timeout_timestamp != 8'd3) ||
            (wrap_timeout_value != 8'd9)) begin
            $display("ERROR: timestamp wrap timeout failed count/ts/value=%0d/%0d/%0d",
                     wrap_timeout_count, wrap_timeout_timestamp, wrap_timeout_value);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TEST PASSED: fault_detector self-check completed");
            $finish;
        end
        else begin
            $fatal(1, "TEST FAILED: %0d error(s)", errors);
        end
    end

    initial begin
        #200000;
        $fatal(1, "TEST FAILED: simulation timeout");
    end

endmodule
