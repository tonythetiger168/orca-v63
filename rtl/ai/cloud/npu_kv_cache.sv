// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - KV-Cache 加速器 (Roc-E/Garuda): paged KV-cache 管理 + GQA/MQA 共享
`include "orca_pkg.sv"

module npu_kv_cache #(
  parameter int PAGE_BITS   = KV_PAGE_BITS,
  parameter int NUM_PAGES   = 2 ** PAGE_BITS,     // 512 頁
  parameter int BLOCK_SIZE  = 16,                 // tokens/page
  parameter int HEAD_DIM    = 128,
  parameter int NUM_KV_HEAD = 8                   // GQA: KV head 數
)(
  input  logic clk, rst_n,
  input  logic alloc_req,                         // 配置新序列
  input  logic [PAGE_BITS-1:0] alloc_num_pages,
  output logic [PAGE_BITS-1:0] alloc_base_page,
  output logic alloc_ok,
  input  logic free_req,
  input  logic [PAGE_BITS-1:0] free_base_page,
  // 區塊表 (per sequence)
  input  logic        bt_we,
  input  logic [15:0] bt_seq_id,
  input  logic [15:0] bt_slot,
  input  logic [PAGE_BITS-1:0] bt_page,
  input  logic        bt_valid,
  output logic [PAGE_BITS-1:0] bt_rd_page,
  output logic        bt_rd_valid,
  // DMA 讀寫 KV
  input  logic        kv_we,
  input  logic [PAGE_BITS-1:0] kv_page,
  input  logic [15:0] kv_offset,
  input  logic [HEAD_DIM*NUM_KV_HEAD-1:0] kv_wdata,
  output logic [HEAD_DIM*NUM_KV_HEAD-1:0] kv_rdata,
  input  logic        kv_rd,
  output logic        kv_hit,
  output logic [31:0] free_pages
);
  import orca_pkg::*;
  // 頁框 freelist (bitmap)
  logic [NUM_PAGES-1:0] page_used;
  logic [PAGE_BITS-1:0] free_ptr;
  // 區塊表 (seq, slot) -> page
  logic [PAGE_BITS-1:0] block_tab [65536][64];
  logic                 block_vld [65536][64];
  // KV data SRAM (page, offset) -> data
  logic [HEAD_DIM*NUM_KV_HEAD-1:0] kv_mem [NUM_PAGES][BLOCK_SIZE];
  logic [HEAD_DIM*NUM_KV_HEAD-1:0] kv_rd_q;

  // 已用頁計數 (alloc +n / free -1), 避開 $countones(512b) 的 Verilator 寬度內部錯誤
  logic [31:0] used_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) used_cnt <= 32'd0;
    else used_cnt <= used_cnt + (alloc_ok ? 32'(alloc_num_pages) : 32'd0)
                             - (free_req  ? 32'd1 : 32'd0);
  end
  assign free_pages = 32'(NUM_PAGES) - used_cnt;
  assign alloc_ok   = alloc_req && (free_pages >= 32'(alloc_num_pages));

  // alloc: 配發連續空閒頁 (first-fit from free_ptr)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      page_used <= '0; free_ptr <= '0; alloc_base_page <= '0;
    end else begin
      if (free_req) page_used[free_base_page] <= 1'b0;
      if (alloc_ok) begin
        alloc_base_page <= free_ptr;
        for (int p = 0; p < NUM_PAGES; p++)
          if (p >= free_ptr && p < free_ptr + alloc_num_pages)
            page_used[p] <= 1'b1;
        free_ptr <= PAGE_BITS'(32'(free_ptr) + 32'(alloc_num_pages));
      end
    end
  end

  // 區塊表
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < 65536; s++) for (int l = 0; l < 64; l++) block_vld[s][l] <= 1'b0;
    end else begin
      bt_rd_valid <= 1'b0;
      if (bt_we) begin
        block_tab[bt_seq_id][bt_slot] <= bt_page;
        block_vld[bt_seq_id][bt_slot] <= bt_valid;
      end
      if (kv_rd) begin
        bt_rd_page  <= block_tab[bt_seq_id][kv_offset[15:6]];
        bt_rd_valid <= block_vld[bt_seq_id][kv_offset[15:6]];
      end
    end
  end

  // KV data
  assign kv_hit = kv_rd && bt_rd_valid;
  assign kv_rdata = kv_rd_q;
  always_ff @(posedge clk) begin
    if (kv_we) kv_mem[kv_page][kv_offset[5:0]] <= kv_wdata;
    kv_rd_q <= kv_mem[kv_page][kv_offset[5:0]];
  end
endmodule : npu_kv_cache
