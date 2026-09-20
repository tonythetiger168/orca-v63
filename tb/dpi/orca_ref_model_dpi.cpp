//=============================================================================
// ORCA v6.3 ZEN++ C++ DPI Reference Model - Implementation
// File: dpi/orca_ref_model_dpi.cpp
// Description: High-performance C++ reference model for UVM DPI integration
//=============================================================================

#include "orca_ref_model_dpi.h"
#include <cmath>
#include <algorithm>
#include <chrono>

// ==========================================================================
// Architectural State
// ==========================================================================

static int g_num_cores = 0;
static int g_smt_threads = 0;

struct ThreadState {
    uint64_t xreg[32];
    uint64_t pc;
    uint64_t freg[32];
    uint64_t vreg[32][8];  // 32 vector regs, 512-bit each (8 x 64-bit)
    uint64_t csr[4096];
    uint64_t instr_count;
    uint64_t exception_count;
    uint64_t branch_count;
    uint64_t mispredict_count;
};

static std::vector<ThreadState> g_threads;
static std::unordered_map<uint64_t, uint8_t> g_memory;  // Sparse memory model

// Instruction decode helpers
static inline uint32_t extract_bits(uint32_t val, int hi, int lo) {
    return (val >> lo) & ((1U << (hi - lo + 1)) - 1);
}

static inline int64_t sign_extend(uint32_t val, int bits) {
    int32_t mask = 1 << (bits - 1);
    return (val ^ mask) - mask;
}

// ==========================================================================
// Initialization
// ==========================================================================

extern "C" void orca_ref_init(int num_cores, int smt_threads) {
    g_num_cores = num_cores;
    g_smt_threads = smt_threads;
    g_threads.resize(smt_threads);
    orca_ref_reset();
    printf("[DPI] ORCA Ref Model initialized: %d cores, %d SMT threads\n",
           num_cores, smt_threads);
}

extern "C" void orca_ref_reset() {
    for (auto& t : g_threads) {
        memset(t.xreg, 0, sizeof(t.xreg));
        memset(t.freg, 0, sizeof(t.freg));
        memset(t.vreg, 0, sizeof(t.vreg));
        memset(t.csr, 0, sizeof(t.csr));
        t.pc = 0x80000000ULL;
        t.xreg[0] = 0;  // x0 is hardwired to 0
        t.instr_count = 0;
        t.exception_count = 0;
        t.branch_count = 0;
        t.mispredict_count = 0;
    }
    g_memory.clear();
}

extern "C" void orca_ref_cleanup() {
    g_threads.clear();
    g_memory.clear();
    printf("[DPI] ORCA Ref Model cleaned up\n");
}

// ==========================================================================
// Integer ALU Execution
// ==========================================================================

