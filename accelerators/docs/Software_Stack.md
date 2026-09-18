# ORCA AI Accelerator — Software Stack & Toolchain Guide
**Version**: 1.1  **Date**: 2026-09-05
---

## 1. Overview
ORCA AI Accelerator Series 提供統一的軟體棧，從 1 TOPS 的 Kestrel 到 32 TOPS 的 Phoenix+ 共享相同的編程模型與工具鏈。開發者可以無縫地在全系列產品之間遷移模型。
---

## 2. Toolchain Architecture
```
+----------------------------------------------------------------+
|                     Application Layer                          |
|  PyTorch 2.0  |  TensorFlow  |  ONNX Runtime  |  TFLite Micro |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Compiler Layer                             |
|  ORCA-MLIR (TPE/AME Dialect)  |  ORCA-GCC (RVV+FMX)         |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Runtime Layer                              |
|  libphoenix_plus.so | libphoenix.so | libfalcon.so | libkestrel.so |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Driver Layer                               |
|  Linux Kernel Driver  |  OpenSBI  |  Bare-metal HAL          |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Hardware Layer                             |
|  Phoenix+ (UCIe) | Phoenix-E | Phoenix (TPE+AME) | Falcon | Kestrel |
+----------------------------------------------------------------+
```

---

## 3. Generation-Specific Toolchains
### 3.1 v5.0 Kestrel — Embedded / TinyML
**Target**: MCU-class devices, bare-metal or RTOS
```bash
# Bare-metal build
riscv64-unknown-elf-gcc -march=rv64gc -mabi=lp64d -O2 -DORCA_NPU_V5 inference.c kestrel_driver.c -o firmware.elf
# Link with Kestrel HALlibkestrel.a:
    kestrel_init()      # Initialize NPU registers
    kestrel_load_weights(base_addr, size)
    kestrel_load_activations(base_addr, size)
    kestrel_run(config) # Start computation
    kestrel_poll()      # Wait for completion
    kestrel_read_results(base_addr, size)
```
**Framework Support**: TensorFlow Lite Micro
```c
// TFLite Micro Kestrel delegate
#include tensorflow/lite/micro/kernels/kestrel/kestrel_delegate.h
// Register Kestrel accelerator for Conv2D ops
auto* delegate = tflite::KestrelDelegate::Create();
interpreter->ModifyGraphWithDelegate(delegate);
```

---

### 3.2 v5.1 Falcon — Edge AI / Vision
**Target**: Linux edge devices, vector + matrix acceleration
```bash
# GCC with FMX extension
riscv64-unknown-elf-gcc -march=rv64gcv -mabi=lp64d -mfmx -O3 -ffast-math model.c -o falcon.elf
# Auto-vectorization + FMX intrinsic expansion
# Flags: -mfmx enables Falcon Matrix Extension
```
**C Intrinsic API** (`<orca/fmx.h>`)
```c
#include <orca/fmx.h>
// Tile types (32x32 elements)
typedef int8_t  fmx_tile_i8_t[32][32];
typedef int16_t fmx_tile_i16_t[32][32];
typedef __fp16  fmx_tile_f16_t[32][32];
// Memory operations
void fmx_mload_i8 (fmx_tile_i8_t*  dst, const void* src);
void fmx_mload_f16(fmx_tile_f16_t* dst, const void* src);
void fmx_mstore_i8 (void* dst, const fmx_tile_i8_t*  src);
// Matrix multiply-accumulate
void fmx_mmacc_i8 (fmx_tile_i8_t*  acc, const fmx_tile_i8_t*  a, const fmx_tile_i8_t*  b);
void fmx_mmacc_f16(fmx_tile_f16_t* acc, const fmx_tile_f16_t* a, const fmx_tile_f16_t* b);
// Activation
void fmx_relu_i8 (fmx_tile_i8_t*  dst, const fmx_tile_i8_t*  src);
void fmx_relu_f16(fmx_tile_f16_t* dst, const fmx_tile_f16_t* src);
void fmx_gelu_f16(fmx_tile_f16_t* dst, const fmx_tile_f16_t* src);
// Quantization
void fmx_quant_i8(fmx_tile_i8_t* dst, const fmx_tile_i16_t* src, int16_t scale, int8_t zp);
```
**ONNX Runtime Backend**
```python
# Python API for ONNX Runtime with Falcon
import onnxruntime as ort
# Register Falcon EP (Execution Provider)
session = ort.InferenceSession(
    'model.onnx',
    providers=['FalconExecutionProvider'],
    provider_options={'num_tiles': 2})
```

