`timescale 1ns/1ps

module tb_tx_rx;
    localparam integer MSG_SIZE = 12;
    localparam integer PACKET_COUNT = 5;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg tx_valid = 1'b0;
    reg [MSG_SIZE-1:0] tx_packet = '0;
    wire tx_ready;
    wire serial_line;

    wire rx_valid;
    wire [MSG_SIZE-1:0] rx_packet;
    reg rx_ready = 1'b1; // Model of upstream FIFO, normally ready

    transmitter #(.MSG_SIZE(MSG_SIZE)) tx (
        .clk(clk), .rst(rst), .valid(tx_valid), .packet(tx_packet),
        .ready(tx_ready), .data_out(serial_line)
    );

    receiver #(.MSG_SIZE(MSG_SIZE)) rx (
        .clk(clk), .rst(rst), .data_in(serial_line),
        .valid(rx_valid), .packet(rx_packet), .ready(rx_ready)
    );

    reg [MSG_SIZE-1:0] sent [0:PACKET_COUNT-1];
    integer sent_count = 0;
    integer received_count = 0;
    integer bit_index = -1;
    reg [MSG_SIZE-1:0] serial_expected;
    integer gaps_checked = 0;
    integer serial_bits_checked = 0;

    // Check before nonblocking updates on posedge, exactly as RX samples the wire.
    always @(posedge clk) begin
        if (!rst) begin
            if (bit_index >= 0) begin
                if (serial_line !== serial_expected[bit_index])
                    $fatal(1, "SERIAL bit mismatch bit=%0d got=%b expected=%b time=%0t",
                           bit_index, serial_line, serial_expected[bit_index], $time);
                serial_bits_checked = serial_bits_checked + 1;
                if (bit_index == 0) bit_index = -2;
                else bit_index = bit_index - 1;
            end else if (bit_index == -2) begin
                // Exactly one idle-zero bit time after the packet.
                if (serial_line !== 1'b0)
                    $fatal(1, "No idle-zero bit after packet at %0t", $time);
                gaps_checked = gaps_checked + 1;
                bit_index = -1;
            end

            // At this edge the TX captures the next parallel packet.
            // The first serial bit will be sampled by RX at the NEXT edge.
            if (tx_valid && tx_ready) begin
                if (sent_count >= PACKET_COUNT)
                    $fatal(1, "Unexpected extra transmitted packet");
                if (bit_index != -1)
                    $fatal(1, "New frame started without required gap");
                sent[sent_count] = tx_packet;
                serial_expected = tx_packet;
                bit_index = MSG_SIZE-1;
                sent_count = sent_count + 1;
                $display("TX[%0d] %b", sent_count, tx_packet);
            end

            // Ready/valid check: sample BEFORE register updates.
            if (rx_valid && rx_ready) begin
                if (received_count >= sent_count)
                    $fatal(1, "RX produced unexpected packet %b", rx_packet);
                if (rx_packet !== sent[received_count])
                    $fatal(1, "RX[%0d] got=%b expected=%b",
                           received_count+1, rx_packet, sent[received_count]);
                received_count = received_count + 1;
                $display("PASS RX[%0d] %b", received_count, rx_packet);
            end
        end
    end

    // Check for valid/packet stability while the FIFO is blocked.
    reg stalled = 1'b0;
    reg [MSG_SIZE-1:0] stalled_packet;
    always @(negedge clk) begin
        if (rst) begin
            stalled = 1'b0;
        end else begin
            if (stalled && (!rx_valid || rx_packet !== stalled_packet))
                $fatal(1, "RX valid/packet changed during FIFO stall");
            stalled = rx_valid && !rx_ready;
            if (stalled) stalled_packet = rx_packet;
        end
    end

    // Present a packet until input valid&&ready handshake.
    // Calling twice consecutively requests maximum TX throughput.
    task automatic send_packet(input [MSG_SIZE-1:0] value);
        begin
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_packet = value;
            tx_valid  = 1'b1;
            @(posedge clk); // TX accepts on this edge
            @(negedge clk);
            tx_valid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_tx_rx.vcd");
        $dumpvars(0, tb_tx_rx);

        repeat (3) @(negedge clk);
        rst = 1'b0;

        // Packets ending both in 1 and 0. One-bit gap must be zero.
        send_packet(12'b11_010_101_10_01);
        send_packet(12'b11_001_011_01_10);
        send_packet(12'b11_111_000_11_01);

        // Stall output FIFO briefly, without filling RX's single-entry buffer.
        // Do not stall for an unbounded duration: serial input has no backpressure.
        wait (received_count == 3);
        @(negedge clk);
        rx_ready = 1'b0;
        send_packet(12'b11_000_111_10_00);
        // Wait until the full packet is available at RX output.
        wait (rx_valid === 1'b1);
        repeat (3) @(negedge clk);
        rx_ready = 1'b1;
        send_packet(12'b11_101_010_01_11);

        wait (received_count == PACKET_COUNT);
        repeat (3) @(negedge clk);
        if (sent_count != PACKET_COUNT)
            $fatal(1, "TX count mismatch");
        if (serial_bits_checked != MSG_SIZE*PACKET_COUNT)
            $fatal(1, "Serial bits count=%0d expected=%0d",
                   serial_bits_checked, MSG_SIZE*PACKET_COUNT);
        if (gaps_checked != PACKET_COUNT)
            $fatal(1, "Gaps=%0d expected=%0d", gaps_checked, PACKET_COUNT);
        $display("ALL TESTS PASSED: packets=%0d serial_bits=%0d zero_gaps=%0d",
                 received_count, serial_bits_checked, gaps_checked);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "TIMEOUT: sent=%0d received=%0d", sent_count, received_count);
    end
endmodule
