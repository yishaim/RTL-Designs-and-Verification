`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
//                               WORK IN PROGRESS
//--------------------------------------------------------------------------------
parameter num_tr = 5;

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
    mailbox #(transaction) gdmbx;
    
    event done; //signal to environment that all transactions are done
    event next_drv; //signal from driver that it is ready for the next transaction
    event next_sco; //signal from scoreboard that it is ready for the next transaction
    
    int count = 0; //user defined # of transactions
    
    function new(mailbox #(transaction) gdmbx);
        this.gdmbx = gdmbx;
        tr = new();
    endfunction
    
    task run();
        repeat(count)
        begin
            assert(tr.randomize) else $error("@%0d [GEN]: RANDOMIZATION ERROR", $time);
            gdmbx.put(tr.copy);
            tr.display("GEN");
            @(next_drv);
            @(next_sco); //comment out for first half tb
        end
        ->done;
    endtask
endclass

//Driver Class
class driver;
    virtual spi_inf sinf; //access to dut interface
    transaction tr;
    mailbox #(transaction) gdmbx;
    mailbox #(bit [11:0]) dsmbx; //mailbox used to send reference data from driver to scoreboard
    
    event next_drv; //signal to generator that the driver is ready for the next transaction
    
    function new(mailbox #(transaction) gdmbx, mailbox #(bit [11:0]) dsmbx);
        this.gdmbx = gdmbx;
        this.dsmbx = dsmbx;
    endfunction
    
    task reset();
        sinf.rst <= 1'b1;
        sinf.new_data <= 1'b0;
        sinf.data_in <= 1'b0;
        sinf.cs <= 1'b1;
        sinf.mosi <= 1'b0;
        repeat(5)@(posedge sinf.clk);
        sinf.rst <= 1'b0;
        repeat(2)@(posedge sinf.clk);
        $display("@%0d [DRV]: DUT RST COMPLETE", $time);
     endtask
     
    task run();
        forever
        begin
            gdmbx.get(tr); //recieve data from generator
            @(posedge sinf.sclk);
            sinf.new_data <= 1'b1; //start transactoin by setting new_data high for 1 clk cycle
            sinf.data_in <= tr.data_in; //send randomized data to dut
            dsmbx.put(tr.data_in); //send ref data to scoreboard
            @(posedge sinf.sclk);
            sinf.new_data <= 1'b0; 
            wait(sinf.cs == 1'b1); //wait for cs to go high, signalling end of data transfer
            $display("@%0d [DRV]: DATA SENT: %0d", $time, tr.data_in); //status update
            ->next_drv;           
        end
    endtask
endclass

//Monitor Class
class monitor;
    virtual spi_inf sinf;
    mailbox #(bit [11:0]) msmbx;
    bit [11:0] srx;
    
    function new(mailbox #(bit [11:0]) msmbx);
        this.msmbx = msmbx;
    endfunction
    
    task run();
        forever
        begin
            @(posedge sinf.sclk)
            wait(sinf.cs == 1'b0)
            @(posedge sinf.sclk)
            for (int i=0; i<12; i++)
            begin
                @(posedge sinf.sclk);
                srx[i] = sinf.mosi;
            end
            wait(sinf.cs == 1'b1);
            $display("@%0d [MON]: data: %0d", $time, srx);
            msmbx.put(srx);
        end
    endtask
    
endclass  

//Scoreboard Class
class scoreboard;
    mailbox #(bit [11:0]) msmbx, dsmbx;
    bit [11:0] ds, ms;
    
    event next_sco;
    
    function new(mailbox #(bit [11:0]) dsmbx, mailbox #(bit [11:0]) msmbx);
        this.dsmbx = dsmbx;
        this.msmbx = msmbx;
    endfunction
    
    task run();
        forever
        begin
            msmbx.get(ms); //receive output data from monitor
            dsmbx.get(ds); //receive reference data from driver
            $display("@%0d [SCO]: data(IN): %0d, data(OUT): %0d",$time, ds, ms);
            if(ds == ms)
                $display("@%0d [SCO]: DATA MATCH", $time);
            else
                $error("@%0d [SCO]: DATA MISMATCH", $time);
            ->next_sco;
        end
    endtask
endclass

//Environment Class
class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;
    
    event next_drv;
    event next_sco;
    
    mailbox #(transaction) gdmbx;
    mailbox #(bit [11:0]) dsmbx, msmbx;
    
    virtual spi_inf sinf;
    
    function new(virtual spi_inf sinf);
        gdmbx = new();
        dsmbx = new();
        msmbx = new();
        
        gen = new(gdmbx);
        drv = new(gdmbx, dsmbx);
        mon = new(msmbx);
        sco = new(dsmbx, msmbx);
        
        this.sinf = sinf;
        drv.sinf = this.sinf;
        mon.sinf = this.sinf;
        
        gen.next_drv = next_drv;
        drv.next_drv = next_drv;
        
        gen.next_sco = next_sco;
        sco.next_sco = next_sco;
    endfunction
    
    task pre_test();
        drv.reset();
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
        $finish();
    endtask
    
    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass

//------------------------------------
//Infra above, test below
//------------------------------------

module tb();
    spi_inf sinf();
    
    spi dut(.clk(sinf.clk), .rst(sinf.rst), .new_data(sinf.new_data), .data_in(sinf.data_in), .sclk(sinf.sclk), .cs(sinf.cs), .mosi(sinf.mosi));
    
    environment env;

    
    initial begin
      sinf.clk <= 0;
    end
    always #5 sinf.clk <= ~sinf.clk;
    
    initial
    begin
        env = new(sinf);
        env.gen.count = num_tr;
        env.run();
    end
    endmodule
