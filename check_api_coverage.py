import os
import re
from fastapi.routing import APIRoute

# Boot up the app to get all routes
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), 'backend')))
from app.main import app

# 1. Get all API endpoints
all_endpoints = set()
for route in app.routes:
    if isinstance(route, APIRoute):
        if not route.path.startswith("/api/v1"):
            continue
        for method in route.methods:
            # We skip OPTIONS etc
            if method in ["GET", "POST", "PUT", "PATCH", "DELETE"]:
                path = route.path.replace("/api/v1", "")
                all_endpoints.add(f"{method} {path}")


# 2. Get tested endpoints
def extract_tested_endpoints(test_dir):
    tested = set()
    for root, _, files in os.walk(test_dir):
        for file in files:
            if not file.endswith(".py"):
                continue
            try:
                with open(os.path.join(root, file), 'r', encoding='utf-8') as f:
                    content = f.read()
                    # Extremely naive matching of requests
                    matches = re.findall(r'client\.(get|post|put|patch|delete)\(\s*[bf]?"/api/v1([^"\?]+)', content, re.IGNORECASE)
                    for method, path in matches:
                        # Normalize path: replace digits or UUID-like strings with {var}
                        # This matches both {id} from route and actual 123 from test
                        norm_path = re.sub(r'/[0-9a-f\-]{8,}|/\d+', '/{var}', path)
                        norm_path = re.sub(r'\{[^\}]+\}', '{var}', norm_path)
                        tested.add(f"{method.upper()} {norm_path}")
            except UnicodeDecodeError:
                print(f"Skipping file due to encoding error: {file}")
                continue
    return tested

tested_endpoints = extract_tested_endpoints("backend/tests/test_api")

# normalize all_endpoints for comparison
normalized_all = {}
for e in all_endpoints:
    method, path = e.split(" ", 1)
    norm_path = re.sub(r'\{[^\}]+\}', '{var}', path)
    normalized_all[f"{method} {norm_path}"] = e

missing = []
for norm_e, real_e in normalized_all.items():
    if norm_e not in tested_endpoints:
        missing.append(real_e)

print(f"Total Routes: {len(all_endpoints)}")
print(f"Missing Coverage Routes: {len(missing)}\n")
for m in sorted(missing):
    print(m)
