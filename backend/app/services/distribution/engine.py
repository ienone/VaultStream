"""Backward-compatible distribution engine alias."""

from app.services.distribution.service import DistributionService


class DistributionEngine(DistributionService):
    """Compatibility name for callers that still import DistributionEngine."""
