`timescale 1ns / 1ps

//--------------------------------------------------------------------------------
//                           DONE
//--------------------------------------------------------------------------------

//Transaction class
class transaction;
    rand bit din;
    bit dout;
    
    function void display(input string tag); //console display function
        $display("@%0d [%0s]: din:%0b dout:%0b", $time, tag, din, dout);
    endfunction
    
    function transaction copy(); //deep copy function
        copy = new();
        copy.din = this.din;
        copy.dout = this.dout;
    endfunction
endclass


//Generator class
class generator;
    transaction tr;
    mailbox #(transaction) mbx;
    event next_tr; //signal from sco to signal its ready for the next tr
    event done; //signal to system that all transaction are finished
    
    int count;
    
    function new(mailbox #(transaction) mbx);
        tr = new();
        this.mbx = mbx;
    endfunction
    
    task run(); //main randomization task
        repeat(count)
        begin
            assert(tr.randomize) else $error("@%0d [GEN]: RANDOMIZATION FAILED", $time);
            mbx.put(tr.copy); //put tr in mbx to be sent to driver
            tr.display("GEN"); //status update
            @(next_tr); //wait for signal from sco
        end
        ->done;
    endtask
endclass

//Driver class   
class driver;
    transaction tr;
    mailbox #(transaction) mbx;
    virtual dff_inf d_inf;
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task rst();
        d_inf.rst <= 1'b1;
        repeat(5)@(posedge d_inf.clk)
        d_inf.rst <= 1'b0;
        repeat(1)@(posedge d_inf.clk)
        $display("@%0d [DRV]: DDUT RST COMPLETED", $time);
    endtask
    
    task run();
        forever
        begin
            mbx.get(tr);
            d_inf.din <= tr.din;
            tr.display("DRV");
            @(posedge d_inf.clk);
        end
    endtask
endclass

//Monitor class
class monitor;
    transaction tr;
    mailbox #(transaction) mbx;
    virtual dff_inf d_inf;
    
    function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    endfunction
    
    task run();
        tr = new();
        forever
        begin
            repeat(2)@(posedge d_inf.clk)
            tr.din = d_inf.din;
            tr.dout = d_inf.dout;
            mbx.put(tr);
            tr.display("MON");
        end
    endtask
endclass

//Scoreboard class
class scoreboard;
    transaction tr;
    mailbox #(transaction) mbx;    
    event next_tr; //signal to generator that system is ready for next transaction
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run();
        forever
        begin
            mbx.get(tr);
            tr.display("SCO");
            if (tr.din == tr.dout)
                $display("@%0d [SCO]: DATA MATCH", $time);
            else
                $error("@%0d [SCO]: DATA MISMATCH", $time);
            ->next_tr;
        end
    endtask
endclass

//Environment class
class environment;
    generator gen;
    driver drv;
    mailbox #(transaction) gdmbx;
    
    monitor mon;
    scoreboard sco;
    mailbox #(transaction) msmbx;
    
    virtual dff_inf d_inf;
    
    event next_tr;
    
    function new(virtual dff_inf d_inf);
        gdmbx = new();
        gen = new(gdmbx);
        drv = new(gdmbx);
        
        msmbx = new();
        mon = new(msmbx);
        sco = new(msmbx);
            
        this.d_inf = d_inf;
        drv.d_inf = this.d_inf;
        mon.d_inf = this.d_inf;
        
        gen.next_tr = this.next_tr;
        sco.next_tr = this.next_tr;
    endfunction
    
    
    task pre_test();
        drv.rst();
    endtask
    
    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
    endtask
    
    task post_test();
        wait(gen.done.triggered);
        $finish;
    endtask
    
    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass

module tb();
    environment env;
    dff_inf d_inf();
    DFF dut(d_inf);
    
    parameter num_tr = 50;
    
    initial
    begin
        d_inf.clk <= 0;
    end
    
    always #5 d_inf.clk = ~d_inf.clk;
    
    initial
        begin
            env = new(d_inf);
            env.gen.count = num_tr;
            env.run();
    end
endmodule