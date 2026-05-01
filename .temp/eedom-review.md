## 🦅 Eagle Eyed Dom — /workspace#0
**PR Review**


> 🔴 **BLOCKED**



> **Security: 0/100** · Quality: 88/100


> **Maintainability: 🟢 A (97/100)** · CCN avg 1.8 · ⚠️ 1 high-complexity


| Plugin | Findings |
|--------|----------|
| Files scanned | 170 |
| clamav | error: [BINARY_CRASHED] clamscan crashed (exit 2): LibClamAV Error: cli_loaddbdir: No supported database files found in /var/lib/clamav
ERROR: Can't open file or directory |
| gitleaks | 0 |
| supply-chain | 42 |
| osv-scanner | 3 |
| scancode | 0 |
| syft | 0 |
| trivy | 22 |
| cdk-nag | skipped |
| cfn-nag | skipped |
| kube-linter | 0 |
| cpd | 0 |
| mypy | 1 |
| semgrep | error: scanner degraded: [NOT_INSTALLED] opengrep not installed |
| blast-radius | 11 |
| complexity | 139 |
| cspell | 1580 |
| ls-lint | skipped |
| Maintainability | 🟢 A (97/100) |


### Actionability

> 22 findings have available fixes. 1776 are blocked on upstream.


**22 fixable** — upgrade available:

