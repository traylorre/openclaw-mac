# Tasks: Grep Flag Fix

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Tasks

- [x] T001 Change `grep -oE -e "$dangerous_flags"` to `grep -oE -- "$dangerous_flags"` on line 2085 of `scripts/hardening-audit.sh`
- [ ] T002 Run `shellcheck scripts/hardening-audit.sh` to verify no regressions
- [ ] T003 Run `make audit` and confirm no `grep: unrecognized option` errors
