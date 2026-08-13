# Changelog

All notable changes to Dowser land here. Format loosely follows Keep a Changelog. Dates ISO-8601.

## [2026.08.13.224] - 2026-08-13
### test(json-repair): Cover stale root-array repair output

What changed:
- Add a repair test that replaces a valid JSONL output with a stale root array, reruns repair, and verifies normalized JSONL plus source triage.

Why:
- This recreates the exact three-file failure reported from the transcript inventory.


## [2026.08.13.223] - 2026-08-13
### fix(json-repair): Rewrite stale array-shaped repair output

What changed:
- Treat an existing repair output as reusable only when it is valid JSON or JSONL in the expected single-document or JSONL form.
- Rewrite an existing root-array output from the preserved original, then triage that original after validation.

Why:
- Three prior repaired files retained their outer array despite a JSONL filename, so the originals could not safely be triaged.


## [2026.08.13.222] - 2026-08-13
### test(json-repair): Classify sequence fixture before source triage

What changed:
- Run the pretty-printed JSON sequence classification assertion before repair moves the source into JSON-Triage.

Why:
- The new workflow deliberately removes malformed input from its original location after producing a valid copy.


## [2026.08.13.221] - 2026-08-13
### test(json-repair): Classify array fixture before source triage

What changed:
- Run the outer-array classification assertion before repair moves the malformed array export into JSON-Triage.

Why:
- The source path is intentionally absent after successful repair and triage.


## [2026.08.13.220] - 2026-08-13
### test(json-repair): Cover cleanup of existing repaired copies

What changed:
- Add a test that restores a malformed source after its first repair, then verifies a second run triages it without rewriting the valid repaired copy.

Why:
- The operator needs a safe rerun to clean the original malformed files already paired with repaired copies.


## [2026.08.13.219] - 2026-08-13
### test(json-repair): Classify fragment fixture before source triage

What changed:
- Run the unstructured-fragment diagnosis before Repair-DowserJson moves the malformed fixture to JSON-Triage.

Why:
- This preserves the intended classification assertion under the new source-separation workflow.


## [2026.08.13.218] - 2026-08-13
### test(json-repair): Classify bracketed fixture before source triage

What changed:
- Run the bracket-led source diagnosis before Repair-DowserJson moves the source into JSON-Triage.

Why:
- Repair now intentionally removes malformed originals from the active fixture path after successful output validation.


## [2026.08.13.217] - 2026-08-13
### test(json-repair): Verify parallel repair triages original sources

What changed:
- Assert that each parallel repair reports SourceMoved and produces a triage copy.
- Restore isolated test fixtures from JSON-Triage before later repair cases.

Why:
- The test suite must verify the new source-separation contract without contaminating subsequent cases.


## [2026.08.13.216] - 2026-08-13
### fix(json-repair): Move repaired sources into JSON-Triage

What changed:
- Validate each repaired copy before moving its malformed source into a sibling JSON-Triage directory.
- On rerun, validate an existing repaired copy and triage its lingering source without rewriting it.
- Return OutputPath, TriagePath, and SourceMoved so triage state is visible.

Why:
- Keeps malformed originals separate from valid inputs while preserving both the original and its parseable repaired copy.


## [2026.08.13.215] - 2026-08-13
### fix(json-repair): Assign a triage destination for each repair task

What changed:
- Each repair task now carries a sibling JSON-Triage destination that preserves the original filename.

Why:
- Successful repairs need a recoverable original copy outside the active input corpus.


## [2026.08.13.214] - 2026-08-13
### fix(json-repair): Exclude repaired and triaged directories from repeat scans

What changed:
- Directory repair enumeration now excludes JSON-Repaired and JSON-Triage children.

Why:
- A rerun must process only the active source corpus, not repaired output or already-triaged originals.


## [2026.08.13.213] - 2026-08-13
### fix(json-repair): Document triage movement after successful repair

What changed:
- Updated Repair-DowserJson help to state that malformed sources move into JSON-Triage after their repaired copy validates.

Why:
- The repair workflow must leave the active corpus free of known malformed source files.


## [2026.08.13.212] - 2026-08-13
### fix(json-assessment): Prevent exports from reusing stale validation rows

What changed:
- Cleared prior validation state before each assessment scan.
- Suppress report writes when the requested path has no parseable JSON files.

Why:
- A missing input directory previously produced CSV output containing rows from an earlier unrelated assessment.


## [2026.08.13.211] - 2026-08-13
### test(json-repair): Cover bracket-led source text

What changed:
- Added a regression fixture for bracket-led code and verifies it is preserved as complete structured source text.

Why:
- Real transcript fragments beginning with [area] were misclassified as supported role-tag transcripts.


## [2026.08.13.210] - 2026-08-13
### test(json-repair): Cover leading blank lines in formatted exports

What changed:
- Updated the RECORD banner fixture to begin with a blank line before the first banner.

Why:
- The reported formatted export begins this way and must not leave a separator in parsed JSON.


## [2026.08.13.209] - 2026-08-13
### fix(json-repair): Restrict tagged transcript classification to supported roles

What changed:
- Classify tagged transcript text only when the first nonblank line is USER, ASSISTANT, or SYSTEM, the three roles the writer supports.

Why:
- Bracketed code such as [area] was incorrectly routed to the tagged-transcript writer and produced no records.


## [2026.08.13.208] - 2026-08-13
### fix(json-repair): Find RECORD headers after leading text

What changed:
- Changed RECORD banner repair to locate validated banner triples instead of discarding the first three physical lines.

Why:
- Formatted exports can begin with a blank line, which previously left a separator in the first JSON record.


## [2026.08.13.207] - 2026-08-13
### test(json-repair): Isolate parallel repair fixture outputs

What changed:
- Removed temporary parallel-test outputs after the assertion so later single-file tests keep their original no-output precondition.

Why:
- The new multi-worker test intentionally writes the same temporary fixture destinations used by later tests.


## [2026.08.13.206] - 2026-08-13
### test(json-repair): Cover multi-worker JSON repair

What changed:
- Added a repair test that dispatches three independent inputs through three bounded workers and verifies every repaired copy exists.

Why:
- The new repair pool needs a direct regression test rather than relying on single-file repair tests.


## [2026.08.13.205] - 2026-08-13
### perf(json-repair): Run JSON repair through bounded worker pool

What changed:
- Replaced sequential diagnose and repair processing with bounded queue-driven workers.
- Kept original files read-only, retained structured per-file results, and protected same-output writes.
- Changed confirmation to one batch-level operation so parallel workers cannot prompt from background runspaces.

Why:
- The previous one-file-at-a-time loop makes a 9,000-file transcript repair batch take far longer than necessary.


## [2026.08.13.204] - 2026-08-13
### perf(json-repair): Add ThreadCount to repair command

What changed:
- Added a validated ThreadCount parameter to Repair-DowserJson with a processor-bounded default.

Why:
- Large repair batches need bounded parallelism that operators can tune.


## [2026.08.13.203] - 2026-08-13
### perf(json-repair): Document bounded repair worker count

What changed:
- Documented the ThreadCount control for Repair-DowserJson.

Why:
- Operators need a visible way to tune a large repair batch without changing code.


## [2026.08.13.202] - 2026-08-13
### perf(json-repair): Add structured JSON repair worker

What changed:
- Added a queue-driven repair worker that diagnoses one file, protects colliding output paths, and returns a result for every file.
- Worker reports progress and diagnostics only through synchronized queues.

Why:
- Repairing thousands of transcript files needs bounded parallel work without racing writes or losing failure details.


## [2026.08.13.201] - 2026-08-13
### perf(json-repair): Route repair directory logging through worker queue

What changed:
- Routed output-directory creation logging through the synchronized queue when repair runs in a worker.

Why:
- The worker must not directly write to the shared logger.


## [2026.08.13.200] - 2026-08-13
### perf(json-repair): Queue repair worker logs through synchronized state

What changed:
- Added an optional synchronized log queue to Write-DowserJsonRepair so workers do not write directly to the host logger.

Why:
- Parallel repair workers need one safe main-thread logging path.


## [2026.08.12.199] - 2026-08-12
### docs(json-repair): document loss-preserving fragment repair behavior

What changed:
- Updated Repair-DowserJson help to state that tagged blocks are role-aware records and unstructured fragments retain their complete original text in provenance-bearing JSONL.

Why:
- The former help incorrectly said malformed or tagged content remained unchanged, even though the repairer now preserves it in separate parseable output files.


## [2026.08.12.198] - 2026-08-12
### fix(json-repair): preserve every unstructured transcript fragment as JSONL

What changed:
- Made NonJsonText and JsonSyntaxError candidates repairable by wrapping complete source text in a provenance-bearing JSONL record.
- Retained tagged-block conversion for transcripts with explicit roles.
- Relaxed RECORD banner handling so an equals-sign line is treated as content unless it is a complete verified banner.
- Added a no-text-loss regression test for untagged fragments.

Why:
- Bulk repair revealed important split transcript fragments without role markers. Skipping them would lose ingestible source material.


## [2026.08.12.197] - 2026-08-12
### test(json-repair): verify multi-block tagged transcripts produce JSONL

What changed:
- Changed the tagged-transcript fixture to include user and assistant blocks.
- Asserted two separate JSONL records, roles, and preserved block content.

Why:
- A single repaired block is valid JSON but cannot demonstrate the one-record-per-line JSONL contract.


## [2026.08.12.196] - 2026-08-12
### feat(json-repair): prepare structured conversion for tagged transcript text

What changed:
- Classified USER, ASSISTANT, and SYSTEM tagged transcript files as repairable source-specific inputs.
- Added a conversion path that writes one JSONL record per tagged block with role, content, sequence, source path, and source format.
- Added a regression test for tagged transcript conversion.

Why:
- Tagged transcript exports are important source material and must be converted into parseable records without dropping their text or role boundaries.


## [2026.08.12.195] - 2026-08-12
### fix(json-scan): replace invalid-file warning flood with one summary

What changed:
- Stopped JSON scan workers from emitting one warning per unreadable or unparsable candidate.
- Retained each failure path and parser error in $global:DowserJsonLastParseFailures.
- Added one consolidated warning with the skipped-file count and three sample paths.

Why:
- Large mixed transcript directories contain thousands of files with JSON-like extensions but non-JSON content; per-file warnings drown out scan progress and results.


## [2026.08.12.194] - 2026-08-12
### test(json-assessment): update assessment fixture key-count expectation

What changed:
- Updated the JSON assessment test from 10 to 12 validation rows after adding the JsonSequence fixture.

Why:
- The fixture intentionally introduces two new paths, id and content, and the assessment output now correctly includes them.


## [2026.08.12.193] - 2026-08-12
### feat(json-repair): normalize multi-line JSON document sequences into JSONL

What changed:
- Added JsonSequence diagnosis for multiple root JSON documents that span physical lines.
- Made JsonSequence repairable by streaming each complete root document to one compact JSONL line.
- Added a regression fixture and test for a property line that line-oriented validators otherwise reject.
- Updated Repair-DowserJson help to describe root arrays and JSON sequences.

Why:
- The supplied Cody history file is a valid multi-document JSON stream, but it is not physical JSONL and editor validators reject property lines inside its pretty-printed records.


## [2026.08.12.192] - 2026-08-12
### fix(json-diagnosis): separate transcript prose from JSON syntax failures

What changed:
- Restricted JSON literal detection to complete true, false, and null tokens instead of any line beginning with t, f, or n.
- Classifies malformed transcript fragments with JSON-looking extensions as NonJsonText rather than JsonSyntaxError.

Why:
- Many exported Cortex transcript fragments begin with prose such as 'fer' or 'false ...'; those are not repairable JSON syntax errors.


## [2026.08.12.191] - 2026-08-12
### fix(json-diagnosis): classify root JSON arrays regardless of element count

What changed:
- Changed root-array classification to rely on the first JSON token instead of the number of top-level records counted by JsonTextReader.
- Preserved the existing conversion action that writes each root-array element as one JSONL record.

Why:
- Newtonsoft can count root-array elements as documents, which previously hid valid array-wrapped JSON from the repair command.


## [2026.08.12.190] - 2026-08-12
### fix(json): Track the first JSON token for root diagnosis

What changed:
- Added state for first-token detection in the JSON diagnosis reader.

Why:
- Reader depth is not a reliable way to distinguish a root array from its array elements.


## [2026.08.12.189] - 2026-08-12
### test(json): Update assessment fixture key count

What changed:
- Updated the full-workspace assessment fixture expectation to include the new root-array export keys.

Why:
- The root-array fixture is valid JSON and is intentionally included when the assessment test scans its shared workspace.


## [2026.08.12.188] - 2026-08-12
### test(json): Verify outer-array-only JSONL conversion

What changed:
- Added a regression test that converts a root JSON array to two JSONL records.
- Verifies nested interactions and contextFiles arrays survive the conversion unchanged.

Why:
- The repair must remove only the root brackets and preserve all internal JSON structure.


## [2026.08.12.187] - 2026-08-12
### test(json): Add nested root-array conversion fixture

What changed:
- Added a root JSON array with nested interactions and contextFiles arrays to the test workspace.

Why:
- The test must prove conversion preserves inner arrays while removing only the outer array wrapper.


## [2026.08.12.186] - 2026-08-12
### test(json): Prepare root-array JSON conversion fixture

What changed:
- Added the root-array export fixture path to the JSON repair test setup.

Why:
- Root-array conversion needs a regression test that proves only the outer delimiters are removed.


## [2026.08.12.185] - 2026-08-12
### feat(json): Convert root JSON arrays to JSONL safely

What changed:
- Added streamed OuterArrayJson conversion that reads one top-level array item at a time.
- Writes each root-array item as one JSONL line.
- Leaves every nested array and object inside each item unchanged.

Why:
- The requested repair removes only the outer document brackets without loading large files or altering internal JSON structure.


## [2026.08.12.184] - 2026-08-12
### feat(json): Classify root-array JSON as JSONL conversion input

What changed:
- Added the OuterArrayJson classification.
- Marks it repairable with the explicit action to remove only the root array wrapper and write JSONL.

Why:
- The requested conversion preserves all nested arrays and objects while removing only the document-level brackets.


## [2026.08.12.183] - 2026-08-12
### fix(json): Detect a root JSON array during streaming

What changed:
- Marks a diagnosis as root-array input only when its first top-level token is StartArray.

Why:
- Only the document-level array brackets may be removed during conversion; nested arrays must remain intact.


## [2026.08.12.182] - 2026-08-12
### fix(json): Track top-level JSON arrays for JSONL conversion

What changed:
- Added root-array state to JSON diagnosis.

Why:
- A top-level array must be identified separately so repair can remove only its outer delimiters.


## [2026.08.12.181] - 2026-08-12
### fix(json): Recognize bracket-tagged transcript exports

What changed:
- Expanded tagged-transcript detection from four speaker names to bracketed alphabetic tags.
- Keeps valid JSON arrays distinct because they begin with a JSON value, not a bare text tag.

Why:
- The raw inventory includes bracket-prefixed transcript exports beyond the initially observed speaker tags.


## [2026.08.12.180] - 2026-08-12
### fix(json): Separate non-JSON text from syntax errors

What changed:
- Parser failures whose first nonblank character cannot begin JSON now classify as NonJsonText.
- NonJsonText results state that a source-specific parser is required instead of presenting a misleading JSON syntax error.

Why:
- The raw transcript inventory contains several text-export families mislabeled with JSON extensions.


## [2026.08.12.179] - 2026-08-12
### fix(json): Capture JSON diagnosis leading text

What changed:
- Captured the first nonblank source line for diagnosis classification.

Why:
- Top-level parser failures must be distinguished between non-JSON text and malformed JSON syntax.


## [2026.08.12.178] - 2026-08-12
### fix(json): Collapse JSON diagnosis warning floods

What changed:
- Removed per-file warning logs from Test-DowserJson.
- Emits one final classification-count summary after the scan while preserving one diagnostic object per file on the pipeline.

Why:
- Thousands of mislabeled transcript files should produce useful progress and a compact diagnosis summary, not terminal noise.


## [2026.08.12.177] - 2026-08-12
### fix(json): Prepare compact JSON diagnosis logging

What changed:
- Added per-classification aggregation state to Test-DowserJson.

Why:
- Large diagnosis scans need one useful outcome summary rather than one log message per invalid file.


## [2026.08.12.176] - 2026-08-12
### docs(json): Document JSON diagnosis and repair workflow

What changed:
- Added INDEX entries for Test-DowserJson and Repair-DowserJson.
- Documented classifications, safe-repair boundary, default JSON-Repaired destination, and related assessment command.

Why:
- The public JSON workflow must be discoverable without guessing command names or output locations.


## [2026.08.12.175] - 2026-08-12
### test(json): Keep single-worker fixture scope stable

What changed:
- Changed the bounded-worker test to pass only its two intended valid fixtures.

Why:
- Malformed-input fixtures must not change the worker-count regression expectations.


## [2026.08.12.174] - 2026-08-12
### test(json): Keep schema fixture scope stable

What changed:
- Changed the schema-profile test to use only its two intended valid fixtures.

Why:
- The test validates schema comparison behavior independently from malformed-input diagnosis coverage.


## [2026.08.12.173] - 2026-08-12
### test(json): Isolate JSON comparison fixtures

What changed:
- Changed the key-comparison test to pass only its two intended valid fixtures.

Why:
- Diagnostic fixtures intentionally include malformed input and must not alter the preexisting comparison contract test.


## [2026.08.12.172] - 2026-08-12
### fix(json): Base JSON coverage on parseable files

What changed:
- Key coverage, missing-file counts, and detailed comparisons now use only successfully parsed files.
- DirectorySummary now separates candidate files, parsed files, and invalid files skipped.

Why:
- Coverage percentages and schema differences must not treat malformed files as missing every JSON key.


## [2026.08.12.171] - 2026-08-12
### fix(json): Exclude failed parses from JSON schema reports

What changed:
- Get-DowserJsonKey now skips failed parser results when building key coverage and schema profiles.
- Retains failed scan records in $global:DowserJsonLastParseFailures.
- Returns a clear warning when no candidate file can be parsed.

Why:
- Malformed or mislabeled files must not appear as empty schemas and distort directory assessment results.


## [2026.08.12.170] - 2026-08-12
### test(json): Cover diagnosis-first JSON repair

What changed:
- Added tests for RECORD banner classification, tagged transcript rejection, default JSON-Repaired output, and repaired JSONL validation.

Why:
- The repair path needs proof that it repairs only the recognized format and leaves source classification visible.


## [2026.08.12.169] - 2026-08-12
### test(json): Add malformed JSON fixture content

What changed:
- Added a RECORD banner export, tagged transcript text, and comment-bearing JSON to the JSON test workspace.

Why:
- Tests must exercise the actual input patterns that the diagnosis-driven repair path classifies.


## [2026.08.12.168] - 2026-08-12
### test(json): Prepare JSON diagnosis fixtures

What changed:
- Added record-banner, tagged-transcript, and comment-bearing JSON fixture paths to the JSON test setup.

Why:
- The diagnosis and repair behavior needs concrete inputs matching the observed malformed transcript formats.