extern "C" void orca_ref_exec_instr(
    uint64_t pc,
    uint32_t instr,
    int      tid,
    uint64_t rs1_data,
    uint64_t rs2_data,
    uint64_t rs3_data,
    uint64_t* result,
    int*      exception,
    int*      exc_code,
    uint64_t* next_pc,
    int*      rd_valid
) {
    if (tid < 0 || tid >= (int)g_threads.size()) {
        *exception = 1;
        *exc_code = 2;  // Illegal instruction
        return;
    }

    ThreadState& t = g_threads[tid];
    t.instr_count++;

    uint32_t opcode = extract_bits(instr, 6, 0);
    uint32_t rd     = extract_bits(instr, 11, 7);
    uint32_t rs1    = extract_bits(instr, 19, 15);
    uint32_t rs2    = extract_bits(instr, 24, 20);
    uint32_t funct3 = extract_bits(instr, 14, 12);
    uint32_t funct7 = extract_bits(instr, 31, 25);

    uint64_t op_a = (rs1 == 0) ? 0 : rs1_data;
    uint64_t op_b = (rs2 == 0) ? 0 : rs2_data;
    uint64_t res = 0;
    int exc = 0;
    int exc_c = 0;
    uint64_t npc = pc + 4;
    int rd_v = 1;

    switch (opcode) {
        case 0x33: {  // OP (ALU)
            switch (funct3) {
                case 0x0: res = (funct7 & 0x20) ? (op_a - op_b) : (op_a + op_b); break;
                case 0x1: res = op_a << (op_b & 0x3F); break;
                case 0x2: res = ((int64_t)op_a < (int64_t)op_b) ? 1 : 0; break;
                case 0x3: res = (op_a < op_b) ? 1 : 0; break;
                case 0x4: res = op_a ^ op_b; break;
                case 0x5: res = (funct7 & 0x20) ? ((int64_t)op_a >> (op_b & 0x3F))
                                                : (op_a >> (op_b & 0x3F)); break;
                case 0x6: res = op_a | op_b; break;
                case 0x7: res = op_a & op_b; break;
            }
            break;
        }
        case 0x13: {  // OP-IMM
            int64_t imm = sign_extend(extract_bits(instr, 31, 20), 12);
            switch (funct3) {
                case 0x0: res = op_a + imm; break;
                case 0x1: res = op_a << (imm & 0x3F); break;
                case 0x2: res = ((int64_t)op_a < imm) ? 1 : 0; break;
                case 0x3: res = (op_a < (uint64_t)imm) ? 1 : 0; break;
                case 0x4: res = op_a ^ imm; break;
                case 0x5: res = (funct7 & 0x20) ? ((int64_t)op_a >> (imm & 0x3F))
                                                : (op_a >> (imm & 0x3F)); break;
                case 0x6: res = op_a | imm; break;
                case 0x7: res = op_a & imm; break;
            }
            break;
        }
        case 0x03: {  // LOAD
            int64_t imm = sign_extend(extract_bits(instr, 31, 20), 12);
            uint64_t addr = op_a + imm;
            if (addr & 0x7) { exc = 1; exc_c = 4; }  // Misaligned
            else {
                auto it = g_memory.find(addr);
                res = (it != g_memory.end()) ? it->second : 0;
                // Sign-extend based on funct3
                switch (funct3) {
                    case 0x0: res = sign_extend(res & 0xFF, 8); break;   // LB
                    case 0x1: res = sign_extend(res & 0xFFFF, 16); break; // LH
                    case 0x2: /* LW - already 32-bit */ break;
                    case 0x3: /* LD - 64-bit */ break;
                    case 0x4: res &= 0xFF; break;   // LBU
                    case 0x5: res &= 0xFFFF; break; // LHU
                    case 0x6: res &= 0xFFFFFFFF; break; // LWU
                }
            }
            break;
        }
        case 0x23: {  // STORE
            int64_t imm = sign_extend((extract_bits(instr, 31, 25) << 5) |
                                       extract_bits(instr, 11, 7), 12);
            uint64_t addr = op_a + imm;
            if (addr & 0x7) { exc = 1; exc_c = 6; }
            else { g_memory[addr] = op_b & 0xFF; rd_v = 0; }
            break;
        }
        case 0x63: {  // BRANCH
            t.branch_count++;
            int64_t imm = sign_extend(
                (extract_bits(instr, 31, 31) << 12) |
                (extract_bits(instr, 30, 25) << 5) |
                (extract_bits(instr, 11, 8) << 1) |
                (extract_bits(instr, 7, 7) << 11), 13);
            bool taken = false;
            switch (funct3) {
                case 0x0: taken = (op_a == op_b); break;  // BEQ
                case 0x1: taken = (op_a != op_b); break;  // BNE
                case 0x4: taken = ((int64_t)op_a < (int64_t)op_b); break;  // BLT
                case 0x5: taken = ((int64_t)op_a >= (int64_t)op_b); break; // BGE
                case 0x6: taken = (op_a < op_b); break;  // BLTU
                case 0x7: taken = (op_a >= op_b); break; // BGEU
            }
            npc = taken ? (pc + imm) : (pc + 4);
            rd_v = 0;
            break;
        }
        case 0x6F: {  // JAL
            int64_t imm = sign_extend(
                (extract_bits(instr, 31, 31) << 20) |
                (extract_bits(instr, 30, 21) << 1) |
                (extract_bits(instr, 20, 20) << 11) |
                (extract_bits(instr, 19, 12) << 12), 21);
            res = pc + 4;
            npc = pc + imm;
            break;
        }
        case 0x67: {  // JALR
            int64_t imm = sign_extend(extract_bits(instr, 31, 20), 12);
            res = pc + 4;
            npc = (op_a + imm) & ~1ULL;
            break;
        }
        case 0x37: {  // LUI
            res = (uint64_t)(instr & 0xFFFFF000);
            break;
        }
        case 0x17: {  // AUIPC
            res = pc + (uint64_t)(instr & 0xFFFFF000);
            break;
        }
        default:
            exc = 1;
            exc_c = 2;  // Illegal instruction
            break;
    }

    // Update architectural state
    if (!exc && rd_v && rd != 0) {
        t.xreg[rd] = res;
    }
    t.pc = npc;
    if (exc) t.exception_count++;

    *result = res;
    *exception = exc;
    *exc_code = exc_c;
    *next_pc = npc;
    *rd_valid = rd_v;
}

// ==========================================================================
// Vector Execution (512-bit RVV)
// ==========================================================================

