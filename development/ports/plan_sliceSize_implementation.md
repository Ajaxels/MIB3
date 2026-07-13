# Plan: Add `sliceSize` Property to MibImage

## Implementation Status

**Status: ✅ COMPLETE** — implemented 2026-05-20; converted to N×2 matrix format 2026-05-20

All 23 changes across 21 files were applied in a single session. Subsequently, the `sliceSize` representation was changed from a cell array to an **N×2 double matrix** — all 11 affected files updated in the same session.

| # | File | Status |
|---|------|--------|
| 1 | `mib/+core/@MibImage/MibImage.m` | ✅ done |
| 2 | `mib/+core/@MibImage/initializeImgInfo.m` | ✅ done |
| 3 | `mib/+core/@MibImage/initialize.m` | ✅ done |
| 4 | `mib/+core/@MibImage/getMeta.m` | ✅ done |
| 5 | `mib/+core/@MibImage/setMeta.m` | ✅ done |
| 6 | `mib/+core/@MibVirtualImage/initialize.m` | ✅ done |
| 7 | `mib/+io/+loaders/BaseImageLoader.m` | ✅ done |
| 8a | `mib/+io/+loaders/ImreadLoader.m` | ✅ done |
| 8b | `mib/+io/+loaders/BioFormatsStdLoader.m` | ✅ done |
| 8c | `mib/+io/+loaders/NrrdLoader.m` | ✅ done |
| 8d | `mib/+io/+loaders/MibImgLoader.m` | ✅ done |
| 8e | `mib/+io/+loaders/VideoReaderLoader.m` | ✅ done |
| 8f | `mib/+io/+loaders/ImodLoader.m` | ✅ done |
| 8g | `mib/+io/+loaders/HDF5NoHeaderLoader.m` | ✅ done |
| 8h | `mib/+io/+loaders/HDF5HeaderLoader.m` | ✅ done |
| 8i | `mib/+io/+loaders/AmiraMeshLoader.m` | ✅ done |
| 9 | `mib/+core/@MibDataset/initialize.m` | ✅ done |
| 10 | `mib/+core/@MibImage/insertSlice.m` | ✅ done |
| 11 | `mib/+core/@MibVirtualImage/insertSlice.m` | ✅ done |
| 12 | `mib/+core/@MibDataset/insertSlice.m` | ✅ done |
| 13 | `mib/+core/@MibImage/crop.m` | ✅ done |
| 14 | `mib/+controllers/@ResampleDataset/ResampleDataset.m` | ✅ done |
| 15 | `mib/+core/@MibImage/save.m` | ✅ done |
| 16 | `mib/+core/@MibLabels/save.m` | ✅ done |
| 17 | `mib/+core/@MibLabels63/save.m` | ✅ done |
| 18 | `mib/+core/@MibDataset/saveImage.m` | ✅ done |
| 19 | `mib/+io/+savers/BaseSaver.m` | ✅ done |
| 20 | `mib/+io/+savers/TiffSaver.m` | ✅ done |
| 21 | `mib/+io/+savers/PngSaver.m` | ✅ done |
| 22 | `mib/+io/+savers/JpgSaver.m` | ✅ done |
| 23 | `mib/+io/+savers/MatlabSaver.m` | ✅ done |

---

## Post-implementation revision: cell array → N×2 matrix

After the initial 23-change implementation, the `sliceSize` format was revised from a cell array to a plain N×2 double matrix. The following 11 files were updated:

| File | Changes |
|------|---------|
| `mib/+core/@MibImage/MibImage.m` | property comment updated |
| `mib/+core/@MibImage/initializeImgInfo.m` | docstring type updated to `double[N×2]` |
| `mib/+io/+loaders/BaseImageLoader.m` | `generateSliceSizes`: `zeros(N,2)` + `repmat([h,w],[N,1])` |
| `mib/+core/@MibImage/insertSlice.m` | `options.sliceSizes=[]`; `size(...,1)` checks; `(1:k,:)` indexing |
| `mib/+core/@MibVirtualImage/insertSlice.m` | same as above |
| `mib/+core/@MibImage/crop.m` | `{}` → `[]`; `numel>1` → `size(...,1)>1`; `(z1:…)` → `(z1:…,:)` |
| `mib/+controllers/@ResampleDataset/ResampleDataset.m` | `= {}` → `= []` (×2) |
| `mib/+core/@MibImage/save.m` | `= {}` → `= []` |
| `mib/+core/@MibLabels/save.m` | `= {}` → `= []` |
| `mib/+core/@MibLabels63/save.m` | `= {}` → `= []` |
| `mib/+core/@MibDataset/saveImage.m` | `= {}` → `= []` |
| `mib/+core/@MibDataset/insertSlice.m` | `sliceSizes = {}` → `= []` |
| `mib/+io/+savers/TiffSaver.m` | `numel==nD` → `size(...,1)==nD`; `{z}` → `(z,:)` |
| `mib/+io/+savers/PngSaver.m` | same |
| `mib/+io/+savers/JpgSaver.m` | same |
| `mib/+io/+savers/MatlabSaver.m` | `numel==nZ` → `size(...,1)==nZ`; `{z}` → `(z,:)` |

Key access patterns after conversion:
- **Empty check:** `isempty(sliceSize)` — `[]` is empty, `size([],1)` = 0
- **Row count:** `size(sliceSize, 1)` — not `numel` (which = 2×N for a matrix)
- **Per-slice access:** `sliceSize(z, :)` — returns `[1×2]` row vector
- **Expansion:** `repmat([h, w], [N, 1])` — produces N×2 matrix
- **Trimming:** `sliceSize(z1:z2, :)` — preserves N×2 shape

