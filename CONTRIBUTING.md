# Contributing

Issues and pull requests are welcome, especially reports of models that run with the SWMM5+ executable but not through the C interface, and builds on new compilers or platforms.

- Start every new source file with a marker line such as `! @license-header What this file does.` and run `python tools/license_headers.py --apply`.
- Never edit upstream sources in place. Add an anchored edit to `cmake/SourceHooks.cmake` and explain in a comment why it is needed and how it preserves the Intel behaviour.
- Fixes to genuine SWMM5+ bugs should also be offered upstream to https://github.com/CIMM-ORG/SWMM5plus.

By contributing you agree that your contribution may be distributed under GPL-3.0-or-later and under other licenses chosen by the copyright holder, Ehsan Madadi.
