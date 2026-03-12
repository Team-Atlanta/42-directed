import os
import re
import sys
import logging
from pathlib import Path
from typing import TYPE_CHECKING, Protocol

from tree_sitter_languages import get_parser

if TYPE_CHECKING:
    from daemon.modules.workspace import WorkspaceManager


class WorkspaceProtocol(Protocol):
    """Protocol for workspace-like objects that provide diff and repo paths."""
    diff_path: str
    def get_focused_repo(self) -> str | None: ...


class SimpleWorkspace:
    """Minimal workspace implementation for standalone CLI use."""
    def __init__(self, diff_path: str, repo_path: str):
        self.diff_path = diff_path
        self._repo_path = repo_path

    def get_focused_repo(self) -> str | None:
        return self._repo_path


class DiffParser:
    """Parse a unified diff and map changed hunks back to the affected C/C++ functions.

    The implementation merges the most recent logic from the standalone unit‑test
    prototype into the original class‑based design so that downstream code keeps
    using the OO interface while benefiting from better hunk detection,
    pre‑processor stripping and wider language support.
    """

    ###########################################################################
    # Construction helpers
    ###########################################################################

    def __init__(self, workspace_manager: "WorkspaceManager | WorkspaceProtocol"):
        self.workspace_manager = workspace_manager
        self.diff_path = self.workspace_manager.diff_path

        focused_repo_path = self.workspace_manager.get_focused_repo()
        if not focused_repo_path:
            raise ValueError("Focused repository not found in the workspace.")
        self.source_root = Path(focused_repo_path)

        if not self.diff_path or not Path(self.diff_path).is_file():
            raise FileNotFoundError(f"Diff file '{self.diff_path}' not found or not specified.")
        if not self.source_root.exists():
            # Source directory might be generated later (e.g., checkout step).
            logging.warning(f"Source directory '{self.source_root}' not found at construction time.")

        # Tree‑sitter parser is relatively expensive; create once.
        self._c_parser = get_parser('c')

    ###########################################################################
    # Public API
    ###########################################################################

    def get_modified_functions(self, use_new_code: bool = True):
        """Return a list of (absolute_path, function_name) tuples affected by the diff."""
        hunks = self._parse_diff_hunks(use_new_code)
        if not hunks:
            logging.info("No hunks parsed from diff – returning empty list.")
            return []

        if not self.source_root.exists():
            logging.error(f"Source directory '{self.source_root}' is not accessible. Cannot locate files.")
            return []

        seen = {}
        for rel_path, start_line, end_line in hunks:
            abs_path = (self.source_root / rel_path).resolve()
            # Ensure we stay inside the repo – cheap security guard.
            try:
                if self.source_root.resolve() not in abs_path.parents:
                    logging.warning(f"Skipping path outside source root: {abs_path}")
                    continue
            except Exception as exc:
                logging.error(f"Failed path safety check for '{abs_path}': {exc}")
                continue

            if not abs_path.is_file():
                logging.warning(f"Changed file not found: {abs_path}")
                continue

            if not self._is_source_file(abs_path):
                logging.debug(f"Skipping non‑source file: {abs_path}")
                continue

            for func in self._find_functions_in_range(abs_path, start_line, end_line):
                seen[(str(abs_path), func)] = None  # dict preserves insertion order since Py3.7

        logging.info("Found %d unique modified functions.", len(seen))
        return list(seen.keys())

    ###########################################################################
    # Internal helpers – diff parsing
    ###########################################################################

    def _parse_diff_hunks(self, use_new_code: bool):
        """Read the unified diff and produce (file, start_line, end_line) tuples."""
        hunks = []
        current_file = None
        try:
            with open(self.diff_path, 'r', encoding='utf‑8', errors='ignore') as fp:
                lines = fp.readlines()
        except Exception as exc:
            logging.error("Failed to read diff '%s': %s", self.diff_path, exc)
            return hunks

        for line in lines:
            # A new git hunk header resets the file until we see +++ / ---
            if line.startswith('diff --git'):
                current_file = None
                continue

            if line.startswith('--- '):
                # Prefer the *old* path (a/..). Only used when !use_new_code
                match = re.match(r'^---\s+a/(.+)', line)
                if match:
                    current_file = match.group(1).strip()
                else:
                    # Fallback absolute or other prefixes
                    match = re.match(r'^---\s+(.+)', line)
                    if match:
                        current_file = match.group(1).strip()
                continue

            if line.startswith('+++ '):
                # Prefer the *new* path (b/..). Used when use_new_code
                match = re.match(r'^\+\+\+\s+b/(.+)', line)
                if match:
                    current_file = match.group(1).strip()
                else:
                    match = re.match(r'^\+\+\+\s+(.+)', line)
                    if match:
                        current_file = match.group(1).strip()
                continue

            if line.startswith('@@') and current_file:
                old_match = re.search(r'-(\d+)(?:,(\d+))?', line)
                new_match = re.search(r'\+(\d+)(?:,(\d+))?', line)

                # Decide which half of the hunk to use.
                match = new_match if use_new_code else old_match
                if not match:
                    # If one side is missing (file addition/deletion), fall back.
                    match = new_match or old_match
                if not match:
                    continue  # malformed

                start_line = int(match.group(1))
                line_count = int(match.group(2) or 1)
                if line_count == 0:
                    # Represent zero‑length range as a single marker line.
                    end_line = start_line
                else:
                    end_line = start_line + line_count - 1

                hunks.append((current_file, start_line, end_line))

        return hunks

    ###########################################################################
    # Internal helpers – function discovery
    ###########################################################################

    @staticmethod
    def _strip_macros(source: str) -> str:
        """Comment‑out pre‑processor directives so tree‑sitter can parse more reliably."""
        cleaned = []
        for line in source.splitlines():
            if line.lstrip().startswith('#'):
                cleaned.append('// ' + line)
            else:
                cleaned.append(line)
        return '\n'.join(cleaned)

    @staticmethod
    def _is_source_file(path: Path) -> bool:
        return path.suffix.lower() in {'.c', '.cc', '.cpp', '.h', '.hpp', '.in'}

    def _extract_functions_with_line_numbers(self, source_code: str):
        """Return list[(name, start_line, end_line)] using a cached C parser."""
        try:
            tree = self._c_parser.parse(source_code.encode('utf‑8', 'ignore'))
        except Exception as exc:
            logging.error("Tree‑sitter parse failure: %s", exc)
            return []

        root = tree.root_node
        out = []

        def walk(node):
            if node.type == 'function_definition':
                # The declarator chain may be nested: declarator → (pointer_)declarator → identifier
                declarator = node.child_by_field_name('declarator')
                func_name_node = None
                current = declarator
                while current and not func_name_node:
                    if current.type == 'identifier':
                        func_name_node = current
                        break
                    nxt = current.child_by_field_name('declarator')
                    current = nxt
                if func_name_node:
                    try:
                        name = func_name_node.text.decode('utf‑8')
                    except Exception:
                        name = '<non‑utf8>'
                    start = node.start_point[0] + 1
                    end = node.end_point[0] + 1
                    out.append((name, start, end))
            for child in node.children:
                walk(child)

        walk(root)
        return out

    def _find_functions_in_range(self, source_path: Path, start_line: int, end_line: int):
        """Return list[str] of functions whose range overlaps [start_line, end_line]."""
        try:
            code = source_path.read_text(encoding='utf‑8', errors='ignore')
        except Exception as exc:
            logging.error("Cannot read source file '%s': %s", source_path, exc)
            return []

        code = self._strip_macros(code)
        funcs = self._extract_functions_with_line_numbers(code)
        matches = {
            name for name, s, e in funcs
            if not (end_line < s or e < start_line)
        }
        return list(matches)


