module pac_maker #(
    parameter int MSG_SIZE = 12,
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
)(
    input wire          clk,
    input wire          rst,
    input wire          start,

    input logic[1:0]    keys,
    input logic[1:0]    sw,

    input  wire[1:0]    my_addr,

    output wire[MSG_SIZE - 1: 0]    packet,
    output logic                    busy,
    output logic                    valid
);

 logic [1:0] key_press;

    key_handler #(
        .KEY_NUM(2),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .ACTIVE_LOW(0)
    ) buttons (
        .clk(clk),
        .rst(rst),
        .keys(keys),
        .key_press(key_press)
    );

logic[1:0] target_addr;
logic[1:0] payload;

typedef enum logic [2:0] {
    IDLE            = 3'd0,
    CONFIG_DST      = 3'd1,
    CONFIG_PAYLOAD  = 3'd2,
    DONE            = 3'd3
} state_t;

state_t state, new_state;

always_ff @(posedge clk) begin
    if (rst) begin
        state     <= IDLE; 
    end else begin
        state <= new_state;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        payload   <= '0;
        target_addr <= '0;
    end else begin
        if (state == CONFIG_DST)
            target_addr <= sw;
        if (state == CONFIG_PAYLOAD)
            payload <= sw;
    end
 end

assign valid = (state == DONE);
assign busy  = (state != IDLE);

always_comb begin
    new_state = state;
    case (state) 
        IDLE: if (start) new_state = CONFIG_DST;
        CONFIG_DST: if (key_press[0]) new_state = CONFIG_PAYLOAD;
        CONFIG_PAYLOAD: if (key_press[0]) new_state = DONE;
        DONE: if (ready) new_state = IDLE;
    endcase
end

assign packet = {3'b110, my_addr, 1'b0, target_addr, payload, 2'b10};

endmodule