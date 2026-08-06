function result = struct2array(S)
% STRUCT2ARRAY - Convert a scalar struct to a flat array of its field values.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      result = struct2array(S)
%
% Replacement for the built-in ``struct2array`` that was removed in MATLAB R2021b.
%
% Input Arguments:
%   - **S** - [struct] scalar input structure
%
% Output Arguments:
%   - **result** - array containing all field values of S concatenated horizontally
%
% Usage:
%
%   **Example 1** - flatten a struct of numeric values
%
%   .. code-block:: matlab
%
%      S.a = 1; S.b = 2; S.c = 3;
%      result = utils.struct2array(S);   % result = [1 2 3]
%

% Convert structure to cell
c = struct2cell(S);

% generate an array
result = [c{:}];
