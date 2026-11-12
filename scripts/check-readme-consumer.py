"""在独立调用方中原样检查 README 的导入别名与已发布包 API 示例。"""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", action="store_true", help="发布前显式使用当前源码模块；默认验证 Mooncakes 发布包")
arguments = parser.parse_args()
readme = (ROOT / "README.md").read_text(encoding="utf-8")
dependency = re.search(r"moon add ([\w/-]+@[\d.]+)", readme)[1]
imports = re.search(r"```text\n(import \{.*?\n\})\n```", readme, re.S)[1]
examples = re.findall(r"```mbt check\n(.*?)```", readme, re.S)
if not examples:
    raise RuntimeError("README 缺少可执行 API 示例")

# 发布前使用独立 workspace，发布后默认验证真实 Mooncakes 包，避免循环发布依赖。
with tempfile.TemporaryDirectory(prefix="binschema-readme-consumer-") as directory:
    consumer = Path(directory)
    (consumer / "moon.mod").write_text(
        'name = "binschema-readme/consumer"\n'
        'supported_targets = "+wasm+wasm-gc+js+native"\n'
        f'import {{ "{dependency}", }}\n', encoding="utf-8",
    )
    # README 代码为 test 块，因此在调用方使用测试专用导入。
    (consumer / "moon.pkg").write_text(imports + ' for "test"\n', encoding="utf-8")
    (consumer / "readme_test.mbt").write_text("\n".join(examples), encoding="utf-8")
    if arguments.source:
        (consumer / "moon.work").write_text(
            f'members = [ ".", "{ROOT.as_posix()}", ]\n', encoding="utf-8",
        )
    result = subprocess.run(
        ["moon", "test", "--target", "all", "--deny-warn", "."],
        cwd=consumer, capture_output=True, encoding="utf-8", timeout=180,
    )
    if result.returncode != 0:
        raise RuntimeError(f"README 调用方复现失败:\n{result.stdout}\n{result.stderr}")
    print(result.stdout, end="")
    mode = "Source" if arguments.source else "Published"
    print(f"{mode} README consumer passed: {dependency}, {len(examples)} examples")
