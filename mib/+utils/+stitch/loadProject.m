function [layout, edges, positions, solverInfo, outputInfo, tforms, zSliceFixes, settings, tileStack] = loadProject(filePath)
% LOADPROJECT - Load a stitching project from a JSON sidecar file.
%
% Syntax:
%   .. code-block:: matlab
%
%      [layout, edges, positions, solverInfo, outputInfo] = utils.stitch.loadProject(filePath)
%      [layout, edges, positions, solverInfo, outputInfo, tforms] = utils.stitch.loadProject(filePath)
%      [..., tforms, zSliceFixes, settings] = utils.stitch.loadProject(filePath)
%
% Reads the ``*.mibstitch.json`` file saved by ``utils.stitch.saveProject``
% and reconstructs all stitching state structs.  ``positions`` is ``[]``
% when ``solvedOrigin`` was not recorded in the file.
%
% Input Arguments:
%   - **filePath** - [char] full path to the ``.mibstitch.json`` file
%
% Output Arguments:
%   - **layout** - struct array with tile fields (index, filename, etc.)
%   - **edges** - struct array with pair edge fields (i, j, direction, nominal, …;
%     ``tform`` carries the 3x3 pairwise transform when one was measured)
%   - **positions** - [double] N-by-3 solved origins ``[y x z]``, or ``[]``
%   - **solverInfo** - struct with solver settings / RMSE
%   - **outputInfo** - struct with blend / output settings
%   - **tforms** - [N x 1 cell] solved per-tile 3x3 transforms (``{}`` for
%     translation-only projects; tiles saved without one fall back to a pure
%     translation synthesised from ``solvedOrigin``)
%   - **zSliceFixes** - [K x 3] per-slice mosaic corrections ``[z dy dx]``
%     from the seam inspector's Fix Z (``[]`` when none were saved)
%   - **settings** - struct of flattened tool settings (schema v3 and newer);
%     an empty struct for older files that carry no ``settings`` block
%   - **tileStack** - [1 x N] ``'Overwrite'`` drawing order, bottom first, as set
%     in the seam inspector; ``[]`` when none was saved (default order)
%
% **Example** - round-trip save / load:
%
%   .. code-block:: matlab
%
%      utils.stitch.saveProject('C:\data\exp.mibstitch.json', layout, edges, [], [], []);
%      [layout2, edges2, pos, si, oi] = utils.stitch.loadProject('C:\data\exp.mibstitch.json');
%

arguments
    filePath (1,:) char
end

if ~isfile(filePath)
    error('utils:stitch:loadProject:fileNotFound', 'File not found: %s', filePath);
end

rawText = fileread(filePath);
project = jsondecode(rawText);

% Reconstruct layout struct array
layout = cellToLayout(project.tiles);

% Reconstruct edges struct array
if isfield(project, 'edges') && ~isempty(project.edges)
    edges = cellToEdges(project.edges);
else
    edges = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
end

% Extract solved positions
numTiles = numel(layout);
positions = [];
if numTiles > 0 && isfield(layout(1), 'solvedOrigin') && ~isempty(layout(1).solvedOrigin)
    positions = zeros(numTiles, 3);
    for tileIdx = 1:numTiles
        if ~isempty(layout(tileIdx).solvedOrigin)
            positions(tileIdx, :) = layout(tileIdx).solvedOrigin;
        else
            positions(tileIdx, :) = layout(tileIdx).nomOrigin;
        end
    end
end

% Solver info
if isfield(project, 'solverInfo') && ~isempty(fieldnames(project.solverInfo))
    solverInfo = project.solverInfo;
else
    solverInfo = [];
end

% Output info
if isfield(project, 'outputInfo') && ~isempty(fieldnames(project.outputInfo))
    outputInfo = project.outputInfo;
else
    outputInfo = [];
end

% Solved per-tile transforms (affine projects). Restored only when at least one
% tile carries a solvedTform; tiles without one get a pure translation from
% their solvedOrigin (position of pixel (1,1) => p = origin_xy - 1).
tforms = {};
if numTiles > 0 && isfield(layout(1), 'solvedTform') && ...
        any(arrayfun(@(t) ~isempty(t.solvedTform), layout))
    tforms = cell(numTiles, 1);
    for tileIdx = 1:numTiles
        if ~isempty(layout(tileIdx).solvedTform)
            tforms{tileIdx} = layout(tileIdx).solvedTform;
        else
            if ~isempty(positions)
                originYXZ = positions(tileIdx, :);
            else
                originYXZ = layout(tileIdx).nomOrigin;
            end
            tforms{tileIdx} = [eye(2), [originYXZ(2) - 1; originYXZ(1) - 1]; 0 0 1];
        end
    end
end

% Per-slice mosaic corrections (inspector Fix Z), rows [z dy dx].
% jsondecode returns a 1x3 vector for a single row - normalise to K x 3.
zSliceFixes = [];
if isfield(project, 'zSliceFixes') && ~isempty(project.zSliceFixes)
    zSliceFixes = double(project.zSliceFixes);
    if isvector(zSliceFixes); zSliceFixes = reshape(zSliceFixes, 1, []); end
