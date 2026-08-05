function filename = stitchedFilename(obj)
% STITCHEDFILENAME - Name for the dataset a stitch produces.
%
% Syntax:
%   .. code-block:: matlab
%
%      filename = obj.stitchedFilename()
%
% ``<source>_stitch.tif``, next to whatever the mosaic was built from: the
% position file for a Position-file layout, otherwise the first tile. A stitched
% mosaic has no file of its own until it is saved, and a dataset with no filename
% makes ``Save as`` open on MATLAB's working folder - somewhere unrelated to the
% data. Pointing it at the source folder puts the suggested name where the tiles
% are, which is where the result belongs.
%
% The extension is always ``.tif`` regardless of what the tiles were: it names a
% single assembled 2-D/3-D image, which is not the same kind of thing as an MRC
% montage container or a ``.ve-mif`` mosaic record, and offering to save a mosaic
% back as its vendor's acquisition format would be wrong.
%
% Output Arguments:
%   - **filename** - [char] full path, e.g. a montage picked as
%     ``C:\data\Cell1.mrc.mdoc`` becomes ``C:\data\Cell1_stitch.tif``.
%
% See also controllers.Stitching.stitchBtn_Callback

sourcePath = '';

% A Position-file layout is named by the position file itself - it is the thing
% the user picked, and for a SerialEM montage the "first tile" is a slice index
% inside one container rather than a file of its own.
if strcmp(obj.BatchOpt.LayoutSource{1}, 'Position file') && ~isempty(obj.BatchOpt.InputPath)
    sourcePath = strtrim(strsplit(obj.BatchOpt.InputPath, newline));
    sourcePath = sourcePath{1};
end

if isempty(sourcePath) && ~isempty(obj.layout) && isfield(obj.layout, 'filename')
    sourcePath = obj.layout(1).filename;
end
if isempty(sourcePath) && ~isempty(obj.layout) && isfield(obj.layout, 'sliceFiles') && ...
        ~isempty(obj.layout(1).sliceFiles)
    % A tile that is a folder Z-stack: name it after the folder, not slice 1.
    sourcePath = fileparts(obj.layout(1).sliceFiles{1});
end
if isempty(sourcePath)
    sourcePath = obj.BatchOpt.InputPath;
end
if isempty(sourcePath)
    filename = 'stitch.tif';
    return;
end

[sourceFolder, baseName] = fileparts(sourcePath);

% Strip a compound extension the way the user reads it: `Cell1.mrc.mdoc` is
% "Cell1", not "Cell1.mrc". fileparts only removes the last one.
[~, innerName, innerExt] = fileparts(baseName);
if ~isempty(innerExt) && numel(innerExt) <= 6 && ~isempty(innerName)
    baseName = innerName;
end

if isempty(baseName); baseName = 'stitch'; end
filename = fullfile(sourceFolder, [baseName '_stitch.tif']);

end
