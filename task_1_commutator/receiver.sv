module receiver #(
    parameter int MSG_SIZE = 12
) (
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 data_in,

    output logic                 valid,
    output logic [MSG_SIZE-1:0]  packet,
    input  logic                 ready
);

    localparam int COUNT_WIDTH =
        (MSG_SIZE > 1) ? $clog2(MSG_SIZE + 1) : 1;

    typedef enum logic [2:0] {
        LISTEN     = 3'd0,
        HEAD       = 3'd1,
        RECEIVE    = 3'd2,
        PACK_TAKEN = 3'd3
    } state_t;

    state_t state;

    logic [COUNT_WIDTH-1:0] counter;
    logic [MSG_SIZE-1:0] shift_reg;

    assign packet = shift_reg;
    assign valid  = (state == PACK_TAKEN);

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= LISTEN;
            counter   <= '0;
            shift_reg <= '0;
        end else begin

            case (state)

                // Wait for first start bit
                LISTEN: begin
                    if (data_in) begin
                        shift_reg <= '0;
                        state <= HEAD;
                    end
                end

                // Check second start bit
                HEAD: begin
                    if (data_in) begin
                        shift_reg <= {{(MSG_SIZE-2){1'b0}}, 2'b11};
                        counter <= MSG_SIZE - 2;
                        state <= RECEIVE;
                    end else begin
                        state <= LISTEN;
                    end
                end

                // Receive remaining bits
                RECEIVE: begin
                    shift_reg <= {shift_reg[MSG_SIZE-2:0], data_in};

                    if (counter == 1) begin
                        counter <= '0;
                        state <= PACK_TAKEN;
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // Present packet until handshake
                PACK_TAKEN: begin
                    if (ready) begin
                        state <= LISTEN;
                    end
                end

                default: begin
                    state <= LISTEN;
                end

            endcase
        end
    end

endmodule