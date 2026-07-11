# CLAUDE.md

Project basics (repo layout, build/test commands, branding) live in [`README.md`](README.md) — read that first for mechanics.

## Fundamental: check the v1 app before building anything new

This repo (`jellytv`, "Why.So.Jelly?") is a **from-scratch rewrite** of an earlier project at
`/Users/xyan/code/jelly-tv-ios`. That v1 app talks directly to a real Jellyfin server (REST
client, SwiftData local store, auth/player/theme state, a working setup wizard) but got
architecturally messy, which is why this rewrite started. It is not being deleted — there is
real, working logic in it worth mining.

**Before implementing any new mechanism, screen, or capability in this repo, look at whether
`/Users/xyan/code/jelly-tv-ios` already solved it.** Concretely:

- Search its `Core/`, `iOS/`, `tvOS/`, and `docs/` for an existing implementation, component,
  or shader before designing one from scratch here.
- If something is worth bringing over, port the *idea* (and code where it's clean enough)
  deliberately — don't copy its structural mess along with it. Note in the proposal/design doc
  what was ported from where (see `openspec/changes/archive/2026-07-11-hero-carousel-transitions/`
  for the pattern: it explicitly named the v1 files a mechanism was ported from).

Do not assume this rule is satisfied just because a feature "looks new" in this repo — most of
what jellytv will eventually need (real Jellyfin browsing/playback, SwiftData, auth) already has
a first draft in v1.
