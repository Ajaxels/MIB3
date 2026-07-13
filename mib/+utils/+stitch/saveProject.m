function saveProject(filePath, layout, edges, positions, solverInfo, outputInfo)
% SAVEPROJECT - Save a stitching project to a JSON sidecar file.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.stitch.saveProject(filePath, layout, edges, positions, solverInfo, outputInfo)
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
end

% Ensure correct extension
if ~endsWith(filePath, '.mibstitch.json')
    [folder, baseName, ~] = fileparts(filePath);
    filePath = fullfile(folder, [baseName, '.mibstitch.json']);
end

project.schemaVersion = 1;
project.createdUtc    = char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));

% Serialise layout (convert 1×N structs to cell arrays for JSON)
if ~isempty(layout)
    project.tiles = layoutToCell(layout, positions);
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
function tileCell = layoutToCell(layout, positions)
% Convert layout struct array to a cell array of structs for jsonencode.
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

    tileCell{tileIdx} = tileStruct;
end
end

% =========================================================================
function edgeCell = edgesToCell(edges)
% Convert edges struct array to a cell array for jsonencode.
numEdges = numel(edges);
edgeCell = cell(numEdges, 1);
for edgeIdx = 1:numEdges
    edgeStruct.i         = edges(edgeIdx).i;
    edgeStruct.j         = edges(edgeIdx).j;
    edgeStruct.direction = edges(edgeIdx).direction;
    edgeStruct.nominal   = edges(edgeIdx).nominal;
    if isfield(edges, 'measured')
        edgeStruct.measured  = edges(edgeIdx).measured;
        edgeStruct.quality   = edges(edgeIdx).quality;
        edgeStruct.valid     = edges(edgeIdx).valid;
    end
    edgeCell{edgeIdx} = edgeStruct;
end
end

% =========================================================================
function result = endsWith(str, suffix)
% Simple endsWith helper (avoids toolbox dependency).
result = numel(str) >= numel(suffix) && strcmp(str(end-numel(suffix)+1:end), suffix);
end
