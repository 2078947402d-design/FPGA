`timescale 1ns / 1ps

// Debug-only stimulus. All registers use FCLK0; test_ch is data, never a clock.
module internal_test_wave_gen (
    input wire clk,
    input wire rst_n,
    output wire [3:0] test_ch
);
    genvar ch;
    generate
        for (ch=0; ch<4; ch=ch+1) begin : gen_wave
            localparam integer HALF_PERIOD = (ch==0) ? 25000 :
                                             (ch==1) ? 12500 :
                                             (ch==2) ? 5000 : 2500;
            localparam integer COUNT_WIDTH = $clog2(HALF_PERIOD);
            reg [COUNT_WIDTH-1:0] count;
            reg level;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    count <= 0;
                    level <= 1'b0;
                end else if (count == HALF_PERIOD-1) begin
                    count <= 0;
                    level <= ~level;
                end else begin
                    count <= count + 1'b1;
                end
            end
            assign test_ch[ch] = level;
        end
    endgenerate
endmodule
