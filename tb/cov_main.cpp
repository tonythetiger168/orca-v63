// ORCA v6.3 ZEN++ - v6.3.3
// cov_main.cpp: Verilator coverage 通用 main
// Verilator 5.006 的 --binary 產生的 main 不會自動輸出 coverage.dat,
// 故以此 main 於模擬結束時明確呼叫 VerilatedCov::write()。
// 用法: verilator --coverage --cc --exe --build --timing ... tb/cov_main.cpp \
//        -CFLAGS "-DVM_TOP_HDR=Vtb_top.h -DVM_TOP=Vtb_top"
#include "verilated.h"
#include "verilated_cov.h"

#define COV_STR_(x) #x
#define COV_STR(x) COV_STR_(x)
#include COV_STR(VM_TOP_HDR)

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_TOP> topp{new VM_TOP{contextp.get()}};

    while (!contextp->gotFinish()) {
        topp->eval();
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }

    topp->final();
    VerilatedCov::write("coverage.dat");
    return 0;
}
