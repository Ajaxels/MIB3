# Conversion Plan: MIB2 `loadModel` → MIB3 `MibModel.loadModel`

**Source:** `C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibModel\loadModel.m`
**Reference pattern:** `C:\Matlab\MIB3\mib\+models\@MibModel\loadImages.m`
**Also port:** `C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibController\menuModelsImport_Callback.m`

---

## 1. Overview

`loadModel` is the single unified entry point for all model/segmentation-label data entering
MIB3. It handles two paths:

1. **File path** — user selects a file (GUI) or batch processing specifies one; data is read
   from disk via the `+io` loader factory pattern.
2. **Import path** — a raw MATLAB array (or struct) is passed directly, typically from the
   workspace import callback. Same post-processing logic is shared.

The implementation follows the layered delegation introduced by `loadImages.m`:

```
MibModel.loadModel          ← thin wrapper: BatchOpt, GUI, virtual guard, events
  └── MibDataset.loadModel  ← orchestrator: extension dispatch, dim check, property set
        └── io.LoaderFactory.create → loader.loadMetadata + loader.loadImages
```

---

## 2. Files to Create

### 2.1 `mib/+models/@MibModel/loadModel.m`

Top-level wrapper. Mirrors the structure of `loadImages.m` exactly.

**Full signature:**
```matlab
function loadModel(obj, model, BatchOptIn)
```

**BatchOpt fields:**

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `DirectoryName` | `{char}` | `{'Inherit from dataset filename'}` | Path resolved at runtime from `obj.I{id}.image.filename` |
| `FilenameFilter` | `char` | `'Labels_[F].model'` | `[F]` is replaced with the base filename of the currently open image |
| `showWaitbar` | `logical` | `true` | |
| `id` | `double` | `obj.id` | Dataset index 1–9; removed from SyncBatch export |
| `mibBatchSectionName` | `char` | `'Ribbon -> Models'` | |
| `mibBatchActionName` | `char` | `'Load model'` | |

**Tooltips:**
- `DirectoryName` — "Directory with the model file; use 'Inherit from dataset filename' to use the dataset directory"
- `FilenameFilter` — "Model filename or filter mask; [F] is replaced by the base filename of the open image"
- `showWaitbar` — "Show or not the progress bar during execution"

**Logic flow:**

```
1. nargin defaults: if nargin<3 BatchOptIn=struct; if nargin<2 model=[];
2. BatchOpt declaration (above fields)
3. if isstruct(BatchOptIn)==0
     if isnan(BatchOptIn)
       rmfield(BatchOpt,'id') → SyncBatch → return
     else
       showErrorDialog → return
   else
     BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn)
     batchModeSwitch = 1
4. Virtual mode guard:
     if obj.I{BatchOpt.id}.datasetType(1)=='V'
       show puffin_warning dialog
       notify(obj,'StopProtocol') → return
5. enableSelection guard:
     if obj.I{BatchOpt.id}.enableSelection == 0
       show warning → return
6. Existing model warning (GUI mode only, ~batchModeSwitch):
     if obj.I{BatchOpt.id}.modelExist
       uiconfirm "existing model will be replaced, continue?"
7. Waitbar:
     if BatchOpt.showWaitbar
       wb = uiprogressdlg(obj.mibGUI, ...)
8a. FILE PATH (isempty(model)):
     GUI mode: call utils.dlgs.mibUiGetFile with all supported extensions
     Batch mode: resolve DirectoryName, expand [F] in FilenameFilter,
                 call dir() to find matching files, build fullpath filenames cell
     Call obj.I{BatchOpt.id}.loadModel(filenames, options)
8b. IMPORT PATH (~isempty(model)):
     options.model = model (raw array, after unpacking struct if needed)
     Call obj.I{BatchOpt.id}.loadModel([], options)
9. Post-load (shared, only if loadModel returned success):
     obj.I{BatchOpt.id}.lastSegmSelection = [2 1]
     obj.showModel = true
     notify(obj,'UpdateGuiWidgets')
     notify(obj,'ShowImage')
     SyncBatch notify (rmfield 'id')
10. delete(wb)
```

**Import path struct unpacking (step 8b):**
```matlab
if isstruct(model)
    if isfield(model,'modelVariable'); options.labelsVariable = model.modelVariable; end
    if isfield(model,'modelMaterialNames'); options.modelMaterialNames = model.modelMaterialNames; end
    if isfield(model,'modelMaterialColors'); options.modelMaterialColors = model.modelMaterialColors; end
    if isfield(model,'modelType'); options.modelType = model.modelType; end
    if isfield(model,'labelText')
        options.labelText = model.labelText;
        options.labelPosition = model.labelPosition;
        options.labelValue = model.labelValue;
    end
    varName = 'model';
    if isfield(model,'modelVariable'); varName = model.modelVariable; end
    options.model = model.(varName);
else
    options.model = model;
end
```