## [2026.08.12.167] - 2026-08-12
### feat(module): Export JSON diagnosis and repair commands

What changed:
- Added Repair-DowserJson and Test-DowserJson to the manifest command surface.

Why:
- The new diagnosis-first workflow must be available after a normal Dowser module import.


## [2026.08.12.166] - 2026-08-12
### refactor(json): Make JSON repair diagnosis-driven

What changed:
- Repair-DowserJson now accepts a file or directory and classifies every file before writing.
- The default destination is a JSON-Repaired folder beside each source, with OutputDirectory as an override.
- Unrecognized, invalid, and tagged transcript inputs are returned as skipped with the diagnosis instead of being guessed into JSON.

Why:
- The repair operation must follow actual file evidence rather than applying one observed transcript fix to every JSON file.


## [2026.08.12.165] - 2026-08-12
### feat(json): Isolate safe JSON repair writers

What changed:
- Added the repair writer for only diagnosis-approved transformations.
- Writes repaired content to a temporary file before publishing it.
- Supports RECORD banner conversion and comment removal without touching source files.

Why:
- Repair output must be produced only after a known classification and must not leave partial destination files.


## [2026.08.12.164] - 2026-08-12
### feat(json): Add JSON diagnosis command

What changed:
- Added Test-DowserJson for file or directory diagnostics with visible progress.
- Reports the classification, exact parser failure location, repair eligibility, and intended safe action.
- Leaves source files unchanged.

Why:
- Operators need evidence about each malformed file before deciding whether a repair is appropriate.


## [2026.08.12.163] - 2026-08-12
### feat(json): Classify JSON parse failures before repair

What changed:
- Added a streaming JSON diagnosis helper that identifies unreadable input, RECORD banner exports, tagged transcript text, comments, valid JSONL, and parser syntax failures.
- Returns parser line, position, and message for syntax failures.
- Marks only deterministic transformations as repairable.

Why:
- A repair command must identify the actual input problem before selecting a safe transformation.


## [2026.08.12.162] - 2026-08-12
### feat(json): Add safe JSON repair command

What changed:
- Added Repair-DowserJson for canonical JSON token output without changing source files.
- Supports JSON comments and trailing commas accepted by Newtonsoft.Json.
- Converts Dowser RECORD banner exports into standard JSONL and rejects unrelated tagged transcripts.

Why:
- Assessment scans need a safe repair path for common syntax damage and formatted record exports.


## [2026.08.12.161] - 2026-08-12
### test(duplicates): Verify duplicate report hash evidence labels

What changed:
- Extended the HTML export regression test to assert the SHA256 proof and per-set hash-algorithm labels.

Why:
- The report's evidence labels are part of the operator-facing duplicate verification contract.


## [2026.08.12.160] - 2026-08-12
### fix(duplicates): Correct the duplicate report hash labels

What changed:
- Changed duplicate-set metadata to label the hash algorithm and hash value separately.
- Removed the repeated SHA prefix from the report proof header.

Why:
- A cleanup report must state its SHA-256 evidence accurately and without misleading duplicated text.


## [2026.08.12.159] - 2026-08-12
### test(duplicates): Cover empty filtered duplicate reports

What changed:
- Added Pester coverage for an HTML export requested with a MinSize that excludes every file.

Why:
- The no-eligible-files path must still produce a readable report at the requested destination.


## [2026.08.12.158] - 2026-08-12
### fix(duplicates): Write an empty report when filters match no files

What changed:
- Find-DowserDuplicate now writes the requested HTML report before returning when MinSize or other filters leave no eligible files.
- The report records zero files scanned and no byte-identical duplicate sets.

Why:
- An explicit report destination must receive an evidence record even when a scan produces no eligible candidates.


## [2026.08.12.157] - 2026-08-12
### fix(duplicates): Refresh enumeration progress from the first file

What changed:
- Changed duplicate-file enumeration progress from a 250-file threshold to the first file and then a 750 ms cadence.
- Uses a visible zero-percent indeterminate stage rather than an unsupported negative progress value.

Why:
- The first scan stage must visibly refresh even when the tree enumerates slowly or contains fewer than 250 files.


## [2026.08.12.156] - 2026-08-12
### fix(duplicates): Resolve duplicate report destination path correctly

What changed:
- Replaced an incompatible Split-Path parameter combination with System.IO.Path.GetDirectoryName for report-parent resolution.

Why:
- The previous parameter set failed when the report export attempted to create its destination directory.


## [2026.08.12.155] - 2026-08-12
### fix(duplicates): Fix duplicate report PowerShell interpolation

What changed:
- Delimited the HashAlgorithm variable before a literal colon in the generated HTML metadata line.

Why:
- PowerShell parsed the colon as part of the variable reference, preventing the private report helper from loading.


## [2026.08.12.154] - 2026-08-12
### docs(duplicates): Document duplicate evidence and report behavior

What changed:
- Expanded the command index with detection modes, progress behavior, output locations, and the Content versus Chunk safety boundary.

Why:
- Disk cleanup needs a clear distinction between proof of duplication and candidate-only matches.


## [2026.08.12.153] - 2026-08-12
### fix(duplicates): Keep the duplicate report static and display-only

What changed:
- Removed CSS custom properties and calculation-based layout from the generated report.
- Kept the report's values fully precomputed in PowerShell and its browser behavior limited to native expandable sections.

Why:
- The report must render supplied evidence without browser-side calculations or avoidable display machinery.


## [2026.08.12.152] - 2026-08-12
### test(duplicates): Cover exact duplicate detection and HTML export

What changed:
- Added Pester coverage for SHA content matches and the detailed duplicate object.
- Added an export test that verifies parent-directory creation and expandable HTML report content.

Why:
- The new cleanup report and exact-content proof need regression coverage before use on large disk scans.


## [2026.08.12.151] - 2026-08-12
### fix(duplicates): Close duplicate scan progress on completion

What changed:
- Find-DowserDuplicate now explicitly completes its progress record before returning results or a no-duplicate outcome.

Why:
- A completed scan must clear the active progress display instead of leaving stale work visible.


## [2026.08.12.150] - 2026-08-12
### feat(duplicates): Wire duplicate scans to the HTML report

What changed:
- Find-DowserDuplicate now invokes the private HTML report writer when ExportHtml is supplied.
- The export consumes only complete Content hash sets and does not add report objects to the command pipeline.

Why:
- The opt-in report must reflect exact duplicate evidence without disrupting existing script consumers.


## [2026.08.12.149] - 2026-08-12
### feat(duplicates): Expose the duplicate HTML report option

What changed:
- Added Find-DowserDuplicate ExportHtml parameter for the new expandable exact-content report.

Why:
- The report writer must be explicitly requested without changing existing CSV or pipeline output.


## [2026.08.12.148] - 2026-08-12
### docs(duplicates): Document the exact-duplicate HTML export

What changed:
- Added Find-DowserDuplicate comment-based help for the ExportHtml parameter and automatic report-directory creation.

Why:
- Operators need the report's proof boundary and destination behavior in Get-Help.


## [2026.08.12.147] - 2026-08-12
### feat(duplicates): Add an expandable exact-duplicate HTML report

What changed:
- Added private Export-DowserDuplicateHtml to create a self-contained report from full-content hash sets.
- The report ranks reclaimable space, exposes hash evidence, and keeps each set's full file paths inside expandable sections.
- The report writer creates a requested parent directory when it does not exist.

Why:
- Cleanup decisions need readable evidence, not a terminal dump or a flat list that obscures duplicate sets.


## [2026.08.12.146] - 2026-08-12
### fix(duplicates): Show progress while comparing file chunks

What changed:
- Find-DowserDuplicate now reports chunk-comparison progress by processed file.
- The Chunk stage announces its scope at Info level before reading file blocks.

Why:
- Chunk comparison can take longer than full-file hashing and must not appear stalled.


## [2026.08.12.145] - 2026-08-12
### perf(duplicates): Hash only same-size exact-duplicate candidates

What changed:
- Find-DowserDuplicate now groups files by byte length before full-content hashing.
- Added per-file progress for the exact-content SHA hash stage.
- Preserved SHA-256 as the default exact-duplicate proof.

Why:
- Files with different lengths cannot be byte-for-byte duplicates, so excluding them from full hashing reduces large scan time while preserving exact results.


## [2026.08.12.144] - 2026-08-12
### fix(duplicates): Show duplicate scan enumeration progress

What changed:
- Find-DowserDuplicate now emits an on-screen progress record while it enumerates files.
- Promoted scan start and eligible-file count to Info logging so normal runs identify the active stage.

Why:
- Large duplicate scans must visibly show active work before the hash stage begins.


## [2026.08.12.143] - 2026-08-12
### chore(disk-usage): Restore the existing disk-usage command contract

What changed:
- Removed the unreviewed PassThru parameter and restored Measure-DowserDiskUsage to its prior parameter surface.
- Left the structured pipeline output, console logging, and ExportHtml behavior unchanged.

Why:
- The existing report is already a public command contract and may have callers that rely on its emitted objects.


## [2026.08.11.142] - 2026-08-11
### docs(json): Correct JSON comparison help descriptions

What changed:
- Replaced stale key-count wording for -Compare and -IncludeFiles.
- Documented validation output in the command output contract.

Why:
- The current help must describe schema assessment and ingestion validation accurately.


## [2026.08.11.141] - 2026-08-11
### docs(json): Complete assessment report export help

What changed:
- Added assessment boundary notes, output contract, example behavior, and related command link to Export-DowserJsonAssessment help.

Why:
- The new public export command needs full in-command guidance consistent with the module surface.


## [2026.08.11.140] - 2026-08-11
### docs(json): Document retained JSON comparison state

What changed:
- Added Get-DowserJsonKey help notes for file-level validation and retained comparison variables.

Why:
- Full help must explain the assessment boundary and how callers reuse results.


## [2026.08.11.139] - 2026-08-11
### test(json): Cover JSON assessment report export

What changed:
- Added an integration test that writes all three assessment CSV reports and verifies full key validation output.

Why:
- The assessment export is only useful if its files are complete and readable by downstream tools.


## [2026.08.11.138] - 2026-08-11
### feat(module): Export JSON assessment report command

What changed:
- Added Export-DowserJsonAssessment to the module's explicit public command manifest.

Why:
- The new assessment exporter must be available after a normal module import.


## [2026.08.11.137] - 2026-08-11
### feat(json): Add JSON assessment report export

What changed:
- Added Export-DowserJsonAssessment to write directory summary, schema profile, and key validation CSV reports from one scan.

Why:
- Assessment results must be portable for database design and review without retaining full source documents.


## [2026.08.11.136] - 2026-08-11
### docs(json): Document retained JSON validation results

What changed:
- Added help for -Validation and $global:DowserJsonLastValidation.

Why:
- Users need to access coverage evidence without running the same large comparison again.


## [2026.08.11.135] - 2026-08-11
### test(json): Verify retained JSON key validation data

What changed:
- Assert that validation output retains every discovered path and identifies an all-file key as AlwaysPresent.

Why:
- Validation categories must be reliable before they guide database field requirements.


## [2026.08.11.134] - 2026-08-11
### feat(json): Classify JSON key coverage for ingestion validation

What changed:
- Build a retained per-key validation dataset for every comparison.
- Classify paths as AlwaysPresent, Common, Occasional, or Rare.
- Emit validation rows when -Validation is supplied.

Why:
- Database parsers need evidence of which paths are mandatory, broadly available, or exceptional.


## [2026.08.11.133] - 2026-08-11
### feat(json): Add JSON key validation switch

What changed:
- Added -Validation to request per-key coverage classifications from a comparison scan.

Why:
- Database ingestion needs a deliberate validation view of reliable and variable JSON paths.


## [2026.08.11.132] - 2026-08-11
### test(json): Verify retained JSON comparison results

What changed:
- Added an assertion that the global last-comparison variable contains every comparison row returned by the command.

Why:
- The retained result must be trustworthy before downstream validation and export workflows use it.


## [2026.08.11.131] - 2026-08-11
### feat(json): Retain the last JSON comparison in a global variable

What changed:
- Capture comparison result rows before pipeline output.
- Store them in $global:DowserJsonLastComparison while preserving normal command output.

Why:
- Users need to inspect, filter, export, or compare the completed report without rerunning a large directory scan.


## [2026.08.11.130] - 2026-08-11
### docs(index): Document schema-based JSON directory reports

What changed:
- Updated the JSON command index entry with schema layouts, profile limit, samples, and capped difference previews.

Why:
- The index must point users to the file-level comparison report rather than obsolete key-count buckets.


## [2026.08.11.129] - 2026-08-11
### docs(json): Correct JSON comparison output help

What changed:
- Replaced obsolete key-count and scan-summary result types in command help with schema-profile result types.

Why:
- The output contract changed from aggregate key counts to actual file-layout profiles.


## [2026.08.11.128] - 2026-08-11
### docs(json): Document schema profile report limit

What changed:
- Added help for the -ProfileLimit parameter.

Why:
- Large directories can contain many one-off schemas, so report size must be controllable.


## [2026.08.11.127] - 2026-08-11
### docs(json): Describe schema profile comparison output

What changed:
- Updated Get-DowserJsonKey help to describe dominant layouts, variants, key differences, and sample files.

Why:
- The command help must explain the comparison report users receive from large directories.


## [2026.08.11.126] - 2026-08-11
### fix(json): Cap schema difference output to useful previews

What changed:
- Replaced full missing and additional key lists with counts and five-key previews in schema profile rows.

Why:
- Schema variants with unrelated layouts must remain readable in an interactive console.


## [2026.08.11.125] - 2026-08-11
### test(json): Cover directory schema profile output

What changed:
- Replaced key-count distribution assertions with dominant and variant schema profile assertions.

Why:
- Tests must verify the report that identifies actual file layouts and their differences.


## [2026.08.11.124] - 2026-08-11
### fix(json): Fix schema profile ordering syntax

What changed:
- Corrected the PowerShell sort expression for descending schema profile frequency.

Why:
- The first schema-profile implementation could not import because its multi-property sort syntax was invalid.


## [2026.08.11.123] - 2026-08-11
### fix(json): Replace key-count dump with JSON schema profiles

What changed:
- Group compared files by their complete key-path set.
- Report the dominant schema, representative variants, sample files, and key additions or omissions.
- Avoid materializing per-key file rows unless detailed key comparison is requested.

Why:
- A directory report must identify real file shapes and their differences, not merely count unrelated key-count buckets.


## [2026.08.11.122] - 2026-08-11
### feat(json): Add bounded schema-profile report size

What changed:
- Added -ProfileLimit to control the number of distinct JSON file schemas shown in comparison output.

Why:
- Large directories need a readable set of representative file shapes rather than an unbounded profile dump.


## [2026.08.11.121] - 2026-08-11
### docs(architecture): List JSON scan private helpers

What changed:
- Corrected the private-helper count and added the JSON coordinator, queue worker, and streaming reader to the architecture inventory.

Why:
- The architecture map must expose the components that implement parallel JSON directory scanning.


## [2026.08.11.120] - 2026-08-11
### docs(architecture): Record bounded parallel JSON scan design

What changed:
- Documented the dedicated MTA pool, synchronized queues, token streaming readers, and caller-owned progress and logging.

Why:
- The parallel JSON scan is a new architectural boundary with explicit memory and observability constraints.


## [2026.08.11.119] - 2026-08-11
### docs(index): Document JSON scan reporting and reader controls

What changed:
- Updated the Get-DowserJsonKey index entry with compact output types, detailed-row switch, and bounded reader default.

Why:
- The index must match the command's scalable directory scan interface.


## [2026.08.11.118] - 2026-08-11
### perf(json): Align internal JSON worker default

What changed:
- Set the private JSON scan coordinator default reader count to the same eight-reader ceiling.

Why:
- Direct internal use must preserve the public command's tested storage-conscious concurrency behavior.


## [2026.08.11.117] - 2026-08-11
### perf(json): Cap default JSON scan readers at eight

What changed:
- Set Get-DowserJsonKey default -ThreadCount to the lower of eight or the processor count.

Why:
- Eight readers was faster than one and twenty-four readers in the representative large-directory benchmark.


## [2026.08.11.116] - 2026-08-11
### docs(json): Document bounded JSON reader default

What changed:
- Updated Get-DowserJsonKey help to state that its reader default is capped at eight.

Why:
- Users need to know the default avoids needless storage oversubscription on large scans.


## [2026.08.11.115] - 2026-08-11
### perf(json): Batch JSON file work per runspace

What changed:
- Queued all paths in synchronized shared state.
- Changed the runspace pool from one invocation per file to one queue-draining invocation per worker.
- Retained main-thread progress, result collection, and log emission.

Why:
- This removes per-file runspace startup overhead that made a 2,363-file scan slower despite parallel readers.


## [2026.08.11.114] - 2026-08-11
### perf(json): Add queue-consuming JSON scan workers

What changed:
- Added a private worker that drains shared JSON file paths and invokes the streaming reader for each file.

Why:
- One long-lived invocation per reader avoids runspace dispatch overhead for every file in large directories.


## [2026.08.11.113] - 2026-08-11
### test(json): Verify compact JSON comparison report

What changed:
- Assert that default comparison output omits detailed rows and reports common and differing key-path totals.

Why:
- The console report must remain concise while accurately describing cross-file key coverage.


## [2026.08.11.112] - 2026-08-11
### test(json): Request detailed rows in key comparison test

What changed:
- Updated the per-key comparison test to pass -ShowKeyComparison explicitly.

Why:
- The default comparison output is intentionally compact, so detailed rows must be requested.


## [2026.08.11.111] - 2026-08-11
### fix(json): Make directory comparison reports compact by default

What changed:
- Emit key-coverage, key-count distribution, and scan-summary rows by default.
- Emit individual KeyComparison rows only with -ShowKeyComparison or -IncludeFiles.

Why:
- A large directory comparison should show progress and a readable report instead of hundreds of raw key rows.


## [2026.08.11.110] - 2026-08-11
### feat(json): Add opt-in detailed key comparisons

What changed:
- Added the -ShowKeyComparison switch to Get-DowserJsonKey.

Why:
- Large comparison scans need a concise default while retaining complete key-path data on demand.


## [2026.08.11.109] - 2026-08-11
### docs(json): Document detailed JSON comparison switch

What changed:
- Added help for -ShowKeyComparison and clarified that -IncludeFiles enables detailed comparison rows.

Why:
- Users need a clear route from the compact console report to file-level key details.


## [2026.08.11.108] - 2026-08-11
### docs(json): Describe compact JSON comparison output

What changed:
- Updated Get-DowserJsonKey help to describe the compact -Compare report and opt-in detailed key rows.

Why:
- Interactive directory scans need a concise default report without obscuring the available detail.


## [2026.08.11.107] - 2026-08-11
### test(json): Cover single-worker JSON directory scans

What changed:
- Added a comparison test using -ThreadCount 1 and verified the expected scan totals.

Why:
- The bounded worker option needs a regression test for the intentional single-reader path.


## [2026.08.11.106] - 2026-08-11
### fix(json): Prevent stale worker disposal after a dispatch failure

