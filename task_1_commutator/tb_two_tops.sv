`timescale 1ns/1ps

module tb_two_tops;
    localparam integer MSG_SIZE = 12;
    localparam integer DEBOUNCE = 2;
    localparam [11:0] DIRECT_PKT  = {3'b110, 2'd1, 1'b0, 2'd2, 2'd1, 2'b10};
    localparam [11:0] TRANSIT_PKT = {3'b110, 2'd1, 1'b0, 2'd3, 2'd2, 2'b10};

    reg clk = 0;
    always #5 clk = ~clk;

    reg reset_n = 0;
    reg [1:0] key_a = 2'b11, key_b = 2'b11; // active low
    reg [1:0] sw_a = 2'b11, sw_b = 2'b11;   // top inverts SW
    wire [2:0] tx_a, tx_b;
    wire [2:0] rx_a = {3{1'b0}};
    wire [2:0] rx_b = {2'b00, tx_a[0]};
    wire [3:0] led_a, led_b, dig_a, dig_b;
    wire [7:0] seg_a, seg_b;

    top #(.DEBOUNCE_CYCLES(DEBOUNCE)) a (
        .CLK(clk), .RESET(reset_n), .KEY(key_a), .SW(sw_a),
        .DATA_IN(rx_a), .DATA_OUT(tx_a),
        .LED(led_a), .SEG(seg_a), .DIG(dig_a)
    );

    top #(.DEBOUNCE_CYCLES(DEBOUNCE)) b (
        .CLK(clk), .RESET(reset_n), .KEY(key_b), .SW(sw_b),
        .DATA_IN(rx_b), .DATA_OUT(tx_b),
        .LED(led_b), .SEG(seg_b), .DIG(dig_b)
    );

    // Transit destination C is modeled by a separate serial receiver on B port 1.
    wire mon_valid;
    wire [MSG_SIZE-1:0] mon_packet;
    receiver #(.MSG_SIZE(MSG_SIZE)) transit_monitor (
        .clk(clk), .rst(!reset_n), .data_in(tx_b[1]),
        .valid(mon_valid), .ready(1'b1), .packet(mon_packet)
    );

    integer transit_count = 0;
    reg [MSG_SIZE-1:0] last_transit = '0;
    always @(posedge clk) begin
        if (reset_n && mon_valid) begin
            // ready=1: valid lasts exactly one sampled cycle
            last_transit <= mon_packet;
            transit_count <= transit_count + 1;
            $display("[%0t] transit B -> C packet=%b", $time, mon_packet);
        end
    end

    task automatic press_a(input integer k);
        begin
            @(negedge clk); key_a[k] = 1'b0;
            repeat (8) @(negedge clk);
            key_a[k] = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask
    task automatic press_b(input integer k);
        begin
            @(negedge clk); key_b[k] = 1'b0;
            repeat (8) @(negedge clk);
            key_b[k] = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    // Physical SW signals are inverted by top.
    task automatic set_a_sw(input [1:0] value);
        begin
            @(negedge clk); sw_a = ~value;
            repeat (5) @(negedge clk);
        end
    endtask

    task automatic wait_active;
        integer t;
        begin : wait_block
            for (t = 0; t < 200; t = t + 1) begin
                @(negedge clk);
                if (a.u_commutator.packet_processor.state == 2'd1 &&
                    b.u_commutator.packet_processor.state == 2'd1) begin
                    $display("PASS: both TXRX modules in LISTEN");
                    disable wait_block;
                end
            end
            $fatal(1, "Both TXRX modules did not enter LISTEN");
        end
    endtask

    task automatic send_manual(input [1:0] dst, input [1:0] data);
        integer t;
        begin
            // KEY[0]: enter manual mode inside txrx
            press_a(0);
            begin : await_mode
                for (t = 0; t < 100; t = t + 1) begin
                    @(negedge clk);
                    if (a.u_commutator.packet_processor.state == 2'd2)
                        disable await_mode;
                end
                $fatal(1, "A failed to enter MK_MSG");
            end

            set_a_sw(dst);
            press_a(0); // accept DST
            set_a_sw(data);
            press_a(0); // accept PAYLOAD

            begin : await_done begin
                for (t = 0; t < 200; t = t + 1) begin
                    @(negedge clk);
                    if (a.u_commutator.packet_processor.state == 2'd1)
                        disable await_done;
                end
                
                $display("DEBUG: txrx state=%0d, pac_maker state=%0d",
                    a.u_commutator.packet_processor.state,
                    a.u_commutator.packet_processor.creator.state);

                $display("DEBUG: manual_valid=%b manual_ready=%b handshake=%b",
                    a.u_commutator.packet_processor.manual_valid,
                    a.u_commutator.packet_processor.manual_ready,
                    a.u_commutator.packet_processor.manual_handshake);

                $display("DEBUG: packet=%b dst=%0d port=%0d route_ok=%b",
                    a.u_commutator.packet_processor.manual_packet,
                    a.u_commutator.packet_processor.dst_addr,
                    a.u_commutator.packet_processor.port,
                    a.u_commutator.packet_processor.route_ok);

                $fatal(1, "A failed to complete manual packet handshake");

                end
            end
        end
    endtask

    integer t;
    initial begin
        $dumpfile("tb_two_tops.vcd");
        $dumpvars(0, tb_two_tops);

        repeat (5) @(negedge clk);
        reset_n = 1'b1;
        repeat (8) @(negedge clk);

        // TEST ONLY: initialize per-instance router IDs and combinational routing tables.
        // In the actual FPGA this is done by separate config memories / controller.
        //a.u_commutator.addr_tab.config_mem[0] = 3'd3;
        //b.u_commutator.addr_tab.config_mem[0] = 3'd3;
        //a.u_commutator.addr_tab.ram[2] = 3'd1; // A -> B via A port 1
        //a.u_commutator.addr_tab.ram[3] = 3'd1; // A -> C via B, A port 1
        //b.u_commutator.addr_tab.ram[3] = 3'd2; // B -> C via B port 2

        #2000;
        // Outer commutator: KEY[1] IDLE->TXRX_MODE, KEY[0] -> LISTEN.
        /*press_a(1);
        press_b(1);
        press_a(0);
        press_b(0);
        wait_active();

        // First packet is delivered locally to router B.
        send_manual(2'd2, 2'd1);
        begin : direct_wait
            for (t = 0; t < 500; t = t + 1) begin
                @(negedge clk);
                if (b.u_commutator.packet_processor.stored_flag) begin
                    if (b.u_commutator.packet_processor.stored_packet !== DIRECT_PKT)
                        $fatal(1, "DIRECT mismatch got=%b expected=%b",
                                  b.u_commutator.packet_processor.stored_packet, DIRECT_PKT);
                    $display("PASS: A -> B local delivery: %b", DIRECT_PKT);
                    disable direct_wait;
                end
            end
            $fatal(1, "DIRECT timeout: B did not store local packet");
        end

        // Second packet is NOT addressed to B: B must forward it on port 1.
        send_manual(2'd3, 2'd2);
        begin : transit_wait
            for (t = 0; t < 500; t = t + 1) begin
                @(negedge clk);
                if (transit_count > 0) begin
                    if (last_transit !== TRANSIT_PKT)
                        $fatal(1, "TRANSIT mismatch got=%b expected=%b", last_transit, TRANSIT_PKT);
                    $display("PASS: A -> B -> C transit packet: %b", TRANSIT_PKT);
                    disable transit_wait;
                end
            end
            $fatal(1, "TRANSIT timeout: B did not forward packet on TX[1]");
        end
        repeat (40) @(negedge clk);
        if (transit_count != 1)
            $fatal(1, "TRANSIT duplication: count=%0d", transit_count);
        $display("ALL TWO-TOP TESTS PASSED");
        $finish;*/
    end

    initial begin
        #10000;
        $fatal(1, "GLOBAL TIMEOUT");
    end
endmodule
