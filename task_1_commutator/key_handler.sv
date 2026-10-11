module key_handler #(
    parameter int KEY_NUM = 2,
    parameter int DEBOUNCE_CYCLES = 1_000_000,
    parameter bit ACTIVE_LOW = 0
) (
    input  logic               clk,
    input  logic               rst,
    input  logic [KEY_NUM-1:0] keys,

    output logic [KEY_NUM-1:0] key_press
);

    localparam int KEY_COUNT_WIDTH =
        (DEBOUNCE_CYCLES > 1)
        ? $clog2(DEBOUNCE_CYCLES)
        : 1;

    localparam logic [KEY_COUNT_WIDTH-1:0] KEY_COUNT_MAX =
        KEY_COUNT_WIDTH'(DEBOUNCE_CYCLES - 1);

    // Synchronization
    (* async_reg = "true" *)
    logic [KEY_NUM-1:0] key_meta, key_sync;

    // Debouncing
    logic [KEY_NUM-1:0] key_stable;
    logic [KEY_NUM-1:0] key_previous;

    logic [KEY_COUNT_WIDTH-1:0] key_count [KEY_NUM];

    wire [KEY_NUM-1:0] key_input =
        ACTIVE_LOW ? ~keys : keys;

    // Generate one-clock pulse on button press
    assign key_press = key_stable & ~key_previous;

    always_ff @(posedge clk) begin
        if (rst) begin
            key_meta     <= '0;
            key_sync     <= '0;
            key_stable   <= '0;
            key_previous <= '0;

            for (int i = 0; i < KEY_NUM; i++) begin
                key_count[i] <= '0;
            end
        end else begin
            key_meta     <= key_input;
            key_sync     <= key_meta;
            key_previous <= key_stable;

            for (int i = 0; i < KEY_NUM; i++) begin
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

endmodule