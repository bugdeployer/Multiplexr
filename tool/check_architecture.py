"""RX import ratchet. Existing exceptions are reported; new edges fail.

Static import/export/part check, not a complete call-graph or runtime audit.
Baseline regeneration is explicit and requires review; CI must never regenerate it.
"""
import argparse
import json
import posixpath
import re
from pathlib import Path

DIRECTIVE = re.compile(r"^\s*(?:import|export|part)\s+(?!of\b)(.*?);", re.M | re.S)
QUOTED = re.compile(r"['\"]([^'\"]+)['\"]")
BASELINE = "tool/architecture_baseline.json"
RAW_PRESENTATION_CALL = re.compile(
    r"\b(?:MethodChannel|EventChannel)\s*\(|"
    r"\.\s*(?:invokeMethod|invokeMapMethod|readState|readStates|writeState)"
    r"\s*(?:<[^;()]*>)?\s*\(")


def layer(path, ownership=None):
    if "/domain/" in path or path.startswith("lib/src/domain/"):
        return "domain"
    if "/application/" in path:
        return "application"
    if ownership and path in ownership:
        role = ownership[path]['layer']
        return role if role in {'domain', 'application', 'presentation', 'infrastructure', 'presenter', 'composition'} else 'unclassified'
    if "/presentation/" in path or path.endswith(("_page.dart", "_pages.dart")) or path in {
        "lib/src/library/catalog.dart", "lib/src/library/collection_form.dart",
        "lib/src/library/player.dart", "lib/src/shell.dart",
        "lib/src/media/audiobooks_page.dart", "lib/src/media/music_player.dart",
    }:
        return "presentation"
    if path.startswith(("lib/src/core/platform/", "lib/src/core/persistence/", "lib/src/platform/", "lib/src/persistence/")) or path.endswith(("_service.dart", "_repository.dart")):
        return "infrastructure"
    return "unclassified"


def resolve(source, uri):
    if uri.startswith("package:multiplexr/"):
        return "lib/" + uri.split("/", 1)[1]
    if ":" in uri:
        return uri
    return posixpath.normpath(posixpath.join(posixpath.dirname(source), uri))


def scan(root, semantic=False):
    violations, inventory = [], []
    ownership_file = root / 'tool/architecture_ownership.json'
    ownership = json.loads(ownership_file.read_text(encoding='utf-8'))['files'] if ownership_file.exists() else {}
    owned = lambda path: layer(path, ownership if semantic else None)
    code_by_source, exports = {}, {}
    for file in sorted((root / "lib").rglob("*.dart")):
        source = file.relative_to(root).as_posix()
        text = file.read_text(encoding="utf-8")
        line_count = len(text.splitlines())
        # Strip comments before parsing directives, preserving quoted URI strings.
        text = re.sub(r"/\*.*?\*/|//[^\n]*|(['\"])(?:\\.|(?!\1).)*?\1",
                      lambda m: m[0] if m[0].startswith(("'", '"')) else " ", text, flags=re.S)
        imports = sorted({resolve(source, q) for d in DIRECTIVE.finditer(text) for q in QUOTED.findall(d[1])})
        owner = owned(source)
        inventory.append({"file": source, "layer": layer(source, ownership), "lines": line_count, "dependencies": imports})
        if semantic and owner == 'unclassified' and ownership_file.exists():
            violations.append({'file': source, 'target': 'missing-semantic-ownership', 'rule': 'unclassified-module'})
        presentation = owner == 'presentation' or bool(re.search(
            r'\b(?:extends\s+(?:State|StatelessWidget|StatefulWidget)\b|with\s+WidgetsBindingObserver\b)', text))
        # Mask string literals: quoted example text is not an executable call.
        code = re.sub(r"(['\"])(?:\\.|(?!\1).)*?\1", "''", text, flags=re.S)
        code_by_source[source] = code
        exports[source] = {resolve(source, uri)
                           for match in re.finditer(r'^\s*export\s+(.*?);', text, re.M | re.S)
                           for uri in QUOTED.findall(match[1])}
        if presentation and RAW_PRESENTATION_CALL.search(code):
            violations.append({'file': source, 'target': 'raw-platform-or-state-call',
                               'rule': 'presentation-raw-operation'})
        for target in imports:
            rule = None
            if owner == "domain" and (
                target.startswith(("package:flutter/", "package:app_shell/", "dart:ui", "dart:io"))
                or target.startswith("lib/") and owned(target) != "domain"
            ):
                rule = "domain-outward"
            elif owner == "application" and (
                target.startswith(("package:flutter/", "dart:ui", "dart:io"))
                or target.startswith("lib/") and (
                    owned(target) in {"presentation", "infrastructure", "presenter", "composition"}
                    or semantic and owned(target) == 'unclassified')
            ):
                rule = "application-outward"
            elif (owner == "presentation" or semantic and owner != "composition") and target.startswith("lib/src/bootstrap/"):
                rule = "presentation-composition" if owner == "presentation" else "nonroot-composition"
            elif owner == "presentation" and (
                target.startswith(("dart:io", "package:http/"))
                or target.startswith("lib/") and owned(target) == "infrastructure"
            ):
                rule = "presentation-infrastructure"
            if rule:
                violations.append({"file": source, "target": target, "rule": rule})
    # Exports expose concrete adapters just as a direct import does. Follow only
    # export edges here: a presenter using a controller is not a raw dependency.
    rows = {row['file']: row for row in inventory}
    for row in inventory:
        if row['layer'] != 'presentation':
            continue
        visited = set()
        code = code_by_source[row['file']]
        row['exportedInfrastructure'] = []
        pending = [export for dependency in row['dependencies']
                   for export in exports.get(dependency, ())]
        while pending:
            target = pending.pop()
            if target in visited:
                continue
            visited.add(target)
            if owned(target) == 'infrastructure':
                row['exportedInfrastructure'].append(target)
                declarations = re.findall(r'\bclass\s+(\w+)', code_by_source.get(target, ''))
                constructs = any(re.search(r'\b' + re.escape(name) + r'\s*\(', code)
                                 for name in declarations)
                if constructs or RAW_PRESENTATION_CALL.search(code):
                    violations.append({'file': row['file'], 'target': target,
                                       'rule': 'presentation-infrastructure-export'})
            pending.extend(exports.get(target, ()))
    return inventory, violations


