module pac_maker #(
    parameter int MSG_SIZE = 12,
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,

    input  logic [1:0]           keys,
    input  logic [1:0]           sw,

    input  wire [1:0]            my_addr,

    input  wire                  ready,

    output wire [MSG_SIZE-1:0]   packet,
    output logic                 busy,
    output logic                 valid,

    output logic [MSG_SIZE-1:0]   pac_maker_disp
);

    logic [1:0] key_press;
    assign key_press = keys;

    /*key_handler #(
        .KEY_NUM(2),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .ACTIVE_LOW(0)
    ) buttons (
        .clk(clk),
        .rst(rst),
        .keys(keys),
        .key_press(key_press)
    );*/

    logic [1:0] target_addr;
    logic [1:0] payload;

    typedef enum logic [2:0] {
        IDLE           = 3'd0,
        CONFIG_DST     = 3'd1,
        CONFIG_PAYLOAD = 3'd2,
        DONE           = 3'd3
    } state_t;

    state_t state, new_state;

    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= new_state;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            payload     <= '0;
            target_addr <= '0;
        end else begin
            if (state == CONFIG_DST && key_press[0])
                target_addr <= sw;

            if (state == CONFIG_PAYLOAD && key_press[0])
                payload <= sw;
        end
    end

    assign valid = (state == DONE);
    assign busy  = (state != IDLE);

    always_comb begin
        new_state = state;
        pac_maker_disp = '0;
        case (state)
            IDLE: begin
                pac_maker_disp = {4'hc, 4'hd, 8'd16};
                if (start) begin
                    new_state = CONFIG_DST;
                end
            end
            CONFIG_DST: begin
                pac_maker_disp = {4'hc, 4'hd, 6'd2, sw};
                if (key_press[0])
                    new_state = CONFIG_PAYLOAD;
            end
            CONFIG_PAYLOAD: begin
                pac_maker_disp = {4'hc, 4'hd, 6'd3, sw};
                if (key_press[0])
                    new_state = DONE;
            end
            DONE: begin
                pac_maker_disp = {4'hc, 4'hd, 4'd3, 4'd0};
                if (ready)
                    new_state = IDLE;
            end
        endcase
    end

    assign packet = {
        3'b110,
        my_addr,
        1'b0,
        target_addr,
        payload,
        2'b10
    };

endmodule