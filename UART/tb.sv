`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//                                WORK IN PROGRESS
//////////////////////////////////////////////////////////////////////////////////
parameter tr_count = 5;

//Transaction class
class transaction;
    
    typedef enum bit [1:0] {write = 2'b00, read = 2'b01} op_wr; //write -> write to peripheral, read -> read from peripheral
    randc op_wr wr;
    
    bit send, tx, done_tx, done_rx;
    bit [7:0] rx_data;
    rand bit rx;
    randc bit [7:0] tx_data;
    
    function transaction copy(); //deep copy
        copy = new();
        copy.send = this.send;
        copy.rx = this.rx;
        copy.tx = this.tx;
        copy.done_tx = this.done_tx;
        copy.done_rx = this.done_rx;
        copy.rx_data = this.rx_data;
        copy.tx_data = this.tx_data;
        copy.wr = this.wr;
    endfunction
    
    function void display(input string tag);
        $display("@%0d [%0s]: OP: %0s, SEND: %0b, TX_DATA: %0b, RX_IN: %0b, TX_OUT: %0b, RX_OUT: %0b, DONE_TX: %0b, DONE_RX: %0b", $time, tag, wr.name(), send, tx_data, rx, tx, rx_data, done_tx, done_rx);
    endfunction

endclass

//Generator class
class generator;
    transaction tr;
    mailbox #(transaction) gdmbx;
    
    event next_drv;
    event next_sco;
    event done;
    
    int count = 0;
    
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
            @(next_sco);
        end
        ->done;
    endtask
endclass

//Driver class
class driver;
    virtual uart_in v_inf;
    
    transaction tr; //data from generator
    bit [7:0] din_tx; //data being sent to scoreboard, used to validate that data input to TX is data that is seen on tx line serially
    mailbox #(transaction) gdmbx;
    mailbox #(bit [7:0]) dsmbx;
    
    bit [7:0] datarx_ref;
    
    event next_drv;
    
    function new(mailbox #(transaction) gdmbx, mailbox #(bit [7:0]) dsmbx);
        this.gdmbx = gdmbx;
        this.dsmbx = dsmbx;
    endfunction
    
    task reset();
        v_inf.rst <= 1'b1;
        v_inf.tx_data <= 0;
        v_inf.rx_data <= 0;
        v_inf.send <= 1'b0;
        v_inf.rx <= 1'b1;
        v_inf.tx <= 1'b1;
        v_inf.done_tx <= 1'b0;
        v_inf.done_rx <= 1'b0;
        repeat(5)@(posedge v_inf.sys_clk_tx);
        v_inf.rst <= 1'b0;
        @(posedge v_inf.sys_clk_tx);
        $display("@%0d [DRV]: RST COMPLETE", $time);
    endtask
    
    task run();
        forever
        begin
            gdmbx.get(tr);
            if (tr.wr == 2'b00) //transmitting data
            begin
                @(posedge v_inf.sys_clk_tx);
                v_inf.rst <= 1'b0;
                v_inf.rx <= 1'b1; //read and write will not happen in parallel, this can be modified later
                v_inf.send <= 1'b1;
                v_inf.tx_data <= tr.tx_data;
                @(posedge v_inf.sys_clk_tx);
                v_inf.send <= 1'b0;
                dsmbx.get(tr.tx_data);
                $display("@%0d [DRV]: DATA SENT",$time);
                tr.display("DRV");
                wait(v_inf.done_tx == 1'b1);
                ->next_drv;
            end
            else if (tr.wr == 1'b01) //receiving data
            begin
                @(posedge v_inf.sys_clk_rx);
                v_inf.rst <= 1'b0;
                v_inf.rx <= 1'b0;
                v_inf.send <= 1'b0; //read and write will not happen in parallel, this can be modified later
                @(posedge v_inf.sys_clk_rx)
                for (int i = 0; i <= 7; i++)
                begin
                    @(posedge v_inf.sys_clk_rx);
                    datarx_ref[i] <= v_inf.rx;
                end
                dsmbx.put(datarx_ref);
                $display("@%0d [DRV]: DATA RCVD",$time);
                tr.display("DRV");
                wait(v_inf.done_rx == 1'b1);
                v_inf.rx <= 1'b1;
                ->next_drv;
            end
        end
    endtask
endclass

//Monitor class
class monitor;
   virtual uart_in v_inf;
   mailbox #(bit [7:0]) msmbx;
   transaction tr;
   
   bit [7:0] srx;
   bit [7:0] rrx;
   
   function new(mailbox #(bit [7:0]) msmbx);
        this.msmbx = msmbx;
        tr = new();
   endfunction 
   
   task run();
        forever
        begin
            @(posedge v_inf.sys_clk_tx)
            if ((v_inf.send == 1'b1) && (v_inf.rx == 1'b1)) //rx == 1 due to rx and tx not running in parallel
            begin
                @(posedge v_inf.sys_clk_tx)
                for (int i = 0; i <= 7; i++) //collecting output of tx
                begin
                    @(posedge v_inf.sys_clk_tx)
                    srx[i] <= v_inf.tx;
                end
                
                @(posedge v_inf.sys_clk_tx);
                msmbx.put(srx); //send output to scoreboard
            end
            else if ((v_inf.send == 1'b0) && (v_inf.rx == 1'b0))
            begin
                wait(v_inf.done_rx == 1);
                rrx <= v_inf.rx_data; //collect data received by rx
                $display("@%0d [MON]: DATA RCVD ON RX: %0d", $time, rrx);
                @(posedge v_inf.sys_clk_tx)
                msmbx.put(rrx); //send received data to scoreboard
            end
        end
   endtask
endclass

//Scoreboard class
class scoreboard;
    mailbox #(bit [7:0]) dsmbx, msmbx;
    
    bit[7:0] ds, ms;
    
    event next_sco;
    
    function new(mailbox #(bit [7:0]) dsmbx, msmbx);
        this.dsmbx = dsmbx;
        this.msmbx = msmbx;
    endfunction
    
    task run();
        forever
        begin
            dsmbx.get(ds);
            msmbx.get(ms);
            $display("@%0d [SCO]: DRV DATA: %0d, MON DATA: %0d", $time, ds, ms);
            if (ds == ms)
                $display("@%0d [SCO]: DATA MATCH",$time);
            else
                $display("@%0d [SCO]: DATA MISMATCH",$time);
        ->next_sco;
        end
    endtask
endclass

//Environment class
class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;
    
    virtual uart_in v_inf;
    
    mailbox #(transaction) gdmbx;
    mailbox #(bit [7:0]) dsmbx, msmbx;
    
    event next_drv;
    event next_sco;
    
    function new(virtual uart_in v_inf);
        gdmbx = new();
        dsmbx = new();
        msmbx = new();
        
        gen = new(gdmbx);
        drv = new(gdmbx, dsmbx);
        mon = new(msmbx);
        sco = new(dsmbx, msmbx);
        
        this.v_inf = v_inf;
        drv.v_inf = this.v_inf;
        mon.v_inf = this.v_inf;
        
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
        wait(gen.done.triggered)
        $finish();
    endtask
    
    task run();
        pre_test();
        test();
        post_test();
    endtask 
      
endclass

//DEBUGGING NEEDED, sys_clks are not firing
module tb();
    uart_in v_inf();
    
    uart_top dut(v_inf.clk, v_inf.rst, v_inf.send, v_inf.rx, v_inf.tx_data, v_inf.done_tx, v_inf.done_rx, v_inf.tx, v_inf.sys_clk_tx, v_inf.sys_clk_rx);
    
    environment env;
    
    initial begin
      v_inf.clk <= 0;
    end
    always #10 v_inf.clk <= ~v_inf.clk;
    
    always
    begin
        env = new(v_inf);
        env.gen.count = tr_count;
        env.run();
    end
endmodule
