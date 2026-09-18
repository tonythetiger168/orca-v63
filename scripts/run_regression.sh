#!/bin/bash
#=============================================================================
# ORCA v6.3 ZEN++ Regression Test Suite Runner
# File: scripts/run_regression.sh
# Description: Automated regression with multiple test configurations
#=============================================================================

set -e

OUT_DIR="build/regression"
SIMV="build/vcs/simv"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REGRESSION_DIR="${OUT_DIR}/${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test list: (test_name, seed, description)
declare -a TESTS=(
    "orca_cpu_alu_test:42:ALU Random Instruction Test"
    "orca_cpu_smt_test:123:SMT-4 Stress Test"
    "orca_cpu_exception_test:99:Exception Handling Test"
    "orca_cpu_flush_test:7:ROB Flush + Freelist Recovery Test (v6.3.3)"
    "orca_cpu_lsu_stress_test:555:LSU 4-Lane Stress Test (v6.3.3)"
    "orca_cpu_mul_vec_test:314:MUL/VEC/Crypto Operand Path Test (v6.3.3)"
    "orca_cpu_aix_test:77:AIX CPU-AI Co-simulation Test"
    "orca_cpu_regression_test:0:Full Regression Suite"
)

mkdir -p ${REGRESSION_DIR}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ORCA v6.3 Regression Suite${NC}"
echo -e "${GREEN}  Timestamp: ${TIMESTAMP}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

for test_entry in "${TESTS[@]}"; do
    IFS=':' read -r TEST_NAME SEED DESC <<< "$test_entry"

    TEST_DIR="${REGRESSION_DIR}/${TEST_NAME}"
    mkdir -p ${TEST_DIR}

    echo -e "${BLUE}[RUN]${NC} ${DESC}"
    echo -e "      Test: ${TEST_NAME} | Seed: ${SEED}"

    # Run simulation
    ${SIMV} \
        +UVM_TESTNAME=${TEST_NAME} \
        +ntb_random_seed=${SEED} \
        +UVM_VERBOSITY=UVM_LOW \
        -l ${TEST_DIR}/sim.log \
        +vpdfile+${TEST_DIR}/waves.vpd \
        2>&1 | tee ${TEST_DIR}/run.log

    SIM_EXIT=${PIPESTATUS[0]}

    # Check result
    if grep -q "TEST PASSED" ${TEST_DIR}/sim.log; then
        echo -e "${GREEN}[PASS]${NC} ${DESC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL]${NC} ${DESC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""
done

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Regression Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "  Total Tests:  $((PASS_COUNT + FAIL_COUNT))"
echo -e "  ${GREEN}Passed:${NC}  ${PASS_COUNT}"
echo -e "  ${RED}Failed:${NC}  ${FAIL_COUNT}"
echo ""
echo -e "  Results: ${REGRESSION_DIR}"
echo -e "${GREEN}========================================${NC}"

# Generate HTML report
python3 scripts/generate_report.py ${REGRESSION_DIR}

if [ ${FAIL_COUNT} -gt 0 ]; then
    exit 1
fi
