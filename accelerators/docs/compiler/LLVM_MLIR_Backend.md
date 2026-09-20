# ORCA AI Compiler Backend — LLVM/MLIR Extension Guide
**Version**: 1.0  **Date**: 2026-09-05  **Target**: ORCA AI Accelerator Series (Kestrel → Phoenix+)**
---

## 1. Overview
ORCA provides a unified compiler toolchain based on **LLVM 18+** and **MLIR (Multi-Level Intermediate Representation)**. The backend translates high-level ML models into optimized machine code for all seven generations of ORCA AI accelerators.
---

## 2. Compiler Architecture
```
+----------------------------------------------------------------+
|                     Input Layer                                |
|  PyTorch  |  TensorFlow  |  ONNX  |  JAX  |  TFLite       |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Frontend                                   |
|  Torch-MLIR  |  TF-MLIR  |  ONNX-MLIR  |  JAX-MLIR      |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     ORCA-MLIR Dialects                         |
|  +--------+  +--------+  +--------+  +--------+            |
|  | orca   |→| tpu    |→| npu    |→| vector |            |
|  | .mem   |  | .tile  |  | .mac   |  | .rvv   |            |
|  +--------+  +--------+  +--------+  +--------+            |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Code Generation                            |
|  +--------+  +--------+  +--------+  +--------+            |
|  | TPE    |  | AME    |  | FMX    |  | Kestrel|            |
|  | Gen    |  | Gen    |  | Gen    |  | Gen    |            |
|  +--------+  +--------+  +--------+  +--------+            |
+----------------------------------------------------------------+
                            |
                            v
+----------------------------------------------------------------+
|                     Target-Specific Output                     |
|  RISC-V +  |  RISC-V +  |  RISC-V +  |  Memory-   |       |
|  WMMA      |  SpMM      |  FMX/FMX2  |  Mapped    |       |
|  (v6.x)    |  (v6.x)    |  (v5.x)    |  (v5.0)    |       |
+----------------------------------------------------------------+
```

---

## 3. ORCA-MLIR Dialects
### 3.1 `orca.mem` Dialect (Kestrel v5.0)
```mlir
// Memory-mapped NPU configuration for Kestrel
func.func @kestrel_conv2d(%weights: memref<1024xi32>, %activations: memref<1024xi32>) -> memref<256xi32> {
  %cfg = orca.mem.config {m=32, n=32, k=32, act_mode=0}
  orca.mem.dma_write %weights to @weight_sram : memref<1024xi32>
  orca.mem.dma_write %activations to @act_sram : memref<1024xi32>
  orca.mem.start
  %result = orca.mem.dma_read @result_sram : memref<256xi32>
  return %result : memref<256xi32>
}
```

### 3.2 `orca.vector` Dialect (Falcon v5.1 / Hawk v5.2)
```mlir
// RVV + FMX vector/matrix operations
func.func @falcon_matmul(%a: vector<128xi8>, %b: vector<128xi8>) -> vector<128xi32> {
  %c0 = arith.constant 0 : i32
  %acc = vector.broadcast %c0 : i32 to vector<128xi32>
  %result = orca.vector.fmx.mmacc %acc, %a, %b
    : vector<128xi32>, vector<128xi8>, vector<128xi8> -> vector<128xi32>
  return %result : vector<128xi32>
}
```

### 3.3 `orca.tpu` Dialect (Phoenix v6.x)
```mlir
// TPE WMMA tensor operations
func.func @phoenix_wmma(%a: tensor<16x16xf16>, %b: tensor<16x16xf16>) -> tensor<16x16xf32> {
  %c0 = arith.constant 0.0 : f32
  %acc = linalg.fill ins(%c0 : f32) outs(%init : tensor<16x16xf32>) -> tensor<16x16xf32>
  %result = orca.tpu.wmma %acc, %a, %b
    : tensor<16x16xf32>, tensor<16x16xf16>, tensor<16x16xf16> -> tensor<16x16xf32>
  return %result : tensor<16x16xf32>
}
```

