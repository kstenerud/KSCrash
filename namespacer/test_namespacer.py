import importlib.util
import tempfile
import unittest
from pathlib import Path

import clang.cindex


NAMESPACER_DIR = Path(__file__).resolve().parent
REPO_ROOT = NAMESPACER_DIR.parent
SOURCES_DIR = REPO_ROOT / "Sources"
spec = importlib.util.spec_from_file_location("kscrash_namespacer", NAMESPACER_DIR / "namespacer.py")
namespacer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(namespacer)


class NamespacerTests(unittest.TestCase):
    def test_objective_c_header_parses_without_errors(self):
        path = SOURCES_DIR / "KSCrashRecording" / "KSCrashSessionLog.h"
        translation_unit = namespacer.get_translation_unit(
            path, include_paths=namespacer.find_include_paths(SOURCES_DIR)
        )

        errors = [
            diagnostic.spelling
            for diagnostic in translation_unit.diagnostics
            if diagnostic.severity >= clang.cindex.Diagnostic.Error
        ]
        self.assertEqual(errors, [])

    def test_collect_symbols_rejects_fatal_diagnostic(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Broken.h"
            path.write_text('#include "DefinitelyMissingKSCrashHeader.h"\nint exported_symbol;\n')

            with self.assertRaisesRegex(RuntimeError, "DefinitelyMissingKSCrashHeader.h"):
                namespacer.collect_symbols(path, include_paths=[])

    def test_changed_sources_generate_expected_symbols(self):
        include_paths = namespacer.find_include_paths(SOURCES_DIR)
        summary_path = SOURCES_DIR / "KSCrashRecording" / "KSCrashRunSummary.m"
        session_path = SOURCES_DIR / "KSCrashRecording" / "KSCrashSessionLog.h"

        summary_symbols = namespacer.collect_symbols(summary_path, include_paths=include_paths)
        session_symbols = namespacer.collect_symbols(session_path, include_paths=include_paths)

        self.assertIn("KSCrashRunSummaryOutcome", summary_symbols)
        self.assertNotIn("int64_t", session_symbols)
        self.assertNotIn("NSString", session_symbols)

    def test_generation_failure_preserves_existing_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            broken = sources / "Broken.h"
            broken.write_text('#include "DefinitelyMissingKSCrashHeader.h"\nint exported_symbol;\n')
            destination = sources / "KSCrashNamespace.h"
            destination.write_text("sentinel namespace header\n")

            with self.assertRaisesRegex(RuntimeError, "DefinitelyMissingKSCrashHeader.h"):
                namespacer.generate_header_file(sources, destination)

            self.assertEqual(destination.read_text(), "sentinel namespace header\n")


if __name__ == "__main__":
    unittest.main()
