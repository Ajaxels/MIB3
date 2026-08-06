function data = storeLoadCategorical(filename)
% STORELOADCATEGORICAL - Load a categorical dataset from a MAT file for use with ``pixelLabelDatastore``.
%
% Syntax:
%   .. code-block:: matlab
%
%      data = storeLoadCategorical(filename)
%
% Input Arguments:
%   - **filename** - [string] full path to the MAT file
%
% Output Arguments:
%   - **data** - cell array containing the loaded categorical variable

inp = load(filename, '-mat');
if isfield(inp, 'imgVariable')
    data = {inp.(inp.imgVariable)};
else
    f = fields(inp);
    data = {inp.(f{1})};
end
end
