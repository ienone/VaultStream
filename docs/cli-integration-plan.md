# VaultStream External CLI Integration Plan

This document consolidates the analysis and implementation strategies for integrating advanced patterns and features from the `xiaohongshu-cli` and `zhihu-cli` projects into VaultStream.

---

## 1. Xiaohongshu (XHS) Integration Analysis

### 1.1 Overview
`xiaohongshu-cli` (v0.6.0) provides robust API signing, anti-crawling measures (Gaussian jitter, backoff), and specialized endpoints for feed/search/user notes.

### 1.2 Comparison with Existing Implementation
| Feature | VaultStream Current | xiaohongshu-cli | Action |
|---------|---------------------|-----------------|--------|
| API Signing | Basic `xhshow.Xhshow` | `CryptoConfig` + `SessionManager` | **Upgrade** to CLI's more stable fingerprinting. |
| Note Fetching | Feed API + SSR Fallback | Same API + cleaner SSR regex | **Adopt** CLI's precise SSR regex. |
| Anti-Crawling | Basic UA | Jitter, cooldown, exp-backoff | **Adopt** CLI's resilient HTTP layer. |
| Discovery | None | Search, Homefeed, Hot categories | **Implement** as `XhsDiscoveryScraper`. |

---

## 2. Borrowable Patterns & Roadmap

### 🟢 Phase 1: Lightweight Enhancements (Ready to Apply)
- [ ] **Precise SSR `undefined` Replacement**: Replace global `.replace('undefined', 'null')` with precise regex `: undefined` -> `: ""` to avoid corrupting content body.
- [ ] **Enhanced Signing**: Implement `CryptoConfig` and `SessionManager` in `XiaohongshuAdapter` for persistent hardware fingerprints.
- [ ] **Browser Fingerprint Alignment**: Align `User-Agent` with `sec-ch-ua` headers (matching macOS Chrome 145).
- [ ] **Cookie Integrity Check**: Add `required_cookies` verification before saving (e.g., must contain `a1`, `webId`, `web_session`).

### 🟡 Phase 2: Structural Improvements (Requires Testing)
- [ ] **Resilient HTTP Client**: Introduce exponential backoff and Gaussian jitter for all adapter requests.
- [ ] **Response Cookie Auto-Merge**: Capture and write back `Set-Cookie` headers from API responses to maintain session freshness.
- [ ] **Tiered Keep-Alive**: Replace heavy Playwright loops with:
    1. Implicit renewal (via normal requests).
    2. Precise failure detection (HTTP 401/403).
    3. Lightweight API probe (only if inactive for N days).

### 🔴 Phase 3: Major Feature Expansion
- [ ] **XHS Discovery Scraper**: Implement user subscription, keyword monitoring, and category hot-lists using the CLI's specialized endpoints.

---

## 3. Zhihu Integration Analysis

### 3.1 Login Flow Optimization
- **Current Issue**: QR login is heavy and occasionally fails due to wind control.
- **CLI Pattern**: Use `POST /udid` and `GET /captcha/v2` for pre-warming, and use `0.15s` polling intervals for near-instant success detection.

### 3.2 Content Parsing Improvements
- **Question Body**: Instead of using `question.detail`, adopt the CLI pattern of fetching the *top-voted answer* as the primary body for question-type URLs.
- **Extra Metadata**: Capture `thanks_count`, `visit_count`, and `title_image` for richer discovery cards.

### 3.3 Discovery Endpoints
- **Recommendation Stream**: `GET /api/v3/feed/topstory/recommend`
- **Hot Lists**: `GET /api/v4/creators/rank/hot`

---

## 4. Implementation Status Tracker

| Task | Platform | Status | Note |
|------|----------|--------|------|
| Issue #1 (Login Status) | XHS | ✅ Done | CSS Selectors updated (March 11 Fixes) |
| Issue #2 (Cookie Refresh) | XHS | ✅ Done | `_refresh_cookie_from_settings` added |
| Precise SSR Regex | XHS | ⏳ Planned | Phase 1 task |
| HTTP QR Migration | All | ✅ Done | Implemented pure HTTP flows for XHS, Weibo, Zhihu |
| Resilient HTTP Layer | All | ⏳ Planned | Phase 2 task |
