//=============================================================================
// ORCA v6.3 ZEN++ Global Package
// File: rtl/common/orca_pkg.sv
// Description: Global parameters, types, and enums shared across all ORCA v6.3
//              RTL modules (CPU tile / AI tile / NoC / SoC).
//
// Note: This file is `include'd by every module (with include guard) and also
//       compiled first in the file list. All parameters come from the
//       architecture spec v1.0 section 6.2.
//=============================================================================

`ifndef ORCA_PKG_SV
`define ORCA_PKG_SV

package orca_pkg;

  // ---------------------------------------------------------------------------
  // ISA Parameters
  // ---------------------------------------------------------------------------
  parameter int XLEN = 64;                 // RV64
  parameter int VLEN = 512;                // 512-bit RVV
  parameter int PLEN = 64;                 // Physical address width (Sv48 + ext)

  // ---------------------------------------------------------------------------
  // SoC-Level Parameters
  // ---------------------------------------------------------------------------
  parameter int NUM_CPU_TILES     = 4;     // 4 CPU tiles
  parameter int NUM_AI_TILES      = 4;     // 4 AI tiles
  parameter int CORES_PER_CPU_TILE= 8;     // 8 cores per CPU tile
  parameter int SMT_THREADS       = 4;     // 4-way SMT
  parameter int NUM_CORES_TOTAL   = NUM_CPU_TILES * CORES_PER_CPU_TILE;   // 32
  parameter int NUM_THREADS_TOTAL = NUM_CORES_TOTAL * SMT_THREADS;        // 128

  // ---------------------------------------------------------------------------
  // CPU Core Microarchitecture Parameters (ZEN++)
  // ---------------------------------------------------------------------------
  parameter int FETCH_WIDTH       = 8;     // 8 inst per fetch block
  parameter int DECODE_WIDTH      = 6;     // 6-wide decoder
  parameter int DISPATCH_WIDTH    = 12;    // 12-wide dispatch
  parameter int RETIRE_WIDTH      = 16;    // 16-wide retire
  parameter int ROB_ENTRIES       = 1024;  // 1K-entry ROB (256 per thread)
  parameter int INT_PRF_ENTRIES   = 384;   // Integer physical register file
  parameter int FP_PRF_ENTRIES    = 256;   // FP physical register file
  parameter int VEC_PRF_ENTRIES   = 512;   // Vector physical register file (512-bit)
  parameter int INT_SCHED_DEPTH   = 64;    // Integer scheduler entries
  parameter int FP_SCHED_DEPTH    = 48;    // FP scheduler entries
  parameter int MEM_SCHED_DEPTH   = 32;    // Memory scheduler entries
  parameter int NUM_INT_ALU       = 4;     // 4x INT ALU
  parameter int NUM_FP_FMA        = 2;     // 2x FP FMA
  parameter int NUM_VEC_ALU       = 2;     // 2x Vector ALU
  parameter int NUM_LD_PIPE       = 4;     // 4x load pipe
  parameter int NUM_ST_PIPE       = 4;     // 4x store pipe
  parameter int L1I_SIZE_KB       = 64;    // L1 I-Cache
  parameter int L1D_SIZE_KB       = 64;    // L1 D-Cache
  parameter int L2_SIZE_KB        = 1024;  // L2 (1 MB per tile)
  parameter int L3_SIZE_MB        = 64;    // L3 shared (per CPU tile)
  parameter int L1I_WAYS          = 8;
  parameter int L1D_WAYS          = 8;
  parameter int L2_WAYS           = 16;
  parameter int L3_WAYS           = 16;
  parameter int BTB_ENTRIES       = 8192;  // L1 BTB (L0 uBTB lives inside ifu_bpu)
  parameter int RAS_DEPTH         = 64;    // Return address stack (per thread)
  parameter int ITLB_ENTRIES      = 96;
  parameter int DTLB_ENTRIES      = 128;
  parameter int MSHR_ENTRIES      = 32;    // Load/store MSHRs
  parameter int SQ_ENTRIES        = 96;    // Store queue
  parameter int LQ_ENTRIES        = 128;   // Load queue

  // ---------------------------------------------------------------------------
  // AI Tile Parameters (ORCA-NPU v3)
  // ---------------------------------------------------------------------------
  parameter int AI_TILES          = 4;     // 4 AI tiles
  parameter int CLUSTERS_PER_TILE = 16;    // 16 clusters per tile
  parameter int CUS_PER_CLUSTER   = 4;     // 4 compute units per cluster
  parameter int PE_ARRAY_DIM      = 64;    // 64x64 systolic array
  parameter int AI_L2_SIZE_MB     = 64;    // 64 MB L2 SRAM per AI tile
  parameter int HBM3_STACKS       = 3;     // 3 HBM3 stacks per AI tile
  parameter int HBM3_CHANNELS     = 16;    // 16 channels per stack
  parameter int AI_DTYPE_INT8     = 3'd0;  // Data type encodings (npu_pe)
  parameter int AI_DTYPE_INT4     = 3'd1;
  parameter int AI_DTYPE_BF16     = 3'd2;
  parameter int AI_DTYPE_FP16     = 3'd3;
  parameter int AI_DTYPE_FP32     = 3'd4;
  parameter int AI_DTYPE_FP8      = 3'd5;

  // ---------------------------------------------------------------------------
  // NoC Parameters
  // ---------------------------------------------------------------------------
  parameter int NOC_DATA_WIDTH    = 512;   // 512-bit flit payload
  parameter int NOC_VC            = 4;     // 4 virtual channels
  parameter int NOC_MESH_X        = 4;     // Mesh dimensions (8 tiles + IO)
  parameter int NOC_MESH_Y        = 4;
  parameter int NOC_X_BITS        = 2;     // $clog2(NOC_MESH_X)
  parameter int NOC_Y_BITS        = 2;     // $clog2(NOC_MESH_Y)

  // ---------------------------------------------------------------------------
  // AIX (AI eXtension) Parameters
  // ---------------------------------------------------------------------------
  parameter int AIX_HANDLE_BITS   = 16;    // 16-bit tensor handle
  parameter int AIX_TILEID_BITS   = 3;     // 3-bit tile ID (0-7)
  parameter int AIX_TDB_SIZE      = 512;   // 512-bit tensor descriptor (64 B)
  parameter int AIX_NUM_TDB       = 256;   // Tensor descriptor buffer entries

  // ---------------------------------------------------------------------------
  // Clock Frequencies (for documentation / CDC constraints)
  // ---------------------------------------------------------------------------
  parameter real CLK_SYS_MHZ      = 3200.0;  // 3.2 GHz core clock
  parameter real CLK_NOC_MHZ      = 1600.0;  // 1.6 GHz NoC clock
  parameter real CLK_AI_MHZ       = 1000.0;  // 1.0 GHz AI tile clock

  // ---------------------------------------------------------------------------
  // Base Types
  // ---------------------------------------------------------------------------
  typedef logic [XLEN-1:0]        xword_t;   // 64-bit integer word
  typedef logic [VLEN-1:0]        vword_t;   // 512-bit vector word
  typedef logic [PLEN-1:0]        paddr_t;   // Physical address
  typedef logic [4:0]             arch_reg_idx_t;  // Architectural register (x0-x31 / f0-f31)
  typedef logic [8:0]             phys_reg_idx_t;  // Physical register (512 max)
  typedef logic [$clog2(ROB_ENTRIES)-1:0] rob_idx_t;   // 10-bit ROB index
  typedef logic [15:0]            uop_id_t;    // Unique uop tag (debug/trace)
  typedef logic [$clog2(SMT_THREADS)-1:0] tid_t;       // SMT thread ID (2-bit)
  typedef logic [$clog2(MSHR_ENTRIES)-1:0] mshr_idx_t; // MSHR index
  typedef logic [$clog2(SQ_ENTRIES)-1:0]   sq_idx_t;   // Store queue index
  typedef logic [$clog2(LQ_ENTRIES)-1:0]   lq_idx_t;   // Load queue index

  // Exception record (carried with uop through the pipeline)
  typedef struct packed {
    logic        valid;    // Exception / trap pending
    logic [3:0]  code;     // mcause-style code
    logic [63:0] tval;     // Trap value (bad address / bad instruction)
  } exception_t;

