# ADR 0005: Field-level observations and conservative safety gates

- Status: Accepted
- Date: 2026-08-11

## Context

OCR/vision will be imperfect, progressive screens can conflict, and wrong transfer/purification/investment advice has unequal consequences. A single scan-level confidence or silent best guess cannot express that risk.

## Decision

Store recognized values as field-level observations with confidence, source region/time, and recognizer version (when implemented). Aggregate through a scan session, reconcile separately, and accept facts only under policy or user confirmation. Recommendations declare critical facts and safety class. Missing/weak/conflicting evidence yields another-screen prompt, Hold, or Review. Transfer requires the strictest complete evidence and remains only advice until manual game action plus user confirmation.

## Consequences

The model carries more evidence and UI must expose uncertainty. Tests need adversarial confidence cases. The system is safer, debuggable, correctable, and can improve recognition without rewriting historical facts. Exact numeric thresholds remain versioned policy to validate during scanner development.
