# Documentation Style

How the same feature gets written up at four different levels, and what must not leak between them.
The root [`CLAUDE.md`](../../CLAUDE.md) carries the summary table and the dash check; this file is
the reasoning and the worked examples.

Where each kind of documentation lives and how to build it:
[`docs/CLAUDE.md`](../../docs/CLAUDE.md) (user docs, Zensical/MkDocs) and
[`docs_api/CLAUDE.md`](../../docs_api/CLAUDE.md) + [docs_api_sphinx.md](docs_api_sphinx.md)
(API reference, Sphinx/RST docblock style).

---

## Match the writing to the audience

| Where | Written for | What belongs there |
|-------|-------------|--------------------|
| Widget tooltip | a user mid-task | one reminder line |
| `docs/docs/...` | general users | what the feature does and what to do; behaviour, never mechanism, and never what the screen already shows |
| RST docblocks in `.m` | developers reading the API | **full technical detail** - arguments, types, defaults, edge cases, why the code does what it does |
| `development/` | whoever revisits the design | benchmarks, measured numbers, alternatives tried and rejected |

Detail belongs at the right level and must not leak downwards.

## Tooltips stay short

A widget tooltip is a reminder, not a manual: name each option and give the one fact that decides
between them. Anything longer - trade-offs, measured numbers, failure modes - belongs in the matching
`docs/docs/user-interface/...` page, which the tooltip can point at.

## `docs/` is the level that gets over-written

Because the implementation is fresh in mind while writing it. Two failure modes, in increasing order
of how often they happen.

### Describe the behaviour, not the machinery

Write "the 3D viewer shows up to 255 materials at a time", not "MATLAB keeps the overlay colours in a
256-entry lookup table, so 255 materials plus the background". Keep entries short, and leave out
measured numbers and design rationale - if the reasoning is worth keeping, put it in `development/`
and have the code comment point there.

### If the user will see it on screen, do not write it down

Avoiding mechanism is not enough, and this is the commoner mistake: narrating plainly visible
behaviour. A `docs/` entry earns its place by saying something the interface does not - what a
setting is *for*, which of two options to pick, a consequence that shows up later or elsewhere.

The generated filename, the wording of a progress message, the fields of a dialog in order, the fact
that a suffix was added - the user meets every one of those the moment they run the tool, so spelling
them out adds length and no information. Naming a widget in order to say what it does is right;
describing what the widget shows is not.

Three habits follow:

- **No edge cases.** `docs/` states the normal behaviour. What happens when the name is empty, when
  the tool is run twice in a row, when the stack has one slice - all of that belongs in the docblock,
  where whoever hits it will look.
- **No justification.** "The suffix is there so that saving cannot overwrite the original" answers a
  question the user never asked. Rationale goes to `development/`, contracts to the docblock.
- **Re-read before you finish** and delete every sentence the user could have learned by looking at
  the screen. Deleting the whole addition is a normal outcome: most implementation details need no
  user-facing entry at all, and a feature that is self-evident in use needs none.

#### Worked example

A stitching tool that renames its output model. What was written first, and what survived review:

> ~~The model keeps the filename it was loaded from, with `_3d` added: stitching
> `Labels_stack.model` leaves the result named `Labels_stack_3d.model`, which is what **Save model**
> then offers. The suffix is there so saving cannot overwrite the 2D instance model the result was
> built from. A model created in MIB and never saved has no name to carry over and is left for the
> save dialog to name as usual.~~

Deleted entirely. The user sees the name in the save dialog; the sentence about *why* the suffix
exists is justification; the sentence about an unsaved model is an edge case. All three facts live in
the `MibDataset.stitchModelInstances` docblock, where someone debugging them will look.

The cancel behaviour of the same tool, first draft and final:

> ~~The progress dialog names the stage it is on and the slice it has reached, and can be stopped
> with its **Cancel** button. Cancelling leaves the model exactly as it was - a partly stitched
> result is never written.~~
>
> Stitching a large stack takes a while. It can be stopped at any point with **Cancel**, which
> leaves the model as it was.

The stage names and the slice counter are on screen. That cancelling is *safe* is not - the user
cannot tell by looking whether a half-stitched model was written - so that clause stays.

## Docblocks are the opposite case

Being terse there is the mistake. They are the developer reference, so an argument with a
non-obvious contract deserves the full explanation. Everything the three habits above strip out of
`docs/` has a home - the docblock for edge cases and contracts, `development/` for rationale and
measurements - so trimming a user page never loses the information.

## The long dash

**Never use the long dash.** Plain hyphen `-` (U+002D) in all documentation, code comments,
docblocks, tooltips and dialog text. Em dash `—` (U+2014) and en dash `–` (U+2013) are banned: they
render inconsistently in MATLAB tooltips and the compiled standalone app, and they are awkward to
type and to search for. Write `Feather - weighted blend`, not `Feather — weighted blend`.

**This is the rule that gets broken most often**, because an em dash is what a model reaches for when
writing English prose and nothing in the editor flags it. The check is in the root `CLAUDE.md`; run
it before finishing any task that touched `.m` files.

**Every `.m` file in the repo is dash-free**, RST docblocks included: the docblock parameter separator
is a plain hyphen (`**name** - description`), and [`docs_api/CLAUDE.md`](../../docs_api/CLAUDE.md) /
[docs_api_sphinx.md](docs_api_sphinx.md) were updated to match. Nothing in Sphinx parses that
separator, so it is purely a glyph choice.

`deployed/` is excluded from the check because it is untracked build output, regenerated from `mib/`
by `deploymentScript.m` - editing it there would be undone on the next build. The `.md` documentation
under `docs/`, `docs_api/` and `development/` has **not** been swept and still contains em dashes.