---

## Context

When MIB3 combines images of different sizes during loading, smaller slices are padded to `max(height)×max(width)` with background fill. The original per-slice dimensions are lost. This makes it impossible to restore individual slice sizes when saving as 2D sequences or exporting segmentation models.

**Goal:** Add a `sliceSize` property to `MibImage` that mirrors the existing `sliceName` lifecycle, tracking `[height, width]` per slice. Propagate to labels/mask layers. When saving as 2D sequences, offer a dialog to crop each slice back to its original dimensions.

**Format:** N×2 double matrix where each row is `[height, width]`. Empty `[]` when all slices share the same size.
> ⚠️ **Design revision (2026-05-20):** Originally planned as a cell array `{[h1,w1]; [h2,w2]; ...}`. Changed to N×2 matrix before merge — cleaner for uniform numeric data. All code uses `size(sliceSize, 1)` for row count, `sliceSize(z, :)` for per-slice access, `repmat([h,w], [N,1])` for expansion, and `[]` (not `{}`) for empty.

**Design decisions:**
- `[height, width]` only — no color channel tracking
- Clear `sliceSize` when X/Y crop is applied (original sizes no longer restorable)
- Clear `sliceSize` when Z, H, or W changes during resample/resize
- Sync `sliceSize` from image to labels/mask layers at all modification points
- Implement saver dialog for "Restore original slice dimensions" in TiffSaver, PngSaver, JpgSaver, MatlabSaver

---

## Change 1: Property declaration

**File:** `mib/+core/@MibImage/MibImage.m`

The property is declared in the `properties` block. MibLabels and MibLabels63 inherit this automatically.

After the existing `sliceName` property (lines 80-81), add the new property. The existing code:
```matlab
        sliceName
        % a cell array of slice filenames that composing the dataset
        time
```

Change to:
```matlab
        sliceName
        % a cell array of slice filenames that composing the dataset
        sliceSize
        % a cell array of original [height, width] per slice; empty when all slices share the same size
        time
```

---

## Change 2: Metadata dictionary default

**File:** `mib/+core/@MibImage/initializeImgInfo.m`

Add `"SliceSize"` key after `"SliceName"` in the dictionary constructor. The existing code at lines 147-148:
```matlab
    "SliceName",        {[]},                                     ...
    "pixSize",          {utils.defaults.initializePixSize()},     ...
```

Change to:
```matlab
    "SliceName",        {[]},                                     ...
    "SliceSize",        {[]},                                     ...
    "pixSize",          {utils.defaults.initializePixSize()},     ...
```

Also update the docstring. After the `'SliceName'` doc line (line 50):
```
%     - ``'SliceName'`` — (cell) per-slice source filenames; default ``{}``
```

Add:
```
%     - ``'SliceSize'`` — (cell) per-slice original ``[height, width]``; default ``{}``
```

---

## Change 3: Initialize from meta

**File:** `mib/+core/@MibImage/initialize.m`

After line 83 where `sliceName` is read, add `sliceSize`. The existing code at lines 82-84:
```matlab
    obj.filename = meta{'Filename'};
    obj.sliceName = meta{'SliceName'};
    obj.lutColors = meta{'lutColors'};
```

Change to:
```matlab
    obj.filename = meta{'Filename'};
    obj.sliceName = meta{'SliceName'};
    obj.sliceSize = meta{'SliceSize'};
    obj.lutColors = meta{'lutColors'};
```

---

## Change 4: getMeta — export to dictionary

**File:** `mib/+core/@MibImage/getMeta.m`

Add `'SliceSize'` to the `initializeImgInfo` call. The existing code at lines 44-45:
```matlab
    'SliceName',        obj.sliceName, ...
    'pixSize',          obj.pixSize, ...
```

Change to:
```matlab
    'SliceName',        obj.sliceName, ...
    'SliceSize',        obj.sliceSize, ...
    'pixSize',          obj.pixSize, ...
```

---

## Change 5: setMeta — import from dictionary

**File:** `mib/+core/@MibImage/setMeta.m`

After line 43 where `sliceName` is set, add `sliceSize`. The existing code at lines 43-44:
```matlab
obj.sliceName   = meta{'SliceName'};
obj.pixSize     = meta{'pixSize'};
```

Change to:
```matlab
obj.sliceName   = meta{'SliceName'};
obj.sliceSize   = meta{'SliceSize'};
obj.pixSize     = meta{'pixSize'};
```

---

## Change 6: Virtual image initialize

**File:** `mib/+core/@MibVirtualImage/initialize.m`

After line 116 where `sliceName` is set, add `sliceSize`. The existing code at lines 116-118:
```matlab
obj.sliceName = meta{'SliceName'};

if ~isempty(meta{'ColorType'})
```

Change to:
```matlab
obj.sliceName = meta{'SliceName'};
obj.sliceSize = meta{'SliceSize'};

if ~isempty(meta{'ColorType'})
```

---

## Change 7: Loading — new generateSliceSizes method

**File:** `mib/+io/+loaders/BaseImageLoader.m`

Add a new protected method `generateSliceSizes` immediately after the closing `end` of `generateSliceNames` (after line 445) and before the existing `finalizeImgInfo` method (line 447).

The existing code at lines 445-447:
```matlab
        end

        function imginfo = finalizeImgInfo(~, imginfo, files, filename)
```

