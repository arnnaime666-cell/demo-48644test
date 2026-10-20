# Week 2 — Child Profiles Extended (CHD-01..05)

**UI:** Parent signup step adds curriculum province (13) + programme type (5) per child; defaults to parent province but changeable.
**Storage:** `children.curriculum_province` independent of parent, programme_type enum (Regular, French Immersion, Francophone, IB, AP).
**Minimization:** No last name/DOB/photo/school — CHD-05 audit preserved (form + table review).
**Acceptance:** Add 3 children, edit second, remove third — dashboard shows 2 with edits; removed not bookable.
