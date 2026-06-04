# Built with AI: from design to code

GitWorkbench was built almost entirely with AI, in two phases — a **design** phase in Claude, then
an **implementation** phase handed off to **Claude Code** — with a human steering and reviewing
throughout.

## 1. Design — in Claude

The component was designed first, as a self-contained handoff package
([`docs/design_handoff/`](docs/design_handoff/)):

- An **interactive HTML/JSX prototype** of the entire UI — the three-pane layout, the diff renderer,
  every state and interaction — openable in a browser. It was the authoritative source of look and
  behavior.
- A structured spec around it: architecture and public API, the data model, a component-by-component
  view spec, exact **design tokens** (colors, typography, metrics), and interactions / accessibility.

No code yet — this phase produced the *what* and the *look*, pinned down precisely enough to hand
off with no further questions.

## 2. Implementation — handed to Claude Code

Claude Code turned the handoff into a real Swift package:

1. **Researched & specced.** It studied the handoff, researched how to drive git from Swift, and
   wrote an implementation design ([`docs/superpowers/specs/`](docs/superpowers/specs/)) capturing
   the decisions the handoff left open — a target layout that keeps the UI core dependency-free, a
   real git provider that shells out to the system `git`, the test strategy, and a build plan.
2. **Planned in small steps.** It split the work into ten focused plans
   ([`docs/superpowers/plans/`](docs/superpowers/plans/)) — foundation, design-system primitives,
   the diff renderer, the store, each view, and the git layer.
3. **Built it plan-by-plan, test-first.** Each task was implemented by a fresh sub-agent following
   TDD, then put through a two-stage review — *does it match the spec?* then *is the code sound?* —
   before moving on. One branch per plan, merged to `main`.

The result: the dependency-free **`GitWorkbench`** component, a **`GitWorkbenchGitKit`** real-git
provider, and two demo apps — faithful to the design's tokens and metrics, with 100+ tests and
**zero third-party dependencies**.

## 3. Iteration — by running it

With the component working, the rest was an interactive loop: run the live demo on a real
repository, spot something, fix or extend it, verify, repeat. Most of the "feel" came from here —
interaction bugs that unit tests and screenshots can't catch (found only by driving the live app),
plus features added on request:

- VSCode-style side-by-side diff scrolling; live filesystem refresh; full discard of staged changes.
- Click a branch to view its history (double-click to switch); resizable, persistable columns.
- Host-customizable themes that also switch at runtime — with sample themes and a menu in the demo.

Every change was held to the same bar: it had to **build**, **pass the tests**, and — for anything
visual — be **proven with a screenshot** captured from the demo. The commit history on `main` is
the record of that loop.

---

*In short: Claude turned an idea into a precise, prototyped design; Claude Code turned that design
into a tested, dependency-free Swift package and iterated it into a polished tool — a human steering
and reviewing at every step.*
