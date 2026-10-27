//============================================================================
//  board_template.sv: starting point for a new board (copy it; not listed in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards own no CPU, sound chip, ROM store or board RAM; those live once in rtl/phoenix_board.sv and the board
//  drives the pool ports below. To add a board: add it to files.qip and verilator/Makefile, instance it in the
//  dispatcher's "Boards" section and put it on the variant muxes. For more RAM, grow RAM_BLOCKS / RAM_AW in the
//  dispatcher. A private RAM / chip that cannot pool needs "// POOL-EXCEPTION: <reason>" on its instance line.
//============================================================================

module board_template
(
    input  wire        clk,
    input  wire        reset,
    input  wire        pause,
    input  wire  [7:0] variant,
    input  wire  [7:0] opt,
    output wire        ce_pix,

    // shared CPU / sound chip pool (rtl/chip_pool_pkg.sv)
    output chip_pool_pkg::z80pa85_i_t z80pa85_0_i,
    input  chip_pool_pkg::z80pa85_o_t z80pa85_0_o,
    output chip_pool_pkg::ay_i_t      ay_0_i,
    input  chip_pool_pkg::ay_o_t      ay_0_o,
    output chip_pool_pkg::tms36xx_i_t tms36xx_0_i,
    input  chip_pool_pkg::tms36xx_o_t tms36xx_0_o,
    output chip_pool_pkg::dsnd_i_t    dsnd_0_i,
    input  chip_pool_pkg::dsnd_o_t    dsnd_0_o,
    // shared ROM blocks (port B reads; index-0 layout in the dispatcher header)
    output wire [13:0] rom0_a,  input wire [7:0] rom0_d,
    output wire [10:0] rom1_a,  input wire [7:0] rom1_d,
    output wire [10:0] rom2_a,  input wire [7:0] rom2_d,
    output wire [10:0] rom3_a,  input wire [7:0] rom3_d,
    output wire [10:0] rom4_a,  input wire [7:0] rom4_d,
    output wire  [7:0] rom5_a,  input wire [7:0] rom5_d,
    output wire  [7:0] rom6_a,  input wire [7:0] rom6_d,
    // board RAM pool (rtl/ram_pool_pkg.sv): RAM_BLOCKS = 2 blocks of 4K x 8, two read / write ports each, one clock to q
    output ram_pool_pkg::pram_i_t [1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [1:0] pr_o,

    input  wire        crt_flip,
    input  wire  [3:0] h_adj,
    input  wire  [3:0] v_adj,

    output wire  [7:0] video_r,
    output wire  [7:0] video_g,
    output wire  [7:0] video_b,
    output wire        video_hs,
    output wire        video_vs,
    output wire        video_hblank,
    output wire        video_vblank,

    output wire signed [15:0] audio
);

endmodule