**File browser filter list** (for `mibUiGetFile`):
```
*.model           MIB model file
*.mat             MATLAB data file
*.am              Amira mesh labels
*.h5;*.hdf5       HDF5 model
*.mibCat          MIB categorical model
*.mrc;*.rec;*.st  MRC/IMOD format
*.nrrd            NRRD format
*.tif;*.tiff      TIFF image
*.xml             HDF5 with XML header
*.*               All files
```

---

### 2.2 `mib/+core/@MibDataset/loadModel.m`

Dataset-level orchestrator. Called by `MibModel.loadModel`.

**Signature:**
```matlab
function result = loadModel(obj, filenames, options)
```

**Parameters:**
- `filenames` — cell array of full-path strings, or `[]` for import path
- `options` struct fields used:
  - `options.model` — raw array (import path); if set, skip file loading
  - `options.modelMaterialNames` — pre-supplied material names (override from file)
  - `options.modelMaterialColors` — pre-supplied material colors
  - `options.modelType` — pre-supplied model type (63/255/65535/4294967295)
  - `options.labelsVariable` — variable name string
  - `options.labelText`, `options.labelPosition`, `options.labelValue` — annotations
  - `options.showWaitbar` — logical
  - `options.preferences` — `obj.preferences` passed from model (for default color palette)
  - `options.mibPath` — for loader options
  - `options.ParentFigure` — for dialogs
  - `options.batchModeSwitch` — suppress confirm dialogs

**Return:** `result = 1` on success, `result = 0` on failure/cancel (or `[]`)

**Logic flow:**

```
1. If options.model is set (import path):
     rawModel = options.model
     Skip to step 5

2. Detect extension from filenames{1} (fileparts, lowercase)

3. resolveLoader:
     loaderInfo = obj.extensionRegistryLoad.resolveLoader(filenames{1}, 'Model', 'Default')
     NOTE: extensionRegistryLoad is a property of MibModel; pass it via options
           OR access via obj.parent reference if MibDataset has one
     If loaderInfo is char (error string) → showErrorDialog → return 0

4. Create loader + load data:
     loaderOptions.mibPath = options.mibPath
     loaderOptions.ParentFigure = options.ParentFigure
     loader = io.LoaderFactory.create(loaderInfo, loaderOptions)
     [imginfo, files] = loader.loadMetadata(filenames, loaderOptions)
     [rawModel, imginfo] = loader.loadImages(files, imginfo, loaderOptions)
     if isempty(rawModel); return 0; end

     For .am only: additionally call
       [~, imginfo_am, ~, materialNamesFromFile] = io.AmiraMesh.getAmiraMeshHeader(filenames{1})
       Extract Colors: loop imginfo_am keys matching 'Materials_*_Color'

5. Determine modelType:
     Priority: options.modelType > imginfo{"modelType"} > auto-detect
     Auto-detect:
       switch class(rawModel)
         'uint8':  if max(rawModel(:))<64 → 63; else → 255
         'uint16': → 65535
         'uint32': → 4294967295
         'double': GUI→uiconfirm to convert to uint32; batch→auto-convert
         otherwise: showErrorDialog → return 0

6. Dimension validation:
     [H,W,D,~,T] = size(rawModel)
     imgH = obj.image.height; imgW = obj.image.width
     imgD = obj.image.depth; imgT = obj.image.time

     if H~=imgH || W~=imgW
       if ~options.batchModeSwitch
         answer = uiconfirm(options.ParentFigure, "Model H×W differs from image. Try to load?")
         if cancelled: return 0
       end
       % Pad or crop H
       if H < imgH
         rawModel(end+1:imgH,:,:,:,:) = 0;
       elseif H > imgH
         rawModel = rawModel(1:imgH,:,:,:,:);
       end
       % Pad or crop W
       if W < imgW
         rawModel(:,end+1:imgW,:,:,:) = 0;
       elseif W > imgW
         rawModel = rawModel(:,1:imgW,:,:,:);
       end

     if D > imgD
       rawModel = rawModel(:,:,1:imgD,:,:);   % crop Z
     elseif D < imgD
       rawModel(:,:,D+1:imgD,:,:) = 0;        % pad Z with zeros

     if T > imgT
       rawModel = rawModel(:,:,:,:,1:imgT);
     elseif T < imgT
       rawModel(:,:,:,:,T+1:imgT) = 0;

7. Collect material metadata:
     Priority chain (first non-empty wins):
     materialNames:  options.modelMaterialNames
                   > imginfo{"modelMaterialNames"} (if isKey)
                   > materialNamesFromFile (.am path)
                   > auto-generate: {'1','2',...} up to max(rawModel(:)) for uint8;
                                    {'1','2'} for uint16/uint32
     materialColors: options.modelMaterialColors
                   > imginfo{"modelMaterialColors"}
                   > materialColorsFromFile (.am path)
                   > For uint8: use options.preferences.Colors.ModelMaterialColors (cyclic)
                   > For uint16/uint32: random RGB [N×3]
     labelsVariable: options.labelsVariable
                   > imginfo{"labelsVariable"} (if isKey)
                   > 'mibModel' (default)

8. Create / reinitialize model layer:
     obj.createModel(modelType)   ← handles class conversion of existing data

9. Store pixel data:
     if T > 1
       obj.setData4D(rawModel, 'labels', [], 3)   % [H W Z 1 T]
     else
       obj.setData3D(rawModel, 'labels', [], 3, [])

10. Set metadata:
      obj.labels.materialNames  = materialNames
      obj.labels.materialColors = materialColors
      obj.labels.labelsVariable = labelsVariable
      obj.labels.filename       = filenames{1}   (or '' for import path)
      obj.labels.countMaterials()                % sync materialsCount

11. Annotations:
      if isfield(options,'labelText') && ~isempty(options.labelText)
        obj.annotations.clearContents()
        obj.annotations.addLabels(options.labelText, options.labelPosition, options.labelValue)
      elseif isKey(imginfo,'labelText') && ~isempty(imginfo{'labelText'})
        obj.annotations.clearContents()
        obj.annotations.addLabels(imginfo{'labelText'}, imginfo{'labelPosition'}, imginfo{'labelValue'})

12. obj.modelExist = true
13. result = 1
```

