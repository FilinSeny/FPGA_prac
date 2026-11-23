`timescale 1ns/1ps

// Single physical top: enter network mode from IDLE, assemble DST/PAYLOAD
// using KEY0 and SW, route through RAM to physical TX[0], return to IDLE.
module tb_one_top_manual;
    localparam integer OUT_IDLE=0, OUT_LISTEN=5, OUT_TXRX_MODE=12;
    localparam integer NET_IDLE=0, NET_LISTEN=1, NET_MK_MSG=2;
    localparam [1:0] SELF_ADDR=2'd1, DEST=2'd2, PAYLOAD=2'd1;
    localparam [11:0] EXPECTED={3'b110,SELF_ADDR,1'b0,DEST,PAYLOAD,2'b10};

    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0;
    reg [1:0] key=2'b11, sw=2'b11;
    wire [2:0] data_out;
    wire [3:0] led,dig;
    wire [7:0] seg;

    top #(.CLK_MHZ(1), .DEBOUNCE_CYCLES(2)) dut (
        .CLK(clk), .RESET(reset_n), .KEY(key), .SW(sw),
        .DATA_IN(3'b000), .DATA_OUT(data_out),
        .LED(led), .SEG(seg), .DIG(dig)
    );

    // Observe actual serial output rather than only TX FIFO writes.
    wire monitor_valid;
    wire [11:0] monitor_packet;
    receiver #(.MSG_SIZE(12)) monitor_tx0 (
        .clk(clk), .rst(!reset_n), .data_in(data_out[0]),
        .valid(monitor_valid), .ready(1'b1), .packet(monitor_packet)
    );
    integer packet_count=0;
    reg [11:0] last_packet='0;
    always @(posedge clk) begin
        if (reset_n && monitor_valid) begin
            packet_count <= packet_count+1;
            last_packet <= monitor_packet;
            $display("[%0t] TX[0] SERIAL PACKET=%012b",$time,monitor_packet);
        end
    end

    integer prev_outer=-1,prev_net=-1,prev_creator=-1;
    integer outer_now,net_now,creator_now;
    always @(negedge clk) begin
        if (reset_n) begin
            outer_now=int'(dut.u_commutator.state);
            net_now=int'(dut.u_commutator.packet_processor.state);
            creator_now=int'(dut.u_commutator.packet_processor.creator.state);
            if (outer_now !== prev_outer) begin
                $display("[%0t] FSM commutator: %0d -> %0d",$time,prev_outer,outer_now);
                prev_outer=outer_now;
            end
            if (net_now !== prev_net) begin
                $display("[%0t] FSM txrx:       %0d -> %0d",$time,prev_net,net_now);
                prev_net=net_now;
            end
            if (creator_now !== prev_creator) begin
                $display("[%0t] FSM pac_maker:  %0d -> %0d",$time,prev_creator,creator_now);
                prev_creator=creator_now;
            end
        end
    end

    always @(posedge clk) begin
        if (reset_n && dut.u_commutator.packet_processor.manual_valid)
            $display("[%0t] MANUAL valid=%b ready=%b dst=%0d ram_port=%b route_ok=%b full0=%b handshake=%b",$time,
                dut.u_commutator.packet_processor.manual_valid,
                dut.u_commutator.packet_processor.manual_ready,
                dut.u_commutator.packet_processor.dst_addr,
                dut.u_commutator.packet_processor.port,
                dut.u_commutator.packet_processor.route_ok,
                dut.u_commutator.packet_processor.tx_full[0],
                dut.u_commutator.packet_processor.manual_handshake);
        if (reset_n && dut.u_commutator.packet_processor.tx_push[0])
            $display("[%0t] TX FIFO[0] PUSH packet=%012b",$time,
                dut.u_commutator.packet_processor.edited_packet);
    end

    task automatic press(input integer idx);
        begin
            @(negedge clk); key[idx]=0;
            $display("[%0t] KEY%0d DOWN",$time,idx);
            repeat(8) @(negedge clk);
            key[idx]=1;
            $display("[%0t] KEY%0d UP",$time,idx);
            repeat(8) @(negedge clk);
        end
    endtask

    task automatic set_sw(input [1:0] v);
        begin
            @(negedge clk); sw=~v;
            $display("[%0t] SW logical=%0d",$time,v);
            repeat(5) @(negedge clk);
        end
    endtask

    task automatic await_network;
        integer i;
        begin : wait_loop
            for (i=0;i<150;i=i+1) begin
                @(negedge clk);
                if (dut.u_commutator.state == OUT_LISTEN &&
                    dut.u_commutator.packet_processor.state == NET_LISTEN) begin
                    $display("PASS: network LISTEN");
                    disable wait_loop;
                end
            end
            $fatal(1,"Cannot enter LISTEN: outer=%0d txrx=%0d",
                dut.u_commutator.state,dut.u_commutator.packet_processor.state);
        end
    endtask

    task automatic await_sent;
        integer i;
        begin : wait_loop
            for (i=0;i<500;i=i+1) begin
                @(negedge clk);
                if (dut.u_commutator.packet_processor.state == NET_LISTEN && packet_count>=1) begin
                    if (last_packet !== EXPECTED)
                        $fatal(1,"WRONG OUTPUT: got=%012b expected=%012b",last_packet,EXPECTED);
                    $display("PASS: manual packet sent through physical TX[0]");
                    disable wait_loop;
                end
            end
            $fatal(1,"SEND TIMEOUT creator=%0d valid=%b ready=%b dst=%b port=%b route_ok=%b full0=%b",
                dut.u_commutator.packet_processor.creator.state,
                dut.u_commutator.packet_processor.manual_valid,
                dut.u_commutator.packet_processor.manual_ready,
                dut.u_commutator.packet_processor.dst_addr,
                dut.u_commutator.packet_processor.port,
                dut.u_commutator.packet_processor.route_ok,
                dut.u_commutator.packet_processor.tx_full[0]);
        end
    endtask

    task automatic await_idle;
        integer i;
        begin : wait_loop
            for (i=0;i<200;i=i+1) begin
                @(negedge clk);
                if (dut.u_commutator.state == OUT_IDLE &&
                    dut.u_commutator.packet_processor.state == NET_IDLE) begin
                    $display("PASS: both FSMs returned to IDLE");
                    disable wait_loop;
                end
            end
            $fatal(1,"STOP TIMEOUT outer=%0d network=%0d",
                dut.u_commutator.state,dut.u_commutator.packet_processor.state);
        end
    endtask

    initial begin
        $dumpfile("tb_one_top_manual.vcd");
        $dumpvars(0,tb_one_top_manual);
        repeat(5) @(negedge clk);
        reset_n=1;
        repeat(8) @(negedge clk);

        // Same Icarus workaround as in the passing two-top simulation.
        // RAM stores port numbers 1..3: RAM port 1 -> physical TX[0].
        force dut.u_commutator.addr_tab.loopback=SELF_ADDR;
        dut.u_commutator.addr_tab.ram[DEST]=2'd1;
        #2;
        if (dut.u_commutator.my_addr !== SELF_ADDR ||
            dut.u_commutator.addr_tab.ram[DEST] !== 2'd1)
            $fatal(1,"INITIALIZATION FAILED self=%b route=%b",
                dut.u_commutator.my_addr,dut.u_commutator.addr_tab.ram[DEST]);
        if (dut.u_commutator.state !== OUT_IDLE)
            $fatal(1,"Not in outer IDLE after reset");
        $display("PASS: preload self=%0d route DST=%0d -> RAM port=1",SELF_ADDR,DEST);

        press(1); // outer IDLE -> TXRX_MODE
        if (dut.u_commutator.state !== OUT_TXRX_MODE)
            $fatal(1,"No TXRX_MODE after KEY1");
        press(0); // outer TXRX_MODE -> LISTEN
        await_network();

        press(0); // txrx LISTEN -> MK_MSG
        if (dut.u_commutator.packet_processor.state !== NET_MK_MSG)
            $fatal(1,"No MK_MSG after KEY0");
        set_sw(DEST);
        press(0); // pac_maker: confirm DST
        set_sw(PAYLOAD);
        press(0); // pac_maker: confirm payload
        await_sent();

        press(1); // txrx LISTEN -> STOPPING -> IDLE; outer -> IDLE
        await_idle();
        if (dut.u_commutator.addr_tab.ram[DEST] !== 2'd1)
            $fatal(1,"Route corrupted after stop");
        $display("ALL ONE-TOP MANUAL TESTS PASSED");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1,"GLOBAL TIMEOUT");
    end
endmodule
