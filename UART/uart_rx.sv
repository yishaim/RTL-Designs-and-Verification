`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//                                WORK IN PROGRESS
//////////////////////////////////////////////////////////////////////////////////

module uart_rx
#(
    parameter clk_freq = 1000000, //MHz
    parameter baud_rate = 9600
)
(
    input clk, rst, rx,
    output reg done_rx, reg sys_clk, reg [7:0] rx_data
);

    localparam count_clk = clk_freq/baud_rate; //determine count necessary to change clk period
    
    integer count = 0;
    integer count_bit = 0;
    
    enum bit {idle = 1'b0, recieve = 1'b1} state;   
    
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
            rx_data <= 8'h00;
            count <= 0;
            done_rx <= 1'b0;
        end
        else
        begin
            case(state)
                
                idle:
                begin
                     count_bit <= 0; //transmission hasnt happened so there are no buts sent
                     done_rx <= 1'b0;
                     rx_data <= 8'h00;
                     if (rx <= 1'b0)
                     begin
                        state <= recieve;
                     end
                     else
                     begin
                        state <= idle;
                     end
                end
                
               recieve:
               begin
                    if (count_bit <= 7)
                    begin
                        rx_data <= {rx, rx_data[7:1]};
                        count_bit <= count_bit + 1;
                        state <= recieve;
                    end
                    else
                    begin
                        count_bit <= 0;
                        done_rx <= 1'b0;
                        state <= idle;
                    end
               end
               
               default: state <= idle;
           endcase
        end
    end
endmodule