What changed:
- Reset the per-dispatch PowerShell instance reference before starting each JSON scan worker.

Why:
- A failed worker creation must not dispose a completed worker from an earlier dispatch attempt.


## [2026.08.11.105] - 2026-08-11
### perf(json): Parallelize JSON file token scans

What changed:
- Get-DowserJsonKey now delegates each file to the bounded JSON runspace scanner.
- Keeps aggregation and console output on the main runspace.

Why:
- Sequential parsing cannot handle directories containing tens or hundreds of thousands of JSON files efficiently.


## [2026.08.11.104] - 2026-08-11
### feat(json): Add JSON scanner thread-count control

What changed:
- Added ThreadCount to Get-DowserJsonKey with a processor-count default.

Why:
- Operators need a bounded way to tune scanning concurrency for large file trees.


## [2026.08.11.103] - 2026-08-11
### feat(json): Document JSON reader concurrency control

What changed:
- Added ThreadCount help to Get-DowserJsonKey.

Why:
- Large scans need a bounded concurrency control suited to their storage throughput.


## [2026.08.11.102] - 2026-08-11
### feat(json): Add bounded ISS runspace orchestration for JSON scans

What changed:
- Added Invoke-DowserJsonKeyScan with a bounded MTA runspace pool.
- Registers the JSON worker through InitialSessionState and drains synchronized result and log queues on the main thread.

Why:
- Large directory scans need parallel file reads without violating runspace state or logging rules.


## [2026.08.11.101] - 2026-08-11
### feat(json): Add a token-streaming JSON worker

What changed:
- Added Read-DowserJsonKeyFile to scan one JSON or JSONL file and enqueue its result and diagnostics through SyncHash queues.

Why:
- Parallel directory scans need isolated parser state and thread-safe result delivery.


## [2026.08.11.100] - 2026-08-11
### docs(index): Document concise JSON comparison output

What changed:
- Added IncludeFiles and the concise comparison row shapes to the JSON command index entry.

Why:
- Operators need to know that path lists are opt-in for large directory scans.


## [2026.08.11.099] - 2026-08-11
### test(json): Verify concise default comparison rows

What changed:
- Added coverage that normal KeyComparison rows omit MissingFromFiles.

Why:
- The console report must not regress to dumping every matching path.


## [2026.08.11.098] - 2026-08-11
### test(json): Request file lists explicitly in comparison coverage

What changed:
- Updated the detailed missing-file assertion to use IncludeFiles.

Why:
- Normal comparison output now exposes counts instead of unbounded path lists.


## [2026.08.11.097] - 2026-08-11
### fix(json): Keep default comparison output concise

What changed:
- Replaced unbounded present and missing path lists with MissingFileCount.
- Moved present, missing, and bucket file lists behind IncludeFiles.

Why:
- Large directory comparisons were producing unreadable console output with thousands of file paths.


## [2026.08.11.096] - 2026-08-11
### feat(json): Add opt-in file lists to JSON comparisons

What changed:
- Added the IncludeFiles switch to Get-DowserJsonKey.

Why:
- Detailed file paths are useful for investigation but overwhelm normal directory reports.


## [2026.08.11.095] - 2026-08-11
### feat(json): Document opt-in file-list detail for compare reports

What changed:
- Added IncludeFiles help to Get-DowserJsonKey.

Why:
- Normal comparison output needs to remain compact when directories contain many files.


## [2026.08.11.094] - 2026-08-11
### docs(index): Document the comparison distribution report

What changed:
- Updated the Get-DowserJsonKey output contract with key-count buckets and the final scan summary.

Why:
- The command index must describe the report rows emitted by -Compare.


## [2026.08.11.093] - 2026-08-11
### test(json): Cover comparison key-count report rows

What changed:
- Added Pester assertions for KeyCountDistribution and final ScanSummary output.

Why:
- The new directory-level report must retain its expected flat output shape and totals.


## [2026.08.11.092] - 2026-08-11
### feat(json): Add key-count buckets to compare output

What changed:
- Get-DowserJsonKey -Compare now emits one KeyCountDistribution row per file key-count bucket.
- Compare output ends with a ScanSummary row containing scanned-file and key-path totals.

Why:
- Directory comparisons need a flat report showing how many files share each key count.


## [2026.08.11.091] - 2026-08-11
### docs(index): Record the JSON CSV alias

What changed:
- Added the Export-JsonCsv opt-in alias to the Export-DowserJsonCsv index entry.

Why:
- The command inventory should show the complete public interactive surface.


## [2026.08.11.090] - 2026-08-11
### docs(index): Record the JSON key alias

What changed:
- Added the Get-JsonKey opt-in alias to the Get-DowserJsonKey index entry.

Why:
- The command inventory should show the complete public interactive surface.


## [2026.08.11.089] - 2026-08-11
### feat(aliases): Add the opt-in JSON key alias

What changed:
- Added Get-JsonKey as an Enable-DowserAliases mapping for Get-DowserJsonKey.

Why:
- Alias coverage requires every exported command to have a short opt-in name.


## [2026.08.11.088] - 2026-08-11
### feat(aliases): Add the opt-in JSON CSV alias

What changed:
- Added Export-JsonCsv as an Enable-DowserAliases mapping for Export-DowserJsonCsv.

Why:
- Alias coverage requires every exported command to have a short opt-in name.


## [2026.08.11.087] - 2026-08-11
### docs(architecture): Describe JSON streaming and sequential processing

What changed:
- Documented the JsonTextReader token stream and intentional sequential execution.

Why:
- Large-file memory bounds and the choice not to add runspace readers are architectural behavior.


## [2026.08.11.086] - 2026-08-11
### docs(index): Document the JSON command contracts

What changed:
- Added complete INDEX.md entries for streamed key inspection and CSV export.
- Recorded parameters, output shapes, and the relationship between the commands.

Why:
- The project index is the authoritative command map for module consumers.


## [2026.08.11.085] - 2026-08-11
### docs(readme): Update the documented command count

What changed:
- Changed the README command count from 27 to 29.

Why:
- The module now exposes two additional JSON commands.


## [2026.08.11.084] - 2026-08-11
### docs(readme): Add JSON inspection and CSV export examples

What changed:
- Added quick-start examples for key comparison and Excel-compatible CSV export.

Why:
- Users need direct command examples for the new JSON workflow.


## [2026.08.11.083] - 2026-08-11
### docs(architecture): Correct the default-on switch design note

What changed:
- Replaced the stale bool-parameter guidance with the current default-on switch pattern.

Why:
- Architecture documentation contradicted the module behavior recorded in the recent switch fix.


## [2026.08.11.082] - 2026-08-11
### docs(architecture): Update the exported command count

What changed:
- Updated ARCHITECTURE.md to list 28 public basenames and 29 exported functions.

Why:
- The manifest now exports two additional JSON commands.


## [2026.08.11.081] - 2026-08-11
### docs(architecture): Update public module file count for JSON commands

What changed:
- Updated the Public directory count from 26 to 28 files in ARCHITECTURE.md.

Why:
- The architecture map must reflect the two new JSON command files.


## [2026.08.11.080] - 2026-08-11
### fix(json): Format CSV rows before calling StreamWriter

What changed:
- Constructed the complete CSV row before passing it to StreamWriter.WriteLine.

Why:
- PowerShell method-call parsing treated the format arguments as WriteLine arguments instead of a single formatted row.


## [2026.08.11.079] - 2026-08-11
### fix(json): Resolve CSV destination paths without invalid parameter binding

What changed:
- Replaced the incompatible Split-Path LiteralPath and Parent call with System.IO path resolution.

Why:
- PowerShell rejects that parameter combination, preventing CSV output from being created.


## [2026.08.11.078] - 2026-08-11
### test(json): Cover JSON inspection and CSV export

What changed:
- Added Pester fixtures for nested JSON, JSONL comparison, and CSV export.
- Covers exported command discovery plus key, document, and value counts.

Why:
- The new streamed commands need regression coverage for nested and line-delimited input.


## [2026.08.11.077] - 2026-08-11
### feat(module): Expose JSON key inspection from the Dowser manifest

What changed:
- Added Get-DowserJsonKey to FunctionsToExport in Dowser.psd1.

Why:
- The streamed inspection command must be available when consumers import the module manifest.


## [2026.08.11.076] - 2026-08-11
### feat(module): Expose JSON CSV export from the Dowser manifest

What changed:
- Added Export-DowserJsonCsv to FunctionsToExport in Dowser.psd1.

Why:
- The new CSV converter must be available when consumers import the module manifest.


## [2026.08.11.075] - 2026-08-11
### feat(json): Export streamed JSON values as Excel-compatible CSV

What changed:
- Added Export-DowserJsonCsv for JSON and JSONL source files.
- Writes long-form CSV rows with source file, document number, JSON key path, and value.

Why:
- Large nested JSON needs a spreadsheet-friendly export without materializing documents in memory.


## [2026.08.11.074] - 2026-08-11
### feat(json): Add streamed JSON and JSONL key inspection

What changed:
- Added Get-DowserJsonKey for per-file key-path counts and directory-wide comparison.
- Uses Newtonsoft.Json.JsonTextReader so full documents are not deserialized into memory.

Why:
- Large JSON and JSONL files need schema inspection without whole-file memory pressure.


## [2026.08.08.073] - 2026-08-08
### fix(Find-DowserFile): Accept multiple -Pattern values, and stop emitting null rows on empty and unresolvable results

What changed:
- -Pattern is now [string[]]$Pattern = @('*'), so -Pattern *.md,*.json works. Each element is wildcard-wrapped independently in begin{}, so -Pattern cortex,*.json wraps only the bare token.
- Added $nameTest = $Pattern.Count -gt 1. Single pattern keeps the Get-ChildItem -Filter fast path; multiple patterns enumerate once and test $_.Name -like against the set, short-circuiting on first hit. The size and date predicates are now chained behind -and $ok so a name rejection skips them.
- $nameTest is threaded into the runspace scriptblock as a new second argument (param($chunk, $patterns, $nameTest, ...)) and the ArgumentList order updated to match.
- Swapped the O(n^2) Select-Object -Unique dedup for Select-DowserUniquePath (the HashSet helper), closing the last of the three sites the 2026.07.10.070 entry listed as outstanding.
- Wrapped the dedup result in @(): no matches previously left $allPaths $null, @($null).Count is 1, and the formatter then emitted one row of null properties and logged 'Found 1 files'.
- Guarded both formatter branches on a null Get-Item result, logging the skip at Verbose. An enumerated path that will not resolve produced a row of nulls instead of being dropped.
- Wrapped the top-level directory enumeration in @() and gated the partition on $topLevelItems.Count -gt 0.
- CBH: rewrote .PARAMETER Pattern for the list form and added an example.

Why:
- -Pattern took one string, so -Pattern *.md,*.json failed with "Cannot process argument transformation on parameter 'Pattern'" and there was no way to ask for two extensions in one pass. -Filter is a filesystem-level filter that accepts exactly one pattern, which is why it could not simply be handed the array; it stays the fast path for the single-pattern case and the multi-pattern case moves the test in-process, one enumeration, no cross-pattern duplicates. Three latent defects surfaced while testing the change and are fixed with it. First, a search that matched nothing returned one PSCustomObject with every property null, because an empty pipeline result collapses to $null and @($null).Count is 1; the Verbose count log said 1 for the same reason. Second, a path that enumerated but would not resolve on the Get-Item pass (dangling symlink, deleted mid-scan) also produced a row of nulls: a real ~/projects/ClauDesk scan returned 863 rows of which 3 were null garbage, now 860 clean. Third, on a directory with no subdirectories Get-ChildItem -Directory returns nothing, $null.FullName is $null, and @($p) + @($null) handed Invoke-DowserRunspacePool a target list containing a null, which its mandatory -InputObject rejected: Find-DowserFile crashed on any flat directory under its own default -UseRunspaces path. Verified on pwsh 7.6.4 across both the runspace and single-threaded paths: multi-pattern, mixed bare-plus-glob, single-pattern, default '*', no-recurse, size-filtered, StopOnFirstMatch, dangling symlink, flat directory, and zero-match all behave; full test suite 140 tests, 137 pass, 0 fail, 3 platform skips.


## [2026.08.08.072] - 2026-08-08
### fix(params): Default-on booleans become real switches, and stop assigning the read-only platform automatics

What changed:
- [bool]$Recurse = $true -> [switch]$Recurse = $true in Find-DowserFile, Find-DowserRecentLog, Find-DowserModified, Find-DowserScript.
- [bool]$UseRunspaces = $true -> [switch]$UseRunspaces = $true in Find-DowserFile, Get-DowserMap, Get-DowserReport.
- Dowser.psm1 platform shim: replaced the Get-Variable probe plus direct $IsWindows/$IsLinux/$IsMacOS assignments with a $PSVersionTable.PSVersion.Major -lt 6 gate that sets the three names through Set-Variable -Scope Script.
- Verified on pwsh 7.6.4: all seven parameters report SwitchParameter; bare -Recurse recurses, -Recurse:$false does not, omitting it still recurses (default-on behaviour preserved); module imports clean.

Why:
- Find-DowserFile -Path X -Pattern *.jsonl -Recurse failed with "Missing an argument for parameter 'Recurse'. Specify a parameter of type 'System.Boolean'". A [bool] parameter is a value parameter: the binder demands an argument, so the one spelling every PowerShell user reaches for first was the one spelling that did not work. The CBH already documented switch semantics ("Default is $true. Pass -Recurse:$false to disable"), so the type was contradicting the help text. [switch] with a $true default keeps default-on behaviour while making bare -Recurse legal and -Recurse:$false the documented off-switch. No call site in the repo used the -Recurse $true space form, so nothing internal broke; only that space form is retired. Separately, the platform shim assigned $IsWindows, $IsLinux and $IsMacOS directly. Those are read-only engine automatics on pwsh 6+, and the analyzer flags the assignment statically even though the Get-Variable guard meant it never executed there, so the file carried three permanent editor warnings. Set-Variable behind a version gate says the same thing without touching the automatics on any host that owns those names.


## [2026.07.10.071] - 2026-07-10
### feat(Find-DowserString): Promote output formatting to a first-class Phase 4/4 with progress, and relink README into the repo root

What changed:
- Renumbered all phase labels from x/3 to x/4 in both Write-Log and Write-Progress calls.
- Added Phase 4/4 (output formatting): an Info log on entry stating the row count and OutputMode, a Write-Progress bar, and an Info log on exit stating the elapsed format time.
- Instrumented the grouped formatter with a throttled per-file progress counter (~5 updates/sec, same cadence as the Phase 1 enumeration loop).
- Replaced the per-group `Measure-Object -Property Count -Sum` cmdlet call with an inline accumulator loop.
- Fixed the Phase 2 progress mislabel: the bar counts directories, so its status text now reads 'Scanning directories for files' instead of 'Gathering files'.
- Created README.md in the repo root as a symlink to docs/README.md, matching the existing docs/CHANGELOG.md root-symlink convention.

Why:
- Output formatting was never counted as a phase, so the function announced 'Phase 3/3: Done' and then went completely silent while Group-Object, Sort-Object and the per-file reduction chewed through the match set. On a 161,135-row result that silence was indistinguishable from the O(n^2) hang it had just been fixed for. If the work is slow enough to notice, it is a phase, and a phase announces itself: name it, count it, show progress through it, and report how long it took. The Phase 2 bar was separately lying about its unit, reporting directory counts under a 'Gathering files' label. Root README.md had been moved to docs/ leaving the repo root with no readme at all; a symlink keeps docs/ as the single source while GitHub and any tool that looks for ./README.md still find it.


## [2026.07.10.070] - 2026-07-10
### fix(Find-DowserString): Stop ArrayList.Add index leaking into worker output, and drop O(n^2) -Unique from the output formatters

What changed:
- Added the missing [void] to the $results.Add(...) call in the search worker's catch{} block (Public/Find-DowserString.ps1, read-error path).
- grouped and counts formatters now use `$_.Group.LineNumber | Sort-Object -Unique` instead of `Select-Object -ExpandProperty LineNumber -Unique | Sort-Object`.
- files formatter now uses Select-DowserUniquePath instead of `Select-Object -ExpandProperty FilePath -Unique`.
- Verified all four OutputModes (grouped, counts, files, matches) against a tree containing an unreadable file.

Why:
- ArrayList.Add returns the index of the inserted element. In the search scriptblock's catch{} branch the call was not voided, so for every file that failed to read, a bare Int32 was emitted into the runspace worker's output stream and collected alongside the real match rows. Group-Object FilePath then bucketed those integers under a null key and the grouped formatter died with 'Property LineNumber cannot be found' at line 618, discarding the entire result set after a 390-second Phase 3. This never fired on clean trees (the Dowser repo smoke test passed) because no file threw; it fires reliably on ~/projects/ where permission-denied and special files exist. Every other .Add() in the file was already voided; this one was the outlier. Separately, the end{} formatters carried the same O(n^2) Select-Object -Unique that was removed from Phase 2, applied per file group over 161,135 match rows, and end{} has no Write-Progress at all, so that stage was both slow and completely silent. Sort-Object -Unique is O(n log n) and preserves the prior semantics (unique-then-sort produces the same ordered set). Known remaining: end{} still emits no progress; Phase 2's progress bar counts directories while its label says 'Gathering files'; the O(n^2) dedup persists in Find-DowserFile.ps1:216 and Get-DowserReport.ps1:349; and other public functions have not been audited for either the Add-leak or the Verbose-gated counts.


## [2026.07.10.069] - 2026-07-10
### fix(Find-DowserString): Replace O(n^2) Select-Object -Unique dedup that read as a hang, and stop hiding status counts behind -Verbose

What changed:
- Added Private/Select-DowserUniquePath.ps1: single-pass HashSet dedup for path lists, preserving first-seen order.
- Find-DowserString Phase 2/3 now calls it instead of `$gatherResults | Select-Object -Unique`.
- Promoted every phase status line and count in Find-DowserString from -Severity Verbose to Info. Only the per-directory 'skipped inaccessible directory' line remains Verbose.
- Added Tests/Select-DowserUniquePath.Tests.ps1 (5 tests), including a regression guard asserting 50,000 paths dedup in under 5 seconds.
- Files changed: Public/Find-DowserString.ps1, Private/Select-DowserUniquePath.ps1 (new), Tests/Select-DowserUniquePath.Tests.ps1 (new).

