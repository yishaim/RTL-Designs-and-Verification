`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
//                                WORK IN PROGRESS
//--------------------------------------------------------------------------------

module DFF(dff_inf d_inf);

    always_ff@(posedge d_inf.clk)
    begin
        if (d_inf.rst)
            d_inf.dout <= 1'b0;
        else
            d_inf.dout <= d_inf.din;
    end
    
endmodule

interface dff_inf;
    logic clk, rst, din;
    logic dout;
 endinterface