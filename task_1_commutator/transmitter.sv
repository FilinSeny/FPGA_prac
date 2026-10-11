module transmitter 
# (
    parameter int MSG_SIZE = 12
)
(
    input wire                      clk,
    input wire                      rst,
    input wire                      valid,

    input logic[MSG_SIZE - 1:0]     packet,

    output logic                    ready,
    output logic                    data_out
);

localparam int COUNT_WIDTH = (MSG_SIZE > 1) ? $clog2(MSG_SIZE + 1) : 1;

logic [MSG_SIZE-1:0] buffer;
logic [COUNT_WIDTH-1:0] counter;

always_ff @(posedge clk) begin
    if (rst) begin
        buffer   <= '0;
        counter  <= '0;
        ready    <= 1'b1;
    end else begin
        // Accept new packet
        if (valid && ready) begin
            buffer  <= packet;
            counter <= MSG_SIZE;
            ready   <= 1'b0;
        end

        // Transmit packet
        else if (counter != 0) begin
            counter <= counter - 1'b1;

            if (counter == 1)
                ready <= 1'b1;
            end
    end
end

assign data_out = counter != 0 ? buffer[counter - 1'b1] : 1'b0;

endmodule