### 3.4 `orca.npu` Dialect (Unified)
```mlir
// Generic NPU dialect lowered to target-specific ops
func.func @orca_inference(%input: tensor<1x224x224x3xf32>) -> tensor<1x1000xf32> {
  %conv1 = orca.npu.conv2d %input, %filter1
    {strides=[2,2], padding='SAME', activation='RELU'}
    : (tensor<1x224x224x3xf32>, tensor<7x7x3x64xf32>) -> tensor<1x112x112x64xf32>
  %pool1 = orca.npu.maxpool %conv1
    {ksize=[3,3], strides=[2,2]}
    : tensor<1x112x112x64xf32> -> tensor<1x56x56x64xf32>
  // ... more layers
  return %fc : tensor<1x1000xf32>
}
```

---

## 4. Target-Specific Code Generation
### 4.1 Kestrel (v5.0) CodeGen
```mlir
// Before: orca.npu.conv2d
// After: Memory-mapped register sequences
llvm.func @kestrel_conv2d(...) {
  // Write CFG_M = 112
  %m_ptr = llvm.inttoptr %c0x50000000 : i64 to !llvm.ptr
  llvm.store %c112_i16, %m_ptr : i16, !llvm.ptr
  // Write CFG_N = 64
  %n_ptr = llvm.inttoptr %c0x50000004 : i64 to !llvm.ptr
  llvm.store %c64_i16, %n_ptr : i16, !llvm.ptr
  // Start computation
  %start_ptr = llvm.inttoptr %c0x5000001C : i64 to !llvm.ptr
  llvm.store %c1_i32, %start_ptr : i32, !llvm.ptr
  // Poll STATUS
  llvm.br ^poll
  ^poll:
  %status_ptr = llvm.inttoptr %c0x50000020 : i64 to !llvm.ptr
  %status = llvm.load %status_ptr : !llvm.ptr -> i32
  %done = llvm.and %status, %c2_i32 : i32
  llvm.cond_br %done, ^done, ^poll
  ^done:
  llvm.return
}
```

### 4.2 Falcon (v5.1) CodeGen
```mlir
// Before: orca.vector.fmx.mmacc
// After: RISC-V custom instructions
llvm.func @falcon_mmacc(...) {
  // fmx.mload v4, a0, 0
  %v4 = llvm.call @llvm.riscv.fmx.mload(%a0, %c0_i32)
    : (i64, i32) -> vector<128xi8>
  // fmx.mload v8, a1, 0
  %v8 = llvm.call @llvm.riscv.fmx.mload(%a1, %c0_i32)
    : (i64, i32) -> vector<128xi8>
  // fmx.mmacc v12, v8, v4
  %v12 = llvm.call @llvm.riscv.fmx.mmacc(%v8, %v4)
    : (vector<128xi8>, vector<128xi8>) -> vector<128xi32>
  llvm.return %v12 : vector<128xi32>
}
```

### 4.3 Phoenix (v6.x) CodeGen
```mlir
// Before: orca.tpu.wmma
// After: Custom CSR + command queue writes
llvm.func @phoenix_wmma(...) {
  // Write command to CSR 0x7C0
  %cmd = llvm.or %c0x01_i64, %tile_config
  llvm.call @llvm.riscv.csrrw(%c0x7C0, %cmd)
    : (i32, i64) -> i64
  // Submit to command FIFO
  %fifo_ptr = llvm.inttoptr %c0x70000000 : i64 to !llvm.ptr
  llvm.store %cmd, %fifo_ptr : i64, !llvm.ptr
  // Wait for completion (interrupt or poll)
  %done = llvm.call @phoenix_wait_irq() : () -> i1
  llvm.return
}
```

---

## 5. Auto-Vectorization and Tiling
### 5.1 Tiling Strategy for Convolution
```python
# Python pseudo-code for ORCA compiler tiling strategy
def tile_conv2d(input_shape, filter_shape, target):
    if target == 'kestrel':        # Simple strip-mining
        return tile_size = (1, 8, 8, 8)  # NHWC
    elif target == 'falcon':        # FMX tile-based
        return tile_size = (1, 32, 32, 32)
    elif target == 'hawk':        # 4-array parallel
        return tile_size = (1, 64, 64, 64)
    elif target in ['phoenix', 'phoenix-e', 'phoenix-plus']:        # WMMA tile-based
        return tile_size = (1, 16, 16, 16)
```

