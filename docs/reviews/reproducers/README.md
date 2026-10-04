# Native recovery bug reproducer

`HLSRecoveryCacheRegressionTests.swift` is a deliberately failing test recorded by the 4 October 2026 audit. It is preserved outside the compiled test target because the approved work excludes application fixes. It is not skipped or disabled in a claimed passing run. The observed RED result is in `tmp/recovery-audit-cache-red.log`: the native and H.264 policy entries remain after bare-video invalidation.

To reproduce, temporarily copy the Swift file into `SmartTubeIOS/Tests/SmartTubeIOSTests/`, run `just test-unit-filter HLSRecoveryCacheRegressionTests`, then remove only that copied file. Expected on baseline `bba26b388571`: one test fails with two expectations. No network or shared cache state is involved; the test uses a local real cache and real HLS policy keys.

After an approved cache fix, move the reproducer into the active test suite, adapt it to the production per-video invalidation operation, and require it to pass while preserving the unrelated video's entry.
