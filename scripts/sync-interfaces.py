"""补齐 moon info 当前不会写回的单后端包接口。先运行 moon info --target all。"""

import os
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent

for directory, children, files in os.walk(ROOT):
    children[:] = [name for name in children if not name.startswith((".", "_"))
                   and name != "target"]
    if "moon.pkg" not in files:
        continue
    package = Path(directory)
    match = re.search(r'^supported_targets\s*=\s*"(native|wasm-gc|wasm|js)"',
                      (package / "moon.pkg").read_text(encoding="utf-8"), re.M)
    if match is None:
        continue
    backend = match[1]
    module = package
    while not (module / "moon.mod").is_file():
        if module == ROOT:
            raise RuntimeError(f"找不到模块清单: {package}")
        module = module.parent
    module_name = re.search(r'^name\s*=\s*"([^"]+)"',
                            (module / "moon.mod").read_text(encoding="utf-8"), re.M)[1]
    relative = package.relative_to(module)
    generated = (ROOT / "_build" / backend / "debug" / "check"
                 / module_name / relative / f"{package.name}.mbti")
    # 模块首选后端不在包支持范围时，使用已生成的对应后端接口。
    content = generated.read_text(encoding="utf-8")
    with (package / "pkg.generated.mbti").open("w", encoding="utf-8", newline="\n") as output:
        output.write(content)
