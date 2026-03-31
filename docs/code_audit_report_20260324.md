# Code Audit Report

- Generated at: `2026-03-24 23:01:35`
- Repo root: `C:\Users\86138\Documents\coding\VaultStream`
- File filters: `exts=['.dart', '.md', '.ps1', '.py', '.sh', '.yaml', '.yml']`; `max_bytes=1500000`

## Summary

- Files scanned: **486**
- Total LOC: **97,258** (non-empty comments included)
- Code LOC (heuristic): **76,889**
- Core business LOC: **57,195**; code: **48,675**
- Duplicate clusters (heuristic): **191**; occurrences: **391**
- Markers:
  - `fallback`: 58
  - `legacy`: 4

## LOC By Area

| Area | Total LOC | Code LOC |
| --- | --- | --- |
| frontend/lib | 42,854 | 34,098 |
| backend/app | 29,695 | 23,736 |
| backend/tests | 13,631 | 10,439 |
| docs | 6,772 | 5,180 |
| scripts | 3,472 | 2,718 |
| frontend/test | 834 | 718 |

## Core Business LOC

| Area | Total LOC | Code LOC |
| --- | --- | --- |
| backend/app | 29,695 | 23,736 |
| frontend/lib | 27,500 | 24,939 |

## LOC By Extension

| Ext | Total LOC | Code LOC |
| --- | --- | --- |
| .py | 46,532 | 36,682 |
| .dart | 43,588 | 34,737 |
| .md | 7,130 | 5,466 |
| .sh | 8 | 4 |

## Top 30 Files By LOC (All)

| File | Total LOC | Code LOC | Bytes |
| --- | --- | --- | --- |
| frontend/lib/features/review/models/bot_chat.freezed.dart | 2,385 | 1,271 | 118,029 |
| docs/architecture/ROADMAP_V2.md | 1,702 | 1,361 | 62,423 |
| frontend/lib/features/dashboard/models/stats.freezed.dart | 1,687 | 847 | 55,544 |
| frontend/lib/features/discovery/models/discovery_models.freezed.dart | 1,529 | 816 | 78,941 |
| frontend/lib/features/collection/models/content.freezed.dart | 1,307 | 731 | 83,287 |
| frontend/lib/features/review/models/distribution_target.freezed.dart | 1,186 | 622 | 54,658 |
| frontend/lib/features/settings/presentation/tabs/automation_tab.dart | 1,123 | 1,065 | 40,908 |
| frontend/lib/features/settings/presentation/tabs/push_tab.dart | 1,052 | 996 | 37,354 |
| frontend/lib/features/review/widgets/queue_content_list.dart | 949 | 872 | 31,117 |
| frontend/lib/features/review/models/distribution_rule.freezed.dart | 946 | 514 | 55,461 |
| backend/app/adapters/zhihu.py | 945 | 794 | 41,970 |
| backend/app/adapters/utils/content_agent.py | 936 | 699 | 31,888 |
| scripts/parser_test/content_agent.py | 935 | 698 | 31,783 |
| backend/tests/test_tasks/test_parsing_task.py | 933 | 708 | 35,786 |
| docs/architecture/BACKEND.md | 861 | 665 | 30,281 |
| backend/app/tasks/parsing.py | 848 | 671 | 38,048 |
| frontend/lib/features/discovery/discovery_page.dart | 841 | 776 | 31,241 |
| backend/app/routers/distribution_queue.py | 801 | 699 | 26,815 |
| frontend/lib/features/review/review_page.dart | 794 | 757 | 26,650 |
| frontend/lib/features/auth/presentation/onboarding_page.dart | 746 | 694 | 26,574 |
| frontend/lib/features/review/targets_management_page.dart | 715 | 681 | 24,287 |
| backend/app/routers/bot_management.py | 696 | 579 | 23,444 |
| backend/app/services/browser_auth_service.py | 674 | 538 | 29,711 |
| backend/app/adapters/rss.py | 646 | 558 | 24,082 |
| frontend/lib/features/review/widgets/distribution_rule_dialog.dart | 641 | 611 | 24,146 |
| frontend/lib/features/discovery/discovery_detail_page.dart | 641 | 593 | 20,918 |
| frontend/lib/features/review/models/queue_item.freezed.dart | 615 | 327 | 31,694 |
| backend/app/media/processor.py | 613 | 467 | 22,985 |
| backend/app/tasks/distribution_worker.py | 609 | 522 | 22,376 |
| backend/tests/test_text_formatters.py | 604 | 398 | 17,930 |

