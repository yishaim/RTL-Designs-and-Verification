`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//                                WORK IN PROGRESS
//////////////////////////////////////////////////////////////////////////////////

module uart_top
#(
    parameter clk_freq = 1000000, //MHz
    parameter baud_rate = 9600
)
(
    input clk, rst, send, rx, [7:0] tx_data,
    output reg done_tx, reg done_rx, reg tx, reg sys_clk_tx, reg sys_clk_rx, reg [7:0] rx_data
);

uart_tx #(clk_freq, baud_rate) utx(clk, rst, send, tx_data, dont_tx, tx, sys_clk_tx);

uart_rx #(clk_freq, baud_rate) urx(clk, rst, rx, done_rx, sys_clk_rx, rx_data);

endmodule

interface uart_in;
    logic clk, rst, send, rx;
    logic [7:0] tx_data;
    logic done_tx, done_rx, tx, sys_clk_tx, sys_clk_rx;
    logic [7:0] rx_data;
endinterface