Change to:
```matlab
        end

        function imginfo = generateSliceSizes(~, files, imginfo)
            % GENERATESLICESIZES - Generate per-slice original dimensions when sizes differ.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imginfo = obj.generateSliceSizes(files, imginfo)
            %
            % This method creates a cell array of [height, width] vectors per slice
            % when the loaded files have different spatial dimensions. When all files
            % share the same height and width, the method does nothing (SliceSize
            % stays at its default empty value), avoiding unnecessary overhead.
            %
            % Input Arguments:
            %   - **files** — structure array with file information:
            %
            %     - ``.height`` — [numeric] image height for this file
            %     - ``.width`` — [numeric] image width for this file
            %     - ``.noLayers`` — [numeric] number of layers per file
            %
            %   - **imginfo** — dictionary with image metadata
            %
            % Output Arguments:
            %   - **imginfo** — updated dictionary with ``'SliceSize'`` field
            %     (cell array of ``[height, width]`` per slice) when dimensions differ;
            %     unchanged otherwise
            %
            % **Example 1** — generate slice sizes and display the first one:
            %
            %   .. code-block:: matlab
            %
            %      imginfo = obj.generateSliceSizes(files, imginfo);
            %      disp(imginfo{"SliceSize"}{1});  % e.g. [512, 256]
            %

            heights = [files.height];
            widths  = [files.width];
            if numel(unique(heights)) > 1 || numel(unique(widths)) > 1
                totalLayers = sum([files.noLayers]);
                SliceSize = cell(totalLayers, 1);
                index = 1;
                for fileId = 1:numel(files)
                    endIdx = index + files(fileId).noLayers - 1;
                    SliceSize(index:endIdx) = {[files(fileId).height, files(fileId).width]};
                    index = endIdx + 1;
                end
                imginfo{"SliceSize"} = SliceSize;
            end
        end

        function imginfo = finalizeImgInfo(~, imginfo, files, filename)
```

---

## Change 8: Call generateSliceSizes from all 9 loaders

In each loader, add one line immediately after the existing `generateSliceNames` call:
```matlab
imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8a. ImreadLoader
**File:** `mib/+io/+loaders/ImreadLoader.m`

Existing code at lines 443-444:
```matlab
            % use io.BaseImageLoader.generateSliceNames of the parent class
            imginfo = obj.generateSliceNames(files, imginfo);
```

Change to:
```matlab
            % use io.BaseImageLoader.generateSliceNames of the parent class
            imginfo = obj.generateSliceNames(files, imginfo);
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8b. BioFormatsStdLoader
**File:** `mib/+io/+loaders/BioFormatsStdLoader.m`

Find line 448 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8c. NrrdLoader
**File:** `mib/+io/+loaders/NrrdLoader.m`

Find line 251 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8d. MibImgLoader
**File:** `mib/+io/+loaders/MibImgLoader.m`

Find line 233 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8e. VideoReaderLoader
**File:** `mib/+io/+loaders/VideoReaderLoader.m`

Find line 262 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8f. ImodLoader
**File:** `mib/+io/+loaders/ImodLoader.m`

Find line 263 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8g. HDF5NoHeaderLoader
**File:** `mib/+io/+loaders/HDF5NoHeaderLoader.m`

Find line 346 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8h. HDF5HeaderLoader
**File:** `mib/+io/+loaders/HDF5HeaderLoader.m`

Find line 571 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

### 8i. AmiraMeshLoader
**File:** `mib/+io/+loaders/AmiraMeshLoader.m`

Find line 299 (`imginfo = obj.generateSliceNames(files, imginfo);`) and add after it:
```matlab
            imginfo = obj.generateSliceSizes(files, imginfo);
```

---

## Change 9: Sync sliceSize to labels during MibDataset.initialize

**File:** `mib/+core/@MibDataset/initialize.m`

When building `labelsMeta`, include `SliceSize` from the image. The existing code at lines 77-83:
```matlab
            labelsMeta = core.MibImage.initializeImgInfo( ...
                'pixSize', obj.image.pixSize, ...
                'Height',  obj.image.height, ...
                'Width',   obj.image.width,  ...
                'Depth',   obj.image.depth,  ...
                'Time',    obj.image.time,   ...
                'Colors',  1);
```

Change to:
```matlab
            labelsMeta = core.MibImage.initializeImgInfo( ...
                'pixSize',   obj.image.pixSize, ...
                'Height',    obj.image.height, ...
                'Width',     obj.image.width,  ...
                'Depth',     obj.image.depth,  ...
                'Time',      obj.image.time,   ...
                'Colors',    1, ...
                'SliceSize', obj.image.sliceSize);
```

This ensures that when labels are created during dataset initialization, they inherit the image's `sliceSize`.

---

## Change 10: MibImage.insertSlice — sliceSize update

**File:** `mib/+core/@MibImage/insertSlice.m`

### 10a. Add options default

The existing code at line 68:
```matlab
if ~isfield(options, 'sliceNames');               options.sliceNames = {};             end
```

Change to:
```matlab
if ~isfield(options, 'sliceNames');               options.sliceNames = {};             end
if ~isfield(options, 'sliceSizes');               options.sliceSizes = {};             end
```

### 10b. Add sliceSize update block after sliceName block

The existing code at lines 134-137 (end of sliceName block, before the time branch):
```matlab
        obj.sliceName = sliceNames;
    end

% -----------------------------------------------------------------------
else  % time
```

