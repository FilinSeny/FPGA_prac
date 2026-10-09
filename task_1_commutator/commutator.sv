module commutator #(
    parameter int CLK_MHZ = 50,
    parameter int DEBOUNCE_CYCLES = CLK_MHZ * 20_000
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [1:0] keys,
    input  logic [2:0] switch_reg,
    input  logic       data_in,
    
    output logic       data_out,
    output logic [7:0] abcdefgh,
    output wire  [3:0] digit
);
    typedef enum logic [4:0] {
        IDLE       = 5'd0,
        CONFIG_DST = 5'd1,
        CONFIG_HOP = 5'd2,
        UPD_RAM    = 5'd3,
        LISTEN     = 5'd4,
        GET_PACK   = 5'd5,
        LOAD_HOP   = 5'd6,
        SEND_PACK  = 5'd7,
        SHOW_RAM   = 5'd9
    } state_t;

    state_t     state, new_state;
    logic [2:0] dst_reg, hop_reg_w;
    wire  [2:0] next_hop, my_addr;
    wire valid_mem;
    wire we_mem = (state == UPD_RAM) && !rst;

    localparam int KEY_COUNT_WIDTH = (DEBOUNCE_CYCLES > 1)
                                  ? $clog2(DEBOUNCE_CYCLES) : 1;
    localparam logic [KEY_COUNT_WIDTH-1:0] KEY_COUNT_MAX =
        KEY_COUNT_WIDTH'(DEBOUNCE_CYCLES - 1);
    (* async_reg = "true" *) logic[1:0] key_meta, key_sync;
    logic   [1:0]   key_stable, key_previous;
    logic   [KEY_COUNT_WIDTH-1:0] key_count[2];
    wire    [1:0]   key_press = key_stable & ~key_previous;

    always_ff @(posedge clk) begin
        if (rst) begin
            key_meta     <= 1'b0;
            key_sync     <= 1'b0;
            key_stable   <= 1'b0;
            key_previous <= 1'b0;
            
            for (int i = 0; i < 2; i++) begin
                key_count[i] <= '0;
            end
        end else begin
            key_meta     <= keys;
            key_sync     <= key_meta;
            key_previous <= key_stable;
           
            for (int i = 0; i < 2; i++) begin
                if (key_sync[i] == key_stable[i]) begin
                    key_count[i] <= '0;
                end else if (key_count[i] == KEY_COUNT_MAX) begin
                    key_stable[i] <= key_sync[i];
                    key_count[i]  <= '0;
                end else begin
                    key_count[i] <= key_count[i] + 1'b1;
                end
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
            dst_reg   <= '0;
            hop_reg_w <= '0;
            ram_addr  <= '0;  
        end else begin
            if (state == SHOW_RAM)
                ram_addr <= next_ram_addr;
            else 
                ram_addr <= '0;
            if (state == CONFIG_DST)
                dst_reg <= switch_reg;
            if (state == CONFIG_HOP)
                hop_reg_w <= switch_reg;
            if (state == SHOW_RAM)
                dst_reg <= ram_addr;
        end
    end

    always_comb begin
        new_state = state;
        next_ram_addr = ram_addr;
        case (state)
            IDLE:       begin
                if (key_press[0]) new_state = CONFIG_DST;
                if (key_press[1]) new_state = SHOW_RAM;
            end
            CONFIG_DST: if (key_press[0]) new_state = CONFIG_HOP;
            CONFIG_HOP: if (key_press[0]) new_state = UPD_RAM;
            UPD_RAM:    new_state = IDLE;
            LISTEN:     if (key_press[0]) new_state = IDLE;
            SHOW_RAM:   begin
                if (key_press[0]) begin
                    if (ram_addr == 3) new_state = IDLE;
                    else begin 
                        next_ram_addr = ram_addr + 1;
                    end
                end 
            end
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
    always_comb begin
        case (state)
             CONFIG_DST, CONFIG_HOP:  begin
                display_number = {4'd0, state[3:0], 4'd0, 1'b0, display_addr};
             end
             SHOW_RAM:
                display_number =  {4'd0, 
                                   state[3:0],
                                   2'b0, ram_addr,
                                   1'b0, next_hop};
            default:   
                display_number = {4'd0, state[3:0], 8'd0};
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
endmodule