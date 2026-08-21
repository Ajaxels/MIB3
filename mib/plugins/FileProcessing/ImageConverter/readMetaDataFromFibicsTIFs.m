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

function dataOut = readMetaDataFromFibicsTIFs(filename)
% function dataOut = readMetaDataFromFibicsTIFs(filename)
% read meta data from TIF files
%
% Parameters:
% filename: full path to TIF filename

% Updates
% 


info = imfinfo(filename);

% the tags are returned for any vendor, not only for Fibics: the consumer
% (extractToXMLMetaFromFibicsTIFs) detects XML vs plain text headers itself
if isfield(info, 'UnknownTags')
    dataOut = info(1).UnknownTags.Value;
else
    dataOut = [];
end
end