Change to:
```matlab
        obj.sliceName = sliceNames;
    end

    % ---- update sliceSize ----
    if ~isempty(obj.sliceSize)
        sliceSizes = obj.sliceSize;
        if numel(sliceSizes) == 1; sliceSizes = repmat(sliceSizes, [D1_z 1]); end

        sliceSizesNew = options.sliceSizes;
        if isempty(sliceSizesNew); sliceSizesNew = {[D2_y, D2_x]}; end
        if numel(sliceSizesNew) == 1; sliceSizesNew = repmat(sliceSizesNew, [D2_z 1]); end

        if insertPosition == D1_z+1
            sliceSizes = [sliceSizes; sliceSizesNew];
        elseif insertPosition == 1
            sliceSizes = [sliceSizesNew; sliceSizes];
        else
            sliceSizes = [sliceSizes(1:insertPosition-1); sliceSizesNew; sliceSizes(insertPosition:end)];
        end
        obj.sliceSize = sliceSizes;
    end

% -----------------------------------------------------------------------
else  % time
```

### 10c. Update the docstring

After the `sliceNames` option doc (line 23):
```
%     - ``.sliceNames`` — cell array of names for the inserted depth slices (default {})
```

Add after it:
```
%     - ``.sliceSizes`` — cell array of [height, width] for the inserted slices (default {})
```

Update the "After the call" doc (line 30) from:
```
%   obj.data{1}, obj.height, obj.width, obj.depth, obj.colors, obj.time,
%   obj.dim_yxzct, obj.sliceName (when applicable)
```

To:
```
%   obj.data{1}, obj.height, obj.width, obj.depth, obj.colors, obj.time,
%   obj.dim_yxzct, obj.sliceName, obj.sliceSize (when applicable)
```

---

## Change 11: MibVirtualImage.insertSlice — sliceSize update

**File:** `mib/+core/@MibVirtualImage/insertSlice.m`

### 11a. Add options default

The existing code at line 44:
```matlab
if ~isfield(options, 'sliceNames'); options.sliceNames = {}; end
```

Change to:
```matlab
if ~isfield(options, 'sliceNames'); options.sliceNames = {}; end
if ~isfield(options, 'sliceSizes'); options.sliceSizes = {}; end
```

### 11b. Add sliceSize update block

After the sliceName block (ends at line 102), before the function's closing `end` at line 104. The existing code at lines 101-104:
```matlab
    obj.sliceName = sliceNames;
end

end
```

Change to:
```matlab
    obj.sliceName = sliceNames;
end

% ---- update sliceSize ----
if ~isempty(obj.sliceSize)
    sliceSizes = obj.sliceSize;
    if numel(sliceSizes) == 1; sliceSizes = repmat(sliceSizes, [D1_z 1]); end

    sliceSizesNew = options.sliceSizes;
    if isempty(sliceSizesNew); sliceSizesNew = {[0, 0]}; end
    if numel(sliceSizesNew) == 1; sliceSizesNew = repmat(sliceSizesNew, [nNew 1]); end

    if insertPosition == D1_z+1
        sliceSizes = [sliceSizes; sliceSizesNew];
    elseif insertPosition == 1
        sliceSizes = [sliceSizesNew; sliceSizes];
    else
        sliceSizes = [sliceSizes(1:insertPosition-1); sliceSizesNew; sliceSizes(insertPosition:end)];
    end
    obj.sliceSize = sliceSizes;
end

end
```

**Note:** Uses `nNew` (not `D2_z`) — that's the variable used in MibVirtualImage.insertSlice for the number of new slices. Uses `{[0, 0]}` as default because virtual images don't have pixel data dimensions available at this point.

### 11c. Update docstring

After the `sliceNames` option doc (around line 22):
```
%     - ``.sliceNames`` — cell array of names for the inserted slices (default {})
```

Add:
```
%     - ``.sliceSizes`` — cell array of [height, width] for the inserted slices (default {})
```

Update the "After the call" doc (line 28) from:
```
%   obj.data, obj.Virtual, obj.depth, obj.dim_yxzct, obj.sliceName (when applicable)
```

To:
```
%   obj.data, obj.Virtual, obj.depth, obj.dim_yxzct, obj.sliceName, obj.sliceSize (when applicable)
```

---

## Change 12: MibDataset.insertSlice — extract, pass, and sync sliceSize

**File:** `mib/+core/@MibDataset/insertSlice.m`

### 12a. Extract SliceSize from meta

After the sliceNames extraction block (lines 132-136), add parallel extraction. The existing code at lines 132-142:
```matlab
% ---- extract slice names from meta (used by image.insertSlice) ----
sliceNames = {};
if ~isempty(meta) && isa(meta, 'dictionary') && isKey(meta, 'SliceName')
    sliceNames = meta{'SliceName'};
end

% -----------------------------------------------------------------------
if strcmp(options.dim, 'depth')
% -----------------------------------------------------------------------
    imgOpts.BackgroundColorIntensity = BackgroundColorIntensity;
    imgOpts.sliceNames               = sliceNames;
```

Change to:
```matlab
% ---- extract slice names from meta (used by image.insertSlice) ----
sliceNames = {};
if ~isempty(meta) && isa(meta, 'dictionary') && isKey(meta, 'SliceName')
    sliceNames = meta{'SliceName'};
end

% ---- extract slice sizes from meta (used by image.insertSlice) ----
sliceSizes = {};
if ~isempty(meta) && isa(meta, 'dictionary') && isKey(meta, 'SliceSize')
    sliceSizes = meta{'SliceSize'};
end

% -----------------------------------------------------------------------
if strcmp(options.dim, 'depth')
% -----------------------------------------------------------------------
    imgOpts.BackgroundColorIntensity = BackgroundColorIntensity;
    imgOpts.sliceNames               = sliceNames;
    imgOpts.sliceSizes               = sliceSizes;
```

### 12b. Sync sliceSize from image to labels after depth insertion