## Top 30 Files By LOC (Core Business)

| File | Total LOC | Code LOC | Bytes |
| --- | --- | --- | --- |
| frontend/lib/features/settings/presentation/tabs/automation_tab.dart | 1,123 | 1,065 | 40,908 |
| frontend/lib/features/settings/presentation/tabs/push_tab.dart | 1,052 | 996 | 37,354 |
| frontend/lib/features/review/widgets/queue_content_list.dart | 949 | 872 | 31,117 |
| backend/app/adapters/zhihu.py | 945 | 794 | 41,970 |
| backend/app/adapters/utils/content_agent.py | 936 | 699 | 31,888 |
| backend/app/tasks/parsing.py | 848 | 671 | 38,048 |
| frontend/lib/features/discovery/discovery_page.dart | 841 | 776 | 31,241 |
| backend/app/routers/distribution_queue.py | 801 | 699 | 26,815 |
| frontend/lib/features/review/review_page.dart | 794 | 757 | 26,650 |
| frontend/lib/features/auth/presentation/onboarding_page.dart | 746 | 694 | 26,574 |
| frontend/lib/features/review/targets_management_page.dart | 715 | 681 | 24,287 |
| backend/app/routers/bot_management.py | 696 | 579 | 23,444 |
| backend/app/services/browser_auth_service.py | 674 | 538 | 29,711 |
| backend/app/adapters/rss.py | 646 | 558 | 24,082 |
| frontend/lib/features/review/widgets/distribution_rule_dialog.dart | 641 | 611 | 24,146 |
| frontend/lib/features/discovery/discovery_detail_page.dart | 641 | 593 | 20,918 |
| backend/app/media/processor.py | 613 | 467 | 22,985 |
| backend/app/tasks/distribution_worker.py | 609 | 522 | 22,376 |
| frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart | 580 | 548 | 23,858 |
| frontend/lib/features/settings/presentation/tabs/connection_tab.dart | 577 | 550 | 19,186 |
| frontend/lib/features/collection/content_detail_page.dart | 574 | 529 | 18,886 |
| frontend/lib/features/collection/widgets/list/content_card.dart | 556 | 480 | 17,483 |
| backend/app/routers/distribution.py | 551 | 436 | 20,496 |
| backend/app/adapters/bilibili_parser/dynamic_parser.py | 498 | 379 | 20,110 |
| backend/app/services/embedding_service.py | 474 | 397 | 16,504 |
| backend/app/adapters/xiaohongshu_parser/note_parser.py | 474 | 365 | 16,713 |
| backend/app/adapters/discovery/rss.py | 448 | 374 | 17,269 |
| backend/app/routers/bot_config.py | 444 | 380 | 16,709 |
| backend/app/routers/discovery.py | 436 | 362 | 15,401 |
| backend/app/routers/contents.py | 427 | 381 | 15,420 |

## Potential Dead/Legacy/Fallback Markers (Heuristic)

