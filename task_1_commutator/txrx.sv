module txrx 
# (
    parameter int MSG_SIZE = 12
)(
    input wire          clk,
    input wire          rst,
    input wire          enable,

    input logic[1:0]    keys,
    input logic[1:0]    sw,

    input logic         data_in,

    input logic[1:0]    next_hop,

    output logic[1:0]   dst_addr,

    output logic        data_out,

    output logic        stoped,
    output logic[15:0]  disp_data
);

typedef enum logic [4:0] {
        IDLE            = 5'd0,
        LISTEN          = 5'd1,
        MK_MSG          = 5'd2,
        CONFIG_HOP      = 5'd3,
        CONF_PAYLOAD    = 5'd4,
        SEND_PACK       = 5'd5
} state_t;

logic transmitter_valid [0:2];
logic[MSG_SIZE - 1:0] packet_to_transmit[0:2];
wire tx_ready[0:2];

transmitter p_out0 (
    .clk(clk),
    .rst(rst),

    .valid(transmitter_valid[0]),
    .ready(tx_ready[0]),

    .packet(packet_to_transmit[0]),

    .data_out(data_out)
);

receiver p_in1 (
    .clk(clk),
    .rst(rst),

    
);



endmodule