end

% Tool settings (schema v3+). Older files have none - an empty struct then tells
% the caller there is nothing to restore into the dialog.
settings = struct();
if isfield(project, 'settings') && isstruct(project.settings) && ...
        ~isempty(fieldnames(project.settings))
    settings = project.settings;
end

% Overwrite drawing order (seam inspector). Validity against the layout is
% checked where it is used (utils.stitch.tileDrawOrder), not here.
tileStack = [];
if isfield(project, 'tileStack') && ~isempty(project.tileStack)
    tileStack = double(project.tileStack(:))';
end

end

% =========================================================================
function layout = cellToLayout(tilesData)
% Reconstruct layout struct array from jsondecode output.

if isempty(tilesData)
    layout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, 'zLayer', {}, ...
        'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {}, ...
        'solvedOrigin', {}, 'solvedTform', {});
    return;
end

% jsondecode returns cell array of structs or a struct array depending on content
if iscell(tilesData)
    numTiles = numel(tilesData);
    layout(numTiles) = struct('index', 0, 'filename', '', 'sliceFiles', {{}}, 'zLayer', 1, ...
        'gridRC', [0 0], 'nomOrigin', [0 0 0], 'tileSize', [0 0 0 0], 'dataClass', '', ...
        'solvedOrigin', [], 'solvedTform', []);
    for tileIdx = 1:numTiles
        layout(tileIdx) = copyTileFields(tilesData{tileIdx}, layout(tileIdx));
    end
else
    % struct array from jsondecode
    numTiles = numel(tilesData);
    for tileIdx = numTiles:-1:1
        layout(tileIdx) = copyTileFields(tilesData(tileIdx), struct());
    end
end

end

% =========================================================================
function targetTile = copyTileFields(sourceTile, targetTile)
% Copy decoded tile fields, coercing types as needed.
fieldList = {'index', 'filename', 'sliceFiles', 'zLayer', 'gridRC', ...
             'nomOrigin', 'tileSize', 'dataClass', 'solvedOrigin', 'solvedTform'};
for fieldIdx = 1:numel(fieldList)
    fieldName = fieldList{fieldIdx};
    if isfield(sourceTile, fieldName)
        value = sourceTile.(fieldName);
        % jsondecode returns row vectors; coerce numeric fields to double row -
        % except the 3x3 transform, whose shape must survive the round-trip.
        if isnumeric(value)
            if strcmp(fieldName, 'solvedTform')
                value = reshape(double(value), 3, []);
                if ~isequal(size(value), [3 3]); value = []; end
            else
                value = double(value(:))';
            end
        end
        targetTile.(fieldName) = value;
    else
        % Fill default for missing optional fields
        switch fieldName
            case {'solvedOrigin', 'solvedTform'};  targetTile.(fieldName) = [];
            case 'sliceFiles';    targetTile.(fieldName) = {};
            case 'dataClass';     targetTile.(fieldName) = 'uint8';
            otherwise;            targetTile.(fieldName) = [];
        end
    end
end
end

% =========================================================================
function edges = cellToEdges(edgesData)
% Reconstruct edges struct array from jsondecode output.

if isempty(edgesData)
    edges = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
    return;
end

if iscell(edgesData)
    numEdges = numel(edgesData);
    for edgeIdx = numEdges:-1:1
        edges(edgeIdx) = copyEdgeFields(edgesData{edgeIdx});
    end
else
    numEdges = numel(edgesData);
    for edgeIdx = numEdges:-1:1
        edges(edgeIdx) = copyEdgeFields(edgesData(edgeIdx));
    end
end

end

% =========================================================================
function edgeStruct = copyEdgeFields(source)
edgeStruct.i         = double(source.i);
edgeStruct.j         = double(source.j);
edgeStruct.direction = source.direction;
edgeStruct.nominal   = double(source.nominal(:))';

if isfield(source, 'measured')
    edgeStruct.measured = double(source.measured(:))';
    edgeStruct.quality  = double(source.quality);
    edgeStruct.valid    = logical(source.valid);
end

% Pairwise transform (present on edges measured with a non-translation model).
% Always set the field so the struct array stays homogeneous.
if isfield(source, 'tform') && ~isempty(source.tform)
    edgeStruct.tform = reshape(double(source.tform), 3, []);
    if ~isequal(size(edgeStruct.tform), [3 3]); edgeStruct.tform = []; end
else
    edgeStruct.tform = [];
end

% Seam-inspector provenance (schema v2); v1 files default to 'auto' / unscored.
if isfield(source, 'source') && ~isempty(source.source)
    edgeStruct.source = char(source.source);
else
    edgeStruct.source = 'auto';
end
if isfield(source, 'seamScore') && ~isempty(source.seamScore)
    edgeStruct.seamScore = double(source.seamScore);
else
    edgeStruct.seamScore = [];
end
if isfield(source, 'dzHint') && ~isempty(source.dzHint)
    edgeStruct.dzHint = double(source.dzHint);
else
    edgeStruct.dzHint = 0;   % "solved dz is the local optimum" / unscored
end
end
