# SPDX-License-Identifier: MPL-2.0
"""Keep the narrowly scoped security exceptions from becoming a blanket bypass."""
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from environment import EXPECTED_CONFLICTS, patched_requirements, require_virtualenv, verify_pip_check


class EnvironmentTests(unittest.TestCase):
    def test_base_environment_is_refused(self):
        with patch("sys.prefix", "base"), patch("sys.base_prefix", "base"), self.assertRaises(RuntimeError):
            require_virtualenv()

    def test_only_the_two_upstream_pins_change(self):
        requirements = ["Pillow==12.3.0", "uv==0.12.23", "aiohttp==3.13.3",
                        'example>=1; python_version < "3.14"']
        self.assertEqual(patched_requirements(requirements),
                         ["Pillow==13.0.0", "uv==0.13.4", *requirements[2:]])

    def test_changed_missing_or_duplicate_pin_requires_review(self):
        for requirements in (["Pillow==12.3.1", "uv==0.12.23"],
                             ["Pillow==12.3.0"],
                             ["Pillow==12.3.0", "uv==0.12.23", "uv==0.12.23"]):
            with self.subTest(requirements=requirements), self.assertRaises(RuntimeError):
                patched_requirements(requirements)

    def test_only_documented_conflicts_are_accepted(self):
        output = "\n".join(EXPECTED_CONFLICTS) + "\n"
        verify_pip_check(SimpleNamespace(returncode=1, stdout=output, stderr=""))
        for result in (SimpleNamespace(returncode=1, stdout=output + "other dependency broken\n", stderr=""),
                       SimpleNamespace(returncode=1, stdout=next(iter(EXPECTED_CONFLICTS)), stderr=""),
                       SimpleNamespace(returncode=0, stdout=output, stderr=""),
                       SimpleNamespace(returncode=2, stdout=output, stderr="pip failed")):
            with self.subTest(result=result), self.assertRaises(RuntimeError):
                verify_pip_check(result)


if __name__ == "__main__":
    unittest.main()
