#!/usr/bin/env python3
"""Parse unified diff files and identify affected functions using tree-sitter.

Output format: path function_name (one per line)
This matches the slice target file format expected by the LLVM analyzer.

Usage:
    parse_diff.py <diff_dir> <src_root>

Arguments:
    diff_dir    Directory containing .diff or .patch files
    src_root    Root directory of the source code to analyze
"""

import os
import sys
from pathlib import Path
from typing import Iterator, Set, Tuple

from unidiff import PatchSet
import tree_sitter_c as tsc
from tree_sitter import Language, Parser


# Supported C/C++ file extensions
C_EXTENSIONS = {'.c', '.h'}
CPP_EXTENSIONS = {'.cc', '.cpp', '.cxx', '.hpp', '.hxx', '.C', '.H'}
ALL_EXTENSIONS = C_EXTENSIONS | CPP_EXTENSIONS


def get_c_parser() -> Parser:
    """Create a tree-sitter parser for C code."""
    parser = Parser(Language(tsc.language()))
    return parser


def find_function_at_line(parser: Parser, source_code: bytes, line_number: int) -> str | None:
    """Find the function name that contains the given line number.

    Args:
        parser: tree-sitter parser
        source_code: Source file content as bytes
        line_number: 1-indexed line number to search for

    Returns:
        Function name if found, None otherwise
    """
    tree = parser.parse(source_code)

    # Convert to 0-indexed for tree-sitter
    target_line = line_number - 1

    def find_function_node(node) -> str | None:
        """Recursively search for function containing target line."""
        # Check if this is a function definition
        if node.type == 'function_definition':
            start_line = node.start_point[0]
            end_line = node.end_point[0]

            if start_line <= target_line <= end_line:
                # Find the declarator to get the function name
                for child in node.children:
                    if child.type == 'function_declarator':
                        # Get the identifier (function name)
                        for subchild in child.children:
                            if subchild.type == 'identifier':
                                return subchild.text.decode('utf-8')
                        # Handle pointer declarators
                        for subchild in child.children:
                            if subchild.type == 'pointer_declarator':
                                for ptr_child in subchild.children:
                                    if ptr_child.type == 'function_declarator':
                                        for fc_child in ptr_child.children:
                                            if fc_child.type == 'identifier':
                                                return fc_child.text.decode('utf-8')
                    # Handle direct declarator with function pointer syntax
                    if child.type == 'declarator':
                        return extract_function_name(child)

        # Recurse into children
        for child in node.children:
            result = find_function_node(child)
            if result:
                return result

        return None

    return find_function_node(tree.root_node)


def extract_function_name(node) -> str | None:
    """Extract function name from a declarator node."""
    if node.type == 'identifier':
        return node.text.decode('utf-8')

    for child in node.children:
        if child.type == 'identifier':
            return child.text.decode('utf-8')
        result = extract_function_name(child)
        if result:
            return result

    return None


def get_changed_lines(patch_file) -> dict[str, Set[int]]:
    """Extract changed line numbers from a patch file.

    Args:
        patch_file: unidiff PatchedFile object

    Returns:
        Dict mapping file paths to sets of changed line numbers (1-indexed)
    """
    changed_lines: dict[str, Set[int]] = {}

    for patched_file in patch_file:
        # Get the target file path (after the patch)
        # Remove leading 'b/' if present (common in git diffs)
        path = patched_file.target_file
        if path.startswith('b/'):
            path = path[2:]

        # Skip deleted files
        if patched_file.is_removed_file:
            continue

        lines = set()
        for hunk in patched_file:
            for line in hunk:
                # We care about added and modified lines (target side)
                if line.is_added:
                    lines.add(line.target_line_no)

        if lines:
            changed_lines[path] = lines

    return changed_lines


def parse_diff_to_functions(diff_dir: str, src_root: str) -> list[Tuple[str, str]]:
    """Parse diff files and identify affected functions.

    Args:
        diff_dir: Directory containing .diff or .patch files
        src_root: Root directory of the source code

    Returns:
        List of (path, function_name) tuples
    """
    diff_path = Path(diff_dir)
    src_path = Path(src_root)

    # Find all diff files
    diff_files = list(diff_path.glob('*.diff')) + list(diff_path.glob('*.patch'))

    if not diff_files:
        print(f"Warning: No .diff or .patch files found in {diff_dir}", file=sys.stderr)
        return []

    # Collect all changed lines across all diffs
    all_changed_lines: dict[str, Set[int]] = {}

    for diff_file in diff_files:
        try:
            with open(diff_file, 'r', encoding='utf-8', errors='replace') as f:
                patch = PatchSet(f.read())

            for file_path, lines in get_changed_lines(patch).items():
                if file_path in all_changed_lines:
                    all_changed_lines[file_path].update(lines)
                else:
                    all_changed_lines[file_path] = lines

        except Exception as e:
            print(f"Warning: Failed to parse {diff_file}: {e}", file=sys.stderr)
            continue

    # Initialize parser
    parser = get_c_parser()

    # Find functions for each changed file
    results: list[Tuple[str, str]] = []
    seen_functions: Set[Tuple[str, str]] = set()

    for file_path, line_numbers in all_changed_lines.items():
        # Check file extension
        ext = Path(file_path).suffix.lower()
        if ext not in ALL_EXTENSIONS:
            continue

        # Try to find the source file
        source_file = src_path / file_path
        if not source_file.exists():
            # Try without leading directories
            for part_count in range(1, len(Path(file_path).parts)):
                alt_path = src_path / Path(*Path(file_path).parts[part_count:])
                if alt_path.exists():
                    source_file = alt_path
                    break
            else:
                print(f"Warning: Source file not found: {file_path}", file=sys.stderr)
                continue

        # Read and parse source file
        try:
            with open(source_file, 'rb') as f:
                source_code = f.read()
        except Exception as e:
            print(f"Warning: Failed to read {source_file}: {e}", file=sys.stderr)
            continue

        # Find functions for each changed line
        for line_no in sorted(line_numbers):
            func_name = find_function_at_line(parser, source_code, line_no)
            if func_name:
                key = (file_path, func_name)
                if key not in seen_functions:
                    seen_functions.add(key)
                    results.append(key)

    return results


def main():
    """Main entry point."""
    if len(sys.argv) != 3:
        print("Usage: parse_diff.py <diff_dir> <src_root>", file=sys.stderr)
        sys.exit(1)

    diff_dir = sys.argv[1]
    src_root = sys.argv[2]

    if not os.path.isdir(diff_dir):
        print(f"Error: diff_dir is not a directory: {diff_dir}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isdir(src_root):
        print(f"Error: src_root is not a directory: {src_root}", file=sys.stderr)
        sys.exit(1)

    functions = parse_diff_to_functions(diff_dir, src_root)

    for path, func_name in functions:
        print(f"{path} {func_name}")


if __name__ == "__main__":
    main()