Why:
- Select-Object -Unique compares each incoming item against every item it has already kept, which is O(n^2). Measured on this box: 10k paths 2.2s, 20k 9.4s, 40k 37.3s. `Find-DowserString ~/projects/ -Patterns MyelinDrite -Recurse` yields 251,874 files past the exclude/size filters, extrapolating to ~25 minutes burned on that single line. Because the phase-2 runspace pool had already called `Write-Progress -Completed`, the console sat blank the whole time and the command was indistinguishable from a deadlock. Dedup exists only to absorb symlink cycles re-enumerating a directory; the enumerator otherwise visits each directory once. A HashSet gets the same answer in one pass (50k paths: 191ms vs ~58s). The comparer is Ordinal, NOT OrdinalIgnoreCase: Select-Object -Unique is case-sensitive on PowerShell 7 (verified on 7.6.3, '/b/File.txt' and '/b/file.txt' both survive), and on Linux those are two different files that must both be searched. Do not 'simplify' this to OrdinalIgnoreCase. Severity doctrine for this module: Verbose is for per-item actions you only want when debugging (every file checked, every directory skipped). Status changes and counts -- how many directories found, how many files to scan, how many matched -- are Info and must be on screen by default. They were all Verbose, so Write-Log returned early at the Verbose gate and the operator got no dialogue at all. Known remaining: the same O(n^2) dedup is still present on large file lists in Public/Find-DowserFile.ps1:216 and Public/Get-DowserReport.ps1:349; the Select-Object -Unique calls in Get-DowserMap.ps1 and ConvertTo-DowserIco.ps1 operate on small exclude lists and are harmless.


## [2026.07.05.068] - 2026-07-05
### feat(Get-DowserMap): Auto-detect archive files (.zip/.7z/.rar/.tar/.gz) and render internal contents as a tree

What changed:
- Get-DowserMap now auto-detects when -Path resolves to a recognized archive file (.zip, .7z, .rar, .tar, .gz) instead of a directory, and renders the archive's internal contents as the same style of box-drawing tree it already renders for real folders, instead of the previous broken single-line output for a leaf-file path.
- .zip is read natively via System.IO.Compression.ZipFile (no external dependency). .7z/.rar/.tar/.gz are listed via the 7-Zip CLI (7z l -slt) when installed; if 7-Zip is missing, an ARCHIVE UNREADABLE line is returned instead of throwing.
- Supports -MaxDepth, -IncludeSize, -IncludeFileCount, -IncludeExtensions/-ExcludeExtensions/-IncludeFilePatterns/-ExcludeFiles/-ExcludeFolders, -Ascii/-AsHtml, -NoDefaultExcludes, -FoldersOnly, -LinuxPaths/-ShowFullPathTree, and the new -SevenZipPath parameter for non-.zip formats.
- Everything is implemented as nested helper functions inside Get-DowserMap.ps1 itself; no new files were added.
- Files changed: Public/Get-DowserMap.ps1 -- added -SevenZipPath parameter and archive-mode auto-detection/rendering (commit a56f7d9).

Why:
- Commit a56f7d9 shipped the archive-mode fix but did not update the changelog; Dowser.psm1 reads its reported version from the newest changelog heading at import time, so the module still reported the stale 2026.07.02.066 version despite the new fix being live.


## [2026.07.02.066] - 2026-07-02

## [2026.07.02.067] - 2026-07-02
### chore(github): Flip DivergentCortex/Dowser to public and apply security hardening

What changed:
- Flipped repo visibility from private to public via PATCH /repos/DivergentCortex/Dowser
- Enabled Dependabot vulnerability alerts via PUT /repos/.../vulnerability-alerts
- Enabled Dependabot automated security fixes via PUT /repos/.../automated-security-fixes
- Enabled secret scanning (status=enabled) via PATCH security_and_analysis
- Enabled secret scanning push protection (status=enabled) via PATCH security_and_analysis
- Enabled private vulnerability reporting via PUT /repos/.../private-vulnerability-reporting
- Set branch protection on main: allow_force_pushes=false, allow_deletions=false

Why:
- Public release gate requires security hardening before exposure to internet traffic.
- Branch protection prevents force-push history rewrites and accidental branch deletion.
- Secret scanning and push protection block credential leaks at commit time.

Verification (Step 6 output):
- visibility=public, private=false
- secret_scanning=enabled, push_protection=enabled, dependabot_updates=enabled
- allow_force_pushes=false, allow_deletions=false
- private_vulnerability_reporting.enabled=true

Manual follow-up:
- CodeQL default-setup returned HTTP 404: GitHub Advanced Security is not available on this org plan.
  Enable CodeQL manually via Settings > Code security and analysis when GHAS is provisioned.

### fix(Dowser.psd1): Revert ProjectUri to DivergentCortex/Dowser

What changed:
- Reverted ProjectUri from kizer88/Dowser back to DivergentCortex/Dowser in the module manifest PSData block

Why:
- Original value was intentional; DivergentCortex/Dowser is the planned org home for this module. The kizer88 value was incorrect.


## [2026.07.01.065] - 2026-07-01
### chore(release): P0-4 fix (default branch) and Phase 6 pre-flip hardening

What changed:
- Changed GitHub default branch from master to main via API
- Deleted stale master branch; only main remains
- Enabled Dependabot vulnerability alerts and automated security fixes (pre-flip)
- Verified .github/CODEOWNERS with rule: * @kizer88 (created by prior agent run)
- Documented post-flip items: secret scanning, push protection, private vuln reporting, CodeQL, branch protection all require public visibility on free tier

Why:
- P0-4: master was the stale default branch while active development targets main. Mismatch would confuse contributors and break default clone behavior. Phase 6 hardening enables all free-tier security features possible while the repo is still private.


## [2026.07.01.064] - 2026-07-01
### chore(ci): Add GitHub Actions CI workflow for Pester tests on Linux

What changed:
- Created .github/workflows/pester.yml: triggers on push to main and pull_request, runs on ubuntu-latest, installs Pester, runs Invoke-Pester Tests/ -Output Detailed -ExcludeTag Windows

Why:
- Public repo needs automated test runs on PRs. Linux-only CI catches cross-platform regressions without requiring a Windows runner.


## [2026.07.01.063] - 2026-07-01
### docs(CODEOWNERS): Add CODEOWNERS file assigning all paths to @kizer88

What changed:
- Created .github/CODEOWNERS with a single rule: * @kizer88

Why:
- Ensures the maintainer is automatically requested for review on all pull requests before the repo goes public.


## [2026.07.01.062] - 2026-07-01
### chore(Tests): Add pre-run report cleanup to Invoke-DowserTestSuite.ps1

What changed:
- Added two-line Get-ChildItem / Remove-Item block after ReportDir creation in Invoke-DowserTestSuite.ps1 to purge stale .csv and .html files before each run

Why:
- Each test run now starts with an empty Reports directory so results from previous sessions cannot be mistaken for the current run's output.


## [2026.07.01.061] - 2026-07-01
### docs(SECURITY.md): Add security policy for vulnerability reporting

What changed:
- Created SECURITY.md at project root with private vulnerability reporting instructions (GitHub Security tab or maintainer email), 7-day acknowledgment and 30-day fix commitments, and in-scope/out-of-scope boundaries

Why:
- Required community file for public repository. Directs security reports to private channels instead of public issues.


## [2026.07.01.060] - 2026-07-01
### chore(ci): Prior session hook and test infrastructure changes

What changed:
- Created _set-executable.sh and _test-hook.sh scripts for hook testing
- Generated test result artifacts (CSV and HTML reports) from Pester runs
- Added workflow configuration files

Why:
- Retroactive changelog entry covering prior session infrastructure and test artifact changes that were not logged at time of creation


## [2026.07.01.059] - 2026-07-01
### chore(Tests): Delete stale test report files from Tests/Reports and add auto-purge before each run

What changed:
- Deleted 10 stale .csv and .html test result files from Tests/Reports/ (all timestamped 20260630)
- Added pre-run cleanup logic in Invoke-DowserTestSuite.ps1 to remove all existing .csv and .html files from the Reports directory before each test run

Why:
- Tests/Reports accumulated result files from multiple prior sessions. The new auto-purge ensures each run starts with a clean Reports directory, preventing stale results from being confused with the current run's output.


## [2026.07.01.058] - 2026-07-01
### feat(git-hooks): Add machine-wide pre-commit denylist for sensitive strings

What changed:
- Configured global git hooks directory at ~/.git-hooks via core.hooksPath
- Wrote pre-commit hook at ~/.git-hooks/pre-commit that blocks commits containing former-employer identifiers and secret patterns (private keys, cloud access keys, platform tokens)
- Hook checks all staged added lines, prints the offending file and pattern, and exits 1 to abort the commit

Why:
- Sensitive strings (former employer hostnames, org names, internal infrastructure paths) kept appearing in commits and requiring after-the-fact history scrubbing. Machine-wide hook intercepts them before commit in every repo.


## [2026.07.01.057] - 2026-07-01
### fix(Dowser.psd1): Fix ProjectUri to match actual repo location kizer88/Dowser

What changed:
- Changed ProjectUri in Dowser.psd1 line 77 from 'https://github.com/DivergentCortex/Dowser' to 'https://github.com/kizer88/Dowser'

Why:
- Pre-public scrub: manifest pointed at a non-existent org repo; corrected to the actual publishing location under kizer88


## [2026.07.01.056] - 2026-07-01
### fix(Write-Log): Update Organization field to Divergent Cortex

What changed:
- Changed .NOTES Organization field in Write-Log.ps1 line 140 from 'Divergent Cortex' to 'Divergent Cortex'

Why:
- Pre-public scrub: .NOTES block attributed the file to a former employer's internal team (Divergent Cortex); updated to reflect current organization


## [2026.07.01.055] - 2026-07-01
### fix(ConvertTo-DowserIco): Remove corporate UNC path example from comment (pre-public scrub)

What changed:
- Replaced UNC path comment on line 240 of ConvertTo-DowserIco.ps1 that exposed a former employer's internal infrastructure (server.example.com) with a generic server/share example

Why:
- Pre-public scrub: comment contained sensitive corporate UNC path referencing internal infrastructure, not appropriate for a public repository


## [2026.06.30.054] - 2026-06-30
### fix(Aliases): Fix alias export: change Set-Alias scope to Script, add dfast alias for Invoke-DowserFastSearch

What changed:
- Changed Set-Alias -Scope Global to -Scope Script in Enable-DowserAliases so aliases land in module scope where Export-ModuleMember -Alias * can see them
- Added 'dfast' = 'Invoke-DowserFastSearch' to the alias map in Aliases/Aliases.ps1 (30 entries total, 29 registered on Linux after builtin collision guard skips pstree/shtree)

Why:
- Set-Alias -Scope Global puts aliases in the session global scope, invisible to Export-ModuleMember which only sees module scope -- result was AliasCount 0 on import. dfast alias was missing from the map entirely, causing Alias-dfast FAIL in the test suite.


## [2026.06.30.053] - 2026-06-30
### fix(Get-DowserReport): Guard empty Message parameter in Write-Log call to fix DirScan+ExportFiles failure

What changed:
- Changed three Write-Log "" calls to Write-Log " " in Public/Get-DowserReport.ps1 -- two blank-line separators in Get-DowserReport end block (lines 653, 669) and one in Compare-DowserReport end block (line 991)
- Empty string passed as positional Message argument caused bind error at runtime despite Write-Log declaring [AllowEmptyString()]

Why:
- Test suite reported Get-DowserReport DirScan and ExportFiles FAIL with error: Cannot bind argument to parameter Message because it is an empty string


## [2026.06.30.052] - 2026-06-30
### fix(Aliases): Fix alias export mechanism; ensure >=20 aliases exported including dfast

What changed:
- Added Enable-DowserAliases call in Dowser.psm1 after dot-sourcing Aliases.ps1 so all 28 aliases register at module import time
- Previously the function was defined but never invoked, leaving AliasCount at 0 and Export-ModuleMember -Alias * exporting nothing

Why:
- Test suite reported AliasCount 0 (need >= 20) and Invoke-FastSearch alias unavailable because Enable-DowserAliases was never called at module load


## [2026.06.30.051] - 2026-06-30
### fix(Get-DowserMap): Runspace path normalization, markdown root display var, -IncludeSize exclusion-aware stack-walk

What changed:
- Runspace scriptblock: normalize file.FullName to forward-slash inline before matching against excludePaths (ConvertTo-ForwardSlashPath not available in runspace)
- Markdown file output: compute $rootDisplay separately from $rootFull -- on Windows converts forward-slash back to backslash for display, leaves $rootFull internal value unchanged
- Replaced flat Get-ChildItem -Recurse size sum in Get-FolderAnnotation with exclusion-aware stack-walk that respects Test-ExcludeFolder / Test-IncludeFile / Test-ExcludeByPath

Why:
- Runspace scriptblocks run in isolated contexts without parent-scope helpers, so the normalize-inline pattern is required. $rootFull is now forward-slash internally so markdown output would show wrong separators on Windows without the $rootDisplay conversion. IncludeSize was ignoring -ExcludeFolders just like IncludePsCount was ignoring filters -- same fix pattern applied.


## [2026.06.30.050] - 2026-06-30
### fix(Get-DowserMap): Add ConvertTo-ForwardSlashPath; normalize rootFull and excludePaths so -ExcludePathPatterns works on Linux

What changed:
- Added ConvertTo-ForwardSlashPath helper function (replaces backslash with forward-slash, platform-agnostic)
- Changed rootFull normalization from ConvertTo-NativeSeparator to ConvertTo-ForwardSlashPath
- Changed excludePaths normalization from ConvertTo-NativeSeparator to ConvertTo-ForwardSlashPath
- Updated ConvertTo-RelativePath to normalize input through ConvertTo-ForwardSlashPath and TrimStart both slash chars
- Updated Test-ExcludeByPath to normalize item.FullName through ConvertTo-ForwardSlashPath before comparison

Why:
- On Linux, ConvertTo-NativeSeparator is a no-op for forward-slash paths but excludePaths patterns containing backslash (from user input or Windows paths) would never match. Using forward-slash as canonical comparison form normalizes both sides identically on all platforms.


## [2026.06.30.049] - 2026-06-30
### fix(Get-DowserMap): Rename -IncludePsCount to -IncludeFileCount (alias kept); count reflects active filters via stack-walk

What changed:
- Renamed param $IncludePsCount to $IncludeFileCount with [Alias('IncludePsCount')] attribute
- Rewrote Get-FolderAnnotation file count block: stack-walk respecting Test-ExcludeFolder / Test-IncludeFile / Test-ExcludeByPath instead of hardcoded Get-ChildItem -Filter *.ps1
- Changed annotation label from '[N .ps1]' to '[N files]'
- Updated both recursive Get-DowserMap calls to pass -IncludeFileCount:$IncludeFileCount
- Updated comment-based help, .PARAMETER, .EXAMPLE, and synopsis to reflect new param name

Why:
- Old implementation ignored active extension/pattern/path filters so count was always all .ps1 files regardless of -IncludeExtensions or -ExcludePathPatterns. New stack-walk uses the same predicates as the display tree so the count matches what is shown.


## [2026.06.30.048] - 2026-06-30
### fix(Get-DowserMap): OS-aware directory separators use [System.IO.Path]::DirectorySeparatorChar on Linux

What changed:
- Changed $folderSuffix else-branch from [string][char]92 to [System.IO.Path]::DirectorySeparatorChar
- Changed $segmentSlash else-branch from [string][char]92 to [System.IO.Path]::DirectorySeparatorChar

Why:
- On Linux the platform separator is / so hardcoded char 92 (backslash) produced wrong output -- folder lines showed \\ instead of /


## [2026.06.30.047] - 2026-06-30
### test(Tests): Sync the test suite with the opt-in alias model and Get-DowserInfo shape for a clean 0-FAIL run

What changed:
- Invoke-DowserTestSuite.ps1 now calls Enable-DowserAliases after import and counts global aliases whose definition targets a *-Dowser* command, instead of counting module-exported aliases (which are always 0 under the opt-in model)
- Replaced the dead 'dfast' alias check with the current 'Invoke-FastSearch' alias; renamed the test to Alias-Invoke-FastSearch
- Fixed the Get-DowserInfo StubInfo test to read .ModuleVersion instead of the nonexistent .Version property, which had been throwing a PropertyNotFoundException to stderr

Why:
- The suite predated changelog 2026.06.29.043, which dropped the auto-loaded d* aliases in favor of opt-in brandless verb-noun aliases registered by Enable-DowserAliases. That left three stale checks: the dfast alias FAIL, the AliasCount WARN (0 exported), and a harness PropertyNotFound crash reading Get-DowserInfo.Version. With these and the earlier Write-Log empty-string fix, the suite now runs 131 PASS / 0 FAIL / 0 WARN / 4 legitimate platform SKIPs.


## [2026.06.30.046] - 2026-06-30
### fix(Write-Log): Allow empty-string messages so blank log spacer lines do not throw

What changed:
- Added [AllowEmptyString()] to the -Message parameter of Write-Log in Private/Write-Log.ps1
- Get-DowserReport (and Compare-DowserReport) emit blank spacer lines via Write-Log "" -Severity Verbose; these now succeed instead of throwing

Why:
- -Message was [Parameter(Mandatory)][string] with no AllowEmptyString, so any Write-Log \"\" threw 'Cannot bind argument to parameter Message because it is an empty string'. Get-DowserReport hits that on every completed scan when logging its summary spacer lines, so the function threw for real callers, not just under test. Allowing empty strings fixes the whole class at the logger. Note: Write-Log here is the single-file copy of the DivergentCortex.Witness logger; mirror this change into Witness to keep the two in sync.


## [2026.06.30.045] - 2026-06-30
### fix(Tests): Apply the legibility fix to the report's Failed Tests table too

What changed:
- Invoke-DowserTestSuite.ps1 now also sets color:#1e1e1e on the Failed Tests table rows (background:#f8d7da), which build separately from the All Test Results rows fixed in 2026.06.30.044

Why:
- The prior fix only touched the All Test Results row generator. The Failed Tests section emits its own light-red rows and still rendered light-gray text on a light fill, leaving the failure details unreadable -- the same contrast bug in a second code path.


## [2026.06.30.044] - 2026-06-30
### fix(Tests): Make the HTML report's All Test Results table legible

What changed:
- Invoke-DowserTestSuite.ps1 now sets color:#1e1e1e on each status-colored result row in the HTML report's All Test Results table

Why:
- The report's dark theme leaves body text light gray (#d4d4d4), but the per-row PASS/FAIL/WARN/SKIP backgrounds are all light colors (#d4edda and friends), so every row was light-gray text on a light fill -- effectively invisible. Forcing dark text on the light rows restores contrast without touching the rest of the dark theme.


## [2026.06.29.043] - 2026-06-29

### feat(aliases): Replace cryptic short aliases with opt-in normalized verb-noun forms

What changed:

- Rewrote Aliases/Aliases.ps1: dropped the d\* short aliases (dfile, dgrep, dtree and friends) in favor of brandless verb-noun aliases (Find-File, Get-Info, Measure-DiskUsage, Get-Tree, and the rest of the 27)
- Aliases are no longer applied on import. They register only when the caller runs the new Enable-DowserAliases function, so a public import never drops generic names into a stranger's session
- Enable-DowserAliases refuses to shadow a builtin (Cmdlet or Application) even with -Force, leaves any other already-taken name alone unless -Force, and is idempotent when an alias is already its own
- Exported Enable-DowserAliases from the manifest and module

Why:

- The old short aliases were a decoder ring, not muscle memory, and auto-exported generic names would squat command names on import. Opt-in normalized forms give the natural names without the module barging into other sessions, and builtins stay protected

## [2026.06.29.042] - 2026-06-29

### chore(manifest): Point ProjectUri at the DivergentCortex org

What changed:

