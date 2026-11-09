function [mibModel, volume, scratch] = buildBigDataModel(testCase, colors, options)
% BUILDBIGDATAMODEL - A fresh MibModel with a synthetic BigData dataset in buffer 1.
%
% Writes a 300 x 260 x 3 OME-Zarr v3 pyramid (3 levels, XY only, chunks
% 64 x 64 x 1) with ``colors`` channels into a temporary folder of ``testCase``
% and opens it as BigData through ``controllers.BigDataOptions.openStoreInBuffer``.
% The model is built with ``Verbose = false, Preferences = 'defaults'``.
%
% Input Arguments:
%   - **testCase** - matlab.unittest.TestCase; owns the temporary folder
%   - **colors** - [double] number of colour channels
%   - **options.DataClass** - ``'uint8'`` (default, values 0-255) or ``'uint16'``
%     (values 0-40000, so the maximum is not the maximum of the class)
%
% Output Arguments:
%   - **mibModel** - models.MibModel
%   - **volume** - [300 260 3 colors], the ground truth in the dataset layout [H W Z C]
%   - **scratch** - [char] the temporary folder; the source store is ``source.zarr3`` in it
%
% See also: mibtest.helpers.attachBigDataLabels

arguments
    testCase
    colors (1,1) double
    options.DataClass (1,:) char {mustBeMember(options.DataClass, {'uint8', 'uint16'})} = 'uint8'
end
tf = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
scratch = tf.Folder;
rng(7);
height = 300; width = 260; depth = 3;
maxValue = 255;
if strcmp(options.DataClass, 'uint16'); maxValue = 40000; end
volume = cast(maxValue * mat2gray(convn(randn(height, width, depth, colors), ones(5, 5), 'same')), options.DataClass);
sourcePath = fullfile(scratch, 'source.zarr3');
metadata = struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.05, 'units', 'um'));
io.savers.Zarr3Saver(struct()).save(reshape(volume, height, width, depth, colors, 1), metadata, sourcePath, ...
    struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], 'Levels', 3, ...
    'DownsampleStrategy', 'XY only'));
% the dataset arrays are [H W Z C]; keep the ground truth in the same order
volume = reshape(volume, height, width, depth, colors);

mibFolder = fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), 'mib');
mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
controllers.BigDataOptions.openStoreInBuffer(mibModel, sourcePath, 1);
end