**Note on `extensionRegistryLoad` access:** `MibDataset` does not hold a reference to
`MibModel`. Pass `extensionRegistryLoad` object via `options.extensionRegistryLoad` from
`MibModel.loadModel`, or pass `loaderInfo` directly (pre-resolved in `MibModel.loadModel`).
**Recommended:** resolve loader in `MibModel.loadModel` and pass pre-built `loaderInfo` via
`options.loaderInfo` — keeps `MibDataset` decoupled from `ExtensionRegistryLoad`.

---

### 2.3 `mib/+io/+loaders/MatModelLoader.m`

New loader for `.model`, `.mat`, `.mibCat` MATLAB-format files.

**Class definition:**
```matlab
classdef MatModelLoader < io.loaders.BaseImageLoader
```

**Constructor:**
```matlab
function obj = MatModelLoader(options)
    obj@io.loaders.BaseImageLoader(options);
end
```

**`loadMetadata(obj, filenames, options)` — returns `[imginfo, files]`:**

```
For each filenames{fnId}:

1. res = load(filenames{fnId}, '-mat')
   Fields = fieldnames(res);

2. Determine labelsVariable:
   - If ismember('modelVariable', Fields) && ischar(res.modelVariable)
       labVar = res.modelVariable
       if ~ismember(labVar, Fields): scan Fields for data variable (see below)
   - Elseif ismember('model_var', Fields)     % MIB v1
       labVar = res.model_var
   - Else: scan Fields, skip known metadata fields:
       skip = {'modelMaterialNames','modelMaterialColors','modelType','modelVariable',
               'model_var','BoundingBox','labelText','labelPosition','labelValue',
               'material_list','color_list','options','imgVariable'};
       labVar = first Fields entry not in skip

3. Extract raw array:
   rawArr = res.(labVar)

4. .mibCat detection:
   if iscategorical(rawArr)
     cats = categories(rawArr)                   % canonical order = material names
     rawArr = uint8(grp2idx(rawArr))             % 0 = Exterior, 1..N = materials
     materialNames_file = cats
     if isfield(res,'options') && isfield(res.options,'modelType')
       modelType_file = res.options.modelType
     else
       modelType_file = 255
     end
     if isfield(res,'options') && isfield(res.options,'modelMaterialColors')
       materialColors_file = res.options.modelMaterialColors
     end

5. Extract metadata fields (if not mibCat):
   materialNames_file = []
   if ismember('modelMaterialNames',Fields); materialNames_file = res.modelMaterialNames; end
   materialColors_file = []
   if ismember('modelMaterialColors',Fields); materialColors_file = res.modelMaterialColors; end
   modelType_file = []
   if ismember('modelType',Fields); modelType_file = res.modelType; end
   labelsVariable = labVar
   if ismember('labelText',Fields)
     labelText_file = res.labelText
     labelPosition_file = res.labelPosition
     labelValue_file = res.labelValue
   end
   BoundingBox = []
   if ismember('BoundingBox',Fields); BoundingBox = res.BoundingBox; end

6. Build files(fnId) struct:
   files(fnId).filename  = filenames{fnId}
   files(fnId).data      = rawArr        % cached — avoids second disk read
   files(fnId).height    = size(rawArr,1)
   files(fnId).width     = size(rawArr,2)
   files(fnId).noLayers  = size(rawArr,3)
   files(fnId).time      = max(1, size(rawArr,4))
   files(fnId).imgClass  = class(rawArr)

7. Build imginfo dictionary (use core.MibImage.initializeImgInfo or plain dictionary):
   imginfo = dictionary();
   imginfo("Height")               = files(1).height
   imginfo("Width")                = files(1).width
   imginfo("Depth")                = sum([files.noLayers])
   imginfo("Time")                 = files(1).time
   imginfo("Colors")               = 1
   imginfo("imgClass")             = files(1).imgClass
   imginfo("labelsVariable")       = labelsVariable
   if ~isempty(materialNames_file)
     imginfo("modelMaterialNames") = materialNames_file
   if ~isempty(materialColors_file)
     imginfo("modelMaterialColors")= materialColors_file
   if ~isempty(modelType_file)
     imginfo("modelType")          = modelType_file
   % annotations
   if exist('labelText_file','var')
     imginfo("labelText")    = labelText_file
     imginfo("labelPosition")= labelPosition_file
     imginfo("labelValue")   = labelValue_file
   if ~isempty(BoundingBox)
     imginfo("BoundingBox")  = BoundingBox
```

