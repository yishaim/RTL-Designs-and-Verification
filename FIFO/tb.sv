`timescale 1ns / 1ps

//--------------------------------------------------------------------
//                                  WORK IN PROGRESS
//--------------------------------------------------------------------


//Transaction Class
class transaction;
    rand bit rd, wr;
    rand bit [7:0] data_in;
    bit full, empty;
    bit [7:0] data_out;
    
    constraint wr_rd {wr != rd; //constrain rd and wr, non-equality between them and equal dist
    wr dist {0:/50, 1:/50};
    rd dist {0:/50, 1:/50};
    }
    
    constraint data_in_con {data_in > 1; data_in < 8;} //constrain data_in between 1 and 8 for testing purposes
    
    //Deep copy of data in a transactin object
    function transaction copy(); 
        copy = new();
        copy.rd = this.rd;
        copy.wr = this.wr;
        copy.data_in = this.data_in;
        copy.full = this.full;
        copy.empty = this.empty;
        copy.data_out = this.data_out;
    endfunction
    
    function void display(input string tag);
        $display("@%0d [%0s]: wr: %0b, rd: %0b\t data_in: %0d, data_out: %0b\t empty: %0b, full: %0b", 
        $time, tag, wr, rd, data_in, data_out, empty, full);
    endfunction
    
endclass

//Generator Class
//-------------------------------------
class generator;
    transaction tr;
    mailbox #(transaction) mbx;
    
    int count = 0;
    
    event next_tr; //signal from driver that its ready for the next transaction
    event done; //all transactions have been randomized and sent to driver
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        tr = new();
    endfunction;    
    
    task run();
        repeat(count)
        begin
            assert(tr.randomize) else $display("RANDOMIZATION ERROR");
            mbx.put(tr.copy);
            tr.display("GEN");
            @(next_tr);
        end
        ->done;
    endtask
endclass

//Driver Class
class driver;

    virtual fifo_inf finf; //connect driver to interface with DUT
    mailbox #(transaction) mbx;
    transaction data_c;
    event next; //signal to generator that the last transaction has been received and sent to interface

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction 
    
    task reset(); //reset interface inputs to default values
        finf.rst <= 1'b1;
        finf.wr <= 1'b0;
        finf.rd <= 1'b0;
        finf.data_in <= 0;
        repeat(5)@(posedge finf.clk);
        finf.rst <= 1'b0;
        $display("[DRV]: DUT RST COMPLETE");
    endtask
    
    task run(); //main driver task, send transaction received from generator to DUT interface
        forever 
        begin
            mbx.get(data_c);
            data_c.display("DRV");
            finf.rd <= data_c.rd;
            finf.wr <= data_c.wr;
            finf.data_in <= data_c.data_in;
            repeat(2)@(posedge finf.clk);
            ->next;
        end
    endtask
endclass

//Monitor class
//------------------------------------------


//Infra above, test below
///------------------------------------
module tb();
    generator gen;
    mailbox #(transaction) mbx;
    
    initial 
    begin
        mbx = new();
        gen = new(mbx);
        gen.count = 20;
        gen.run;
    end
    
endmodule
