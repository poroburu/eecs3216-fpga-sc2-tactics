`timescale 1ns/1ps
module tb_packet;
    reg clk=0, rst=1;
    always #10 clk=!clk;
    reg [7:0] byte_data=0;
    reg byte_valid=0, framing_error=0, packet_ready=0;
    wire packet_valid;
    wire [7:0] packet_kind, read_data;
    wire [31:0] round_id, snapshot_id, rejected, timeouts, overruns;
    wire [15:0] payload_length;
    reg [8:0] read_address=0;
    packet_rx #(.TIMEOUT_TICKS(16)) dut(.*);
    reg [7:0] fixture[0:1023], active[0:461];
    integer manifest, result, size, accepted, tx_check, i, test_count=0;
    integer active_size=0;
    reg [31:0] active_round=0, active_snapshot=0;
    reg [7:0] active_kind=0;
    reg [1023:0] filename;
    // Exercise the independent TX envelope against the same committed bytes.
    reg tx_start=0;
    wire tx_ready, tx_valid, tx_done;
    reg tx_byte_ready=0;
    wire [7:0] tx_byte;
    wire [8:0] tx_address;
    wire [15:0] tx_length={fixture[13],fixture[12]};
    packet_tx serializer(.clk(clk),.rst(rst),.start(tx_start),.ready(tx_ready),
        .kind(fixture[3]),.round_id({fixture[7],fixture[6],fixture[5],fixture[4]}),
        .snapshot_id({fixture[11],fixture[10],fixture[9],fixture[8]}),
        .payload_length(tx_length),.payload_address(tx_address),.payload_data(fixture[14+tx_address]),
        .byte_data(tx_byte),.byte_valid(tx_valid),.byte_ready(tx_byte_ready),.done(tx_done));
    task tick; begin @(posedge clk); #1; end endtask
    task send_byte(input [7:0] value); begin
        @(negedge clk); byte_data=value; byte_valid=1;
        tick(); @(negedge clk); byte_valid=0; tick();
    end endtask
    task check_active; begin
        if (payload_length !== active_size || round_id !== active_round ||
            snapshot_id !== active_snapshot || packet_kind !== active_kind)
            $fatal(1,"active metadata changed unexpectedly in %0s",filename);
        for (i=0; i<active_size; i=i+1) begin
            @(negedge clk); read_address=i; tick();
            if (read_data !== active[i]) $fatal(1,"active payload corrupted at %0d in %0s",i,filename);
        end
    end endtask
    task check_tx;
        integer n, cycles;
        begin
            @(negedge clk); tx_start=1; tick();
            @(negedge clk); tx_start=0;
            n=0; cycles=0;
            while (!tx_ready) begin
                tx_byte_ready=(cycles%3 != 0);
                #1;
                if (tx_valid && tx_byte_ready) begin
                    if (tx_byte !== fixture[n]) $fatal(1,"TX mismatch at %0d in %0s",n,filename);
                    n=n+1;
                end
                tick(); @(negedge clk); cycles=cycles+1;
                if (cycles>2000) $fatal(1,"TX hung");
            end
            tx_byte_ready=0;
            if (n != size) $fatal(1,"TX length mismatch %0d != %0d",n,size);
        end
    endtask
    initial begin
        repeat(3) tick(); @(negedge clk); rst=0;
        manifest=$fopen("manifest.txt","r");
        if (!manifest) $fatal(1,"missing fixture manifest");
        while (!$feof(manifest)) begin
            result=$fscanf(manifest,"%s %d %d %d\n",filename,size,accepted,tx_check);
            if (result == 4) begin
                $readmemh(filename,fixture,0,size-1);
                if (tx_check) check_tx();
                for (i=0; i<size; i=i+1) send_byte(fixture[i]);
                repeat(20) tick(); // also recover from truncated candidates
                if (packet_valid !== accepted[0]) $fatal(1,"wrong acceptance for %0s",filename);
                if (accepted) begin
                    active_size=size-15;
                    active_round={fixture[7],fixture[6],fixture[5],fixture[4]};
                    active_snapshot={fixture[11],fixture[10],fixture[9],fixture[8]};
                    active_kind=fixture[3];
                    for (i=0; i<active_size; i=i+1) active[i]=fixture[14+i];
                end
                check_active();
                if (accepted) begin
                    // Lock committed memory: an unsolicited frame must not replace it.
                    send_byte(8'ha5); send_byte(8'h5a);
                    check_active();
                    @(negedge clk); packet_ready=1; tick();
                    @(negedge clk); packet_ready=0;
                end
                test_count=test_count+1;
            end
        end
        // Framing error and reset in the middle of a candidate; next valid START recovers.
        send_byte(8'ha5); send_byte(8'h5a); send_byte(1);
        @(negedge clk); framing_error=1; tick();
        @(negedge clk); framing_error=0;
        check_active();
        send_byte(8'ha5); send_byte(8'h5a);
        @(negedge clk); rst=1; tick(); @(negedge clk); rst=0;
        active_size=0; active_round=0; active_snapshot=0; active_kind=0;
        filename="start.mem"; $readmemh(filename,fixture,0,14);
        for (i=0; i<15; i=i+1) send_byte(fixture[i]);
        if (!packet_valid || round_id != 1) $fatal(1,"reset recovery failed");
        if (rejected != 0) $fatal(1,"unexpected rejection after reset");
        $display("PASS packet RX/TX: %0d fixtures/random cases, atomic memory, busy, timeout, framing/reset recovery",test_count);
        $finish;
    end
    initial begin #100000000; $fatal(1,"watchdog"); end
endmodule
