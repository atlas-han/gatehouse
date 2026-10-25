# docs/work

이슈 하나의 진행 상태를 파일로 남긴다. 세션이 끊기거나 컨텍스트가 압축돼도 이 폴더만 보면 이어서 진행할 수 있다.

| 파일 | 만드는 단계 | 누가 |
| --- | --- | --- |
| `<이슈>/INTENT.md` | `/intent <이슈>` | 메인 세션, 사람이 열린 질문에 답함 |
| `<이슈>/spec.md` | `/spec` | 메인 세션 |
| `<이슈>/spec-review.md` | `/spec` | `spec-reviewer` subagent |
| `<이슈>/plan.md` | `/work-plan` (PR에 `spec-approved` 라벨이 붙은 뒤) | 메인 세션 |
| `<이슈>/verify-report.md` | `/work-verify` | `verifier` subagent |

흐름: `/issue`(이슈 생성, `--plan W<n>`은 주차 일괄) → `/work <이슈>`(이슈 worktree를 만들거나 들어가 아래를 다음 사람 지점까지 실행) → `/intent` → `/spec` → **사람: spec 승인(`spec-approved` 라벨)** → `/work-plan` → `/implement` ⇄ `/work-verify`(FAIL 3회 초과 시 사람에게) → `/ship` → **사람: PR 승인·병합**

모든 변경은 이슈 worktree(`.claude/worktrees/issue-<이슈>`)에서 한다. 메인 체크아웃에서는 hook이 파일 변경과 커밋을 막는다.
