module top #(
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
) (
    input  wire       CLK,
    input  wire       RESET,     // Board reset button: active low.
    input  wire [1:0] KEY,    // Board buttons: active low.
    input  wire [1:0] SW,

    output wire       DATA_OUT,
    output wire       DATA_IN,
    output wire [3:0] LED,
    output wire [7:0] SEG,
    output wire [3:0] DIG
);

    wire data_in, data_out;
    assign data_in = DATA_IN;
    assign data_out = DATA_OUT;

    (* async_reg = "true" *) logic [1:0] reset_pipe = 2'b11;
    always_ff @(posedge CLK or negedge RESET) begin
        if (!RESET)
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0], 1'b0};
    end
    wire rst = reset_pipe[1];

    (* async_reg = "true" *) logic [2:0] address_meta, address_bits;
    always_ff @(posedge CLK) begin
        if (rst) begin
            address_meta <= '0;
            address_bits <= '0;
        end else begin
            address_meta[1:0] <= ~SW[1:0];
            address_bits[1:0] <= address_meta[1:0];
        end
    end

    wire [7:0] abcdefgh;
    wire [3:0] digit;

    commutator #(
        .CLK_MHZ(CLK_MHZ), .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_commutator (
        .clk(CLK),
        .rst(rst),
        .keys({~KEY[1], ~KEY[0]}),
        .switch_reg(address_bits),
        .abcdefgh(SEG),
        .digit(DIG),
        .data_in(data_in),
        .data_out(data_out)
    );

    ///assign SEG = ~abcdefgh;
    ///assign DIG = ~digit;
    assign LED = ~{rst, address_bits};
endmodule

/*
module top #(
    parameter int CLK_MHZ = 50
) (
    input  logic       CLK,
    input  logic       RESET,

    output logic [7:0] SEG,
    output logic [3:0] DIG
);

    logic [2:0] loopback;
    logic [2:0] data_out;
    logic valid;

    // Your original RAM module
    ram #(
        .ADDR_WIDTH(3)
    ) addr_tab (
        .clk(CLK),
        .rst(~RESET),
        .addr(3'd0),
        .data_in(3'd0),
        .we(1'b0),
        .data_out(data_out),
        .loopback(loopback),
        .valid(valid)
    );

    // Display loopback: 000X
    wire [15:0] display_number = {
        12'd0,
        1'b0,
        loopback
    };

    seven_seg_disp #(
        .w_digit(4),
        .clk_mhz(CLK_MHZ)
    ) display (
        .clk(CLK),
        .rst(~RESET),
        .number(display_number),
        .dots(4'b0000),
        .abcdefgh(SEG),
        .digit(DIG)
    );

endmodule*/