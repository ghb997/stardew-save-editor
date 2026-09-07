"""Optional syntax scan. Requires tree-sitter==0.26.0, tree-sitter-swift==0.7.3.

This is not Swift compiler typechecking and does not execute XCTest.
"""
from pathlib import Path
import json
import re
import sys
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
errors = []
unsupported = []
files = sorted(root.rglob("*.swift"))
for path in files:
    source = path.read_bytes()
    for match in re.finditer(rb"-> sending ", source):
        unsupported.append({"file": path.relative_to(root).as_posix(),
                            "line": source[:match.start()].count(b"\n") + 1,
                            "qualifier": "sending return (requires Swift 6 compiler validation)"})
    # This grammar predates Swift 6 region-based isolation. Preserve offsets,
    # explicitly report what is skipped, and parse the remainder of each file.
    source = source.replace(b"-> sending ", b"->         ")
    tree = parser.parse(source)
    def inspect(node):
        if node.type == "ERROR" or node.is_missing:
            errors.append({"file": path.relative_to(root).as_posix(),
                           "line": node.start_point.row + 1,
                           "column": node.start_point.column + 1,
                           "kind": node.type,
                           "text": source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")[:180]})
        for child in node.children:
            inspect(child)
    inspect(tree.root_node)
result = {"method": "tree-sitter-swift syntax parsing only; not Swift typechecking or XCTest execution",
          "swift_files": len(files), "errors": errors,
          "unsupported_qualifiers_not_typechecked": unsupported}
output = root / "validation" / "swift-syntax-results.json"
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=True, indent=2))
sys.exit(bool(errors))
