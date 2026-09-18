#!/bin/bash
#=============================================================================
# ORCA v6.3 GitHub Push Script
#=============================================================================

set -e

REPO_URL="git@github.com:orca-semicon/orca-v63.git"
BRANCH="main"
VERSION="v6.3.0"

echo "========================================"
echo "  ORCA v6.3 GitHub Push"
echo "========================================"

if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git remote add origin $REPO_URL
fi

if ! git remote get-url origin &>/dev/null; then
    git remote add origin $REPO_URL
fi

if [ -z "$(git config user.name)" ]; then
    git config user.name "ORCA Bot"
    git config user.email "bot@orca-semicon.com"
fi

echo "Staging files..."
git add -A

if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 0
fi

echo "Committing..."
git commit -m "ORCA v6.3 ZEN++ Release $VERSION

- 32-core RISC-V CPU with 4-way SMT (128 threads)
- 12-wide dispatch / 16-wide retire
- 4 AI Accelerator Tiles (512 TOPS INT8)
- HBM3 memory (96 GB, 9.8 TB/s)
- < 50 ns CPU-AI co-processing latency
- Complete UVM testbench with C++ DPI reference model
- SystemVerilog Assertions (45+ assertions)
- CI/CD pipeline (GitHub Actions + Jenkins)
- 11 investment-grade analysis charts

Generated: $(date '+%Y-%m-%d %H:%M:%S')"

echo "Tagging release $VERSION..."
git tag -a $VERSION -m "ORCA v6.3 ZEN++ Release"

echo "Pushing to GitHub..."
git push origin $BRANCH --tags

echo "========================================"
echo "  Push Complete!"
echo "  Repository: $REPO_URL"
echo "  Branch: $BRANCH"
echo "  Tag: $VERSION"
echo "========================================"
