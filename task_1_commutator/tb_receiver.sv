`timescale 1ns/1ps
module tb_receiver;
    localparam int MSG_SIZE = 12;
    localparam logic [MSG_SIZE-1:0] A = 12'b11_010_101_10_01; // last bit 1
    localparam logic [MSG_SIZE-1:0] B = 12'b11_001_011_01_10; // last bit 0
    localparam logic [MSG_SIZE-1:0] C = 12'b11_111_000_11_01; // last bit 1
    localparam logic [MSG_SIZE-1:0] D = 12'b11_000_111_00_10; // last bit 0

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1, data_in = 0, ready = 0;
    wire valid;
    wire [MSG_SIZE-1:0] packet;
    integer checks = 0;
    integer accepted = 0;
    logic [MSG_SIZE-1:0] last_accepted;

    receiver #(.MSG_SIZE(MSG_SIZE)) dut (
        .clk(clk), .rst(rst), .data_in(data_in),
        .ready(ready), .valid(valid), .packet(packet)
    );

    // Count handshakes at the sampling edge, before NBA updates.
    always @(posedge clk) begin
        if (!rst && valid && ready) begin
            accepted = accepted + 1;
            last_accepted = packet;
            $display("HANDSHAKE at %0t: %b", $time, packet);
        end
    end

    task automatic bit_cycle(input logic bit_value);
        @(negedge clk);
        data_in = bit_value;
        @(posedge clk);
        #1;
    endtask

    task automatic send_frame(input logic [MSG_SIZE-1:0] value);
        for (integer k=MSG_SIZE-1; k>=0; k=k-1)
            bit_cycle(value[k]);
    endtask

    task automatic expect_packet(input logic [MSG_SIZE-1:0] expected, input string name);
        if (valid !== 1'b1 || packet !== expected)
            $fatal(1,"FAIL %s: valid=%b packet=%b expected=%b",name,valid,packet,expected);
        checks++;
        $display("PASS %s: %b",name,packet);
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst = 1;
        ready = 0;
        data_in = 0;
        repeat (2) @(posedge clk);
        #1;
        if (valid !== 0) $fatal(1,"FAIL reset valid");
        @(negedge clk);
        rst = 0;
        checks++;
    endtask

    initial begin
        $dumpfile("tb_receiver_stream.vcd");
        $dumpvars(0,tb_receiver);
        reset_dut();

        // Case 1: contiguous A -> B with ready high; A ends in 1.
        // Assert ready before A's final cycle, so its handshake is at
        // the first bit of B; no idle cycle is inserted between frames.
        $display("CASE 1: back-to-back A(last=1) -> B(first=1)");
        ready = 1;
        send_frame(A);
        expect_packet(A,"A complete");
        send_frame(B);
        expect_packet(B,"B complete (no copied A final bit)");
        if (accepted != 1 || last_accepted !== A)
            $fatal(1,"FAIL A handshake: count=%0d last=%b",accepted,last_accepted);
        checks++;
        // There is deliberately no 0 idle bit: the first bit of B follows
        // the last bit of A at the very next rising edge.
        bit_cycle(1'b0); // consume B, and keep line low for next case
        if (accepted != 2 || last_accepted !== B || valid !== 0)
            $fatal(1,"FAIL B handshake");
        checks++;

        // Case 2: A held while C is already arriving. At the final bit of C
        // release ready: old A is consumed and C replaces it on same edge.
        $display("CASE 2: ready stalls, release on completion of next frame");
        ready = 0;
        send_frame(A);
        expect_packet(A,"A held");
        for (integer i=MSG_SIZE-1; i>=1; i=i-1) begin
            bit_cycle(C[i]);
            expect_packet(A,"A stable while C is accumulating");
        end
        @(negedge clk);
        ready = 1;
        data_in = C[0];
        @(posedge clk);
        #1;
        expect_packet(C,"C replaces A at handshake");
        if (accepted != 3 || last_accepted !== A)
            $fatal(1,"FAIL stalled A handshake");
        checks++;
        bit_cycle(0); // consume C
        if (accepted != 4 || last_accepted !== C || valid !== 0)
            $fatal(1,"FAIL C handshake");
        checks++;

        // Case 3: A held, B ends while still not ready: B must be dropped.
        // This is a limitation of single-output-buffer receiver, not FIFO.
        $display("CASE 3: output blocked at completion => frame dropped");
        ready = 0;
        send_frame(A);
        expect_packet(A,"A blocked");
        send_frame(D);
        expect_packet(A,"A preserved, D dropped");
        ready = 1;
        bit_cycle(0); // handshake for A
        if (accepted != 5 || last_accepted !== A || valid !== 0)
            $fatal(1,"FAIL blocked A consume");
        checks++;
        $display("NOTE: D was dropped by design (no input backpressure/FIFO in receiver)");

        // Case 4: reset mid-packet, then a fresh packet.
        $display("CASE 4: reset during partial packet");
        bit_cycle(1);
        bit_cycle(1);
        bit_cycle(0);
        reset_dut();
        ready = 0;
        send_frame(B);
        expect_packet(B,"fresh B after reset");

        $display("ALL TESTS PASSED (%0d checks)",checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1,"TIMEOUT");
    end
endmodule