**`loadImages(obj, files, imginfo, options)` — returns `[img, imginfo]`:**

```
Assemble:
  for fnId = 1:numel(files)
    if fnId == 1
      img = files(fnId).data
    else
      img = cat(3, img, files(fnId).data)
    end
  end
  % ensure 5D: [H W Z 1 T]
  if ndims(img) == 3; img = reshape(img, [size(img,1), size(img,2), size(img,3), 1, 1]); end
```

---

## 3. Files to Modify

### 3.1 `mib/+models/@MibModel/MibModel.m`

Add to the `methods` block (alphabetical position between `loadImages` and `initialize`):

```matlab
loadModel(obj, model, BatchOptIn)  % load segmentation model from file or import from variable
```

### 3.2 `mib/+core/@MibDataset/MibDataset.m`

Add to the `methods` block:

```matlab
result = loadModel(obj, filenames, options)  % load model pixel data and metadata from files or array
```

### 3.3 `mib/+io/ExtensionRegistryLoad.m`

**In `initDefaults()`**, add after the existing `extensionSets` assignments:

```matlab
% Model loading mode — all file formats that can contain a segmentation model
obj.extensionSets("Model.Default") = {sort({'am','h5','hdf5','mat','mibCat','model',...
    'mrc','nrrd','rec','st','tif','tiff','xml'})};
```

**In `defaultLoaderId(obj, mode, reader, ext)`**, add at the top before existing mode routing:

```matlab
if mode == "Model"
    switch lower(ext)
        case {'model', 'mat', 'mibcat'}
            id = 'MatModel';
        case 'am'
            id = 'AmiraMesh';
        case 'xml'
            id = 'hdf5-header';
        case {'h5', 'hdf5'}
            id = 'hdf5-no-header';
        case {'mrc', 'rec', 'st'}
            id = 'imod';
        case 'nrrd'
            id = 'nrrd';
        otherwise
            id = 'imread';   % tif, tiff, png, bmp, etc.
    end
    return;
end
```

### 3.4 `mib/+io/LoaderFactory.m`

**In the `create` switch-case**, add before `otherwise`:

```matlab
case "MatModel"
    % MATLAB .mat / .model / .mibCat model files
    loader = io.loaders.MatModelLoader(options);
```

Also add to `getAvailableLoaders`:

