`timescale 1ns/1ps
module tb_uart_display;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rx = 1;
    wire tx;
    wire [7:0] hex0, hex1, hex2, hex3, hex4, hex5;
    uart_loopback dut(clk, rx, tx, hex0, hex1, hex2, hex3, hex4, hex5);
    integer received_count = 0;
    reg [7:0] expected_bytes [0:1023];
    integer expected_count = 0;
    reg [47:0] expected_text = {6{8'h20}};
    always @(negedge clk) begin
        if (dut.received_valid) begin
            if (received_count >= expected_count)
                $fatal(1, "Unexpected received byte %h", dut.received_byte);
            if (dut.received_byte !== expected_bytes[received_count])
                $fatal(1, "Byte %0d mismatch", received_count);
            received_count = received_count + 1;
        end
    end
    task send_byte(input [7:0] value, input integer bit_ns = 8681,
                   input bit good_stop = 1);
        if (good_stop) begin
            expected_bytes[expected_count] = value;
            expected_count = expected_count + 1;
            if (value == 12) expected_text = {6{8'h20}};
            else if (value >= 32 && value <= 126)
                expected_text = {expected_text[39:0], value};
        end
        rx = 0; #(bit_ns);
        for (integer b=0; b<8; b=b+1) begin
            rx = value[b]; #(bit_ns);
        end
        rx = good_stop; #(bit_ns);
    endtask
    task check_text;
        #100;
        if (dut.characters !== expected_text)
            $fatal(1, "Display mismatch: expected %h, got %h", expected_text, dut.characters);
    endtask
    initial begin
        #103;
        check_text();
        // A short low glitch must not be accepted as a start bit.
        rx = 0; #1000; rx = 1; #10000;
        if (received_count != 0) $fatal(1, "False start accepted");
        for (integer b=0; b<256; b=b+1) send_byte(b);
        check_text();
        // Invalid stop/break must be dropped; idle high permits recovery.
        send_byte(8'h41, 8681, 0);
        #20000; rx = 1; #20000;
        check_text();
        for (integer b=32; b<48; b=b+1) send_byte(b, 8507);
        check_text();
        for (integer b=48; b<64; b=b+1) send_byte(b, 8855);
        check_text();
        send_byte(12);
        check_text();
        send_byte("U"); send_byte("A"); send_byte("R");
        send_byte("T"); send_byte("o"); send_byte("n");
        check_text();
        if ({hex5,hex4,hex3,hex2,hex1,hex0} !== 48'hC188AF87A3AB)
            $fatal(1, "UARTon glyph output mismatch");
        if (received_count != expected_count)
            $fatal(1, "Lost bytes: received %0d/%0d", received_count, expected_count);
        $display("PASS: %0d UART bytes, all 256 values, false start, invalid stop, +/-2%% baud, clear and six HEX glyphs", received_count);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
