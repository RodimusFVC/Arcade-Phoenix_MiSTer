//============================================================================
//  Phoenix core dispatcher: the boards and the shared CPU / sound chip pool, ROM and RAM blocks
//  Copyright (C) 2026 Rodimus
//
//  Only one board runs at a time, so every CPU, sound chip, ROM and board RAM exists once, here, and the active
//  board drives it through chip_pool_pkg buses / rom<n> / pool ports. Board (selected by the MRA variant byte):
//    phx  rtl/boards/phoenix/phx_board.sv  Phoenix + bootlegs (8085 / Z80), Pleiads, Survival
//
//  Index 0 layout:
//    rom0 0000-3FFF maincpu   rom1 4000-47FF bgtiles plane 1   rom2 4800-4FFF bgtiles plane 0
//    rom3 5000-57FF fgtiles plane 1   rom4 5800-5FFF fgtiles plane 0   rom5 6000-60FF / rom6 6100-61FF colour PROMs
//  Index 5: discrete sound engine program.
//============================================================================

module phoenix_board
(
    input  wire        clk,
    input  wire        reset,
    input  wire        pause,
    input  wire  [7:0] variant,
    input  wire  [7:0] opt,
    output wire        ce_pix,

    input  wire  [7:0] in0,
    input  wire  [7:0] ctrl,
    input  wire  [7:0] dsw0,
    input  wire  [7:0] dsw1,
    input  wire  [7:0] cab,

    input  wire [24:0] ioctl_addr,
    input  wire  [7:0] ioctl_dout,
    input  wire        ioctl_wr0,
    input  wire        prog_wr,      // MRA index 5: discrete sound engine program
    input  wire [12:0] prog_addr,
    input  wire  [7:0] prog_data,

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

    output wire signed [15:0] audio,

    output wire [15:0] cpu_addr,
    output wire        cpu_m1,

    input  wire [15:0] hs_address,
    input  wire  [7:0] hs_data_in,
    output wire  [7:0] hs_data_out,
    input  wire        hs_write
);

/////////////////////////////  Boards  /////////////////////////////

localparam RAM_BLOCKS = 2;           // board RAM pool: block count, address width
localparam RAM_AW     = 12;

chip_pool_pkg::z80pa85_i_t phx_z80pa85_0_i, z80pa85_0_i;
chip_pool_pkg::z80pa85_o_t z80pa85_0_o;
chip_pool_pkg::ay_i_t      phx_ay_0_i, ay_0_i;
chip_pool_pkg::ay_o_t      ay_0_o;
chip_pool_pkg::tms36xx_i_t phx_tms36xx_0_i, tms36xx_0_i;
chip_pool_pkg::tms36xx_o_t tms36xx_0_o;
chip_pool_pkg::dsnd_i_t    phx_dsnd_0_i, dsnd_0_i;
chip_pool_pkg::dsnd_o_t    dsnd_0_o;

wire [13:0] rom0_a;  wire [7:0] rom0_d;
wire [10:0] rom1_a;  wire [7:0] rom1_d;
wire [10:0] rom2_a;  wire [7:0] rom2_d;
wire [10:0] rom3_a;  wire [7:0] rom3_d;
wire [10:0] rom4_a;  wire [7:0] rom4_d;
wire  [7:0] rom5_a;  wire [7:0] rom5_d;
wire  [7:0] rom6_a;  wire [7:0] rom6_d;
ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] phx_pr_i, pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;

phx_board u_phx
(
    .clk(clk), .reset(reset), .pause(pause), .variant(variant), .opt(opt), .ce_pix(ce_pix),
    .in0(in0), .ctrl(ctrl), .dsw0(dsw0), .dsw1(dsw1), .cab(cab),
    .z80pa85_0_i(phx_z80pa85_0_i), .z80pa85_0_o(z80pa85_0_o),
    .ay_0_i(phx_ay_0_i), .ay_0_o(ay_0_o),
    .tms36xx_0_i(phx_tms36xx_0_i), .tms36xx_0_o(tms36xx_0_o),
    .dsnd_0_i(phx_dsnd_0_i), .dsnd_0_o(dsnd_0_o),
    .rom0_a(rom0_a), .rom0_d(rom0_d), .rom1_a(rom1_a), .rom1_d(rom1_d), .rom2_a(rom2_a), .rom2_d(rom2_d),
    .rom3_a(rom3_a), .rom3_d(rom3_d), .rom4_a(rom4_a), .rom4_d(rom4_d), .rom5_a(rom5_a), .rom5_d(rom5_d),
    .rom6_a(rom6_a), .rom6_d(rom6_d),
    .pr_i(phx_pr_i), .pr_o(pool_o),
    .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .video_r(video_r), .video_g(video_g), .video_b(video_b), .video_hs(video_hs), .video_vs(video_vs),
    .video_hblank(video_hblank), .video_vblank(video_vblank),
    .audio(audio), .cpu_addr(cpu_addr), .cpu_m1(cpu_m1),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(hs_data_out), .hs_write(hs_write)
);

