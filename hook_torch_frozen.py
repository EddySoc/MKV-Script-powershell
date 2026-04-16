"""
PyInstaller runtime hook - patches inspect.getsource so torch.distributed.config
can initialize in a frozen (PyInstaller) exe without raising OSError.
"""
import inspect as _inspect

_orig_getsource = _inspect.getsource

def _safe_getsource(object):
    try:
        return _orig_getsource(object)
    except OSError:
        return ""

_inspect.getsource = _safe_getsource