extern "C" void orca_ref_exec_vec_instr(
    uint64_t pc,
    uint32_t instr,
    int      tid,
    const uint64_t* vs1_data,
    const uint64_t* vs2_data,
    const uint64_t* vd_data,
    int      vl,
    int      sew,
    uint64_t* vd_result,
    int*      exception
) {
    if (tid < 0 || tid >= (int)g_threads.size()) {
        *exception = 1;
        return;
    }

    ThreadState& t = g_threads[tid];
    uint32_t opcode = extract_bits(instr, 6, 0);
    uint32_t funct3 = extract_bits(instr, 14, 12);

    // Copy input to output as base
    for (int i = 0; i < 8; i++) {
        vd_result[i] = vd_data[i];
    }

    int elements_per_reg = 512 / sew;  // Number of elements in 512-bit reg
    int num_regs = (vl + elements_per_reg - 1) / elements_per_reg;

    switch (funct3) {
        case 0x0: {  // OPIVV (vector-vector integer)
            for (int i = 0; i < vl; i++) {
                int reg_idx = i / elements_per_reg;
                int elem_idx = i % elements_per_reg;
                int shift = elem_idx * sew;

                uint64_t mask = (sew == 64) ? ~0ULL : ((1ULL << sew) - 1);
                uint64_t a = (vs1_data[reg_idx] >> shift) & mask;
                uint64_t b = (vs2_data[reg_idx] >> shift) & mask;
                uint64_t res = (a + b) & mask;

                vd_result[reg_idx] &= ~(mask << shift);
                vd_result[reg_idx] |= (res << shift);
            }
            break;
        }
        case 0x3: {  // OPIVI (vector-immediate)
            int64_t imm = sign_extend(extract_bits(instr, 19, 15), 5);
            for (int i = 0; i < vl; i++) {
                int reg_idx = i / elements_per_reg;
                int elem_idx = i % elements_per_reg;
                int shift = elem_idx * sew;

                uint64_t mask = (sew == 64) ? ~0ULL : ((1ULL << sew) - 1);
                uint64_t a = (vs2_data[reg_idx] >> shift) & mask;
                uint64_t res = (a + imm) & mask;

                vd_result[reg_idx] &= ~(mask << shift);
                vd_result[reg_idx] |= (res << shift);
            }
            break;
        }
        default:
            *exception = 1;
            return;
    }

    *exception = 0;
}

// ==========================================================================
// AI Reference: Matrix Multiplication
// ==========================================================================

extern "C" void orca_ref_ai_matmul(
    int M, int N, int K,
    int dtype,
    const uint8_t* A,
    const uint8_t* B,
    uint8_t*       C,
    int lda, int ldb, int ldc
) {
    if (dtype == 0) {  // INT8
        for (int m = 0; m < M; m++) {
            for (int n = 0; n < N; n++) {
                int32_t sum = 0;
                for (int k = 0; k < K; k++) {
                    int8_t a = (int8_t)A[m * lda + k];
                    int8_t b = (int8_t)B[k * ldb + n];
                    sum += a * b;
                }
                C[m * ldc + n] = (uint8_t)(sum > 127 ? 127 : (sum < -128 ? -128 : sum));
            }
        }
    } else if (dtype == 1) {  // BF16 (simplified: treat as uint16_t)
        for (int m = 0; m < M; m++) {
            for (int n = 0; n < N; n++) {
                float sum = 0.0f;
                for (int k = 0; k < K; k++) {
                    uint16_t a_raw = *(uint16_t*)&A[(m * lda + k) * 2];
                    uint16_t b_raw = *(uint16_t*)&B[(k * ldb + n) * 2];
                    // Simplified BF16 to float
                    float a = (float)(int16_t)a_raw;
                    float b = (float)(int16_t)b_raw;
                    sum += a * b;
                }
                *(uint16_t*)&C[(m * ldc + n) * 2] = (uint16_t)(int16_t)sum;
            }
        }
    } else {  // FP32
        for (int m = 0; m < M; m++) {
            for (int n = 0; n < N; n++) {
                float sum = 0.0f;
                for (int k = 0; k < K; k++) {
                    float a = *(float*)&A[(m * lda + k) * 4];
                    float b = *(float*)&B[(k * ldb + n) * 4];
                    sum += a * b;
                }
                *(float*)&C[(m * ldc + n) * 4] = sum;
            }
        }
    }
}

// ==========================================================================
// AI Reference: Attention (Q*K^T -> Softmax -> *V)
// ==========================================================================