```matlab
loaderList(idx).loaderId = 'MatModel';
loaderList(idx).description = 'MATLAB model format (.model, .mat, .mibCat)';
loaderList(idx).extensions = {'model', 'mat', 'mibCat'};
idx = idx + 1;
```

---

## 4. Controller Wiring (after core implementation)

### 4.1 `mib/+controllers/@MibSegmentation/gui_Callbacks.m`

The empty stub at line 34 (`case 'loadModel'`) needs:
```matlab
case 'loadModel'
    obj.mibModel.loadModel();
```

### 4.2 `mib/+controllers/@BatchProcessing/initialize.m`

Uncomment or add the `loadModel` batch action entry so it appears in the batch processing list.

### 4.3 Ribbon callback (MIB3 equivalent of `menuModelsImport_Callback`)

When porting the workspace import ribbon button, the callback should:
```matlab
% 1. GUI: show variable picker dialog (list uint8/uint16/uint32 workspace vars)
% 2. varIn = evalin('base', selectedVarName)
% 3. obj.mibModel.loadModel(varIn, struct())
```

---

## 5. Amira `.am` Material Color Extraction Detail

The existing `AmiraMeshLoader` loads pixel data but does NOT extract material colors. In
`MibDataset.loadModel`, after calling `loader.loadImages` for `.am` files, call:

```matlab
[~, imginfo_am] = io.AmiraMesh.getAmiraMeshHeader(filenames{1});
% Extract material names and colors from imginfo_am dictionary
% Keys follow pattern: 'Materials_1_Id', 'Materials_1_Color', 'Materials_1_Name', etc.
materialNamesFromFile = {};
materialColorsFromFile = [];
matIdx = 1;
while isKey(imginfo_am, sprintf('Materials_%d_Name', matIdx))
    materialNamesFromFile{end+1} = imginfo_am(sprintf('Materials_%d_Name', matIdx));
    colorStr = imginfo_am(sprintf('Materials_%d_Color', matIdx));
    % colorStr is typically "R G B A" space-separated, values 0-1
    colorVals = str2num(colorStr);  %#ok<ST2NM>
    materialColorsFromFile(end+1,:) = colorVals(1:3);
    matIdx = matIdx + 1;
end
```

---

## 6. Edge Cases and Notes

| Case | Handling |
|------|----------|
| `.mibCat` categorical→uint8 | `grp2idx(categorical_array)` → uint8; material order from `categories()` |
| `double` class input | GUI: `uiconfirm` before `uint32(model)`; batch: auto-convert silently |
| H×W mismatch | GUI: confirm; then pad/crop; batch: pad/crop silently |
| Z mismatch (model < image) | Pad remaining slices with zeros via partial `setData3D` |
| Z mismatch (model > image) | Crop to `obj.image.depth` |
| 4D models | Check `size(rawModel,4)` == `obj.image.time`; use `setData4D` |
| No material colors in file | uint8: cycle through `preferences.Colors.ModelMaterialColors`; uint16/32: `rand(N,3)` |
| No material names in file | uint8: `{'1','2',...,num2str(max(model(:)))}`; uint16/32: `{'1','2'}` |
| Annotations in .model | Always `clearContents()` first; then `addLabels(text, pos, val)` |
| MIB2 `model_var` field | Fallback for v1 `.model` files that used `model_var` not `modelVariable` |
| imginfo `numEntries` | `MibDataset.loadModel` must NOT call `numEntries`; use `isempty(rawModel)` check |
| `extensionRegistryLoad` access | Pass `options.extensionRegistryLoad` from `MibModel.loadModel` to `MibDataset.loadModel` |

---

## 7. Verification Steps

1. **Run MIB3:** `cd C:\Matlab\MIB3\mib; mib3`
2. Load any image dataset
3. Test each format via Ribbon → Models → Load model:
   - `*.model` / `*.mat` — verify material names and colors
   - `*.am` — verify Amira material names AND colors extracted from header
   - `*.h5` / `*.xml` with embedded `material_list` — verify names/colors
   - `*.nrrd`, `*.mrc` — verify auto-generated numeric names
   - `*.mibCat` — verify categorical→uint8 conversion + correct material order
4. Test **import from workspace**: create `O = rand(256,256,10,'uint8'); O(O>0.5)=1; O(O<=0.5)=0;` then import
5. Test **batch mode**: set `BatchOpt.FilenameFilter='Labels_[F].model'` and run through batch controller
6. Test **dimension mismatch**: load a model with wrong H×W; confirm dialog appears in GUI mode
7. Run `buildtool check` — no code issues
