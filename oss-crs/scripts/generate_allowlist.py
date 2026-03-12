#!/usr/bin/env python3
"""Convert slice results to AFL_LLVM_ALLOWLIST format.

AFL++ allowlist format:
- One entry per line
- Use fun: prefix for explicit function match
- Can use src: prefix for source file match (not used here)

Input: Directory containing .slicing_func_result files
Output: AFL_LLVM_ALLOWLIST content to stdout
"""

import os
import sys
from pathlib import Path


def generate_allowlist(slice_results_dir: str) -> list[str]:
    """Extract function names from slice results.

    Args:
        slice_results_dir: Directory containing .slicing_func_result files

    Returns:
        List of function names found in slice results
    """
    functions = set()

    results_path = Path(slice_results_dir)
    for result_file in results_path.glob("*.slicing_func_result"):
        with open(result_file) as f:
            for line in f:
                func = line.strip()
                if func and not func.startswith("#"):
                    functions.add(func)

    # Also check merged_slice_result.txt if it exists
    merged = results_path / "merged_slice_result.txt"
    if merged.exists():
        with open(merged) as f:
            for line in f:
                func = line.strip()
                if func and not func.startswith("#"):
                    functions.add(func)

    return sorted(functions)


def main():
    if len(sys.argv) != 2:
        print("Usage: generate_allowlist.py <slice_results_dir>", file=sys.stderr)
        sys.exit(1)

    slice_results_dir = sys.argv[1]

    if not os.path.isdir(slice_results_dir):
        print(f"ERROR: {slice_results_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    functions = generate_allowlist(slice_results_dir)

    if not functions:
        # Exit with error - slicer.sh will handle abort
        print("ERROR: No functions found in slice results", file=sys.stderr)
        sys.exit(1)

    # Output in AFL_LLVM_ALLOWLIST format
    for func in functions:
        print(f"fun:{func}")


if __name__ == "__main__":
    main()
