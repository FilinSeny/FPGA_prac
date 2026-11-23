`timescale 1ns/1ps

// End-to-end test with two actual top modules.
// Preloaded routing tables, start in outer IDLE(0), manual packet assembly,
// local delivery, transit, graceful stop and return to outer IDLE(0).
module tb_two_tops_fsm;
    localparam integer DEBOUNCE = 2;
    localparam [11:0] DIRECT_PKT  = {3'b110, 2'd1, 1'b0, 2'd2, 2'd1, 2'b10};
    localparam [11:0] TRANSIT_PKT = {3'b110, 2'd1, 1'b0, 2'd3, 2'd2, 2'b10};
    localparam integer OUTER_IDLE=0, OUTER_LISTEN=5, OUTER_TXRX_MODE=12;
    localparam integer NET_IDLE=0, NET_LISTEN=1, NET_MK_MSG=2, NET_STOPPING=3;

    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0;
    reg [1:0] key_a=2'b11, key_b=2'b11;
    reg [1:0] sw_a=2'b11, sw_b=2'b11;
    wire [2:0] tx_a, tx_b;
    wire [2:0] rx_a=3'b000;
    wire [2:0] rx_b={2'b00, tx_a[0]};
    wire [3:0] led_a,led_b,dig_a,dig_b;
    wire [7:0] seg_a,seg_b;

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

    wire mon_valid;
    wire [11:0] mon_packet;
    receiver #(.MSG_SIZE(12)) c_monitor (
        .clk(clk), .rst(!reset_n), .data_in(tx_b[1]),
        .valid(mon_valid), .ready(1'b1), .packet(mon_packet)
    );
    integer transit_count=0;
    reg [11:0] last_transit=0;
    always @(posedge clk) begin
        if (reset_n && mon_valid) begin
            transit_count <= transit_count+1;
            last_transit <= mon_packet;
            $display("[%0t] PACKET B.TX[1] -> C: %012b",$time,mon_packet);
        end
    end

    // Log EVERY sampled FSM state transition, including the packet creator FSM.
    // Sampling on negedge avoids active/NBA race with always_ff on posedge.
    integer prev_oa=-1, prev_ob=-1, prev_na=-1, prev_nb=-1;
    integer prev_pa=-1, prev_pb=-1;
    integer oa,ob,na,nb,pa,pb;
    always @(negedge clk) begin
        if (reset_n) begin
            oa=int'(a.u_commutator.state);
            ob=int'(b.u_commutator.state);
            na=int'(a.u_commutator.packet_processor.state);
            nb=int'(b.u_commutator.packet_processor.state);
            pa=int'(a.u_commutator.packet_processor.creator.state);
            pb=int'(b.u_commutator.packet_processor.creator.state);
            if (oa !== prev_oa) begin
                $display("[%0t] FSM A/commutator: %0d -> %0d",$time,prev_oa,oa); prev_oa=oa;
            end
            if (ob !== prev_ob) begin
                $display("[%0t] FSM B/commutator: %0d -> %0d",$time,prev_ob,ob); prev_ob=ob;
            end
            if (na !== prev_na) begin
                $display("[%0t] FSM A/txrx:       %0d -> %0d",$time,prev_na,na); prev_na=na;
            end
            if (nb !== prev_nb) begin
                $display("[%0t] FSM B/txrx:       %0d -> %0d",$time,prev_nb,nb); prev_nb=nb;
            end
            if (pa !== prev_pa) begin
                $display("[%0t] FSM A/pac_maker:  %0d -> %0d",$time,prev_pa,pa); prev_pa=pa;
            end
            if (pb !== prev_pb) begin
                $display("[%0t] FSM B/pac_maker:  %0d -> %0d",$time,prev_pb,pb); prev_pb=pb;
            end
        end
    end

    always @(posedge clk) begin
        if (reset_n && a.u_commutator.packet_processor.manual_handshake)
            $display("[%0t] HANDSHAKE A manual=%012b DST=%0d RAM_port=%0d physical_port=%0d",$time,
                a.u_commutator.packet_processor.manual_packet,
                a.u_commutator.packet_processor.dst_addr,
                a.u_commutator.packet_processor.port,
                a.u_commutator.packet_processor.physical_port);
        if (reset_n && b.u_commutator.packet_processor.accepted &&
            !b.u_commutator.packet_processor.is_local &&
            b.u_commutator.packet_processor.selected_valid)
            $display("[%0t] ROUTE B DST=%0d RAM_port=%0d phys=%0d tx_push=%b%b%b",$time,
                b.u_commutator.packet_processor.dst_addr,
                b.u_commutator.packet_processor.port,
                b.u_commutator.packet_processor.physical_port,
                b.u_commutator.packet_processor.tx_push[2],
                b.u_commutator.packet_processor.tx_push[1],
                b.u_commutator.packet_processor.tx_push[0]);
    end

    task automatic press_a(input integer idx);
        begin
            @(negedge clk); key_a[idx]=0;
            $display("[%0t] INPUT A KEY%0d DOWN",$time,idx);
            repeat(8) @(negedge clk);
            key_a[idx]=1;
            $display("[%0t] INPUT A KEY%0d UP",$time,idx);
            repeat(8) @(negedge clk);
        end
    endtask
    task automatic press_b(input integer idx);
        begin
            @(negedge clk); key_b[idx]=0;
            $display("[%0t] INPUT B KEY%0d DOWN",$time,idx);
            repeat(8) @(negedge clk);
            key_b[idx]=1;
            $display("[%0t] INPUT B KEY%0d UP",$time,idx);
            repeat(8) @(negedge clk);
        end
    endtask
    task automatic switch_a(input [1:0] v);
        begin
            @(negedge clk); sw_a=~v;
            $display("[%0t] INPUT A SW logical=%0d",$time,v);
            repeat(5) @(negedge clk);
        end
    endtask

    task automatic wait_network_on;
        integer i;
        begin : wait_block
            for(i=0;i<150;i=i+1) begin
                @(negedge clk);
                if (a.u_commutator.state == OUTER_LISTEN &&
                    b.u_commutator.state == OUTER_LISTEN &&
                    a.u_commutator.packet_processor.state == NET_LISTEN &&
                    b.u_commutator.packet_processor.state == NET_LISTEN) begin
                    $display("PASS: outer FSM=5 and txrx FSM=1 on both devices");
                    disable wait_block;
                end
            end
            $fatal(1,"Network start timeout");
        end
    endtask

    task automatic start_both_from_idle;
        begin
            if (a.u_commutator.state !== OUTER_IDLE || b.u_commutator.state !== OUTER_IDLE)
                $fatal(1,"Expected both outer FSMs in IDLE(0) before start");
            $display("\n=== START: IDLE(0) -> TXRX_MODE(12) -> LISTEN(5) ===");
            press_a(1);
            press_b(1);
            if(a.u_commutator.state !== OUTER_TXRX_MODE || b.u_commutator.state !== OUTER_TXRX_MODE)
                $fatal(1,"Expected both outer FSMs in TXRX_MODE(12)");
            press_a(0);
            press_b(0);
            wait_network_on();
        end
    endtask

    task automatic make_manual_a(input [1:0] dst,input [1:0] payload);
        integer i;
        begin
            $display("\n=== MANUAL ASSEMBLY A: dst=%0d payload=%0d ===",dst,payload);
            if(a.u_commutator.packet_processor.state !== NET_LISTEN)
                $fatal(1,"A txrx is not LISTEN before manual packet");
            press_a(0); // LISTEN -> MK_MSG, creator IDLE -> CONFIG_DST
            if(a.u_commutator.packet_processor.state !== NET_MK_MSG)
                $fatal(1,"A did not enter MK_MSG");
            switch_a(dst);
            press_a(0); // DST confirmation
            switch_a(payload);
            press_a(0); // payload confirmation
            begin : wait_done
                for(i=0;i<250;i=i+1) begin
                    @(negedge clk);
                    if(a.u_commutator.packet_processor.state == NET_LISTEN) begin
                        $display("PASS: manual packet accepted; txrx returned to LISTEN");
                        disable wait_done;
                    end
                end
                $display("DIAG A: creator_state=%0d manual_valid=%b ready=%b dst=%b port=%b route_ok=%b",
                    a.u_commutator.packet_processor.creator.state,
                    a.u_commutator.packet_processor.manual_valid,
                    a.u_commutator.packet_processor.manual_ready,
                    a.u_commutator.packet_processor.dst_addr,
                    a.u_commutator.packet_processor.port,
                    a.u_commutator.packet_processor.route_ok);
                $fatal(1,"Manual packet handshake timeout");
            end
        end
    endtask

    task automatic wait_direct;
        integer i;
        begin : direct_block
            for(i=0;i<500;i=i+1) begin
                @(negedge clk);
                if(b.u_commutator.packet_processor.stored_flag) begin
                    if(b.u_commutator.packet_processor.stored_packet !== DIRECT_PKT)
                        $fatal(1,"Wrong direct packet got=%012b expected=%012b",
                            b.u_commutator.packet_processor.stored_packet,DIRECT_PKT);
                    $display("PASS: A -> B DIRECT packet=%012b",DIRECT_PKT);
                    disable direct_block;
                end
            end
            $fatal(1,"Direct delivery timeout");
        end
    endtask

    task automatic wait_transit;
        integer i;
        begin : transit_block
            for(i=0;i<500;i=i+1) begin
                @(negedge clk);
                if(transit_count>0) begin
                    if(last_transit !== TRANSIT_PKT)
                        $fatal(1,"Wrong transit packet got=%012b expected=%012b",last_transit,TRANSIT_PKT);
                    $display("PASS: A -> B -> C TRANSIT packet=%012b",TRANSIT_PKT);
                    disable transit_block;
                end
            end
            $fatal(1,"Transit delivery timeout");
        end
    endtask

    task automatic stop_both_to_idle;
        integer i;
        begin
            $display("\n=== STOP: KEY1 -> STOPPING -> IDLE(0) ===");
            press_a(1);
            press_b(1);
            begin : await_stop
                for(i=0;i<200;i=i+1) begin
                    @(negedge clk);
                    if (a.u_commutator.state == OUTER_IDLE &&
                        b.u_commutator.state == OUTER_IDLE &&
                        a.u_commutator.packet_processor.state == NET_IDLE &&
                        b.u_commutator.packet_processor.state == NET_IDLE) begin
                        $display("PASS: both outer commutators and both txrx returned to IDLE(0)");
                        disable await_stop;
                    end
                end
                $fatal(1,"Stop timeout: outer A=%0d B=%0d txrx A=%0d B=%0d",
                    a.u_commutator.state,b.u_commutator.state,
                    a.u_commutator.packet_processor.state,b.u_commutator.packet_processor.state);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_two_tops_fsm.vcd");
        $dumpvars(0,tb_two_tops_fsm);
        repeat(5) @(negedge clk);
        reset_n=1;
        repeat(8) @(negedge clk);

        // Same workaround as the previously passing two-top test.
        // Only router IDs are forced; packet generation, lookup and transmission are real RTL.
        force a.u_commutator.addr_tab.loopback=2'd1;
        force b.u_commutator.addr_tab.loopback=2'd2;
        a.u_commutator.addr_tab.ram[2]=2'd1; // A -> B, TX[0]
        a.u_commutator.addr_tab.ram[3]=2'd1; // A -> C via B, TX[0]
        b.u_commutator.addr_tab.ram[3]=2'd2; // B -> C, TX[1]
        #2;
        if(a.u_commutator.my_addr !== 2'd1 || b.u_commutator.my_addr !== 2'd2)
            $fatal(1,"Router addresses not initialized");
        if(a.u_commutator.addr_tab.ram[2] !== 2'd1 ||
           a.u_commutator.addr_tab.ram[3] !== 2'd1 ||
           b.u_commutator.addr_tab.ram[3] !== 2'd2)
            $fatal(1,"Routing table not initialized");
        $display("PASS: RAM PRELOADED: A[2]=1 A[3]=1 B[3]=2; self A=1 B=2");
        if(a.u_commutator.state !== OUTER_IDLE || b.u_commutator.state !== OUTER_IDLE)
            $fatal(1,"Reset did not leave outer FSM in IDLE(0)");
        $display("PASS: INITIAL STATE A=0 B=0");

        start_both_from_idle();
        make_manual_a(2'd2,2'd1);
        wait_direct();
        make_manual_a(2'd3,2'd2);
        wait_transit();
        repeat(30) @(negedge clk);
        if(transit_count !== 1)
            $fatal(1,"Transit duplicated: %0d packets",transit_count);
        stop_both_to_idle();

        // No reset: RAM contents must survive a return to outer IDLE.
        if(a.u_commutator.addr_tab.ram[2] !== 2'd1 ||
           a.u_commutator.addr_tab.ram[3] !== 2'd1 ||
           b.u_commutator.addr_tab.ram[3] !== 2'd2)
            $fatal(1,"Routing table was corrupted on stop");
        $display("PASS: ROUTING TABLE PRESERVED AFTER RETURN TO IDLE");

        $display("\nALL TWO-TOP FSM TESTS PASSED");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1,"GLOBAL TIMEOUT: simulator advanced time but test incomplete");
    end
endmodule
