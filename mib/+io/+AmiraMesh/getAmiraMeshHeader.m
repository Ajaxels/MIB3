function [par, img_info, dim_xyczt, materialNames, materialColors] = getAmiraMeshHeader(filename)
% GETAMIRAMESHHEADER - Get header of Amira Mesh file.
%
% Syntax:
%   .. code-block:: matlab
%
%      [par, img_info, dim_xyczt] = io.AmiraMesh.getAmiraMeshHeader()
%      [par, img_info, dim_xyczt, materialNames, materialColors] = io.AmiraMesh.getAmiraMeshHeader(filename)
%
% Input Arguments:
%   - **filename** - *(optional)* filename of Amira Mesh file; when omitted,
%     a file selection dialog is started
%
% Output Arguments:
%   - **par** - struct array with header parameters; each element has fields:
%
%     - ``.Name`` - parameter name string
%     - ``.Value`` - parameter value
%
%   - **img_info** - MATLAB dictionary (``configureDictionary("string","cell")``);
%     access values with ``{}`` indexing
%   - **dim_xyczt** - [1×5] dataset dimensions [width, height, colors, depth, time]
%   - **materialNames** - cell array of detected material names (``Exterior`` excluded)
%   - **materialColors** - [Nx3] RGB material colours (0-1); ``Exterior`` excluded
%

% Updates
% 09.01.2018, IB added extraction of embedded containers in the amiramesh headers
% 30.01.2019, IB updated to be compatible with version 3

par = [];
img_info = configureDictionary("string","cell");  % string keys, cell-wrapped values (MIB3 standard)
dim_xyczt = [];
materialNames = {};
materialColors = [];

if nargin < 1
    [filename, pathname] = utils.dlgs.mibUiGetFile( ...
        {'*.am','Amira mesh labels(*.am)';
         '*.*',  'All Files (*.*)'}, ...
         'Pick a file');
    if isequal(filename, 0); return; end
    filename = [pathname filename{1}];
end
%fid = fopen(filename, 'r');
fid = fopen(filename, 'r', 'n', 'UTF-8');

% define type of data
tline = fgetl(fid);
if strcmp(tline(1:20), '# AmiraMesh 3D ASCII') % if strcmp(tline, '# AmiraMesh 3D ASCII 2.0')    
    type = 'ascii';
elseif strcmp(tline(1:20), '# AmiraMesh BINARY-L') || strcmp(tline(1:20),'# AmiraMesh 3D BINAR') %elseif strcmp(tline, '# AmiraMesh BINARY-LITTLE-ENDIAN 2.1') || strcmp(tline,'# AmiraMesh 3D BINARY 2.0')
    type = 'binary';
else
    disp('Error! Unknown type'); return;
end

% define lattice info
while numel(strfind(tline,'Lattice')) == 0
    tline = fgetl(fid);
end
spaces = strfind(tline,' ');
width = str2double(tline(spaces(2):spaces(3)));
height = str2double(tline(spaces(3):spaces(4)));
depth = str2double(tline(spaces(4):end));

% get Parameters
while numel(strfind(tline,'Parameters')) == 0
    tline = fgetl(fid);
end

par = struct();
level = 0;
% skiping the header
parIndex = 1;