After the image insertSlice call and the labels/mask/selection insertSlice calls, sync sliceSize. The existing code at lines 148-174 (after the image insert, the labels/mask/selection inserts happen through line 173, followed by annotation shift). After all layer insertions but before annotations (line 176), add a sync block.

Find this existing code at lines 173-176:
```matlab
        end
        if options.showWaitbar; wb.Value = 0.85; end

        % ---- shift annotations: labelPositions = [z, x, y, t] ----
```

Change to:
```matlab
        end
        if options.showWaitbar; wb.Value = 0.85; end

        % ---- sync sliceSize from image to label layers ----
        if ~isempty(obj.image.sliceSize)
            if obj.labels.exists; obj.labels.sliceSize = obj.image.sliceSize; end
            if isa(obj, 'core.MibDataset') && ~isa(obj.labels, 'core.MibLabels63')
                if obj.maskExist; obj.mask.sliceSize = obj.image.sliceSize; end
            end
        end

        % ---- shift annotations: labelPositions = [z, x, y, t] ----
```

---

## Change 13: MibImage.crop — sliceSize handling

**File:** `mib/+core/@MibImage/crop.m`

The key challenge: we need to detect whether X/Y changed BEFORE the crop is applied. Replace the full body from line 44 onwards. The existing code from line 44 to end (line 69):

```matlab
x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Crop data{1}: layout is [height, width, depth, colors, time]
obj.data{1} = obj.data{1}( ...
    y1:y1+dy-1, ...
    x1:x1+dx-1, ...
    z1:z1+dz-1, ...
    :, ...
    t1:t1+dt-1);

% Update scalar dimension properties from the cropped array
obj.height = size(obj.data{1}, 1);
obj.width  = size(obj.data{1}, 2);
obj.depth  = size(obj.data{1}, 3);
obj.time   = size(obj.data{1}, 5);
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

% Trim sliceName if the dataset had per-slice filenames
if numel(obj.sliceName) > 1
    obj.sliceName = obj.sliceName(z1 : z1+dz-1);
end
end
```

Change to:
```matlab
x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Check if X/Y dimensions are changing (needed for sliceSize clearing)
xyChanged = (x1 > 1) || (y1 > 1) || (dx < obj.width) || (dy < obj.height);

% Crop data{1}: layout is [height, width, depth, colors, time]
obj.data{1} = obj.data{1}( ...
    y1:y1+dy-1, ...
    x1:x1+dx-1, ...
    z1:z1+dz-1, ...
    :, ...
    t1:t1+dt-1);

% Update scalar dimension properties from the cropped array
obj.height = size(obj.data{1}, 1);
obj.width  = size(obj.data{1}, 2);
obj.depth  = size(obj.data{1}, 3);
obj.time   = size(obj.data{1}, 5);
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

% Trim sliceName if the dataset had per-slice filenames
if numel(obj.sliceName) > 1
    obj.sliceName = obj.sliceName(z1 : z1+dz-1);
end

% Clear sliceSize if X or Y was cropped (original sizes no longer restorable);
% otherwise trim to the new Z range
if ~isempty(obj.sliceSize)
    if xyChanged
        obj.sliceSize = {};
    elseif numel(obj.sliceSize) > 1
        obj.sliceSize = obj.sliceSize(z1 : z1+dz-1);
    end
end
end
```

**Key point:** `xyChanged` is computed BEFORE the crop so we can compare against original dimensions.

Since MibLabels and MibLabels63 inherit MibImage.crop, and their sliceSize was synced from the image (via Change 9 and Change 12), the crop method will correctly handle labels' sliceSize too.

---

## Change 14: ResampleDataset — clear sliceSize on image and labels

**File:** `mib/+controllers/@ResampleDataset/ResampleDataset.m`

After the sliceName clearing (lines 705-708), add sliceSize clearing for both image and labels. The existing code at lines 705-710:
```matlab
            % remove SliceName filenames if Z changed (they are now mismatched)
            if ~isempty(obj.mibModel.I{id}.image.sliceName) && newZ ~= obj.depth
                obj.mibModel.I{id}.image.sliceName = {};
            end

            % clear selection and mask unless 'everything' was resampled together
```

Change to:
```matlab
            % remove SliceName filenames if Z changed (they are now mismatched)
            if ~isempty(obj.mibModel.I{id}.image.sliceName) && newZ ~= obj.depth
                obj.mibModel.I{id}.image.sliceName = {};
            end

            % remove SliceSize if Z or spatial dimensions changed
            if ~isempty(obj.mibModel.I{id}.image.sliceSize) && ...
                    (newZ ~= obj.depth || newH ~= obj.height || newW ~= obj.width)
                obj.mibModel.I{id}.image.sliceSize = {};
                obj.mibModel.I{id}.labels.sliceSize = {};
            end

            % clear selection and mask unless 'everything' was resampled together
```

---

## Change 15: MibImage.save — export sliceSize to metadata

**File:** `mib/+core/@MibImage/save.m`

After the sliceName block (lines 209-214), add sliceSize. The existing code at lines 209-216:
```matlab
% per-slice source filenames
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
else
    metadata.sliceName = {};
end

% resolution for PNG/TIF Resolution tags — pixels per inch
```

Change to:
```matlab
% per-slice source filenames
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
else
    metadata.sliceName = {};
end

% per-slice original dimensions
if ~isempty(obj.sliceSize)
    metadata.sliceSize = obj.sliceSize;
else
    metadata.sliceSize = {};
end

% resolution for PNG/TIF Resolution tags — pixels per inch
```

---

## Change 16: MibLabels.save — propagate sliceSize

