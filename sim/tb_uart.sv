`timescale 1ns/1ps
module tb_uart;
    localparam BIT_TICKS=434;
    reg clk=0, rst=1, rx=1;
    always #10 clk=!clk;
    wire [7:0] data;
    wire valid, framing_error;
    uart_rx receiver(.*);
    reg [7:0] tx_data=0;
    reg tx_valid=0;
    wire tx_ready, tx;
    uart_tx transmitter(.clk(clk),.rst(rst),.data(tx_data),.valid(tx_valid),.ready(tx_ready),.tx(tx));
    integer received=0, errors=0, sent=0, i, j;
    reg [7:0] expected[0:299];
    task ticks(input integer n); begin repeat(n) @(negedge clk); end endtask
    task send(input [7:0] value, input integer bit_time, input integer stop_ok);
        integer k;
        begin
            rx=0; ticks(bit_time);
            for (k=0; k<8; k=k+1) begin rx=value[k]; ticks(bit_time); end
            rx=stop_ok; ticks(bit_time); rx=1;
        end
    endtask
    always @(posedge clk) begin
        #1;
        if (valid) begin
            if (data !== expected[received]) $fatal(1,"RX mismatch %0d got %h expected %h",received,data,expected[received]);
            received=received+1;
        end
        if (framing_error) errors=errors+1;
    end
    // Independent serial monitor, not a second instance of our UART receiver.
    reg [7:0] sampled;
    integer k;
    initial forever begin
        @(negedge tx);
        ticks(BIT_TICKS/2);
        if (tx !== 0) $fatal(1,"TX invalid start");
        for (k=0; k<8; k=k+1) begin ticks(BIT_TICKS); sampled[k]=tx; end
        ticks(BIT_TICKS);
        if (tx !== 1 || sampled !== sent[7:0]) $fatal(1,"TX framing/data error %0d",sent);
        sent=sent+1;
    end
    initial begin
        ticks(5); rst=0; ticks(5);
        // False start shorter than half bit produces no byte.
        rx=0; ticks(100); rx=1; ticks(500);
        for (i=0; i<256; i=i+1) begin
            expected[i]=i;
            send(i,433+(i%3),1); // back-to-back with small baud mismatch
        end
        ticks(500);
        if (received != 256) $fatal(1,"missing RX byte");
        send(8'h55,434,0); ticks(1000);
        if (errors != 1 || received != 256) $fatal(1,"stop error not isolated");
        rx=0; ticks(1000); rst=1; ticks(5); rst=0; rx=1; ticks(1000);
        expected[256]=8'haa; send(8'haa,434,1); ticks(500);
        if (received != 257) $fatal(1,"RX reset recovery failed");
        for (j=0; j<256; j=j+1) begin
            wait(tx_ready); @(negedge clk); tx_data=j; tx_valid=1;
            ticks(1); tx_valid=0;
            wait(tx_ready);
        end
        ticks(500);
        if (sent != 256) $fatal(1,"missing TX byte");
        $display("PASS UART RX/TX: all 256 byte values, back-to-back, baud skew, false start, stop error, reset");
        $finish;
    end
    initial begin #100000000; $fatal(1,"watchdog"); end
endmodule
