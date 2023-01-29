`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
//                               WORK IN PROGRESS
//--------------------------------------------------------------------------------

//Transaction Class
class transaction;
    rand bit new_data;
    rand bit[11:0] data_in;
    bit cs, mosi;
    
    function transaction copy(); //Deep copy
        copy = new();
        copy.new_data = this.new_data;
        copy.data_in = this.data_in;
        copy.cs = this.cs;
        copy.mosi = this.mosi;
    endfunction
    
    function void display(input string tag); //Diplay status to console
        $display("@%0d [%0s]:  data_in: %0d, new_data: %0b, cs: %0b, mosi: %0b", $time, tag, data_in, new_data, cs, mosi);
    endfunction
endclass
//Generator Class
class generator;
    transaction tr;
    mailbox #(transaction) mbx;
    
    event done; //signal to environment that all transactions are done
    event next_drv; //signal from driver that it is ready for the next transaction
    event next_sco; //signal from scoreboard that it is ready for the next transaction
    
    int count; //user defined # of transactions
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        tr = new();
    endfunction
    
    task run();
        repeat(count);
        begin
            assert(tr.randomize) else $error("RANDOMIZATION ERROR");
            tr.display("GEN");
            mbx.put(tr.copy);
            @(next_drv);
            @(next_sco);
        end
        ->done;
    endtask
endclass

//Driver Class

//Monitor Class

//Scoreboard Class

//Environment Class


module tb();
endmodule
