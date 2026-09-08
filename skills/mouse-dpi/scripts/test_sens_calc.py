#!/usr/bin/env python3
"""Offline solver regressions: python -m unittest discover -s this-directory."""
import subprocess
import sys
import unittest

import sens_calc


class SolverTests(unittest.TestCase):
    def test_cli_rejects_target_slower_than_minecraft_minimum(self):
        result = subprocess.run(
            [sys.executable, sens_calc.__file__, "--dpi", "800", "--game",
             "minecraft", "--target-cm360", "200"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("VERDICT: SET", result.stdout)
        self.assertIn("no positive setting reaches", result.stderr)

    def test_custom_formula_cannot_silently_return_an_unsolved_target(self):
        # 914.4 / (914.4 * (s + 1)) is at most 1 for nonnegative s.
        with self.assertRaises(SystemExit):
            sens_calc.solve_setting(lambda s: s + 1, 914.4, 2)

    def test_minecraft_minimum_setting_remains_reachable(self):
        formula = sens_calc.FORMULAS["minecraft"][0]
        target = sens_calc.cm360(800, formula(0))
        rc, output = sens_calc.run_capture(
            ["--dpi", "800", "--game", "minecraft",
             "--target-cm360", str(target)]
        )
        self.assertEqual(rc, 0)
        self.assertIn("VERDICT: SET s = 0 ", output)

    def test_custom_zero_endpoints_remain_reachable(self):
        for expression, target in (("s + 0.001", "1000"), ("1000*s + 1", "1")):
            with self.subTest(expression=expression):
                rc, output = sens_calc.run_capture(
                    ["--dpi", "914.4", "--formula", expression,
                     "--target-cm360", target]
                )
                self.assertEqual(rc, 0)
                self.assertIn("VERDICT: SET s = 0 ", output)

    def test_formula_undefined_at_zero_can_still_solve_positive_settings(self):
        formula, *_ = sens_calc.make_formula(None, "math.log(s)", None)
        setting = sens_calc.solve_setting(formula, 914.4, 1)
        self.assertAlmostEqual(sens_calc.cm360(914.4, formula(setting)), 1)

    def test_reachable_linear_and_nonlinear_targets_round_trip(self):
        for game in ("source", "minecraft"):
            with self.subTest(game=game):
                formula = sens_calc.FORMULAS[game][0]
                setting = sens_calc.solve_setting(formula, 800, 30)
                self.assertAlmostEqual(sens_calc.cm360(800, formula(setting)), 30)


if __name__ == "__main__":
    unittest.main()
