#!/usr/bin/env python3
#=============================================================================
# ORCA v6.3 ZEN++ Regression Report Generator
# File: scripts/generate_report.py
# Description: Generates HTML report from regression results
#=============================================================================

import sys
import os
import glob
import re
from datetime import datetime

def parse_log(log_file):
    """Parse simulation log for key metrics."""
    result = {
        'status': 'UNKNOWN',
        'errors': 0,
        'warnings': 0,
        'sim_time': 'N/A',
        'coverage': 'N/A'
    }

    try:
        with open(log_file, 'r') as f:
            content = f.read()

        if 'TEST PASSED' in content:
            result['status'] = 'PASS'
        elif 'TEST FAILED' in content:
            result['status'] = 'FAIL'

        # Count errors and warnings
        result['errors'] = len(re.findall(r'UVM_ERROR', content))
        result['warnings'] = len(re.findall(r'UVM_WARNING', content))

        # Extract simulation time
        time_match = re.search(r'Simulation time: ([\d.]+)s', content)
        if time_match:
            result['sim_time'] = time_match.group(1) + 's'

        # Extract coverage
        cov_match = re.search(r'Coverage: ([\d.]+)%', content)
        if cov_match:
            result['coverage'] = cov_match.group(1) + '%'

    except Exception as e:
        result['status'] = 'ERROR'
        result['errors'] = str(e)

    return result

def generate_html(regression_dir):
    """Generate HTML report."""

    tests = []
    for test_dir in sorted(glob.glob(os.path.join(regression_dir, '*'))):
        if os.path.isdir(test_dir):
            test_name = os.path.basename(test_dir)
            log_file = os.path.join(test_dir, 'sim.log')

            if os.path.exists(log_file):
                metrics = parse_log(log_file)
                tests.append({
                    'name': test_name,
                    'dir': test_dir,
                    **metrics
                })

    # Count results
    pass_count = sum(1 for t in tests if t['status'] == 'PASS')
    fail_count = sum(1 for t in tests if t['status'] == 'FAIL')
    total = len(tests)

    # Generate HTML
    html = f"""<!DOCTYPE html>
<html>
<head>
    <title>ORCA v6.3 Regression Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        .header {{ background: #2c3e50; color: white; padding: 20px; border-radius: 8px; }}
        .summary {{ display: flex; gap: 20px; margin: 20px 0; }}
        .card {{ background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); flex: 1; }}
        .pass {{ color: #27ae60; font-size: 2em; font-weight: bold; }}
        .fail {{ color: #e74c3c; font-size: 2em; font-weight: bold; }}
        .total {{ color: #3498db; font-size: 2em; font-weight: bold; }}
        table {{ width: 100%; border-collapse: collapse; margin-top: 20px; background: white; border-radius: 8px; overflow: hidden; }}
        th {{ background: #34495e; color: white; padding: 12px; text-align: left; }}
        td {{ padding: 12px; border-bottom: 1px solid #ecf0f1; }}
        tr:hover {{ background: #f8f9fa; }}
        .status-pass {{ color: #27ae60; font-weight: bold; }}
        .status-fail {{ color: #e74c3c; font-weight: bold; }}
        .timestamp {{ color: #7f8c8d; font-size: 0.9em; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>ORCA v6.3 ZEN++ Regression Report</h1>
        <p class="timestamp">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>

    <div class="summary">
        <div class="card">
            <div class="total">{total}</div>
            <div>Total Tests</div>
        </div>
        <div class="card">
            <div class="pass">{pass_count}</div>
            <div>Passed</div>
        </div>
        <div class="card">
            <div class="fail">{fail_count}</div>
            <div>Failed</div>
        </div>
    </div>

    <table>
        <tr>
            <th>Test Name</th>
            <th>Status</th>
            <th>Errors</th>
            <th>Warnings</th>
            <th>Sim Time</th>
            <th>Coverage</th>
        </tr>
"""

    for test in tests:
        status_class = 'status-pass' if test['status'] == 'PASS' else 'status-fail'
        html += f"""
        <tr>
            <td>{test['name']}</td>
            <td class="{status_class}">{test['status']}</td>
            <td>{test['errors']}</td>
            <td>{test['warnings']}</td>
            <td>{test['sim_time']}</td>
            <td>{test['coverage']}</td>
        </tr>
"""

    html += """
    </table>
</body>
</html>
"""

    report_file = os.path.join(regression_dir, 'report.html')
    with open(report_file, 'w') as f:
        f.write(html)

    print(f"Report generated: {report_file}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: generate_report.py <regression_directory>")
        sys.exit(1)

    generate_html(sys.argv[1])