- Dowser.psd1 ProjectUri now reads https://github.com/DivergentCortex/Dowser instead of the personal kizer88 URL, ahead of transferring the repo into the DivergentCortex org alongside Witness

Why:

- The module already brands itself Divergent Cortex in Author and CompanyName; the public home should match, and the canonical URL should be correct before the repo goes public so no stale personal URL is ever the canonical one

## [2026.06.29.041] - 2026-06-29

### test(Tests): Fix platform-guard tests for Write-Log model and add a logging contract test

What changed:

- Fixed the 5 failing tests in Test-DowserPlatformGuards.Tests.ps1. They broke because the logging refactor routes warnings and verbose through Write-Log (console plus log file) instead of PowerShell native Warning/Verbose streams, so -WarningVariable and 4>&1 captured nothing, and dot-sourced functions hit FATAL: No log file path set. The tests now Initialize-Log to a temp log file in BeforeAll (redirecting the module script scope via the module session state) and assert against the log file content instead of the streams
- Added Tests/Test-DowserLogging.Tests.ps1 (14 tests): Initialize-Log creates the dated file and writes the SCRIPT START banner; bare Write-Log lands as type 1 Info always; Write-Log -Severity Verbose is suppressed by default and only written when VerboseLogfile is on (type 4); Write-Log -Severity Warning is always written (type 2); CMTrace wire format markers and time/date fields present; Write-Log throws FATAL when no path is configured
- Full suite now 110 passed, 0 failed (independently re-run)

Why:

- The logging refactor changed where diagnostics go (Write-Log file, not the native streams), so stream-based test assertions no longer saw the messages; the tests had to assert against the log file, and a dedicated logging test was added to lock the Write-Log severity-gating contract

## [2026.06.29.040] - 2026-06-29

### fix(logging): Demote diagnostic Write-Log calls to Severity Verbose so they are off by default

What changed:

- Added -Severity Verbose to every diagnostic/operational Write-Log call across all Public functions and Private helpers; the prior pass had wrongly left them bare (Info), which made them always-on. Verbose severity is suppressed unless the caller runs with -Verbose (Write-Log honors the caller VerbosePreference via its preference bridge)
- Left the per-function Starting/Ending announce lines bare (Info) so a normal run still logs which function ran; left -Severity Warning and -Severity Error untouched (always-on)
- Verified by grep: zero bare Write-Log calls remain anywhere except the Starting/Ending announces; all 33 module files parse clean (AST)

Why:

- Operational traces that were originally Write-Verbose must stay off by default and only surface when the user passes -Verbose; promoting them to Info spammed the console and log on every normal run. Now a default run logs only the announce plus warnings and errors, and -Verbose reveals the full trace

## [2026.06.29.039] - 2026-06-29

### fix(Public): Demote operational diagnostics from always-on Info to Verbose in five Public functions

What changed:

- ConvertTo-DowserBase64.ps1: added -Severity Verbose to 7 bare Write-Log calls (decode/encode path traces, clipboard state, file save confirmation, length report)
- ConvertTo-DowserExe.ps1: added -Severity Verbose to 6 bare Write-Log calls (compile and ConfuserEx operation traces in both ConvertTo-DowserExe and ConvertTo-DowserExeConfuserEx)
- ConvertTo-DowserIco.ps1: added -Severity Verbose to 4 bare Write-Log calls (UNC staging, icon write confirmation, temp cleanup)
- Expand-DowserExe.ps1: added -Severity Verbose to 6 bare Write-Log calls (7-Zip path, extractability check, directory creation, extraction start, extraction count, result detail)
- Test-DowserExtractable.ps1: adding -Severity Verbose to 20 bare Write-Log calls (7-Zip probe, file enumeration, per-file analysis traces, signature matches, native ZIP/CAB probes, 7-Zip oracle results)

Why:

- A prior pass converted Write-Verbose diagnostics to bare Write-Log with no -Severity, making them always-on Info. These are operational step traces, not user-facing outcomes. They must be -Severity Verbose so they are silent by default and only surface when the caller passes -Verbose.

## [2026.06.29.038] - 2026-06-29

### refactor(logging): Route all logging through Write-Log and harden error handling across every script

What changed:

- Converted every native Write-Host, Write-Verbose, Write-Warning, Write-Error, Write-Debug, and Write-Information across all Public functions and Private helpers to Write-Log; Info is the default so normal entries are bare Write-Log, Warning/Error use -Severity, and -Severity Verbose is reserved for genuinely high-volume per-item traces (per-node tree helpers, per-file access-denied, report rows that fire in bulk)
- Verified zero native Write-\* remain anywhere except inside Write-Log.ps1 itself (the logger, which cannot call itself) and two Find-DowserString CBH example strings that search for the literal text 'Write-Host'
- Added Starting/Ending announce lines (bare Write-Log) to every real-work function; trivial pure helpers (ConvertTo-DowserBytes, Format-DowserSize, Get-DowserSortKey) deliberately left untouched to avoid slop
- Hardened error handling to the sandwich pattern: risky operations wrapped in try/catch, catches log the real exception (GetType().Name, ScriptLineNumber, Message) instead of a generic message, empty/silent catch blocks given real Write-Log lines, no nested try/catch
- Write-Progress (UI) and pipeline data output (Write-Output) left intact; logs continue to land in logs/Dowser\_<yyyyMMdd>.log (dated file, already configured by the module loader). All 33 module files parse clean (AST verified)

Why:

- The module mixed native Write-\* cmdlets with gated Write-Verbose, so operational activity and errors were not reliably captured in the log file; routing everything through Write-Log gives one console-plus-file surface by default, and the sandwich error handling ensures real diagnostics reach the log instead of generic or swallowed errors

## [2026.06.29.037] - 2026-06-29

### docs(CBH): Standardize comment-based help across the module with signature in NOTES

What changed:

- Added/repaired comment-based help on Dowser.psm1 and all 26 Public functions plus the 5 Private helpers: one-line SYNOPSIS, NOTES moved to sit immediately under SYNOPSIS, then DESCRIPTION, a PARAMETER entry per parameter, at least one EXAMPLE, and OUTPUTS/INPUTS where applicable
- Placed the Curtis Leggett / Divergent Cortex framed signature block (it is not water they seek, but the truth beneath the trees) in every function's NOTES; real pre-existing metadata (Alias, Source, Ported-from) kept below the signature
- Corrected stale example invocation names (e.g. Find-FileDuplicates -> Find-DowserDuplicate, Find-OrphanFiles -> Find-DowserOrphan) and converted em dashes and double-hyphens in help prose to ASCII
- Verified every module file parses clean and is fully ASCII via the PowerShell AST parser; signature presence confirmed across all files

Why:

- Comment-based help was incomplete or missing on many functions and lacked a consistent author signature; this brings the whole public and private surface to one documented standard with NOTES-under-SYNOPSIS ordering and the house signature, with no logic changes

## [2026.06.29.036] - 2026-06-29

### refactor(Write-Log): Align Write-Log comments and platform-guard tests with the Witness backport

What changed:

- Removed leftover WHAT-narration comments from the Write-Log function body (caller-info, component-priority, and console sections) so it matches the clean comment style of the canonical DivergentCortex.Witness Write-Log
- Updated Test-DowserPlatformGuards.Tests.ps1 to the Witness-aligned helper names: Remove-DowserOldLogFiles -> Clear-LogFile, and Get-ExecutionContextInfo -> Get-PlatformContext with the new platform shape (asserts Platform in Linux/macOS instead of SessionType eq NonWindows)
- Verified via AST parse: no parse errors, all six functions intact

Why:

- The updated Write-Log.ps1 is a single-file backport of DivergentCortex.Witness; its body still carried pre-backport narration comments and the Pester suite still referenced the old helper names, which would fail after the rename

## [2026.06.29.035] - 2026-06-29

### fix(Get-DowserTemplate): Fix phantom process block so the function actually runs on Windows

What changed:

- Wrapped the platform guard in a begin block and moved the $unsupported flag check into the process block
- process { } was previously free-floating code after a bare if, so PowerShell parsed it as a call to a nonexistent process command (AST confirmed ProcessBlock present: False), meaning the COM body never ran and the function threw on Windows
- After the fix the AST reports ProcessBlock present: True with no parse errors; pipeline input declared by the param now binds correctly

Why:

- The function was broken on its target platform: free statements before a process block turn the block into a phantom command call, so the Shell.Application query never executed and Windows callers hit a process-not-recognized error

## [2026.06.29.034] - 2026-06-29

### docs(comments): De-slop inline comments across module scripts, comments-only pass

What changed:

- Write-Log.ps1 (example/gold standard): 38 inline comments de-slopped, killed WHAT-restatement and step-marker narration, rewrote load-bearing comments into house voice, removed a -- double-hyphen in Write-LogFinal
- Public/ scripts (26 files) and Private/ helpers plus Aliases.ps1 swept by parallel agents: pure WHAT-restatement and section-header narration deleted, load-bearing comments rewritten terse lowercase why-not-what
- Converted remaining em dashes in active inline comments to ASCII in Get-DowserMap.ps1 (lines 31, 77, 159) and Get-DowserReport.ps1 (line 63)
- Preserved all banner signature headers, comment-based help blocks, #region and ==== divider lines, and param-block doc comments

Why:

- Comments restating what the code already shows are AI slop and noise; this pass enforces the house comment standard (explain why not what, terse lowercase voice, ASCII only) without any logic, string, or whitespace changes to behavior

## [2026.06.29.033] - 2026-06-29

### chore(go-public): History purge, GitHub hardening, final sanitization pass

What changed:

- Purged from all git history via git filter-repo: .claude/ai_forge/, .claude/settings.json, .firecrawl/, synapse-daemon.log, logs/dashboard.log, Tests/Reports/, resources/exeinfope/, resources/exeinfope.zip (62 commits reduced to 47)
- Expired reflog and ran aggressive GC to remove unreachable objects from local repo
- Sanitized remaining internal path reference in Public/Measure-DowserDirectory.ps1 .NOTES block (replaced raw personal path with generic porting note)
- Enabled Dependabot vulnerability alerts and automated security fixes on GitHub via Caledon MCP
- Secret scanning, private vulnerability reporting, branch protection, CodeQL deferred: require public visibility on free-plan repos

Why:

- Final remediation pass before public visibility flip. History purge removes internal tooling artifacts that should never appear in a public repo. Dependabot provides automated dependency vulnerability monitoring. Remaining GitHub hardening activates at or after the public flip.

## [2026.06.28.032] - 2026-06-28

### chore(go-public): Pre-publication sanitization and repo hardening for open-source release

What changed:

- Removed synapse-daemon.log, logs/dashboard.log, resources/exeinfope/ directory, and resources/exeinfope.zip from working tree
- Untracked Tests/Reports/ via git rm --cached (reports regenerated on each run)
- Expanded .gitignore: added _.log, logs/, .claude/, _.nupkg, .DS_Store, Thumbs.db; removed comment revealing AI tooling
- Removed General_Scripts folder entry from Dowser.code-workspace
- Generated real GUID (64c72862-caae-4d55-9a1f-0d5bf94d3695) replacing placeholder in Dowser.psd1
- Set ProjectUri to https://github.com/kizer88/Dowser in manifest
- Updated Copyright field to MIT license text
- Added MIT LICENSE file at repo root (copyright 2026 Curt Leggett)
- Created root README.md from docs/README.md with adjusted links; removed exeinfope references from project layout
- Removed exeinfope references from docs/README.md and docs/ARCHITECTURE.md
- Replaced hardcoded paths in Tests/Invoke-DowserTestSuite.ps1 and Tests/Test-DowserRunspacePool.ps1 with $PSScriptRoot-relative paths
- Sanitized internal infra names (synapse-sql, SecureCRT share) in .NOTES blocks across Public/\*.ps1
- Replaced 'comprehensive' with concrete language in Get-DowserProperty.ps1 synopsis and verbose output
- Standardized author attribution to 'Curtis Leggett / Divergent Cortex' across all .ps1 files (6 files)
- Replaced Write-Host with Write-Information/Write-Warning in Private/Test-DowserHelpers.ps1 and Tests/Test-DowserRunspacePool.ps1
- Replaced all General_Scripts references with 'standalone scripts' across source and docs
- Redacted CHANGELOG: removed agent names from headings, WSL/runtime_cortex paths, internal process jargon, research tool run IDs; normalized heading format; enforced ASCII throughout

Why:

- Preparing repository for public visibility on GitHub. Removes private infrastructure references, internal tooling names, hardcoded paths, placeholder values, and third-party bundled binaries that should not ship in an open-source release.

## [2026.06.22.031] - 2026-06-22

### fix(Get-DowserMap): -IncludeHidden now shows hidden dirs (.claude etc); -NoDefaultExcludes propagated to recursive calls

What changed:

- Public/Get-DowserMap.ps1, Test-ExcludeFolder (~line 442): added early-return guard -- when -IncludeHidden is active and the item has the Hidden file attribute, return $false immediately, skipping the name-based exclude check. Get-ChildItem -Force was enumerating hidden directories correctly but Test-ExcludeFolder discarded them because names like .claude appeared in $defaultExcludes -> $excludeExact. The two mechanisms had no connection.
- Public/Get-DowserMap.ps1, Test-FolderContainsIncludedFolder (~line 512): applied the same hidden bypass to the inline $excludeExact and $excludeWild checks inside this function -- the only other location where the raw exclude arrays were applied to items without hidden-item awareness.
- Public/Get-DowserMap.ps1, non-ShowFullPathTree recursive call (~line 706): added -NoDefaultExcludes:$NoDefaultExcludes. This parameter was omitted, causing -NoDefaultExcludes to be silently dropped at depth 1 and beyond; default excludes were re-applied to all subdirectories regardless of the flag.
- Public/Get-DowserMap.ps1, ShowFullPathTree recursive call (~line 808): same fix applied to the second recursive call site, which had the same omission.

Why:

- .claude is hardcoded in $defaultExcludes. Test-ExcludeFolder fired after Get-ChildItem -Force enumerated hidden items, then immediately discarded them via $excludeExact -contains $item.Name. -IncludeHidden controlled enumeration and ANSI dimming but never touched the exclude filter -- the two mechanisms were completely disconnected. The hidden bypass in Test-ExcludeFolder threads user intent through: if the user explicitly asked to see hidden items, the name-based default exclude list should not silently discard them. The -NoDefaultExcludes propagation gap was a separate wiring bug: the flag was missing from both recursive call sites so it only applied at the root depth-0 call. .claude remains in $defaultExcludes; normal output without -IncludeHidden is unchanged.

## [2026.06.18.030] - 2026-06-18

### feat(aliases): add missing short aliases for Get-DowserInfo, Compare-DowserReport, New-DowserHiddenFolder

What changed:

- Added Set-Alias dinfo -> Get-DowserInfo in Aliases/Aliases.ps1 under # Get-Dowser\* group
- Added Set-Alias dcompare -> Compare-DowserReport in Aliases/Aliases.ps1 under new # Compare-Dowser\* group (alphabetically first)
- Added Set-Alias dhide -> New-DowserHiddenFolder in Aliases/Aliases.ps1 under new # New-Dowser\* group (between Invoke and Test groups)
- Added Tests/Test-DowserAliasCoverage.Tests.ps1: Pester 5 guard asserting every exported function has at least one alias so this gap cannot recur silently
- Collision check confirmed dinfo, dcompare, dhide were clear of all built-in cmdlets and existing aliases before addition

Why:

- 24 of 27 exported functions had short aliases; Get-DowserInfo, Compare-DowserReport, and New-DowserHiddenFolder had none. The Pester guard prevents future exported functions from shipping without an alias.

## [2026.06.17.029] - 2026-06-17

### docs(index): Add missing Source field to Test-DowserExtractable and Test-DowserIntegrity INDEX entries

What changed:

- INDEX.md: added a Source line to the Test-DowserExtractable entry (Test-DowserExtractable.ps1, with a pointer to exe-static-classification-reference.md for the classification logic)
- INDEX.md: added a Source line to the Test-DowserIntegrity entry (Test-DowserIntegrity.ps1)

Why:

- These were the only two cmdlet entries missing the Source field that the INDEX format block defines and every other entry carries; the gap let a reader miss which Public/ file backs each function. Found during the broader doc-freshness sweep, unrelated to the cross-platform repair reconciliation.

## [2026.06.17.028] - 2026-06-17

### docs(reconcile): Reconcile README/ARCHITECTURE/INDEX to the verified post-repair cross-platform behavior

What changed:

- README.md: export count 26 -> 27 (Compare-DowserReport is now an exported public function); flipped its 'not independently exported' paragraph to 'normal exported public function'; added a Compare-DowserReport row to the function table; renamed the 'Degraded' platform bucket to 'Reduced' and moved Get-DowserOwnership and New-DowserHiddenFolder out of it into Full cross-platform with their real non-Windows behavior; updated New-DowserHiddenFolder purpose row and the Public/ layout line
- ARCHITECTURE.md: described the explicit 27-name Export-ModuleMember + manifest surface and how Compare-DowserReport is named explicitly; renamed Degraded -> Reduced and dropped Get-DowserOwnership from it; added paragraphs on Get-DowserOwnership Unix ownership, New-DowserHiddenFolder dot-prefix hiding (-AttributesOnly warns, no rename), the $IsWindows -ne $false guard idiom (PS 5.1 $null) covering the COM reads, Authenticode, and hidden-folder path; appended an export clause to the one-function-per-file note
- INDEX.md: rebuilt the Platform Support section (Fully Cross-Platform now lists the finders/measurers/Get-DowserOwnership/New-DowserHiddenFolder; Degraded renamed Reduced with Get-DowserOwnership removed and the Get-DowserProperty Authenticode note added); rewrote the Get-DowserOwnership, New-DowserHiddenFolder, ConvertTo-DowserBase64, and Expand-DowserExe entries with current inputs/outputs; flipped the Compare-DowserReport Note to 'exported public function'; corrected the stale Expand-DowserExe output schema (Success/FileCount/ArchiveType/Details) and documented the opt-in -PassThru behavior change
- Verified every claim against current code (Dowser.psd1 27-name FunctionsToExport, Dowser.psm1 Export-ModuleMember, Get-DowserOwnership.ps1, New-DowserHiddenFolder.ps1, ConvertTo-DowserBase64.ps1, Expand-DowserExe.ps1, Get-DowserProperty.ps1) before writing; no forward-looking claims, ASCII only

Why:

- The cross-platform repair pass (slots 2026.06.16.021-.027) changed exported surface and several functions' behavior; the README, ARCHITECTURE, and INDEX still described pre-repair reality (26 exports, Compare-DowserReport unexported, Get-DowserOwnership and New-DowserHiddenFolder as degraded/Windows-attribute-only, stale Expand-DowserExe output schema and always-emit). Stale docs send agents into confident failure, so they ship reconciled with the code in the same window.

## [2026.06.16.027] - 2026-06-16

### fix(manifest): Lock down export surface to an explicit 27-function list and export Compare-DowserReport

What changed:

