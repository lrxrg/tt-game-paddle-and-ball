// The game core: a lightweight Snake game optimized to fit strict Tiny Tapeout hardware limits.
`default_nettype none

module game_core #(
    parameter DB = 500000    // debounce time in clocks, 20 ms at 25 MHz
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        up,        // raw button up (active-high)
    input  wire        down,      // raw button down (active-high)
    input  wire        left,      // raw button left (active-high)
    input  wire        right,     // raw button right (active-high)
    input  wire [9:0] x,         // column of the pixel being drawn
    input  wire [9:0] y,         // row of the pixel being drawn
    input  wire        active,    // high inside the picture
    input  wire        frame,     // one clock pulse per picture
    output wire [5:0] rgb        // {R[1:0], G[1:0], B[1:0]}
);

    // 1. clean up the four buttons (active-high)
    wire up_c, down_c, left_c, right_c;
    ip_debounce #(.N(DB)) db_up    (.clk(clk), .rst_n(rst_n), .noisy(up),    .clean(up_c));
    ip_debounce #(.N(DB)) db_down  (.clk(clk), .rst_n(rst_n), .noisy(down),  .clean(down_c));
    ip_debounce #(.N(DB)) db_left  (.clk(clk), .rst_n(rst_n), .noisy(left),  .clean(left_c));
    ip_debounce #(.N(DB)) db_right (.clk(clk), .rst_n(rst_n), .noisy(right), .clean(right_c));

    // Edge detection for button presses
    reg up_prev, down_prev, left_prev, right_prev;
    always @(posedge clk) begin
        if (!rst_n) begin
            up_prev    <= 1'b0;
            down_prev  <= 1'b0;
            left_prev  <= 1'b0;
            right_prev <= 1'b0;
        end else begin
            up_prev    <= up_c;
            down_prev  <= down_c;
            left_prev  <= left_c;
            right_prev <= right_c;
        end
    end

    wire up_press    = up_c & ~up_prev;
    wire down_press  = down_c & ~down_prev;
    wire left_press  = left_c & ~left_prev;
    wire right_press = right_c & ~right_prev;

    // 2. snake moves every 4 frames
    wire snake_step;
    ip_tick #(.DIV(4)) snake_tick (.clk(clk), .rst_n(rst_n), .en(frame), .tick(snake_step));

    // 3. Grid setup: 640x480 screen -> 40x30 grid of 16x16 pixel cells
    // Directions: 0=UP, 1=RIGHT, 2=DOWN, 3=LEFT
    reg [1:0] dir;
    reg [1:0] pending_dir;
    reg       has_pending;
    reg [5:0] head_x;
    reg [4:0] head_y;
    reg [1:0] length; // Compact length (max 3 body segments)

    // Minimal body history (0 to 2) to fit Tiny Tapeout area constraints
    reg [5:0] hist_x [0:2];
    reg [4:0] hist_y [0:2];

    // LFSR for food generation
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else if (frame) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    reg [5:0] food_x;
    reg [4:0] food_y;
    reg       game_over;

    integer i; // Loop variable for sequential block
    always @(posedge clk) begin
        if (!rst_n) begin
            dir         <= 2'd1; // start moving right
            pending_dir <= 2'd1;
            has_pending <= 1'b0;
            head_x      <= 6'd20;
            head_y      <= 5'd15;
            length      <= 2'd2;  // initial length 2 body segments
            game_over   <= 1'b0;
            food_x      <= 6'd10;
            food_y      <= 5'd10;
            
            // Spread initial body segments to the left
            hist_x[0] <= 6'd19; hist_y[0] <= 5'd15;
            hist_x[1] <= 6'd18; hist_y[1] <= 5'd15;
            hist_x[2] <= 6'd18; hist_y[2] <= 5'd15;
        end else if (!game_over) begin
            // Capture button presses into pending buffer
            if (up_press    && (dir != 2'd2) && (!has_pending || pending_dir != 2'd2)) begin
                pending_dir <= 2'd0;
                has_pending <= 1'b1;
            end
            if (right_press && (dir != 2'd3) && (!has_pending || pending_dir != 2'd3)) begin
                pending_dir <= 2'd1;
                has_pending <= 1'b1;
            end
            if (down_press  && (dir != 2'd0) && (!has_pending || pending_dir != 2'd0)) begin
                pending_dir <= 2'd2;
                has_pending <= 1'b1;
            end
            if (left_press  && (dir != 2'd1) && (!has_pending || pending_dir != 2'd1)) begin
                pending_dir <= 2'd3;
                has_pending <= 1'b1;
            end

            if (snake_step) begin
                if (has_pending) begin
                    dir <= pending_dir;
                    has_pending <= 1'b0;
                end

                // Shift body history up to 2
                for (i = 2; i > 0; i = i - 1) begin
                    if (i < length) begin
                        hist_x[i] <= hist_x[i-1];
                        hist_y[i] <= hist_y[i-1];
                    end
                end
                hist_x[0] <= head_x;
                hist_y[0] <= head_y;

                // Move head based on current direction
                case (dir)
                    2'd0: begin // UP
                        if (head_y == 0) game_over <= 1'b1;
                        else head_y <= head_y - 5'd1;
                    end
                    2'd1: begin // RIGHT
                        if (head_x == 39) game_over <= 1'b1;
                        else head_x <= head_x + 6'd1;
                    end
                    2'd2: begin // DOWN
                        if (head_y == 29) game_over <= 1'b1;
                        else head_y <= head_y + 5'd1;
                    end
                    2'd3: begin // LEFT
                        if (head_x == 0) game_over <= 1'b1;
                        else head_x <= head_x - 6'd1;
                    end
                endcase

                // Self collision check up to 2
                for (i = 0; i < 3; i = i + 1) begin
                    if ((i < length) && (head_x == hist_x[i]) && (head_y == hist_y[i]))
                        game_over <= 1'b1;
                end

                // Food collision check (grows up to length 3)
                if ((head_x == food_x) && (head_y == food_y)) begin
                    if (length < 2'd3) length <= length + 2'd1;
                    food_x <= lfsr[5:0] % 6'd40;
                    food_y <= lfsr[10:6] % 5'd30;
                end
            end
        end
    end

    // 4. Pixel grid mapping (16x16 pixel blocks)
    wire [5:0] cur_gx = x[9:4]; 
    wire [4:0] cur_gy = y[9:4]; 

    wire is_head = (cur_gx == head_x) && (cur_gy == head_y);
    wire is_food = (cur_gx == food_x) && (cur_gy == food_y);

    integer j; // Separate loop variable for combinatorial block
    reg is_body;
    always @* begin
        is_body = 1'b0;
        for (j = 0; j < 3; j = j + 1) begin
            if ((j < length) && (cur_gx == hist_x[j]) && (cur_gy == hist_y[j]))
                is_body = 1'b1;
        end
    end

    // 5. Colour output: Red on game over, Yellow food, Cyan head, Green body, Dark background
    assign rgb = !active     ? 6'b00_00_00 :
                 game_over   ? 6'b11_00_00 :
                 is_food     ? 6'b11_11_00 :
                 is_head     ? 6'b00_11_11 :
                 is_body     ? 6'b00_11_00 :
                               6'b01_01_01;
endmodule