- `python-dotenv` 1.0.1 → **1.2.2** (medium) — [CVE-2026-28684](https://avd.aquasec.com/nvd/cve-2026-28684)
- `python-dotenv` 1.1.1 → **1.2.2** (medium) — [CVE-2026-28684](https://avd.aquasec.com/nvd/cve-2026-28684)
- `requests` 2.32.4 → **2.33.0** (medium) — [CVE-2026-25645](https://avd.aquasec.com/nvd/cve-2026-25645)
- `requests` 2.32.5 → **2.33.0** (medium) — [CVE-2026-25645](https://avd.aquasec.com/nvd/cve-2026-25645)
- `urllib3` 2.2.3 → **2.6.0** (high) — [CVE-2025-66418](https://avd.aquasec.com/nvd/cve-2025-66418)
- `urllib3` 2.2.3 → **2.6.0** (high) — [CVE-2025-66471](https://avd.aquasec.com/nvd/cve-2025-66471)
- `urllib3` 2.2.3 → **2.6.3** (high) — [CVE-2026-21441](https://avd.aquasec.com/nvd/cve-2026-21441)
- `urllib3` 2.2.3 → **2.5.0** (medium) — [CVE-2025-50181](https://avd.aquasec.com/nvd/cve-2025-50181)
- `urllib3` 2.2.3 → **2.5.0** (medium) — [CVE-2025-50182](https://avd.aquasec.com/nvd/cve-2025-50182)
- `urllib3` 2.5.0 → **2.6.0** (high) — [CVE-2025-66418](https://avd.aquasec.com/nvd/cve-2025-66418)

- *...12 more*




**1776 blocked** — no fix available:

- **blast-radius**: 11 findings (info, medium)
- **complexity**: 139 findings (info)
- **cspell**: 1580 findings (info)
- **mypy**: 1 findings (high)
- **osv-scanner**: 3 findings (medium, high)
- **supply-chain**: 42 findings (high, critical)




<details open><summary>📌 <b>Unpinned Dependencies (42)</b></summary>

| Package | Version | Ecosystem | Risk |
|---------|---------|-----------|------|
| `express` | `^4.21.0` | npm | caret range — allows minor+patch |
| `youtube-transcript` | `^1.3.0` | npm | caret range — allows minor+patch |
| `@types/express` | `^5.0.0` | npm | caret range — allows minor+patch |
| `@types/youtube` | `^0.1.2` | npm | caret range — allows minor+patch |
| `concurrently` | `^9.0.0` | npm | caret range — allows minor+patch |
| `tsx` | `^4.19.0` | npm | caret range — allows minor+patch |
| `typescript` | `^5.7.0` | npm | caret range — allows minor+patch |
| `vite` | `^6.0.0` | npm | caret range — allows minor+patch |
| `coremltools` | `(no version)` | pypi | no version — installs latest |
| `numpy` | `(no version)` | pypi | no version — installs latest |
| `torch` | `(no version)` | pypi | no version — installs latest |
| `tqdm` | `(no version)` | pypi | no version — installs latest |
| `transformers` | `(no version)` | pypi | no version — installs latest |
| `sentencepiece` | `(no version)` | pypi | no version — installs latest |
| `sphinx` | `(no version)` | pypi | no version — installs latest |
| `breathe` | `(no version)` | pypi | no version — installs latest |
| `sphinx-book-theme` | `(no version)` | pypi | no version — installs latest |
| `sphinx` | `(no version)` | pypi | no version — installs latest |
| `breathe` | `(no version)` | pypi | no version — installs latest |
| `sphinx-book-theme` | `(no version)` | pypi | no version — installs latest |
| `sphinx-copybutton` | `(no version)` | pypi | no version — installs latest |
| `mlx` | `(no version)` | pypi | no version — installs latest |
| `setuptools` | `>=42` | pypi | minimum bound only — no upper cap |
| `cmake` | `>=3.25` | pypi | minimum bound only — no upper cap |
| `mlx` | `>=0.21.0` | pypi | minimum bound only — no upper cap |
| `coremltools` | `(no version)` | pypi | no version — installs latest |
| `numpy` | `(no version)` | pypi | no version — installs latest |
| `torch` | `(no version)` | pypi | no version — installs latest |
| `tqdm` | `(no version)` | pypi | no version — installs latest |
| `transformers` | `(no version)` | pypi | no version — installs latest |
| `sentencepiece` | `(no version)` | pypi | no version — installs latest |
| `sphinx` | `(no version)` | pypi | no version — installs latest |
| `breathe` | `(no version)` | pypi | no version — installs latest |
| `sphinx-book-theme` | `(no version)` | pypi | no version — installs latest |
| `sphinx` | `(no version)` | pypi | no version — installs latest |
| `breathe` | `(no version)` | pypi | no version — installs latest |
| `sphinx-book-theme` | `(no version)` | pypi | no version — installs latest |
| `sphinx-copybutton` | `(no version)` | pypi | no version — installs latest |
| `mlx` | `(no version)` | pypi | no version — installs latest |
| `setuptools` | `>=42` | pypi | minimum bound only — no upper cap |
| `cmake` | `>=3.25` | pypi | minimum bound only — no upper cap |
| `mlx` | `>=0.21.0` | pypi | minimum bound only — no upper cap |

</details>



<details open>
<summary>🔴 <b>Critical/High Vulnerabilities (1)</b></summary>

| CVE | Package | Version | Severity | Summary |
|-----|---------|---------|----------|---------|
| 🟠 [CVE-2026-39363](https://nvd.nist.gov/vuln/detail/CVE-2026-39363) | `vite` | 6.4.1 | high | Vite Vulnerable to Arbitrary File Read via Vite Dev Server WebSocket |

</details>

<details>
<summary>🟡 <b>Medium/Low Vulnerabilities (2)</b></summary>

| CVE | Package | Severity |
|-----|---------|----------|
| [CVE-2026-41305](https://nvd.nist.gov/vuln/detail/CVE-2026-41305) | `postcss@8.5.8` | medium |
| [CVE-2026-39365](https://nvd.nist.gov/vuln/detail/CVE-2026-39365) | `vite@6.4.1` | medium |

</details>


SBOM: 906 components detected

Trivy: 22 vulnerabilities found

<details open>
<summary>🔬 <b>Type Errors — mypy (1)</b></summary>

🔴 **`benchmark/run_benchmark.py:22`** — `import-not-found`
> Cannot find implementation or library stub for module named "jiwer"

</details>


<details open><summary>💥 <b>Blast Radius (11)</b></summary>

**🟡 MEDIUM (6)**

- `tools/sidecast-debug/src/ui.ts` (tools/sidecast-debug/src/ui.ts) — 25 outgoing calls — high_fan_out
- `tools/sidecast-debug/src/sidecast.ts` (tools/sidecast-debug/src/sidecast.ts) — 16 outgoing calls — high_fan_out
- `tools/sidecast-debug/src/transcript.ts` (tools/sidecast-debug/src/transcript.ts) — 10 outgoing calls — high_fan_out
- `benchmark/run_benchmark.py` — missing_tested_by
- `benchmark/run_benchmark.py` (benchmark/run_benchmark.py) — srp_high_fan_out_imports
- `tools/sidecast-debug/src/sidecast.ts` (tools/sidecast-debug/src/sidecast.ts) — srp_high_fan_out_imports
**ℹ️ INFO (5)**

- `extractVideoId` (tools/sidecast-debug/src/player.ts) — orphan_symbol
- `loadSettings` (tools/sidecast-debug/src/settings.ts) — orphan_symbol
- `defaultSettings` (tools/sidecast-debug/src/settings.ts) — orphan_symbol
- `hexToTintName` (tools/sidecast-debug/src/settings.ts) — orphan_symbol
- `generate` (tools/sidecast-debug/src/sidecast.ts) — orphan_symbol

*5757 symbols, 8620 edges, 12 checks*

</details>



<details><summary>📊 <b>Complexity (avg CCN: 1.8, max: 26, 1074 NLOC)</b></summary>

**⚠️ High complexity (CCN > 10):**

| Function | File | CCN | MI | NLOC |
|----------|------|-----|----|------|
| `main` | `benchmark/run_benchmark.py` | 26 | A (52.2) | 72 |

| Function | CCN | MI | NLOC |
|----------|-----|----|------|
| `main` | 26 | A (52.2) | 72 |
| `text.slice` | 10 | A (86.3) | 19 |
| `renderPersonaCard` | 8 | A (52.0) | 82 |
| `generate` | 6 | A (61.5) | 61 |
| `onTimeUpdate` | 5 | A (93.2) | 16 |
| `jaccard` | 5 | A (98.3) | 11 |
| `(anonymous)` | 5 | A (100.0) | 1 |
| `Date` | 4 | A (85.5) | 21 |
| `(anonymous)` | 4 | A (100.0) | 7 |
| `extractJSON` | 4 | A (100.0) | 7 |
| `(anonymous)` | 3 | A (89.7) | 16 |
| `loadVideo` | 3 | A (78.2) | 31 |
| `hexToTintName` | 3 | A (100.0) | 3 |
| `window.setInterval` | 3 | A (100.0) | 11 |
| `extractVideoId` | 3 | A (100.0) | 11 |
| `renderSettingsPanel` | 3 | A (46.3) | 113 |
| `fetchTranscript` | 3 | A (100.0) | 11 |
| `findActiveSegmentIndex` | 3 | A (100.0) | 9 |
| `buildContextWindow` | 3 | A (78.7) | 30 |
| `run_whisper` | 2 | A (77.0) | 33 |
| `(anonymous)` | 2 | A (100.0) | 3 |
| `onSeek` | 2 | A (100.0) | 12 |
| `(anonymous)` | 2 | A (100.0) | 5 |
| `defaultSettings` | 2 | A (100.0) | 6 |
| `=>` | 2 | A (99.8) | 12 |
| `onStateChange` | 2 | A (100.0) | 7 |
| `el` | 2 | A (100.0) | 5 |
| `updateSelected` | 2 | A (86.0) | 17 |
| `(anonymous)` | 2 | A (97.0) | 11 |
| `(anonymous)` | 2 | A (100.0) | 9 |
| `(anonymous)` | 2 | A (100.0) | 3 |
| `renderModelPicker` | 2 | A (79.3) | 26 |
| `(anonymous)` | 2 | A (100.0) | 1 |
| `(anonymous)` | 2 | A (100.0) | 5 |
| `(anonymous)` | 2 | A (98.0) | 12 |
| `(anonymous)` | 2 | A (100.0) | 3 |
| `seconds.toString.padStart` | 2 | A (100.0) | 8 |
| `msg.confidence.toFixed` | 2 | A (95.5) | 14 |
| `buildPrompt` | 2 | A (76.3) | 32 |
| `(anonymous)` | 2 | A (100.0) | 4 |
| `normalize_text` | 1 | A (100.0) | 6 |
| `(anonymous)` | 1 | A (100.0) | 4 |
| `(anonymous)` | 1 | A (100.0) | 5 |
| `(anonymous)` | 1 | A (100.0) | 3 |
| `(anonymous)` | 1 | A (100.0) | 4 |
| `refreshSettings` | 1 | A (100.0) | 7 |
| `(anonymous)` | 1 | A (100.0) | 2 |
| `(anonymous)` | 1 | A (100.0) | 2 |
| `(anonymous)` | 1 | A (100.0) | 2 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 4 |
| `(anonymous)` | 1 | A (100.0) | 8 |
| `saveSettings` | 1 | A (100.0) | 3 |
| `=>` | 1 | A (100.0) | 1 |
| `Math.floor` | 1 | A (100.0) | 7 |
| `settings.personas.filter` | 1 | A (100.0) | 1 |
| `settings.personas.filter` | 1 | A (100.0) | 2 |
| `=>` | 1 | A (100.0) | 1 |
| `PlayerCallback` | 1 | A (100.0) | 1 |
| `constructor` | 1 | A (100.0) | 9 |
| `onReady` | 1 | A (100.0) | 4 |
| `onStateChange` | 1 | A (100.0) | 4 |
| `(.onYouTubeIframeAPIReady` | 1 | A (100.0) | 1 |
| `>` | 1 | A (100.0) | 6 |
| `OnChange` | 1 | A (100.0) | 1 |
| `label` | 1 | A (100.0) | 5 |
| `fieldInput` | 1 | A (100.0) | 1 |
| `fieldSelect` | 1 | A (100.0) | 1 |
| `options.forEach` | 1 | A (100.0) | 7 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `fieldSlider` | 1 | A (100.0) | 1 |
| `inp.addEventListener` | 1 | A (100.0) | 5 |
| `fieldToggle` | 1 | A (100.0) | 1 |
| `divider` | 1 | A (100.0) | 3 |
| `groupHeading` | 1 | A (100.0) | 5 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `findPreset` | 1 | A (100.0) | 3 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 8 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 6 |
| `(anonymous)` | 1 | A (100.0) | 6 |
| `(anonymous)` | 1 | A (100.0) | 3 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 4 |
| `(anonymous)` | 1 | A (100.0) | 10 |
| `(anonymous)` | 1 | A (100.0) | 6 |
| `(anonymous)` | 1 | A (100.0) | 4 |
| `(anonymous)` | 1 | A (100.0) | 5 |
| `(anonymous)` | 1 | A (100.0) | 5 |
| `(anonymous)` | 1 | A (100.0) | 5 |
| `(anonymous)` | 1 | A (100.0) | 7 |
| `(anonymous)` | 1 | A (100.0) | 4 |
| `(anonymous)` | 1 | A (100.0) | 10 |
| `renderTranscriptViewer` | 1 | A (100.0) | 2 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `escapeHtml` | 1 | A (100.0) | 4 |
| `msg.confidence.toFixed` | 1 | A (100.0) | 4 |
| `s.toString.padStart` | 1 | A (100.0) | 2 |
| `escapeHtml` | 1 | A (100.0) | 5 |
| `escapeHtml` | 1 | A (100.0) | 1 |
| `escapeHtml` | 1 | A (100.0) | 3 |
| `(anonymous)` | 1 | A (100.0) | 6 |
| `setStatus` | 1 | A (100.0) | 6 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `getSegmentsUpTo` | 1 | A (100.0) | 6 |
| `resetSummary` | 1 | A (100.0) | 5 |
| `getSummary` | 1 | A (100.0) | 3 |
| `ensureSummary` | 1 | A (100.0) | 2 |
| `toSummarize.map` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `getMessages` | 1 | A (100.0) | 3 |
| `clearState` | 1 | A (100.0) | 6 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `normalizedWords` | 1 | A (100.0) | 8 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `llmCall` | 1 | A (100.0) | 8 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `threshold` | 1 | A (100.0) | 4 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |
| `(anonymous)` | 1 | A (100.0) | 1 |

</details>



<details open>
<summary>📝 <b>Spelling (1580)</b></summary>

| File | Line | Word | Suggestions |
|------|------|------|-------------|
| `/workspace/.github/workflows/release-dmg.yml` | 47 | `libexec` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 48 | `libexec` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 77 | `mktemp` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 89 | `codesign` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 96 | `codesigning` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 97 | `CODESIGN` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 102 | `CODESIGN` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 102 | `CODESIGN` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 109 | `CODESIGN` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 109 | `CODESIGN` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 136 | `appcast` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 138 | `EDDSA` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 138 | `EDDSA` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 152 | `EDDSA` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 171 | `appcast` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 172 | `appcast` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 172 | `APPCAST` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 193 | `APPCAST` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 196 | `appcast` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 201 | `appcast` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 212 | `openoats` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 214 | `openoats` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 215 | `openoats` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 217 | `openoats` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 220 | `openoats` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 237 | `yazinsai` |  |
| `/workspace/.github/workflows/release-dmg.yml` | 249 | `yazinsai` |  |
| `/workspace/.wfc/pipeline/session-state.json` | 11 | `Qwen` |  |
| `/workspace/.wfc/pipeline/session-state.json` | 11 | `Voxtral` |  |
| `/workspace/.wfc/pipeline/session-state.json` | 11 | `GLMASR` |  |

*...1550 more*

</details>


---
*Eagle Eyed Dom v0.2.11 · 11 blast-radius · 139 complexity · 1580 cspell · 1 mypy · 3 osv-scanner · 42 supply-chain · 22 trivy*
