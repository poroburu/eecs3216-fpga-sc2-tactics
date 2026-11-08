// Display the last six printable UART characters; retain the direct echo path.
module uart_loopback (
    input wire clk_50,
    input wire uart_rx,
    output wire uart_tx,
    output wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);
    assign uart_tx = uart_rx;
    wire [7:0] received_byte;
    wire received_valid;
    uart_rx receiver (
        .clk(clk_50), .serial_in(uart_rx),
        .data(received_byte), .valid(received_valid)
    );
    // Blank at power-up; form feed (0x0C) clears all six digits.
    reg [47:0] characters = {6{8'h20}};
    always @(posedge clk_50) begin
        if (received_valid) begin
            if (received_byte == 8'h0C) characters <= {6{8'h20}};
            else if (received_byte >= 8'h20 && received_byte <= 8'h7E)
                characters <= {characters[39:0], received_byte};
        end
    end
    // Active-low {DP,g,f,e,d,c,b,a}; several letters need approximations.
    function automatic [7:0] segments(input [7:0] ascii);
        case (ascii)
            "0", "O": segments = 8'hC0;
            "1", "I", "i": segments = 8'hF9;
            "2", "Z", "z": segments = 8'hA4;
            "3": segments = 8'hB0;
            "4": segments = 8'h99;
            "5", "S", "s": segments = 8'h92;
            "6": segments = 8'h82;
            "7": segments = 8'hF8;
            "8", "B", "b": segments = 8'h80;
            "9", "G", "g": segments = 8'h90;
            "A", "a": segments = 8'h88;
            "C": segments = 8'hC6;
            "c": segments = 8'hA7;
            "D", "d": segments = 8'hA1;
            "E", "e": segments = 8'h86;
            "F", "f": segments = 8'h8E;
            "H", "K", "k": segments = 8'h89;
            "h": segments = 8'h8B;
            "J", "j": segments = 8'hE1;
            "L", "l": segments = 8'hC7;
            "M", "m", "N", "n": segments = 8'hAB;
            "o": segments = 8'hA3;
            "P", "p": segments = 8'h8C;
            "Q", "q": segments = 8'h98;
            "R", "r": segments = 8'hAF;
            "T", "t": segments = 8'h87;
            "U", "V", "W": segments = 8'hC1;
            "u", "v", "w": segments = 8'hE3;
            "X", "x": segments = 8'h89;
            "Y", "y": segments = 8'h91;
            "-": segments = 8'hBF;
            "_": segments = 8'hF7;
            ".": segments = 8'h7F;
            default: segments = 8'hFF;
        endcase
    endfunction
    assign HEX5 = segments(characters[47:40]);
    assign HEX4 = segments(characters[39:32]);
    assign HEX3 = segments(characters[31:24]);
    assign HEX2 = segments(characters[23:16]);
    assign HEX1 = segments(characters[15:8]);
    assign HEX0 = segments(characters[7:0]);
endmodule
