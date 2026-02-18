"""
枚举一致性校验脚本 — 检查前后端枚举值是否对齐。

Usage:
    python scripts/check_enum_consistency.py

Exit code:
    0 — 全部一致
    1 — 存在不一致
"""
import ast
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_MODELS = PROJECT_ROOT / "backend" / "app" / "models.py"
FRONTEND_CONTENT = PROJECT_ROOT / "frontend" / "lib" / "features" / "collection" / "models" / "content.dart"

# 需要校验的后端枚举
TARGET_ENUMS = [
    "Platform", "ContentStatus", "ReviewStatus", "LayoutType",
    "QueueItemStatus", "BilibiliContentType", "TwitterContentType",
]


def parse_python_enums(filepath: Path) -> dict[str, list[str]]:
    """从 Python 文件中提取 str Enum 的值"""
    source = filepath.read_text(encoding="utf-8")
    tree = ast.parse(source)
    enums: dict[str, list[str]] = {}

    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        # 检查是否继承 str, Enum
        base_names = []
        for base in node.bases:
            if isinstance(base, ast.Name):
                base_names.append(base.id)
            elif isinstance(base, ast.Attribute):
                base_names.append(base.attr)
        if "Enum" not in base_names:
            continue
        if node.name not in TARGET_ENUMS:
            continue

        values = []
        for item in node.body:
            if isinstance(item, ast.Assign):
                for target in item.targets:
                    if isinstance(target, ast.Name) and target.id.isupper():
                        # 提取赋值的字符串值
                        if isinstance(item.value, ast.Constant) and isinstance(item.value.value, str):
                            values.append(item.value.value)
        enums[node.name] = values

    return enums


def parse_dart_hardcoded_strings(filepath: Path) -> dict[str, set[str]]:
    """从 Dart 文件中提取硬编码的平台/状态字符串"""
    if not filepath.exists():
        return {}
    source = filepath.read_text(encoding="utf-8")
    result: dict[str, set[str]] = {}

    # 平台比较: platform.toLowerCase() == 'xxx' 或 platform == 'xxx'
    platform_pattern = re.compile(r"platform(?:\.toLowerCase\(\))?\s*==\s*'(\w+)'")
    platforms = set(platform_pattern.findall(source))
    if platforms:
        result["Platform (frontend hardcoded)"] = platforms

    # contentType 比较: contentType == 'xxx'
    ct_pattern = re.compile(r"contentType\s*==\s*'(\w+)'")
    content_types = set(ct_pattern.findall(source))
    if content_types:
        result["ContentType (frontend hardcoded)"] = content_types

    # layoutType 字符串: 'article', 'video' 等在 resolvedLayoutType 相关代码
    layout_pattern = re.compile(r"return\s+'(\w+)'\s*;")
    layouts = set(layout_pattern.findall(source))
    if layouts:
        result["LayoutType defaults (frontend)"] = layouts

    return result


def main():
    if not BACKEND_MODELS.exists():
        print(f"[ERROR] 后端模型文件不存在: {BACKEND_MODELS}")
        sys.exit(1)

    print("=" * 60)
    print("VaultStream 枚举一致性校验报告")
    print("=" * 60)

    # 解析后端枚举
    backend_enums = parse_python_enums(BACKEND_MODELS)
    print(f"\n[Backend] 后端枚举 ({BACKEND_MODELS.name}):")
    for name, values in sorted(backend_enums.items()):
        print(f"  {name}: {values}")

    # 解析前端硬编码值
    frontend_strings = parse_dart_hardcoded_strings(FRONTEND_CONTENT)
    if frontend_strings:
        print(f"\n[Frontend] 前端硬编码值 ({FRONTEND_CONTENT.name}):")
        for name, values in sorted(frontend_strings.items()):
            print(f"  {name}: {sorted(values)}")
    else:
        print(f"\n[Frontend] 前端文件不存在或无硬编码值: {FRONTEND_CONTENT}")

    # 一致性检查
    print("\n" + "=" * 60)
    print("[Check] 一致性检查")
    print("=" * 60)
    issues = []

    # 检查前端平台值 vs 后端 Platform 枚举
    # 已知别名: 'x' -> 'twitter' (x.com 是 twitter 的别名)
    KNOWN_ALIASES = {"x": "twitter"}
    backend_platforms = set(backend_enums.get("Platform", []))
    frontend_platforms = frontend_strings.get("Platform (frontend hardcoded)", set())
    if frontend_platforms:
        resolved = {KNOWN_ALIASES.get(p, p) for p in frontend_platforms}
        missing_in_backend = resolved - backend_platforms
        if missing_in_backend:
            issues.append(f"前端引用了后端不存在的平台值: {missing_in_backend}")
        # 注意: 不是所有后端值都需要在前端出现（如 universal, douyin）

    # 检查前端 contentType vs 后端已知类型
    known_content_types = set()
    for enum_name in ["BilibiliContentType", "TwitterContentType"]:
        known_content_types.update(backend_enums.get(enum_name, []))
    # 加入已知但未枚举化的类型
    known_content_types.update(["answer", "question", "pin", "column", "collection", "note"])
    frontend_ct = frontend_strings.get("ContentType (frontend hardcoded)", set())
    if frontend_ct:
        unknown_ct = frontend_ct - known_content_types
        if unknown_ct:
            issues.append(f"前端引用了未知的 content_type: {unknown_ct}")

    # 检查前端 layout 默认值 vs 后端 LayoutType
    backend_layouts = set(backend_enums.get("LayoutType", []))
    frontend_layouts = frontend_strings.get("LayoutType defaults (frontend)", set())
    if frontend_layouts:
        unknown_layouts = frontend_layouts - backend_layouts
        if unknown_layouts:
            issues.append(f"前端使用了后端不存在的 layout 值: {unknown_layouts}")

    if issues:
        print("\n[WARN] 发现不一致:")
        for issue in issues:
            print(f"  [X] {issue}")
        print(f"\n总计 {len(issues)} 个问题")
        sys.exit(1)
    else:
        print("\n[OK] 所有检查通过，前后端枚举值一致")
        sys.exit(0)


if __name__ == "__main__":
    main()
