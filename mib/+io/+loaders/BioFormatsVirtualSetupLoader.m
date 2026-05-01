classdef BioFormatsVirtualSetupLoader < io.loaders.BaseImageLoader
% BIOFORMATSVIRTUALSETUPLOADER - Virtual-mode setup loader for BioFormats datasets.
%
% Wraps BioFormatsStdLoader and adapts it for virtual stacking mode:
% loadMetadata delegates entirely to BioFormatsStdLoader
% (series selection dialog, pixel-size extraction, etc.)
% loadImages does NOT read pixel data; instead returns the file
% path(s) as a cell array and stores the Virtual
% struct in imginfo{"Virtual"} so that
% MibVirtualImage.initialize can wire it up.
%
% **Relationship to BioFormatsVirtualLoader**
%
% These two classes serve different phases of the virtual dataset lifecycle:
%
% BioFormatsVirtualSetupLoader — runs ONCE when the user opens a file.
% Phase : dataset initialisation (MibModel.loadImages)
% Job : parse metadata, build the Virtual struct, return file paths.
% Reads pixels? No.
% Lifetime: discarded after open; implements BaseImageLoader.
% Created by: LoaderFactory
%
% BioFormatsVirtualLoader — runs on EVERY slice request during session.
% Phase : on-demand pixel reading (MibVirtualImage.getDataVirt)
% Job : open Memoizer reader, call bfGetPlane per channel.
% Reads pixels? Yes.
% Lifetime: cached in MibVirtualImage.loaders{} for the session.
% Created by: MibVirtualImage.getOrCreateLoader (lazily, per file)
%
% Usage example:
%
%   .. code-block:: matlab
%
%      loader = io.loaders.BioFormatsVirtualSetupLoader(options);
%      [imginfo, files] = loader.loadMetadata({'stack.czi'}, options);
%      [img, imginfo] = loader.loadImages(files, imginfo, options);
%      % img is {'C:\data\stack.czi'} and imginfo{"Virtual"} holds the struct

properties
    innerLoader
    % io.loaders.BioFormatsStdLoader instance that handles all
    % format-specific metadata parsing (series selection, pixel sizes, etc.)
end

methods
    function obj = BioFormatsVirtualSetupLoader(options)
        % BIOFORMATSVIRTUALSETUPLOADER - Create a virtual-mode BioFormats setup loader.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj = BioFormatsVirtualSetupLoader(options)
        %
        % Input Arguments:
        %   - **options** — *(optional)* [struct] options passed to BioFormatsStdLoader
        %
        % Output Arguments:
        %   - **obj** — [BioFormatsVirtualSetupLoader] new loader instance
        %

        obj.Options = struct();
        obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

        if nargin < 1; options = struct(); end
        obj.Options = obj.mergeOptions(obj.Options, options);
        obj.initBaseProps(options);
        obj.innerLoader = io.loaders.BioFormatsStdLoader(options);
    end

    function [imginfo, files] = loadMetadata(obj, filenames, options)
        % LOADMETADATA - Delegate metadata loading to BioFormatsStdLoader unchanged.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [imginfo, files] = obj.loadMetadata(filenames, options)
        %
        % Input Arguments:
        %   - **filenames** — [cell] cell array of file paths to load
        %   - **options** — [struct] loader options
        %
        % Output Arguments:
        %   - **imginfo** — [dictionary] image metadata dictionary
        %   - **files** — [struct array] per-file metadata; each element has fields:
        %
        %     - ``.origFilename`` — [char] path to the actual file
        %     - ``.seriesName``   — [numeric] 1-based series index
        %     - ``.noLayers``     — [numeric] number of z-slices in this series
        %     - ``.color``        — [numeric] number of colour channels
        %

        [imginfo, files] = obj.innerLoader.loadMetadata(filenames, options);
    end

    function [img, imginfo] = loadImages(obj, files, imginfo, options) 
        % LOADIMAGES - Virtual-mode image setup — does NOT load pixel data.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImages(files, imginfo, options)
        %
        % Returns the file path(s) as a cell array (consumed by
        % MibVirtualImage.initialize as obj.data{}) and populates
        % imginfo{"Virtual"} with the struct fields required by MibVirtualImage.
        %
        % Input Arguments:
        %   - **files** — [struct array] per-file metadata from loadMetadata
        %   - **imginfo** — [dictionary] image metadata from loadMetadata
        %   - **options** *(optional)* — [struct] unused in virtual mode
        %
        % Output Arguments:
        %   - **img** — [nFiles x 1 cell] cell array of original file paths
        %   - **imginfo** — [dictionary] updated dictionary; ``imginfo{"Virtual"}`` is
        %     added with fields:
        %
        %     - ``.objectType``    — [cell] ``'bioformats'`` per file
        %     - ``.seriesName``    — [cell] 1-based series index per file
        %     - ``.slicesPerFile`` — [numeric] z-slice count per file
        %     - ``.filenames``     — [cell] original file paths (before multi-series rename)
        %     - ``.readerId``      — [totalZ x 1 numeric] maps each slice index to its source file index
        %

        nFiles = numel(files);
        img = cell([nFiles 1]);

        Virtual.objectType    = cell([nFiles 1]);
        Virtual.seriesName    = cell([nFiles 1]);
        Virtual.slicesPerFile = zeros([nFiles 1]);
        Virtual.filenames     = cell([nFiles 1]);

        for i = 1:nFiles
            img{i}                  = files(i).origFilename;
            Virtual.filenames{i}    = files(i).origFilename;
            Virtual.seriesName{i}   = files(i).seriesName;   % 1-based series index
            Virtual.slicesPerFile(i)= files(i).noLayers;
            Virtual.objectType{i}   = 'bioformats';
        end

        % Build readerId: maps each global z-slice index to its source file index
        totalSlices       = sum(Virtual.slicesPerFile);
        Virtual.readerId  = zeros([totalSlices, 1]);
        idx = 1;
        for i = 1:nFiles
            n = Virtual.slicesPerFile(i);
            Virtual.readerId(idx : idx+n-1) = i;
            idx = idx + n;
        end

        % Update imginfo dimensions from files
        imginfo{"Height"} = max([files.height]);
        imginfo{"Width"}  = max([files.width]);
        imginfo{"Depth"}  = sum([files.noLayers]);
        imginfo{"Colors"} = max([files.color]);
        imginfo{"Time"}   = max([files.time]);

        imginfo{"Virtual"} = Virtual;
    end
end
end
