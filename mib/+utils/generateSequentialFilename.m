function fn = generateSequentialFilename(name, num, files_no, ext)
% function fn = generateSequentialFilename(name, num, files_no, ext)
% returns a filename string where NUM is zero-padded to as many digits as needed
% to represent the total file count FILES_NO.
%
%   Inputs:
%     name     - Base filename string, e.g. 'image'
%     num      - Current file index (1-based), e.g. 5
%     files_no - Total number of files in the sequence, e.g. 200
%     ext      - File extension string including dot, e.g. '.tif'
%
%   Output:
%     fn       - Filename string, e.g. 'image_005.tif'
%
%   Notes:
%     - If FILES_NO == 1, no index suffix is added.
%     - Minimum zero-padding is 2 digits (for FILES_NO < 100).
%     - Padding width scales automatically with FILES_NO.
%
%   Example:
%     % Generate filenames for a 500-image sequence
%     for k = 1:500
%         fn = utils.generateSequentialFilename('image', k, 500, '.tif');
%     end
%     % k=1   -> 'image_001.tif'
%     % k=42  -> 'image_042.tif'
%     % k=500 -> 'image_500.tif'

if files_no == 1
    fn = [name ext];
else
    digits = max(2, floor(log10(files_no)) + 1);
    fn = sprintf('%s_%0*i%s', name, digits, num, ext);
end
end