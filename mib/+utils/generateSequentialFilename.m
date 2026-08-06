function fn = generateSequentialFilename(name, num, files_no, ext)
% GENERATESEQUENTIALFILENAME - Build a zero-padded sequential filename.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      fn = generateSequentialFilename(name, num, files_no, ext)
%
% Returns a filename string where ``num`` is zero-padded to as many digits
% as needed to represent the total file count ``files_no``.
%
% Input Arguments:
%   - **name**     - [char] base filename string, e.g. ``'image'``
%   - **num**      - [numeric] current file index (1-based), e.g. ``5``
%   - **files_no** - [numeric] total number of files in the sequence, e.g. ``200``
%   - **ext**      - [char] file extension string including dot, e.g. ``'.tif'``
%
% Output Arguments:
%   - **fn** - [char] filename string, e.g. ``'image_005.tif'``
%
% .. note::
%    When ``files_no == 1``, no index suffix is added.
%    Minimum zero-padding is 2 digits; padding width scales automatically with ``files_no``.
%
% Usage:
%
%   **Example 1** - generate filenames for a 500-image sequence
%
%   .. code-block:: matlab
%
%      for k = 1:500
%          fn = utils.generateSequentialFilename('image', k, 500, '.tif');
%          % k=1   -> 'image_001.tif'
%          % k=42  -> 'image_042.tif'
%          % k=500 -> 'image_500.tif'
%      end
%

if files_no == 1
    fn = [name ext];
else
    digits = max(2, floor(log10(files_no)) + 1);
    fn = sprintf('%s_%0*i%s', name, digits, num, ext);
end
end