- Dowser.psd1: replaced FunctionsToExport = @('\*') with an explicit 27-name list (the 26 Public/ basenames plus Compare-DowserReport). The wildcard declared an open-ended public API; the explicit list is the genuine surface and makes the intent auditable.
- Dowser.psm1: changed Export-ModuleMember -Function $Public.BaseName to ($Public.BaseName + 'Compare-DowserReport'). Compare-DowserReport is a real public function dot-sourced inside Get-DowserReport.ps1, so it is not a Public/ basename and was never actually exported; naming it explicitly surfaces it and keeps the psm1 consistent with the manifest (the manifest FunctionsToExport intersects with Export-ModuleMember, so the manifest entry alone would have been inert).
- Get-DowserProperty.ps1 (~line 226): fixed the bare `if ($IsWindows -and $IncludeSignature)` Authenticode-signature guard to `if (($IsWindows -ne $false) -and $IncludeSignature)`. On Windows PowerShell 5.1 $IsWindows is $null, so `$null -and ...` wrongly skipped signature checking on a real Windows platform -- the last instance of the platform-guard bug class. Also converted two pre-existing em-dashes in this file's comments (lines 33, 225) to ASCII.
- Verified by Import-Module -Force + Get-Command -Module Dowser: exported function count goes 26 -> 27 (the +1 is Compare-DowserReport becoming exported as intended); Compare-DowserReport resolves; all internal helpers (ConvertTo-DowserExeConfuserEx, \_Build-DduHtml, \_DduTableHtml, Remove-DowserOldLogFiles, Write-LogFinal, Get-SafeLogIdentity, Get-ExecutionContextInfo, Initialize-Log) confirmed not exported; Compare-Object shows the runtime exported set exactly equals the manifest declaration with no extras either way.

Why:

- FunctionsToExport = @('\*') declared an open-ended public API. While Export-ModuleMember -Function $Public.BaseName already limited the effective runtime surface to the 26 basenames (so no helper actually leaked), the wildcard was misleading and the same gate accidentally excluded Compare-DowserReport, a genuine public function that was always meant to be callable. An explicit, audited export list is the correct hygiene: it documents the real API, surfaces the one missing public function, and keeps internal helpers private by name. The line-226 guard was the final undiscovered instance of the PS 5.1 $null-$IsWindows bug class fixed across the rest of the module.

## [2026.06.16.026] - 2026-06-16

### fix(platform-guards): Audit cleanup: real -PassThru in Expand-DowserExe, Get-DowserProperty guard, stronger 7z test, trim comments

What changed:

- Expand-DowserExe.ps1 (~line 165): fixed dead `if ($PassThru) { $extractResult } else { $extractResult }` where both branches emitted, making -PassThru a no-op. Now implements standard -PassThru semantics: the extraction result object is emitted to the pipeline ONLY when -PassThru is supplied; the default path writes a one-line Write-Verbose summary and emits nothing. BEHAVIOR CHANGE: the function no longer always-emits the result object by default.
- Get-DowserProperty.ps1 (~line 164): converted the bare `if ($IsWindows)` Shell.Application COM guard to the canonical `if ($IsWindows -ne $false)` idiom (same PS 5.1 $null bug class fixed elsewhere -- the bare form skipped the Windows COM path on 5.1). The non-Windows degraded else-branch (verbose 'not available on this platform' then continue to hashing) is unaffected.
- Tests/Test-DowserPlatformGuards.Tests.ps1: strengthened the 7-Zip default-param test from a no-throw-only assertion (which passed even with the old unsafe default) to capturing Test-DowserExtractable's verbose stream and asserting the runtime-bound SevenZipPath resolves to the bare '7z' token and is NOT a 'Program Files'/'7z.exe' Windows path.
- Trimmed the duplicated two-line canonical-guard comment block (identical boilerplate copy-pasted at each guard site) to one concise line per site in ConvertTo-DowserIco.ps1, ConvertTo-DowserExe.ps1 (both guards), Get-DowserTemplate.ps1, and Write-Log.ps1 (both guards).

Why:

- Code review of the Task #2 changeset passed with four cleanup findings. The Expand-DowserExe -PassThru if/else was dead code that made the switch meaningless; standard -PassThru is silent-by-default with opt-in emit, matching the function's ShouldProcess design and the terminal position it occupies in the documented pipeline examples. Get-DowserProperty carried the exact bare-$IsWindows bug class the sweep fixed everywhere else. The 7-Zip test gave false confidence (no-throw passes regardless of the default value). The duplicated guard comments were copy-paste boilerplate flagged by the review.

## [2026.06.16.025] - 2026-06-16

### fix(cross-platform): Audit cleanup: Base64 double-emission, duplicate-output discriminator, trim copy-pasted guard comments

What changed:

- ConvertTo-DowserBase64: fixed double-emission -- when -OutputFile AND -CopyToClipboard are both set and the clipboard fails (headless), the function no longer emits the base64 blob to the pipeline (the file is the destination); the pipeline fallback now fires only when no -OutputFile was given. Added a Pester case asserting file-written + pipeline-empty under that combination
- Find-DowserDuplicate: added an OutputType discriminator ('ModeSummary' / 'TopSets') to each emitted summary object so the two different shapes are distinguishable and Export-Csv no longer silently drops columns
- Trimmed the copy-pasted 2-line canonical-guard comment to one concise line at each guard site in Get-DowserOwnership.ps1 and New-DowserHiddenFolder.ps1 (idiom unchanged)
- Full Pester suite now 92/92

Why:

- Code review of Task #1 passed with three findings: a confirmed double-emission defect introduced by the clipboard guard, an output-shape ambiguity in Find-DowserDuplicate, and duplicated verbose guard comments (copy-paste boilerplate). These remediate all three before T1 closes.

## [2026.06.16.024] - 2026-06-16

### fix(cross-platform): Find-DowserOrphan output hygiene and ASCII-clean comments in owned Linux-fix files

What changed:

- Find-DowserOrphan: routed the tail Format-Table preview to Write-Verbose via Out-String so the function returns only clean FileInfo objects (no Format-Table formatting records leaking into the pipeline) -- same output-hygiene class as the Find-DowserDuplicate fix
- Converted 3 pre-existing non-ASCII em-dashes to -- in comment/help text only (Get-DowserOwnership.ps1 synopsis line, New-DowserHiddenFolder.ps1 .PARAMETER AttributesOnly and .NOTES Source) so the owned files are uniformly ASCII-clean
- Added Pester assertion that Find-DowserOrphan returns FileInfo objects with no format-record pollution; full suite now 91/91

Why:

- Folding the two known items flagged during review into this pass before the code review: the Format-Table-at-tail polluted Find-DowserOrphan's FileInfo return, and the em-dashes broke the module's ASCII-only source standard.

## [2026.06.16.023] - 2026-06-16

### fix(cross-platform): Fix Linux-behavior, path-separator, and output-silence defects across nine Public cmdlets

What changed:

- Get-DowserOwnership: deleted stray [System.IO.DirectoryInfo]$Directory pipeline-leak; guarded Shell.Application COM behind the canonical Windows branch and added a Unix fallback that populates Owner/Group/UnixMode + PlatformNote from .NET FileInfo so ownership returns real data on Linux instead of an empty object
- New-DowserHiddenFolder: added the non-Windows branch -- dot-prefix the folder leaf for true Linux hiding (Verbose note that NTFS Hidden/System is Windows-only); under -AttributesOnly warn-only with no rename; re-Get-Item after any rename and return the real on-disk Attributes + PlatformNote (never a claimed Hidden,System value)
- ConvertTo-DowserBase64: removed the function-body $ErrorActionPreference='Stop' scope leak (rely on per-cmdlet -ErrorAction); no-destination branch now Write-Output the base64 string instead of Write-Verbose; Set-Clipboard guarded for headless/no-display sessions, warning and emitting to the pipeline instead of throwing
- Measure-DowserDirectory: replaced backslash interpolation with Join-Path so the immediate child FileCount is correct on Linux (was always 0)
- Measure-DowserDiskUsage: the isRoot reparse-point check now uses $dirComparer instead of forced OrdinalIgnoreCase, for case-sensitivity consistency on Linux
- Find-DowserOrphan: directory exclusion now matches both path separators so exclusions work on Linux
- Find-DowserDuplicate: $modeSummary and $topSets are now emitted as objects via Write-Output (Format-Table output routed to Write-Verbose) so callers can capture them
- Find-DowserDependency: default $ExcludePaths is now platform-aware (Windows defaults vs Linux /proc,/sys,/dev,/usr,/.git) instead of Windows-only backslash paths that silently never matched on Linux
- Get-DowserMap: internal path filtering/comparison now uses the platform separator via ConvertTo-NativeSeparator (replacing ConvertTo-BackslashPath) so Get-ChildItem -LiteralPath calls and include-folder traversal work on Linux; ConvertTo-WslPath keeps local backslash normalization; segment splits use [\\/]; the symlink render feature is preserved (verified)
- Added Tests/Test-DowserLinuxBehavior.Tests.ps1 (Pester 5) covering all of the above; full suite passes 90/90

Why:

- A cross-platform sweep found these cmdlets producing silent false success, empty/zero output, or pipeline-only-to-Write-Verbose results on non-Windows PowerShell 7; this fixes the Linux behavior while keeping Windows behavior unchanged via the PS5.1-safe canonical $IsWindows guard.

## [2026.06.16.022] - 2026-06-16

### fix(platform-guards): Make Test-DowserIntegrity Pester suite run on pwsh 7 and convert remaining non-ASCII in owned files

What changed:

- Tests/Test-DowserIntegrity.Tests.ps1: replaced the corrupt-EXE fixture write `[byte[]](...) | Set-Content -Encoding Byte` (the Byte encoding name was removed in PowerShell 6+, so the BeforeAll threw and the whole suite failed at setup on pwsh 7) with the version-agnostic `[System.IO.File]::WriteAllBytes($path, [byte[]](...))`; the suite now runs and passes 11/11 on pwsh 7
- Get-DowserTemplate.ps1, Get-DowserTopology.ps1, Private/Write-Log.ps1: converted pre-existing non-ASCII characters in comments and comment-based help to ASCII (em-dash -> --, smart double-quotes -> straight quotes); comment/help text only, no logic touched; these three owned files are now ASCII-clean

Why:

- Folded in two pre-existing issues surfaced during the Task #2 platform-guard sweep that fall inside the full cross-platform scope and live in files this change already owns. The `Set-Content -Encoding Byte` idiom is Windows-PowerShell-5.1-only and broke the integrity test suite at fixture setup on pwsh 7, masking real coverage; WriteAllBytes is correct on both 5.1 and 7+. The module is meant to be ASCII-clean and these em-dashes/smart quotes were the only non-ASCII bytes left in the files touched by this task.

## [2026.06.16.021] - 2026-06-16

### fix(platform-guards): Fix PS 5.1 platform-guard bugs and Windows-only function guards across 7 Public files and Write-Log

What changed:

- ConvertTo-DowserIco.ps1: converted the bare `if (-not $IsWindows)` guard to the canonical `if ($IsWindows -eq $false)` idiom (was firing wrongly on PS 5.1 where $IsWindows is $null); removed the dead user32.dll DestroyIcon P/Invoke block (compiled via Add-Type but never called)
- ConvertTo-DowserExe.ps1: converted the ConvertTo-DowserExe guard to the canonical idiom; added a platform guard to ConvertTo-DowserExeConfuserEx (previously unguarded); guarded both `Add-Type -OutputType ConsoleApplication` compile calls behind a PSVersion < 6 check so they no longer throw on pwsh 7, failing clean with a clear 'requires Windows PowerShell 5.1' warning instead
- Get-DowserTemplate.ps1: converted the bare `if (-not $IsWindows)` Shell.Application guard to the canonical idiom
- Test-DowserExtractable.ps1, Test-DowserIntegrity.ps1, Expand-DowserExe.ps1: made the $IsWindows-driven default-parameter expressions for -SevenZipPath (and the $expandExe begin-block assignments) 5.1-safe using `if ($IsWindows -eq $false) { '7z' } else { <Windows path> }` so a standalone 5.1 host resolves the Windows 7-Zip/expand.exe path rather than the bare PATH names
- Get-DowserTopology.ps1: guarded the -InColor PSAnsiFileMap colorization setup behind a PSVersion >= 7 check; on 5.1 it now warns and renders uncolorized instead of null-ref crashing on the PS7-only $global:PSAnsiFileMap
- Private/Write-Log.ps1: converted the two bare $IsWindows guards (Get-SafeLogIdentity, Get-ExecutionContextInfo) to the canonical idiom; renamed the unapproved-verb Cleanup-LogFiles to Remove-DowserOldLogFiles and updated both internal call sites (Write-Log auto-cleanup, Write-LogFinal); replaced two `Get-Variable -Name logfilepath -ValueOnly` lookups with the already-resolved $Logfile param (Write-Log dir creation) and the $LogFilePath param default (Initialize-Log)
- Tests/Test-DowserPlatformGuards.Tests.ps1: new Pester 5 suite (10 tests) covering Windows-only graceful-skip on non-Windows, the ConfuserEx guard returning before the throwing Add-Type, Get-DowserTopology -InColor not crashing, and the Cleanup-LogFiles -> Remove-DowserOldLogFiles rename

Why:

- The cross-platform sweep found platform guards written as bare `if ($IsWindows)` / `if (-not $IsWindows)`, which misfire on Windows PowerShell 5.1 where $IsWindows is $null: the negated form treats 5.1 as non-Windows and skips the Windows code path. The canonical `-ne $false` / `-eq $false` idiom is correct on 5.1 ($null), Windows pwsh ($true), and Linux/macOS ($false). Separately, Add-Type -OutputType was removed in PowerShell 6+, so the EXE compilers threw on pwsh 7 even on Windows, and the -InColor path null-ref crashed on 5.1 because PSAnsiFileMap is PS7-only. Cleanup-LogFiles used an unapproved verb that trips PSScriptAnalyzer and the upcoming manifest export lock-down.

## [2026.06.14.020] - 2026-06-14

### docs(project-wide): Reconcile docs to 26-function surface; fix README/INDEX/ARCHITECTURE; fold and de-slop changelog 019

What changed:

- README.md: added the missing Measure-DowserDiskUsage row, corrected the function count from 25 to 26 (matches Public/ file count), rewrote the Compare-DowserReport note to state accurately that it is dot-sourced with Get-DowserReport but not an independently exported member, expanded the platform-support section, and added a Measure-DowserDiskUsage quick-start example
- INDEX.md: added the missing Find-DowserString entry (a headline function that had no entry), and recharacterized Compare-DowserReport to note it is not an independent export
- ARCHITECTURE.md: corrected Public/ function count from 25 to 26
- CHANGELOG.md: consolidated the Get-DowserMap symlink-render feature and its same-day regression fix (originally two adjacent same-day entries) into the single 2026.06.14.019 feat entry, since the fix corrected a defect introduced earlier the same day with no release between them; trimmed the combined entry to standard length and removed internal references (line numbers, internal variable names, implementation noise). The 2026.06.14.020 slot freed by that consolidation is reused by this documentation-reconciliation entry.

Why:

- Docs had drifted behind the code: the README undercounted functions and omitted Measure-DowserDiskUsage, INDEX was missing Find-DowserString, and both treated Compare-DowserReport ambiguously. The symlink-feature changelog entry was roughly 3x normal length and carried implementation noise and internal references that mean nothing to a reader; its same-day regression fix corrected unshipped code from the same feature, so the two belong as one entry (2026.06.14.019) rather than separate historical events.

## [2026.06.14.019] - 2026-06-14

### feat(Get-DowserMap): Detect and show symlinks as a two-line block instead of silently skipping them

What changed:

- Symlinks and reparse points are now rendered in place as a two-line block (name line, then a target line) instead of being silently dropped from the tree. Default behavior shows the link without descending into it; -FollowReparse descends as if the link were a normal folder.
- Added link glyphs: name marker U+2192 and target marker U+21B3, with ASCII fallbacks (> and ~) under -Ascii and HTML entities under -AsHtml, matching the existing glyph convention.
- Broken or dangling links (no resolvable target) render with a "(broken link)" placeholder on the target line.
- Symlink rendering works in all three output modes (console, -AsHtml, -AsMarkdown) and on both the default and -ShowFullPathTree render paths.
- Added a LinkCount field to traversal state; it appears in -EmitSummary output when at least one link is shown.
- Added Tests/Get-DowserMap.Tests.ps1 (Pester 5): covers the name and target lines, no-descend default, continuation bar on non-last children, -FollowReparse descent, and -AsHtml entity output. The suite skips on platforms where symlink creation is not permitted.

Why:

- The tree silently dropped symlinks, making them invisible in the output. Showing them as a two-line block (name / target) lets users see what links exist and where they point without the tree recursing into them, while -FollowReparse remains available for callers who want to descend.

## [2026.06.07.018] - 2026-06-07

### fix(Measure-DowserDiskUsage): Fix treemap double-count, symlink root skipped, case-sensitive dir keys on Linux

What changed:

- Fix #1 (Linux case-sensitive dir keys): $dirSizes now uses Ordinal comparer on non-Windows (where $IsWindows -eq $false) and OrdinalIgnoreCase on Windows/PS-5.1 ($IsWindows is $null on 5.1, treated as Windows); ancestor-walk stop test updated to use the same comparer via $dirComparer.Equals(); Phase 2 root-exclusion filter also updated to use $dirComparer.Equals() -- prevents sibling dirs Foo/foo collapsing to one key on Linux and prevents the ancestor loop overshooting on case-diverged paths
- Fix #2 (symlink/reparse root dropped): reparse-point skip guard now checks $isRoot first and only skips descendant reparse points, so a symlink or junction passed as -Path is scanned correctly rather than silently returning empty results
- Fix #3 (treemap double-count + proportionality): treemap rebuilt from IMMEDIATE children of root only (keys in $dirSizes whose GetDirectoryName == resolvedRoot), producing a non-overlapping partition with no double-counting; widths = SizeBytes / TotalBytes \* 100 so area is honestly proportional to real disk usage; a remainder block (ddu-remainder class) covers root-level files and any items beyond TopN; $dirSizes and $dirComparer passed into \_Build-DduHtml for this computation
- Tests: all Join-Path paths use nested form for cross-platform correctness; added extensionless file noext and <none> extension assertions; added treemap-proportionality assertions (block widths sum to ~100%, largest block >= 98%, remainder block present); added symlink-root test (skipped on Windows or when symlink creation is not permitted)

Why:

- Code review identified three real defects: the treemap drew overlapping nested dirs producing misleading area proportions, a symlinked root was silently skipped producing empty results, and $dirSizes used OrdinalIgnoreCase on case-sensitive Linux filesystems causing sibling dirs with different casing to merge into one bucket

## [2026.06.07.017] - 2026-06-07

### feat(Measure-DowserDiskUsage): Add Measure-DowserDiskUsage (ddu) -- WinDirStat-style recursive disk-usage report with HTML treemap

What changed:

