#!/usr/bin/env python3
"""Regression checks for committing a live preview from the settings window."""
import os
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))

try:
    import aura_glass_settings as settings
except ImportError as exc:
    print("check-apply-lifecycle: skipped (%s)" % exc)
    raise SystemExit(0)


class FakeWindow:
    """Only the observable collaborators of Window._start_apply's callback."""

    def __init__(self):
        self._repo = ROOT
        self._preview_generation = 7
        self._preview_session = "preview-1"
        self._preview_active = True
        self._preview_terminal_requested = True
        self._close_after_apply = False
        self.preview_bar_states = []
        self._apply_log = type("Log", (), {
            "get_buffer": lambda _log: type("Buffer", (), {
                "get_end_iter": lambda _buffer: None,
                "insert": lambda *_args: None,
                "create_mark": lambda *_args: None,
            })(),
            "scroll_to_mark": lambda *_args: None,
        })()
        self.reload_saw_preview_active = None
        self.finished = []
        self._preview_queue = type("Queue", (), {
            "finish": lambda _queue, generation: setattr(self, "finished_generation", generation)
        })()
        self._toasts = type("Toasts", (), {"add_toast": lambda *_args: None})()

    def _clear_preview_css(self):
        pass

    def _run_started(self, _message):
        pass

    def _run_line(self, _line):
        pass

    def _applied_message(self):
        return "Applied"

    def _reload(self):
        self.reload_saw_preview_active = self._preview_active

    def _sync_preview_bar(self):
        self.preview_bar_states.append(self._preview_active)

    def _run_finished(self, ok, message):
        self.finished.append((ok, message))

    def destroy(self):
        raise AssertionError("ordinary Apply must not close the window")


def check_successful_apply_retires_preview_before_reloading():
    """A later Apply must not inherit a preview that its first Apply committed."""
    window = FakeWindow()
    completion = []
    original_stream, original_log = settings.stream_command, settings.log_append
    settings.stream_command = lambda _argv, _line, done: completion.append(done)
    settings.log_append = lambda _view, _line: None
    try:
        settings.Window._start_apply(window, ["--accent", "teal"], 7)
        assert len(completion) == 1
        completion[0](True, "")
    finally:
        settings.stream_command, settings.log_append = original_stream, original_log

    assert window._preview_active is False
    assert window.reload_saw_preview_active is False
    assert window.preview_bar_states == [False]
    assert window._preview_terminal_requested is False
    assert window._preview_session is None
    assert window.finished == [(True, "Applied")]
    assert window.finished_generation == 7


def main():
    check_successful_apply_retires_preview_before_reloading()
    print("check-apply-lifecycle: OK")


if __name__ == "__main__":
    main()
