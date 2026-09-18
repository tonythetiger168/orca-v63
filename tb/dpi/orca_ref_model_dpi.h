//=============================================================================
// ORCA v6.3 ZEN++ C++ DPI Reference Model - Header
// File: dpi/orca_ref_model_dpi.h
// Description: High-performance C++ reference model for UVM DPI integration
//              10-100x faster than pure SV reference model
//=============================================================================

#ifndef ORCA_REF_MODEL_DPI_H
#define ORCA_REF_MODEL_DPI_H

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <unordered_map>
#include <string>

extern "C" {

// ---------------------------------------------------------------------------
// DPI Export Functions (called from SV)
// ---------------------------------------------------------------------------

// Initialize reference model
void orca_ref_init(int num_cores, int smt_threads);

// Reset architectural state
void orca_ref_reset();

// Execute single instruction and return result
void orca_ref_exec_instr(
    uint64_t pc,
    uint32_t instr,
    int      tid,
    uint64_t rs1_data,
    uint64_t rs2_data,
    uint64_t rs3_data,
    // Outputs
    uint64_t* result,
    int*      exception,
    int*      exc_code,
    uint64_t* next_pc,
    int*      rd_valid
);

// Execute vector instruction (512-bit)
void orca_ref_exec_vec_instr(
    uint64_t pc,
    uint32_t instr,
    int      tid,
    const uint64_t* vs1_data,  // 8 x 64-bit = 512-bit
    const uint64_t* vs2_data,
    const uint64_t* vd_data,
    int      vl,               // Vector length
    int      sew,              // Selected element width
    // Outputs
    uint64_t* vd_result,       // 8 x 64-bit
    int*      exception
);

// Read architectural register
uint64_t orca_ref_read_xreg(int tid, int reg_num);

// Write architectural register
void orca_ref_write_xreg(int tid, int reg_num, uint64_t value);

// Read PC
uint64_t orca_ref_read_pc(int tid);

// Check ROB entry consistency
int orca_ref_check_rob_entry(
    int       rob_idx,
    uint64_t  expected_pc,
    uint32_t  expected_instr,
    uint64_t  expected_result,
    int       expected_complete
);

// AI reference: Execute matrix multiplication
void orca_ref_ai_matmul(
    int       M, int N, int K,
    int       dtype,           // 0=INT8, 1=BF16, 2=FP32
    const uint8_t* A,
    const uint8_t* B,
    uint8_t*       C,
    int       lda, int ldb, int ldc
);

// AI reference: Execute attention (Q*K^T -> Softmax -> *V)
void orca_ref_ai_attention(
    int       seq_len,
    int       head_dim,
    int       num_heads,
    int       dtype,
    const uint8_t* Q,
    const uint8_t* K,
    const uint8_t* V,
    uint8_t*       output
);

// Performance statistics
void orca_ref_get_stats(
    uint64_t* total_instrs,
    uint64_t* total_exceptions,
    uint64_t* total_branches,
    uint64_t* total_mispredicts,
    double*   avg_ipc
);

// Dump architectural state for debug
void orca_ref_dump_state(int tid);

// Cleanup
void orca_ref_cleanup();

} // extern "C"

#endif // ORCA_REF_MODEL_DPI_H