---

### 3.3 v5.2 Hawk — High-Performance Edge / Light Server
**Target**: Edge servers, Vision Transformers, lightweight LLM
```bash
# GCC with FMX2 extension + Transformer intrinsics
riscv64-unknown-elf-gcc -march=rv64gcv -mabi=lp64d -mfmx2 -mtransformer -O3 model.c -o hawk.elf
# Flags: -mfmx2 enables 4-array systolic, -mtransformer enables block ops
```
**C Intrinsic API** (`<orca/fmx2.h>`)
```c
#include <orca/fmx2.h>
// 4-array tile operations
void fmx2_mmacc_i8(fmx2_tile_i8_t acc[4], const fmx2_tile_i8_t a[4], const fmx2_tile_i8_t b[4]);
// Transformer block (hard-accelerated)
typedef struct {
    uint16_t seq_len;
    uint16_t head_dim;
    uint8_t  num_heads;
} fmx2_xfmr_config_t;
void fmx2_transformer_block(void* output, const void* input, const void* weights,
    const fmx2_xfmr_config_t* config);
```

---

### 3.4 v6.0 Phoenix — Server-Class AI / LLM
**Target**: Linux server, multi-core, large models
```bash
# MLIR-based compilation pipeline
orca-mlir-opt --pass-pipeline='
    convert-torch-to-tosa,
    convert-tosa-to-linalg,
    convert-linalg-to-tpe-ame,
    convert-tpe-ame-to-llvm' model.mlir | orca-llvm-llc -march=riscv64 -mcpu=phoenix -o model.s
# PyTorch 2.0 compile backend
import torch
from orca.pytorch import PhoenixCompiler
# Compile model for Phoenixmodel = torch.compile(model, backend='phoenix', mode='reduce-overhead')
```
**Triton Kernel Extension**
```python
# Custom Triton kernel for Phoenix
import triton
import triton.language as tl
from orca.triton import tpe_wmma, ame_spmm
@triton.jit
def phoenix_matmul_kernel(a_ptr, b_ptr, c_ptr, M, N, K, BLOCK_SIZE: tl.constexpr):
    pid = tl.program_id(axis=0)
    num_pid_m = tl.cdiv(M, BLOCK_SIZE)
    num_pid_n = tl.cdiv(N, BLOCK_SIZE)
    pid_m = pid // num_pid_n
    pid_n = pid % num_pid_n
    a_tile = tl.load(a_ptr + ...)
    b_tile = tl.load(b_ptr + ...)
    c_tile = tpe_wmma(a_tile, b_tile)
    tl.store(c_ptr + ..., c_tile)
```

---

### 3.5 v6.1 Phoenix-E — Edge Server
**Target**: Industrial gateway, smart NVR, medical imaging
```bash
# Same toolchain as Phoenix v6.0, auto-detects tile count at runtime
orca-llvm-llc -march=riscv64 -mcpu=phoenix-e -o model.s
# Runtime auto-detects 6 tiles vs 8 tiles, adjusts tiling strategy
```
**Runtime API** (`libphoenix.so`, same as v6.0)
```c
// Phoenix-E uses identical API to Phoenix v6.0
// Runtime queries hardware capabilities automatically
phoenix_init();  // Detects Phoenix-E (6 tiles, 12 blocks, 256-bit)
// No code change needed from Phoenix v6.0
```

