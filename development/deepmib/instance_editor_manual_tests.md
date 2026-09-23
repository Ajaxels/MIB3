# Instance editor - manual test protocol

Companion to [`split_and_merge_toolbox.md`](split_and_merge_toolbox.md). What the automated suite
cannot reach: the live window, the mouse, and real data.

> **Status: not yet run on real data.** The MitoNet benchmark and the salivary-gland stack cited in
> [`instance_3d_plan.md`](instance_3d_plan.md) are no longer on this machine, so the interactive pass
> on a real 1481-object model and the click-picking path remain to be done by hand.

Everything below needs MIB running. **Restart MIB first** - the ribbon is built at startup, so the button does not
appear in an already-open session.

Use an instance model with a few thousand objects, ideally the output of
*Ribbon -> Model -> Convert type -> Indexed objects -> Stitch 2D instances to 3D* on a real 2D
prediction stack. A small model will not show the things worth checking.

## A. Opening

| # | Do | Expect |
|---|----|--------|
| A1 | *Ribbon -> Model -> Model tools -> Instance editor*, first time this session | Window opens to the left of MIB, in **2D** mode: `3D (whole object)` unticked, connectivity 8/4 |
| A1a | Tick `3D (whole object)`, `Shortcuts` and `Pick objects by clicking`, untick the automatic list refresh, close and reopen | All four come back as they were. Then check the two takeovers really are live, not just ticked: press ++a++ over a selection and click an object. A checkbox that is on while the mouse or keys are not held is the failure to watch for |
| A1b | Reopen with the image document closed, or on a buffer with no model | `Pick objects by clicking` comes back **off** rather than ticked-but-dead |
| A1c | Set connectivity to the full neighbourhood in 3D, close, reopen | Still 3D and still `26`. Untick 3D, close, reopen: 2D and `8` - the same stance in the other mode's numbers |
| A2 | Look at the status line | `Slice N: K objects...` - the list is the shown slice, and it says so without an index having been built |
| A3 | Tick **3D (whole object)**, press **Rebuild**, look again | `N objects, highest index M`, green. Compare N with the object count the stitcher reported: same number |
| A4 | Note how long that Rebuild took | One pass over the volume; a few seconds on a 100-slice stack. **If it is much worse, say so** - the whole design rests on this being affordable |

Guards, each expecting a message and no change:

- A5 - no model at all
- A6 - a 63 or 255 material model -> *"Not an instance model"*, operations greyed out
- A7 - a **Virtual** dataset, and a **BigData** dataset -> refused with a reason

## B. The object list

