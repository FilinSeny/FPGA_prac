module commutator #(
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [1:0] keys,       // Active high; keys[0] confirms the current step.
    input  logic [2:0] switch_reg,
    output wire  [7:0] abcdefgh,   // Active-low segments, order a b c d e f g dp.
    output wire  [3:0] digit       // Active-low digit enables; digit[0] is rightmost.
);
    typedef enum logic [4:0] {
        IDLE       = 5'd0,
        CONFIG_DST = 5'd1,
        CONFIG_HOP = 5'd2,
        UPD_RAM    = 5'd3,
        LISTEN     = 5'd4,
        GET_PACK   = 5'd5,
        LOAD_HOP   = 5'd6,
        SEND_PACK  = 5'd7
    } state_t;

    state_t state, new_state;
    logic [2:0] dst_reg, hop_reg_w;
    wire  [2:0] next_hop, my_addr;
    wire valid_mem;
    wire we_mem = (state == UPD_RAM) && !rst;

    // Synchronize and debounce the confirmation button.
    // Holding it down must not advance through several states.
    localparam int KEY_COUNT_WIDTH = (DEBOUNCE_CYCLES > 1)
                                  ? $clog2(DEBOUNCE_CYCLES) : 1;
    localparam logic [KEY_COUNT_WIDTH-1:0] KEY_COUNT_MAX =
        KEY_COUNT_WIDTH'(DEBOUNCE_CYCLES - 1);
    (* async_reg = "true" *) logic key_meta, key_sync;
    logic key_stable, key_previous;
    logic [KEY_COUNT_WIDTH-1:0] key_count;
    wire key_press = key_stable && !key_previous;

    always_ff @(posedge clk) begin
        if (rst) begin
            key_meta     <= 1'b0;
            key_sync     <= 1'b0;
            key_stable   <= 1'b0;
            key_previous <= 1'b0;
            key_count    <= '0;
        end else begin
            key_meta     <= keys[0];
            key_sync     <= key_meta;
            key_previous <= key_stable;
            if (key_sync == key_stable) begin
                key_count <= '0;
            end else if (key_count == KEY_COUNT_MAX) begin
                key_stable <= key_sync;
                key_count  <= '0;
            end else begin
                key_count <= key_count + 1'b1;
            end
        end
    end

    ram #(.ADDR_WIDTH(3)) addr_tab (
        .clk(clk),
        .rst(rst),
        .addr(dst_reg),
        .data_in(hop_reg_w),
        .data_out(next_hop),
        .loopback(my_addr),
        .valid(valid_mem),
        .we(we_mem)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            dst_reg   <= '0;
            hop_reg_w <= '0;
        end else begin
            state <= new_state;
            if (state == CONFIG_DST)
                dst_reg <= switch_reg;
            if (state == CONFIG_HOP)
                hop_reg_w <= switch_reg;
        end
    end

    always_comb begin
        new_state = state;
        case (state)
            IDLE:       if (key_press) new_state = CONFIG_DST;
            CONFIG_DST: if (key_press) new_state = CONFIG_HOP;
            CONFIG_HOP: if (key_press) new_state = UPD_RAM;
            UPD_RAM:    new_state = IDLE;
            LISTEN:     if (key_press) new_state = IDLE;
            // Packet processing and entry into LISTEN are still to be implemented.
            default:    new_state = IDLE;
        endcase
    end

    logic [2:0] display_addr;
    wire [15:0] display_number;
    always_comb begin
        case (state)
            CONFIG_DST, CONFIG_HOP: display_addr = switch_reg;
            default:                display_addr = dst_reg;
        endcase
    end

    // Left to right: state tens, state units, 0, address.
    // State codes are currently 0..7, so the tens digit is always zero.
    assign display_number = {4'd0, state[3:0], 4'd0, 1'b0, display_addr};

    seven_seg_disp #(.w_digit(4), .clk_mhz(CLK_MHZ)) display (
        .clk(clk),
        .rst(rst),
        .number(display_number),
        .dots(4'b0000),
        .abcdefgh(abcdefgh),
        .digit(digit)
    );
endmodule