function [tileFolders, trueWindows, parentFolder] = writeSerialSectionFolders(numSections, seed)
% WRITESERIALSECTIONFOLDERS - A small 2x2 serial-section montage, one folder per tile.
%
% Syntax:
%   .. code-block:: matlab
%
%      [tileFolders, trueWindows, parentFolder] = mibtest.helpers.writeSerialSectionFolders(6, 61)
%
% Writes the input ``BatchOpt.RegisterSlices`` expects: four folders
% (Horizontal order - tile_01 top-left ... tile_04 bottom-right) of 160x160 px
% TIFF slices, 40 px overlap between neighbours. Each section is its own image
% (a shared texture plus section-specific content), and every slice of every
% tile is cut +-2 px off its stage position, independently - stage backlash,
% no drift. Deterministic for a given ``seed``. The caller deletes
% ``parentFolder`` (``testCase.addTeardown(@() rmdir(parentFolder, 's'))``).
%
% Input Arguments:
%   - **numSections** - [double] slices per folder
%   - **seed** - [double] RNG seed
%
% Output Arguments:
%   - **tileFolders** - [1x4 cell] folder paths
%   - **trueWindows** - [4 x numSections x 2] ``[y x]`` origin of the window each
%     slice was cut from, in the coordinates of the section image
%   - **parentFolder** - [char] the temporary folder holding all four
%
% See also: StitchingControllerTest, StitchingInspectorControllerTest

margin = 4;
canvasSize = 280 + 2 * margin;
shared = double(mibtest.helpers.stitchTextureImage(canvasSize, canvasSize, seed));
parentFolder = tempname;
mkdir(parentFolder);
rng(seed, 'twister');
tileFolders = cell(1, 4);
trueWindows = zeros(4, numSections, 2);
for tileIdx = 1:4
    tileFolders{tileIdx} = fullfile(parentFolder, sprintf('tile_%02d', tileIdx));
    mkdir(tileFolders{tileIdx});
end
for section = 1:numSections
    own = double(mibtest.helpers.stitchTextureImage(canvasSize, canvasSize, seed + section));
    sectionImage = uint8(0.6 * shared + 0.4 * own);
    for tileIdx = 1:4
        row = ceil(tileIdx / 2);
        col = 2 - mod(tileIdx, 2);
        window = [1 + margin + (row - 1) * 120, 1 + margin + (col - 1) * 120] + randi([-2 2], 1, 2);
        trueWindows(tileIdx, section, :) = window;
        imwrite(sectionImage(window(1):window(1) + 159, window(2):window(2) + 159), ...
            fullfile(tileFolders{tileIdx}, sprintf('slice_%03d.tif', section)));
    end
end
end
