`timescale 1ns / 1ps

module tb_timing_diagnostic_e2e;
    localparam integer C=4; localparam integer W=64; localparam integer LANES=32;
    reg clk, rst_n; reg [C-1:0] async_ch, clear_stats;
    reg [C*W-1:0] min_high,min_low,timeout_ticks,pmin,pmax,pref,jump_lim,drift_lim,jitter_lim;
    wire [W-1:0] timestamp; wire [C-1:0] sync_level,rise_pulse,fall_pulse;
    wire [C*W-1:0] period_ticks,high_ticks,low_ticks,min_period,max_period,p2p,adj_diff;
    wire [C-1:0] period_valid,high_valid,low_valid,stats_valid;
    wire [LANES-1:0] event_valid; wire [LANES*4-1:0] event_channel;
    wire [LANES*8-1:0] event_type; wire [LANES*W-1:0] event_timestamp,event_value;
    integer errors,lane,ch,t; integer short_cnt[0:3],long_cnt[0:3],jump_cnt[0:3],drift_cnt[0:3],jitter_cnt[0:3],period_cnt[0:3];

    // 8 位端到端实例，用有限仿真时间验证全局计数器回绕。
    reg wrap_rst_n,wrap_async; reg [7:0] wrap_pmax;
    wire [7:0] wrap_ts,wrap_period; wire wrap_period_valid,wrap_rise;
    wire [7:0] wrap_ev_valid; wire [31:0] wrap_ev_ch; wire [63:0] wrap_ev_type;
    wire [63:0] wrap_ev_ts,wrap_ev_value; integer wrap_long_count,wrap_rise_count;
    reg [7:0] wrap_first_rise,wrap_second_rise;

    timing_diagnostic_core_v2 #(.CHANNELS(C),.SYNC_STAGES(3),.TS_WIDTH(W),.CHANNEL_ID_WIDTH(4)) dut (
      .clk(clk),.rst_n(rst_n),.async_ch(async_ch),.clear_period_stats(clear_stats),
      .min_high_ticks(min_high),.min_low_ticks(min_low),.timeout_ticks(timeout_ticks),
      .period_min_limit(pmin),.period_max_limit(pmax),.reference_period(pref),
      .jump_limit_ticks(jump_lim),.drift_limit_ticks(drift_lim),.jitter_limit_ticks(jitter_lim),
      .timestamp(timestamp),.sync_level(sync_level),.rise_pulse(rise_pulse),.fall_pulse(fall_pulse),
      .period_ticks(period_ticks),.high_ticks(high_ticks),.low_ticks(low_ticks),
      .period_valid(period_valid),.high_valid(high_valid),.low_valid(low_valid),
      .min_period(min_period),.max_period(max_period),.peak_to_peak_jitter(p2p),
      .adjacent_period_diff(adj_diff),.period_stats_valid(stats_valid),
      .event_valid(event_valid),.event_channel(event_channel),.event_type(event_type),
      .event_timestamp(event_timestamp),.event_value(event_value));

    timing_diagnostic_core_v2 #(.CHANNELS(1),.SYNC_STAGES(3),.TS_WIDTH(8),.CHANNEL_ID_WIDTH(4)) wrap_dut (
      .clk(clk),.rst_n(wrap_rst_n),.async_ch(wrap_async),.clear_period_stats(1'b0),
      .min_high_ticks(8'd0),.min_low_ticks(8'd0),.timeout_ticks(8'd0),
      .period_min_limit(8'd0),.period_max_limit(wrap_pmax),.reference_period(8'd0),
      .jump_limit_ticks(8'd0),.drift_limit_ticks(8'd0),.jitter_limit_ticks(8'd0),
      .timestamp(wrap_ts),.sync_level(),.rise_pulse(wrap_rise),.fall_pulse(),
      .period_ticks(wrap_period),.high_ticks(),.low_ticks(),.period_valid(wrap_period_valid),
      .high_valid(),.low_valid(),.min_period(),.max_period(),.peak_to_peak_jitter(),
      .adjacent_period_diff(),.period_stats_valid(),.event_valid(wrap_ev_valid),
      .event_channel(wrap_ev_ch),.event_type(wrap_ev_type),.event_timestamp(wrap_ev_ts),
      .event_value(wrap_ev_value));

    initial begin clk=0; forever #10 clk=~clk; end

    task automatic cfg;
      input integer c; input [63:0] mn,mx,rf,jp,dr,ji;
      begin pmin[c*W+:W]=mn;pmax[c*W+:W]=mx;pref[c*W+:W]=rf;
        jump_lim[c*W+:W]=jp;drift_lim[c*W+:W]=dr;jitter_lim[c*W+:W]=ji; end
    endtask
    task automatic periodic;
      input integer c,initial_low,hi,lo,pulses; integer i;
      begin
        repeat(initial_low) @(negedge clk);
        for(i=0;i<pulses;i=i+1) begin
          async_ch[c]=1; repeat(hi) @(negedge clk); async_ch[c]=0;
          if(i<pulses-1) repeat(lo) @(negedge clk);
        end
      end
    endtask
    task automatic variable_ch3; begin
      repeat(4) @(negedge clk); async_ch[3]=1; repeat(3) @(negedge clk); async_ch[3]=0;
      repeat(7) @(negedge clk); async_ch[3]=1; repeat(3) @(negedge clk); async_ch[3]=0;
      repeat(11) @(negedge clk); async_ch[3]=1; repeat(3) @(negedge clk); async_ch[3]=0;
      repeat(10) @(negedge clk); async_ch[3]=1; repeat(3) @(negedge clk); async_ch[3]=0;
    end endtask

    always @(posedge clk) begin #1;
      if(rst_n) begin
        for(ch=0;ch<C;ch=ch+1) if(period_valid[ch]) period_cnt[ch]=period_cnt[ch]+1;
        for(lane=0;lane<LANES;lane=lane+1) if(event_valid[lane]) begin
          ch=event_channel[lane*4+:4]; t=event_type[lane*8+:8];
          if(ch!=lane/8 || t!=(lane%8)+1) begin $display("ERROR: E2E metadata"); errors=errors+1; end
          case(t) 4:short_cnt[ch]=short_cnt[ch]+1; 5:long_cnt[ch]=long_cnt[ch]+1;
            6:jump_cnt[ch]=jump_cnt[ch]+1; 7:drift_cnt[ch]=drift_cnt[ch]+1;
            8:jitter_cnt[ch]=jitter_cnt[ch]+1; default: begin $display("ERROR: unexpected base event");errors=errors+1;end endcase
        end
      end
      if(wrap_rst_n) begin
        if(wrap_rise) begin wrap_rise_count=wrap_rise_count+1;
          if(wrap_rise_count==1) wrap_first_rise=wrap_ts;
          if(wrap_rise_count==2) wrap_second_rise=wrap_ts; end
        if(wrap_ev_valid[4]) wrap_long_count=wrap_long_count+1;
      end
    end

    initial begin
      errors=0;rst_n=0;async_ch=0;clear_stats=0;min_high=0;min_low=0;timeout_ticks=0;
      pmin=0;pmax=0;pref=0;jump_lim=0;drift_lim=0;jitter_lim=0;
      wrap_rst_n=0;wrap_async=0;wrap_pmax=19;wrap_long_count=0;wrap_rise_count=0;
      wrap_first_rise=0;wrap_second_rise=0;
      for(ch=0;ch<C;ch=ch+1) begin short_cnt[ch]=0;long_cnt[ch]=0;jump_cnt[ch]=0;drift_cnt[ch]=0;jitter_cnt[ch]=0;period_cnt[ch]=0;end
      repeat(5) @(posedge clk); @(negedge clk); rst_n=1;
      cfg(0,8,12,10,2,1,2); cfg(1,8,0,0,0,0,0); cfg(2,0,12,0,0,0,0); cfg(3,0,0,10,2,2,3);
      fork periodic(0,4,4,6,4); periodic(1,5,2,4,3); periodic(2,6,5,9,3); variable_ch3(); join
      repeat(12) @(posedge clk); #2;
      if(period_cnt[0]!=3 || period_ticks[0*W+:W]!=10 || short_cnt[0]+long_cnt[0]+jump_cnt[0]+drift_cnt[0]+jitter_cnt[0]!=0) begin $display("ERROR: CH0 E2E");errors=errors+1;end
      if(period_cnt[1]!=2 || period_ticks[1*W+:W]!=6 || short_cnt[1]!=2) begin $display("ERROR: CH1 E2E");errors=errors+1;end
      if(period_cnt[2]!=2 || period_ticks[2*W+:W]!=14 || long_cnt[2]!=2) begin $display("ERROR: CH2 E2E");errors=errors+1;end
      if(period_cnt[3]!=3 || period_ticks[3*W+:W]!=13 || jump_cnt[3]!=1 || drift_cnt[3]!=2 || jitter_cnt[3]!=1 ||
         min_period[3*W+:W]!=10 || max_period[3*W+:W]!=14 || p2p[3*W+:W]!=4 || adj_diff[3*W+:W]!=1) begin $display("ERROR: CH3 E2E");errors=errors+1;end

      // 8 位端到端计数器跨越 255->0，两个上升沿相隔 20 tick。
      @(negedge clk); wrap_rst_n=1;
      while(wrap_ts!=8'd245) @(negedge clk);
      wrap_async=1; repeat(2) @(negedge clk); wrap_async=0;
      repeat(18) @(negedge clk); wrap_async=1; repeat(2) @(negedge clk); wrap_async=0;
      repeat(8) @(posedge clk); #2;
      if(wrap_period_valid) begin end
      if(wrap_period!=8'd20 || wrap_long_count!=1 || wrap_rise_count<2 || !(wrap_second_rise<wrap_first_rise)) begin
        $display("ERROR: E2E timestamp wrap period=%0d long=%0d rises=%0d ts=%0d/%0d",wrap_period,wrap_long_count,wrap_rise_count,wrap_first_rise,wrap_second_rise); errors=errors+1; end

      @(negedge clk); rst_n=0; repeat(3) @(posedge clk); #2;
      if(event_valid!=0 || stats_valid!=0) begin $display("ERROR: E2E runtime reset");errors=errors+1;end
      if(errors==0) begin $display("TEST PASSED: timing_diagnostic end-to-end self-check completed");$finish;end
      else $fatal(1,"TEST FAILED: %0d error(s)",errors);
    end
    initial begin #500000; $fatal(1,"TEST FAILED: timeout"); end
endmodule