def cycles(inventory):
    graph = {row['file']: [d for d in row['dependencies'] if d.startswith('lib/')]
             for row in inventory}
    indices, low, pending, active, result = {}, {}, [], set(), []

    def visit(source):
        indices[source] = low[source] = len(indices)
        pending.append(source)
        active.add(source)
        for target in graph.get(source, ()):
            if target not in indices:
                visit(target)
                low[source] = min(low[source], low[target])
            elif target in active:
                low[source] = min(low[source], indices[target])
        if low[source] == indices[source]:
            component = []
            while True:
                target = pending.pop()
                active.remove(target)
                component.append(target)
                if target == source:
                    break
            if len(component) > 1 or source in graph.get(source, ()):
                result.append(sorted(component))

    for source in graph:
        if source not in indices:
            visit(source)
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--report", type=Path)
    parser.add_argument('--strict-architecture', action='store_true',
                        help='Fail on all semantic ownership edges, unclassified modules and import cycles; no baseline exemptions.')
    args = parser.parse_args()
    inventory, violations = scan(args.root)
    _, semantic_violations = scan(args.root, semantic=True)
    import_cycles = cycles(inventory)
    baseline_file = args.root / BASELINE
    if args.write_baseline:
        baseline_file.write_text(json.dumps({"version": 1, "exceptions": [
            {**v, "owner": "application boundary",
             "reason": "Existing import; migrate behind pure contracts/application ports. No new edge is allowed."}
            for v in violations]}, indent=2) + "\n", encoding="utf-8")
    baseline = json.loads(baseline_file.read_text(encoding="utf-8"))["exceptions"]
    key = lambda v: (v["file"], v["target"], v["rule"])
    allowed = {key(v) for v in baseline}
    new = [v for v in violations if key(v) not in allowed]
    # Semantic ownership is mandatory for pure roots even while the remaining
    # legacy presentation bridges are being migrated. Do not hide a new adapter
    # under an unfamiliar filename or classify it as a presenter to evade CI.
    semantic_core = [v for v in semantic_violations
                     if v['rule'] in {'application-outward', 'domain-outward', 'unclassified-module', 'nonroot-composition'}
                     and key(v) not in allowed]
    new = list({key(v): v for v in new + semantic_core}.values())
    stale = [v for v in baseline if key(v) not in {key(e) for e in violations}]
    report = {"inventory": inventory, "existingExceptions": violations, "newViolations": new, "resolvedExceptions": stale,
              'semanticViolations': semantic_violations, 'importCycles': import_cycles,
              'architectureGatePassed': not semantic_violations and not import_cycles}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Architecture: {len(inventory)} Dart files; {len(violations)} existing boundary edges; {len(new)} new; {len(stale)} resolved.")
    unclassified = sum(row['layer'] == 'unclassified' for row in inventory)
    exports = sum(bool(row.get('exportedInfrastructure')) for row in inventory)
    presenters = sum(row['layer'] == 'presenter' for row in inventory)
    print(f"Coverage: {unclassified} unclassified files; {presenters} host/presenter ownership entries; {exports} presentation files expose adapter exports.")
    print(f"Full architecture gate: {len(semantic_violations)} semantic edges; {len(import_cycles)} import cycles. Ratchet success is not gate completion.")
    for component in import_cycles:
        print('CYCLE: ' + ' -> '.join(component))
    for item in new:
        print(f"NEW {item['rule']}: {item['file']} -> {item['target']}")
    if args.strict_architecture:
        for item in semantic_violations:
            print(f"SEMANTIC {item['rule']}: {item['file']} -> {item['target']}")
    return 1 if new or import_cycles or args.strict_architecture and semantic_violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
