"""
In-process access to the Rust core engine (``phlio_native``).

``phlio_native`` is the PyO3 build of ``phlio_core`` (see
``phlio_core/crates/native``). Importing it once and calling functions
directly is ~3000x cheaper than spawning the ``phlio-core`` CLI per call
(measured: ~0.5 µs vs ~1.5 ms for ``generate_id``), and it also gives the
API a fast, bounded brute-force guard (``Throttle``).

Resolution order, so the backend runs everywhere:

1. ``phlio_native`` on ``sys.path`` (Docker image, or ``maturin develop``).
2. A freshly built ``libphlio_native.so`` / ``phlio_native.pyd`` under
   ``phlio_core/target/release-native`` (a contributor ran
   ``cargo build --profile release-native -p phlio-native --features extension-module``).
3. ``None`` — callers fall back to the CLI and then to pure Python.

Set ``PHLIO_NATIVE=0`` to force the fallback (useful when bisecting a bug).
"""

from __future__ import annotations

import importlib
import importlib.machinery
import importlib.util
import logging
import os
import sys
from pathlib import Path
from types import ModuleType

logger = logging.getLogger("phlio.core_engine")

#: Functions the backend relies on; an older build missing any is ignored.
REQUIRED = ("generate_id", "sign", "verify", "constant_time_eq", "sha256_hex",
            "totp_matching_step", "score_risk", "Throttle")


def _from_build_dir() -> ModuleType | None:
    root = Path(__file__).resolve().parents[4] / "phlio_core" / "target" / "release-native"
    names = ("libphlio_native.so", "libphlio_native.dylib", "phlio_native.dll")
    for name in names:
        path = root / name
        if path.is_file():
            loader = importlib.machinery.ExtensionFileLoader("phlio_native", str(path))
            spec = importlib.util.spec_from_file_location("phlio_native", path, loader=loader)
            if spec is None:
                continue
            module = importlib.util.module_from_spec(spec)
            loader.exec_module(module)
            sys.modules["phlio_native"] = module
            return module
    return None


def _load() -> ModuleType | None:
    if os.environ.get("PHLIO_NATIVE", "1").strip().lower() in ("0", "false", "off", "no"):
        logger.info("phlio_native disabled by PHLIO_NATIVE=0")
        return None
    module: ModuleType | None = None
    try:
        module = importlib.import_module("phlio_native")
    except ImportError:
        try:
            module = _from_build_dir()
        except (ImportError, OSError) as exc:  # wrong platform/ABI, corrupt file
            logger.warning("phlio_native build found but not loadable: %s", exc)
    if module is None:
        return None
    missing = [name for name in REQUIRED if not hasattr(module, name)]
    if missing:
        logger.warning("phlio_native %s is missing %s — ignoring it",
                       getattr(module, "__version__", "?"), ", ".join(missing))
        return None
    logger.info("phlio_native %s loaded (in-process Rust core engine)", module.__version__)
    return module


#: The loaded module, or ``None`` when unavailable.
native: ModuleType | None = _load()
