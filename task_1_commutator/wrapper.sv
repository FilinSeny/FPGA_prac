module wrapper #(
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
) (
    input  wire       CLK,
    input  wire       RESET,     
    input  wire [1:0] KEY,  
    input  wire [1:0] SW,

    output wire       BUZZER,
    output wire [2:0] DATA_OUT,
    input  wire [2:0] DATA_IN,
    output wire [3:0] LED,
    output wire [7:0] SEG,
    output wire [3:0] DIG
);

top #(
    .CLK_MHZ(CLK_MHZ),
    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
) u_top (
    .CLK(CLK),
    .RESET(RESET),
    .KEY(KEY),
    .SW(SW),
    .DATA_OUT({DATA_OUT[2:1], BUZZER}),
    .LED(LED),
    .SEG(SEG),
    .DIG(DIG)
);

endmodule