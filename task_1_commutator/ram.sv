module ram #(
    parameter int ADDR_WIDTH = 2
) (
    input  logic [ADDR_WIDTH-1:0] data_in,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic                  we,
    input  logic                  clk,
    input  logic                  rst,

    output logic                  valid,
    output logic [ADDR_WIDTH-1:0] data_out,
    output logic [ADDR_WIDTH-1:0] loopback
);

    localparam int RAM_DEPTH = 2**ADDR_WIDTH;

    // Own router address
    logic [ADDR_WIDTH-1:0] config_mem [0:0];

    initial begin
        $readmemh("../data/config.mem", config_mem);
    end

    assign loopback = config_mem[0];

    // Routing table: logical addresses 0..RAM_DEPTH-1
    logic [ADDR_WIDTH-1:0] ram [0:RAM_DEPTH-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < RAM_DEPTH; i++) begin
                ram[i] <= '0;
            end
        end else if (we && (addr != loopback)) begin
            ram[addr] <= data_in;
        end
    end

    assign valid = !we && !rst;

    assign data_out = (addr == loopback)
                    ? loopback
                    : ram[addr];

endmodule