**File:** `mib/+core/@MibLabels/save.m`

After the sliceName block (lines 224-233, ending before `options.FilenamePrefix = 'Labels_';`), add sliceSize block. The existing code at lines 224-234:
```matlab
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
elseif isfield(options, 'imageSliceNames') && ~isempty(options.imageSliceNames)
    % Use per-slice filenames from the parent image layer (injected by
    % MibDataset.saveImage) so that 2-D sequence savers can apply the
    % 'Use original filename' policy for labels.
    metadata.sliceName = options.imageSliceNames;
else
    metadata.sliceName = {};
end
options.FilenamePrefix = 'Labels_';
```

Change to:
```matlab
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
elseif isfield(options, 'imageSliceNames') && ~isempty(options.imageSliceNames)
    % Use per-slice filenames from the parent image layer (injected by
    % MibDataset.saveImage) so that 2-D sequence savers can apply the
    % 'Use original filename' policy for labels.
    metadata.sliceName = options.imageSliceNames;
else
    metadata.sliceName = {};
end
if ~isempty(obj.sliceSize)
    metadata.sliceSize = obj.sliceSize;
elseif isfield(options, 'imageSliceSizes') && ~isempty(options.imageSliceSizes)
    metadata.sliceSize = options.imageSliceSizes;
else
    metadata.sliceSize = {};
end
options.FilenamePrefix = 'Labels_';
```

---

## Change 17: MibLabels63.save — propagate sliceSize

**File:** `mib/+core/@MibLabels63/save.m`

Identical pattern to Change 16. After the sliceName block (lines 162-171, ending before `options.FilenamePrefix = 'Labels_';`). The existing code at lines 162-172:
```matlab
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
elseif isfield(options, 'imageSliceNames') && ~isempty(options.imageSliceNames)
    % Use per-slice filenames from the parent image layer (injected by
    % MibDataset.saveImage) so that 2-D sequence savers can apply the
    % 'Use original filename' policy for labels.
    metadata.sliceName = options.imageSliceNames;
else
    metadata.sliceName = {};
end
options.FilenamePrefix = 'Labels_';
```

Change to:
```matlab
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
elseif isfield(options, 'imageSliceNames') && ~isempty(options.imageSliceNames)
    % Use per-slice filenames from the parent image layer (injected by
    % MibDataset.saveImage) so that 2-D sequence savers can apply the
    % 'Use original filename' policy for labels.
    metadata.sliceName = options.imageSliceNames;
else
    metadata.sliceName = {};
end
if ~isempty(obj.sliceSize)
    metadata.sliceSize = obj.sliceSize;
elseif isfield(options, 'imageSliceSizes') && ~isempty(options.imageSliceSizes)
    metadata.sliceSize = options.imageSliceSizes;
else
    metadata.sliceSize = {};
end
options.FilenamePrefix = 'Labels_';
```

---

## Change 18: MibDataset.saveImage — pass sliceSize to labels and mask savers

**File:** `mib/+core/@MibDataset/saveImage.m`

### 18a. Labels path — pass imageSliceSizes

After line 209 (`options.imageSliceNames = obj.image.sliceName;`), add the parallel line. The existing code at lines 208-210:
```matlab
        if ~isfield(options, 'imageSliceNames') || isempty(options.imageSliceNames)
            options.imageSliceNames = obj.image.sliceName;
        end
```

Change to:
```matlab
        if ~isfield(options, 'imageSliceNames') || isempty(options.imageSliceNames)
            options.imageSliceNames = obj.image.sliceName;
        end
        if ~isfield(options, 'imageSliceSizes') || isempty(options.imageSliceSizes)
            options.imageSliceSizes = obj.image.sliceSize;
        end
```

### 18b. Mask path — add sliceSize to metadata

After line 250 (`if ~isempty(obj.image.sliceName); metadata.sliceName = obj.image.sliceName; end`), add:

The existing code at lines 249-251:
```matlab
        metadata.sliceName      = {};
        if ~isempty(obj.image.sliceName); metadata.sliceName = obj.image.sliceName; end
        metadata.layerType        = 'mask';
```

Change to:
```matlab
        metadata.sliceName      = {};
        if ~isempty(obj.image.sliceName); metadata.sliceName = obj.image.sliceName; end
        metadata.sliceSize      = {};
        if ~isempty(obj.image.sliceSize); metadata.sliceSize = obj.image.sliceSize; end
        metadata.layerType        = 'mask';
```

---

## Change 19: BaseSaver — helper method + metadata doc

**File:** `mib/+io/+savers/BaseSaver.m`

### 19a. Update METADATA CONVENTION docstring

After line 25:
```matlab
% .sliceName   — (cell of char) per-slice source filenames
```

Add a new line:
```matlab
% .sliceSize   — (cell of [1x2] double) per-slice original [height, width]; empty when uniform
```

### 19b. Add cropSliceToOriginalSize method

Before the closing `end  % protected methods` at line 398. The existing code at lines 395-399:
```matlab
            end
        end

    end  % protected methods
end
```

Change to:
```matlab
            end
        end

        function img2D = cropSliceToOriginalSize(~, img2D, sliceSize)
            % CROPSLICETOORIGINALSIZE - Crop a padded 2-D slice back to its original dimensions.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      img2D = obj.cropSliceToOriginalSize(img2D, sliceSize)
            %
            % Input Arguments:
            %   - **img2D** — [H, W] or [H, W, C] image slice (possibly padded)
            %   - **sliceSize** — [1x2] vector ``[origHeight, origWidth]``
            %
            % Output Arguments:
            %   - **img2D** — cropped to ``[origHeight, origWidth, :]``
            %
            if ~isempty(sliceSize)
                origH = min(sliceSize(1), size(img2D, 1));
                origW = min(sliceSize(2), size(img2D, 2));
                img2D = img2D(1:origH, 1:origW, :);
            end
        end

    end  % protected methods
end
```

