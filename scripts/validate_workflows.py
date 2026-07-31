from __future__ import annotations
import importlib.util
from pathlib import Path
_path=Path(__file__).with_name('validate-workflows.py')
_spec=importlib.util.spec_from_file_location('validate_workflows_impl',_path)
_module=importlib.util.module_from_spec(_spec); assert _spec and _spec.loader; _spec.loader.exec_module(_module)
validate=_module.validate