`define EXC_NONE '0   // exception_t is packed; all-zero = no exception

  // ---------------------------------------------------------------------------
  // Opcode Type (internal uop opcode, decoded from RISC-V major opcode)
  // ---------------------------------------------------------------------------
  typedef enum logic [5:0] {
    OP_NOP     = 6'd0,    // Bubble / invalidated uop
    OP_ALU     = 6'd1,    // Integer register-register (R-type)
    OP_ALUI    = 6'd2,    // Integer register-immediate (I-type)
    OP_LUI     = 6'd3,    // LUI
    OP_AUIPC   = 6'd4,    // AUIPC
    OP_BRANCH  = 6'd5,    // Conditional branch (BEQ/BNE/BLT/BGE/BLTU/BGEU)
    OP_JAL     = 6'd6,    // JAL
    OP_JALR    = 6'd7,    // JALR
    OP_LOAD    = 6'd8,    // Integer load
    OP_STORE   = 6'd9,    // Integer store
    OP_AMO     = 6'd10,   // Atomic memory operation (A extension)
    OP_FENCE   = 6'd11,   // FENCE / FENCE.I
    OP_SYSTEM  = 6'd12,   // ECALL/EBREAK/CSR*
    OP_MUL     = 6'd13,   // M extension: MUL/MULH/MULHSU/MULW
    OP_DIV     = 6'd14,   // M extension: DIV/DIVU/REM/REMU
    OP_FP      = 6'd15,   // FP register-register (F/D extension)
    OP_FPM     = 6'd16,   // FP fused multiply-add
    OP_FPLD    = 6'd17,   // FP load
    OP_FPST    = 6'd18,   // FP store
    OP_VEC     = 6'd19,   // RVV vector operation
    OP_VEC_CFG = 6'd20,   // RVV vsetvli/vsetivl/vsetvl
    OP_VEC_LD  = 6'd21,   // Vector load
    OP_VEC_ST  = 6'd22,   // Vector store
    OP_CRYPTO  = 6'd23,   // Zk/Zkn crypto instruction
    OP_AIX     = 6'd24,   // AIX tensor instruction
    OP_CSR     = 6'd25,   // CSR read/write (subset of SYSTEM fast path)
    OP_HALT    = 6'd26    // Pipeline flush / halt marker
  } opcode_type_t;

  // ---------------------------------------------------------------------------
  // Micro-Op (uop) - the fundamental unit flowing through the ZEN++ pipeline
  // ---------------------------------------------------------------------------
  typedef struct packed {
    opcode_type_t opcode;         // Internal decoded opcode
    xword_t       pc;             // PC of the instruction
    xword_t       imm;            // Sign/zero-extended immediate
    arch_reg_idx_t rs1;           // Architectural source 1
    arch_reg_idx_t rs2;           // Architectural source 2
    arch_reg_idx_t rd;            // Architectural destination
    phys_reg_idx_t prs1;          // Physical source 1 (after rename)
    phys_reg_idx_t prs2;          // Physical source 2 (after rename)
    phys_reg_idx_t prd;           // Physical destination (after rename)
    phys_reg_idx_t prd_old;       // Previous physical destination (for rollback)
    rob_idx_t     rob_idx;        // Assigned ROB entry
    uop_id_t      uop_id;         // Unique tag for trace/debug
    tid_t         tid;            // SMT thread ID
    sq_idx_t      sq_idx;         // Store queue index (stores only)
    lq_idx_t      lq_idx;         // Load queue index (loads only)
    logic         is_branch;      // Branch-type uop
    logic         is_cond;        // Conditional (direct) branch
    logic         is_indirect;    // Indirect branch (JALR)
    logic         is_return;      // Return (pop RAS)
    logic         is_call;        // Call (push RAS)
    logic         is_load;        // Load-type
    logic         is_store;       // Store-type
    logic         is_fp;          // Uses FP register file
    logic         is_vec;         // Uses vector register file
    logic         is_aix;         // AIX tensor instruction
    logic         pred_taken;     // BPU prediction (1 = taken)
    xword_t       pred_target;    // BPU predicted target
    logic [2:0]   funct3;         // RISC-V funct3
    logic [6:0]   funct7;         // RISC-V funct7
    exception_t   exc;            // Decoded exception (illegal inst, etc.)
  } uop_t;

`define UOP_NOP '0   // uop_t is packed; opcode 0 = OP_NOP

  // ---------------------------------------------------------------------------
  // Functional Unit Type (for scheduler port mapping)
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    FU_ALU   = 4'd0,     // Integer ALU
    FU_MUL   = 4'd1,     // Multiplier
    FU_DIV   = 4'd2,     // Divider
    FU_FPU   = 4'd3,     // FP unit
    FU_FMA   = 4'd4,     // FP FMA
    FU_VEC   = 4'd5,     // Vector ALU
    FU_BRU   = 4'd6,     // Branch resolve unit
    FU_LSU   = 4'd7,     // Load/store unit
    FU_CSR   = 4'd8,     // CSR unit
    FU_CRY   = 4'd9,     // Crypto unit
    FU_AIX   = 4'd10     // AIX dispatch port
  } fu_type_t;

  // ---------------------------------------------------------------------------
  // NoC Flit Definition
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_HEAD   = 2'd0,   // Head flit (carries route info)
    FLIT_BODY   = 2'd1,   // Body flit
    FLIT_TAIL   = 2'd2,   // Tail flit (last of packet)
    FLIT_SINGLE = 2'd3    // Single-flit packet (head+tail)
  } flit_type_t;

  typedef struct packed {
    logic [NOC_DATA_WIDTH-1:0] payload;  // Flit payload
    logic [NOC_X_BITS-1:0]     dest_x;   // Destination mesh X
    logic [NOC_Y_BITS-1:0]     dest_y;   // Destination mesh Y
    logic [NOC_X_BITS-1:0]     src_x;    // Source mesh X
    logic [NOC_Y_BITS-1:0]     src_y;    // Source mesh Y
    logic [$clog2(NOC_VC)-1:0] vc_id;    // Virtual channel
    flit_type_t                ftype;    // Head/body/tail/single
    logic                      valid;    // Flit valid
  } flit_t;

  `define FLIT_EMPTY '0   // flit_t is packed; valid=0

  // ---------------------------------------------------------------------------
  // AIX Tensor Descriptor (TDB entry, 512-bit / 64 bytes)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [63:0]  base_addr;      // Tensor base address (physical)
    logic [31:0]  dim0;           // Dimension 0 (rows / outermost)
    logic [31:0]  dim1;           // Dimension 1 (cols)
    logic [31:0]  dim2;           // Dimension 2 (channels)
    logic [31:0]  dim3;           // Dimension 3 (batch)
    logic [31:0]  stride0;        // Byte stride dim0
    logic [31:0]  stride1;        // Byte stride dim1
    logic [31:0]  stride2;        // Byte stride dim2
    logic [7:0]   dtype;          // AI_DTYPE_*
    logic [7:0]   layout;         // Layout code (0=row-major NCHW, 1=NHWC, ...)
    logic [7:0]   sparse_mask;    // Sparsity metadata pointer (compression)
    logic         valid;          // Descriptor valid
    logic [134:0] reserved;       // Pad to 512 bits
  } aix_tdb_t;

  // AIX command descriptor (issued by CPU via AIX instruction)
  typedef struct packed {
    logic [AIX_HANDLE_BITS-1:0] tdb0;      // Tensor handle A
    logic [AIX_HANDLE_BITS-1:0] tdb1;      // Tensor handle B
    logic [AIX_HANDLE_BITS-1:0] tdb2;      // Tensor handle C (output)
    logic [7:0]                 opcode;    // AIX opcode (GEMM/CONV/ATTN/...)
    logic [7:0]                 flags;     // Accumulate / sparse / ...
    logic [AIX_TILEID_BITS-1:0] tile_id;   // Target AI tile
    logic [31:0]                length;    // Element count / iteration count
  } aix_cmd_t;

  // AIX opcodes
  localparam logic [7:0] AIX_OP_GEMM    = 8'h01;  // C = A x B (+C)
  localparam logic [7:0] AIX_OP_CONV    = 8'h02;  // Convolution
  localparam logic [7:0] AIX_OP_ATTN_QK = 8'h03;  // Attention QK^T
  localparam logic [7:0] AIX_OP_ATTN_AV = 8'h04;  // Attention AV
  localparam logic [7:0] AIX_OP_EW_ADD  = 8'h05;  // Element-wise add
  localparam logic [7:0] AIX_OP_EW_MUL  = 8'h06;  // Element-wise multiply
  localparam logic [7:0] AIX_OP_ACT     = 8'h07;  // Activation function
  localparam logic [7:0] AIX_OP_REDUCE  = 8'h08;  // Reduction (sum/max)
  localparam logic [7:0] AIX_OP_DMA_LD  = 8'h10;  // Host->AI DMA load
  localparam logic [7:0] AIX_OP_DMA_ST  = 8'h11;  // AI->Host DMA store

  // ---------------------------------------------------------------------------
  // Cache Coherence States (MESI-F, used by lsu_dcache / l2cache / orca_chi_coh)
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    COH_INVALID   = 3'd0,   // I
    COH_SHARED    = 3'd1,   // S
    COH_EXCLUSIVE = 3'd2,   // E
    COH_MODIFIED  = 3'd3,   // M
    COH_FORWARD   = 3'd4,   // F (shared + designated responder)
    COH_PENDING   = 3'd5    // Transient state (request outstanding)
  } coh_state_t;

  // HBM3 bank states (used by npu_hbm3_ctrl)
  typedef enum logic [3:0] {
    BANK_IDLE        = 4'd0,
    BANK_ACTIVE      = 4'd1,
    BANK_ACTIVATING  = 4'd2,
    BANK_PRECHARGING = 4'd3,
    BANK_READING     = 4'd4,
    BANK_WRITING     = 4'd5,
    BANK_REFRESHING  = 4'd6
  } bank_state_t;

  // ---------------------------------------------------------------------------
  // Tile / Node ID Types
  // ---------------------------------------------------------------------------
  typedef logic [AIX_TILEID_BITS:0] node_id_t;  // 4-bit node ID (8 tiles + IO)
  typedef enum logic [3:0] {
    NODE_CPU_T0 = 4'd0, NODE_CPU_T1 = 4'd1, NODE_CPU_T2 = 4'd2, NODE_CPU_T3 = 4'd3,
    NODE_AI_T0  = 4'd4, NODE_AI_T1  = 4'd5, NODE_AI_T2  = 4'd6, NODE_AI_T3  = 4'd7,
    NODE_MEM    = 4'd8, NODE_IO     = 4'd9, NODE_NONE   = 4'hF
  } node_type_t;

  // ---------------------------------------------------------------------------
  // Performance Monitor Event Codes (write-once counters in SoC)
  // ---------------------------------------------------------------------------
  typedef enum logic [7:0] {
    PMEV_CYCLES        = 8'd0,   // Core cycles
    PMEV_INST_RETIRE   = 8'd1,   // Instructions retired
    PMEV_BR_MISPRED    = 8'd2,   // Branch mispredictions
    PMEV_L1D_MISS      = 8'd3,   // L1D cache misses
    PMEV_L2_MISS       = 8'd4,   // L2 cache misses
    PMEV_STALL_ROB     = 8'd5,   // ROB-full stalls
    PMEV_STALL_PRF     = 8'd6,   // Physical-RF-full stalls
    PMEV_AIX_ISSUE     = 8'd7,   // AIX instructions issued
    PMEV_AIX_COMP      = 8'd8,   // AIX commands completed
    PMEV_NOC_FLIT      = 8'd9,   // NoC flits transmitted
    PMEV_NOC_STALL     = 8'd10   // NoC output-port stalls
  } pm_event_t;

// ---------------------------------------------------------------------------
  // ROB Entry (used by cmt_rob)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic        complete;     // Execution finished
    uop_t        uop;
    xword_t      result;       // Execution result
    logic        branch_taken; // Actual branch direction
    xword_t      branch_target;
    logic        exception;    // Exception pending
    exception_t  exc_code;
    phys_reg_idx_t prd;        // Physical destination (from rename)
    phys_reg_idx_t old_prd;
    tid_t        tid;
  } rob_entry_t;

endpackage : orca_pkg


`endif // ORCA_PKG_SV
