import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from check_architecture import scan, cycles


class BoundaryCheckTest(unittest.TestCase):
    def test_semantic_ownership_exposes_previously_unknown_adapters(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'tool').mkdir()
            folder = root / 'lib/src/feature/application'
            folder.mkdir(parents=True)
            (folder / 'use_case.dart').write_text("import '../../hidden.dart';", encoding='utf-8')
            (root / 'lib/src/hidden.dart').write_text('class Hidden {}', encoding='utf-8')
            (root / 'tool/architecture_ownership.json').write_text(json.dumps({'files': {
                'lib/src/hidden.dart': {'layer': 'infrastructure', 'reason': 'Concrete adapter.'}
            }}), encoding='utf-8')
            _, edges = scan(root, semantic=True)
            self.assertEqual([e['rule'] for e in edges], ['application-outward'])
            (root / 'lib/src/new.dart').write_text('', encoding='utf-8')
            _, edges = scan(root, semantic=True)
            self.assertIn('unclassified-module', [e['rule'] for e in edges])

    def test_cycles_include_exports_and_do_not_report_dag_nodes(self):
        self.assertEqual(cycles([
            {'file': 'lib/a.dart', 'dependencies': ['lib/b.dart']},
            {'file': 'lib/b.dart', 'dependencies': ['lib/a.dart']},
            {'file': 'lib/c.dart', 'dependencies': ['lib/a.dart']},
        ]), [['lib/a.dart', 'lib/b.dart']])

    def test_export_barrel_and_raw_operations_cannot_hide_storage(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / 'lib/src'
            folder.mkdir(parents=True)
            (folder / 'models.dart').write_text("export 'store_service.dart';", encoding='utf-8')
            (folder / 'store_service.dart').write_text('class Store {}', encoding='utf-8')
            (folder / 'sample_page.dart').write_text(
                "import 'models.dart';\nvoid save(Store store) { store.writeState('key', {}); }",
                encoding='utf-8')
            _, edges = scan(root)
            self.assertEqual({v['rule'] for v in edges}, {
                'presentation-infrastructure-export', 'presentation-raw-operation'})

    def test_native_calls_in_widgets_are_checked_without_filename_conventions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / 'lib/src'
            folder.mkdir(parents=True)
            (folder / 'custom.dart').write_text(
                "class Custom extends StatelessWidget { void run() { const MethodChannel('test'); } }",
                encoding='utf-8')
            _, edges = scan(root)
            self.assertEqual([v['rule'] for v in edges], ['presentation-raw-operation'])

    def test_presentation_cannot_construct_through_composition_root(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / 'lib/src/example/presentation'
            folder.mkdir(parents=True)
            (folder / 'page.dart').write_text(
                "import '../../bootstrap/app_composition.dart';", encoding='utf-8')
            _, edges = scan(root)
            self.assertEqual([v['rule'] for v in edges], ['presentation-composition'])

    def test_relative_package_and_conditional_imports_are_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / "lib/src/example/domain"
            folder.mkdir(parents=True)
            (folder / "model.dart").write_text(
                "// import 'dart:io';\n"
                "export 'package:multiplexr/src/core/platform/platform_transport.dart';\n"
                "import 'safe.dart' if (dart.library.io) 'dart:io';\n",
                encoding="utf-8",
            )
            _, edges = scan(root)
            self.assertEqual({v['target'] for v in edges}, {
                'lib/src/core/platform/platform_transport.dart', 'dart:io'})

    def test_presenters_cannot_reintroduce_bootstrap_fallbacks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'tool').mkdir()
            (root / 'lib/src/bootstrap').mkdir(parents=True)
            (root / 'lib/src/bootstrap/assembly.dart').write_text('class Assembly {}', encoding='utf-8')
            (root / 'lib/src/controller.dart').write_text("import 'bootstrap/assembly.dart';", encoding='utf-8')
            (root / 'tool/architecture_ownership.json').write_text(json.dumps({'files': {
                'lib/src/controller.dart': {'layer': 'presenter', 'reason': 'Observable UI owner.'},
                'lib/src/bootstrap/assembly.dart': {'layer': 'composition', 'reason': 'Adapter assembly.'}
            }}), encoding='utf-8')
            _, edges = scan(root, semantic=True)
            self.assertIn('nonroot-composition', [e['rule'] for e in edges])

    def test_new_edge_fails_and_baseline_edge_reports(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'tool').mkdir()
            folder = root / 'lib/src/example/domain'
            folder.mkdir(parents=True)
            file = folder / 'model.dart'
            file.write_text("import 'dart:io';", encoding='utf-8')
            script = str(Path(__file__).with_name('check_architecture.py'))
            command = [sys.executable, script, '--root', temp]
            self.assertEqual(subprocess.run(command + ['--write-baseline'], capture_output=True).returncode, 0)
            file.write_text("import 'dart:io';\nimport 'package:flutter/material.dart';", encoding='utf-8')
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)
            file.write_text('', encoding='utf-8')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn('1 resolved', result.stdout)


if __name__ == '__main__':
    unittest.main()