while numel(strfind(tline, 'Lattice')) == 0
    tline = strtrim(fgetl(fid));
    if numel(strfind(tline, 'Lattice')) ~= 0; break; end
    if isempty(tline); continue; end
    if level == 0; field = cellstr(''); end
    
    openGroup = strfind(tline, '{');
    closeGroup = strfind(tline, '}');
    if ~isempty(openGroup) & isempty(closeGroup)
        level = level + 1;
        if strcmp(strtrim(tline(1:openGroup(1)-1)),'im_browser')    % remove the group made with im_browser
            field(level) = cellstr('');
        elseif strcmp(strtrim(tline(1:openGroup(1)-1)),'HistoryLogHead')    % remove the group HistoryLogHead
            % HistoryLogHead is Amira's undo/history log, not metadata. It cannot be
            % skipped line-by-line like the rest of the header: its ModuleState entries
            % are multi-line quoted strings containing braces and even the word
            % "Lattice", which corrupts the brace level and terminates this loop early
            % (leaving par without a single field). Consume the whole group at once,
            % honouring quoting, and drop back to the level we came from.
            level = level - 1;
            io.AmiraMesh.skipQuotedGroup(fid);
        elseif tline(end) == '{' && level > 1
            level = level - 1;
            par(parIndex).Name = field{level};
            par(parIndex).Value = cellstr(loopHeader(fid, tline, level));
            parIndex = parIndex + 1;
        else
            field(level) = cellstr(tline(1:openGroup(1)-1));
        end
    elseif isempty(openGroup) & ~isempty(closeGroup)
        level = level - 1;
        if level == -1; break; end  % end of the Parameters section
        field(level+1) = cellstr('');
    else
        spaces = strfind(strtrim(tline), ' ');
        if isempty(spaces); continue; end
        parField = '';
        for lev = 1:level
            parField = [parField '_' field{lev}];
        end
        
        try
            parField = [parField '_' tline(1:spaces(1)-1)];
        catch err
            0
        end
        if parField(1) == '_'; parField = parField(2:end); end
        if parField(1) == '_'; parField = parField(2:end); end
        
        value = tline(spaces(1)+1:end);
        
        if value(end) ~= ',' && value(end) ~= '"' && ~strcmp(parField,'CoordType')
            tline2 = strtrim(fgetl(fid));
            if tline2(1) ~= '}'
                value = sprintf('%s \t %s', value, tline2);
            else
                level = level - 1;
            end
        end
        
        if value(end) == ','
            value = value(1:end-1); 
        end  % remove ending comma 

        if numel(value)>0 && value(1) == '"' && value(end) == '"' 
            value = value(2:end-1); 
        elseif numel(value)>0
            if isempty(strfind(value, ' '))
                value = str2num(value); 
            end
        end   % remove quotation marks from strings 
        %par.(parField) = cellstr(value);
        par(parIndex).Name = parField;
        par(parIndex).Value = value;
        parIndex = parIndex + 1;
    end
end

% check the header for proper CoordType and ContentType fields
HxMultiChannelField3_sw = 0;
% par stays a fieldless struct() when the Parameters block held nothing parsable,
% which would make {par.Name} throw "Unrecognized field name"
if ~isfield(par, 'Name'); par = struct('Name', {}, 'Value', {}); end
parNames = {par.Name};
parIndex = find(ismember(parNames, 'ContentType'));
if ~isempty(parIndex)
    if strcmp(par(parIndex(1)).Value,'HxMultiChannelField3') == 1
        HxMultiChannelField3_sw = 1;
    end
end

% get number of data blocks
dataIndex = 1;
while numel(strfind(tline,'# Data section follows')) == 0
    if numel(strfind(tline,'Lattice')) ~= 0
        if numel(strfind(tline,'byte')) ~= 0
            classType(dataIndex) = cellstr('uint8');
        elseif numel(strfind(tline,'ushort')) ~= 0 || numel(strfind(tline,'usingle')) ~= 0
            classType(dataIndex) = cellstr('uint16');
        elseif numel(strfind(tline,'int')) ~= 0
            classType(dataIndex) = cellstr('uint32');
        end

        % check for zip compression
        if strfind(tline, 'HxZip')
            errordlg(sprintf('!!! Error !!!\n\nUnfortunately MIB is not yet compatible with Zip-compressed AM files; please use BioFormats reader instead!\n\n- Check the Directory contents panel->Bio checkbox\n- Right mouse click over "all known"\n- Select "Register extension"\n- Add "am" to the "Bioformats file reader" editbox')); 
            par = [];
            return;
        end

        % define number of colors
        openBlock = strfind(tline,'[');
        closeBlock = strfind(tline,']');
        if ~isempty(openBlock) && ~isempty(closeBlock)
            colorChannels(dataIndex) = str2double(tline(openBlock+1:closeBlock-1));
        else
            colorChannels(dataIndex) = 1;
        end
        dataIndex = dataIndex + 1;
    end
    tline = fgetl(fid);
end
fclose(fid);

if HxMultiChannelField3_sw == 1     % each data block is a single color channel
    colorChannels = ones(dataIndex,1)*(dataIndex - 1);
end

