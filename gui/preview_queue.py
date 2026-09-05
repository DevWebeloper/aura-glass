"""Serialize settings-preview subprocess lifecycle transitions.

The settings window owns subprocess creation and GTK updates.  This small,
standard-library-only class owns only ordering, so completion callbacks can be
rejected when a newer request is active.
"""


class PreviewQueue:
    """Run at most one preview, apply, or revert request at a time."""

    def __init__(self, launch):
        self._launch = launch
        self._active = None
        self._pending_preview = None
        self._terminal = None
        self._generation = 0

    def request_preview(self, argv):
        """Offer a replaceable preview unless a terminal operation owns queue."""
        if self._terminal is not None:
            return
        request = ("preview", tuple(argv))
        if self._active is None:
            self._start(request)
        else:
            self._pending_preview = request

    def request_terminal(self, kind, argv):
        """Queue one Apply or Revert, dropping previews that it supersedes."""
        if kind not in ("apply", "revert"):
            raise ValueError("terminal kind must be apply or revert")
        if self._terminal is not None:
            return
        self._pending_preview = None
        self._terminal = (kind, tuple(argv))
        if self._active is None:
            self._start_terminal()

    def finish(self, generation):
        """Release precisely the active request that issued ``generation``."""
        if self._active is None or self._active[2] != generation:
            return
        kind = self._active[0]
        self._active = None
        if kind in ("apply", "revert"):
            self._terminal = None
        if self._terminal is not None:
            self._start_terminal()
        elif self._pending_preview is not None:
            request, self._pending_preview = self._pending_preview, None
            self._start(request)

    def _start_terminal(self):
        request, self._terminal = self._terminal, None
        self._start(request)
        if self._active is not None:
            self._terminal = request

    def _start(self, request):
        self._generation += 1
        active = (request[0], request[1], self._generation)
        self._active = active
        try:
            self._launch(*active)
        except Exception:
            self.finish(active[2])
