//  Based on MAME phoenix/phoenix.cpp (license:BSD-3-Clause, copyright-holders: Richard Davies)
//  Copyright (C) 2026 Rodimus

module phx_board
(
    input  wire        clk,
    input  wire        reset,
    input  wire        pause,
    input  wire  [7:0] variant,
    input  wire  [7:0] opt,
    output wire        ce_pix,

    input  wire  [7:0] in0,
    input  wire  [7:0] ctrl,
    input  wire  [7:0] dsw0,         // MRA port 2: DSW0 (bit 7 = vblank)
    input  wire  [7:0] dsw1,
    input  wire  [7:0] cab,

    output chip_pool_pkg::z80pa85_i_t z80pa85_0_i,
    input  chip_pool_pkg::z80pa85_o_t z80pa85_0_o,
    output chip_pool_pkg::ay_i_t      ay_0_i,
    input  chip_pool_pkg::ay_o_t      ay_0_o,
    output chip_pool_pkg::tms36xx_i_t tms36xx_0_i,
    input  chip_pool_pkg::tms36xx_o_t tms36xx_0_o,
    output chip_pool_pkg::dsnd_i_t    dsnd_0_i,
    input  chip_pool_pkg::dsnd_o_t    dsnd_0_o,
    output wire [13:0] rom0_a,  input wire [7:0] rom0_d,
    output wire [10:0] rom1_a,  input wire [7:0] rom1_d,
    output wire [10:0] rom2_a,  input wire [7:0] rom2_d,
    output wire [10:0] rom3_a,  input wire [7:0] rom3_d,
    output wire [10:0] rom4_a,  input wire [7:0] rom4_d,
    output wire  [7:0] rom5_a,  input wire [7:0] rom5_d,
    output wire  [7:0] rom6_a,  input wire [7:0] rom6_d,
    output ram_pool_pkg::pram_i_t [1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [1:0] pr_o,

    input  wire        crt_flip,
    input  wire  [3:0] h_adj,
    input  wire  [3:0] v_adj,

    output reg   [7:0] video_r,
    output reg   [7:0] video_g,
    output reg   [7:0] video_b,
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

wire v_pleiads = variant == 8'd1;
wire v_surv    = variant == 8'd2;

reg [3:0] div = 4'd0;
always @(posedge clk) div <= div + 4'd1;
assign ce_pix    = div[2:0] == 3'd7;
wire   cpu_cen_p = (opt[2] ? div == 4'd15 : div[2:0] == 3'd7) && !pause;
wire   cpu_cen_n = (opt[2] ? div == 4'd7  : div[2:0] == 3'd3) && !pause;

reg [8:0] hcnt = 9'd0;
reg [7:0] vcnt = 8'd0;
always @(posedge clk) if (ce_pix) begin
    if (hcnt == 9'd351) begin
        hcnt <= 9'd0;
        vcnt <= vcnt + 8'd1;
    end else
        hcnt <= hcnt + 9'd1;
end
wire hbl = hcnt[8];
wire vbl = vcnt >= 8'd208;

wire [8:0] hs_start = 9'd272 - {{5{h_adj[3]}}, h_adj};
wire [7:0] vs_start = 8'd224 - {{4{v_adj[3]}}, v_adj};
wire [8:0] hs_end   = hs_start + 9'd32;
wire [7:0] vs_end   = vs_start + 8'd8;
wire hsync = hcnt >= hs_start && hcnt < hs_end;
wire vsync = vcnt >= vs_start && vcnt < vs_end;

wire [15:0] A;
reg         surv_sid = 1'b0;
wire        cpu_wait_n;
wire  [7:0] cpu_do;
reg   [7:0] cpu_di;
wire        m1_n, mreq_n, rd_n, wr_n, rfsh_n;

assign z80pa85_0_i.cen_p  = cpu_cen_p;
assign z80pa85_0_i.cen_n  = cpu_cen_n;
assign z80pa85_0_i.wait_n = cpu_wait_n;
assign z80pa85_0_i.int_n  = 1'b1;
assign z80pa85_0_i.nmi_n  = 1'b1;
assign z80pa85_0_i.i8080  = ~opt[2];
assign z80pa85_0_i.i8085  = ~opt[2];
assign z80pa85_0_i.rim_d  = {surv_sid, 7'h0F};
assign z80pa85_0_i.di     = cpu_di;
assign A      = z80pa85_0_o.a;
assign cpu_do = z80pa85_0_o.dout;
assign m1_n   = z80pa85_0_o.m1_n;
assign mreq_n = z80pa85_0_o.mreq_n;
assign rd_n   = z80pa85_0_o.rd_n;
assign wr_n   = z80pa85_0_o.wr_n;
assign rfsh_n = z80pa85_0_o.rfsh_n;

assign cpu_addr = A;
assign cpu_m1   = ~m1_n & ~mreq_n;

wire mem_rd = ~mreq_n & ~rd_n & rfsh_n;

function automatic [4:0] cyc_base (input [7:0] op);
    case (op)
        8'h01: cyc_base = 5'd10;
        8'h02: cyc_base = 5'd7;
        8'h03: cyc_base = 5'd6;
        8'h06: cyc_base = 5'd7;
        8'h08: cyc_base = 5'd10;
        8'h09: cyc_base = 5'd10;
        8'h0A: cyc_base = 5'd7;
        8'h0B: cyc_base = 5'd6;
        8'h0E: cyc_base = 5'd7;
        8'h10: cyc_base = 5'd7;
        8'h11: cyc_base = 5'd10;
        8'h12: cyc_base = 5'd7;
        8'h13: cyc_base = 5'd6;
        8'h16: cyc_base = 5'd7;
        8'h18: cyc_base = 5'd10;
        8'h19: cyc_base = 5'd10;
        8'h1A: cyc_base = 5'd7;
        8'h1B: cyc_base = 5'd6;
        8'h1E: cyc_base = 5'd7;
        8'h21: cyc_base = 5'd10;
        8'h22: cyc_base = 5'd16;
        8'h23: cyc_base = 5'd6;
        8'h26: cyc_base = 5'd7;
        8'h28: cyc_base = 5'd10;
        8'h29: cyc_base = 5'd10;
        8'h2A: cyc_base = 5'd16;
        8'h2B: cyc_base = 5'd6;
        8'h2E: cyc_base = 5'd7;
        8'h31: cyc_base = 5'd10;
        8'h32: cyc_base = 5'd13;
        8'h33: cyc_base = 5'd6;
        8'h34: cyc_base = 5'd10;
        8'h35: cyc_base = 5'd10;
        8'h36: cyc_base = 5'd10;
        8'h38: cyc_base = 5'd10;
        8'h39: cyc_base = 5'd10;
        8'h3A: cyc_base = 5'd13;
        8'h3B: cyc_base = 5'd6;
        8'h3E: cyc_base = 5'd7;
        8'h46: cyc_base = 5'd7;
        8'h4E: cyc_base = 5'd7;
        8'h56: cyc_base = 5'd7;
        8'h5E: cyc_base = 5'd7;
        8'h66: cyc_base = 5'd7;
        8'h6E: cyc_base = 5'd7;
        8'h70: cyc_base = 5'd7;
        8'h71: cyc_base = 5'd7;
        8'h72: cyc_base = 5'd7;
        8'h73: cyc_base = 5'd7;
        8'h74: cyc_base = 5'd7;
        8'h75: cyc_base = 5'd7;
        8'h76: cyc_base = 5'd5;
        8'h77: cyc_base = 5'd7;
        8'h7E: cyc_base = 5'd7;
        8'h86: cyc_base = 5'd7;
        8'h8E: cyc_base = 5'd7;
        8'h96: cyc_base = 5'd7;
        8'h9E: cyc_base = 5'd7;
        8'hA6: cyc_base = 5'd7;
        8'hAE: cyc_base = 5'd7;
        8'hB6: cyc_base = 5'd7;
        8'hBE: cyc_base = 5'd7;
        8'hC0: cyc_base = 5'd6;
        8'hC1: cyc_base = 5'd10;
        8'hC2: cyc_base = 5'd7;
        8'hC3: cyc_base = 5'd7;
        8'hC4: cyc_base = 5'd9;
        8'hC5: cyc_base = 5'd12;
        8'hC6: cyc_base = 5'd7;
        8'hC7: cyc_base = 5'd12;
        8'hC8: cyc_base = 5'd6;
        8'hC9: cyc_base = 5'd10;
        8'hCA: cyc_base = 5'd7;
        8'hCB: cyc_base = 5'd6;
        8'hCC: cyc_base = 5'd9;
        8'hCD: cyc_base = 5'd9;
        8'hCE: cyc_base = 5'd7;
        8'hCF: cyc_base = 5'd12;
        8'hD0: cyc_base = 5'd6;
        8'hD1: cyc_base = 5'd10;
        8'hD2: cyc_base = 5'd7;
        8'hD3: cyc_base = 5'd10;
        8'hD4: cyc_base = 5'd9;
        8'hD5: cyc_base = 5'd12;
        8'hD6: cyc_base = 5'd7;
        8'hD7: cyc_base = 5'd12;
        8'hD8: cyc_base = 5'd6;
        8'hD9: cyc_base = 5'd10;
        8'hDA: cyc_base = 5'd7;
        8'hDB: cyc_base = 5'd10;
        8'hDC: cyc_base = 5'd9;
        8'hDD: cyc_base = 5'd7;
        8'hDE: cyc_base = 5'd7;
        8'hDF: cyc_base = 5'd12;
        8'hE0: cyc_base = 5'd6;
        8'hE1: cyc_base = 5'd10;
        8'hE2: cyc_base = 5'd7;
        8'hE3: cyc_base = 5'd16;
        8'hE4: cyc_base = 5'd9;
        8'hE5: cyc_base = 5'd12;
        8'hE6: cyc_base = 5'd7;
        8'hE7: cyc_base = 5'd12;
        8'hE8: cyc_base = 5'd6;
        8'hE9: cyc_base = 5'd6;
        8'hEA: cyc_base = 5'd7;
        8'hEC: cyc_base = 5'd9;
        8'hED: cyc_base = 5'd10;
        8'hEE: cyc_base = 5'd7;
        8'hEF: cyc_base = 5'd12;
        8'hF0: cyc_base = 5'd6;
        8'hF1: cyc_base = 5'd10;
        8'hF2: cyc_base = 5'd7;
        8'hF4: cyc_base = 5'd9;
        8'hF5: cyc_base = 5'd12;
        8'hF6: cyc_base = 5'd7;
        8'hF7: cyc_base = 5'd12;
        8'hF8: cyc_base = 5'd6;
        8'hF9: cyc_base = 5'd6;
        8'hFA: cyc_base = 5'd7;
        8'hFC: cyc_base = 5'd9;
        8'hFD: cyc_base = 5'd7;
        8'hFE: cyc_base = 5'd7;
        8'hFF: cyc_base = 5'd12;
        default: cyc_base = 5'd4;
    endcase
endfunction

reg  [7:0] op_cur = 8'd0, di_d = 8'd0;
reg [15:0] pc_cur = 16'd0;
reg        m1_d = 1'b0, op_valid = 1'b0;
reg signed [11:0] pace = 12'sd0;
wire       m1_now = ~m1_n & ~mreq_n;
wire       m1_rise = m1_now & ~m1_d;
wire [2:0] op_len  = (op_cur[7:6] == 2'b11 && op_cur[2:0] == 3'b010) || (op_cur[7:6] == 2'b11 && op_cur[2:0] == 3'b100) ||
                     op_cur == 8'hC3 || op_cur == 8'hCD ? 3'd3 : 3'd1;
wire       seq     = A == pc_cur + 16'(op_len);
wire [4:0] cyc_x   = (op_cur == 8'hC3) ? 5'd3 :
                     (op_cur == 8'hCD) ? 5'd9 :
                     (op_cur[7:6] == 2'b11 && op_cur[2:0] == 3'b000 && !seq) ? 5'd6 :
                     (op_cur[7:6] == 2'b11 && op_cur[2:0] == 3'b010 && !seq) ? 5'd3 :
                     (op_cur[7:6] == 2'b11 && op_cur[2:0] == 3'b100 && !seq) ? 5'd9 : 5'd0;
wire [9:0] cyc_clk = 10'(cyc_base(op_cur) + cyc_x) << 4;
always @(posedge clk) begin
    di_d <= cpu_di;
    m1_d <= m1_now;
    if (reset || opt[2]) begin
        pace <= 12'sd0; op_valid <= 1'b0;
    end else begin
        if (m1_rise) begin
            pace     <= pace + (op_valid ? $signed({2'b0, cyc_clk}) : 12'sd0) - (pause ? 12'sd0 : 12'sd1);
            pc_cur   <= A;
            op_valid <= 1'b1;
        end else if (!pause && pace > -12'sd1024)
            pace <= pace - 12'sd1;
        if (~m1_now & m1_d) op_cur <= di_d;
    end
end
assign cpu_wait_n = !(m1_now && pace > 12'sd0);
wire mem_wr = ~mreq_n & ~wr_n;
reg  wr_d = 1'b0;
always @(posedge clk) wr_d <= mem_wr;
wire wr_stb = mem_wr & ~wr_d;

wire cs_rom    = A[15:14] == 2'b00;
wire cs_vram   = A[15:12] == 4'h4;
wire cs_vreg   = A[15:10] == 6'b0101_00;
wire cs_scroll = A[15:10] == 6'b0101_10;
wire cs_snda   = A[15:10] == 6'b0110_00 && !v_surv;
wire cs_sndb   = A[15:10] == 6'b0110_10 && !v_surv;
wire cs_ayadr  = A[15:8]  == 8'h68 && v_surv;
wire cs_aydat  = A[15:8]  == 8'h69 && v_surv;
wire cs_in0    = A[15:10] == 6'b0111_00;
wire cs_dsw0   = A[15:10] == 6'b0111_10;
wire cs_dsw1   = opt[1] && A == 16'h5000;

reg       page = 1'b0;
reg [1:0] pal_bank = 2'd0;
reg [7:0] scroll = 8'd0;
reg [7:0] prot_q = 8'd0;
reg [7:0] snd_a = 8'd0, snd_b = 8'd0;

always @(posedge clk) begin
    if (reset) begin
        page <= 1'b0; pal_bank <= 2'd0; scroll <= 8'd0; prot_q <= 8'd0; snd_a <= 8'd0; snd_b <= 8'd0;
    end else if (wr_stb) begin
        if (cs_vreg) begin
            page <= cpu_do[0];
            if (v_pleiads) begin
                pal_bank <= cpu_do[2:1];
                prot_q   <= cpu_do & 8'hFC;
            end else
                pal_bank <= {1'b0, cpu_do[1]};
        end
        if (cs_scroll) scroll <= cpu_do;
        if (cs_snda)   snd_a  <= cpu_do;
        if (cs_sndb)   snd_b  <= cpu_do;
    end
end

wire cocktail = page & cab[0];

wire [7:0] rom_q;
assign rom0_a = A[13:0];
assign rom_q  = rom0_d;

reg  [10:0] fg_va, bg_va;
wire  [7:0] fg_cq, bg_cq, fg_vq, bg_vq;
wire        vram_we = wr_stb & cs_vram;

wire [11:0] ram0_a, ram0_ba, ram1_a, ram1_ba;
wire  [7:0] ram0_wd, ram0_q, ram0_bq, ram1_wd, ram1_q, ram1_bq;
wire        ram0_we, ram1_we;
assign pr_i[0].a_addr = {3'd0, ram0_a};   assign pr_i[0].a_d = ram0_wd;  assign pr_i[0].a_we = ram0_we;
assign pr_i[0].b_addr = {3'd0, ram0_ba};  assign pr_i[0].b_d = 8'd0;     assign pr_i[0].b_we = 1'b0;
assign pr_i[1].a_addr = {3'd0, ram1_a};   assign pr_i[1].a_d = ram1_wd;  assign pr_i[1].a_we = ram1_we;
assign pr_i[1].b_addr = {3'd0, ram1_ba};  assign pr_i[1].b_d = 8'd0;     assign pr_i[1].b_we = 1'b0;
assign ram0_q = pr_o[0].a_q;  assign ram0_bq = pr_o[0].b_q;
assign ram1_q = pr_o[1].a_q;  assign ram1_bq = pr_o[1].b_q;
assign ram0_a  = {page, A[10:0]};  assign ram0_wd = cpu_do;  assign ram0_we = vram_we & ~A[11];  assign fg_cq = ram0_q;
assign ram1_a  = {page, A[10:0]};  assign ram1_wd = cpu_do;  assign ram1_we = vram_we &  A[11];  assign bg_cq = ram1_q;
assign ram0_ba = {page, fg_va};    assign fg_vq = ram0_bq;
assign ram1_ba = {page, bg_va};    assign bg_vq = ram1_bq;

wire [7:0] in0_v = {cocktail ? ctrl[7:4] : ctrl[3:0],
                    opt[3] ? ~(prot_q == 8'h0C || prot_q == 8'h30) : in0[3], in0[2:0]};
always @(*) begin
    cpu_di = 8'hFF;
    if (cs_rom)       cpu_di = rom_q;
    else if (cs_vram) cpu_di = A[11] ? bg_cq : fg_cq;
    else if (cs_dsw1) cpu_di = dsw1;
    else if (cs_aydat) cpu_di = ay_dout;
    else if (cs_in0)  cpu_di = v_surv ? surv_q : in0_v;
    else if (cs_dsw0) cpu_di = {~vbl, dsw0[6:0]};
end

reg  [1:0] surv_readc = 2'd0;
reg  [7:0] surv_lat0 = 8'd0, surv_lat1 = 8'd0, surv_prot = 8'd0, surv_q = 8'd0;
reg        in0_rd_d = 1'b0;
wire       in0_rd = mem_rd & cs_in0;
wire [7:0] surv_raw = ~(cocktail ? {ctrl[7:3], in0[2:0]} : in0);
reg  [3:0] surv_js;
reg        surv_s;
reg  [7:0] surv_p;
always @(*) begin
    surv_js = surv_raw[7:4]; surv_s = 1'b0; surv_p = 8'hFF;
    case (surv_raw[7:4])
        4'h0: surv_js = 4'h7;
        4'h1: surv_js = 4'h8;
        4'h2: begin surv_js = 4'h2; surv_s = 1'b1; surv_p = 8'hFE; end
        4'h3: begin surv_js = 4'hA; surv_s = 1'b1; end
        4'h4: begin surv_js = 4'h4; surv_s = 1'b1; surv_p = 8'hFE; end
        4'h5: begin surv_js = 4'hC; surv_s = 1'b1; end
        4'h8: surv_js = 4'h1;
        4'hA: begin surv_js = 4'h3; surv_s = 1'b1; end
        4'hC: begin surv_js = 4'h5; surv_s = 1'b1; end
        default: ;
    endcase
end
always @(posedge clk) begin
    in0_rd_d <= in0_rd;
    if (reset) begin
        surv_readc <= 2'd0; surv_lat0 <= 8'd0; surv_lat1 <= 8'd0; surv_prot <= 8'd0; surv_sid <= 1'b0; surv_q <= 8'd0;
    end else if (v_surv && in0_rd && !in0_rd_d) begin
        if (surv_readc == 2'd2) begin
            surv_readc <= 2'd0;
            surv_prot  <= 8'h00;
            surv_q     <= ~surv_raw;
        end else begin
            surv_readc <= surv_readc + 2'd1;
            surv_prot  <= surv_p;
            surv_sid   <= surv_s;
            surv_lat0  <= surv_lat1;
            surv_lat1  <= ~{surv_js, surv_raw[3:0]};
            surv_q     <= surv_lat1;
        end
    end
end

wire [7:0] ay_dout;
wire [9:0] ay_snd;
assign ay_0_i.ce     = div == 4'd15 && !pause;
assign ay_0_i.bdir   = (cs_ayadr | cs_aydat) & mem_wr;
assign ay_0_i.bc1    = (cs_ayadr & mem_wr) | (cs_aydat & mem_rd);
assign ay_0_i.din    = cpu_do;
assign ay_0_i.ioa_in = 8'hFF;
assign ay_0_i.iob_in = surv_prot;
assign ay_dout = ay_0_o.dout;
assign ay_snd  = ay_0_o.sound;

wire [7:0] cx = crt_flip ? 8'd255 - hcnt[7:0] : hcnt[7:0];
wire [7:0] cy = crt_flip ? 8'd207 - vcnt : vcnt;
wire [7:0] sx = cocktail ? ~cx : cx;
wire [7:0] sy = cocktail ? ~cy : cy;
wire [7:0] bx = sx + scroll;

reg  [2:0] s1_fx, s1_bx, s1_row;
reg  [2:0] s2_fx, s2_bx;
reg  [7:0] s2_fcode, s2_bcode;
reg  [1:0] s3_bank;
reg  [7:0] prom_a;

wire [7:0] bglo_q, bghi_q, fglo_q, fghi_q, prl_q, prh_q;

always @(posedge clk) if (ce_pix) begin
    fg_va  <= {1'b0, sy[7:3], sx[7:3]};
    bg_va  <= {1'b0, sy[7:3], bx[7:3]};
    s1_fx  <= sx[2:0];
    s1_bx  <= bx[2:0];
    s1_row <= sy[2:0];
    s2_fcode <= fg_vq;
    s2_bcode <= bg_vq;
    s2_fx    <= s1_fx;
    s2_bx    <= s1_bx;
end

reg [10:0] fg_ga, bg_ga;
always @(posedge clk) if (ce_pix) begin
    fg_ga <= {fg_vq, s1_row};
    bg_ga <= {bg_vq, s1_row};
end

assign rom1_a = bg_ga;  assign bglo_q = rom1_d;
assign rom2_a = bg_ga;  assign bghi_q = rom2_d;
assign rom3_a = fg_ga;  assign fglo_q = rom3_d;
assign rom4_a = fg_ga;  assign fghi_q = rom4_d;

wire [2:0] s2_fxb = s2_fx;
wire [1:0] fpix = {fghi_q[s2_fxb], fglo_q[s2_fxb]};
wire [1:0] bpix = {bghi_q[s2_bx],  bglo_q[s2_bx]};
wire       use_fg = fpix != 2'd0;
always @(posedge clk) if (ce_pix)
    prom_a <= use_fg ? {pal_bank, 1'b1, fpix, s2_fcode[7:5]} : {pal_bank, 1'b0, bpix, s2_bcode[7:5]};

assign rom5_a = prom_a;  assign prl_q = rom5_d;
assign rom6_a = prom_a;  assign prh_q = rom6_d;

wire [3:0] p0 = opt[0] ? prh_q[7:4] : prl_q[3:0];
wire [3:0] p1 = prh_q[3:0];
wire [5:0] lv = {p1[0], p0[0], p1[2], p0[2], p1[1], p0[1]};
reg [23:0] rgb, rgb_s;
always @(*) begin
    case (lv)
        6'b000000: rgb = 24'h000000;
        6'b000001: rgb = 24'h000000;
        6'b000010: rgb = 24'h070691;
        6'b000011: rgb = 24'h0A07BD;
        6'b000100: rgb = 24'h000000;
        6'b000101: rgb = 24'h000000;
        6'b000110: rgb = 24'h070691;
        6'b000111: rgb = 24'h0A07BD;
        6'b001000: rgb = 24'h23AD24;
        6'b001001: rgb = 24'h23AD24;
        6'b001010: rgb = 24'h2AB5B6;
        6'b001011: rgb = 24'h2DB8E0;
        6'b001100: rgb = 24'h2EDF2D;
        6'b001101: rgb = 24'h2EDF2D;
        6'b001110: rgb = 24'h35E7BF;
        6'b001111: rgb = 24'h36E8E9;
        6'b010000: rgb = 24'h000000;
        6'b010001: rgb = 24'h000000;
        6'b010010: rgb = 24'h070691;
        6'b010011: rgb = 24'h0A07BD;
        6'b010100: rgb = 24'h000000;
        6'b010101: rgb = 24'h000000;
        6'b010110: rgb = 24'h070691;
        6'b010111: rgb = 24'h0A07BD;
        6'b011000: rgb = 24'h23AD24;
        6'b011001: rgb = 24'h23AD24;
        6'b011010: rgb = 24'h2AB5B6;
        6'b011011: rgb = 24'h2DB8E0;
        6'b011100: rgb = 24'h2EDF2D;
        6'b011101: rgb = 24'h2EDF2D;
        6'b011110: rgb = 24'h35E7BF;
        6'b011111: rgb = 24'h36E8E9;
        6'b100000: rgb = 24'h9F1114;
        6'b100001: rgb = 24'h9F1114;
        6'b100010: rgb = 24'hA518A5;
        6'b100011: rgb = 24'hA71BCE;
        6'b100100: rgb = 24'h9F1114;
        6'b100101: rgb = 24'h9F1114;
        6'b100110: rgb = 24'hA518A5;
        6'b100111: rgb = 24'hA71BCE;
        6'b101000: rgb = 24'hC0C136;
        6'b101001: rgb = 24'hC0C136;
        6'b101010: rgb = 24'hC8C8C8;
        6'b101011: rgb = 24'hCCCAF1;
        6'b101100: rgb = 24'hCDF040;
        6'b101101: rgb = 24'hCDF040;
        6'b101110: rgb = 24'hD4F7D5;
        6'b101111: rgb = 24'hD5FBF9;
        6'b110000: rgb = 24'hCA1618;
        6'b110001: rgb = 24'hCA1618;
        6'b110010: rgb = 24'hD11EAA;
        6'b110011: rgb = 24'hD31FD2;
        6'b110100: rgb = 24'hCA1618;
        6'b110101: rgb = 24'hCA1618;
        6'b110110: rgb = 24'hD11EAA;
        6'b110111: rgb = 24'hD31FD2;
        6'b111000: rgb = 24'hEDC63A;
        6'b111001: rgb = 24'hEDC63A;
        6'b111010: rgb = 24'hF4CDCF;
        6'b111011: rgb = 24'hF5D0F5;
        6'b111100: rgb = 24'hF6F644;
        6'b111101: rgb = 24'hF6F644;
        6'b111110: rgb = 24'hFDFDD9;
        6'b111111: rgb = 24'hFFFFFF;
        default: rgb = 24'h000000;
    endcase
    case (lv)
        6'b000000: rgb_s = 24'h000000;
        6'b000001: rgb_s = 24'h000000;
        6'b000010: rgb_s = 24'h070485;
        6'b000011: rgb_s = 24'h0A07BD;
        6'b000100: rgb_s = 24'h000000;
        6'b000101: rgb_s = 24'h000000;
        6'b000110: rgb_s = 24'h070485;
        6'b000111: rgb_s = 24'h0A07BD;
        6'b001000: rgb_s = 24'h209D21;
        6'b001001: rgb_s = 24'h209D21;
        6'b001010: rgb_s = 24'h26A4A4;
        6'b001011: rgb_s = 24'h29A7DC;
        6'b001100: rgb_s = 24'h2EDF2D;
        6'b001101: rgb_s = 24'h2EDF2D;
        6'b001110: rgb_s = 24'h33E6B0;
        6'b001111: rgb_s = 24'h36E8E9;
        6'b010000: rgb_s = 24'h000000;
        6'b010001: rgb_s = 24'h000000;
        6'b010010: rgb_s = 24'h070485;
        6'b010011: rgb_s = 24'h0A07BD;
        6'b010100: rgb_s = 24'h000000;
        6'b010101: rgb_s = 24'h000000;
        6'b010110: rgb_s = 24'h070485;
        6'b010111: rgb_s = 24'h0A07BD;
        6'b011000: rgb_s = 24'h209D21;
        6'b011001: rgb_s = 24'h209D21;
        6'b011010: rgb_s = 24'h26A4A4;
        6'b011011: rgb_s = 24'h29A7DC;
        6'b011100: rgb_s = 24'h2EDF2D;
        6'b011101: rgb_s = 24'h2EDF2D;
        6'b011110: rgb_s = 24'h33E6B0;
        6'b011111: rgb_s = 24'h36E8E9;
        6'b100000: rgb_s = 24'h8E1012;
        6'b100001: rgb_s = 24'h8E1012;
        6'b100010: rgb_s = 24'h951695;
        6'b100011: rgb_s = 24'h9819CC;
        6'b100100: rgb_s = 24'h8E1012;
        6'b100101: rgb_s = 24'h8E1012;
        6'b100110: rgb_s = 24'h951695;
        6'b100111: rgb_s = 24'h9819CC;
        6'b101000: rgb_s = 24'hAEAE31;
        6'b101001: rgb_s = 24'hAEAE31;
        6'b101010: rgb_s = 24'hB5B5B5;
        6'b101011: rgb_s = 24'hB8B6EB;
        6'b101100: rgb_s = 24'hBDEF3E;
        6'b101101: rgb_s = 24'hBDEF3E;
        6'b101110: rgb_s = 24'hC3F5C3;
        6'b101111: rgb_s = 24'hC5F9F7;
        6'b110000: rgb_s = 24'hCA1618;
        6'b110001: rgb_s = 24'hCA1618;
        6'b110010: rgb_s = 24'hD11D9B;
        6'b110011: rgb_s = 24'hD31FD2;
        6'b110100: rgb_s = 24'hCA1618;
        6'b110101: rgb_s = 24'hCA1618;
        6'b110110: rgb_s = 24'hD11D9B;
        6'b110111: rgb_s = 24'hD31FD2;
        6'b111000: rgb_s = 24'hE9B436;
        6'b111001: rgb_s = 24'hE9B436;
        6'b111010: rgb_s = 24'hF0BABD;
        6'b111011: rgb_s = 24'hF2BEF1;
        6'b111100: rgb_s = 24'hF6F644;
        6'b111101: rgb_s = 24'hF6F644;
        6'b111110: rgb_s = 24'hFDFCCB;
        6'b111111: rgb_s = 24'hFFFFFF;
        default: rgb_s = 24'h000000;
    endcase
end

always @(posedge clk) if (ce_pix) {video_r, video_g, video_b} <= v_surv ? rgb_s : rgb;

localparam DLY = 4;
reg [DLY-1:0] hbl_d = '0, vbl_d = '0, hs_d = '0, vs_d = '0;
always @(posedge clk) if (ce_pix) begin
    hbl_d <= {hbl_d[DLY-2:0], hbl};
    vbl_d <= {vbl_d[DLY-2:0], vbl};
    hs_d  <= {hs_d[DLY-2:0],  hsync};
    vs_d  <= {vs_d[DLY-2:0],  vsync};
end
assign video_hblank = hbl_d[DLY-1];
assign video_vblank = vbl_d[DLY-1];
assign video_hs     = hs_d[DLY-1];
assign video_vs     = vs_d[DLY-1];

wire signed [15:0] ds_out;
assign dsnd_0_i.src = {40'd0, 7'd0, z80pa85_0_o.sod, snd_b, snd_a};
assign ds_out = dsnd_0_o.out;

wire signed [15:0] mm_out;
assign tms36xx_0_i.cfg_b        = v_pleiads;
assign tms36xx_0_i.tune_we      = wr_stb & cs_sndb & !v_pleiads;
assign tms36xx_0_i.tune         = cpu_do[7:6];
assign tms36xx_0_i.note_we      = wr_stb & cs_sndb & v_pleiads & (cpu_do != snd_b);
assign tms36xx_0_i.note_octave  = (cpu_do[7:6] == 2'd3) ? 2'd2 : cpu_do[7:6];
assign tms36xx_0_i.note         = cpu_do[3:0];
assign tms36xx_0_i.enable_we    = 1'b0;
assign tms36xx_0_i.voice_enable = 6'd0;
assign mm_out = tms36xx_0_o.audio;

reg  signed [26:0] ay_dc = 27'sd0;
wire signed [11:0] ay_x  = $signed({2'b00, ay_snd}) - $signed(ay_dc[26:15]);
always @(posedge clk) if (reset) ay_dc <= 27'sd0; else if (div == 4'd15) ay_dc <= ay_dc + 27'(ay_x);
wire signed [16:0] ay_out = 17'(ay_x) <<< 6;

wire signed [16:0] mix = v_surv ? ay_out : 17'(ds_out) + (v_pleiads ? 17'(mm_out >>> 2) : 17'(mm_out >>> 1));
assign audio = (mix > 17'sd32767) ? 16'sh7FFF : (mix < -17'sd32768) ? 16'sh8000 : mix[15:0];

assign hs_data_out = 8'h00;

endmodule
