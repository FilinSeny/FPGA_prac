`timescale 1ns/1ps

module tb_ram;
    localparam int ADDR_WIDTH = 3;
    localparam int DEPTH = 1 << ADDR_WIDTH;
    localparam logic [ADDR_WIDTH-1:0] EXPECTED_SELF = 3'd3;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst = 0;
    logic we = 0;
    logic [ADDR_WIDTH-1:0] addr = '0;
    logic [ADDR_WIDTH-1:0] data_in = '0;
    wire valid;
    wire [ADDR_WIDTH-1:0] data_out, loopback;

    ram #(.ADDR_WIDTH(ADDR_WIDTH)) dut (
        .clk(clk), .rst(rst), .we(we), .addr(addr),
        .data_in(data_in), .valid(valid),
        .data_out(data_out), .loopback(loopback)
    );

    function automatic logic [ADDR_WIDTH-1:0] route_value(input int a);
        route_value = ADDR_WIDTH'((a + 2) % DEPTH);
    endfunction

    task automatic verify_read(input int a, input logic [ADDR_WIDTH-1:0] expected);
        @(negedge clk);
        addr = ADDR_WIDTH'(a);
        we = 0;
        #1;
        if (valid !== 1'b1 || data_out !== expected)
            $fatal(1, "FAIL read addr=%0d: data=%b expected=%b valid=%b", a, data_out, expected, valid);
        $display("PASS read addr=%0d data=%0d", a, data_out);
    endtask

    task automatic write_route(input int a, input logic [ADDR_WIDTH-1:0] value);
        @(negedge clk);
        addr = ADDR_WIDTH'(a);
        data_in = value;
        we = 1;
        #1;
        if (valid !== 1'b0)
            $fatal(1, "FAIL: valid must be 0 during write");
        @(posedge clk);
        #1;
        we = 0;
    endtask

    initial begin
        $dumpfile("ram_tb.vcd");
        $dumpvars(0, tb_ram);

        // config.mem must contain hex digit 3 at RAM cell 0.
        #2;
        if (loopback !== EXPECTED_SELF)
            $fatal(1, "FAIL init: loopback=%b; expected %b. Check ../data/config.mem and working directory", loopback, EXPECTED_SELF);
        $display("PASS initialization: loopback=%0d", loopback);

        // Reset clears routes but must retain the own address.
        @(negedge clk);
        rst = 1;
        #1;
        if (valid !== 1'b0)
            $fatal(1, "FAIL: valid must be 0 during reset");
        @(posedge clk);
        #1;
        rst = 0;
        if (loopback !== EXPECTED_SELF)
            $fatal(1, "FAIL: reset modified loopback");
        $display("PASS reset preserves loopback");

        // Populate all destinations, including the valid address zero.
        for (int a = 0; a < DEPTH; a++) begin
            if (a != int'(EXPECTED_SELF))
                write_route(a, route_value(a));
        end

        for (int a = 0; a < DEPTH; a++) begin
            if (a == int'(EXPECTED_SELF))
                verify_read(a, EXPECTED_SELF);
            else
                verify_read(a, route_value(a));
        end

        // Attempt to overwrite the own address: must be ignored.
        write_route(int'(EXPECTED_SELF), 3'd7);
        verify_read(int'(EXPECTED_SELF), EXPECTED_SELF);
        if (loopback !== EXPECTED_SELF)
            $fatal(1, "FAIL: own address changed");
        $display("PASS own address protected");

        @(negedge clk);
        rst = 1;
        @(posedge clk);
        #1;
        rst = 0;
        if (loopback !== EXPECTED_SELF)
            $fatal(1, "FAIL: reset changed loopback");

        for (int a = 0; a < DEPTH; a++) begin
            if (a == int'(EXPECTED_SELF))
                verify_read(a, EXPECTED_SELF);
            else
                verify_read(a, '0);
        end

        $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
