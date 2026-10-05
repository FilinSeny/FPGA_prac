module ram

#(parameter ADDR_WIDTH = 3)

(
	input  [(ADDR_WIDTH-1):0] data_in,
	input  [(ADDR_WIDTH-1):0] addr,
	input  we, clk,
	input  rst,

	output valid,
	output [(ADDR_WIDTH-1):0] data_out,
	output [(ADDR_WIDTH-1):0] loopback
);
	//Адреса нумеруются с 1 тк как 0 - loopback
	//При записи выход считаем не валидным


	reg [ADDR_WIDTH-1:0] ram[2**ADDR_WIDTH-1:0];
	///reg [ADDR_WIDTH-1:0] addr_reg;
	///reg [DATA_WIDTH-1:0] data_out;

	initial begin
        $readmemh("../data/config.mem", ram, 0, 0);
    end

	always @ (posedge clk) begin
		if (rst) begin
			integer i;
			for (i = 1; i < 2**ADDR_WIDTH; i += 1) begin
				ram[i] <= 1'b0;
			end
		end else
		begin
			if (we && addr)
				ram[addr] <= data_in;
		end

	end

	assign valid = !we && !rst;
	assign data_out = ram[addr];
	assign loopback = ram[0];

endmodule
