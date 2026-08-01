# Quantitative Research And Analysis

Use this playbook for research notes, analytical reviews, methodology explanations, model discussions, and recommendations based on quantitative evidence.

## Research Standard

Frame the work around a question, hypothesis, or decision.
Do not begin with tools or methods unless the method itself is the subject.

Cover the dimensions that materially affect validity:

- data provenance and point-in-time correctness;
- population, sample construction, and coverage;
- missingness and selection mechanisms;
- feature definitions and transformations;
- benchmark and baseline choice;
- leakage and temporal consistency;
- validation design and out-of-sample behavior;
- robustness across regimes, segments, and parameter choices;
- statistical uncertainty;
- economic or financial plausibility;
- operational reproducibility and monitoring.

Do not force every dimension into every message.
Select the dimensions that can change the conclusion.

## Research Narrative

Use this default progression when a complete analytical narrative is needed:

1. State the research question and why it matters.
2. Summarize the conclusion and its confidence level.
3. Describe the data and method sufficiently for evaluation.
4. Present the strongest evidence.
5. Test alternative explanations and failure modes.
6. Explain the economic or financial interpretation.
7. State limitations and what remains unknown.
8. Recommend the next experiment or decision.

For exploratory work, distinguish promising signals from validated findings.
For production recommendations, include monitoring and failure-handling implications.

## Reviewing Another Analyst's Work

Recognize the strongest contribution specifically.
Then identify the highest-leverage validity question rather than listing every possible concern.

Ask whether:

- the evidence answers the stated question;
- results survive a simpler baseline;
- time ordering reflects information available at the decision point;
- the model may be learning data artifacts;
- parameter choices are justified or merely convenient;
- aggregate results hide important segment failures;
- the output is financially realistic;
- another analyst can reproduce the result.

Use the constructive analytical specialist playbook when turning this review into feedback.

## Quantitative Language

Prefer actual magnitudes, denominators, time periods, and confidence intervals over adjectives such as "large," "robust," or "significant."
Use "statistically significant" only for a defined statistical test.
Do not imply economic significance from statistical significance alone.

Label values as sourced, calculated, estimated, modeled, or imputed where the distinction matters.
State the as-of date and methodology version when results can change over time.

## Recommended Outputs

A short analytical update should contain the question, current result, principal caveat, and next test.

A research memo should contain an executive conclusion, methodology, evidence, validation, limitations, and recommendation.

A methodology explanation should connect each design choice to the problem it solves and the failure mode it prevents.

A research review should prioritize findings by their effect on validity and decision usefulness.