// one board so far: its buses drive the pool directly
assign z80pa85_0_i = phx_z80pa85_0_i;
assign ay_0_i      = phx_ay_0_i;
assign tms36xx_0_i = phx_tms36xx_0_i;
assign dsnd_0_i    = phx_dsnd_0_i;
assign pool_i      = phx_pr_i;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// z80pa85_0: phx main CPU (8085 = 8080 mode + RIM, paced by the board; Z80 for the condor-machine bootlegs)
wire [15:0] z80pa85_0_a;
wire  [7:0] z80pa85_0_do;
wire        z80pa85_0_m1_n, z80pa85_0_mreq_n, z80pa85_0_iorq_n, z80pa85_0_rd_n, z80pa85_0_wr_n, z80pa85_0_rfsh_n, z80pa85_0_sod;
T80pa #(.Mode(0)) z80pa85_0
(
    .RESET_n(~reset), .CLK(clk), .CEN_p(z80pa85_0_i.cen_p), .CEN_n(z80pa85_0_i.cen_n),
    .WAIT_n(z80pa85_0_i.wait_n), .INT_n(z80pa85_0_i.int_n), .NMI_n(z80pa85_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80pa85_0_m1_n), .MREQ_n(z80pa85_0_mreq_n), .IORQ_n(z80pa85_0_iorq_n), .RD_n(z80pa85_0_rd_n),
    .WR_n(z80pa85_0_wr_n), .RFSH_n(z80pa85_0_rfsh_n), .HALT_n(), .BUSAK_n(),
    .OUT0(1'b0), .A(z80pa85_0_a), .DI(z80pa85_0_i.di), .DO(z80pa85_0_do), .R800_mode(1'b0),
    .I8080(z80pa85_0_i.i8080), .I8085(z80pa85_0_i.i8085), .RIM_D(z80pa85_0_i.rim_d), .SOD(z80pa85_0_sod),
    .REG(), .DIRSet(1'b0), .DIR(212'd0)
);
assign z80pa85_0_o.a      = z80pa85_0_a;      assign z80pa85_0_o.dout   = z80pa85_0_do;
assign z80pa85_0_o.m1_n   = z80pa85_0_m1_n;   assign z80pa85_0_o.mreq_n = z80pa85_0_mreq_n;
assign z80pa85_0_o.iorq_n = z80pa85_0_iorq_n; assign z80pa85_0_o.rd_n   = z80pa85_0_rd_n;
assign z80pa85_0_o.wr_n   = z80pa85_0_wr_n;   assign z80pa85_0_o.rfsh_n = z80pa85_0_rfsh_n;
assign z80pa85_0_o.sod    = z80pa85_0_sod;

// ay_0: phx Survival AY-3-8910 (jt49_bus, sel = 1)
wire [7:0] ay_0_dout, ay_0_a, ay_0_b, ay_0_c, ay_0_iob;
wire [9:0] ay_0_snd;
jt49_bus ay_0
(
    .rst_n(~reset), .clk(clk), .clk_en(ay_0_i.ce), .bdir(ay_0_i.bdir), .bc1(ay_0_i.bc1), .din(ay_0_i.din), .sel(1'b1),
    .dout(ay_0_dout), .sound(ay_0_snd), .A(ay_0_a), .B(ay_0_b), .C(ay_0_c), .sample(),
    .IOA_in(ay_0_i.ioa_in), .IOA_out(), .IOB_in(ay_0_i.iob_in), .IOB_out(ay_0_iob)
);
assign ay_0_o.dout = ay_0_dout; assign ay_0_o.a = ay_0_a; assign ay_0_o.b = ay_0_b; assign ay_0_o.c = ay_0_c;
assign ay_0_o.iob_out = ay_0_iob; assign ay_0_o.sound = ay_0_snd;

// tms36xx_0: phx Phoenix MM6221AA <49>; cfg_b selects the Pleiads voicing (TMS3615 stand-in for the Epson 7910)
wire signed [15:0] tms36xx_0_audio;
wire               tms36xx_0_ce;
tms36xx #(.CLK_HZ(44_000_000), .BASEFREQ(372), .SPEED(156033),
          .DECAY0_MS(500), .DECAY1_MS(0), .DECAY2_MS(0), .DECAY3_MS(1050), .DECAY4_MS(0), .DECAY5_MS(0),
          .BASEFREQ_B(247), .SPEED_B(0),
          .DECAY0_MS_B(330), .DECAY1_MS_B(330), .DECAY2_MS_B(0), .DECAY3_MS_B(330), .DECAY4_MS_B(0), .DECAY5_MS_B(330)) tms36xx_0