- Created Public/Measure-DowserDiskUsage.ps1: recursive directory scan, biggest-dirs rollup ranked by size, biggest-files ranking, by-extension aggregation; all size strings via Format-DowserSize
- Added -ExportHtml: self-contained HTML report with slice-and-dice treemap (block area proportional to disk usage), three ranked tables, dark palette matching Get-DowserReport.ps1 (#1e1e1e, #569cd6, #4ec9b0)
- Added -MinSize filter (parsed by ConvertTo-DowserBytes), -ExcludePath for skipping named dirs, -TopN (default 15)
- Created Tests/Measure-DowserDiskUsage.Tests.ps1: temp tree with known byte sizes; asserts total, dir-rollup order, file-ranking order, extension aggregation, HTML treemap markup and palette colors
- Added Set-Alias ddu Measure-DowserDiskUsage to Aliases/Aliases.ps1
- Added full INDEX.md entries for Measure-DowserDiskUsage and the previously platform-table-only Measure-DowserDirectory

Why:

- User has directories ballooning to tens of GB and needs a WinDirStat-style 'what is eating my space' answer built into Dowser; Measure-DowserDirectory covers immediate subdirs only with no ranking, no extension breakdown, and no HTML output

## [2026.06.07.016] - 2026-06-07

### docs(project-wide): Full documentation pass: rewrite README, ARCHITECTURE; fix INDEX; archive spent artifacts

What changed:

- README.md rewritten: removed stale Windows D:\ import path, added project description, quick start examples, full exported function table with aliases, platform support section, accurate project layout
- ARCHITECTURE.md rewritten: added executive summary, private helper inventory, parallelism model, platform support model, design decisions with rationale (switch vs bool, tilde resolution, pattern auto-wrap, Write-Information for banners), removed stale 'cross-platform is out of scope' claim
- INDEX.md: added missing Get-DowserInfo entry, fixed truncated Expand-DowserExe entry (completed outputs, related, source, aliases fields)
- Archived spent working artifacts to .archives/\_archive.zip: PORTING_OUTLINE.md (porting complete at 21/21), docs/superpowers/plans/2026-05-24-cross-platform-compat.md (plan fully implemented), DOWSER_PROJECT_OUTLINE.md (superseded by README + ARCHITECTURE)
- Created .gitignore with entries for .archives/, Tests/Reports/, .firecrawl/

Why:

- Documentation was stale: README had hardcoded Windows paths and no function inventory, ARCHITECTURE claimed cross-platform was out of scope (contradicted by changelog 013), INDEX was missing Get-DowserInfo and had a truncated Expand-DowserExe entry, and three spent design artifacts cluttered the docs surface

## [2026.06.04.015] - 2026-06-04

### fix(module-wide): Fix [switch] defaults, pattern matching, and silent error swallowing across 7 functions

**Bug class 1: `[switch]$Param = $true` silently ignored (7 params across 5 files)**

PowerShell `[switch]` parameters ignore `= $true` defaults -- they always evaluate as `$false` unless the caller explicitly passes the flag. Changed to `[bool]` in all affected parameters:

- `Find-DowserFile.ps1`: `$Recurse`, `$UseRunspaces`
- `Find-DowserModified.ps1`: `$Recurse`
- `Find-DowserRecentLog.ps1`: `$Recurse`
- `Find-DowserScript.ps1`: `$Recurse`
- `Get-DowserMap.ps1`: `$UseRunspaces`
- `Get-DowserReport.ps1`: `$UseRunspaces`

Impact: all of these functions silently ran non-recursive / single-threaded unless the caller explicitly passed `-Recurse` or `-UseRunspaces`, despite docs and intent saying "default $true".

**Bug class 2: Pattern parameters require exact filename match (2 files)**

`-Pattern` passed raw to `Get-ChildItem -Filter`, which requires exact wildcard syntax. A bare string like `cortex-mcp` matched nothing unless a file was named exactly that. Added auto-wrap: bare strings without `*` or `?` get wrapped in `*...*` before being passed to `-Filter`.

- `Find-DowserFile.ps1`: auto-wrap in `begin` block
- `Get-DowserReport.ps1`: auto-wrap in `begin` block

**Bug class 3: Silent error swallowing producing wrong results (3 files)**

- `Find-DowserOrphan.ps1`: `Get-Content -ErrorAction SilentlyContinue` bypassed the existing try/catch, making unreadable scanner files invisible. Files only referenced in unreadable files would be false-positive orphans. Changed to `-ErrorAction Stop` so the catch block fires and emits `Write-Warning`.
- `Find-DowserString.ps1`: empty catch in worker runspace scriptblock silently swallowed read failures. Added error sentinel row (`Pattern = '[READ-ERROR]'`) so callers can distinguish "no matches" from "could not read file".
- `Get-DowserMap.ps1`: four empty `catch { }` blocks in annotation helpers and cache builders (size measurement, PS1 count, match-cache scan, include-folder scan). Failed measurements rendered as 0 or $false silently. Added `Write-Verbose` to all four so failures surface with `-Verbose`.

## [2026.06.02.014] - 2026-06-02

### fix(path-resolution): Fix tilde (~) path resolution for .NET System.IO API calls across 4 modules

What changed:

- Find-DowserString: resolve $Path via Resolve-Path before [System.IO.File]::Exists and [System.IO.Directory]::EnumerateDirectories -- fixes -Recurse reporting 1 directory for ~/paths
- ConvertTo-DowserBase64: replace [System.IO.Path]::GetFullPath with GetUnresolvedProviderPathFromPSPath for $OutputFile -- GetFullPath does not expand tilde
- ConvertTo-DowserIco: resolve $OutputFile via GetUnresolvedProviderPathFromPSPath before [System.IO.File]::Open
- Write-Log: resolve $Logfile via GetUnresolvedProviderPathFromPSPath before [System.IO.File]::WriteAllText and System.IO.FileStream

Why:

- PowerShell tilde (~) is shell-only expansion; .NET static methods receive the literal string and silently fail or write to wrong locations. Audited all 31 files in Public/ and Private/ -- these 4 were the only affected modules.

## [2026.05.24.013] - Cross-Platform Compatibility

### Added

- Platform detection in Dowser.psm1 (defines $IsWindows/$IsLinux/$IsMacOS for PS 5.1 compatibility)
- Platform guards on Windows-only functions: ConvertTo-DowserIco, ConvertTo-DowserExe, Get-DowserTemplate
- Graceful degradation for COM-dependent Get-DowserProperty on non-Windows
- Cross-platform identity resolution (Get-SafeLogIdentity) in Write-Log
- Platform-aware 7-Zip defaults (uses PATH-based '7z' on Linux/macOS)
- CompatiblePSEditions = @('Desktop', 'Core') in module manifest
- Tests/Test-DowserCrossPlatform.Tests.ps1 test suite
- Platform Support section in docs/INDEX.md

### Fixed

- Module import failure on Linux caused by System.Drawing assembly load at file scope in ConvertTo-DowserIco
- Backslash path literal in Get-DowserInfo that failed path resolution on Linux
- WindowsIdentity calls in Write-Log that are unavailable on non-Windows platforms
- Hardcoded Windows paths for 7-Zip and expand.exe in Expand-DowserExe, Test-DowserExtractable, Test-DowserIntegrity
- 3-argument Join-Path in Dowser.psm1 that broke PS 5.1 (replaced with nested 2-argument calls)

### Changed

- Dowser.psm1 uses Join-Path for all internal path construction (cross-platform safe)
- ModuleVersion bumped from 0.1.0 to 0.2.0
- Module description updated to note cross-platform support

## [2026.05.04.012] - 2026-05-04 -- Find-DowserString: single-file mode

### Fixed

- `Public/Find-DowserString.ps1` - When `-Path` is a file (not a directory), the function
  now short-circuits the directory enumeration and runspace-based file gathering and
  searches that single file directly. Previously the file path was fed into Phase 2's
  `Get-ChildItem -Path $dir -File` running inside a runspace that did not always inherit
  the caller's mapped drives (e.g. H:), silently returning zero files and emitting
  "No matches found" against files that obviously contained matches.
- Mapped-drive paths are resolved to their provider path up front so Phase 3 worker
  runspaces can read them reliably.

### Added

- New `OutputMode = 'singlefile'` (auto-selected when `-Path` is a file and `-OutputMode`
  was not explicitly set). Emits one header (file path, patterns, total match count,
  unique line count) followed by up to 25 sample matches as `lineNumber: truncated-line`,
  with whitespace collapsed and content clipped at 160 chars. Tail line indicates how
  many additional match rows exist if the cap was hit.

## [2026.04.29.011] - 2026-04-29 -- Find-DowserString: grouped output mode (new default)

### Changed

- `Public/Find-DowserString.ps1` - Output reorganized to group results by parent directory.

  Was: default `OutputMode = 'counts'` emitted one PSCustomObject per file. PowerShell's
  default table formatter then truncated the FilePath column on long paths,
  producing rows like:

      \\some-host\...\deep\nested\path\comm...
      \\some-host\...\deep\nested\path\comm...

  with the same parent dir repeated and the actual filename clipped.

  Now: new `OutputMode = 'grouped'` is the default. Output is text (Write-Output strings),
  formatted as a directory header with files listed underneath:

      C:\Projects\SomeApp\dist  (5 files, 14 matches)
          commands-registry-BKukdIJg.js                         [   1]  line 584
          commands-registry-DaH1KNEE.js                         [   1]  line 544
          pi-embedded-CblkcCno.js                               [   6]  lines 41772, 42016, 42032, 42044, 42050, 42058

      C:\Projects\SomeApp\dist\plugin-sdk  (2 files, 7 matches)
          commands-registry-DfTR18y4.js                         [   1]  line 584
          reply-BbVFaxrJ.js                                     [   6]  lines 43591, 70345, 79000, ...

  Filenames left-padded to widest in each group, clamped 30..80 chars.
  Line numbers truncate to first 8 with `(+N more)` suffix when over.

### Breaking

- The default `OutputMode` changed from `counts` to `grouped`. Pipeline consumers that
  relied on the object stream (`Find-DowserString ... | Where-Object MatchCount -gt 5`)
  must now pass `-OutputMode counts` explicitly. The `counts` mode itself is unchanged.

### Added

- `OutputMode = 'grouped'` value added to ValidateSet. Comment-based help for
  `-OutputMode` updated to describe all four modes including defaults.

---

## [2026.04.29.010] - 2026-04-29 -- Find-DowserString: phase banners + streaming directory enumeration

### Changed

- `Public/Find-DowserString.ps1` - 3-phase status model with immediate visible feedback.

  Was: a blocking `Get-ChildItem -Directory -Recurse -Force` that ran silently before any
  progress could fire. On large trees (e.g. AppData\Roaming\Code - Insiders) this looked
  frozen for tens of seconds because Write-Progress had no chance to render until the
  recursive enum returned.

  Now:
  - Phase 1/3: Directory enumeration via streaming
    `[System.IO.Directory]::EnumerateDirectories` stack-walk.
    - Write-Progress fires before any directory I/O begins.
    - Updates throttled to ~5 Hz with running directory count and current branch leaf.
    - Excluded folders (`.git`, `node_modules`, `bin`, `obj` by default) pruned at
      branch level - we never descend into them, where the prior code walked them and
      filtered after. Net win on speed for repos and AppData trees.
    - Access-denied / reparse / vanished dirs swallowed silently as before.
  - Phase 2/3: File gathering. Existing runspace pool retained; ProgressStatus
    relabeled `Phase 2/3: Gathering files`.
  - Phase 3/3: String searching. Existing runspace pool retained; ProgressStatus
    relabeled `Phase 3/3: Searching files`.

  Per-phase banner via `Write-Information -InformationAction Continue` so the user
  sees a labeled status line at the start and end of each phase regardless of
  `$ProgressPreference`. Format:

      [Find-DowserString] Phase 1/3: Enumerating directories under '<path>'
      [Find-DowserString] Phase 1/3: Found N directories in Xs
      [Find-DowserString] Phase 2/3: Gathering files in N directories
      [Find-DowserString] Phase 2/3: Matched N files in Xs
      [Find-DowserString] Phase 3/3: Searching N files for K pattern(s)
      [Find-DowserString] Phase 3/3: Done. M match rows from N files in Xs

  No new files. No new helpers. No public-API surface change. `-Verbose` still works
  for the existing diagnostic stream; the new banners are independent of it.

### Notes

- Write-Information chosen over Write-Host to respect Dowser's `[FORBIDDEN] Write-Host
in public functions` rule from project CLAUDE.md. The forced `-InformationAction
Continue` makes the messages visible without polluting the function's output stream.

---

## [2026.04.21.009] - 2026-04-21 -- Corrupted File Detection (Test-DowserIntegrity)

### Added

- `Public/Test-DowserIntegrity.ps1` - Layered file-corruption detection.
  Dispatches by category to the strongest available validator; never one magic test.

  Detection tiers:
  - Zero-byte check (all files, high confidence)
  - Archive category (.zip, .7z, .rar, .cab, .msu, .tar, .gz, .bz2, .xz, .wim, .msi,
    .iso, .nupkg, .jar, .apk, etc.): 7-Zip `7z t` when available (definitive,
    non-zero exit = corrupt). Falls back in order to:
    native `[System.IO.Compression.ZipFile]` full-stream read for ZIP family,
    `expand.exe -D` for CAB/MSU, OLE compound-file magic for MSI, then read-access probe.
  - PE category (.exe, .dll, .sys, .ocx, .drv, .scr, .cpl, .ax, .efi, .mui):
    MZ header, e_lfanew bounds, PE signature, COFF sanity (1..96 sections),
    Optional Header magic (0x10B / 0x20B / 0x107), section-table bounds, and
    per-section rawOffset + rawSize must not exceed file length. Catches truncation,
    header overwrites, and malformed SFX stubs.
  - Generic files: first + last 512-byte read-access probe.

  Hygiene scan (always on, added to address SCCM source-package pain):
  - Hidden / System attribute detection
  - Zone.Identifier ADS (Mark-of-the-Web) - the classic blocker that makes SCCM
    or Windows refuse to distribute/execute content
  - Any other alternate data stream
  - Residue filename patterns: Thumbs.db, desktop.ini, .DS*Store, .*_, ~$_,
    _.tmp, _.bak, _.orig, _.swp, _.swo, _.lock, _.partial, _.crdownload, \*.part
  - Any hygiene finding on an otherwise-OK file flips Status to `Residue`.

  Optional features:
  - SHA256 hashing via `-ComputeHash`.
  - Baseline drift detection via `-BaselineCsv` (expects RelativePath, Length, SHA256).
    Implies `-ComputeHash`. Size / hash / missing entries flip Status to Suspicious.

  Output modes:
  - Default: emits a single summary PSCustomObject (TotalFiles, per-Status counts,
    ProblemCount, TopProblems[10], DetailsGlobal pointer). The full per-file array is
    always stashed in `$global:DowserIntegrityDetails` for interactive drill-down.
  - `-Detailed`: streams per-file PSCustomObjects (Path, RelativePath, Name, Extension,
    SizeBytes, Size, Category, Status, Method, Confidence, SHA256, BaselineMatch,
    Details, Issues[]). Defaults to problems-only (Corrupt / Error / Warning / Suspicious);
    `-IncludeClean` adds OK and Unverified.

  Parameters: `-Path` (pipeline, FullName), `-Recurse`, `-Filter`, `-SevenZipPath`,
  `-SkipSevenZip`, `-ComputeHash`, `-BaselineCsv`, `-Detailed`, `-IncludeClean`.

- `Aliases/Aliases.ps1` - Added: `dintegrity`, `dinteg` -> Test-DowserIntegrity.
- `docs/INDEX.md` - Added entry for Test-DowserIntegrity.
- `Tests/Test-DowserIntegrity.Tests.ps1` - Pester smoke suite (see below).

---

## [2026.04.15.008] - 2026-04-15 -- Canonical EXE Static-Analysis Reference

### Added

- `docs/exe-static-classification-reference.md` -- Canonical merged technical reference for static
  classification of Windows .EXE files as Extractable vs Requires Decompilation.
  Merges two independent research outputs covering the same domain from different angles.
  Covers: hex signatures for ZIP/7z/CAB/RAR/WIM/GZIP/BZIP2/ZSTD/LZMA; installer framework
  fingerprints for NSIS/Inno/InstallShield/WiX/AdvancedInstaller/IExpress/WinRAR SFX/7z SFX;
  script-to-EXE detection for ps2exe/AutoIt/AutoHotkey/PyInstaller/cx_Freeze/Nuitka/pkg/Electron/
  Go/Rust; .NET COM_DESCRIPTOR byte offsets; 7z Type= complete reference; Windows built-in
  detection methods (FileVersionInfo, ZipArchive, expand.exe, ReflectionOnlyLoadFrom,
  MetadataLoadContext); PE header analysis (imports, sections, characteristics); decision matrix
  and master PowerShell classification function; source citations to 16+ primary sources;
  Appendix A quick-reference hex table; Appendix B evidence map and conflict resolutions.
  Key conflicts resolved: PyInstaller magic corrected to `4D 45 49 0C 0B 0A 0B 0E` (from source);
  NSIS deadbeef clarified as `EF BE AD DE` (little-endian on disk); WiX Burn covered with both
  `.wixburn` section AND `WIXBURN_MANIFEST` resource; Advanced Installer adds CompanyName "Caphyon".
  All claims labeled HIGH_CONFIDENCE or HEURISTIC. Document: 2353 lines, ~107 KB.

---

## [2026.04.15.007] - 2026-04-15 -- EXE Extractability Detection + Extraction

### Added

- `Public/Test-DowserExtractable.ps1` - Tests whether an EXE is simply extractable or requires decompilation.
  Multi-tier detection: PE header analysis (.NET COM_DESCRIPTOR), VersionInfo fingerprinting
  (ps2exe, NSIS, Inno Setup, InstallShield, WinRAR SFX, 7-Zip SFX, WinZip SFX, AutoIt, etc.),
  7-Zip oracle (`7z l` output parsing for Type field and payload classification), and magic byte
  scanning (ZIP, 7z, CAB, RAR signatures + ZIP EOCD backward scan). Classifies into Extractable,
  ResourcesOnly, or DecompileRequired with confidence levels. Accepts pipeline input, directory
  scanning with -Recurse, and UNC paths.
- `Public/Expand-DowserExe.ps1` - Extracts files from extractable EXEs using 7-Zip.
  Runs Test-DowserExtractable first to verify, then `7z x` to extract. ShouldProcess support
  (-WhatIf, -Confirm). Auto-creates destination folder named `<ExeName>_extracted`. -Force for
  overwrite. Pipes naturally from Test-DowserExtractable output.
- `Aliases/Aliases.ps1` - Added: `dtest`/`dtestexe` for Test-DowserExtractable,
  `dexpand`/`dextract` for Expand-DowserExe.
- `docs/INDEX.md` - Added entries for both new cmdlets.

### Fixed

- `Public/Invoke-DowserNumericSort.ps1` - Replaced `"$wordToComplete*"` with
  `($wordToComplete + '*')` in Register-ArgumentCompleter to avoid potential string
  terminator parse errors from non-ASCII characters.
- `Public/Invoke-DowserNumericSort.ps1` - Replaced em-dash (U+2014) with ASCII
  hyphen in .NOTES comment block.

---

## [2026.04.12.006] - 2026-04-12 -- Invoke-DowserTestSuite interactive path fallback + ASCII sweep

### Fixed

- `Tests/Invoke-DowserTestSuite.ps1` - Fixed param default path resolution when run outside script context.
  Replaced `$PSScriptRoot`-based defaults with `$PSCommandPath` fallback chain (`$MyInvocation.MyCommand.Path` -> `Resolve-Path '.'`) for:
  - `ModulePath` (line 38)
  - `ReportDir` (line 40)
    This eliminates `Split-Path` empty-string failures in interactive runs.
- `Tests/Invoke-DowserTestSuite.ps1` - Replaced all non-ASCII horizontal separator lines with ASCII `-` separators (26 lines).

### Verification

- Syntax check: `SYNTAX_PASS` (PS parser, 0 errors).
- Suite rerun: `pwsh -NoProfile -File Tests/Invoke-DowserTestSuite.ps1 -SkipSlow`
  -> `Total=131 PASS=112 FAIL=0 WARN=15 SKIP=4` and `ALL PASS (zero FAILs)`.
- Non-ASCII audit: `rg -nP "[^\\x00-\\x7F]" Tests/Invoke-DowserTestSuite.ps1 | wc -l` -> `0`.

---

## [2026-04-12] - Unicode Em Dash Purge

### Fixed

- `Tests/Invoke-DowserTestSuite.ps1` - Replaced all 13 Unicode em dashes (U+2014) with ASCII hyphen "-".
  Operator directive: ASCII only, no Unicode punctuation anywhere.
  Affected lines: 4, 12, 120, 319, 513, 540, 547, 549, 558, 560, 569, 655, 657.
- `Tests/Reports/*.csv` and `*.html` (12 files) - Replaced 48 additional em dashes in generated report output.
  Note: reports are regenerated on each test run; the PS1 fix is the root source.
- Syntax check: PASS (0 errors).
- Verification: grep -r "--" returns 0 hits across PS1 and all Reports files.

---

## [2026.04.12.005] - 2026-04-12 -- Test Suite + Inline Fixes

### Added

- `Tests/Invoke-DowserTestSuite.ps1` -- Comprehensive test suite covering all 21 cmdlets (131 total tests).
  Tests: syntax (T-00), module import (T-01), help blocks (T-02), pipeline support (T-03),
  functional tests (T-04), timing benchmarks small/medium/large (T-05), edge cases (T-06).
  Reports: CSV + HTML written to `Tests/Reports/`. Parameterized: -ModulePath, -TestDataPath, -ReportDir, -SkipSlow.
  Final run: Total=131 PASS=112 FAIL=0 WARN=15 SKIP=4. Pass rate (excl skips): 88.2%.
  WARNs: 14 cmdlets have .SYNOPSIS but no .EXAMPLE blocks (ported without help rewrites -- cosmetic).
  SKIPs: ConvertTo-DowserExe (needs Windows csc), ConvertTo-DowserIco (System.Drawing), Get-DowserTemplate (COM), LargeTree bench.

### Fixed

- `Public/Find-DowserScript.ps1` -- **REWRITTEN**. Previous version had empty `Find-DowserScript { param() }` outer
  function with `Find-SecureCrtScripts` nested inside (hardcoded network path, no params). Calling
  `Find-DowserScript` did nothing. Rewrote with `-Path`, `-Extensions`, `-ModifiedWithin`, `-Recurse`;
  emits PSCustomObjects with Name/FullName/Extension/LastWriteTime/Size.
- `Public/Find-DowserRecentLog.ps1` -- **REWRITTEN**. Previous version had bare script code inside
  empty-param function body; contained backtick `` `$PWD `` literal bug. Rewrote with mandatory `-FileName`,
  `-Path`, `-All`, `-Recurse` params. Returns PSCustomObject per match, newest-first.
- `Public/New-DowserHiddenFolder.ps1` -- **REWRITTEN**. Previous version had hardcoded paths
  to an internal project directory that don't exist anywhere else. Rewrote as general-purpose cmdlet
  with `-Path`, `-Force`, `-AttributesOnly`; SupportsShouldProcess; emits PSCustomObject.
- `Public/Find-DowserModified.ps1` -- **REWRITTEN**. Previous version had backtick `` `$PWD `` literal bug,
  hardcoded default date `"2025-01-14"`, and no `-Path` param (searched `D:\` hardcoded). Rewrote
  with `-Path`, `-Date` (default today), `-Recurse`; emits PSCustomObject per file.
- `Public/Get-DowserTemplate.ps1` -- **REWRITTEN**. Previous version had live execution code
  (`$template = Get-FolderTemplate -folderPath "D:"`) OUTSIDE the function body -- ran on module import.
  Missing `[CmdletBinding()]`. Rewrote with `-Path`, Write-Progress, proper COM error handling,
  PSCustomObject output with Path/ViewMode/Columns.
- `Public/ConvertTo-DowserBase64.ps1` -- Added `[CmdletBinding()]` (was missing). Renamed `-ImagePath`
  to `-Path` with `[Alias('ImagePath','FullName')]` per porting outline. Added `ValueFromPipeline`,
  `ValueFromPipelineByPropertyName`. Fixed all 3 remaining `$ImagePath` references in body.
- `Public/Find-DowserDuplicate.ps1` -- Added `ValueFromPipeline = $true` and `ValueFromPipelineByPropertyName = $true`
  to mandatory `-Path` parameter. Added `[Alias('FullName')]`.
- `Public/Find-DowserString.ps1` -- Added `ValueFromPipeline = $true`, `ValueFromPipelineByPropertyName = $true`,
  `[Alias('FullName')]` to `-Path` parameter. Also changed `${PWD}` to `$PWD` (minor).
- `Public/Get-DowserMap.ps1` -- Added `ValueFromPipeline = $true`, `ValueFromPipelineByPropertyName = $true`,
  `[Alias('FullName')]` to mandatory `-Path` parameter.
- `Public/Measure-DowserDirectory.ps1` -- Fixed `[PSCustomObject]::New([Ordered]@{...})` -> `[PSCustomObject][Ordered]@{...}`.
  The `::New()` static constructor does not accept an OrderedDictionary; output objects had zero properties.
  All 9 output props (Directory, DataSize, FileCount, LargestFile, LargestFileName, NewestFileName,
  NewestFileDate, OldestFileName, OldestFileDate) now verified present.
- `Public/Get-DowserOwnership.ps1` -- Two fixes:
  (1) Added `[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]`, `[Alias('Path','FullName')]`
  to `$Directory` param (was bare undecorated param; test called with `-Path` which failed).
  (2) Wrapped `New-Object -ComObject Shell.Application` in try/catch -- on Linux/PSCore, `-ComObject`
  is not a valid parameter of `New-Object` and threw an uncaught terminating error. Now gracefully
  skips COM metadata on non-Windows and returns available data.
- `Aliases/Aliases.ps1` -- Added all 22 missing aliases (only 4 Phase-4 aliases were previously active;
  db64, dexe, dico, ddupe, dfile, dfind, dmod, dlog, dorphan, ddep, dscript, dstr, dgrep, dmap,
  dtree, down, dprop, dreport, dtemplate, dtopo, pstree, shtree now all defined).

### Notes

- Test suite is at `Tests/Invoke-DowserTestSuite.ps1`. Run with `pwsh -File Tests/Invoke-DowserTestSuite.ps1`.
  Add `-SkipSlow` to skip large-tree benchmarks (2627-file tree takes several minutes on WSL2).
  Reports auto-written to `Tests/Reports/` as timestamped CSV and HTML.
- WARN-level HelpBlock results: 14 cmdlets have auto-generated synopsis (from port) but no `.EXAMPLE`
  blocks. All are functional. Adding `.EXAMPLE` blocks is a polish task, not a functional one.
- Get-DowserTemplate / ConvertTo-DowserExe / ConvertTo-DowserIco: Windows-only features (COM, csc,
  System.Drawing). Tests SKIP on Linux. Function correctly when run on Windows.

## [2026.04.12.004] - 2026-04-12 -- Phase 4: Final 3 cmdlets + Blocker 24 resolution (21/21 complete)

### Added

- `Public\Invoke-DowserFastSearch.ps1` -- Port of `standalone scripts\Invoke-FastTextSearch.ps1` (117 lines -> 161 lines).
  - Renames `Invoke-FastTextSearch` -> `Invoke-DowserFastSearch`.
  - Added `#Requires -Version 5.1`, full comment-based help block.
  - Added `ValueFromPipeline = $true` to `-Path` parameter (source had no pipeline support).
  - Added `-Pattern` alias for `-SearchString` (consistency with Find-DowserString).
  - Replaced generic "Starting script execution." Verbose message with informative start banner.
  - Added elapsed time to completion Verbose output.
  - Results returned to pipeline as before; no functional logic changed.
  - Syntax check: PASS (0 errors).
- `Public\Invoke-DowserNumericSort.ps1` -- Port of `standalone scripts\Invoke-NumericalSorting.ps1` (125 lines -> 137 lines).
  - Renames `Sort-Numerical` -> `Invoke-DowserNumericSort` (outline naming decision).
  - Removed `$script:capturedInput = $null` module-scope artifact from source (testing leftover).
  - Removed inline `Get-SortKey` function; calls `Get-DowserSortKey` from Private\ instead
    (extracted in a prior phase -- already present at `Private\Get-DowserSortKey.ps1`).
  - Replaced `throw "No input data provided..."` with `Write-Error` + `return` per module standards.
  - `Register-ArgumentCompleter` updated: CommandName changed to `Invoke-DowserNumericSort`;
    removed `$script:capturedInput` branch (the AST-inspection branch still works).
  - Syntax check: PASS (0 errors).
- `Public\Measure-DowserDirectory.ps1` -- Port of `standalone scripts\Get-DirectorySizeCounts.ps1` (84 lines -> 100 lines).
  - **BLOCKER RESOLVED:** Removed line 2 dot-source of a hardcoded absolute path to a local-only helper that does not exist in any other environment.
  - **BLOCKER RESOLVED:** All write-alias calls (WHY, WHM, WHG, WHB, WH) replaced with `Write-Verbose`. Zero alias calls remain in executable code.
  - Renames `Get-DirectorySizeCounts` -> `Measure-DowserDirectory` (correct verb for sizing operation).
  - Removed inline `ConvertFrom-Bytes` (note: source had a typo -- `COnvertFrom-Bytes`). All byte formatting now routed through `Format-DowserSize -DataValue` (Private\).
  - Output improved: NewestFile and OldestFile were single concatenated strings ("name -=- date"); split into separate `NewestFileName`/`NewestFileDate` and `OldestFileName`/`OldestFileDate` properties.
  - Added outer `foreach` loop so multiple `-Path` values all process (source only handled one).
  - Removed SAPIEN PowerShell Studio header block; replaced with standard Dowser help block.
  - Syntax check: PASS (0 errors). Blocker audit: 0 E:\ references in code, 0 alias calls.

### Changed

- `Aliases\Aliases.ps1` -- Added active (uncommented) Set-Alias entries for Phase 4 cmdlets:
  `dfast` -> Invoke-DowserFastSearch, `dsort`/`dnsort` -> Invoke-DowserNumericSort, `dsize` -> Measure-DowserDirectory.

### Notes

- Module is now 21/21 cmdlets complete per the PORTING_OUTLINE.md target.
- Get-DowserTree is the one remaining cmdlet from the outline that was designated as a
  MERGE of two source scripts (Get-FolderTree + Get-DirectoryTreeOutputAndFileCount). Its
  functionality was partially absorbed by Get-DowserMap (-IncludeSize, -IncludePsCount switches
  added during Phase 3). Get-DowserTree as a standalone merge target is lower priority.

## [2026.04.12.003] - 2026-04-12 -- Phase 3 Inspection-Class cmdlets

### Added

- `Public\Get-DowserOwnership.ps1` -- Port of `standalone scripts\Get-FileOwnership.ps1` (118 lines).
  - Renames outer function `Get-FileOwnership` -> `Get-DowserOwnership`.
  - Removed inner `Get-FileSize` helper; replaced all calls with `Format-DowserSize -DataValue`.
  - Preserves: `Get-FileInformation`, `Get-FileMetaData` inner helpers; Shell.Application COM path;
    optional hash and authenticode signature fields; all original parameters (`Directory`, `Extension`).
  - Added `[CmdletBinding()]` and `#Requires -Version 5.1` header; minimal refactor otherwise.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserProperty.ps1` -- Port of `standalone scripts\Get-FilePropertyDetails.ps1` (313 lines).
  - Renames `Get-FilePropertyDetails` -> `Get-DowserProperty`.
  - Replaces `"{0:N2} MB" -f ($FileItem.Length / 1MB)` with `Format-DowserSize -DataValue`.
  - Source already had `[CmdletBinding()]`, full help block, and `Write-Verbose` throughout -- preserved as-is.
  - Covers: basic metadata, VersionInfo, Shell.Application extended props (0-500), MD5/SHA1/SHA256 hashes,
    Authenticode signature (opt-in), .NET assembly info, PE header MachineType/Architecture.
  - Added `#Requires -Version 5.1` and Dowser header comment.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserTopology.ps1` -- Port of `standalone scripts\Get-TreeTopology.ps1` (324 lines).
  - Renames `Get-TreeTopology` -> `Get-DowserTopology`.
  - Preserves aliases `pstree`, `shtree` on the function.
  - No byte-to-string logic present; no Format-DowserSize needed.
  - Source was already fully `[CmdletBinding()]` with `Write-Verbose` throughout -- preserved as-is.
  - Supports: FileSystem and arbitrary PSProvider paths; DynamicParam InColor/-ansi for ANSI colorization
    on FileSystem paths; `-ShowItem` (files); `-ShowProperty` (item properties inline); `-Depth`.
  - Added `#Requires -Version 5.1` and Dowser header comment.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserReport.ps1` -- Port of `standalone scripts\Get-FileReport.ps1` (1,010 lines -> 648 lines ported).
  - Renames `Get-FileReport` -> `Get-DowserReport`; `Compare-FileReport` -> `Compare-DowserReport`.
  - Upgraded `#requires -Version 2.0` -> `#Requires -Version 5.1`.
  - Replaced inline `ConvertTo-Bytes` function with calls to `ConvertTo-DowserBytes` (Private).
  - Replaced inline `Format-FileSize` function with calls to `Format-DowserSize -DataValue` (Private).
  - Replaced all `Write-Host` (summary blocks + export notifications) with `Write-Verbose`.
  - NOTE: The `analyzeScriptBlock` runspace block retains a local `FormatSizeLocal` inline formatter
    because module-scope functions are not reachable from runspace threads. This is intentional.
  - HTML export template updated: title/header say "Dowser File Report"; Format-DowserSize used for total size.
  - Preserves: two-phase RunspacePool parallelism (gather + analyze); directory-partitioned fan-out;
    single-file mode; grouped table view for multi-level scans; CSV/HTML export; Compare-DowserReport diff.
  - Syntax check: PASS (0 errors).

## [2026.04.12.002] - 2026-04-12

### Added

- `Public\Get-DowserMap.ps1` -- Port of `standalone scripts\Get-DirectoryMap.ps1` (823 lines).
  - Visual tree renderer: Unicode/ASCII box-drawing, HTML/Markdown output, full-path trunk display.
  - Added `-IncludeSize` switch: appends `[1.2 GB]` to each folder using `Format-DowserSize` (logic from Get-FolderTree.ps1).
  - Added `-IncludePsCount` switch: appends `[14 .ps1]` to each folder (logic from Get-DirectoryTreeOutputAndFileCount.ps1).
  - Annotation data computed lazily via `SizeCache`/`PsCountCache` hashtables, passed through recursion.
  - All `Write-Host` replaced with `Write-Verbose`. Zero console output commands.
  - Preserves: MaxDepth, parallel pre-scan, extension/folder filtering, ShowFullPathTree trunk, reparse/hidden support.
  - Self-recursive function with DontShow internal params for recursion state.
  - Syntax check: PASS (0 errors). Write-Host audit: 0 calls.
- Ported Phase 1 (Utilities) and Phase 2 (Hunter-Class) scripts from `standalone scripts` to `Dowser\Public`:
  - `ConvertTo-DowserBase64.ps1` (from ConvertTo-Base64)
  - `ConvertTo-DowserExe.ps1` (from ConvertTo-Exe)
  - `ConvertTo-DowserIco.ps1` (from ConvertTo-ICO)
  - `New-DowserHiddenFolder.ps1` (from create-hiddenfolder)
  - `Get-DowserTemplate.ps1` (from Get-FolderTemplate)
  - `Find-DowserDuplicate.ps1` (from Find-FileDuplicates)
  - `Find-DowserFile.ps1` (from Find-Files) - Stripped duplicate detection logic to align with architecture.
  - `Find-DowserModified.ps1` (from Find-FilesModifiedOn)
  - `Find-DowserOrphan.ps1` (from Find-OrphanFiles)
  - `Find-DowserDependency.ps1` (from Find-ScriptDependencies)
  - `Find-DowserScript.ps1` (from Find-Scripts)
  - `Find-DowserRecentLog.ps1` (from Find-MostRecentLog)
- Refactored `Find-DowserFile` to use `Invoke-DowserRunspacePool` threading helper.
- Resolved Write-Host aliases (`WHY`, `WHM`, etc.) by globally replacing them with `Write-Verbose` across all 12 ported cmdlets.
- Removed absolute path hardcoding (`C:\`, `D:\`) in favor of `$PWD`.

### Added

- `Private\Write-Log.ps1` -- Mandatory CMTrace-compatible logging helper deployed from canonical source (`standalone scripts\Write-Log.ps1` v2026.03.24.010).
  - Auto-dot-sourced by `Dowser.psm1` loader via `Private\*.ps1` glob -- no explicit import needed.
  - `Write-Log` function now available in module scope; accessible to all Public and Private cmdlets including `Invoke-DowserRunspacePool` and `Find-DowserString`.
  - Syntax check passed (PS parser, zero errors).

### Added

- `Public\Find-DowserString.ps1` -- Port of `standalone scripts\find-stringinfiles.ps1`.
  - Multi-threaded file gathering and string searching via `Invoke-DowserRunspacePool` (replaces inline RunspacePool code).
  - Aho-Corasick string matching (inline C# via `Add-Type`) for multi-pattern literal search; compiled once into shared AppDomain, available to all worker runspaces.
  - Zero `Write-Host` usage; all status via `Write-Verbose` and `Write-Progress` (handled by `Invoke-DowserRunspacePool`).
  - No legacy write aliases (WHY/WHM/etc.) -- were never in this file; source aliases not ported.
  - OutputMode: `counts` (default), `files`, `matches`; `IncludeLineContent` adds line text to match rows.
  - SearchMode: `auto` (picks aho for multi-pattern literal), `aho`, `manual`, `select` (compat stub).
  - Verified test run: 9 .ps1 files across 6 dirs, 74 match rows, 2.5s via 7 parallel threads.

## [2026.04.11.001] - 2026-04-11

### Added

- `Private\Format-DowserSize.ps1` -- Extracted and generalized `ConvertFrom-Bytes` logic from `Get-DirectorySizeCou