---

### 3.6 v6.2 Phoenix+ — Datacenter / Multi-Chip
**Target**: High-density inference servers, 5G MEC, fleet AI
```bash
# Multi-die compilation with automatic work distribution
orca-mlir-opt --tpe-ame-distribute-dies=2 model.mlir | orca-llvm-llc -march=riscv64 -mcpu=phoenix-plus -o model.s
# PyTorch backend
import torch
from orca.pytorch import PhoenixPlusCompiler
# Compile for dual-die Phoenix+
model = torch.compile(
    model,
    backend='phoenix_plus',
    mode='max-autotune',
    options={'num_dies': 2, 'parallel_strategy': 'data'})
```
**Runtime API** (`libphoenix_plus.so`)
```c
#include <orca/phoenix_plus.h>
// Initialize dual-die subsystem
phoenix_plus_init(2);  // 2 dies
// Query topology
phoenix_plus_topology_t topo;
phoenix_plus_get_topology(&topo);
// Run inference with automatic work distribution
phoenix_plus_inference(model, input, output, PHOENIX_PLUS_AUTO_PARALLEL);
// Strategies: DATA_PARALLEL, TENSOR_PARALLEL, PIPELINE_PARALLEL
```

---

## 4. Runtime Libraries
### 4.1 libkestrel.so (v5.0)
| API | Description |
|:---|:---|
| `kestrel_init()` | Initialize NPU, reset config registers |
| `kestrel_configure(const kestrel_config_t* cfg)` | Set M/N/K, activation mode, base addresses |
| `kestrel_load_weights(const void* src, size_t len)` | DMA weights from DDR to NPU SRAM |
| `kestrel_load_activations(const void* src, size_t len)` | DMA activations from DDR to NPU SRAM |
| `kestrel_run()` | Start computation, return immediately |
| `kestrel_wait()` | Poll until NPU_DONE |
| `kestrel_read_results(void* dst, size_t len)` | DMA results from NPU to DDR |
| `kestrel_get_ops_counter()` | Read performance counter |

### 4.2 libfalcon.so (v5.1)
| API | Description |
|:---|:---|
| `falcon_init()` | Initialize FMX, allocate tile SRAM |
| `falcon_tile_load(int tile_id, const void* src)` | Load tile from memory |
| `falcon_tile_store(int tile_id, void* dst)` | Store tile to memory |
| `falcon_mmacc(int acc_tile, int a_tile, int b_tile)` | Matrix multiply-accumulate |
| `falcon_activate(int dst_tile, int src_tile, falcon_act_t mode)` | Apply activation |
| `falcon_quantize(int dst_tile, int src_tile, float scale, int zp)` | Quantize to INT8 |
| `falcon_sync()` | Wait for all FMX operations to complete |

### 4.3 libphoenix.so (v6.0 / v6.1)
| API | Description |
|:---|:---|
| `phoenix_init(int num_tpe_tiles, int num_ame_blocks)` | Initialize TPE + AME (auto-detect on v6.1) |
| `phoenix_tpe_wmma(...)` | Submit WMMA command to TPE |
| `phoenix_ame_spmm(...)` | Submit SpMM command to AME |
| `phoenix_submit_batch(phoenix_cmd_t* cmds, int count)` | Batch submit commands to FIFO |
| `phoenix_wait_event(uint64_t event_id)` | Wait for specific command completion |
| `phoenix_get_tpe_ops()` | Read TPE performance counter |
| `phoenix_get_ame_ops()` | Read AME performance counter |
| `phoenix_memory_pool_alloc(size_t size)` | Allocate coherent memory for DMA |

