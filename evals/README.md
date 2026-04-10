# Grid Column Suggestion Evals

Evaluation suite for testing the Agentforce Grid skill's column suggestion quality.

## Criteria

Based on the Grid Column Suggestion Evals specification:

### CORE Criteria (binary FAIL)
1. **Valid references** -- no hallucinated column IDs or names
2. **No circular dependencies** -- new columns can only reference existing ones
3. **Correct column type** -- AI vs Formula vs Reference for the right reasons
4. **Relevant to user's role** -- suggestions match role context
5. **No duplication** -- don't recreate existing columns
6. **Response format matches use** -- SINGLE_SELECT for filtering, PLAIN_TEXT for content

### DIAGNOSTIC Criteria (quality signals)
1. References existing grid data
2. Correct data flow direction
3. Actionable output (not dead-end)
4. Prompt specificity
5. Single Select option quality
6. Action type appropriateness
7. Source-of-truth leverage
8. Pipeline completeness

## Test Cases

| ID | Name | Type | Tests |
|----|------|------|-------|
| 1 | Sales Rep -- Opportunity Risk | Passing | Correct AI/SINGLE_SELECT for risk assessment |
| 2 | CSM -- Check-In Email | Passing | Correct AI/PLAIN_TEXT for email generation |
| 3 | RevOps -- Data Quality Flag | Passing | Correct AI/SINGLE_SELECT for quality triage |
| 4 | Sales Rep -- Competitive Intel | Passing | Correct AI + web search, SOT awareness |
| 5 | Hallucinated Column Ref | Negative | Core #1: must not reference non-existent columns |
| 6 | Wrong Column Type | Negative | Core #3: Formula can't do multi-field reasoning |
| 7 | Circular Dependency | Negative | Core #2: can't reference future columns |
| 8 | Duplicates Existing | Negative | Core #5: Account Summary already exists |
| 9 | Irrelevant to Role | Negative | Core #4: RevOps != sales outreach |
| 10 | Wrong Response Format | Negative | Core #6: priority needs SINGLE_SELECT |
| 11 | Dead-End Output | Negative | Diagnostic: raw JSON dump adds no value |
| 12 | Ignores Available SOT | Negative | Diagnostic: should use prompt template |

## Running

Use the Anthropic skill-creator methodology:
1. Run each eval with and without the skill
2. Grade outputs against the expectations
3. Aggregate results
4. Review in the eval viewer
5. Iterate on the skill based on failures
