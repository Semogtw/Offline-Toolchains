from __future__ import annotations
import importlib.util
from pathlib import Path
_path=Path(__file__).with_name('collect-lock-inputs.py')
_spec=importlib.util.spec_from_file_location('collect_lock_inputs_impl',_path)
_module=importlib.util.module_from_spec(_spec); assert _spec and _spec.loader; _spec.loader.exec_module(_module)
collect=_module.collect
