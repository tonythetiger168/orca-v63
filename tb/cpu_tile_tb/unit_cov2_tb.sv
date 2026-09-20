// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - unit coverage round 2
// exu_alu / rnu_rat / cmt_archreg / lsu_mshr / lsu_dcache / orca_noc_link / npu_tile_noc
`include "orca_pkg.sv"

module unit_cov2_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  // ============ exu_alu ============
  uop_t alu_uop; logic alu_v, alu_rdy, alu_rv, alu_bt, alu_bm; xword_t alu_r, alu_brg; rob_idx_t alu_ri;
  exu_alu u_alu (.clk(clk), .rst_n(rst_n), .uop(alu_uop), .uop_valid(alu_v), .uop_ready(alu_rdy),
    .operand_a(64'h0000_0000_0000_00F0), .operand_b(64'h0000_0000_0000_000F),
    .operand_c(64'hFFFF_0000_0000_0000),
    .result(alu_r), .result_valid(alu_rv), .rob_idx(alu_ri),
    .branch_taken(alu_bt), .branch_target(alu_brg), .branch_mispredict(alu_bm));

  // ============ rnu_rat ============
  tid_t [DISPATCH_WIDTH-1:0] rt_tid_i;
  arch_reg_idx_t [DISPATCH_WIDTH-1:0] rt_rs1a, rt_rs2a, rt_rda;
  logic [DISPATCH_WIDTH-1:0] rt_rdwe, rt_isfp;
  phys_reg_idx_t [DISPATCH_WIDTH-1:0] rt_prdi, rt_prs1o, rt_prs2o, rt_poldo;
  logic [1:0] rt_ckid; phys_reg_idx_t rt_fmap [32];
  logic rt_ckpush, rt_ckrestore, rt_flusht; tid_t rt_cktid, rt_rtid, rt_ftid; logic [1:0] rt_rid;
  rnu_rat u_rat (.clk(clk), .rst_n(rst_n), .tid_i(rt_tid_i), .rs1a(rt_rs1a), .rs2a(rt_rs2a),
    .rda(rt_rda), .rd_we(rt_rdwe), .prd_i(rt_prdi), .is_fp(rt_isfp),
    .prs1_o(rt_prs1o), .prs2_o(rt_prs2o), .prd_old_o(rt_poldo),
    .ckpt_push(rt_ckpush), .ckpt_tid(rt_cktid), .ckpt_id(rt_ckid),
    .ckpt_restore(rt_ckrestore), .restore_tid(rt_rtid), .restore_id(rt_rid),
    .flush_thread(rt_flusht), .flush_tid(rt_ftid), .flush_map(rt_fmap));

  // ============ cmt_archreg ============
  tid_t [RETIRE_WIDTH-1:0] ag_tid; arch_reg_idx_t [RETIRE_WIDTH-1:0] ag_rda;
  phys_reg_idx_t [RETIRE_WIDTH-1:0] ag_prd; xword_t [RETIRE_WIDTH-1:0] ag_data;
  logic [RETIRE_WIDTH-1:0] ag_v, ag_fp; phys_reg_idx_t ag_map [SMT_THREADS][32];
  xword_t ag_dbg; tid_t ag_dtid; arch_reg_idx_t ag_drda; logic ag_dfp;
  cmt_archreg u_ag (.clk(clk), .rst_n(rst_n), .rt_tid(ag_tid), .rt_rda(ag_rda), .rt_prd(ag_prd),
    .rt_data(ag_data), .rt_valid(ag_v), .rt_fp(ag_fp), .cur_map(ag_map),
    .dbg_tid(ag_dtid), .dbg_rda(ag_drda), .dbg_fp(ag_dfp), .dbg_rdata(ag_dbg));

  // ============ lsu_mshr ============
  paddr_t ms_ra, ms_fa; logic ms_rv, ms_is, ms_acc, ms_fv, ms_re, ms_full, ms_wb;
  mshr_idx_t ms_idx, ms_ridx; logic [MSHR_ENTRIES-1:0] ms_cmp; paddr_t ms_cmpa [MSHR_ENTRIES]; paddr_t ms_wba;
  lsu_mshr u_mshr (.clk(clk), .rst_n(rst_n), .req_addr(ms_ra), .req_valid(ms_rv), .req_is_store(ms_is),
    .req_accept(ms_acc), .req_idx(ms_idx), .miss_full(ms_full),
    .fill_valid(ms_fv), .fill_addr(ms_fa), .complete(ms_cmp), .complete_addr(ms_cmpa),
    .retire_entry(ms_re), .retire_idx(ms_ridx), .wb_req(ms_wb), .wb_addr(ms_wba));

  // ============ lsu_dcache ============
  paddr_t dc_ra; logic dc_rv, dc_we, dc_rdy, dc_hit, dc_mack, dc_fv, dc_wbv, dc_sbe;
  xword_t dc_wd, dc_rd; logic [7:0] dc_wm; paddr_t dc_ma, dc_wba; logic [511:0] dc_fl, dc_wbl;
  lsu_dcache u_dcache (.clk(clk), .rst_n(rst_n), .req_addr(dc_ra), .req_valid(dc_rv), .req_we(dc_we),
    .req_wdata(dc_wd), .req_wmask(dc_wm), .req_ready(dc_rdy), .req_rdata(dc_rd), .req_hit(dc_hit),
    .miss_addr(dc_ma), .miss_valid(), .miss_ack(dc_mack), .fill_line(dc_fl), .fill_valid(dc_fv),
    .wb_valid(dc_wbv), .wb_addr(dc_wba), .wb_line(dc_wbl), .stbuf_empty(dc_sbe));

  // ============ orca_noc_link ============
  flit_t nl_tx, nl_rx; logic nl_tv, nl_tr, nl_rv, nl_rr, nl_lu;
  logic [15:0] nl_ptx, nl_prx; logic nl_ptv, nl_prv; logic [NOC_VC-1:0] nl_cr;
  orca_noc_link u_link (.clk(clk), .rst_n(rst_n), .tx_flit(nl_tx), .tx_valid(nl_tv), .tx_ready(nl_tr),
    .rx_flit(nl_rx), .rx_valid(nl_rv), .rx_ready(nl_rr),
    .phy_tx(nl_ptx), .phy_tx_v(nl_ptv), .phy_rx(nl_prx), .phy_rx_v(nl_prv),
    .link_up(nl_lu), .rx_credit(nl_cr));
  assign nl_prx = nl_ptx; assign nl_prv = nl_ptv;

  // ============ npu_tile_noc ============
  paddr_t tn_da; logic tn_dv, tn_dwr, tn_dr, tn_or, tn_iv, tn_ir; logic [511:0] tn_dwd, tn_drd;
  flit_t tn_no, tn_ni; logic [NOC_VC-1:0] tn_cr;
  npu_tile_noc u_tn (.clk(clk), .rst_n(rst_n), .dma_addr(tn_da), .dma_valid(tn_dv),
    .dma_is_write(tn_dwr), .dma_wdata(tn_dwd), .dma_ready(tn_dr), .dma_rdata(tn_drd),
    .noc_out(tn_no), .noc_out_ready(tn_or), .noc_in(tn_ni), .noc_in_valid(tn_iv),
    .noc_in_ready(tn_ir), .vc_credit(tn_cr));

  int i;
  initial begin
    alu_uop='0; alu_v=0; rt_tid_i='0; rt_rs1a='0; rt_rs2a='0; rt_rda='0; rt_rdwe='0;
    rt_isfp='0; rt_prdi='0; rt_ckpush=0; rt_ckrestore=0; rt_flusht=0; rt_cktid='0;
    rt_rtid='0; rt_ftid='0; rt_rid='0; for(i=0;i<32;i++) rt_fmap[i]=phys_reg_idx_t'(i);
    ag_tid='0; ag_rda='0; ag_prd='0; ag_data='0; ag_v='0; ag_fp='0; ag_dtid='0; ag_drda='0; ag_dfp=0;
    ms_ra='0; ms_rv=0; ms_is=0; ms_fv=0; ms_fa='0; ms_re=0; ms_ridx='0;
    dc_ra='0; dc_rv=0; dc_we=0; dc_wd='0; dc_wm='0; dc_mack=0; dc_fv=0; dc_fl='0;
    nl_tx='0; nl_tv=0; nl_rr=1; nl_cr={NOC_VC{1'b1}};
    tn_da='0; tn_dv=0; tn_dwr=0; tn_dwd='0; tn_or=1; tn_ni='0; tn_iv=0; tn_cr={NOC_VC{1'b1}};
    rst_n=0; #57 rst_n=1; @(negedge clk);

    // OP_ALU: funct3=0..7 x imm[30] (ADD/SUB,SLL,SLT,SLTU,XOR,SRL/SRA,OR,AND)
    for (int f3=0; f3<8; f3++) begin
      for (int i30=0; i30<2; i30++) begin
        alu_uop='0; alu_uop.opcode=OP_ALU; alu_uop.imm[14:12]=3'(f3); alu_uop.imm[30]=i30;
        alu_uop.rob_idx=rob_idx_t'(f3);
        alu_v=1; @(negedge clk);
        begin int g=0; while(!alu_rdy&&g<20) begin @(negedge clk); g++; end end
        alu_v=0; repeat(2) @(negedge clk);
      end
    end
    // OP_ALUI: funct3=0..7 x imm[30]
    for (int f3=0; f3<8; f3++) begin
      for (int i30=0; i30<2; i30++) begin
        alu_uop='0; alu_uop.opcode=OP_ALUI; alu_uop.imm[14:12]=3'(f3); alu_uop.imm[30]=i30;
        alu_uop.rob_idx=rob_idx_t'(f3);
        alu_v=1; @(negedge clk);
        begin int g=0; while(!alu_rdy&&g<20) begin @(negedge clk); g++; end end
        alu_v=0; repeat(2) @(negedge clk);
      end
    end
    // LUI / AUIPC
    alu_uop='0; alu_uop.opcode=OP_LUI; alu_uop.imm=64'hABCDE000; alu_v=1; @(negedge clk);
    begin int g=0; while(!alu_rdy&&g<20) begin @(negedge clk); g++; end end alu_v=0; repeat(2) @(negedge clk);
    alu_uop='0; alu_uop.opcode=OP_AUIPC; alu_uop.imm=64'h12345000; alu_uop.pc=64'h1000; alu_v=1; @(negedge clk);
    begin int g=0; while(!alu_rdy&&g<20) begin @(negedge clk); g++; end end alu_v=0; repeat(2) @(negedge clk);
    // branch path: is_branch + 條件分支 funct3 (BEQ/BNE/BLT/BGE/BLTU/BGEU)
    for (int f3=0; f3<8; f3++) begin
      alu_uop='0; alu_uop.is_branch=1; alu_uop.imm[14:12]=3'(f3);
      alu_uop.pred_taken=(f3%2==0); alu_uop.pc=64'h2000; alu_uop.rob_idx=rob_idx_t'(f3);
      alu_v=1; @(negedge clk);
      begin int g=0; while(!alu_rdy&&g<20) begin @(negedge clk); g++; end end
      alu_v=0; repeat(2) @(negedge clk);
    end
    // AMO
    alu_uop='0; alu_uop.opcode=OP_AMO; alu_uop.imm[14:12]=3'd2; alu_uop.rob_idx=8;
    alu_v=1; @(negedge clk);
    begin int g=0; while(!alu_rdy&&g<20) begin @(negedge clk); g++; end end alu_v=0; repeat(2) @(negedge clk);

    for (int round=0; round<4; round++) begin
      for (int s=0; s<DISPATCH_WIDTH; s++) begin
        rt_tid_i[s]=tid_t'(s%4); rt_rs1a[s]=arch_reg_idx_t'(s%32); rt_rs2a[s]=arch_reg_idx_t'((s+1)%32);
        rt_rda[s]=arch_reg_idx_t'((s+round)%32); rt_rdwe[s]=(s%2==0); rt_isfp[s]=(s%3==0);
        rt_prdi[s]=phys_reg_idx_t'(32+s+round);
      end
      @(negedge clk);
    end
    for (int t=0; t<4; t++) begin rt_ckpush=1; rt_cktid=tid_t'(t); @(negedge clk); end
    rt_ckpush=0;
    for (int t=0; t<4; t++) begin rt_ckrestore=1; rt_rtid=tid_t'(t); rt_rid=2'(t%4); @(negedge clk); end
    rt_ckrestore=0;
    for (int t=0; t<4; t++) begin rt_flusht=1; rt_ftid=tid_t'(t); @(negedge clk); end
    rt_flusht=0; repeat(4) @(negedge clk);

    for (int round=0; round<3; round++) begin
      for (int s=0; s<RETIRE_WIDTH; s++) begin
        ag_tid[s]=tid_t'(s%4); ag_rda[s]=arch_reg_idx_t'((s+round)%32);
        ag_prd[s]=phys_reg_idx_t'(32+s); ag_data[s]=64'h1000+s+round;
        ag_v[s]=(s%2==0); ag_fp[s]=(s%3==0);
      end
      @(negedge clk);
    end
    ag_v='0;
    for (int t=0; t<4; t++) for (int r=0; r<32; r+=7) begin
      ag_dtid=tid_t'(t); ag_drda=arch_reg_idx_t'(r); ag_dfp=(r%2==0); #1; @(negedge clk);
    end

    for (int k=0; k<MSHR_ENTRIES+4; k++) begin
      ms_ra=64'h1000_0000 + (k*64); ms_rv=1; ms_is=(k%2==0); @(negedge clk);
      ms_rv=1; @(negedge clk); ms_rv=0;
    end
    for (int k=0; k<MSHR_ENTRIES; k++) begin
      ms_fa=64'h1000_0000 + (k*64); ms_fv=1; @(negedge clk); ms_fv=0;
    end
    for (int k=0; k<MSHR_ENTRIES; k++) begin
      if (ms_cmp[k]) begin ms_re=1; ms_ridx=mshr_idx_t'(k); @(negedge clk); end
    end
    ms_re=0; repeat(4) @(negedge clk);

    dc_ra=64'h2000_0000; dc_rv=1; dc_we=0; @(negedge clk); dc_rv=0;
    dc_mack=1; dc_fl={8{64'hABCD_1234_5678_EF00}}; dc_fv=1; @(negedge clk); dc_fv=0; dc_mack=0;
    repeat(2) @(negedge clk);
    dc_ra=64'h2000_0000; dc_rv=1; dc_we=0; @(negedge clk); dc_rv=0;
    dc_ra=64'h2000_0000; dc_rv=1; dc_we=1; dc_wd=64'hDEAD_BEEF_CAFE_0000; dc_wm=8'hF0; @(negedge clk); dc_rv=0;
    repeat(4) @(negedge clk);

    for (int c=0; c<4; c++) begin
      nl_tx='0; nl_tx.valid=1; nl_tx.ftype=FLIT_SINGLE; nl_tx.payload=512'hAAAA_0000+c; nl_tx.dest_x=2'(c); nl_tx.dest_y=2'd1;
      nl_tv=1; nl_cr={NOC_VC{c%2==1}}; @(negedge clk); nl_tv=0; nl_cr={NOC_VC{1'b1}};
      repeat(3) @(negedge clk);
    end
    repeat(6) @(negedge clk);

    tn_da=64'h9000_0000; tn_dv=1; tn_dwr=1; tn_dwd={8{64'h1234_5678_9ABC_DEF0}}; @(negedge clk); tn_dv=0;
    repeat(6) @(negedge clk);
    tn_da=64'h9000_1000; tn_dv=1; tn_dwr=0; @(negedge clk); tn_dv=0;
    repeat(3) @(negedge clk);
    tn_ni='0; tn_ni.valid=1; tn_ni.payload={8{64'hFEED_FACE_0000_1111}}; tn_iv=1; @(negedge clk); tn_iv=0;
    repeat(6) @(negedge clk);

    $display("UNIT COV2 TB PASS");
    $finish;
  end
endmodule : unit_cov2_tb