In 3D mode; the 2D list is a different thing and has [group I](#i-2d-mode---the-list-follows-the-slice).

| # | Do | Expect |
|---|----|--------|
| B1 | Click a column header | Sorts by it; clicking again reverses |
| B2 | Sort by *Voxels* ascending | The dust is at the top - this is how you find noise objects |
| B3 | Sort by *Slices* ascending | Single-slice objects first |
| B4 | **Max size** 50 in the settings dialog | Only objects that small are listed as soon as it is accepted; `0` restores all |
| B5 | **Max rows** 50 on a model with thousands | Only 50 rows; the tool stays responsive |
| B5a | Reopen the dialog | Opens on the values just entered, and again after closing and reopening the editor |
| B5b | Open it in 2D mode | No **Max slices** question, and the connectivity offers 8/4 rather than 26/6 |
| B6 | Type a known index into **Go to object** | That object is selected and the view moves to it |
| B7 | Type an index that does not exist | *"There is no object N in this model"*, nothing selected |
| B8 | Click one row | View centres on the object, slice jumps to it, object appears in the Selection layer |
| B9 | Ctrl-click / shift-click several rows | All highlighted together |
| B10 | Highlight one entry in **Selected objects**, right-click, *Remove highlighted from selection* | Only that object leaves the selection and the highlight; *Clear list* empties it |
| B10a | Pick two objects by clicking in the image, then click each entry in **Selected objects** in turn | The view moves to each, and the selection still holds both - clicking there looks, it does not pick. The entry stays highlighted, so the right-click menu still has something to act on |

## C. Picking by clicking - the part no test covers

| # | Do | Expect |
|---|----|--------|
| C1 | Tick **Pick objects by clicking**, click an object | Selected and highlighted |
| C2 | Click a second object | Selection *replaces*: only the second one |
| C3 | **Shift**-click a third | Now two are selected |
| C4 | **Ctrl**-click one of them | Removed from the selection |
| C5 | Click on background | Plain click empties the selection; shift and ctrl clicks there do nothing |
| C5b | **Drag with the right mouse button** | The view pans, as with the editor closed. Then click an object: still picks. Panning is how you reach the next object, and taking over the mouse takes the pan with it unless it is handed back |
| C5c | Set *Preferences -> left mouse button* to **pan**, then click | Left drag pans, right click picks. The gestures follow the preference, they do not fight it |
| C6 | Zoom out a long way, then click a small object | The *correct* object is picked - the check that the click reads full-resolution data rather than the rendered image |
| C7 | Untick the checkbox, then use the Brush | Brush works normally again |
| C8 | Tick it again, then **close the window** with the checkbox still on | Brush and all other segmentation tools work. **This is the one that makes MIB unusable if it is broken** - the editor takes over the image mouse and sets `disableSegmentation`, and both must come back |
| C9 | With pick mode on: run an operation, change slice, switch ribbon tab, then click an object | Still picks. Watch for silence in DeveloperMode: no `imageButtonDown` line means the mouse was lost again |
| C10 | With pick mode on, switch to another buffer | The mouse is handed back to the first document; the checkbox clears |

## D. Operations

Undo (++ctrl+z++) after **every** one of these and confirm the model returns exactly as it was.

| # | Do | Expect |
|---|----|--------|
| D0 | After any applied operation | The selection and its highlight are empty, ready for the next pick. A rejected operation leaves the selection alone |
| D1 | Select two objects, **Merge** | One object, carrying the **smaller** of the two indices |
| D1b | Brush one shape across two objects, pick nothing, **Merge** | Same result. The whole of both objects is joined, not just the part under the shape, and the shape is gone afterwards |
| D1c | Brush a shape half over one object and half onto background, pick nothing, **Merge** | The object grows by the new part, keeps its index, and no new index is handed out. Check its voxel count before and after |
| D1d | Brush a shape on empty background, pick nothing, **Merge** | It becomes a new object with the next free index, listed with exactly the drawn voxels, and the shape is used up |
| D2 | Merge three at once | All take the smallest index |
| D3 | Find an object whose index covers two separate blobs, **Split components** | Largest piece keeps the index; the other gets a new one. Both listed |
| D4 | **Split components** on a normal object | Nothing happens, no error |
| D5 | Move to a slice in the middle of an object, **Cut at slice** | Everything from that slice onwards becomes a new object |
| D6 | **Cut at slice** on the object's first slice, and on a slice outside it | Refused with a message naming the object's slice range |
| D7 | Two objects with a Z gap, **Connect** (`interpolate`) | Gap filled, both now one object with the smaller index |
| D7a | In 3D, brush the slice an object is missing from, pick nothing, press ++a++ (or **Merge**) | The object above and below takes the brushed area and keeps its index. The same gesture as D1c, one slice further |
| D7a1 | Do it where the object below the stroke is a **different** object from the one above | Only the better covered one takes it; the other keeps every voxel and its own index. They are now touching, so **Connect** joins them if that is what you wanted. Joining both automatically is what this used to do |
| D7b | The same with the stroke slightly too wide, clipping the corner of a neighbour on z-1 | Only the object it mostly lands on is taken. Check the neighbour's voxel count before and after |
| D7b1 | In 3D, find an object missing from one slice. Brush the gap so the stroke also catches the neighbour beside it by a few pixels, pick nothing, ++a++ | The gap goes to the object above and below, and the neighbour keeps every voxel - check its count before and after. This used to hand the whole stroke to the neighbour |
| D7b2 | The same, but brush the shape squarely over the neighbour instead | It goes to the neighbour, which is how an object is grown in-plane. Covering beats clipping |
| D7c | Brush a shape whose far end reaches nothing, pick nothing, ++a++ | The object at the near end grows by the shape and keeps its index. On empty space at both ends it becomes a new object instead (D1d) |
| D7d | Brush a stroke straight across two objects **on the same slice**, pick nothing, ++a++ | Those two are joined, not whatever lies above and below. What the drawing covers is asked first |
| D7e | The **same drawing as D7a**, but in 2D mode | It becomes a new object on that slice. The reach is a property of 3D mode, not of the gesture |
| D7f | Repeat D7a with **Connect** instead of ++a++, nothing picked | Identical result - the two are the same code once nothing is picked, and `Connect Mode` is not consulted. Pick the two objects and it becomes the `interpolate`/`selection` operation again, the only form that still joins two objects from one press |
| D8 | **Connect** across a gap with a *third* object sitting in it | The third object is untouched. Check its voxel count before and after |
| D9 | Brush a bridge into the Selection layer, **Connect** (`selection`) | Only the brushed area is used |
| D10 | **Connect** on three objects | Refused |
| D11 | Select some noise, **Delete** | Gone; index freed and reused by the next split |

## E. The brush workflow

The reason the tool exists. On a false merge - one index covering two mitochondria:

1. Brush the break into the **Selection** layer where the two should separate.
2. In 3D, brush it on a few slices and press ++i++ to interpolate between them.
3. Press **Split by selection**. Nothing needs to be picked - the drawing says what to cut. Pick an
   object only to keep the cut off a neighbour the line also crosses.

Expect: the brushed voxels are cleared out of the object and the two halves become separate objects,
in **one** ++ctrl+z++ step. Compare against doing it by hand (++shift+s++ to subtract, then **Split
components**) - the result should be the same.

The editor borrows the Selection layer for its highlight, so the drawing and the highlight share it:

| # | Do | Expect |
|---|----|--------|
| E0 | Brush a break, pick nothing, **Split by selection** | The object under the drawing is split. No *"pick the objects to work on first"* |
| E0b | Brush a line crossing two objects, pick nothing, split | Both are cut. Then pick one of them first and repeat: only that one is cut |
| E0c | Brush somewhere on background only, split | *"The Selection layer does not cover any object"*, and the drawing is still there to be moved |
| E0d | Brush over the **whole** of one object, pick nothing, split | The object is removed and its index freed - no *"nothing would be left"*. ++ctrl+z++ brings it back |
| E0e | The same in 2D, on an object spanning several slices | It goes from the shown slice only; the list still has it on the others, under the same number |
| E0f | Pick an object by clicking, draw **nothing**, press ++s++ | The object is removed - the highlight in the Selection layer is what the key subtracts. It used to sit there unchanged while the operation reported success |
| E0g | Pick an object, brush a break across it and a neighbour, press ++s++ | Only the picked one is cut, and it is **cut**, not removed. The pick stands in for the drawing only when there is no drawing |
| E1 | Brush a break, then pick the object | The object lights up. The break is underneath it and the split below still works - this is the sequence that used to fail with *"covers the whole of object N"* |
| E2 | Draw somewhere else in the dataset, then pick an object | The drawing is still there. Picking used to clear the whole layer, on every click |
| E3 | Split by selection, then look at the Selection layer | The drawing that was used is gone; the rest of the layer is untouched |
| E4 | Pick an object, then start brushing on it | The highlight disappears at the first stroke and drawing behaves normally. The stroke that cleared it is not kept - draw first, pick second |
| E5 | Pick an object, close the editor | The Selection layer is what you drew, not the object that was highlighted |
| E6 | Brush a bridge in a Z gap, pick two objects, **Connect** (`selection`) | The bridge is used, not the highlight |

## F. Staleness - the correctness one

| # | Do | Expect |
|---|----|--------|
| F1 | With the editor open, brush on the model in the main window | Status line turns red: *"Index is out of date"* |
| F2 | Now run any operation | It rebuilds the index first, then acts - and acts on the **right** voxels |
| F3 | ++ctrl+z++ after a **brush stroke on the model** | Status goes red - a stroke leaves no repair note |
| F3a | ++ctrl+z++ after an **editor operation** | Status stays green and the object count follows the undo. No rebuild, no pause: the undo entry carried the region. Press again to redo - still green |
| F3b | Time F3a on the largest model you have | Instant whatever the size. If it pauses, the note was not recognised and it fell back to a rebuild - the DeveloperMode line `repairIndexAfterUndo: index repaired over [...]` says which happened |
| F4 | Press **Rebuild** | Green, with the object count matching the model |
| F5 | Change time point on a 4D dataset | The list follows the shown time point |

The failure to watch for: an operation that edits *somewhere other than the object you picked*. That
is what a stale bounding box does, and it is silent.

## G. Cleanup and Compact

| # | Do | Expect |
|---|----|--------|
| G1 | **Cleanup**, **Min object size** 50 | Small objects gone; **the survivors keep their numbers** |
| G2 | **Cleanup**, **Min object depth** 1 | Single-slice objects gone |
| G3 | **Cleanup**, **Absorb fragments** 5 | Object count drops but the labelled voxel total barely moves - specks are handed to neighbours, not deleted |
| G3a | Press **Cleanup** again | The dialog opens on the values just used |
| G3b | Cancel the dialog | Nothing runs, and the previous values survive |
| G3c | Set values through the gear button, then press **Cleanup** | The dialog opens on them; accepting cleans with them |
| G3d | Close and reopen the editor | The dialog still opens on the last values - they live in `sessionSettings`, not the window |
| G3e | Let a cleanup finish | A box reports what was removed, what was absorbed and what is left, and reminds you the numbers did not change |
| G4 | Cancel the progress dialog mid-run | Model unchanged, and the note goes to the command window rather than a box |
| G5 | **Compact** | Numbering becomes 1..N with no gaps |
| G5a | Read the box it puts up | How many objects were renumbered, how many kept their number, and the highest index before and after. On a model with gaps the reclaimed count should equal the drop in the highest index |
| G5b | **Compact** in 2D mode, then cancel the progress dialog part way | The model is unchanged - the slice loop writes into a copy and commits only at the end |
| G6 | ++ctrl+z++ after Cleanup and after Compact | Both restore fully |

## H. Persistence and batch

| # | Do | Expect |
|---|----|--------|
| H1 | Save the model, reload it, reopen the editor | Same objects, same indices |
| H2 | Open *Ribbon -> Home -> Batch processing* | *Ribbon -> Model -> Instance editor* is listed with all its options |
| H3 | Run a Merge from a batch protocol | Works without opening the window |

## I. 2D mode - the list follows the slice

Do this group on an **unstitched** model, straight out of the 2D predictor, where the numbering
restarts on every slice. Untick **3D (whole object)** first.

| # | Do | Expect |
|---|----|--------|
| I1 | Look at the list | Two columns, *Index* and *Pixels*. No *Slices*, no *Z range* - those describe the whole stack and mean nothing here |
| I2 | Compare the row count with what is on screen | The list is the objects **on this slice**, not the whole model. This is the bug that prompted the group: it used to report every object as spanning slices 1-501 |
| I3 | Open the detection settings | No slice filter is offered - there is no slice count to filter on here |
| I3a | **Cut at slice**, **Connect**, **Connect Mode** | All greyed out - both operations work along Z. Connect in particular used to stay live and merge the whole of both objects through the stack, ignoring the mode |
| I3b | **Cleanup**, **Compact**, the gear button | Still live. They read the whole volume whatever the mode says, which is intended |
| I3c | **Update list**, **Update the list on slice change** | Both live here; both greyed out in 3D mode |
| I3d | **Compact** here, on an unstitched model | Each slice is renumbered on its own: a slice holding 1, 3, 5 becomes 1, 2, 3. Check two slices with different gaps. The same press in 3D closes nothing on such a model, every value being in use somewhere - that is the difference the mode makes |
| I4 | Status line | *"Slice N: K objects; M in the whole model"* |
| I5 | Move one slice with **Update the list on slice change** ticked | The list re-reads, and the status line names the new slice |
| I6 | Time how long a slice step takes on the full-size stack | Should be unnoticeable. **If scrolling has become sluggish, say so** - that is what the checkbox is there to switch off |
| I7 | Untick it, move several slices | List unchanged; status line turns orange and says which slice it is describing versus where the image is |
| I8 | Press **Update list** | Catches up to the shown slice |
| I9 | Pick an object, then move to another slice with the automatic update on | The selection is dropped - the same number on the new slice is a different object |
| I10 | Pick an object | Only the shown slice is highlighted, not every slice carrying that number |
| I11 | Click a row | The view centres on the object and **stays on the current slice** |
| I12 | **Go to object** with a number on another slice but not this one | *"There is no object N on slice M"* |
| I13 | Split or delete an object, without moving slice | The list re-reads by itself and shows the result |
| I14 | Switch **3D (whole object)** back on | The list becomes the whole model again, with all four columns |

## J. The keyboard shortcuts

Group **C** is the same set of hazards for the mouse; this is the one for the keys.

| # | Do | Expect |
|---|----|--------|
| J0 | With the editor focused, press ++ctrl+z++ after any edit | It undoes, checkbox or no checkbox. Then click a button or a table row and try again. Also ++i++ and the arrow keys: **no** key at all used to reach MIB from this window |
| J1 | Tick **Shortcuts**, hover an object, ++ctrl+f++ | Selected and highlighted |
| J2 | Hover a second object, ++ctrl+f++ | Both are selected - it adds, unlike a plain click |
| J3 | Press ++a++ | They merge, exactly as the button does |
| J3a | Brush on empty background and press ++a++; then brush onto an existing object and press ++a++ again | A new object, then that object grown - D1d and D1c from the keyboard. This is the whole point of the key: paint what the prediction missed and commit it without leaving the brush |
| J3b | Pick two objects with ++ctrl+f++, draw a shape, press ++c++ | The list, the highlight **and** the drawing are all gone. ++shift+c++ clears the layer through the stack, as it does in MIB |
| J4 | Brush a break, press ++s++ | The object under the drawing splits |
| J5 | Press ++shift+a++ and ++shift+s++ | Same as without shift. **Nothing is added to or subtracted from the material** - that is the failure to watch for, and it is silent |
| J6 | Press ++ctrl+a++, ++alt+s++, ++i++, ++c++ | MIB's own behaviour, untouched |
| J7 | Untick the checkbox, press ++a++, ++s++ and ++c++ over a selection | Add to material, subtract from material and clear selection are back |
| J8 | Tick it, then **close the window** | Same as J7. **This is the one that makes MIB confusing if it is broken** |
| J9 | Tick it, then switch to a dataset with no model (or a 63-material one), press ++a++ | MIB's own shortcut runs. The editor declines keys it cannot act on rather than swallowing them |
| J10 | Tick it and type into **Go to object** | The number goes in; the keys are not stolen from the field |

## What to report back

- The A4 index-build time and the object count it was measured on.
- **I2** and **I6** - whether the 2D list now describes the slice, and what a slice step costs.
- Anything in **C8** or **F** - those two can do real damage.
- Whether the operations are fast enough to work through a model object by object, which is the whole
  point of the bounding-box design.
