# AngerRate 0.1.0 launch

## Published

- Repository: https://github.com/boxyhn/anger-rate
- Public preview: https://github.com/boxyhn/anger-rate/releases/tag/v0.1.0
- Demo: ../flame-demo.gif (prototype animation, not a screen recording of live scoring)

## Channel status

- MacMenuBar: submission form prepared, not submitted. Requires an app-domain email (no Gmail/Hotmail) and at least three screenshots showing the app in the actual menu bar. Form: https://macmenubar.com/submit-your-menu-bar-app/
- Show HN: not submitted. Guidelines prohibit generated/AI-edited text; the maker must supply their own original submission text. https://news.ycombinator.com/newsguidelines.html
- Reddit r/macapps: authenticated, but promotion requires 10 local subreddit karma. No post or promotional comment submitted.
- Reddit r/SideProject: submitted https://www.reddit.com/r/SideProject/comments/1w85q8e/ . Detail page explicitly says “removed by Reddit’s filters”; it is not a successful public promotion. Sent a moderator review request through the compose form; fields cleared after submission, but no separate delivery receipt was available. Do not repost while awaiting review.
- GeekNews: 글등록 redirects to login. Not submitted. Review current Show GN guidance before posting once authenticated.
- Product Hunt: deferred until initial feedback, as discussed.

## English draft for channels that permit assisted copy

Title: I made a menu bar flame to notice when I get frustrated with coding agents

I kept getting frustrated while using Codex and Claude Code, so I made AngerRate: a small, free macOS menu bar app that turns language signals into an animated flame.

The flame goes from a candle to a growing flame to a roaring flame. At 100, it nudges you once: “Time for a breather?” It settles as the score decays.

It includes Korean and English UI and profanity rules. Live detection runs locally. Optional initial personalization uses the coding CLI you are already signed in to; representative messages are sent through that CLI for the review. No separate API key is required.

It is a heuristic, not an emotion diagnosis. I would especially appreciate feedback on false positives and whether the flame helps you notice the moment without becoming distracting.

Code, demo and download: https://github.com/boxyhn/anger-rate

This is the first public preview. The downloadable DMG is Apple Silicon, macOS 13+, ad-hoc signed and not yet notarized. MIT licensed.

## Korean draft

제목: Show GN: AI와 코딩하다 화가 날 때 알려주는 맥 메뉴 막대 불꽃, AngerRate

Codex와 Claude Code를 쓰다 말이 거칠어지는 순간을 알아차리고 싶어서 만들었습니다.

메뉴 막대의 작은 불꽃이 촛불 → 피어나는 불 → 타오르는 불로 변합니다. 언어 신호를 바탕으로 점수를 계산하고, 100에 도달하면 “잠깐 쉬어갈까요?”라고 한 번 알려줍니다. 시간이 지나면 불꽃도 잦아듭니다.

한영 UI와 기본 욕설 사전을 지원하고, 실시간 감지는 로컬에서 처리합니다. 선택적으로 기존 로그인된 Codex/Claude CLI로 과거 세션을 점검해 개인 기준을 제안받을 수 있습니다. 이때 대표 메시지는 해당 CLI로 전달됩니다.

감정 진단 도구는 아닙니다. 오탐이나 불꽃 움직임이 도움이 되는지 피드백을 받고 싶습니다.

소스·데모·다운로드: https://github.com/boxyhn/anger-rate

MIT 오픈소스이며 첫 공개 미리보기입니다. DMG는 Apple Silicon/macOS 13+용이고 Apple 공증 전입니다.
