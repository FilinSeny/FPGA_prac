module fifo #(
    parameter int width = 1,
    parameter int depth = 4
)(
    input  logic             clk,
    input  logic             rst,
    input  logic             push,
    input  logic             pop,
    input  logic [width-1:0] write_data,
    output wire  [width-1:0] read_data,
    output wire              empty,
    output wire              full
);
    localparam int PTR_W = (depth > 1) ? $clog2(depth) : 1;
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [PTR_W:0] count;
    logic [width-1:0] data [0:depth-1];

    assign empty = (count == 0);
    assign full  = (count == depth);
    assign read_data = data[rd_ptr];

    wire do_pop  = pop  && !empty;
    wire do_push = push && (!full || do_pop);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (do_push) begin
                data[wr_ptr] <= write_data;
                wr_ptr <= (wr_ptr == depth-1) ? '0 : wr_ptr + 1'b1;
            end
            if (do_pop)
                rd_ptr <= (rd_ptr == depth-1) ? '0 : rd_ptr + 1'b1;
            case ({do_push, do_pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule


/*module fifo
# (
    parameter width = 1, depth = 4
)
(
    input                clk,
    input                rst,
    input                push,
    input                pop,
    input  [width - 1:0] write_data,
    output [width - 1:0] read_data,
    output               empty,
    output               full
);

    //------------------------------------------------------------------------

    localparam pointer_width = $clog2 (depsth);
    localparam max_ptr       = pointer_width' (depth - 1);

    //------------------------------------------------------------------------

    logic [pointer_width - 1:0] wr_ptr, rd_ptr;
    logic wr_ptr_odd_circle, rd_ptr_odd_circle;

    logic [width - 1:0] data [0: depth - 1];

    always_ff @ (posedge clk or posedge rst)
        if (rst)
        begin
            wr_ptr <= '0;
            wr_ptr_odd_circle <= 1'b0;
        end
        else if (push)
        begin
            if (wr_ptr == max_ptr)
            begin
                wr_ptr <= '0;
                wr_ptr_odd_circle <= ~ wr_ptr_odd_circle;
            end
            else
            begin
                wr_ptr <= wr_ptr + 1'b1;
            end
        end
        
    always_ff @ (posedge clk or posedge rst)
        if (rst)
        begin
            rd_ptr <= '0;
            rd_ptr_odd_circle <= 1'b0;
        end
        else if (pop)
        begin
            if (rd_ptr == max_ptr)
            begin
                rd_ptr <= '0;
                rd_ptr_odd_circle <= ~ rd_ptr_odd_circle;
            end
            else
            begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end

    assign read_data = data[rd_ptr];

    //------------------------------------------------------------------------

    always_ff @ (posedge clk)
        if (push)
            data [wr_ptr] <= write_data;

    assign read_data = data [rd_ptr];

    //------------------------------------------------------------------------

    wire equal_ptrs  = (wr_ptr == rd_ptr);
    wire same_circle = (wr_ptr_odd_circle == rd_ptr_odd_circle);

    assign empty = equal_ptrs & same_circle;

    assign full = equal_ptrs & !same_circle;

endmodule*/
