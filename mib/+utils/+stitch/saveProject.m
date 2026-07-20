function saveProject(filePath, layout, edges, positions, solverInfo, outputInfo, tforms, zSliceFixes)
% SAVEPROJECT - Save a stitching project to a JSON sidecar file.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.stitch.saveProject(filePath, layout, edges, positions, solverInfo, outputInfo)
%      utils.stitch.saveProject(filePath, layout, edges, positions, solverInfo, outputInfo, tforms)
%      utils.stitch.saveProject(filePath, layout, edges, positions, solverInfo, outputInfo, tforms, zSliceFixes)
%
% Writes all stitching state to ``<name>.mibstitch.json`` for reproducibility
% and later use by the QC / seam checker.  The file is human-readable JSON
% encoded with ``jsonencode``.
%
% Input Arguments:
%   - **filePath** — [char] full path for the output JSON file (the ``.mibstitch.json``
%     extension is appended if not already present)
%   - **layout** — struct array as returned by the layout builders
%   - **edges** — struct array of measured/validated pair edges (may be ``[]``)
%   - **positions** — [double] N-by-3 array of solved origins ``[y x z]``
%     (may be ``[]`` if not yet solved)
%   - **solverInfo** — struct with solver settings and RMSE (may be ``[]``)
%   - **outputInfo** — struct with blend mode, output path, canvas size (may be ``[]``)
%   - **tforms** *(optional)* — [N x 1 cell] solved per-tile 3x3 affine transforms
%     from :func:`utils.stitch.solveGlobalAffine` (stored per tile as
%     ``solvedTform``); pass ``{}``/omit for translation-only projects
%   - **zSliceFixes** *(optional)* — [K x 3] per-slice mosaic corrections
%     ``[z dy dx]`` from the seam inspector's Fix Z; pass ``[]``/omit for none
%
% **Example** — save after solving:
%
%   .. code-block:: matlab
%
%      utils.stitch.saveProject('C:\data\experiment.mibstitch.json', ...
%          layout, edges, positions, solverInfo, outputInfo);
%

arguments
    filePath   (1,:) char
    layout     struct
    edges
    positions
    solverInfo
    outputInfo
    tforms      cell = {}
    zSliceFixes double = []
end

% Ensure correct extension
if ~endsWith(filePath, '.mibstitch.json')
    [folder, baseName, ~] = fileparts(filePath);
    filePath = fullfile(folder, [baseName, '.mibstitch.json']);
end

% v2 adds edge provenance for the seam inspector: per-edge 'source'
% ('auto'|'user'|'confirmed') and 'seamScore' (NCC at the solved placement).
project.schemaVersion = 2;
project.createdUtc    = char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));

% Serialise layout (convert 1×N structs to cell arrays for JSON)
if ~isempty(layout)
    project.tiles = layoutToCell(layout, positions, tforms);
else
    project.tiles = {};
end

% Serialise edges
if ~isempty(edges)
    project.edges = edgesToCell(edges);
else
    project.edges = {};
end

% Solver info
if isempty(solverInfo)
    project.solverInfo = struct();
else
    project.solverInfo = solverInfo;
end

% Output info
if isempty(outputInfo)
    project.outputInfo = struct();
else
    project.outputInfo = outputInfo;
end

% Per-slice mosaic corrections (inspector Fix Z), rows [z dy dx]
if ~isempty(zSliceFixes)
    project.zSliceFixes = zSliceFixes;
end

% Encode and write
jsonText = jsonencode(project, 'PrettyPrint', true);
fileID = fopen(filePath, 'w', 'n', 'UTF-8');
if fileID == -1
    error('utils:stitch:saveProject:cannotOpenFile', ...
        'Cannot open file for writing: %s', filePath);
end
cleanup = onCleanup(@() fclose(fileID));
fprintf(fileID, '%s', jsonText);

end

% =========================================================================
function tileCell = layoutToCell(layout, positions, tforms)
% Convert layout struct array to a cell array of structs for jsonencode.
if nargin < 3; tforms = {}; end
numTiles = numel(layout);
tileCell = cell(numTiles, 1);
for tileIdx = 1:numTiles
    tileStruct.index      = layout(tileIdx).index;
    tileStruct.filename   = layout(tileIdx).filename;
    tileStruct.sliceFiles = layout(tileIdx).sliceFiles;
    tileStruct.zLayer     = layout(tileIdx).zLayer;
    tileStruct.gridRC     = layout(tileIdx).gridRC;
    tileStruct.nomOrigin  = layout(tileIdx).nomOrigin;
    tileStruct.tileSize   = layout(tileIdx).tileSize;
    tileStruct.dataClass  = layout(tileIdx).dataClass;

    if ~isempty(positions) && size(positions, 1) >= tileIdx
        tileStruct.solvedOrigin = positions(tileIdx, :);
    else
        tileStruct.solvedOrigin = [];
    end

    if numel(tforms) >= tileIdx && ~isempty(tforms{tileIdx})
        tileStruct.solvedTform = tforms{tileIdx};
    else
        tileStruct.solvedTform = [];
    end

    tileCell{tileIdx} = tileStruct;
end
end

% =========================================================================
function edgeCell = edgesToCell(edges)
% Convert edges struct array to a cell array for jsonencode.
numEdges = numel(edges);
edgeCell = cell(numEdges, 1);
for edgeIdx = 1:numEdges
    edgeStruct = struct();   % fresh struct — optional fields must not leak across edges
    edgeStruct.i         = edges(edgeIdx).i;
    edgeStruct.j         = edges(edgeIdx).j;
    edgeStruct.direction = edges(edgeIdx).direction;
    edgeStruct.nominal   = edges(edgeIdx).nominal;
    if isfield(edges, 'measured')
        edgeStruct.measured  = edges(edgeIdx).measured;
        edgeStruct.quality   = edges(edgeIdx).quality;
        edgeStruct.valid     = edges(edgeIdx).valid;
    end
    if isfield(edges, 'tform') && ~isempty(edges(edgeIdx).tform)
        edgeStruct.tform = edges(edgeIdx).tform;
    end
    if isfield(edges, 'source') && ~isempty(edges(edgeIdx).source)
        edgeStruct.source = edges(edgeIdx).source;
    end
    if isfield(edges, 'seamScore') && ~isempty(edges(edgeIdx).seamScore)
        edgeStruct.seamScore = edges(edgeIdx).seamScore;
    end
    if isfield(edges, 'dzHint') && ~isempty(edges(edgeIdx).dzHint) && edges(edgeIdx).dzHint ~= 0
        edgeStruct.dzHint = edges(edgeIdx).dzHint;
    end
    edgeCell{edgeIdx} = edgeStruct;
end
end

% =========================================================================
function result = endsWith(str, suffix)
% Simple endsWith helper (avoids toolbox dependency).
result = numel(str) >= numel(suffix) && strcmp(str(end-numel(suffix)+1:end), suffix);
end