| Kind | Location | Text |
| --- | --- | --- |
| fallback | backend/app/adapters/bilibili_parser/base.py:312 | # 兜底：当作普通文本 |
| fallback | backend/app/adapters/bilibili_parser/dynamic_parser.py:195 | # 4) 兜底：如果没有paragraphs，也尽量从可能存在的字段拿到文本 |
| fallback | backend/app/adapters/bilibili_parser/dynamic_parser.py:414 | title = raw_title if raw_title else generate_title_from_text(summary, max_len=60, fallback="B站动态") |
| fallback | backend/app/adapters/favorites/zhihu_fetcher.py:53 | fallback = "https://www.zhihu.com/" |
| fallback | backend/app/adapters/favorites/zhihu_fetcher.py:55 | return fallback |
| fallback | backend/app/adapters/favorites/zhihu_fetcher.py:60 | return fallback |
| fallback | backend/app/adapters/favorites/zhihu_fetcher.py:65 | return fallback |
| fallback | backend/app/adapters/favorites/zhihu_fetcher.py:72 | return fallback |
| fallback | backend/app/adapters/favorites/zhihu_fetcher.py:84 | return fallback |
| fallback | backend/app/adapters/twitter.py:337 | title=generate_title_from_text(text, max_len=60, fallback=f"@{screen_name or 'unknown'} 的推文"), |
| fallback | backend/app/adapters/utils/content_agent.py:62 | # Generic fallback |
| fallback | backend/app/adapters/utils/content_agent.py:75 | Returns OG metadata, auto-detected CSS selector, DOM/image summaries (for LLM fallback). |
| fallback | backend/app/adapters/utils/content_agent.py:121 | logger.debug("no known selector matched, fallback to LLM targeting") |
| fallback | backend/app/adapters/utils/content_agent.py:267 | logger.warning("conversion failed ({}), fallback to body text", e) |
| fallback | backend/app/adapters/utils/content_agent.py:329 | # LLM: Selector Targeting (fallback when auto-detect fails) |
| fallback | backend/app/adapters/utils/content_agent.py:872 | # Selector: auto or LLM fallback |
| fallback | backend/app/adapters/utils/text_utils.py:22 | fallback: Optional[str] = None, |
| fallback | backend/app/adapters/utils/text_utils.py:33 | fallback: 无法生成时的回退值 |
| fallback | backend/app/adapters/utils/text_utils.py:50 | return fallback |
| fallback | backend/app/adapters/utils/text_utils.py:55 | return fallback |
| fallback | backend/app/adapters/utils/text_utils.py:63 | return fallback |
| fallback | backend/app/adapters/utils/text_utils.py:87 | fallback: str = "无标题" |
| fallback | backend/app/adapters/utils/text_utils.py:96 | fallback: 都无法生成时的回退值 |
| fallback | backend/app/adapters/utils/text_utils.py:118 | return fallback |
| fallback | backend/app/adapters/weibo.py:166 | # 优先使用数据库注入的 self.cookies（扫码登录），fallback 到 .env 静态配置 |
| fallback | backend/app/adapters/weibo_parser/base.py:84 | # Fallback: 从pid构建URL |
| fallback | backend/app/adapters/weibo_parser/weibo_parser.py:191 | title = generate_title_from_text(plain_text, max_len=60, fallback="微博内容") |
| fallback | backend/app/adapters/xiaohongshu_parser/note_parser.py:120 | title = ensure_title(raw_title, description, max_len=60, fallback="小红书笔记") |
| fallback | backend/app/adapters/zhihu_parser/answer_parser.py:27 | # Fallback to searching values |
| fallback | backend/app/adapters/zhihu_parser/article_parser.py:22 | # Fallback: try to find any article if ID mismatch (unlikely but possible with redirects) |
| fallback | backend/app/adapters/zhihu_parser/pin_parser.py:46 | content_html = "" # Fallback or process list if needed |
| fallback | backend/app/adapters/zhihu_parser/pin_parser.py:140 | # Fallback to HTML text extraction, trying to preserve links via Markdown conversion |
| fallback | backend/app/adapters/zhihu_parser/pin_parser.py:157 | pin_title = generate_title_from_text(description, max_len=60, fallback="知乎想法") |
| fallback | backend/app/adapters/zhihu_parser/question_parser.py:19 | # Fallback search |
| fallback | backend/app/core/llm_factory.py:64 | logger.debug("LLMFactory: TEXT_LLM_API_KEY not found, trying fallback to VISION_LLM.") |
| fallback | backend/app/media/extractor.py:52 | """Return True when the URL is the author avatar or an avatar-like fallback.""" |
| fallback | backend/app/media/extractor.py:111 | cover_url: 封面图URL（兜底） |
| fallback | backend/app/media/extractor.py:213 | # 兜底：使用封面图 |
| fallback | backend/app/services/content_presenter.py:33 | def compute_display_title(content, max_len: int = 60, fallback: str = "无标题") -> str: |
| fallback | backend/app/services/content_presenter.py:36 | return ensure_title(content.title, content.body, max_len=max_len, fallback=fallback) |
| fallback | backend/app/services/embedding_service.py:284 | logger.debug("FTS query unavailable, fallback to LIKE ranking") |
| fallback | backend/app/services/embedding_service.py:409 | logger.warning(f"Embedding remote call failed, fallback to local: {e}") |
| fallback | backend/app/services/telegram_bot_service.py:75 | # Fallback: try to get from settings synchronously |
| fallback | frontend/lib/features/collection/widgets/detail/components/rich_content.dart:102 | // For articles/questions, show media if no markdown body (fallback) or explicitly handled |
| fallback | frontend/lib/features/collection/widgets/detail/components/rich_content.dart:322 | // 兜底：从 media_urls 查找（可能因 URL 编码差异匹配失败） |
| fallback | frontend/lib/features/collection/widgets/detail/components/unified_stats.dart:339 | icon: Icons.emoji_emotions_outlined, // Fallback |
| fallback | frontend/lib/features/review/widgets/render_config_editor.dart:64 | bool _getBool(String key, [bool fallback = false]) => |
| fallback | frontend/lib/features/review/widgets/render_config_editor.dart:65 | (_structure[key] as bool?) ?? fallback; |
| fallback | frontend/lib/features/review/widgets/render_config_editor.dart:67 | String _getString(String key, [String fallback = '']) => |
| fallback | frontend/lib/features/review/widgets/render_config_editor.dart:68 | (_structure[key] as String?) ?? fallback; |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:505 | dynamic _getSettingValue(List<SystemSetting> settings, String key, dynamic fallback) { |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:509 | return fallback; |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:528 | int _parseInt(dynamic value, int fallback) { |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:531 | if (value is String) return int.tryParse(value) ?? fallback; |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:532 | return fallback; |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:535 | double _parseDouble(dynamic value, double fallback) { |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:538 | if (value is String) return double.tryParse(value) ?? fallback; |
| fallback | frontend/lib/features/settings/presentation/tabs/automation_tab.dart:539 | return fallback; |
| legacy | backend/app/adapters/universal_adapter.py:26 | """在独立进程中运行爬取（Windows 兼容）""" |
| legacy | backend/app/core/queue_adapter.py:73 | """从队列取出任务（CAS 原子性获取，兼容 SQLite）""" |
| legacy | backend/app/services/browser_auth_service.py:494 | # 兼容 success=True 和 success=1 两种形式 |
| legacy | backend/app/services/settings_service.py:19 | """Backwards-compatible secret extraction helper for tests and legacy callers.""" |

## Duplicate Code Clusters (Heuristic)

### Cluster 1

- Hash: `945e3a76b332bc357b0105ae764ce3855b2b3dcb`
- Occurrences: **4** (window=10)
  - `frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart:431`
  - `frontend/lib/features/review/widgets/bot_chat_dialog.dart:243`
  - `frontend/lib/features/review/widgets/distribution_rule_dialog.dart:402`
  - `frontend/lib/features/review/widgets/render_config_editor.dart:259`

### Cluster 2

- Hash: `a11f09bd38cb187e12464f674da5ff6fe7e8f05b`
- Occurrences: **3** (window=10)
  - `backend/app/adapters/bilibili_parser/article_parser.py:59`
  - `backend/app/adapters/bilibili_parser/bangumi_parser.py:63`
  - `backend/app/adapters/bilibili_parser/live_parser.py:62`

### Cluster 3

- Hash: `99ae9bb480f719f5d05f02af10079ec1da91c56d`
- Occurrences: **3** (window=10)
  - `backend/app/adapters/bilibili_parser/article_parser.py:60`
  - `backend/app/adapters/bilibili_parser/bangumi_parser.py:64`
  - `backend/app/adapters/bilibili_parser/live_parser.py:63`

### Cluster 4

- Hash: `f41d44e48cf8a2fe9a5bb4a2d1b28984ccfb0b5e`
- Occurrences: **3** (window=10)
  - `frontend/lib/features/review/widgets/bot_chat_dialog.dart:239`
  - `frontend/lib/features/review/widgets/distribution_rule_dialog.dart:398`
  - `frontend/lib/features/review/widgets/render_config_editor.dart:255`

### Cluster 5

- Hash: `e3472be64c8a8f0087b78d46b0406e81fc12f10b`
- Occurrences: **3** (window=10)
  - `frontend/lib/features/review/widgets/bot_chat_dialog.dart:240`
  - `frontend/lib/features/review/widgets/distribution_rule_dialog.dart:399`
  - `frontend/lib/features/review/widgets/render_config_editor.dart:256`

### Cluster 6

- Hash: `8bb5478feaa4a08b027e5588306b4c9c09002aa1`
- Occurrences: **3** (window=10)
  - `frontend/lib/features/review/widgets/bot_chat_dialog.dart:241`
  - `frontend/lib/features/review/widgets/distribution_rule_dialog.dart:400`
  - `frontend/lib/features/review/widgets/render_config_editor.dart:257`

### Cluster 7

- Hash: `701a2392ead542aa4ea651f5ce86def2ce127345`
- Occurrences: **3** (window=10)
  - `frontend/lib/features/review/widgets/bot_chat_dialog.dart:242`
  - `frontend/lib/features/review/widgets/distribution_rule_dialog.dart:401`
  - `frontend/lib/features/review/widgets/render_config_editor.dart:258`

### Cluster 8

- Hash: `723c08cbe3973544b0b37687699485f9f5224ae2`
- Occurrences: **3** (window=10)
  - `frontend/lib/features/review/widgets/bot_chat_dialog.dart:244`
  - `frontend/lib/features/review/widgets/distribution_rule_dialog.dart:403`
  - `frontend/lib/features/review/widgets/render_config_editor.dart:260`

### Cluster 9

- Hash: `3f17bd5c965e1177a3a76b1946602c3d737626f4`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:278`
  - `backend/app/adapters/rss.py:372`

### Cluster 10

- Hash: `b265869759474fdfdf8011e3c64df26b7bb9c177`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:279`
  - `backend/app/adapters/rss.py:373`

### Cluster 11

- Hash: `106c0c9b56b3fb1307983badcf9c4caf768593c6`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:280`
  - `backend/app/adapters/rss.py:374`

### Cluster 12

- Hash: `805c9c964e93dd874f1ca601235836040fcd93f9`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:281`
  - `backend/app/adapters/rss.py:375`

### Cluster 13

- Hash: `c410a7cfe4a2ae0e789483115497e12aff6b616a`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:283`
  - `backend/app/adapters/rss.py:377`

### Cluster 14

- Hash: `3fa868a14596e4305c9add109347018d90d4eb66`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:284`
  - `backend/app/adapters/rss.py:378`

### Cluster 15

- Hash: `f9aa887fde4f98b6ac45f8da31cd1d9f2574fbb0`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:328`
  - `backend/app/adapters/rss.py:471`

### Cluster 16

- Hash: `6d8e2e795cb370a07ebfa1a8718f1243cd57d14a`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:329`
  - `backend/app/adapters/rss.py:472`

### Cluster 17

- Hash: `eedffeb11110f2215de963dab5bd87908fe4af72`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:330`
  - `backend/app/adapters/rss.py:473`

### Cluster 18

- Hash: `e27037abaeb1df6fab644941d5a5786840b7defc`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:331`
  - `backend/app/adapters/rss.py:474`

### Cluster 19

- Hash: `a98eb7c41bd62cd60ad6204bc04cbcc450287026`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:332`
  - `backend/app/adapters/rss.py:475`

### Cluster 20

- Hash: `e9e059b9bb46346b87c6f0319188e55f1e378f09`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:333`
  - `backend/app/adapters/rss.py:476`

### Cluster 21

- Hash: `2fb9616b637e245335c077ea2efab3bf14235ef7`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:334`
  - `backend/app/adapters/rss.py:477`

### Cluster 22

- Hash: `ae52a37ec8cdfd237d38dfb824509858a1f1fb25`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:335`
  - `backend/app/adapters/rss.py:478`

### Cluster 23

- Hash: `da5a9d6535ecec1fa5f1ee49e66d635bf91ef705`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:337`
  - `backend/app/adapters/rss.py:480`

### Cluster 24

- Hash: `8ddf187a438a9e4f39fd64f057e07a6405c3e268`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:338`
  - `backend/app/adapters/rss.py:481`

### Cluster 25

- Hash: `b71d4321aa433d08065a6fc55fbe9ea2b0a15c67`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:339`
  - `backend/app/adapters/rss.py:482`

### Cluster 26

- Hash: `41c0a53e5cecc686ee1b1d7202acb1c3789374a3`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:340`
  - `backend/app/adapters/rss.py:483`

### Cluster 27

- Hash: `46b158543b941ccc5d2d475d7d53d39158de2f34`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:341`
  - `backend/app/adapters/rss.py:484`

### Cluster 28

- Hash: `85cfd15cf478d7ce5691581c61d9faaf2f86d4b7`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:342`
  - `backend/app/adapters/rss.py:485`

### Cluster 29

- Hash: `d09f4a870c393cacbdabec65ee9404033e59d527`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:343`
  - `backend/app/adapters/rss.py:486`

### Cluster 30

- Hash: `be0e42ccbb4a64565504dd58b5ca15f3d0f971cb`
- Occurrences: **2** (window=10)
  - `backend/app/adapters/discovery/rss.py:344`
  - `backend/app/adapters/rss.py:487`

*Truncated: showing 30/191 clusters.*

## Candidate Hand-Rolled Utilities (Heuristic)

This section only flags *candidates* based on keyword scans; validate before refactoring.

- **retry/backoff**: 58 files
  - `backend/app/adapters/errors.py`
  - `backend/app/adapters/favorites/xiaohongshu_fetcher.py`
  - `backend/app/adapters/favorites/zhihu_fetcher.py`
  - `backend/app/adapters/utils/__init__.py`
  - `backend/app/adapters/utils/anti_risk.py`
  - `backend/app/adapters/utils/tiered_fetcher.py`
  - `backend/app/core/events.py`
  - `backend/app/core/queue_adapter.py`
  - `backend/app/media/processor.py`
  - `backend/app/routers/contents.py`
  - `backend/app/routers/distribution_queue.py`
  - `backend/app/services/browser_auth_service.py`
  - `backend/app/services/telegram_bot_service.py`
  - `backend/app/tasks/discovery_cleanup.py`
  - `backend/app/tasks/discovery_sync.py`
  - `backend/app/tasks/distribution_worker.py`
  - `backend/app/tasks/favorites_sync.py`
  - `backend/app/tasks/maintenance.py`
  - `backend/app/tasks/parsing.py`
  - `backend/app/tasks/runner.py`
  - *(truncated)*
- **caching/LRU**: 25 files
  - `backend/app/adapters/zhihu.py`
  - `backend/app/core/db_adapter.py`
  - `backend/app/routers/events.py`
  - `backend/app/routers/media.py`
  - `backend/app/services/settings_service.py`
  - `backend/app/tasks/favorites_sync.py`
  - `backend/tests/test_repositories_deep.py`
  - `backend/tests/test_settings_service.py`
  - `frontend/lib/core/network/sse_service.dart`
  - `frontend/lib/features/collection/widgets/detail/components/author_header.dart`
  - `frontend/lib/features/collection/widgets/detail/components/media_gallery_item.dart`
  - `frontend/lib/features/collection/widgets/detail/components/media_grid.dart`
  - `frontend/lib/features/collection/widgets/detail/components/rich_content.dart`
  - `frontend/lib/features/collection/widgets/detail/components/zhihu_top_answers.dart`
  - `frontend/lib/features/collection/widgets/detail/gallery/full_screen_gallery.dart`
  - `frontend/lib/features/collection/widgets/detail/layout/gallery_landscape_layout.dart`
  - `frontend/lib/features/collection/widgets/detail/layout/user_profile_layout.dart`
  - `frontend/lib/features/collection/widgets/detail/layout/video_landscape_layout.dart`
  - `frontend/lib/features/collection/widgets/list/content_card.dart`
  - `frontend/lib/features/collection/widgets/renderers/payload_block_renderer.dart`
  - *(truncated)*
- **singleton/global**: 3 files
  - `backend/app/services/settings_service.py`
  - `backend/tests/test_tasks/test_distribution_task.py`
  - `scripts/code_audit_report.py`
- **custom json**: 70 files
  - `backend/app/adapters/favorites/twitter_fetcher.py`
  - `backend/app/adapters/utils/content_agent.py`
  - `backend/app/adapters/xiaohongshu_parser/note_parser.py`
  - `backend/app/adapters/zhihu_parser/base.py`
  - `backend/app/core/events.py`
  - `backend/app/routers/agent.py`
  - `backend/app/routers/events.py`
  - `backend/app/schemas/content.py`
  - `backend/app/services/background_task_leader.py`
  - `backend/app/services/browser_auth_service.py`
  - `backend/app/services/patrol_service.py`
  - `backend/app/tasks/favorites_sync.py`
  - `backend/app/tasks/parsing.py`
  - `backend/tests/test_adapters/test_content_agent_full.py`
  - `backend/tests/test_adapters/test_web_request.py`
  - `backend/tests/test_patrol_service.py`
  - `frontend/lib/features/collection/models/content.dart`
  - `frontend/lib/features/collection/models/content.freezed.dart`
  - `frontend/lib/features/collection/models/content.g.dart`
  - `frontend/lib/features/collection/providers/collection_provider.dart`
  - *(truncated)*
- **custom datetime parsing**: 2 files
  - `backend/app/adapters/twitter.py`
  - `backend/app/adapters/weibo_parser/weibo_parser.py`

## Suggested Next Pass (Manual)

- Pick top duplicate clusters and decide whether to extract shared helpers.
- For `fallback/legacy/deprecated` markers, confirm which branches are still needed (by logs/metrics/tests).
- For hand-rolled utilities, decide if replacing with stdlib or a mature lib is worth it (cost vs stability).
