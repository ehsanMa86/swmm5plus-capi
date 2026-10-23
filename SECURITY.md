# Security policy

## Supported versions

Security fixes are made in the latest release. Please update to it before reporting a problem.

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately through [GitHub security advisories](https://github.com/ehsanMa86/swmm5plus-capi/security/advisories/new) with the swmm5plus-capi version, the platform and, if possible, an input file or the calls that reproduce it.

You will get a reply within a week. Once a fix is released, the advisory is published with credit to the reporter, unless they prefer otherwise.

SWMM5+ and EPA SWMM read the input file and write output files in the folders the host passes to `s5p_open`. Problems in how input files are read, and writes outside those folders, are in scope. Crashes that the upstream solvers also show with the same file are fixed upstream when possible.
