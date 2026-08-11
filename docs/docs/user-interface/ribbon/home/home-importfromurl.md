# Import from URL / Zarr

<span class="widget widget-button">Import</span> -> <span class="widget widget-dropdown">URL / Zarr</span> opens a dataset
straight from the internet, without downloading it first.

Two very different sources share this dialog, and MIB decides which applies by inspecting the
URL rather than asking you:

- an **OME-Zarr container** in a cloud bucket, opened as a BigData, Virtual or Standard
  dataset. Nothing is copied to your disk: MIB reads only the parts of the volume you look at.
- **any ordinary image URL** (`.png`, `.tif`, `.jpg`), downloaded and opened as a Standard
  dataset. This is what this menu item always did, and it is unchanged.

---

## Accepted URL forms

| Form | Example |
|------|---------|
| Virtual-host S3 | `https://bucket.s3.amazonaws.com/path/store.zarr` |
| Virtual-host S3, with region | `https://bucket.s3.us-west-2.amazonaws.com/path/store.zarr` |
| Path-style S3 | `https://s3.us-west-2.amazonaws.com/bucket/path/store.zarr` |
| `s3://` shorthand | `s3://bucket/path/store.zarr` |
| Any S3-compatible host | `https://s3.your-institute.org/bucket/path/store.zarr` |
| Any other web host | `https://example.org/data/store.zarr` |

An `s3://` address is rewritten to its `https://` equivalent and shown back to you in the field,
so you can always see exactly what is being contacted. Only **public** buckets are supported:
everything is fetched anonymously, and no credentials are ever requested or stored.

### N5 addresses

MIB cannot read **N5** containers. It does not have to: repositories that publish N5 normally
publish an OME-Zarr copy of the same volume beside it, under the same name. Paste an `.n5` URL and
MIB looks for that copy, switches to it, and tells you so in the status line:

```
s3://janelia-cosem-datasets/jrc_hela-2/jrc_hela-2.n5
   -> https://janelia-cosem-datasets.s3.amazonaws.com/jrc_hela-2/jrc_hela-2.zarr
```

The swap is checked against the server, never assumed, and the rewritten address is shown in the
field. A group path inside the container is carried across, so
`.../jrc_hela-2.n5/recon-1/em/fibsem-uint8` lands on the matching group of the zarr copy. If no
copy exists, the status line says so rather than reporting a generic failure.

---

## Using the dialog

The dialog opens with the <span class="widget widget-edit">URL</span> field focused; if the
clipboard holds a link it is already there and selected, so typing or pasting replaces it.

1. Paste the URL of the **container** - the folder usually named `*.zarr` - and press
   ++enter++ (or <span class="widget widget-button">Connect</span>).
2. Expand the tree to find the group you want. Each expand fetches one directory listing, so
   browsing a huge published dataset stays quick.
3. Select a group. When it holds an image pyramid, its details appear in the panel below and
   <span class="widget widget-button">Open</span> becomes available:

    ```
    Levels : 15  (s0 .. s14)
    Axes   : zyx
    Size   : 23601 x 21451 x 49645  (X x Y x Z)
    Type   : uint8
    Voxel  : 8 x 8 x 8 nm
    Format : OME-Zarr v2  (read through Python)
    ```

4. Choose <span class="widget widget-dropdown">Load as</span> and
   <span class="widget widget-dropdown">Dataset mode</span>, then press
   <span class="widget widget-button">Open</span>.

<span class="widget widget-edit">Group path</span> shows the selection as a path relative to the
container, for example `recon-1/em/fibsem-uint8`. You can also type it directly, which is the
only option on servers that do not allow directory listing (see below).

### Ordinary image URLs

Steps 2-4 apply to OME-Zarr containers only. If the URL turns out to be a plain image file
instead, there is nothing to browse and nothing to choose, so pressing ++enter++ downloads and
opens it right away as a Standard dataset and closes the dialog - paste, ++enter++, done.

<span class="widget widget-button">Connect</span> stops short of that: it reports what the file
is and waits for <span class="widget widget-button">Open</span>. Use it when you would rather
check the URL before anything is downloaded.

### Load as