warning_state = warning('off');
for p=1:numel(par)
    if strcmp(par(p).Name,'BoundingBox')
        bb = str2num(par(p).Value); %#ok<ST2NM>
        bb = sprintf('%f %f %f %f %f %f', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
    else
        fieldName = par(p).Name;
        fieldName = strrep(fieldName,':','_');
        fieldName = strrep(fieldName,'.','_');
        fieldName = strrep(fieldName,'-','_');
        img_info{string(fieldName)} = par(p).Value;

        % get material names and colors
        if strcmp(par(p).Name, 'Materials')
            matName = par(p).Value{1};
            pos1 = strfind(matName, '{');
            if ~isempty(pos1)
                matName = matName(1:pos1-2);
                if ~strcmp(matName, 'Exterior')
                    materialNames = [materialNames; {matName}];
                    % Extract Color field: "Color R G B [A]"
                    colorTok = regexp(par(p).Value{1}, 'Color\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', 'tokens', 'once');
                    if ~isempty(colorTok)
                        rgb = [str2double(colorTok{1}), str2double(colorTok{2}), str2double(colorTok{3})];
                    else
                        rgb = rand(1, 3);
                    end
                    materialColors = [materialColors; rgb]; %#ok<AGROW>
                end
            else
                break;
            end
        end
    end
end

warning(warning_state);     % Switch warning back to initial settings
img_info{"imgClass"} = classType{1};
if max(colorChannels) > 1
    img_info{"ColorType"} = 'truecolor';
else
    img_info{"ColorType"} = 'grayscale';
end

if isKey(img_info, "ImageDescription")
    curr_text = img_info{"ImageDescription"};
    bb_info_exist = strfind(curr_text, 'BoundingBox');
    if bb_info_exist == 1
        spaces = strfind(curr_text,' ');
        if numel(spaces) < 7; spaces(7) = numel(curr_text); end
        tab_pos = strfind(curr_text,sprintf('\t'));
        if isempty(tab_pos); tab_pos = strfind(curr_text,sprintf('|')); end
        pos = min([spaces(7) tab_pos]);
        img_info{"ImageDescription"} = ['BoundingBox ' bb curr_text(pos:end)];
    elseif bb_info_exist > 1 % a case when MIB TIF was saved as AM from Fiji
        curr_text = curr_text(bb_info_exist:end);
        spaces = strfind(curr_text,' ');
        if numel(spaces) < 7; spaces(7) = numel(curr_text); end
        tab_pos = strfind(curr_text,sprintf('\t'));
        if isempty(tab_pos); tab_pos = strfind(curr_text,sprintf('|')); end
        pos = min([spaces(7) tab_pos]);
        bb = curr_text(1:pos);
        img_info{"ImageDescription"} = ['BoundingBox ' bb curr_text(pos:end)];
    else
        img_info{"ImageDescription"} = ['BoundingBox ' bb curr_text];
    end
else
    if exist('bb','var')
        img_info{"ImageDescription"} = ['BoundingBox ' bb];
    else
        img_info{"ImageDescription"} = '';
    end
end
if HxMultiChannelField3_sw == 0 && max(colorChannels) == 4  % RGBA
    colorChannels = 3;
end
    
dim_xyczt = [width height max(colorChannels) depth 1];
end

function parValueText = loopHeader(fid, parValueText, level)
% LOOPHEADER - Collect embedded containers as plain text.
%
% Syntax:
%   .. code-block:: matlab
%
%      parValueText = loopHeader(fid, parValueText, level)
%
while level >= 1
    tline = strtrim(fgetl(fid));

    if tline(end) == '{'    % open group
        level = level + 1;
        parValueText = sprintf('%s\n%s', parValueText, tline);
    elseif tline(end) == '}'    % close group
        openGroup = strfind(tline, '{');
        closeGroup = strfind(tline, '}');
        if numel(openGroup) < numel(closeGroup)     % close the group
            level = level - 1;
            parValueText = sprintf('%s\n}', parValueText);
        else    % situation when: \"Deblur\" setVar \"CustomHelp\" {deblur.html}
            parValueText = sprintf('%s\n%s', parValueText, tline);
        end
    else
        parValueText = sprintf('%s\n%s', parValueText, tline);
    end
    %sprintf('Level: %d, %s', level, tline)
end
end
