import requests

url = "https://mapp.api.weibo.cn/fx/493bfdaf31cffc58f0ddcb59738cf77c.html"
headers = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
}

print(f"Original URL: {url}")

try:
    # 1. Try HEAD with redirects
    resp = requests.head(url, headers=headers, allow_redirects=True, timeout=10)
    print(f"HEAD Final URL: {resp.url}")
    print(f"HEAD History: {[r.url for r in resp.history]}")

    # 2. Try GET with redirects
    resp_get = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
    print(f"GET Final URL: {resp_get.url}")
    
    # Check for canonical link in HTML
    if "text/html" in resp_get.headers.get("Content-Type", ""):
        print("Searching for canonical or mblogid in body...")
        import re
        match_id = re.search(r'"id":\s*(\d+)', resp_get.text)
        match_mblogid = re.search(r'"mblogid":\s*"([a-zA-Z0-9]+)"', resp_get.text)
        match_bid = re.search(r'bid=([a-zA-Z0-9]+)', resp_get.text)
        
        if match_id:
            print(f"Found ID in body: {match_id.group(1)}")
        if match_mblogid:
            print(f"Found mblogid in body: {match_mblogid.group(1)}")
        if match_bid:
             print(f"Found bid in body: {match_bid.group(1)}")

except Exception as e:
    print(f"Error: {e}")
