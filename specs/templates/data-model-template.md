# Data Model: {FEATURE_NAME}

**Feature**: {CHANGE_ID}
**Date**: {YYYY_MM_DD}

---

# # Entity Overview

| Entity | Description | Storage |
|--------|-------------|---------|
| | | |

---

# # Entity Definitions

## # {ENTITY}

**Purpose**: {WHAT_THIS_ENTITY_REPRESENTS}

**Fields**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, NOT NULL | Unique identifier |
| created_at | TIMESTAMP | NOT NULL | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL | Last update timestamp |

**Relationships**:
- {RELATIONSHIP_DESCRIPTION}

**Indexes**:
- {INDEX_DEFINITION}

**Validation Rules**:
- {RULE}

---

# # State Diagrams

{IF_ENTITY_HAS_LIFECYCLE_STATES}

---

# # Migration Notes

{DATABASE_MIGRATION_CONSIDERATIONS}




