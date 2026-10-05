module commutator ()
    //функционал
    /*
        1 установка режима часов - внешние/внутренние
        2 ресет конкретного коммутатора
        3 ввод таблицы маршрутизации 
        4 вывод актуалольной инфы:
            состояние - светодиод
            пакет - семисегментник (если что воткнем омдаз с ним)
        5 состояние прослушки портов
    */

    enum logic[4:0] 
    {
        IDLE        = 5'd0,
        CONFIG_DST  = 5'd1,
        CONF_HOP    = 5'd2,
        UPD_RAM     = 5'd3,
        LISTEN      = 5'd4,
        GET_PACK    = 5'd5,
        LOAD_HOP    = 5'd6,
        SEND_PACK   = 5'd7
    } state, new_state;

    logic       clk;
    logic       rst;

    logic       keys[0:1];

    logic[2:0]  switch_reg, dst_reg, hop_reg_w;
    logic[2:0]  next_hop;
    logic[2:0]  my_addr;
    logic       valid_mem;
    logic       we_mem;
    
    ram addr_tab(
        .clk(clk),
        .rst(rst),
        .addr(dst_reg),
        .data_in(hop_reg),
        .data_out(next_hop),
        .loopback(my_addr),
        .valid(valid),
        .we(we_mem)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= 0;
        end else begin
            state <= new_state;
            if (state == CONFIG_DST) begin
                dst_reg <= switch_reg;
            end
            if (state == CONFIG_HOP) begin
                hop_reg_w <= switch_reg;
            end
        end
    end

    always_comb begin
        case (state)
            IDLE: begin
                if (key[0]) begin
                    new_state <= CONFIG_DST;
                end else begin
                    new_state <= IDLE;
                    //потом сделать таймер на 3с, по истечению котрого уходим в
                    //режим прослушки (listening)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           n
                end
            end
            CONFIG_DST: begin
                if (key[0]) begin
                    new_state <= CONFIG_HOP;
                end else begin
                    new_state <= state;
                end
            end
            CONF_HOP: begin
                if (key[0]) begin
                    new_state <= UPD_RAM;
                end else begin
                    new_state <= state;
                end
            end
            UPD_RAM: begin
                new_state <= IDLE;
            end
            LISTEN: begin
                if (key[0]) begin
                    new_state <= IDLE;
                end
            end
        endcase
    end

    always_comb begin
        case(state)
            we_mem <= 0;
            LISTEN: begin
                ///Подача enable на приемник
            end
            UPD_RAM: begin
                we_mem <= 1
                valid_mem <= 1;
            end

        endcase
    end
endmodule