###############################################################################
# CLI entry point for standalone use (e.g., in Docker containers)
###############################################################################

def main():
    """CLI entry point: parse diff files and output 'path function_name' lines.

    Usage:
        python diff_parser.py <diff_path_or_dir> <src_root>

    Arguments:
        diff_path_or_dir  Single .diff/.patch file OR directory containing them
        src_root          Root directory of the source code
    """
    if len(sys.argv) != 3:
        print("Usage: diff_parser.py <diff_path_or_dir> <src_root>", file=sys.stderr)
        sys.exit(1)

    diff_input = Path(sys.argv[1])
    src_root = sys.argv[2]

    if not diff_input.exists():
        print(f"Error: diff path does not exist: {diff_input}", file=sys.stderr)
        sys.exit(1)

    if not Path(src_root).is_dir():
        print(f"Error: src_root is not a directory: {src_root}", file=sys.stderr)
        sys.exit(1)

    # Collect diff files
    if diff_input.is_dir():
        diff_files = list(diff_input.glob('*.diff')) + list(diff_input.glob('*.patch'))
        if not diff_files:
            print(f"Warning: No .diff or .patch files found in {diff_input}", file=sys.stderr)
            return
    else:
        diff_files = [diff_input]

    # Process each diff file and collect unique (path, function) pairs
    seen = {}
    for diff_file in diff_files:
        try:
            workspace = SimpleWorkspace(str(diff_file), src_root)
            parser = DiffParser(workspace)
            for abs_path, func_name in parser.get_modified_functions():
                # Convert absolute path to relative for slice target format
                try:
                    rel_path = Path(abs_path).relative_to(src_root)
                except ValueError:
                    rel_path = Path(abs_path)
                seen[(str(rel_path), func_name)] = None
        except FileNotFoundError as e:
            print(f"Warning: {e}", file=sys.stderr)
            continue
        except ValueError as e:
            print(f"Warning: {e}", file=sys.stderr)
            continue

    # Output in slice target format: "path function_name"
    for (rel_path, func_name) in seen.keys():
        print(f"{rel_path} {func_name}")


if __name__ == "__main__":
    main()