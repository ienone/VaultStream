from app.bot.messages import MSG_BLACKLISTED, MSG_NO_PERMISSION
from app.bot.permissions import PermissionManager


def test_empty_whitelist_denies_non_admin_user():
    manager = PermissionManager(admin_ids=set(), whitelist_ids=set(), blacklist_ids=set())

    allowed, reason = manager.check_permission(123)

    assert allowed is False
    assert reason == MSG_NO_PERMISSION


def test_empty_whitelist_allows_admin_for_normal_command():
    manager = PermissionManager(admin_ids={123}, whitelist_ids=set(), blacklist_ids=set())

    allowed, reason = manager.check_permission(123)

    assert allowed is True
    assert reason is None


def test_whitelist_allows_member_and_denies_other_user():
    manager = PermissionManager(admin_ids=set(), whitelist_ids={123}, blacklist_ids=set())

    allowed, reason = manager.check_permission(123)
    assert allowed is True
    assert reason is None

    allowed, reason = manager.check_permission(456)
    assert allowed is False
    assert reason == MSG_NO_PERMISSION


def test_blacklist_still_takes_precedence():
    manager = PermissionManager(admin_ids={123}, whitelist_ids={123}, blacklist_ids={123})

    allowed, reason = manager.check_permission(123)

    assert allowed is False
    assert reason == MSG_BLACKLISTED
