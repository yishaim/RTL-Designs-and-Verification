`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//                                  WORK IN PROGRESS
//////////////////////////////////////////////////////////////////////////////////
module spi(
    input clk, rst, new_data,
    input [11:0] data_in,
    output reg sclk, cs, mosi
    );

typedef enum bit[1:0] {idle = 2'b00, send = 2'b10} state_type;
state_type state = idle;

int count_clk = 0; //counter used in clk divider
int count_serial = 0;//counter used for serial data transfer

reg[11:0] temp;

//Generate sclk (clk = 100MHz, sclk = 1MHz => sclk tOff = 50*clk tOff (same for tOn))
always @(posedge clk)
begin
    if (rst)
    begin //set clk counter and sclk to 0 on rst
        count_clk <= 0; 
        sclk <= 1'b0;
    end
    else
    begin
        if (count_clk < 50)
            count_clk <= count_clk + 1; //count until sclk has been in its current state for 50 clk cycles
        else
        begin
            count_clk <= 0; //rst counter_clk to 0
            sclk <= ~sclk; //switch sclk to the other state
        end
    end
end

//State Machine
always@(posedge sclk)
begin
    if(rst == 1'b1)
    begin
        cs <= 1'b1;
        mosi <= 1'b0;
    end
    else
    begin
        case(state)
            idle:
            begin
                if (new_data)
                begin
                    state <= send;
                    cs <= 1'b0;
                    temp <= data_in;
                end
                else
                begin
                    state <= idle;
                    temp <= 8'h00;
                end
            end
            send:
            begin
                if (count_serial <= 11)
                begin
                    mosi <= temp[count_serial]; //data sent LSB -> MSB
                    count_serial++;
                end
                else
                begin
                    count_serial <= 0;
                    state <= idle;
                    cs <= 1'b1;
                    mosi <= 8'h00;
                end
            end
            default: state <= idle;
        endcase
    end
end
endmodule

interface spi_inf;
    logic clk, rst, new_data;
    logic [11:0] data_in;
    logic sclk, cs, mosi;
endinterface