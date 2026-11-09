function labels = attachBigDataLabels(testCase, mibModel, scratch)
% ATTACHBIGDATALABELS - An empty BigData model store next to the source, attached to buffer 1.
%
% Creates ``Labels_source.zarr3`` in ``scratch`` with the pyramid of the image
% of buffer 1, one material, and enables the selection. The store is closed at
% the teardown of ``testCase``.
%
% Input Arguments:
%   - **testCase** - matlab.unittest.TestCase
%   - **mibModel** - models.MibModel from ``mibtest.helpers.buildBigDataModel``
%   - **scratch** - [char] folder for the store
%
% Output Arguments:
%   - **labels** - core.MibBigDataLabels attached to ``mibModel.I{1}``
%
% See also: mibtest.helpers.buildBigDataModel

dataset = mibModel.I{1};
labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
labels.createStore([dataset.image.height dataset.image.width dataset.image.depth], ...
    fullfile(scratch, 'Labels_source.zarr3'), dataset.image.pyramid);
labels.materialNames = {'1'};
labels.materialColors = [1 0 0];
dataset.labels = labels;
dataset.modelExist = true;
dataset.enableSelection = true;
testCase.addTeardown(@() labels.closeStore());
end
