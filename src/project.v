// The Tiny Tapeout top module for the game track (updated for 4 directional buttons).
`default_nettype none

module tt_um_lrxrg_game_paddle_and_ball (
    input  wire [7:0] ui_in,    // dedicated inputs: [0]=up, [1]=down, [2]=left, [3]=right
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidirectional pins, input path
    output wire [7:0] uio_out,  // bidirectional pins, output path
    output wire [7:0] uio_oe,   // bidirectional pins, 1 = drive
    input  wire       ena,      // high when the design is powered, ignore
    input  wire       clk,      // clock
    input  wire       rst_n     // reset, active low
);
    wire        hsync, vsync, active, frame;
    wire [9:0]  x, y;
    wire [5:0]  rgb;

    vga_sync vga (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync), .active(active), .x(x), .y(y), .frame(frame));

    game_core core (
        .clk(clk), .rst_n(rst_n),
        .up(ui_in[0]), .down(ui_in[1]), .left(ui_in[2]), .right(ui_in[3]),
        .x(x), .y(y), .active(active), .frame(frame),
        .rgb(rgb)
    );

    // TinyVGA PMOD pin order: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    assign uo_out = {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

    wire _unused = &{ena, uio_in, ui_in[7:4], 1'b0};
endmodule
