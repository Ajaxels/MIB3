function [layout, edges, positions, solverInfo, outputInfo] = loadProject(filePath)
% LOADPROJECT - Load a stitching project from a JSON sidecar file.
%
% Syntax:
%   .. code-block:: matlab
%
%      [layout, edges, positions, solverInfo, outputInfo] = utils.stitch.loadProject(filePath)
%
% Reads the ``*.mibstitch.json`` file saved by ``utils.stitch.saveProject``
% and reconstructs all stitching state structs.  ``positions`` is ``[]``
% when ``solvedOrigin`` was not recorded in the file.
%
% Input Arguments:
%   - **filePath** — [char] full path to the ``.mibstitch.json`` file
%
% Output Arguments:
%   - **layout** — struct array with tile fields (index, filename, etc.)
%   - **edges** — struct array with pair edge fields (i, j, direction, nominal, …)
%   - **positions** — [double] N-by-3 solved origins ``[y x z]``, or ``[]``
%   - **solverInfo** — struct with solver settings / RMSE
%   - **outputInfo** — struct with blend / output settings
%
% **Example** — round-trip save / load:
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

end

% =========================================================================
function layout = cellToLayout(tilesData)
% Reconstruct layout struct array from jsondecode output.

if isempty(tilesData)
    layout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, 'zLayer', {}, ...
        'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {}, 'solvedOrigin', {});
    return;
end

% jsondecode returns cell array of structs or a struct array depending on content
if iscell(tilesData)
    numTiles = numel(tilesData);
    layout(numTiles) = struct('index', 0, 'filename', '', 'sliceFiles', {{}}, 'zLayer', 1, ...
        'gridRC', [0 0], 'nomOrigin', [0 0 0], 'tileSize', [0 0 0 0], 'dataClass', '', 'solvedOrigin', []);
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
             'nomOrigin', 'tileSize', 'dataClass', 'solvedOrigin'};
for fieldIdx = 1:numel(fieldList)
    fieldName = fieldList{fieldIdx};
    if isfield(sourceTile, fieldName)
        value = sourceTile.(fieldName);
        % jsondecode returns row vectors; coerce numeric fields to double row
        if isnumeric(value)
            value = double(value(:))';
        end
        targetTile.(fieldName) = value;
    else
        % Fill default for missing optional fields
        switch fieldName
            case 'solvedOrigin';  targetTile.(fieldName) = [];
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
end
