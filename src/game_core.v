// The game core: a growing Snake game (up to 6 segments) optimized with unrolled logic.
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

    // 3. Grid setup: 40x30 grid of 16x16 pixel cells
    // Directions: 0=UP, 1=RIGHT, 2=DOWN, 3=LEFT
    reg [1:0] dir;
    reg [1:0] pending_dir;
    reg       has_pending;
    
    // Snake parts: Head + 5 body segments (grows from length 2 up to 6)
    reg [5:0] head_x, b1_x, b2_x, b3_x, b4_x, b5_x;
    reg [4:0] head_y, b1_y, b2_y, b3_y, b4_y, b5_y;
    reg [2:0] length; // 2 to 6 segments

    // LFSR for food generation
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else if (frame) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // Lightweight food coordinate mapping (zero division/modulo logic)
    wire [5:0] raw_fx = lfsr[5:0];
    wire [4:0] raw_fy = lfsr[10:6];
    wire [5:0] next_food_x = (raw_fx >= 6'd40) ? (raw_fx - 6'd40) : raw_fx;
    wire [4:0] next_food_y = (raw_fy >= 5'd30) ? (raw_fy - 5'd30) : raw_fy;

    reg [5:0] food_x;
    reg [4:0] food_y;
    reg       game_over;

    always @(posedge clk) begin
        if (!rst_n) begin
            dir         <= 2'd1; // start moving right
            pending_dir <= 2'd1;
            has_pending <= 1'b0;
            head_x      <= 6'd20; head_y <= 5'd15;
            b1_x        <= 6'd19; b1_y   <= 5'd15;
            b2_x        <= 6'd18; b2_y   <= 5'd15;
            b3_x        <= 6'd18; b3_y   <= 5'd15;
            b4_x        <= 6'd18; b4_y   <= 5'd15;
            b5_x        <= 6'd18; b5_y   <= 5'd15;
            length      <= 3'd2;  // start small (head + 1 body segment) and grow up to 6!
            game_over   <= 1'b0;
            food_x      <= 6'd10;
            food_y      <= 5'd10;
        end else if (!game_over) begin
            // Capture button presses into pending buffer (preventing 180-degree self-reversals)
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

                // Shift body segments forward
                b5_x <= b4_x; b5_y <= b4_y;
                b4_x <= b3_x; b4_y <= b3_y;
                b3_x <= b2_x; b3_y <= b2_y;
                b2_x <= b1_x; b2_y <= b1_y;
                b1_x <= head_x; b1_y <= head_y;

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

                // Self collision check (unrolled)
                if ((length >= 3'd2 && head_x == b1_x && head_y == b1_y) ||
                    (length >= 3'd3 && head_x == b2_x && head_y == b2_y) ||
                    (length >= 3'd4 && head_x == b3_x && head_y == b3_y) ||
                    (length >= 3'd5 && head_x == b4_x && head_y == b4_y) ||
                    (length >= 3'd6 && head_x == b5_x && head_y == b5_y)) begin
                    game_over <= 1'b1;
                end

                // Food collision check (grows snake length up to 6)
                if ((head_x == food_x) && (head_y == food_y)) begin
                    if (length < 3'd6) length <= length + 3'd1;
                    food_x <= next_food_x;
                    food_y <= next_food_y;
                end
            end
        end
    end

    // 4. Pixel grid mapping (16x16 pixel blocks) - Fully unrolled combinatorial logic (ZERO LOOPS)
    wire [5:0] cur_gx = x[9:4]; 
    wire [4:0] cur_gy = y[9:4]; 

    wire is_head = (cur_gx == head_x) && (cur_gy == head_y);
    wire is_b1   = (length >= 3'd2) && (cur_gx == b1_x) && (cur_gy == b1_y);
    wire is_b2   = (length >= 3'd3) && (cur_gx == b2_x) && (cur_gy == b2_y);
    wire is_b3   = (length >= 3'd4) && (cur_gx == b3_x) && (cur_gy == b3_y);
    wire is_b4   = (length >= 3'd5) && (cur_gx == b4_x) && (cur_gy == b4_y);
    wire is_b5   = (length >= 3'd6) && (cur_gx == b5_x) && (cur_gy == b5_y);
    wire is_body = is_b1 || is_b2 || is_b3 || is_b4 || is_b5;
    wire is_food = (cur_gx == food_x) && (cur_gy == food_y);

    // 5. Colour output: Red on game over, Yellow food, Cyan head, Green body segments, Dark background
    assign rgb = !active     ? 6'b00_00_00 :
                 game_over   ? 6'b11_00_00 :
                 is_food     ? 6'b11_11_00 :
                 is_head     ? 6'b00_11_11 :
                 is_body     ? 6'b00_11_00 :
                               6'b01_01_01;
endmodule