(
    .clk(clk), .reset(reset), .cfg_b(tms36xx_0_i.cfg_b),
    .tune_we(tms36xx_0_i.tune_we), .tune(tms36xx_0_i.tune),
    .note_we(tms36xx_0_i.note_we), .note_octave(tms36xx_0_i.note_octave), .note(tms36xx_0_i.note),
    .enable_we(tms36xx_0_i.enable_we), .voice_enable(tms36xx_0_i.voice_enable),
    .audio(tms36xx_0_audio), .ce_snd(tms36xx_0_ce)
);
assign tms36xx_0_o.audio = tms36xx_0_audio; assign tms36xx_0_o.ce_snd = tms36xx_0_ce;

// dsnd_0: sound board effects / noise; program loaded via MRA index 5
wire signed [15:0] dsnd_0_out;
dsnd_engine #(.TICK(917)) dsnd_0
(
    .clk(clk), .reset(reset), .pause(pause),
    .prog_wr(prog_wr), .prog_addr(prog_addr), .prog_data(prog_data),
    .src(dsnd_0_i.src),
    // DSNDMERGE-2026-10-27: original below (dsnd_o_t now carries out_r / sample)
    // .out(dsnd_0_out)
    .out(dsnd_0_out), .out_r(dsnd_0_o.out_r), .sample(dsnd_0_o.sample)
);
assign dsnd_0_o.out = dsnd_0_out;

/////////////////////////////  Shared ROM blocks  /////////////////////////////
// port A = the index-0 download, port B = the board's reads

wire load_rom0 = ioctl_wr0 && ioctl_addr[24:14] == 11'd0;          // 0000-3FFF
wire load_rom1 = ioctl_wr0 && ioctl_addr[24:11] == 14'h08;         // 4000-47FF
wire load_rom2 = ioctl_wr0 && ioctl_addr[24:11] == 14'h09;         // 4800-4FFF
wire load_rom3 = ioctl_wr0 && ioctl_addr[24:11] == 14'h0A;         // 5000-57FF
wire load_rom4 = ioctl_wr0 && ioctl_addr[24:11] == 14'h0B;         // 5800-5FFF
wire load_rom5 = ioctl_wr0 && ioctl_addr[24:8]  == 17'h60;         // 6000-60FF
wire load_rom6 = ioctl_wr0 && ioctl_addr[24:8]  == 17'h61;         // 6100-61FF

dpram_dc #(.widthad_a(14)) rom0 (.clock_a(clk), .address_a(ioctl_addr[13:0]), .data_a(ioctl_dout), .wren_a(load_rom0), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom0_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom0_d));
dpram_dc #(.widthad_a(11)) rom1 (.clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(load_rom1), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom1_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom1_d));
dpram_dc #(.widthad_a(11)) rom2 (.clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(load_rom2), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom2_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom2_d));
dpram_dc #(.widthad_a(11)) rom3 (.clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(load_rom3), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom3_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom3_d));
dpram_dc #(.widthad_a(11)) rom4 (.clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(load_rom4), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom4_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom4_d));
dpram_dc #(.widthad_a(8))  rom5 (.clock_a(clk), .address_a(ioctl_addr[7:0]),  .data_a(ioctl_dout), .wren_a(load_rom5), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom5_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom5_d));
dpram_dc #(.widthad_a(8))  rom6 (.clock_a(clk), .address_a(ioctl_addr[7:0]),  .data_a(ioctl_dout), .wren_a(load_rom6), .byteena_a(1'b1), .q_a(),
                                 .clock_b(clk), .address_b(rom6_a), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(rom6_d));

/////////////////////////////  Shared RAM pool  /////////////////////////////
// Block 0: fg video RAM (2 pages x 2K); block 1: bg video RAM (2 pages x 2K). Port A = CPU, port B = display.
// dsnd_engine program / work RAMs are not pooled (64- / 32-bit wide, part of dsnd_0).

genvar n;
generate
    for (n = 0; n < RAM_BLOCKS; n++) begin : rpool
        dpram_dc #(.widthad_a(RAM_AW)) ram
        (
            .clock_a(clk), .address_a(pool_i[n].a_addr[RAM_AW-1:0]), .data_a(pool_i[n].a_d), .wren_a(pool_i[n].a_we),
            .byteena_a(1'b1), .q_a(pool_o[n].a_q),
            .clock_b(clk), .address_b(pool_i[n].b_addr[RAM_AW-1:0]), .data_b(pool_i[n].b_d), .wren_b(pool_i[n].b_we),
            .byteena_b(1'b1), .q_b(pool_o[n].b_q)
        );
    end
endgenerate

endmodule
