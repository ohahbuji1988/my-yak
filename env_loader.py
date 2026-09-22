import os
from pathlib import Path

def load_env(env_path = None):
    """
    .env 파일을 안전하게 읽어 os.environ에 적재합니다.
    (키 값을 콘솔에 노출하지 않음)
    """
    candidates = [
        Path(".env"),
        Path("../.env"),
        Path.home() / ".env"
    ]
    if env_path:
        candidates.insert(0, Path(env_path))
    
    for p in candidates:
        if p.exists() and p.is_file():
            try:
                with open(p, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            key, val = line.split("=", 1)
                            key = key.strip()
                            val = val.strip().strip("'\"")
                            if key and key not in os.environ:
                                os.environ[key] = val
                break
            except Exception:
                pass

load_env()