### 5.2 MLIR Pass Pipeline
```bash
# Full compilation pipeline for Phoenix+
orca-mlir-opt input.mlir  --pass-pipeline='
    canonicalize,
    orca-lower-to-npu,              # Lower to generic NPU dialect
    orca-tile-and-fuse,             # Tile and fuse loops
    orca-lower-to-tpu,              # Lower to TPE/AME ops
    orca-distribute-dies=2,         # Multi-die distribution (Phoenix+)
    convert-vector-to-llvm,         # Vector to LLVM
    convert-memref-to-llvm,         # MemRef to LLVM
    convert-func-to-llvm,           # Func to LLVM
    reconcile-unrealized-casts'  > output.ll
# LLVM code generation
llc -march=riscv64 -mcpu=phoenix-plus -O3 output.ll -o output.s
# Link with runtime
gcc -o inference output.s -lorca_phoenix_plus
```

---

## 6. PyTorch 2.0 Compile Backend
### 6.1 Registration
```python
# orca/pytorch/__init__.py
import torch
from torch._dynamo.backends.registry import register_backend
from orca.pytorch.codegen import OrcaCodegen
@register_backend
def orca(compiler_fn, example_inputs, options=None):
    target = options.get('target', 'phoenix')
    return OrcaCodegen(compiler_fn, target=target)
```

### 6.2 Usage
```python
import torch
# Compile for Phoenix+
model = torch.compile(
    my_model,
    backend='orca',
    options={'target': 'phoenix-plus', 'num_dies': 2})
# Compile for Hawk (edge)
model_edge = torch.compile(
    my_model,
    backend='orca',
    options={'target': 'hawk'})
```

---

## 7. ONNX Runtime Execution Provider
### 7.1 EP Registration
```cpp
// onnxruntime/core/providers/orca/orca_execution_provider.cc
class OrcaExecutionProvider : public IExecutionProvider {public:
  OrcaExecutionProvider(const OrcaProviderOptions& options)
    : target_(options.target) {}
  std::vector<std::unique_ptr<ComputeCapability>> GetCapability(
      const onnxruntime::GraphViewer& graph) override {
    // Partition graph into ORCA-supported subgraphs
    return PartitionGraph(graph, target_);
  }
  Status Compile(const std::vector<FusedNodeAndGraph>& fused_nodes) override {
    for (auto& node : fused_nodes) {
      auto program = LowerToOrcaMLIR(node.graph, target_);
      auto binary = CompileMLIR(program, target_);
      kernels_.push_back(std::move(binary));
    }
    return Status::OK();
  }
private:
  std::string target_;
  std::vector<std::unique_ptr<OrcaKernel>> kernels_;
};
```

---

## 8. Supported Operators by Target
| Operator | Kestrel | Falcon | Hawk | Phoenix | Phoenix-E | Phoenix+ |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| Conv2D | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DepthwiseConv | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FC / Linear | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ReLU | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ReLU6 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GELU | ❌ | ❌ | ✅ HW | ✅ HW | ✅ HW | ✅ HW |
| SiLU | ❌ | ❌ | ✅ HW | ✅ HW | ✅ HW | ✅ HW |
| Softmax | ❌ | ❌ | ✅ HW | ✅ HW | ✅ HW | ✅ HW |
| LayerNorm | ❌ | ❌ | ✅ HW | ✅ HW | ✅ HW | ✅ HW |
| MaxPool | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AvgPool | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BatchNorm | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| MatMul | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Attention (MHA) | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| SpMM (sparse) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |

---

## 9. Build Instructions
```bash
# Clone LLVM/MLIR
git clone https://github.com/llvm/llvm-project.git
cd llvm-project
git checkout release/18.x
# Apply ORCA patches (included in this repo)
git apply ../orca_ai_accelerators/patches/llvm-18-orca.patch
# Build
mkdir build && cd build
cmake -G Ninja ../llvm
  -DLLVM_ENABLE_PROJECTS='mlir;clang;lld'
  -DLLVM_TARGETS_TO_BUILD='RISCV'
  -DLLVM_ENABLE_ASSERTIONS=ON
  -DCMAKE_BUILD_TYPE=Release
ninja
# Install ORCA MLIR dialects
cd ../orca_ai_accelerators/compiler/orca-mlir
mkdir build && cd build
cmake -G Ninja ..
  -DMLIR_DIR=/path/to/llvm/build/lib/cmake/mlir
ninja sudo ninja install
```
