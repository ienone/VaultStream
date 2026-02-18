"""
Export OpenAPI schema from FastAPI app.

Usage:
    cd backend && python ../scripts/export_openapi.py
    或: python scripts/export_openapi.py
"""
import json
import sys
from pathlib import Path

# 确保 backend 目录在 sys.path
backend_dir = Path(__file__).resolve().parent.parent / "backend"
sys.path.insert(0, str(backend_dir))

def main():
    try:
        from app.main import app
    except Exception as e:
        print(f"❌ 无法导入 FastAPI app: {e}")
        print("   请确保在项目根目录运行，且 backend 依赖已安装")
        sys.exit(1)

    schema = app.openapi()
    output_path = Path(__file__).resolve().parent.parent / "docs" / "openapi.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(schema, f, indent=2, ensure_ascii=False)

    endpoint_count = sum(
        len(methods) for methods in schema.get("paths", {}).values()
    )
    schema_count = len(schema.get("components", {}).get("schemas", {}))

    print(f"✅ OpenAPI schema 已导出: {output_path}")
    print(f"   endpoints: {endpoint_count}, schemas: {schema_count}")
    print(f"   版本: {schema.get('info', {}).get('version', 'unknown')}")


if __name__ == "__main__":
    main()
