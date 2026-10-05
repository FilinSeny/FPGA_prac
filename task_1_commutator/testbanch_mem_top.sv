`timescale 1ns/1ps
module tb_top;
    logic CLK = 1'b0;
    logic RESET = 1'b0;
    logic [3:0] KEY_SW = 4'b1111;
    wire [3:0] LED, DIG;
    wire [7:0] SEG;
    int writes = 0;
    
    top #(.DEBOUNCE_CYCLES(4)) dut (.*);

    always #10 CLK = ~CLK; // 50 MHz.

    // Observe the real RAM write port; do not inject data into the DUT.
    always @(posedge CLK)
        if (dut.u_commutator.we_mem && dut.u_commutator.dst_reg != 0)
            writes = writes + 1;

    task automatic cycles(input int n);
        repeat (n) @(negedge CLK);
    endtask

    task automatic expect_state(input int expected);
        if (dut.u_commutator.state !== 5'(expected))
            $fatal(1, "state=%0d, expected=%0d", dut.u_commutator.state, expected);
    endtask

    task automatic confirm;
        @(negedge CLK);
        KEY_SW[0] = 1'b0;
        cycles(20); // Synchronizer, debounce and FSM latency.
        KEY_SW[0] = 1'b1;
        cycles(20);
    endtask

    task automatic set_address(input logic [2:0] value);
        @(negedge CLK);
        KEY_SW[3:1] = ~value;
        cycles(5);
    endtask

    task automatic check_entry(input int address, input logic [2:0] expected);
        if (dut.u_commutator.addr_tab.ram[address] !== expected)
            $fatal(1, "RAM[%0d]=%0d, expected=%0d", address,
                   dut.u_commutator.addr_tab.ram[address], expected);
    endtask

    task automatic configure_route(input logic [2:0] destination,
                                   input logic [2:0] hop);
        int old_writes;
        old_writes = writes;
        expect_state(0);
        confirm();
        expect_state(1);
        set_address(destination);

        if (dut.u_commutator.display_number !== {8'h01,4'h0,1'b0,destination})
            $fatal(1, "destination display mismatch");
        confirm();
        expect_state(2);

        if (dut.u_commutator.dst_reg !== destination)
            $fatal(1, "destination was not captured");
        set_address(hop);

        if (dut.u_commutator.display_number !== {8'h02,4'h0,1'b0,hop})
            $fatal(1, "hop display mismatch");
        confirm();
        expect_state(0);

        if (dut.u_commutator.hop_reg_w !== hop)
            $fatal(1, "hop was not captured");
        if (writes != old_writes + ((destination == 0) ? 0 : 1))
            $fatal(1, "unexpected number of RAM writes");
        if (dut.u_commutator.valid_mem !== 1'b1)
            $fatal(1, "RAM read must be valid in IDLE");
        if (destination != 0) begin
            check_entry(int'(destination), hop);
            if (dut.u_commutator.next_hop !== hop)
                $fatal(1, "RAM output mismatch");
        end
    endtask

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        cycles(5);
        RESET = 1'b1;
        cycles(10);
        expect_state(0);
        check_entry(0, 3'd2); // data/config.mem contains 2.
        for (int i=1; i<8; i++) check_entry(i, '0);

        // A short glitch must not be accepted as a button press.
        KEY_SW[0] = 1'b0;
        cycles(1);
        KEY_SW[0] = 1'b1;
        cycles(15);
        expect_state(0);

        // Holding confirmation must advance only once.
        KEY_SW[0] = 1'b0;
        cycles(80);
        expect_state(1);
        KEY_SW[0] = 1'b1;
        cycles(20);
        set_address(3'd1);
        confirm();
        expect_state(2);

        set_address(3'd3);
        confirm();
        expect_state(0);
        check_entry(1, 3'd3);

        if (writes != 1) $fatal(1, "holding the button caused extra writes");

        for (int i=2; i<8; i++) configure_route(3'(i), 3'((i+2)%7+1));
        configure_route(3'd3, 3'd7); // Overwrite an existing route.
        configure_route(3'd0, 3'd6); // Reserved entry must be preserved.
        check_entry(0, 3'd2);
        if (dut.u_commutator.my_addr !== 3'd2)
            $fatal(1, "loopback changed");
        check_entry(1, 3'd3);
        for (int i=2; i<8; i++)
            check_entry(i, (i==3) ? 3'd7 : 3'((i+2)%7+1));


        RESET = 1'b0;
        cycles(5);
        RESET = 1'b1;
        cycles(10);
        expect_state(0);
        check_entry(0, 3'd2);
        for (int i=1; i<8; i++) check_entry(i, '0);
        $display("PASS: button interface, routes 1..7, overwrite, loopback, reset and display");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "simulation timeout");
    end
endmodule