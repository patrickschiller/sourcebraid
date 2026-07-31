import subprocess
import unittest
from unittest import mock

from scripts.push_with_retry import synchronize_and_push


class PushWithRetryTest(unittest.TestCase):
    @mock.patch("scripts.push_with_retry.time.sleep")
    @mock.patch("scripts.push_with_retry.subprocess.run")
    def test_retries_after_concurrent_push_rejection(self, run, sleep):
        run.side_effect = [
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 1),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0),
        ]

        synchronize_and_push("main", attempts=3, delay_seconds=0.5)

        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                ["git", "fetch", "origin", "main"],
                ["git", "rebase", "FETCH_HEAD"],
                ["git", "push", "origin", "HEAD:main"],
                ["git", "fetch", "origin", "main"],
                ["git", "rebase", "FETCH_HEAD"],
                ["git", "push", "origin", "HEAD:main"],
            ],
        )
        sleep.assert_called_once_with(0.5)

    @mock.patch("scripts.push_with_retry.time.sleep")
    @mock.patch("scripts.push_with_retry.subprocess.run")
    def test_fails_after_bounded_attempts(self, run, sleep):
        run.side_effect = [
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 1),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 1),
        ]

        with self.assertRaisesRegex(RuntimeError, "after 2 attempts"):
            synchronize_and_push("main", attempts=2, delay_seconds=0)

        sleep.assert_called_once_with(0)


if __name__ == "__main__":
    unittest.main()
