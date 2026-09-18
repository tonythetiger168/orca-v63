// soc_east_tb (v6.3.4 fix BUG-C): SoC 層 EAST 路由 directed 測試
// 證明 BUG-C 修復後 (flit_t 525b 線網 + adapter 直通) :
//   (i)   單跳 EAST: (0,0)->(1,0) flit 經 he[0][0] east 埠到達且內容完整
//   (ii)  多跳 EAST: (0,0)->(3,0) 經 he[0..2][0] 三跳到達
//   (iii) XY 轉彎:  (0,0)->(1,1) 先 E 後 N (he[0][0] + vn[1]) 到達 AI tile 1
//   (iv)  VC 掃描:  vc_id=0..3 全部正確轉發到同一目的
//   (v)   多 flit:  HEAD+TAIL 兩拍 packet, TAIL 帶完整標頭路由到同一目的且
//                   512b payload 不截斷 (HBM3/CHI 路徑)
// 注入: stub_tiles_east.sv cpu tile 0 內建序列 (每筆恰一拍);
//       本 TB 令 clk_sys==clk_noc (#5), adapter 直通下無 CDC, 時序完全確定。
`include "orca_pkg.sv"

module soc_east_tb;
  import orca_pkg::*;
  localparam int FW = $bits(flit_t);   // 525

  logic clk_sys = 0, clk_noc = 0;
  always #5 clk_sys = ~clk_sys;
  always #5 clk_noc = ~clk_noc;   // v6.3.4 fix BUG-C: 與 clk_sys 同頻同相
  logic rst_n;
  logic pcie_rx_p, pcie_rx_n, pcie_refclk_p, pcie_refclk_n;
  logic [7:0] bow_rx_data, bow_rx_clk;
  logic jtag_tck, jtag_tms, jtag_tdi, ext_irq_n;
  wire [3:0] ddr5_ck_t, ddr5_ck_c, ddr5_cs_n;
  wire [3:0] ddr5_dqs_t, ddr5_dqs_c;
  wire [63:0] ddr5_dq;
  wire [15:0] ddr5_addr;  wire [1:0] ddr5_ba;  wire ddr5_act_n;
  wire [11:0] hbm3_ck_t, hbm3_ck_c, hbm3_cs_n;
  wire [11:0] hbm3_dqs_t, hbm3_dqs_c;
  wire [1535:0] hbm3_dq;
  wire pcie_tx_p, pcie_tx_n;
  wire [7:0] bow_tx_data, bow_tx_clk;
  wire jtag_tdo, nmi_out;

  orca_v63_soc #(.NCO(1), .NCL_AI(1)) dut (
    .clk_sys(clk_sys), .clk_noc(clk_noc), .rst_n(rst_n),
    .ddr5_ck_t(ddr5_ck_t), .ddr5_ck_c(ddr5_ck_c), .ddr5_cs_n(ddr5_cs_n),
    .ddr5_dqs_t(ddr5_dqs_t), .ddr5_dqs_c(ddr5_dqs_c), .ddr5_dq(ddr5_dq),
    .ddr5_addr(ddr5_addr), .ddr5_ba(ddr5_ba), .ddr5_act_n(ddr5_act_n),
    .hbm3_ck_t(hbm3_ck_t), .hbm3_ck_c(hbm3_ck_c), .hbm3_cs_n(hbm3_cs_n),
    .hbm3_dqs_t(hbm3_dqs_t), .hbm3_dqs_c(hbm3_dqs_c), .hbm3_dq(hbm3_dq),
    .pcie_tx_p(pcie_tx_p), .pcie_tx_n(pcie_tx_n),
    .pcie_rx_p(pcie_rx_p), .pcie_rx_n(pcie_rx_n),
    .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
    .bow_tx_data(bow_tx_data), .bow_tx_clk(bow_tx_clk),
    .bow_rx_data(bow_rx_data), .bow_rx_clk(bow_rx_clk),
    .jtag_tck(jtag_tck), .jtag_tms(jtag_tms), .jtag_tdi(jtag_tdi),
    .jtag_tdo(jtag_tdo), .ext_irq_n(ext_irq_n), .nmi_out(nmi_out));

  int errors = 0;

  // ---------------- 到達擷取與鏈路證據 (clk_noc negedge 採樣) ----------------
  logic [FW-1:0] rxq [4][2][$];       // 每目的 tile 收到的 flit 序列
  int saw_he [3][2]; int saw_hw [3][2];
  int saw_vn [4];    int saw_vs [4];
  logic [FW-1:0] he_cap [3][2];       // he_v 拉起當拍的 he_d (EAST 證據)
  logic [FW-1:0] vn_cap [4];

  always @(negedge clk_noc) begin
    for (int x = 0; x < 4; x++) begin
      if (dut.ct_iv[x] === 1'b1) rxq[x][0].push_back(FW'(dut.ct_in[x]));
      if (dut.at_iv[x] === 1'b1) rxq[x][1].push_back(FW'(dut.at_in[x]));
      if (dut.vn_v[x] === 1'b1) begin saw_vn[x]++; vn_cap[x] = dut.vn_d[x]; end
      if (dut.vs_v[x] === 1'b1) saw_vs[x]++;
    end
    for (int x = 0; x < 3; x++) begin
      for (int y = 0; y < 2; y++) begin
        if (dut.he_v[x][y] === 1'b1) begin saw_he[x][y]++; he_cap[x][y] = dut.he_d[x][y]; end
        if (dut.hw_v[x][y] === 1'b1) saw_hw[x][y]++;
      end
    end
  end

  task automatic wait_q(input int x, input int y, input int n);
    int to;
    to = 0;
    while (rxq[x][y].size() < n && to < 300) begin
      @(negedge clk_noc); to++;
    end
    if (rxq[x][y].size() < n) begin
      errors++;
      $display("TB FAIL: timeout waiting %0d flit(s) at tile (%0d,%0d), got %0d",
               n, x, y, rxq[x][y].size());
    end
  endtask

  function automatic flit_t mkflit(input logic [1:0] dx, dy,
                                   input logic [1:0] vc,
                                   input flit_type_t ft,
                                   input logic [511:0] pl);
    flit_t f;
    f         = '0;
    f.valid   = 1'b1;
    f.ftype   = ft;
    f.dest_x  = dx;
    f.dest_y  = dy;
    f.src_x   = 2'd0;
    f.src_y   = 2'd0;
    f.vc_id   = vc;
    f.payload = pl;
    return f;
  endfunction

  // 逐位比對到達 flit 與預期 flit (含 dest/vc/ftype/payload 完整標頭)
  task automatic check_flit(input logic [FW-1:0] got, input flit_t exp, input string tag);
    flit_t g;
    g = flit_t'(got);
    if (got !== FW'(exp)) begin
      errors++;
      $display("TB FAIL: %s flit mismatch", tag);
      $display("  exp: dest=(%0d,%0d) vc=%0d ftype=%0d payload=%h",
               exp.dest_x, exp.dest_y, exp.vc_id, exp.ftype, exp.payload);
      $display("  got: dest=(%0d,%0d) vc=%0d ftype=%0d payload=%h",
               g.dest_x, g.dest_y, g.vc_id, g.ftype, g.payload);
    end else begin
      $display("TB OK: %s 到達 flit 逐位完整 dest=(%0d,%0d) vc=%0d ftype=%0d payload=%h",
               tag, g.dest_x, g.dest_y, g.vc_id, g.ftype, g.payload);
    end
  endtask

  initial begin
    for (int x = 0; x < 3; x++) for (int y = 0; y < 2; y++) begin
      saw_he[x][y] = 0; saw_hw[x][y] = 0;
    end
    for (int x = 0; x < 4; x++) begin saw_vn[x] = 0; saw_vs[x] = 0; end
    rst_n = 0;
    pcie_rx_p = 0; pcie_rx_n = 1; pcie_refclk_p = 0; pcie_refclk_n = 1;
    bow_rx_data = '0; bow_rx_clk = '0;
    jtag_tck = 0; jtag_tms = 1; jtag_tdi = 0; ext_irq_n = 1;
    repeat (8) @(posedge clk_sys);
    rst_n = 1;

    // ================= (i) 單跳 EAST: (0,0)->(1,0) =================
    wait_q(1, 0, 1);
    if (rxq[1][0].size() >= 1)
      check_flit(rxq[1][0][0], mkflit(2'd1, 2'd0, 2'd0, FLIT_SINGLE, 512'hE457_0001_D15EA5E0), "EAST-1HOP");
    if (saw_he[0][0] < 1) begin
      errors++;
      $display("TB FAIL: EAST-1HOP he_v[0][0] 未拉起 (EAST 仍不可達)");
    end else begin
      flit_t ef;
      ef = flit_t'(he_cap[0][0]);
      $display("EVIDENCE EAST-1HOP: he_v[0][0] pulse=%0d, he_d[0][0] dest=(%0d,%0d) payload[63:0]=%h",
               saw_he[0][0], ef.dest_x, ef.dest_y, ef.payload[63:0]);
    end

    // ================= (ii) 多跳 EAST: (0,0)->(3,0) =================
    wait_q(3, 0, 1);
    if (rxq[3][0].size() >= 1)
      check_flit(rxq[3][0][0], mkflit(2'd3, 2'd0, 2'd1, FLIT_SINGLE, 512'hE457_3009_F00D), "EAST-3HOP");
    if (saw_he[0][0] < 2 || saw_he[1][0] < 1 || saw_he[2][0] < 1) begin
      errors++;
      $display("TB FAIL: EAST-3HOP 中間跳未全部拉起 he_v[0..2][0]=%0d,%0d,%0d",
               saw_he[0][0], saw_he[1][0], saw_he[2][0]);
    end else begin
      $display("EVIDENCE EAST-3HOP: he_v[0][0]=%0d he_v[1][0]=%0d he_v[2][0]=%0d (三跳皆經 east 埠)",
               saw_he[0][0], saw_he[1][0], saw_he[2][0]);
    end

    // ================= (iii) XY 轉彎: (0,0)->(1,1) =================
    wait_q(1, 1, 1);
    if (rxq[1][1].size() >= 1)
      check_flit(rxq[1][1][0], mkflit(2'd1, 2'd1, 2'd2, FLIT_SINGLE, 512'h7021_E211_ABCD), "XY-TURN");
    if (saw_vn[1] < 1) begin
      errors++;
      $display("TB FAIL: XY-TURN 缺北向跳 vn_v[1]=%0d", saw_vn[1]);
    end else begin
      flit_t vf;
      vf = flit_t'(vn_cap[1]);
      $display("EVIDENCE XY-TURN: he_v[0][0]=%0d 後 vn_v[1]=%0d, vn_d[1] dest=(%0d,%0d) (先 E 後 N)",
               saw_he[0][0], saw_vn[1], vf.dest_x, vf.dest_y);
    end

    // ================= (iv) VC 掃描 0..3: (0,0)->(1,0) =================
    begin
      logic [3:0] vc_seen;
      vc_seen = '0;
      wait_q(1, 0, 5);
      if (rxq[1][0].size() >= 5) begin
        for (int v = 0; v < 4; v++) begin
          flit_t g;
          g = flit_t'(rxq[1][0][1 + v]);
          vc_seen[g.vc_id] = 1'b1;
          if (g.payload[63:0] !== (64'hC0DE_4C00 + 64'(g.vc_id))) begin
            errors++;
            $display("TB FAIL: VC-SCAN vc=%0d payload=%h", g.vc_id, g.payload);
          end
        end
        if (vc_seen !== 4'b1111) begin
          errors++;
          $display("TB FAIL: VC-SCAN 未收齊 vc 0..3, seen=%b", vc_seen);
        end else begin
          $display("EVIDENCE VC-SCAN: vc_id 0..3 全部轉發到 (1,0), seen=%b", vc_seen);
        end
      end
    end

    // ================= (v) 多 flit packet: HEAD+TAIL -> (1,1) =================
    begin
      wait_q(1, 1, 3);
      if (rxq[1][1].size() >= 3) begin
        flit_t gh, gt;
        gh = flit_t'(rxq[1][1][1]);
        gt = flit_t'(rxq[1][1][2]);
        if (gh.ftype !== FLIT_HEAD ||
            FW'(gh) !== FW'(mkflit(2'd1, 2'd1, 2'd0, FLIT_HEAD, {64'hA55A_0000_1111_0000, 448'h0}))) begin
          errors++;
          $display("TB FAIL: MULTI-FLIT HEAD 損毀 ftype=%0d", gh.ftype);
        end
        if (gt.ftype !== FLIT_TAIL ||
            FW'(gt) !== FW'(mkflit(2'd1, 2'd1, 2'd0, FLIT_TAIL, {16{32'hCAFE_F00D}}))) begin
          errors++;
          $display("TB FAIL: MULTI-FLIT TAIL 損毀/未跟隨路由 ftype=%0d dest=(%0d,%0d)",
                   gt.ftype, gt.dest_x, gt.dest_y);
        end
        if (gt.payload !== {16{32'hCAFE_F00D}}) begin
          errors++;
          $display("TB FAIL: MULTI-FLIT TAIL 512b payload 截斷: %h", gt.payload);
        end
        if (errors == 0) begin
          $display("EVIDENCE MULTI-FLIT: HEAD ftype=%0d 與 TAIL ftype=%0d 依序到達 (1,1), TAIL dest=(%0d,%0d) payload[63:0]=%h (512b 完整)",
                   gh.ftype, gt.ftype, gt.dest_x, gt.dest_y, gt.payload[63:0]);
        end
      end
    end
    repeat (6) @(negedge clk_noc);

    if (errors != 0) $fatal(1, "TB FAIL: soc_east %0d errors", errors);
    $display("TB PASS: soc_east EAST 單跳/多跳/XY轉彎/VC掃描/多flit 全部到達且內容完整");
    $finish;
  end
endmodule : soc_east_tb