- **Image** - open the group as the dataset.
- **Labels** - load it as a segmentation model on top of the dataset that is already open. The
  label store must cover exactly the same extent as the open image; if it does not, the dialog
  says so before you press Open (see [Limitations](#limitations)).

### Dataset mode

- **BigData** *(default)* - browse and segment. The image stays remote; any model you create is
  written to a **local** folder of your choosing.
- **Virtual** - browse only. Reads the image exactly as BigData does.
- **Standard** - read one pyramid level fully into memory. Right for small groups, such as an
  annotated crop; not for a multi-terabyte volume.

---

## Worked example: Janelia OpenOrganelle

[OpenOrganelle](https://openorganelle.janelia.org) publishes its FIB-SEM volumes in a public
bucket. For the dataset `jrc_mus-liver-zon-1`:

```
https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr
```

Press ++enter++, then expand `recon-1` -> `em` -> `fibsem-uint8`. That group is a 15-level
pyramid of a `23601 x 21451 x 49645` volume at 8 nm - about 25 teravoxels. Open it as
**BigData** and browse it like any other dataset.

Other datasets in the same bucket follow the same layout; a few store the image under
`recon-1/em/tem-uint8` instead. You do not need to know which, because the tree shows you.

!!! note "Both links on an OpenOrganelle dataset page give you N5"
    The <span class="widget widget-button">Fiji</span> link and the
    <span class="widget widget-button">Copy data url</span> button on a dataset page both hand out
    the `.n5` address, for example
    `s3://janelia-cosem-datasets/jrc_hela-2/jrc_hela-2.n5`. Paste it as it is - MIB switches to the
    `.zarr` copy published alongside it. See [N5 addresses](#n5-addresses).

!!! tip
    Leaving <span class="widget widget-edit">Group path</span> empty and pressing Open makes MIB
    search the container for the image group itself, which takes a few seconds. Picking the group
    in the tree is faster and unambiguous.

---

## Requirements

Reading a remote **OME-Zarr v2** store - which is what OpenOrganelle and most published
OME-NGFF v0.4 data are - needs two Python packages beyond those a local zarr v2 store needs,
installed into the interpreter set at
[Preferences -> External directories -> Python installation path](home-preferences.md#external-directories):

```bash
"<path-to-python.exe>" -m pip install aiohttp requests
```

MIB checks for them when you press Open and tells you the exact command if they are missing.
Remote **OME-Zarr v3** stores need no Python at all.

---

## Limitations

**Speed.** The first look at any region is fetched over the network and takes roughly a second or
two per screenful at full resolution. After that it is held in memory, so scrubbing through slices
and panning within what you have already seen are effectively instant.

This works because of how OME-Zarr stores data. A *chunk* is the smallest piece a server will send,
and published volumes are usually chunked for 3D access - the Janelia C. elegans store uses
64 x 128 x 128, so **every chunk carries 64 slices**. Fetching one screenful therefore also fetches
the next 63 slices of it, and MIB now keeps them instead of discarding them:

| | First view of a region | Next slice |
|---|---|---|
| Without the cache | ~2 s | ~2 s |
| With the cache | ~2 s | **~0.01 s** |

The memory budget is **Preferences -> Input/output -> Zarr library -> Chunk Cache**, 512 MB by
default. That holds roughly eight full-resolution screenfuls of the store above; when it is full the
least recently used chunks are dropped. Setting it to 0 turns the cache off.

The image pyramid does the rest: zoomed out, MIB reads a small downsampled level rather than the
full-resolution one, so a whole-volume overview costs far less than a full-resolution screenful.

**Sub-volume annotations cannot be overlaid.** Many published containers include ground-truth
crops - small, densely annotated cubes carved out of the parent volume, often at a finer voxel
size. MIB cannot yet place such a crop at its true position on the parent volume, so loading one
with **Load as: Labels** is refused with an explanation. Open the crop itself as an **Image**
instead (in **Standard** mode, since these are small) and work on it directly.

**Browsing needs the S3 listing API - but not Amazon.** Any endpoint that answers
`ListObjectsV2` can be browsed, including institutional MinIO and Ceph servers hosted on their own
domain. MIB does not check the host name: it simply tries, and a server that does not
speak the API costs one request. When that happens the dialog says so and you type the
<span class="widget widget-edit">Group path</span> yourself; everything else works normally.

---

## Batch mode

The dialog is available in [Batch processing](home-batchprocessing.md) as
**Ribbon -> Home -> Import from URL**, with `Url`, `GroupPath`, `LoadAs`, `DatasetMode` and
`showWaitbar`. `showWaitbar` has no control in the dialog - the dialog always shows progress - and exists so a protocol can suppress it. A recorded protocol replays without browsing, so `GroupPath` should be filled in.
