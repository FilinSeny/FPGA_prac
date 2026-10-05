module mem_tab

#( parameter DATA_WIDTH = 6, parameter ADDR_WIDTH = 4 )

(
    input clk,
    input rst,
    input reg[1:0] dst,
    input we,
    input re,
    input reg[1:0] next_hop_in,

    output wire[1:0] next_hop_out,
    output enable
);

initial begin
    //чтение памяти из конфиг файла\
    //мб это нужно в самом раме, пока хз
end

/*
    организация памяти 
    адрес 0 - собственный mac
    адрес 1 - шлюз по умолчанию - заполняется по иницаализации

    далее формат 2слова
    1е - адрес назначения
    2е - некстхоп

*/

wire addr;
ram my_ram(
    .clk(clk),
    .rst(rst),
    .we(we)
);


always @* begin
    if (we)
end



endmodule