module testbanch_mem;
    localparam int ADDR_WIDTH = 3;
    // config.mem must contain a single hexadecimal digit: 3
    localparam logic [ADDR_WIDTH-1:0] EXPECTED_SELF_ADDR = 3'd3;

    logic                   clk = 1'b0;
    logic                   rst;
    logic                   we;
    logic [ADDR_WIDTH-1:0]  dst_addr;
    logic [ADDR_WIDTH-1:0]  next_hop_new;
    wire  [ADDR_WIDTH-1:0]  next_hop_got;
    wire  [ADDR_WIDTH-1:0]  self_addr;
    wire                    out_data_valid;

    ram #(.ADDR_WIDTH(ADDR_WIDTH)) dut (
        .clk(clk),
        .rst(rst),
        .we(we),
        .addr(dst_addr),
        .data_in(next_hop_new),
        .data_out(next_hop_got),
        .loopback(self_addr),
        .valid(out_data_valid)
    );

    always #5 clk = ~clk;

    task automatic check_read(
        input logic [ADDR_WIDTH-1:0] read_addr,
        input logic [ADDR_WIDTH-1:0] expected
    );
        @(negedge clk);
        we = 1'b0;
        dst_addr = read_addr;
        #1; // Asynchronous read settles.
        if (out_data_valid !== 1'b1 || next_hop_got !== expected)
            $fatal(1, "read addr=%0d: data=%0d valid=%b; expected data=%0d valid=1",
                   read_addr, next_hop_got, out_data_valid, expected);
    endtask

    task automatic write_route(
        input logic [ADDR_WIDTH-1:0] write_addr,
        input logic [ADDR_WIDTH-1:0] value
    );
        @(negedge clk);
        dst_addr = write_addr;
        next_hop_new = value;
        we = 1'b1;
        #1;
        if (out_data_valid !== 1'b0)
            $fatal(1, "valid must be 0 while writing addr=%0d", write_addr);
        @(posedge clk);
        #1; // Nonblocking memory write completes.
        @(negedge clk);
        we = 1'b0;
    endtask

    initial begin
        $dumpfile("testbanch_mem.vcd");
        $dumpvars(0, testbanch_mem);

        rst = 1'b1;
        we = 1'b0;
        dst_addr = '0;
        next_hop_new = '0;
        #1;
        if (out_data_valid !== 1'b0)
            $fatal(1, "valid must be 0 during reset");
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;
        if (self_addr !== EXPECTED_SELF_ADDR)
            $fatal(1, "config: self_addr=%0d; expected %0d",
                   self_addr, EXPECTED_SELF_ADDR);

        check_read('0, EXPECTED_SELF_ADDR);
        check_read(3'd1, '0);
        check_read(3'd2, '0);
        check_read(3'd7, '0);

        write_route(3'd1, 3'd2);
        write_route(3'd2, 3'd1);
        check_read(3'd1, 3'd2);
        check_read(3'd2, 3'd1);

        write_route('0, 3'd7); // Address 0 must remain read-only.
        check_read('0, EXPECTED_SELF_ADDR);
        if (self_addr !== EXPECTED_SELF_ADDR)
            $fatal(1, "writing addr=0 changed loopback to %0d", self_addr);
        check_read(3'd1, 3'd2);
        check_read(3'd2, 3'd1);

        @(negedge clk);
        rst = 1'b1;
        #1;
        if (out_data_valid !== 1'b0)
            $fatal(1, "valid must be 0 during reset");
        @(posedge clk);
        #1;
        @(negedge clk);
        rst = 1'b0;
        if (self_addr !== EXPECTED_SELF_ADDR)
            $fatal(1, "reset changed loopback to %0d", self_addr);
        check_read(3'd1, '0);
        check_read(3'd2, '0);

        $display("PASS: config, reset, writes, reads, reserved addr=0 and valid");
        $finish;
    end
endmodule