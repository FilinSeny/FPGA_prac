module commutator #(
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [1:0] keys,
    input  logic [1:0] switch_reg,
    input  logic [2:0] data_in,
    
    output logic [2:0] data_out,
    output logic [7:0] abcdefgh,
    output wire  [3:0] digit
);
    typedef enum logic [4:0] {
        IDLE       = 5'd0,
        DATA_RW    = 5'd1,
        CONFIG_DST = 5'd2,
        CONFIG_HOP = 5'd3,
        UPD_RAM    = 5'd4,
        LISTEN     = 5'd5,
        GET_PACK   = 5'd6,
        LOAD_HOP   = 5'd7,
        SEND_PACK  = 5'd8,
        SHOW_RAM   = 5'd9,
        TXRX_MODE  = 5'd12
    } state_t;

    state_t     state, new_state;
    logic [1:0] dst_reg, hop_reg_w;
    wire  [1:0] next_hop, my_addr;
    wire valid_mem;
    wire we_mem = (state == UPD_RAM) && !rst;

    logic [1:0] key_press;

    wire        txrx_enable;

    wire [1:0]  port;
    assign port = next_hop;

    wire        txrx_stoped;
    wire [15:0] txrx_disp;
    wire        has_stored_packet;
    wire [1:0]  tx_dsp;

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

    logic [1:0] sync_dst_reg, async_dst;
    always_comb begin
        case (state)
            TXRX_MODE, LISTEN:
                dst_reg = tx_dsp;
            default:
                dst_reg = sync_dst_reg;
        endcase
    end

    logic[1:0] dst_reg_, hop_reg_w_, next_hop_, my_addr_;
    logic valid_mem_, we_mem_;
    ram #(
        .ADDR_WIDTH(2)
    ) addr_tab (
        .clk(clk),
        .rst(rst),
        .addr(dst_reg),
        .data_in(hop_reg_w),
        .data_out(next_hop),
        .loopback(my_addr),
        .valid(valid_mem),
        .we(we_mem)
    );

    logic[1:0]  ram_addr, next_ram_addr;

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= IDLE; 
        end else begin
            state <= new_state;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            sync_dst_reg   <= '0;
            hop_reg_w <= '0;
            ram_addr  <= '0;  
        end else begin
            if (state == SHOW_RAM)
                ram_addr <= next_ram_addr;
            else 
                ram_addr <= '0;
            if (state == CONFIG_DST)
                sync_dst_reg <= switch_reg;
            if (state == CONFIG_HOP)
                hop_reg_w <= switch_reg;
            if (state == SHOW_RAM)
                sync_dst_reg <= ram_addr;
        end
    end

    always_comb begin
        new_state = state;
        next_ram_addr = ram_addr;
        case (state)
            IDLE: begin
                if (key_press[0]) new_state = DATA_RW;
                if (key_press[1]) new_state = TXRX_MODE;
            end
            DATA_RW:       begin
                if (key_press[0]) new_state = CONFIG_DST;
                if (key_press[1]) new_state = SHOW_RAM;
            end
            CONFIG_DST: if (key_press[0]) new_state = CONFIG_HOP;
            CONFIG_HOP: if (key_press[0]) new_state = UPD_RAM;
            UPD_RAM:    new_state = IDLE;
            LISTEN:     if (txrx_stoped) new_state = IDLE;
            SHOW_RAM:   begin
                if (key_press[0]) begin
                    if (ram_addr == 3) new_state = IDLE;
                    else begin 
                        next_ram_addr = ram_addr + 1;
                    end
                end 
            end
            TXRX_MODE: begin
                if (key_press[0]) new_state = LISTEN;

            end

            ///default:    new_state = IDLE;
        endcase
    end

    assign txrx_enable = (state == LISTEN);

    logic [2:0] display_addr;
    logic [15:0] display_number;
    always_comb begin
        case (state)
            CONFIG_DST, CONFIG_HOP: display_addr = switch_reg;
            default:                display_addr = sync_dst_reg;
        endcase
    end

    wire [3:0] state_tens, state_ones;
    assign state_tens = state / 10;
    assign state_ones = state % 10; 

    // Left to right: state tens, state units, 0, address.
    // State codes are currently 0..7, so the tens digit is always zero.
    always_comb begin
        case (state)
             CONFIG_DST, CONFIG_HOP:  begin
                display_number = {state_tens, state_ones, 4'd0, 1'b0, display_addr};
             end
             SHOW_RAM:
                display_number =  {state_tens, 
                                   state_ones,
                                   2'b0, ram_addr,
                                   2'b0, next_hop};
            LISTEN:
                display_number = txrx_disp;
            default:   
                display_number = {state_tens, state_ones, 8'd0};
        endcase
    end

    seven_seg_disp #(.w_digit(4), .clk_mhz(CLK_MHZ)) display (
        .clk(clk),
        .rst(rst),
        .number(display_number),
        .dots(4'b0000),
        .abcdefgh(abcdefgh),
        .digit(digit)
    );

    txrx #(
        .CLK_MHZ(CLK_MHZ),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) packet_processor (
        .clk(clk),
        .rst(rst),

        .enable(txrx_enable),
        .keys(key_press),
        .sw(switch_reg[1:0]),
        .data_in(data_in),
        .my_addr(my_addr),
        .port(port),

        .data_out(data_out),
        .stoped(txrx_stoped),
        .disp_data(txrx_disp),

        .stored_valid(has_stored_packet),
        .dst_addr(tx_dsp)
    );


endmodule