---

## Change 20: TiffSaver — dialog + crop in 2D write loop

**File:** `mib/+io/+savers/TiffSaver.m`

### 20a. Add "Restore original slice dimensions" to the dialog

The existing dialog code at lines 249-260:
```matlab
            if ~options.silent && ~callerSetFilename && nD > 1
                prompts = {'Filename generator:'; 'Multi-dimensional saving policy:'};
                defAns  = {{'Use original filename', 'Use sequential filename', 2}; ...
                           {'3D stack', '2D sequence', 1}};
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'TIF saving settings', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
                options.Saving3DPolicy    = answer{2};
            end
```

Change to:
```matlab
            hasSliceSizes = isfield(metadata, 'sliceSize') && numel(metadata.sliceSize) == nD;
            if ~options.silent && ~callerSetFilename && nD > 1
                prompts = {'Filename generator:'; 'Multi-dimensional saving policy:'};
                defAns  = {{'Use original filename', 'Use sequential filename', 2}; ...
                           {'3D stack', '2D sequence', 1}};
                if hasSliceSizes
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'TIF saving settings', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
                options.Saving3DPolicy    = answer{2};
                if hasSliceSizes
                    options.RestoreOriginalSize = strcmp(answer{3}, 'Yes');
                end
            end
```

### 20b. Crop in 2D write loop

At line 320 where `img2D` is extracted:
```matlab
                            img2D = squeeze(slice4D(:, :, :, z));  % [H, W, C]
```

Change to:
```matlab
                            img2D = squeeze(slice4D(:, :, :, z));  % [H, W, C]
                            if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                                    hasSliceSizes
                                img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize{z});
                            end
```

**Note:** `hasSliceSizes` was computed at the method level (Change 20a) so it's in scope here.

---

## Change 21: PngSaver — dialog + crop

**File:** `mib/+io/+savers/PngSaver.m`

### 21a. Replace the dialog block

The existing dialog code at lines 208-219:
```matlab
            if ~options.silent && ~callerSetFilename && ...
                    isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                    nT == 1 && nD > 1
                prompts  = {'Filename generator:'};
                defAns   = {{'Use original filename', 'Use sequential filename', 1}};
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'Define naming', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
            end
```

Change to:
```matlab
            hasSliceSizes = isfield(metadata, 'sliceSize') && numel(metadata.sliceSize) == nD;
            showNamingDlg = ~options.silent && ~callerSetFilename && ...
                    isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                    nT == 1 && nD > 1;
            showSizeDlg = ~options.silent && hasSliceSizes && nD > 1;
            if showNamingDlg || showSizeDlg
                prompts = {};
                defAns  = {};
                if showNamingDlg
                    prompts{end+1} = 'Filename generator:';
                    defAns{end+1}  = {'Use original filename', 'Use sequential filename', 1};
                end
                if showSizeDlg
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'Define naming', dlgOpts);
                if isempty(answer); return; end
                answerIdx = 1;
                if showNamingDlg
                    options.FilenameGenerator = answer{answerIdx}; answerIdx = answerIdx + 1;
                end
                if showSizeDlg
                    options.RestoreOriginalSize = strcmp(answer{answerIdx}, 'Yes');
                end
            end
```

### 21b. Crop in write loop

At line 237 where `img2D` is extracted:
```matlab
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]
```

Change to:
```matlab
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]
                        if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                                hasSliceSizes
                            img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize{z});
                        end
```

---

## Change 22: JpgSaver — dialog + crop

**File:** `mib/+io/+savers/JpgSaver.m`

### 22a. Add hasSliceSizes variable

After line 177 where `showNaming` is defined:
```matlab
            showNaming = ~callerSetFilename && ...
                isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                nT == 1 && nD > 1;
```

Add after it:
```matlab
            hasSliceSizes = isfield(metadata, 'sliceSize') && numel(metadata.sliceSize) == nD;
```

### 22b. Add the restore prompt to the dialog

In the dialog block (inside `if ~options.silent && ...`), after the existing showNaming prompt addition at lines 184-187:
```matlab
                if showNaming
                    prompts{end+1} = 'Filename generator:';
                    defAns{end+1}  = {'Use original filename', 'Use sequential filename', 1};
                end
```

Add after it:
```matlab
                if hasSliceSizes && nD > 1
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
```

### 22c. Update answer extraction

Replace the existing answer extraction at lines 194-198:
```matlab
                options.Compression = answer{1};
                options.Quality     = answer{2};
                if showNaming
                    options.FilenameGenerator = answer{3};
                end
```

With:
```matlab
                options.Compression = answer{1};
                options.Quality     = answer{2};
                nextIdx = 3;
                if showNaming
                    options.FilenameGenerator = answer{nextIdx}; nextIdx = nextIdx + 1;
                end
                if hasSliceSizes && nD > 1
                    options.RestoreOriginalSize = strcmp(answer{nextIdx}, 'Yes');
                end
```

### 22d. Crop in write loop

At line 217 where `img2D` is extracted:
```matlab
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]
```

Change to:
```matlab
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]
                        if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                                hasSliceSizes
                            img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize{z});
                        end
```

---

## Change 23: MatlabSaver — dialog + crop for 2D model sequences

**File:** `mib/+io/+savers/MatlabSaver.m`

