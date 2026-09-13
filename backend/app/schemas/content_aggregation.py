"""Bounded, source-linked output for the automatic content workflow."""
from pydantic import BaseModel, ConfigDict, Field, model_validator


class AggregationEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    content_id: int = Field(gt=0)
    quote: str = Field(min_length=8, max_length=300)


class AggregationClaim(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    text: str = Field(min_length=1, max_length=600)
    evidence: list[AggregationEvidence] = Field(min_length=1, max_length=5)


class AggregationGroup(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    event_id: int | None = Field(default=None, gt=0)
    title: str = Field(min_length=1, max_length=200)
    source_ids: list[int] = Field(min_length=2, max_length=30)
    claims: list[AggregationClaim] = Field(min_length=1, max_length=10)
    tags: list[str] = Field(max_length=5)

    @model_validator(mode="after")
    def validate_evidence(self):
        ids = set(self.source_ids)
        if len(ids) != len(self.source_ids):
            raise ValueError("duplicate aggregation sources")
        cited = {entry.content_id for claim in self.claims for entry in claim.evidence}
        if cited != ids:
            raise ValueError("all group sources must be cited, without external references")
        if any(not tag.strip() or len(tag) > 50 for tag in self.tags):
            raise ValueError("invalid aggregation tag")
        return self


class AggregationOutput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    groups: list[AggregationGroup] = Field(max_length=10)

    @model_validator(mode="after")
    def validate_groups(self):
        event_ids = [group.event_id for group in self.groups if group.event_id is not None]
        if len(event_ids) != len(set(event_ids)):
            raise ValueError("an existing event can be updated once per batch")
        ids = [source for group in self.groups for source in group.source_ids]
        if len(ids) != len(set(ids)):
            raise ValueError("one source cannot be assigned to multiple events in a batch")
        return self
