`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//                                WORK IN PROGRESS
//////////////////////////////////////////////////////////////////////////////////

module uart_tx
#(
    parameter clk_freq = 1000000, //MHz
    parameter baud_rate = 9600
)
(
    input clk, rst, send,
    input [7:0] tx_data,
    output reg done_tx, reg tx, reg sys_clk  
);

    localparam count_clk = clk_freq/baud_rate; //determine count necessary to change clk period

    integer count = 0;
    integer count_bit = 0;

    reg [7:0] tx_store;

   enum bit {idle = 1'b0, transfer = 1'b1} state;

//Generate system clk
    always@(posedge clk)
    begin
        if (count < count_clk)
            count <= count + 1;
        else
        begin
            count <= 0;
            sys_clk <= ~sys_clk;
        end
    end 
    
 //Reset decoder and FSM
    always@(posedge sys_clk)
    begin
        if (rst)
        begin
            state <= idle;
        end
        else
        begin
            case(state)
            
                idle:
                begin
                    count_bit <= 0; //transmission hasnt happened so there are no buts sent
                    tx <= 1'b1; //default value when not transmitting
                    done_tx <= 1'b0;
                    if (send) //master signalled to start transmission
                    begin
                        state <= transfer;
                        tx_store <= tx_data; //store data to before trasmitting
                        tx <= 1'b0; //switch tx to 0, starting transmission
                    end
                    else
                    begin
                        state <= idle;
                    end    
                end
                
                transfer:
                begin
                    if (count_bit <= 7)
                    begin
                        tx <= tx_store[count_bit];
                        count_bit = count_bit + 1;
                        state <= transfer;
                    end
                    else
                    begin
                        count_bit <= 0;
                        tx <= 1'b1;
                        done_tx <= 1'b1;
                        state <= idle;
                    end
                end
                
                default: state <= idle;
            endcase
        end
    end
endmodule

