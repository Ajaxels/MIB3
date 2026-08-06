function model = storeLoadModel(filename)
% STORELOADMODEL - Load a MIB label model from a MAT file for use with ``pixelLabelDatastore``.
%
% Syntax:
%   .. code-block:: matlab
%
%      model = storeLoadModel(filename)
%
% Input Arguments:
%   - **filename** - [string] full path to the MAT file containing the model
%
% Output Arguments:
%   - **model** - loaded model array
%

res = load(filename, '-mat');
model = res.(res.modelVariable);
end
