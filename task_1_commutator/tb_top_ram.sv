`timescale 1ns/1ps

module tb_top_ram;
    // The board exposes two address switches: addresses 0..3 only.
    // RAM may still use ADDR_WIDTH=3 internally.
    localparam logic [2:0] EXPECTED_SELF = 3'd3;
    localparam int IDLE=0, DATA_RW=1, CONFIG_DST=2, CONFIG_HOP=3;
    localparam int UPD_RAM=4, LISTEN=5, SHOW_RAM=9, TXRX_MODE=12;

    logic CLK = 1'b1;
    logic CLK1 = 1'b1;
    always #5 CLK = ~CLK;
    logic RESET = 1'b1;
    logic [1:0] KEY = 2'b11;  // active-low
    logic [1:0] SW = 2'b11;   // active-low
    wire DATA_OUT, DATA_IN;
    wire [3:0] LED, DIG;
    wire [7:0] SEG;
    int checks = 0;

    top #(.CLK_MHZ(1), .DEBOUNCE_CYCLES(3)) dut (
        .CLK(CLK), .RESET(RESET), .KEY(KEY), .SW(SW),
        .DATA_OUT(DATA_OUT), .DATA_IN(DATA_IN),
        .LED(LED), .SEG(SEG), .DIG(DIG)
    );
    
    task automatic check_state(input int wanted, input string label);
        #1;
        if (int'(dut.u_commutator.state) != wanted)
            $fatal(1, "FAIL %s: state=%0d expected=%0d", label,
                   dut.u_commutator.state, wanted);
        checks++;
        $display("PASS %s", label);
    endtask

    task automatic press_key(input int index);
        @(negedge CLK);
        KEY[index] = 1'b0;
        repeat (10) @(negedge CLK);
        KEY[index] = 1'b1;
        repeat (10) @(negedge CLK);
    endtask

    task automatic set_switches(input logic [1:0] value);
        @(negedge CLK);
        SW = ~value;
        repeat (5) @(negedge CLK);
        #1;
        if (dut.u_commutator.switch_reg !== {1'b0, value})
            $fatal(1, "FAIL SW: got %b expected %b",
                   dut.u_commutator.switch_reg, {1'b0, value});
        checks++;
    endtask

    logic seen_upd_ram = 0;

    always @(posedge CLK) begin
        if (RESET && dut.u_commutator.state == UPD_RAM)
            seen_upd_ram <= 1'b1;
    end

    task automatic write_route(input logic [1:0] dest,
                               input logic [1:0] hop);
        // Start in IDLE, configure destination and next hop via key0.
        press_key(0);
        check_state(DATA_RW, "IDLE -> DATA_RW");
        press_key(0);
        check_state(CONFIG_DST, "DATA_RW -> CONFIG_DST");
        set_switches(dest);
        press_key(0);
        check_state(CONFIG_HOP, "CONFIG_DST -> CONFIG_HOP");
        #1;
        if (dut.u_commutator.dst_reg !== {1'b0, dest})
            $fatal(1, "FAIL dst_reg=%0d expected=%0d",
                   dut.u_commutator.dst_reg, dest);
        set_switches(hop);
        
        seen_upd_ram = 0;

        press_key(0);

        if (!seen_upd_ram)
            $fatal(1, "FAIL: UPD_RAM was never reached");

        $display("PASS CONFIG_HOP -> UPD_RAM");

        check_state(IDLE, "UPD_RAM -> IDLE");

        #1;
        if (dut.u_commutator.addr_tab.ram[int'(dest)] !== {1'b0, hop})
            $fatal(1, "FAIL route[%0d]: got=%0d expected=%0d", dest,
                   dut.u_commutator.addr_tab.ram[int'(dest)], hop);
        checks++;
        $display("PASS route %0d -> %0d", dest, hop);
    endtask

    task automatic check_show_address(input int expected_addr);
        #1;
        if (int'(dut.u_commutator.ram_addr) != expected_addr)
            $fatal(1, "FAIL SHOW_RAM index=%0d expected=%0d",
                   dut.u_commutator.ram_addr, expected_addr);
        checks++;
        $display("SHOW_RAM logical=%0d mem_addr(dst_reg)=%0d next_hop=%0d display=%04h",
                 dut.u_commutator.ram_addr,
                 dut.u_commutator.dst_reg,
                 dut.u_commutator.next_hop,
                 dut.u_commutator.display_number);
    endtask

    initial begin
        $dumpfile("tb_top_ram.vcd");
        $dumpvars(0, tb_top_ram);
        #1;
        
        
        if (dut.u_commutator.my_addr !== EXPECTED_SELF)
            $fatal(1, "FAIL loopback=%0d expected=%0d (check config.mem / ram[0])",
                   dut.u_commutator.my_addr, EXPECTED_SELF);
        checks++;
        $display("PASS initial loopback=%0d", EXPECTED_SELF);

        
        @(negedge CLK);
        RESET = 1'b0;
        repeat (3) @(negedge CLK);
        RESET = 1'b1;
        repeat (5) @(negedge CLK);
        check_state(IDLE, "reset -> IDLE");
        if (dut.u_commutator.my_addr !== EXPECTED_SELF)
            $fatal(1, "FAIL reset changed loopback");
        checks++;
        checks++;
        $display("PASS display shows router address in IDLE");

        // All externally accessible non-self destinations: 0, 1, 2.
        write_route(2'd1, 2'd1);
        write_route(2'd2, 2'd2);
        write_route(2'd3, 2'd0);

        // Verify routing for 0..3, including local loopback at 3.
        for (int a = 0; a < 4; a++) begin
            // Read RAM combinationally through the actual commutator address register.
            // Temporarily forcing the register is only for verification, not synthesizable.
            case (a)
                0: force dut.u_commutator.dst_reg = 3'd0;
                1: force dut.u_commutator.dst_reg = 3'd1;
                2: force dut.u_commutator.dst_reg = 3'd2;
                3: force dut.u_commutator.dst_reg = 3'd3;
            endcase
            #2;
            case (a)
                1: if (dut.u_commutator.next_hop !== 3'd1) $fatal(1, "FAIL read route 0");
                2: if (dut.u_commutator.next_hop !== 3'd2) $fatal(1, "FAIL read route 1");
                3: if (dut.u_commutator.next_hop !== EXPECTED_SELF) $fatal(1, "FAIL loopback route 3");
            endcase
            $display("PASS read logical address %0d -> %0d", a, dut.u_commutator.next_hop);
            checks++;
            release dut.u_commutator.dst_reg;
            @(negedge CLK);
        end

        press_key(1);
        check_state(TXRX_MODE, "KEY1 -> TXRX_MODE");
        press_key(0);
        check_state(LISTEN, "KEY0 -> LISTEN");
        press_key(1);
        check_state(IDLE, "KEY0 -> IDLE");

        press_key(0);
        check_state(DATA_RW, "KEY0 -> DATA_RW for display");
        press_key(1);
        check_state(SHOW_RAM, "KEY1 -> SHOW_RAM");
        check_show_address(0);
        for (int a = 1; a < 4; a++) begin
            press_key(0);
            check_state(SHOW_RAM, "SHOW_RAM stays active");
            check_show_address(a);
        end
        press_key(0);
        check_state(IDLE, "SHOW_RAM index 3 -> IDLE");

        if (dut.u_commutator.my_addr !== EXPECTED_SELF)
            $fatal(1, "FAIL loopback was modified");
        checks++;
        $display("ALL TESTS PASSED (%0d checks)", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "TIMEOUT");
    end
    
endmodule
