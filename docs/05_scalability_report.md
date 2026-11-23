# Phase 5 – Large Dataset Scalability Evaluation

## Objective
Evaluate the Google Maps Navigation database using a large dataset and observe query performance.

## Dataset
The large dataset contains 18,725,908 CSV lines, including headers, across the dataset files.

## Validation
The following tables were verified against the loaded large dataset:

| Table | Rows |
|---|---:|
| users | 800,000 |
| places | 800,853 |
| place_reviews | 1,799,990 |
| navigation_sessions | 4,000,000 |
| traffic_readings | 4,999,656 |

## Benchmark
The optimized benchmark was executed on the gmaps_large database. R01–R12 completed before the benchmark was manually interrupted.

## Observations
Selective indexed queries demonstrated low execution times. R11 (navigation_sessions) was the slowest query among the completed results, at 726.903 ms, using a sequential scan. Queries involving large tables require further optimization and evaluation.

## Limitations
The benchmark was incomplete. R13–R30 and write workloads were not completed and are not included in the measured results.

## Conclusion
The large dataset was successfully loaded and validated. Partial benchmark results provide an initial performance evaluation and identify queries requiring further investigation.
