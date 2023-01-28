`timescale 1ns / 1ps

//--------------------------------------------------------------------
//                                  DONE
//--------------------------------------------------------------------


//Transaction Class
//-------------------------------------
class transaction;
    rand bit rd, wr;
    rand bit [7:0] data_in;
    bit full, empty;
    bit [7:0] data_out;
    bit [4:0] wr_ptr, rd_ptr; 
    
    constraint wr_rd {wr != rd; //constrain rd and wr, non-equality between them and equal dist
    wr dist {0:/50, 1:/50};
    rd dist {0:/50, 1:/50};
    }
    
    constraint data_con {data_in >=0 ; data_in < 31 ;} //constrain data_in between 1 and 8 for testing purposes
    
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
        $display("@%0d [%0s]: wr: %0b, rd: %0b\t data_in: %0d, data_out: %0d\t empty: %0b, full: %0b\t", 
        $time, tag, wr, rd, data_in, data_out, empty, full);
    endfunction
    
endclass

//Generator Class
//-------------------------------------
class generator;
    transaction tr;
    mailbox #(transaction) mbx;
    
    int count = 0;
    
    event next_tr; //signal from scoreboard that its ready for the next transaction
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
//Preliminary tb for generator class
/*module tb();
    generator gen;
    mailbox #(transaction) mbx;
    
    initial 
    begin
        mbx = new();
        gen = new(mbx);
        gen.count = 20;
        gen.run;
    end
    
endmodul
*/

//Driver Class
//--------------------------------
class driver;

    virtual fifo_inf finf; //connect driver to interface with DUT
    mailbox #(transaction) mbx;
    transaction data_c;
    event next_tr; //signal to generator that the last transaction has been received and sent to interface

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
            ->next_tr;
        end
    endtask
endclass
//preliminary tb for driver
/*module tb();
    //create instances of the necessary classes, events and components
    
    
    generator gen;
    driver drv;
    mailbox #(transaction) mbx;
    fifo_inf finf();
    event next_tr;
    
    //link DUT and interface
    FIFO dut(finf.clk, finf.rd, finf.wr, finf.rst, finf.data_in, finf.data_out, finf.full, finf.empty);
    
    //set clk (T = 10ns)
    always
    begin
        finf.clk <= 1;
        #5;
        finf.clk <= ~finf.clk;
        #5;
    end
    //constuct and connect generator and driver through mbx and next_tr
    initial
    begin
        mbx = new();
        gen = new(mbx);
        drv = new(mbx);
        
        gen.count = 20;
        gen.next_tr = next_tr;
        
        drv.finf = finf;
        drv.next_tr = next_tr;
    end
    
    initial
    begin
        fork
            gen.run();
            drv.run;
        join
    end
    
    initial
    begin
        #400;
        $finish;
    end
endmodule
*/

//Monitor Class
//-------------------------------------
class monitor;
    virtual fifo_inf finf;
    mailbox #(transaction) mbx;
    transaction tr;
    //event next; //temp for preliminary test
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run(); //transfer data post DUT to transaction through interface
        tr = new();
        forever 
        begin
            repeat(2)@(posedge finf.clk);
            tr.wr = finf.wr;
            tr.rd = finf.rd;
            tr.data_in = finf.data_in;
            tr.data_out = finf.data_out;
            tr.empty = finf.empty;
            tr.full = finf.full;
            mbx.put(tr); //put transaction in mbx and send to scoreboard
            tr.display("MON"); 
        end
    endtask
 endclass    

//Scoreboard Class
//-------------------------------------
class scoreboard;
    mailbox #(transaction) mbx;
    transaction tr;
    event next_tr;
    
    bit[7:0] queue[$]; //create queue to store expected data to compare to FIFO
    bit[7:0] temp; //temp variable to hold data taken off queue
    
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run();
        forever
        begin
            mbx.get(tr);
            tr.display("SC0"); //display final data seen by scoreboar
            
            if (tr.wr == 1'b1)
            begin
                if (tr.full == 1'b0)
                 begin
                    queue.push_front(tr.data_in); //add written data to back of queue
                    $display("[SCO]: DATA STORED IN QUEUE: %0d", tr.data_in); //update with written status
                 end
                 else
                    $display("[SCO]: FIFO FULL, DATA NOT WRITTEN"); //status update, fifo full
            end
            if (tr.rd == 1'b1)
            begin
                if (tr.empty == 1'b0)
                begin
                    temp = queue.pop_back(); //pop data from front of queue
                    if (tr.data_out == temp)
                        $display("[SCO]: DATA MATCH"); //status update: data from DUT matches data taken from queue
                    else $error("[SCO]: DATA MISMATCH");//status update: data from DUT doesnt matches data taken from queue
                end
                else
                begin
                    $display("[SCO]: FIFO EMPTY, DATA NOT READ"); //status update: fifo empty
                end
            end
            -> next_tr; //signal generator that system is ready for the next transaction
        end
    endtask    
endclass
//preliminary tb for monitor and scoreboard classes
/*module tb();
    monitor mon;
    scoreboard sco;
    mailbox #(transaction) mbx;
    event next;
    fifo_inf finf();
    
    FIFO dut(finf.clk, finf.rd, finf.wr, finf.rst, finf.data_in, finf.data_out, finf.full, finf.empty);
    
    initial
    begin
        finf.clk <= 1'b1;
    end 
    always #5 finf.clk <= ~finf.clk;
    
    initial
    begin
        mbx = new();
        mon = new(mbx);
        sco = new(mbx);
        
        mon.next = next;
        sco.next = next;
    end  
      
    initial
    begin
        fork
            mon.run();
            sco.run();
        join
    end
    
    initial
    begin
        #200;
        $finish();
    end
endmodule
*/

class environment;
    generator gen;
    driver drv;
    mailbox #(transaction) gdmbx; //mbx between generator and driver
    
    monitor mon;
    scoreboard sco;
    mailbox #(transaction) msmbx; //mbx between monitor and scoreboard
    
    event next_gs; //signal fronm scoreboard to generator to trigger next transaction randomization
    
    virtual fifo_inf finf;
    
    function new(virtual fifo_inf finf); 
        gdmbx = new();
        msmbx = new();
        gen = new(gdmbx);
        drv = new(gdmbx);
        mon = new(msmbx);
        sco = new(msmbx);
        
        this.finf = finf;
        drv.finf = this.finf;
        mon.finf = this.finf;
        
        gen.next_tr = next_gs;
        sco.next_tr = next_gs;
    endfunction
    
    task pre_test();
        drv.reset;
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
    endtask;
endclass

//Infra above, test below
///------------------------------------
module tb();
    environment env;
    fifo_inf finf();
    FIFO dut(finf.clk, finf.rd, finf.wr, finf.rst, finf.data_in, finf.data_out, finf.full, finf.empty);
    
    parameter num_tr = 50;
    
    initial
    begin
        finf.clk <= 0;
    end
    
    always #5 finf.clk = ~finf.clk;
    
        initial
    begin
        env = new(finf);
        env.gen.count = num_tr;
        env.run();
    end
endmodule
    
    
    

