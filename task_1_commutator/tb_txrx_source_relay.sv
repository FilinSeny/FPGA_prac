`timescale 1ns/1ps
module tb_txrx_source_relay;
    localparam int MSG_SIZE = 12;
    localparam int DEBOUNCE = 2;
    localparam logic [1:0] ADDR_A = 2'd1;
    localparam logic [1:0] ADDR_B = 2'd2;
    localparam logic [1:0] ADDR_C = 2'd3; // destination beyond B (monitor only)

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst = 1'b1;
    logic enable_a = 1'b0, enable_b = 1'b0;
    logic [1:0] keys_a = 2'b00, keys_b = 2'b00;
    logic [1:0] sw_a = 2'b00, sw_b = 2'b00;
    wire [2:0] out_a, out_b;
    wire [2:0] in_a = 3'b000;
    wire [2:0] in_b = {2'b00, out_a[0]};  // A port 0 -> B port 0
    wire [1:0] dst_a, dst_b;
    wire stopped_a, stopped_b, stored_a, stored_b;
    wire [15:0] display_a, display_b;

    // A routes all non-local packets through its physical port 0.
    txrx #(.MSG_SIZE(MSG_SIZE), .DEBOUNCE_CYCLES(DEBOUNCE), .FIFO_DEPTH(8)) node_a (
        .clk(clk), .rst(rst), .enable(enable_a),
        .keys(keys_a), .sw(sw_a), .data_in(in_a),
        .my_addr(ADDR_A), .port(2'd0), .dst_addr(dst_a),
        .data_out(out_a), .stoped(stopped_a),
        .disp_data(display_a), .stored_valid(stored_a)
    );

    // B routes non-local packets through port 1 (towards C).
    txrx #(.MSG_SIZE(MSG_SIZE), .DEBOUNCE_CYCLES(DEBOUNCE), .FIFO_DEPTH(8)) node_b (
        .clk(clk), .rst(rst), .enable(enable_b),
        .keys(keys_b), .sw(sw_b), .data_in(in_b),
        .my_addr(ADDR_B), .port(2'd1), .dst_addr(dst_b),
        .data_out(out_b), .stoped(stopped_b),
        .disp_data(display_b), .stored_valid(stored_b)
    );

    // Downstream physical-line observer, NOT a third txrx.
    wire monitor_valid;
    wire [MSG_SIZE-1:0] monitor_packet;
    receiver #(.MSG_SIZE(MSG_SIZE)) downstream_monitor (
        .clk(clk), .rst(rst), .data_in(out_b[1]),
        .ready(1'b1), .valid(monitor_valid), .packet(monitor_packet)
    );

    localparam logic [MSG_SIZE-1:0] DIRECT_PKT = 12'b110_01_0_10_01_10;
    localparam logic [MSG_SIZE-1:0] TRANSIT_PKT = 12'b110_01_0_11_10_10;

    integer monitor_count = 0;
    // Observe on the falling clock edge, after RX nonblocking updates.
    always @(negedge clk) begin
        if (!rst && monitor_valid) begin
            if (monitor_packet !== TRANSIT_PKT)
                $fatal(1, "Unexpected packet on B port 1: got=%b expected=%b",
                       monitor_packet, TRANSIT_PKT);
            monitor_count = monitor_count + 1;
            $display("PASS: B relayed packet to port 1: %b at t=%0t", monitor_packet, $time);
        end
    end

    // Debounced 1-clock key_press; keep each press/release long enough.
    task automatic press_a(input integer key_no);
        @(negedge clk); keys_a[key_no] = 1'b1;
        repeat (1) @(negedge clk);
        keys_a[key_no] = 1'b0;
        repeat (1) @(negedge clk);
    endtask

    task automatic send_manual_a(
        input logic [1:0] destination,
        input logic [1:0] data_bits
    );
        press_a(0); // enter MK_MSG, pac_maker starts
        if (node_a.state !== node_a.MK_MSG)
            $fatal(1, "A did not enter MK_MSG (state=%0d)", node_a.state);
        sw_a = destination;
        press_a(0); // latch DST
        sw_a = data_bits;
        press_a(0); // latch PAYLOAD
    endtask

    task automatic await_b_local(input logic [MSG_SIZE-1:0] expected);
        integer n;
        n = 0;
        while ((!stored_b || display_b[11:0] !== expected) && n < 250) begin
            @(negedge clk);
            n = n + 1;
        end
        if (!stored_b || display_b[11:0] !== expected)
            $fatal(1, "B local packet timeout: got=%b expected=%b", display_b[11:0], expected);
    endtask

    task automatic await_transit;
        integer n;
        n = 0;
        while (monitor_count < 1 && n < 250) begin
            @(negedge clk);
            n = n + 1;
        end
        if (monitor_count != 1)
            $fatal(1, "Transit timeout: B did not emit packet on port 1");
    endtask

    initial begin
        $dumpfile("tb_txrx_source_relay.vcd");
        $dumpvars(0, tb_txrx_source_relay);
        repeat (4) @(negedge clk);
        rst = 1'b0;
        enable_a = 1'b1;
        enable_b = 1'b1;
        repeat (6) @(negedge clk);
        if (stopped_a || stopped_b)
            $fatal(1, "Could not start nodes: A=%b B=%b", stopped_a, stopped_b);
        $display("PASS: both nodes entered LISTEN");

        // Test 1: A(1) -> B(2)
        send_manual_a(ADDR_B, 2'b01);
        await_b_local(DIRECT_PKT);
        if (monitor_count != 0)
            $fatal(1, "B wrongly forwarded packet addressed to itself");
        $display("PASS: A -> B local delivery, B stored %b", display_b[11:0]);
        repeat (5) @(negedge clk);

        // Test 2: A(1) -> C(3) via B(2)
        send_manual_a(ADDR_C, 2'b10);
        await_transit();
        if (display_b[11:0] !== DIRECT_PKT)
            $fatal(1, "Transit unexpectedly overwrote B local storage: %b", display_b[11:0]);
        if (node_a.state !== node_a.LISTEN)
            $fatal(1, "A did not leave manual mode after handshake");
        $display("PASS: transit A -> B -> output port 1, SRC/DST/PAYLOAD preserved");

        repeat (25) @(negedge clk);
        if (monitor_count != 1)
            $fatal(1, "Duplicate transit packet detected, count=%0d", monitor_count);
        $display("ALL TWO-TXRX TESTS PASSED");
        $finish;
    end

    // Simulation-time watchdog. If VVP freezes on one timestamp due to
    // a delta-cycle loop, this watchdog also stops advancing.
    initial begin
        #100000;
        $fatal(1, "GLOBAL TIMEOUT");
    end
endmodule