### 23a. Add hasSliceSizes variable

After line 354 where `hasSliceNames` is defined:
```matlab
            hasSliceNames = isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nZ;
```

Add:
```matlab
            hasSliceSizes = isfield(metadata, 'sliceSize') && numel(metadata.sliceSize) == nZ;
```

### 23b. Add restore prompt to dialog

In the dialog block (inside the `if ~options.silent && ~callerSetFilename && nZ > 1 && hasSliceNames` block), after the existing prompt setup at lines 364-365:
```matlab
                prompts = {'Filename generator:'};
                defAns  = {{'Use sequential filename', 'Use original filename', 1}};
```

Change to:
```matlab
                prompts = {'Filename generator:'};
                defAns  = {{'Use sequential filename', 'Use original filename', 1}};
                if hasSliceSizes
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
```

### 23c. Update answer extraction

After the existing answer extraction at line 369:
```matlab
                options.FilenameGenerator = answer{1};
```

Change to:
```matlab
                options.FilenameGenerator = answer{1};
                if hasSliceSizes
                    options.RestoreOriginalSize = strcmp(answer{2}, 'Yes');
                end
```

### 23d. Crop in 2D write loop

At line 399 where per-slice data is extracted:
```matlab
                vars.(labVar) = squeeze(data(:,:,z,1,1));
```

Change to:
```matlab
                vars.(labVar) = squeeze(data(:,:,z,1,1));
                if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                        hasSliceSizes
                    vars.(labVar) = obj.cropSliceToOriginalSize(vars.(labVar), metadata.sliceSize{z});
                end
```

---

## Verification

1. **Load uniform images** (e.g., 3 TIFs all 512×512) — verify `obj.mibModel.I{1}.image.sliceSize` is `[]` (empty default)
2. **Load mixed-size images** (e.g., 512×512 + 256×256 TIFs) — verify `sliceSize` is `{[512,512]; [256,256]}`
3. **Check labels sync** — after step 2, verify `obj.mibModel.I{1}.labels.sliceSize` matches `image.sliceSize`
4. **Insert slices** into dataset with populated `sliceSize` — verify array grows correctly at beginning/middle/end and labels stay synced
5. **Crop Z-only** (no X/Y change) — verify `sliceSize` trimmed to Z range on both image and labels
6. **Crop X/Y** — verify `sliceSize` cleared to `{}` on both image and labels
7. **Resample/Resize** with changed Z, H, or W — verify `sliceSize` cleared on both image and labels
8. **Save image as 2D TIF sequence** with `RestoreOriginalSize=Yes` — verify each output file has its original dimensions
9. **Save image as 2D TIF sequence** with `RestoreOriginalSize=No` — verify full canvas size (existing behavior unchanged)
10. **Save model (labels) as 2D .model sequence** with `RestoreOriginalSize=Yes` — verify each output model has original dimensions
11. **Save as 2D PNG/JPG sequence** — verify dialog appears and crop works
12. **Run `buildtool check`** — no new code issues

---

## File Summary (23 changes across ~21 unique files)

| # | File | Change |
|---|------|--------|
| 1 | `mib/+core/@MibImage/MibImage.m` | Add `sliceSize` property |
| 2 | `mib/+core/@MibImage/initializeImgInfo.m` | Add `"SliceSize"` key + docstring |
| 3 | `mib/+core/@MibImage/initialize.m` | Read `meta{'SliceSize'}` |
| 4 | `mib/+core/@MibImage/getMeta.m` | Export `sliceSize` |
| 5 | `mib/+core/@MibImage/setMeta.m` | Import `sliceSize` |
| 6 | `mib/+core/@MibVirtualImage/initialize.m` | Read `meta{'SliceSize'}` |
| 7 | `mib/+io/+loaders/BaseImageLoader.m` | New `generateSliceSizes` method |
| 8a-8i | 9 loader files | Call `generateSliceSizes` after `generateSliceNames` |
| 9 | `mib/+core/@MibDataset/initialize.m` | Include `SliceSize` in labelsMeta |
| 10 | `mib/+core/@MibImage/insertSlice.m` | `options.sliceSizes` default + sliceSize update block + docstring |
| 11 | `mib/+core/@MibVirtualImage/insertSlice.m` | Same pattern as Change 10 |
| 12 | `mib/+core/@MibDataset/insertSlice.m` | Extract SliceSize from meta + pass via imgOpts + sync to labels |
| 13 | `mib/+core/@MibImage/crop.m` | `xyChanged` detection + clear on X/Y crop + trim on Z crop |
| 14 | `mib/+controllers/@ResampleDataset/ResampleDataset.m` | Clear sliceSize on image + labels |
| 15 | `mib/+core/@MibImage/save.m` | Export sliceSize to metadata struct |
| 16 | `mib/+core/@MibLabels/save.m` | Propagate sliceSize (own → imageSliceSizes fallback) |
| 17 | `mib/+core/@MibLabels63/save.m` | Same as Change 16 |
| 18 | `mib/+core/@MibDataset/saveImage.m` | Pass imageSliceSizes option + add to mask metadata |
| 19 | `mib/+io/+savers/BaseSaver.m` | Doc update + `cropSliceToOriginalSize` helper |
| 20 | `mib/+io/+savers/TiffSaver.m` | Dialog + crop in 2D loop |
| 21 | `mib/+io/+savers/PngSaver.m` | Dialog + crop in 2D loop |
| 22 | `mib/+io/+savers/JpgSaver.m` | Dialog + crop in 2D loop |
| 23 | `mib/+io/+savers/MatlabSaver.m` | Dialog + crop in 2D loop |
