`timescale 1ns/1ps

module tb_transmitter;
    localparam int MSG_SIZE = 12;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst = 1'b1;
    logic valid = 1'b0;
    logic [MSG_SIZE-1:0] packet = '0;
    wire ready;
    wire data_out;
    integer checks = 0;

    transmitter #(.MSG_SIZE(MSG_SIZE)) dut (
        .clk(clk),
        .rst(rst),
        .valid(valid),
        .packet(packet),
        .ready(ready),
        .data_out(data_out)
    );

    task automatic check_ready(input logic expected, input string message);
        if (ready !== expected)
            $fatal(1, "FAIL %s: ready=%b expected=%b time=%0t",
                   message, ready, expected, $time);
        checks++;
    endtask

    // Check MSB-first serialization and reject attempted packets while busy.
    task automatic send_and_check(input logic [MSG_SIZE-1:0] value,
                                  input bit try_busy_valid);
        @(negedge clk);
        check_ready(1'b1, "ready before packet");
        packet = value;
        valid  = 1'b1;

        @(posedge clk);
        #1; // Wait for nonblocking assignments to update.
        check_ready(1'b0, "ready after acceptance");

        for (int i = MSG_SIZE-1; i >= 0; i--) begin
            if (data_out !== value[i])
                $fatal(1, "FAIL packet=%b bit[%0d]: out=%b expected=%b time=%0t",
                       value, i, data_out, value[i], $time);
            checks++;
            check_ready(1'b0, "ready during serialization");

            @(negedge clk);
            // Do not let changing packet overwrite the buffered packet.
            packet = ~value;
            valid  = try_busy_valid ? 1'b1 : 1'b0;
            @(posedge clk);
            #1;
        end

        // After the 12th bit has been sampled, transmission is finished.
        check_ready(1'b1, "ready after 12 bits");
        if (data_out !== 1'b0)
            $fatal(1, "FAIL idle data_out=%b expected=0", data_out);
        checks++;
        $display("PASS packet=%b (12 bits, MSB first, busy ignored)", value);

        @(negedge clk);
        valid = 1'b0;
    endtask

    initial begin
        $dumpfile("tb_transmitter.vcd");
        $dumpvars(0, tb_transmitter);

        repeat (2) @(negedge clk);
        #1;
        check_ready(1'b1, "ready during reset");
        @(negedge clk);
        rst = 1'b0;
        #1;
        check_ready(1'b1, "ready after reset");

        send_and_check(12'b1011_0010_1101, 1'b1);
        send_and_check(12'b0000_0000_0000, 1'b0);
        send_and_check(12'b1111_1111_1111, 1'b1);
        send_and_check(12'b0101_1010_0011, 1'b0);

        // Reset in the middle of an active transmission.
        @(negedge clk);
        valid  = 1'b1;
        packet = 12'hA53;
        @(posedge clk);
        #1;
        check_ready(1'b0, "busy before reset");
        @(negedge clk);
        valid = 1'b0;
        rst   = 1'b1;
        @(posedge clk);
        #1;
        check_ready(1'b1, "ready after mid-packet reset");
        if (data_out !== 1'b0)
            $fatal(1, "FAIL data_out after reset=%b", data_out);
        checks++;
        @(negedge clk);
        rst = 1'b0;

        send_and_check(12'b1000_0000_0001, 1'b1);

        $display("ALL TESTS PASSED (%0d checks)", checks);
        $finish;
    end

    initial begin
      #100000;
        $fatal(1, "TIMEOUT");
    end
endmodule
