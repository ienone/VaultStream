from app.adapters.base import PlatformAdapter


def test_to_int_supports_platform_compact_counts():
    assert PlatformAdapter._to_int("4万") == 40_000
    assert PlatformAdapter._to_int("1.7万") == 17_000
    assert PlatformAdapter._to_int("2.5K") == 2_500
    assert PlatformAdapter._to_int("1,234") == 1_234
    assert PlatformAdapter._to_int("not-a-count") == 0
