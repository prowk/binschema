"""复现 README 中的 Native 示例与 CLI 文件读写入口。"""

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def run(package, *arguments):
    result = subprocess.run(
        ["moon", "run", "--target", "native", "--release", "--deny-warn",
         package, "--", *map(str, arguments)],
        cwd=ROOT, capture_output=True, encoding="utf-8", timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"命令失败: {result.args}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def require(text, expected):
    if expected not in text:
        raise AssertionError(f"缺少预期输出 {expected!r}:\n{text}")


def main():
    output = run("examples/custom_packet")
    for expected in ("encoded: 42 53 01 e5 8e 26 07 00",
                     "stream_id: 624485", "trace fields: 4"):
        require(output, expected)
    output = run("examples/demo_protocol")
    for expected in ("messages: 3", "roundtrip bytes: 24", "trace fields: 23"):
        require(output, expected)
    output = run("examples/tcp_framing/app", "demo")
    for expected in ("scenario=normal", "scenario=fragmented", "scenario=coalesced",
                     "backpressure queue full", "ChecksumMismatch", "LimitExceeded",
                     "idle timeout", "all scenarios passed"):
        require(output, expected)
    print("Native examples: custom_packet, demo_protocol, TCP demo passed")

    # 临时目录与中文文件名同时验证真实文件 I/O 和 Windows 路径编码。
    with tempfile.TemporaryDirectory(prefix="binschema-compat-") as directory:
        for format_name in ("png", "wav", "pcap", "bmff", "dns", "elf"):
            path = Path(directory) / f"样例.{format_name}"
            run("cmd/main", "sample", format_name, path)
            if not path.is_file() or path.stat().st_size == 0:
                raise AssertionError(f"CLI 未生成样例: {path}")
            report = json.loads(run("cmd/main", "inspect", path,
                                    "--format", format_name, "--json"))
            if report["roundtrip_equal"] is not True:
                raise AssertionError(f"CLI 往返失败: {report}")
            require(run("cmd/main", "verify", path, "--format", format_name), "验证通过")
            json.loads(run("cmd/main", "lint", format_name, "--json"))
            print(f"CLI {format_name}: sample, inspect, verify, lint passed")


if __name__ == "__main__":
    main()
