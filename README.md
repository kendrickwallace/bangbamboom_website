# bangbamboom.com — teaser site

A single-page pre-launch site for **Bang Bam Boom**, a comic-creation platform
not yet open. Its one job is collecting a waitlist.

## It is a static site. There is no backend.

One HTML file, a folder of images, deployed to Netlify from this repo. The
waitlist is handled entirely by Clerk's client-side component — no server, no
database, no API, no secret.

If a serverless function ever seems necessary here, something has gone wrong.

## This repo is public

- The Clerk **publishable** key (`pk_...`) lives in `index.html`. That is by
  design — it is meant to sit in page source.
- The Clerk **secret** key (`sk_...`) must never appear here. The teaser does
  not need it and cannot use it.
- No `.env`, no database URL, no storage credential, no model-provider key.

## Layout

| Path | What it is |
|---|---|
| `index.html` | The whole site — markup, styles and the Clerk mount |
| `images/` | Logo derivatives and the five step screenshots |
| `Brand Assets/` | `BangBamBoom Logo with Alpha.png` — the 1254×1254 master |
| `netlify.toml` | Static publish + security headers. No build command |

Every logo size in `images/` is resampled from the alpha master. Always derive
from it — the flat version without alpha has hard binary edges and looks
stamped-out at small sizes.

## Going live

1. Create the Clerk **production** instance and swap `CLERK_PUBLISHABLE_KEY` in
   `index.html` from `pk_test_...` to `pk_live_...`. That one line is the only
   change; it also removes Clerk's "Development mode" badge from the panel.
2. Point **bangbamboom.com** at the Netlify site.

The app itself will live at **app.bangbamboom.com** and is hosted separately —
it is not part of this repo.

## Working on it locally

    python3 -m http.server 8123

then open <http://localhost:8123>. There is nothing to build or install.

## Notes for whoever edits this next

- **`colorNeutral` is the one that matters.** Clerk derives muted text, borders
  and dividers from it, not from `colorText`. Left at its black default,
  everything derived renders black-on-black on this ground.
- **Clerk ships its own card** — background, border, shadow, fixed width. The
  `.cl-card` / `.cl-cardBox` rules strip it so it sits *on* the panel rather
  than as a box inside a box.
- **Popovers and modals portal to `<body>`**, outside the container that mounted
  them, so they must be styled with global rules.
- **Appearance variable names moved between Clerk majors.** Both spellings are
  set, and the input is also painted directly in CSS as a backstop.
- **Never give `.step-shot` an explicit `width`.** With a definite width,
  `max-height` clamps the height without recomputing the width, and the
  screenshots render squashed. Both dimensions stay `auto`, bounded by
  `max-width` / `max-height`, so the intrinsic ratio is always preserved.
- **Headless Chrome clamps the viewport to 500px minimum.** A screenshot
  requested narrower renders at 500 and is cropped — that looks exactly like a
  horizontal-overflow bug and is not one.
