`timescale 1ns/1ps
module tb_txrx_single;
    localparam int MSG_SIZE=12;
    localparam int DEBOUNCE=2;
    localparam logic [1:0] SELF=2'd1;

    logic clk=0;
    always #5 clk=~clk;

    logic rst=1, enable=0;
    logic [1:0] keys=0, sw=0;
    logic [2:0] data_in=0;
    logic [1:0] next_hop=2'd1;
    wire [1:0] dst_addr;
    wire [2:0] data_out;
    wire stoped;
    wire [15:0] disp_data;
    wire stored_valid;
    // Observe serial TX port 1 using a real receiver.
    wire mon_valid;
    wire [MSG_SIZE-1:0] mon_packet;
    receiver #(.MSG_SIZE(MSG_SIZE)) monitor_rx (
       .clk(clk), .rst(rst), .data_in(data_out[1]),
       .valid(mon_valid), .ready(1'b1), .packet(mon_packet)
    );
    txrx #(.MSG_SIZE(MSG_SIZE),.DEBOUNCE_CYCLES(DEBOUNCE),.FIFO_DEPTH(8)) dut (
      .clk(clk),.rst(rst),.enable(enable),.keys(keys),.sw(sw),
      .data_in(data_in),.my_addr(SELF),.next_hop(next_hop),
      .dst_addr(dst_addr),.data_out(data_out),.stoped(stoped),
      .disp_data(disp_data),.stored_valid(stored_valid)
    );
    integer tx_seen=0;
    logic saw_stopping_while_busy=0;
    always @(posedge clk) begin
        if (!rst && dut.state == dut.STOPPING && !dut.tx_ready[1])
            saw_stopping_while_busy <= 1;
    end
    logic [MSG_SIZE-1:0] expected_tx=12'b110_01_0_10_11_10;
    always @(posedge clk) begin
        if (!rst && mon_valid) begin
            if (mon_packet !== expected_tx)
                $fatal(1,"single: TX packet mismatch got=%b expected=%b",mon_packet,expected_tx);
            tx_seen=tx_seen+1;
            $display("PASS single: routed packet %b",mon_packet);
        end
    end

    task automatic press(input int k);
        @(negedge clk); keys[k]=1'b1;
        repeat (9) @(negedge clk);
        keys[k]=1'b0;
        repeat (9) @(negedge clk);
    endtask

    task automatic send_serial(input logic [MSG_SIZE-1:0] pkt, input int portnum);
        for (int i=MSG_SIZE-1;i>=0;i--) begin
            @(negedge clk); data_in[portnum]=pkt[i];
        end
        @(negedge clk); data_in[portnum]=1'b0;
    endtask

    task automatic wait_tx_count(input int wanted);
        int cycles;
        cycles=0;
        while (tx_seen < wanted && cycles<150) begin
            @(negedge clk); cycles++;
        end
        if (tx_seen != wanted) $fatal(1,"single: TX timeout (got %0d, need %0d)",tx_seen,wanted);
    endtask

    initial begin
        $dumpfile("tb_txrx_single.vcd"); $dumpvars(0,tb_txrx_single);
        repeat (4) @(negedge clk); rst=0;
        repeat (3) @(negedge clk);
        if (!stoped || data_out !== 3'b000) $fatal(1,"single: IDLE not quiet");
        enable=1;
        repeat (4) @(negedge clk);
    
        if (stoped) $fatal(1,"single: enable failed");
        // External packet for this node: SRC=2, DST=1, PAYLOAD=01
        send_serial(12'b110_10_0_01_01_10,0);
        repeat (12) @(negedge clk);
        if (!stored_valid || disp_data[11:0] !== 12'b110_10_0_01_01_10)
            $fatal(1,"single: local store mismatch, valid=%b data=%b",stored_valid,disp_data[11:0]);
        $display("PASS single: external packet stored locally");
        // External packet needs forwarding to port 1.
        
        send_serial(expected_tx,0);
        wait_tx_count(1);
        // Enter manual mode; construct packet to SELF for local storage.
        press(0); // KEY0 starts manual mode
        if (dut.state != dut.MK_MSG) $fatal(1,"single: did not enter manual mode");
        sw=SELF; press(0);  // destination
        sw=2'b11; press(0); // payload
        repeat (10) @(negedge clk);
        if (!stored_valid || disp_data[11:0] !== 12'b110_01_0_01_11_10)
            $fatal(1,"single: manual local packet mismatch data=%b",disp_data[11:0]);
        if (dut.state != dut.LISTEN) $fatal(1,"single: manual mode not exited");
        $display("PASS single: manual local packet and FSM handshake");
        // Start a second routed transmission, then request shutdown
        // while port 1 is sending bits.
        send_serial(expected_tx,0);
        begin : wait_busy
            int cycles=0;
            while (dut.tx_ready[1] !== 1'b0 && cycles<80) begin
                @(negedge clk); cycles++;
            end
            if (dut.tx_ready[1] !== 1'b0)
                $fatal(1,"single: second TX did not start");
        end
        press(1); // request STOPPING during current packet
        wait_tx_count(2);
        repeat (6) @(negedge clk);
        if (!saw_stopping_while_busy)
            $fatal(1,"single: STOPPING never overlapped active transmission");
        if (!stoped || data_out !== 3'b000)
            $fatal(1,"single: stop failed");
        $display("PASS single: stopped, all serial outputs idle");
        // Ensure enable-high does not restart automatically.
        repeat (15) @(negedge clk);
        if (!stoped) $fatal(1,"single: unexpected auto restart");
        enable=0; repeat (3) @(negedge clk);
        enable=1; repeat (4) @(negedge clk);
        if (stoped) $fatal(1,"single: re-enable failed");
        $display("ALL SINGLE TXRX TESTS PASSED");
        $finish;
    end
    initial begin #200000; $fatal(1,"single: GLOBAL TIMEOUT"); end
endmodule
