function result = mibImWrite(img, filename, parameters)
% MIBIMWRITE - Save image to a file using MATLAB imwrite function.
%
% Wraps ``imwrite`` with dynamic parameter passing from a structure.
% Supports all formats handled by ``imwrite`` (TIF, PNG, JPG, BMP, etc.).
%
% Syntax:
%   .. code-block:: matlab
%
%       result = utils.mibImWrite(img, filename)
%       result = utils.mibImWrite(img, filename, parameters)
%
% Parameters:
%   **img** — image array [height, width, colors]
%
%   **filename** — destination filename (extension determines format)
%
%   **parameters** *(optional)* — structure whose field names and values are
%       passed as name-value pairs to ``imwrite``. For example:
%
%       - ``.Compression`` — ``'lzw'``, ``'none'``, etc. (TIF)
%       - ``.Quality`` — numeric 0–100 (JPG)
%       - ``.BitDepth`` — numeric bit depth (PNG)
%
% Return values:
%   **result** — ``1`` on success, ``0`` on failure

result = 0; %#ok<NASGU>
[~, ~, ext] = fileparts(filename);
if nargin < 3;     parameters = struct();  end

fields = fieldnames(parameters);
formatOut = ext(2:end);

if numel(fields) > 0
    str2 = ['imwrite(img, filename, ''', formatOut, ''''];
    for fieldId = 1:numel(fields)
        if isa(parameters.(fields{fieldId}), 'char')
            str2 = sprintf('%s, ''%s'', ''%s''', str2, fields{fieldId}, parameters.(fields{fieldId}));
        else
            str2 = sprintf('%s, ''%s'', %d', str2, fields{fieldId}, parameters.(fields{fieldId}));
        end
    end
    str2 = sprintf('%s);', str2);
    eval(str2);
else
    imwrite(img,filename, formatOut);
end

fprintf('ib_imwrite: %s was saved.\n', filename);
result = 1;
end
