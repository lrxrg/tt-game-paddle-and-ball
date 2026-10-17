`default_nettype none

module game #(
parameter DB = 500000      // debounce time in clocks, 20 ms at 25 MHz
) (
input  wire        clk,
input  wire        rst_n,
input  wire        up,        // raw button for up direction
input  wire        down,      // raw button for down direction
input  wire        left,      // raw button for left direction
input  wire        right,     // raw button for right direction
input  wire [9:0]  x,         // column of the pixel being drawn
input  wire [9:0]  y,         // row of the pixel being drawn
input  wire        active,    // high inside the picture frame
input  wire        frame,     // one clock pulse per picture
output wire [5:0]  rgb        // {R[1:0], G[1:0], B[1:0]}
);

localparam [4:0] GRID_W = 5'd32;
localparam [4:0] GRID_H = 5'd24;

// Direction encoding
localparam [1:0] DIR_UP    = 2'd0;
localparam [1:0] DIR_DOWN  = 2'd1;
localparam [1:0] DIR_LEFT  = 2'd2;
localparam [1:0] DIR_RIGHT = 2'd3;

// 1. Clean up buttons using debounce logic
wire up_c, down_c, left_c, right_c;
ip_debounce #(.N(DB)) db_up    (.clk(clk), .rst_n(rst_n), .noisy(up),    .clean(up_c));
ip_debounce #(.N(DB)) db_down  (.clk(clk), .rst_n(rst_n), .noisy(down),  .clean(down_c));
ip_debounce #(.N(DB)) db_left  (.clk(clk), .rst_n(rst_n), .noisy(left),  .clean(left_c));
ip_debounce #(.N(DB)) db_right (.clk(clk), .rst_n(rst_n), .noisy(right), .clean(right_c));

// 2. Snake movement tick (moves every 10 frames to keep speed playable)
wire snake_step;
ip_tick #(.DIV(10)) snake_tick (.clk(clk), .rst_n(rst_n), .en(frame), .tick(snake_step));

// 3. Direction control (preventing direct 180-degree reversals)
reg [1:0] dir, next_dir;
always @(*) begin
    next_dir = dir;
    if (up_c && dir != DIR_DOWN)       next_dir = DIR_UP;
    else if (down_c && dir != DIR_UP)   next_dir = DIR_DOWN;
    else if (left_c && dir != DIR_RIGHT) next_dir = DIR_LEFT;
    else if (right_c && dir != DIR_LEFT) next_dir = DIR_RIGHT;
end

// 4. Game state: Head position, length, and game over status
reg [4:0] head_x, head_y;
reg [5:0] length;
reg       game_over;

// Simple pseudo-random generator for food positioning based on clock cycles
reg [4:0] food_x, food_y;
reg [7:0] lfsr;
always @(posedge clk) begin
    if (!rst_n) lfsr <= 8'hA5;
    else lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
end

// Snake head movement and collision/food detection logic
always @(posedge clk) begin
    if (!rst_n) begin
        head_x    <= 5'd16;
        head_y    <= 5'd12;
        dir       <= DIR_RIGHT;
        length    <= 6'd4;
        game_over <= 1'b0;
        food_x    <= 5'd8;
        food_y    <= 5'd8;
    end else if (snake_step && !game_over) begin
        dir <= next_dir;

        // Update head position based on current direction with wall collision check
        case (next_dir)
            DIR_UP:    if (head_y == 0) game_over <= 1'b1; else head_y <= head_y - 1;
            DIR_DOWN:  if (head_y == GRID_H - 1) game_over <= 1'b1; else head_y <= head_y + 1;
            DIR_LEFT:  if (head_x == 0) game_over <= 1'b1; else head_x <= head_x - 1;
            DIR_RIGHT: if (head_x == GRID_W - 1) game_over <= 1'b1; else head_x <= head_x + 1;
        endcase

        // Check food consumption
        if (head_x == food_x && head_y == food_y) begin
            length <= length + 1;
            food_x <= lfsr[4:0] % GRID_W;
            food_y <= lfsr[7:5] % GRID_H;
        end
    end
end

// 5. Pixel-to-grid mapping for rendering (scaling 20x20 pixel blocks)
wire [4:0] pix_grid_x = x[9:4]; 
wire [4:0] pix_grid_y = y[9:4]; 

// Hit detections for rendering elements
wire is_head   = (pix_grid_x == head_x) && (pix_grid_y == head_y);
wire is_food   = (pix_grid_x == food_x) && (pix_grid_y == food_y);
wire is_grid_border = (x[3:0] == 4'd0) || (y[3:0] == 4'd0);

// 6. Color assignment: Food is red, snake head is green, background is dark/bright blue on game over
assign rgb = !active          ? 6'b00_00_00 :
             is_food          ? 6'b11_00_00 :
             is_head          ? 6'b00_11_00 :
             game_over        ? 6'b00_00_11 : 
             is_grid_border   ? 6'b01_01_01 : 6'b00_00_00;


endmodule
