classdef BioFormatsVirtualSetupLoader < io.loaders.BaseImageLoader
% BIOFORMATSVIRTUALSETUPLOADER - Virtual-mode setup loader for BioFormats datasets.
%
% Wraps BioFormatsStdLoader and adapts it for virtual stacking mode:
%
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
% BioFormatsVirtualSetupLoader  — runs ONCE when the user opens a file.
% Phase   : dataset initialisation (MibModel.loadImages)
% Job     : parse metadata, build the Virtual struct, return file paths.
% Reads pixels? No.
% Lifetime: discarded after open; implements BaseImageLoader.
% Created by: LoaderFactory
%
% BioFormatsVirtualLoader  — runs on EVERY slice request during session.
% Phase   : on-demand pixel reading (MibVirtualImage.getDataVirt)
% Job     : open Memoizer reader, call bfGetPlane per channel.
% Reads pixels? Yes.
% Lifetime: cached in MibVirtualImage.loaders{} for the session.
% Created by: MibVirtualImage.getOrCreateLoader (lazily, per file)
%
%
% Usage:
%
% .. code-block:: matlab
%
%   loader = io.loaders.BioFormatsVirtualSetupLoader(options);
%   [imginfo, files] = loader.loadMetadata({'stack.czi'}, options);
%   [img, imginfo]   = loader.loadImages(files, imginfo, options);
%   % img is {'C:\data\stack.czi'} and imginfo{"Virtual"} holds the struct

    properties
        innerLoader
        % io.loaders.BioFormatsStdLoader instance that handles all
        % format-specific metadata parsing (series selection, pixel sizes, etc.)
    end

    methods
        function obj = BioFormatsVirtualSetupLoader(options)
            % BIOFORMATSVIRTUALSETUPLOADER - obj = BioFormatsVirtualSetupLoader(options).
            %
            % Syntax:
            %   function obj = BioFormatsVirtualSetupLoader(options)
            %
            % Constructor
            %
            % Input Arguments:
            %   - **options** — [*optional,* struct] options passed to BioFormatsStdLoader
            %

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
            obj.initBaseProps(options);
            obj.innerLoader = io.loaders.BioFormatsStdLoader(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - [imginfo, files] = loadMetadata(obj, filenames, options).
            %
            % Syntax:
            %   function [imginfo, files] = loadMetadata(obj, filenames, options)
            %
            % Delegate metadata loading to BioFormatsStdLoader unchanged.
            %
            % After this call:
            % files(i).origFilename  — path to the actual file
            % files(i).seriesName    — 1-based series index
            % files(i).noLayers      — number of z-slices in this series
            % files(i).color         — number of colour channels

            [imginfo, files] = obj.innerLoader.loadMetadata(filenames, options);
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options) %#ok<INUSD>
            % LOADIMAGES - [img, imginfo] = loadImages(obj, files, imginfo, options).
            %
            % Syntax:
            %   function [img, imginfo] = loadImages(obj, files, imginfo, options) %#ok<INUSD>
            %
            % Virtual-mode image setup — does NOT load pixel data.
            %
            % Returns the file path(s) as a cell array (consumed by
            % MibVirtualImage.initialize as obj.data{}) and populates
            % imginfo{"Virtual"} with the struct fields required by
            % MibVirtualImage:
            % .objectType    — 'bioformats' per file
            % .seriesName    — 1-based series index per file
            % .slicesPerFile — z-slice count per file
            % .filenames     — original file paths (before multi-series rename)
            % .readerId      — [1 x totalZ] map: slice index file index
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata
            %   - **imginfo** — dictionary from loadMetadata
            %   - **options** — (unused in virtual mode)
            %
            % Output Arguments:
            %   - **img** — {1 x nFiles} cell array of original file paths
            %   - **imginfo** — updated dictionary with imginfo{"Virtual"} added
            %

            nFiles = numel(files);
            img = cell([nFiles 1]);

            Virtual.objectType    = cell([nFiles 1]);
            Virtual.seriesName    = cell([nFiles 1]);
            Virtual.slicesPerFile = zeros([nFiles 1]);
            Virtual.filenames     = cell([nFiles 1]);

            for i = 1:nFiles
                img{i}                   = files(i).origFilename;
                Virtual.filenames{i}     = files(i).origFilename;
                Virtual.seriesName{i}    = files(i).seriesName;   % 1-based series index
                Virtual.slicesPerFile(i) = files(i).noLayers;
                Virtual.objectType{i}    = 'bioformats';
            end

            % Build readerId: maps each global z-slice index to its source file index
            totalSlices      = sum(Virtual.slicesPerFile);
            Virtual.readerId = zeros([totalSlices, 1]);
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
