module txrx #(
    parameter int MSG_SIZE = 12,
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000,
    parameter int FIFO_DEPTH = 24
)(
    input  logic       clk,
    input  logic       rst,

    input  logic       enable,
    input  logic [1:0] keys,
    input  logic [1:0] sw,
    input  logic [2:0] data_in,
    input  logic [1:0] my_addr,
    input  logic [1:0] next_hop,

    output logic [1:0] dst_addr,
    output wire  [2:0] data_out,
    output wire        stoped,
    output wire [15:0] disp_data,
    output wire        stored_valid
);
    typedef enum logic [1:0] {
        IDLE     = 2'd0,
        LISTEN   = 2'd1,
        MK_MSG   = 2'd2,
        STOPPING = 2'd3
    } state_t;
    state_t state, new_state;

    logic [1:0] mode_key_press;
    key_handler #(
        .KEY_NUM(2),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .ACTIVE_LOW(0)
    ) mode_buttons (
        .clk(clk),
        .rst(rst),
        .keys(keys),
        .key_press(mode_key_press)
    );

    logic start_armed;
    always_ff @(posedge clk) begin
        if (rst)
            start_armed <= 1'b1;
        else if (!enable)
            start_armed <= 1'b1;
        else if (state == IDLE && enable && start_armed)
            start_armed <= 1'b0;
    end

    wire manual_start = (state == LISTEN) && mode_key_press[0] &&
                        !mode_key_press[1];
    wire stop_request = (state == LISTEN) && mode_key_press[1];
    wire processing = (state == LISTEN || state == MK_MSG);
    // No packet may enter a transmitter on the STOP key's sampling edge.
    wire allow_new_tx = processing && !stop_request;

    wire [MSG_SIZE-1:0] manual_packet;
    wire manual_valid, manual_busy;
    logic manual_ready;
    wire manual_handshake = manual_valid && manual_ready;

    wire tx_ready [0:2];
    wire all_tx_idle = tx_ready[0] && tx_ready[1] && tx_ready[2];

    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= new_state;
    end

    always_comb begin
        new_state = state;
        case (state)
            IDLE:
                if (enable && start_armed)
                    new_state = LISTEN;
            LISTEN:
                if (mode_key_press[1])
                    new_state = STOPPING;
                else if (mode_key_press[0])
                    new_state = MK_MSG;
            MK_MSG:
                // Manual mode cannot be interrupted using the stop key.
                // Leave only when the packet was really accepted.
                if (manual_handshake)
                    new_state = LISTEN;
            STOPPING:
                if (all_tx_idle)
                    new_state = IDLE;
            default: new_state = IDLE;
        endcase
    end

    // In STOPPING receivers are cleared, transmitters still run.
    // In IDLE all datapath queues and transmitters are cleared.
    wire rx_rst  = rst || (state == IDLE) || (state == STOPPING);
    wire tx_rst  = rst || (state == IDLE);
    wire man_rst = rst || (state == IDLE) || (state == STOPPING);

    pac_maker #(
        .MSG_SIZE(MSG_SIZE),
        .CLK_MHZ(CLK_MHZ),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) creator (
        .clk(clk),
        .rst(man_rst),
        .start(manual_start),
        .keys(keys),
        .sw(sw),
        .my_addr(my_addr),
        .packet(manual_packet),
        .busy(manual_busy),
        .valid(manual_valid),
        .ready(manual_ready)
    );

    wire [MSG_SIZE-1:0] rx_packet [0:2];
    wire rx_valid [0:2], rx_ready [0:2];
    wire [MSG_SIZE-1:0] rx_head [0:2];
    wire rx_full [0:2], rx_empty [0:2];
    logic rx_pop [0:2];

    wire [MSG_SIZE-1:0] tx_head [0:2];
    wire tx_full [0:2], tx_empty [0:2];
    logic tx_push [0:2];
    logic tx_pop [0:2];
    wire [MSG_SIZE-1:0] tx_write_data [0:2];
    wire [2:0] tx_serial;

    genvar p;
    generate for (p = 0; p < 3; p = p + 1) begin : port_gen
        receiver #(
            .MSG_SIZE(MSG_SIZE))
        u_rx (
            .clk(clk),
            .rst(rx_rst),
            .data_in(data_in[p]),
            .valid(rx_valid[p]),
            .ready(rx_ready[p]),
            .packet(rx_packet[p])
        );

        assign rx_ready[p] = allow_new_tx && !rx_full[p];
        fifo #(
            .width(MSG_SIZE),
            .depth(FIFO_DEPTH))
        u_rx_fifo (
            .clk(clk),
            .rst(rx_rst),
            .push(rx_valid[p] && rx_ready[p]),
            .pop(rx_pop[p]),
            .write_data(rx_packet[p]),
            .read_data(rx_head[p]),
            .full(rx_full[p]),
            .empty(rx_empty[p])
        );

        fifo #(
            .width(MSG_SIZE),
            .depth(FIFO_DEPTH))
        u_tx_fifo (
            .clk(clk),
            .rst(tx_rst),
            .push(tx_push[p]),
            .pop(tx_pop[p]),
            .write_data(tx_write_data[p]),
            .read_data(tx_head[p]),
            .full(tx_full[p]),
            .empty(tx_empty[p])
        );
        // On STOPPING no new packet starts, but the current one finishes.
        always_comb begin
            tx_pop[p] = allow_new_tx && tx_ready[p] && !tx_empty[p];
        end
        transmitter #(
        .MSG_SIZE(MSG_SIZE))
        u_tx (
            .clk(clk),
            .rst(tx_rst),
            .valid(allow_new_tx && !tx_empty[p]),
            .ready(tx_ready[p]),
            .packet(tx_head[p]),
            .data_out(tx_serial[p])
        );
        assign tx_write_data[p] = edited_packet;
    end endgenerate

    // Suppress the serial output only after entering IDLE.
    assign data_out = (state == IDLE) ? 3'b000 : tx_serial;

    // Input round-robin arbiter, with manual packet priority.
    logic [1:0] rr;
    logic selected_rx_valid;
    logic [1:0] selected_rx;
    logic [MSG_SIZE-1:0] selected_packet;
    logic selected_valid, accepted;
    wire [MSG_SIZE-1:0] edited_packet;
    wire is_local;
    wire route_ok;

    always_comb begin
        selected_rx_valid = 1'b0;
        selected_rx = 2'd0;
        for (int off = 0; off < 3; off = off + 1) begin
            int idx;
            idx = (int'(rr) + off) % 3;
            if (!selected_rx_valid && !rx_empty[idx]) begin
                selected_rx_valid = 1'b1;
                selected_rx = 2'(idx);
            end
        end
    end

    always_comb begin
        selected_valid = manual_valid || selected_rx_valid;
        selected_packet = '0;
        if (manual_valid)
            selected_packet = manual_packet;
        else if (selected_rx_valid)
            selected_packet = rx_head[selected_rx];
    end

    assign edited_packet = {3'b110, selected_packet[8:7], 1'b0,
                            selected_packet[5:2], 2'b10};
    assign dst_addr = selected_valid ? edited_packet[5:4] : 2'b00;
    assign is_local = (dst_addr == my_addr);
    assign route_ok = (next_hop < 2'd3);

    always_comb begin
        accepted = 1'b0;
        if (allow_new_tx && selected_valid) begin
            if (is_local)
                accepted = 1'b1;
            else if (route_ok && !tx_full[next_hop])
                accepted = 1'b1;
        end
    end

    always_comb begin
        manual_ready = accepted && manual_valid;
        for (int i = 0; i < 3; i = i + 1) begin
            rx_pop[i] = accepted && !manual_valid && selected_rx_valid &&
                        (selected_rx == i);
            tx_push[i] = accepted && !is_local && route_ok &&
                         (next_hop == i);
        end
    end

    logic [MSG_SIZE-1:0] stored_packet;
    logic stored_flag;
    always_ff @(posedge clk) begin
        if (rst || state == IDLE) begin
            rr <= 2'd0;
            stored_packet <= '0;
            stored_flag <= 1'b0;
        end else begin
            if (accepted && !manual_valid && selected_rx_valid)
                rr <= (selected_rx == 2'd2) ? 2'd0 : selected_rx + 1'b1;
            if (accepted && is_local) begin
                stored_packet <= edited_packet;
                stored_flag <= 1'b1;
            end
        end
    end

    assign stored_valid = stored_flag;
    assign disp_data = {{(16-MSG_SIZE){1'b0}}, stored_packet};
    assign stoped = (state == IDLE);
endmodule


/* module txrx 
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
        CONFIGING_PACK  = 5'd3,
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

wire receiver_valid [0:2],
wire receiver_ready [0:2],
logic [MSG_SIZE - 1:0] recieved_packet [0:2]

receiver p_in1 (
    .clk(clk),
    .rst(rst),

    .data_in(data_in),

    .valid(receiver_valid[0]),
    .ready(receiver_ready[0]),

    .packet(recieved_packet[0])
);

logic[2:0] looper;

always_ff @(posedge clk) begin
    if (rst) begin
        looper <= 3'b001;
    end else begin
        looper <= {looper[1:0], looper[2]};
    end
end

wire[MSG_SIZE - 1:0] rx_fifo_head[0:2];
wire rx_fifo_full[0:2], rx_fifo_empty[0:2];;
assign receiver_ready[0] = !rx_fifo_full[0];

fifo input_fifo_0 # (
    .width(MSG_SIZE),
    .depth(2 * MSG_SIZE)
) (
    .clk(clk),
    .rst(rst),

    .push(receiver_valid[0]),
    .pop(looper[0]),

    .write_data(recieved_packet[0]),
    .read_data(rx_fifo_head[0]),

    .full(rx_fifo_full[0]),
    .empty(rx_fifo_empty[0])
)

//------------cicle_mux---------------

wire[MSG_SIZE -1:0] recomposer_input;
wire                recomposer_valid;

always_comb begin
    case (looper)
        3'b100: begin
            recomposer_input = rx_fifo_head[2];
            recomposer_valid = !rx_fifo_empty[2];
        end
        3'b010: begin
            recomposer_input = rx_fifo_head[1];
            recomposer_valid = !rx_fifo_empty[1];
        end
        3'b001: begin
            recomposer_input = rx_fifo_head[0];
            recomposer_valid = !rx_fifo_empty[0];
        end
        default: begin
            recomposer_input = rx_fifo_head[2];
            recomposer_valid = !rx_fifo_empty[2];
        end
    endcase
end

//------------Recomposer--------------

wire[MSG_SIZE-1:0] recomposed_packet;

assign recomposed_packet = {3'b110, 
                            my_addr, 
                            1'b0, recomposer_input[5:2], 
                            2'b10};

///----------Mux of input packet manual or input----

wire[MSG_SIZE-1:0] created_packet;
wire created_packet_valid;
wire creator_busy;
wire creator_start;

pac_maker pac_creator #(
    .MSG_SIZE(MSG_SIZE)
) (
    .clk(clk),
    .rst(rst),
    
    .keys(keys),
    .sw(sw),

    .my_addr(my_addr),
    .packet(created_packet),

    .busy(creator_busy),
    .valid(created_packet_valid),

    .start(creator_start)
);

//------------FSM for pack creation mode-------

assign creator_start = state == MK_MSG;

always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
    end else begin
        state <= new_state;
    end
end

always_comb begin
    new_state = state;
    case (state) 
        IDLE: if (enable) new_state = LISTEN;

        LISTEN: begin 
            if (stoped) new_state = IDLE;
            if (keys[0]) new_state = MK_MSG;
        end

        MK_MSG: if (created_packet_valid) new_state = LISTEN;
    endcase
end

//--------------Pack source mux-------------------------------------------------

wire[MSG_SIZE-1:0] pack_to_send;
wire    can_transmitt_mux;

always_comb begin
    if (created_packet_valid) begin
        pack_to_send = created_packet;
    end else begin
        pack_to_send = recieved_packet;
    end
end

//------------Pack analazer-----------------------------------------------------

///add storage for received packets;

wire [MSG_SIZE - 1:0] pack_to_storage;
logic[MSG_SIZE - 1:0] stored_packet;
logic new_pack_got;

always_ff @(posedge clk) begin
    if (rst) begin 
        stored_packet <= '0;
    end else begin
        if (new_pack_got) begin
            stored_packet <= pack_to_storage;
        end
    end
end

assign new_pack_got = pack_to_send[8:7] == pack_to_send[5:4];

wire showld_send;
assign showld_send = new_pack_got ? 1'b0 : 1'b1;
wire[MSG_SIZE - 1:0] tx_fifo_tail[0:2];
wire                 tx_fifo_push[0:2];

assign dst_addr = new_pack_got[5:4];

always_comb begin
    tx_fifo_tail[dst_addr] = pack_to_send;
    tx_fifo_push[dst_addr] = showld_send;
end

wire    transmitter_is_ready[0:2];
wire    pack_to_transmitter[0:2];
wire    tx_fifo_full[0:2];
wire    tx_fifo_empty[0:2];

fifo tx_fifo_0 #(
    .width(MSG_SIZE),
    .depth(2 * MSG_SIZE)
) (
    .clk(clk),
    .rst(rst),

    .push(showld_send[0]),
    .full(tx_fifo_full[0]),
    .write_data(tx_fifo_tail[0]),

    .read_data(pack_to_transmitter[0]),
    .pop(transmitter_is_ready[0])
);

transmitter tx_0 #(
    .MSG_SIZE(MSG_SIZE)
) (
    .clk(clk),
    .rst(rst),

    .valid(!tx_fifo_empty),
    .ready(showld_send[0]),

    .data_out(data_out),
    .packet(pack_to_transmitter[0])
);

endmodule