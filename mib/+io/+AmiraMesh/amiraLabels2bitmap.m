% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi 
% Date: 25.04.2023

function [bitmap] = amiraLabels2bitmap(filename)
% AMIRALABELS2BITMAP - Converts Amira Mesh Labels to bitmap matrix, for Amira ver. 5.2.2.
%
% Syntax:
%   .. code-block:: matlab
%
%      bitmap = io.AmiraMesh.amiraLabels2bitmap()
%      bitmap = io.AmiraMesh.amiraLabels2bitmap(filename)
%
% Input Arguments:
%   - **filename** - *(optional)* filename of Amira Mesh labels file; when omitted,
%     a file selection dialog is started
%
% Output Arguments:
%   - **bitmap** - label image as [height, width, colors, depth]
%

% Updates
% ver 1.01 - 18.05.2012 - updated read procedure
% ver 1.02 - 06.08.2012 - compatible with RLE compression algorithm
% ver 1.03 - 30.01.2019, IB updated to be compatible with version 3
% ver 1.04 - 01.11.2026, RLE decoded by the MEX io.AmiraMesh.hxByteRleDecode; byte-level RLE
%            for uint16/uint32, MIB2 word-level RLE files still read

bitmap = NaN;
if nargin < 1
    [filename, pathname] = utils.dlgs.mibUiGetFile( ...
        {'*.am','Amira mesh labels(*.am)';
         '*.*',  'All Files (*.*)'}, ...
         'Pick a file');
    if isequal(filename, 0); return; end
    filename = [pathname filename{1}];
end
%filename = 'ER.am';
%fid = fopen(filename, 'r');
fid = fopen(filename, 'r', 'n', 'UTF-8');

% define type of data
tline = fgetl(fid);
if strcmp(tline(1:20), '# AmiraMesh 3D ASCII') % strcmp(tline, '# AmiraMesh 3D ASCII 2.0')
    type = 'ascii';
elseif strcmp(tline(1:20), '# AmiraMesh BINARY-L') % strcmp(tline, '# AmiraMesh BINARY-LITTLE-ENDIAN 2.1')
    type = 'binary';
else
    disp('Error! Unknown type'); return;
end

% define lattice info
while numel(strfind(tline,'Lattice')) == 0
    tline = fgetl(fid);
end
spaces = strfind(tline,' ');
width = str2num(tline(spaces(2):spaces(3))); %#ok<ST2NM>
height = str2num(tline(spaces(3):spaces(4))); %#ok<ST2NM>
depth = str2num(tline(spaces(4):end)); %#ok<ST2NM>

tline = '';
% skiping the header until Lattice { byte Labels } to find out the compression settings
while numel(strfind(tline,'Lattice')) == 0
    tline = fgetl(fid);
end
% "@1(HxByteRLE,<size>)", where MIB3 pads the size with trailing spaces
rleTokens = regexp(tline, 'HxByteRLE\s*,\s*(\d+)', 'tokens', 'once');
RLEcompression = ~isempty(rleTokens);
if RLEcompression
    elementsInFile = str2double(rleTokens{1});
end
if isempty(strfind(tline, 'Labels'))
    msgbox(sprintf('Wrong data type!\nRequires Labels in the Lattice description!'), 'Error!', 'error');
    return;
end

if strfind(tline, 'byte')
    imgClass = 'uint8';
elseif strfind(tline, 'ushort')
    imgClass = 'uint16';
elseif strfind(tline, 'int')
    imgClass = 'uint32';
else
    msgbox('Wrong data type!', 'Error!', 'error');
    return;
end

% skiping the rest of the header
while numel(strfind(tline,'# Data section follows')) == 0
    tline = fgetl(fid);
end
tline = fgetl(fid); % '@1'

elements_no = height*width*depth;
if strcmp(type,'ascii')
    bitmap_vec = zeros(elements_no,1,'uint8'); 
    for index=1:elements_no
        bitmap_vec(index) = str2num(fgetl(fid));
    end
    fclose(fid);
else
    if RLEcompression == 0
        switch imgClass
            case 'uint8'
                bitmap_vec = fread(fid, height*width*depth, '*uint8', 0, 'ieee-le');
            case 'uint16'
                bitmap_vec = fread(fid, height*width*depth, '*uint16', 0, 'ieee-le');
            case 'uint32'
                bitmap_vec = fread(fid, height*width*depth, '*uint32', 0, 'ieee-le');
            end
        fclose(fid);
    else    % read RLE compressed block
        % HxByteRLE is a byte stream and the size in the header counts bytes. MIB2 wrote
        % uint16/uint32 labels with word-sized packets and counted words instead; such a file
        % has (at least) size*bytesPerElement bytes after "@1", a byte stream only size + 1.
        bytesPerElement = numel(typecast(zeros(1, imgClass), 'uint8'));
        dataStart = ftell(fid);
        fseek(fid, 0, 'eof');
        bytesLeft = ftell(fid) - dataStart;
        fseek(fid, dataStart, 'bof');
        if bytesPerElement > 1 && bytesLeft >= elementsInFile * bytesPerElement
            stream = fread(fid, elementsInFile, ['*' imgClass], 0, 'ieee-le');
            bitmap_vec = io.AmiraMesh.hxByteRleDecode(stream, elements_no);
        else
            stream = fread(fid, elementsInFile, '*uint8');
            bitmap_vec = io.AmiraMesh.hxByteRleDecode(stream, elements_no * bytesPerElement);
            bitmap_vec = typecast(bitmap_vec, imgClass);
        end
        fclose(fid);
    end
end

% fclose(fid);
%bitmap_list = reshape(permute(bitmap,[2 1 3]),1,[])';
bitmap = reshape(bitmap_vec, [width, height, depth]);
bitmap = permute(bitmap, [2 1 3]);
disp(['amiraLabels2bitmap: ' filename ' was loaded!']);