### 4.4 libphoenix_plus.so (v6.2)
| API | Description |
|:---|:---|
| `phoenix_plus_init(int num_dies)` | Initialize multi-die subsystem |
| `phoenix_plus_get_topology(...)` | Query die configuration |
| `phoenix_plus_inference(...)` | Run inference with auto-parallelism |
| `phoenix_plus_set_strategy(...)` | Set parallel strategy (data/tensor/pipeline) |
| `phoenix_plus_all_reduce(...)` | Cross-die result reduction |
| `phoenix_plus_get_die_ops(int die_id)` | Per-die performance counter |

---

## 5. Debugging & Profiling
### 5.1 Performance Counters
All generations expose hardware performance counters:
| Counter | v5.0 | v5.1 | v5.2 | v6.0 | v6.1 | v6.2 | Description |
|:|:---|:---|:---|:---|:---|:---|:---|
| `OPS_TOTAL` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Total MAC operations executed |
| `CYCLES_BUSY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Cycles NPU is active |
| `CYCLES_IDLE` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Cycles NPU is idle |
| `DMA_RD_BYTES` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Total DMA read bytes |
| `DMA_WR_BYTES` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Total DMA write bytes |
| `TPE_TILE_HITS` | — | — | — | ✅ | ✅ | ✅ | TPE tile cache hits |
| `AME_SKIP_ROWS` | — | — | — | ✅ | ✅ | ✅ | AME rows skipped (sparse) |
| `D2D_TX_BYTES` | — | — | — | — | — | ✅ | Die-to-die transmit bytes (Phoenix+) |
| `D2D_RX_BYTES` | — | — | — | — | — | ✅ | Die-to-die receive bytes (Phoenix+) |

### 5.2 Debug Interface
```bash
# Read performance counters via /sysfs (Linux)
cat /sys/class/orca-npu/tpe_ops_counter
cat /sys/class/orca-npu/ame_ops_counter
cat /sys/class/orca-npu/d2d_tx_bytes  # Phoenix+ only
cat /sys/class/orca-npu/d2d_rx_bytes  # Phoenix+ only
# Trace command execution (via ftrace)
echo 1 > /sys/kernel/debug/tracing/events/orca_npu/enable
cat /sys/kernel/debug/tracing/trace
```

---

## 6. Porting Guide
### 6.1 From v5.0 Kestrel to v5.1 Falcon
```c
// v5.0: Memory-mapped register programming
kestrel_configure(&cfg);
kestrel_run();
kestrel_wait();
// v5.1: FMX intrinsic programming (higher level)
fmx_mload_i8(&tile_a, weight_ptr);
fmx_mload_i8(&tile_b, act_ptr);
fmx_mmacc_i8(&tile_c, &tile_a, &tile_b);
fmx_relu_i8(&tile_c, &tile_c);
fmx_mstore_i8(result_ptr, &tile_c);
```

### 6.2 From v5.1 Falcon to v5.2 Hawk
```c
// v5.1: Single tile operation
fmx_mmacc_i8(&tile_c, &tile_a, &tile_b);
// v5.2: 4-array tile operation
fmx2_tile_i8_t a[4], b[4], c[4];
fmx2_mmacc_i8(c, a, b);
// v5.2: Transformer block (hard-accelerated)
fmx2_transformer_block(output, input, weights, &xfmr_cfg);
```

### 6.3 From v5.2 Hawk to v6.0 Phoenix
```c
// v5.2: FMX2 tile operation
fmx2_mmacc_i8(c, a, b);
// v6.0: WMMA command queue
phoenix_cmd_t cmd = {
    .type = PHOENIX_CMD_TPE_WMMA,
    .tile_a = 0, .tile_b = 1, .tile_c = 2,
    .scale = 1.0f, .zp = 0
};
phoenix_submit_batch(&cmd, 1);
phoenix_wait_event(cmd.event_id);
```

### 6.4 From v6.0 Phoenix to v6.1 Phoenix-E
```c
// v6.0: Explicit tile count
phoenix_init(8, 16);  // 8 TPE tiles, 16 AME blocks
// v6.1: Auto-detect (same code runs on both)
phoenix_init(-1, -1);  // Auto-detect: 6 tiles, 12 blocks on Phoenix-E
// No other code changes needed — ISA is identical
```

### 6.5 From v6.0 Phoenix to v6.2 Phoenix+
```c
// v6.0: Single-die inference
phoenix_inference(model, input, output);
// v6.2: Multi-die inference (automatic work distribution)
phoenix_plus_init(2);  // 2 dies
phoenix_plus_inference(model, input, output, PHOENIX_PLUS_AUTO_PARALLEL);
```

---

## 7. Build System Integration
### 7.1 CMake
```cmake
# Find ORCA AI package
find_package(OrcaAI REQUIRED)
# Target-specific configuration
if(ORCA_AI_TARGET STREQUAL kestrel)
    target_compile_definitions(myapp PRIVATE ORCA_NPU_V5)
    target_link_libraries(myapp OrcaAI::kestrel)