extern "C" void orca_ref_ai_attention(
    int seq_len,
    int head_dim,
    int num_heads,
    int dtype,
    const uint8_t* Q,
    const uint8_t* K,
    const uint8_t* V,
    uint8_t*       output
) {
    int total_len = seq_len * head_dim * num_heads;
    std::vector<float> scores(seq_len * seq_len);
    std::vector<float> attn_weights(seq_len * seq_len);
    std::vector<float> out_fp32(seq_len * head_dim * num_heads);

    for (int h = 0; h < num_heads; h++) {
        int head_offset = h * seq_len * head_dim;

        // Q * K^T
        for (int i = 0; i < seq_len; i++) {
            for (int j = 0; j < seq_len; j++) {
                float dot = 0.0f;
                for (int d = 0; d < head_dim; d++) {
                    float q = (dtype == 0) ? (float)(int8_t)Q[head_offset + i * head_dim + d]
                                            : *(float*)&Q[(head_offset + i * head_dim + d) * 4];
                    float k = (dtype == 0) ? (float)(int8_t)K[head_offset + j * head_dim + d]
                                            : *(float*)&K[(head_offset + j * head_dim + d) * 4];
                    dot += q * k;
                }
                scores[i * seq_len + j] = dot / sqrtf((float)head_dim);
            }
        }

        // Softmax
        for (int i = 0; i < seq_len; i++) {
            float max_score = scores[i * seq_len];
            for (int j = 1; j < seq_len; j++) {
                max_score = std::max(max_score, scores[i * seq_len + j]);
            }
            float sum_exp = 0.0f;
            for (int j = 0; j < seq_len; j++) {
                attn_weights[i * seq_len + j] = expf(scores[i * seq_len + j] - max_score);
                sum_exp += attn_weights[i * seq_len + j];
            }
            for (int j = 0; j < seq_len; j++) {
                attn_weights[i * seq_len + j] /= sum_exp;
            }
        }

        // * V
        for (int i = 0; i < seq_len; i++) {
            for (int d = 0; d < head_dim; d++) {
                float sum = 0.0f;
                for (int j = 0; j < seq_len; j++) {
                    float v = (dtype == 0) ? (float)(int8_t)V[head_offset + j * head_dim + d]
                                            : *(float*)&V[(head_offset + j * head_dim + d) * 4];
                    sum += attn_weights[i * seq_len + j] * v;
                }
                out_fp32[head_offset + i * head_dim + d] = sum;
            }
        }
    }

    // Convert back to output format
    for (int i = 0; i < total_len; i++) {
        if (dtype == 0) {
            float val = out_fp32[i];
            output[i] = (uint8_t)(val > 127 ? 127 : (val < -128 ? -128 : (int8_t)val));
        } else {
            *(float*)&output[i * 4] = out_fp32[i];
        }
    }
}

// ==========================================================================
// Statistics
// ==========================================================================

extern "C" void orca_ref_get_stats(
    uint64_t* total_instrs,
    uint64_t* total_exceptions,
    uint64_t* total_branches,
    uint64_t* total_mispredicts,
    double*   avg_ipc
) {
    *total_instrs = 0;
    *total_exceptions = 0;
    *total_branches = 0;
    *total_mispredicts = 0;

    for (const auto& t : g_threads) {
        *total_instrs += t.instr_count;
        *total_exceptions += t.exception_count;
        *total_branches += t.branch_count;
        *total_mispredicts += t.mispredict_count;
    }

    *avg_ipc = (*total_instrs > 0) ? (double)(*total_instrs) / (*total_instrs + *total_exceptions) : 0.0;
}

// ==========================================================================
// Register Access
// ==========================================================================

extern "C" uint64_t orca_ref_read_xreg(int tid, int reg_num) {
    if (tid < 0 || tid >= (int)g_threads.size() || reg_num < 0 || reg_num >= 32) return 0;
    return (reg_num == 0) ? 0 : g_threads[tid].xreg[reg_num];
}

extern "C" void orca_ref_write_xreg(int tid, int reg_num, uint64_t value) {
    if (tid < 0 || tid >= (int)g_threads.size() || reg_num < 0 || reg_num >= 32) return;
    if (reg_num != 0) g_threads[tid].xreg[reg_num] = value;
}

extern "C" uint64_t orca_ref_read_pc(int tid) {
    if (tid < 0 || tid >= (int)g_threads.size()) return 0;
    return g_threads[tid].pc;
}

extern "C" void orca_ref_dump_state(int tid) {
    if (tid < 0 || tid >= (int)g_threads.size()) return;
    const ThreadState& t = g_threads[tid];
    printf("[DPI] Thread %d State Dump:\n", tid);
    printf("  PC: 0x%016lx\n", t.pc);
    printf("  Instructions: %lu, Exceptions: %lu\n", t.instr_count, t.exception_count);
    printf("  x0-x7:  %016lx %016lx %016lx %016lx %016lx %016lx %016lx %016lx\n",
           t.xreg[0], t.xreg[1], t.xreg[2], t.xreg[3],
           t.xreg[4], t.xreg[5], t.xreg[6], t.xreg[7]);
}