elseif(ORCA_AI_TARGET STREQUAL falcon)
    target_compile_definitions(myapp PRIVATE ORCA_NPU_V5_1)
    target_link_libraries(myapp OrcaAI::falcon)
elseif(ORCA_AI_TARGET STREQUAL hawk)
    target_compile_definitions(myapp PRIVATE ORCA_NPU_V5_2)
    target_link_libraries(myapp OrcaAI::hawk)
elseif(ORCA_AI_TARGET STREQUAL phoenix)
    target_compile_definitions(myapp PRIVATE ORCA_NPU_V6)
    target_link_libraries(myapp OrcaAI::phoenix)
elseif(ORCA_AI_TARGET STREQUAL phoenix-e)
    target_compile_definitions(myapp PRIVATE ORCA_NPU_V6_1)
    target_link_libraries(myapp OrcaAI::phoenix)  # Same lib as v6.0
elseif(ORCA_AI_TARGET STREQUAL phoenix-plus)
    target_compile_definitions(myapp PRIVATE ORCA_NPU_V6_2)
    target_link_libraries(myapp OrcaAI::phoenix_plus)
endif()
```

### 7.2 Makefile
```makefile
# ORCA AI Accelerator build
ORCA_AI_ROOT ?= /opt/orca-ai
ARCH ?= rv64gcv
# Include path
CFLAGS += -I$(ORCA_AI_ROOT)/include
# Library path
LDFLAGS += -L$(ORCA_AI_ROOT)/lib
# Link appropriate runtime
ifeq ($(TARGET),kestrel)
    LDFLAGS += -lorca_kestrel
else ifeq ($(TARGET),falcon)
    LDFLAGS += -lorca_falcon -mfmx
else ifeq ($(TARGET),hawk)
    LDFLAGS += -lorca_hawk -mfmx2
else ifeq ($(TARGET),phoenix)
    LDFLAGS += -lorca_phoenix
else ifeq ($(TARGET),phoenix-e)
    LDFLAGS += -lorca_phoenix
else ifeq ($(TARGET),phoenix-plus)
    LDFLAGS += -lorca_phoenix_plus
endif
```

---

## 8. Verification & Simulation
### 8.1 Verilator Simulation
```bash
# Build simulation model
verilator --cc --exe --build -Wall orca_npu_v5.sv sim_main.cpp
# Run with test vectors
./obj_dir/Vorca_npu_v5 --weights=weights.bin --activations=acts.bin --golden=golden.bin
```

### 8.2 FPGA Prototyping
| Board | Target | Status |
|:---|:---|:---|
| Xilinx ZCU104 | v5.0 Kestrel | Planned |
| Xilinx VCK190 | v5.1 Falcon | Planned |
| Xilinx VCK190 | v5.2 Hawk | Planned |
| AMD Alveo U55C | v6.0 Phoenix | Future |
| AMD Alveo U55C | v6.1 Phoenix-E | Future |
| Custom 2.5D CoWoS | v6.2 Phoenix+ | Future |
