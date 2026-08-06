classdef MibIconCache
    % MIBIBONCACHE - Static cache for MIB icons and images backed by a MAT resource file.
    %
    % Provides fast access to cached icon and image files stored in a MAT resource file.
    % Improves performance up to 10 times relative to direct disk reads.
    % The cache is automatically built from asset directories and persists across calls.
    %
    % **Basic usage:**
    %
    %   .. code-block:: matlab
    %
    %       img = core.MibIconCache.get('icons', 'about_24px');
    %       img = core.MibIconCache.get('images', 'mib_question');
    %       core.MibIconCache.buildResourceFile(resourceFilePath, assetsDir);
    %
    % **Example** - benchmark cache performance vs. direct file reads:
    %
    %   .. code-block:: matlab
    %
    %       % Scan icons directory
    %       files = dir('C:\MATLAB\MIB3\mib\assets\icons\*.png');
    %       filesNames1 = {files.name};
    %       filesNames2 = cellfun(@(f) erase(f, '.png'), filesNames1, 'UniformOutput', false);
    %
    %       % Test 1: Cache (returns image arrays)
    %       t1 = tic;
    %       imgs = cell(numel(filesNames2), 1);
    %       for i = 1:numel(filesNames2)
    %           imgs{i} = core.MibIconCache.get('icons', filesNames2{i});
    %       end
    %       timeCache = toc(t1);
    %
    %       % Test 2: Direct imread (actually load images)
    %       t1 = tic;
    %       imgs2 = cell(numel(filesNames1), 1);
    %       for i = 1:numel(filesNames1)
    %           imgs2{i} = imread(fullfile(obj.controller.mibPath, 'assets/icons', filesNames1{i}));
    %       end
    %       timeFile = toc(t1);
    %
    %       % Show performance improvement
    %       fprintf('Time difference (timeCache/timeFile) = %f\n', timeCache/timeFile);

    methods (Static)
         function img = get(foldername, name, resourceFilePath, assetsDir)
            % GET - Return icon/image from the resource cache by name.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       img = MibIconCache.get(foldername, name, resourceFilePath, assetsDir)
            %
            % Retrieves a cached icon or image from the MAT resource file. If the cache
            % is not yet loaded, it is loaded from the persistent variable. If the resource
            % file is missing, it is automatically generated from the assets directory.
            %
            % Input Arguments:
            %   - **foldername** - [char] folder name specifying which type of resource:
            %
            %     - ``'icons'`` - icons folder
            %     - ``'images'`` - images folder
            %
            %   - **name** - [char] icon/image name without extension
            %   - **resourceFilePath** - *(optional)* [char] full path to resource file (default: ``MIB3/mib/assets/mib_icons.res``)
            %   - **assetsDir** - *(optional)* [char] path to assets directory containing 'images' and 'icons' folders (default: ``MIB3/mib/assets``)
            %
            % Output Arguments:
            %   - **img** - [numeric array] image data for the requested icon/image
            %
            % **Example 1** - get icon from the icons folder:
            %
            %   .. code-block:: matlab
            %
            %       img = core.MibIconCache.get('icons', 'about_24px');
            %
            % **Example 2** - get image from the images folder:
            %
            %   .. code-block:: matlab
            %
            %       img = core.MibIconCache.get('images', 'mib_question');
            %

            % Normalize inputs
            if nargin < 4; assetsDir = []; end
            if nargin < 3; resourceFilePath = []; end

            persistent iconCache cachePath assetsPath
            % iconCache - a structure with images and icons:
            % iconCache.icons: icons from "assets/icons/"
            % iconCache.images: images from "assets/images/"

            % ---------------- Fast path: warm cache ----------------
            % If the cache is already loaded and either:
            %  - no new resourceFilePath is requested, or
            %  - the requested resourceFilePath matches the cached one,
            % then try to serve directly from iconCache and return.
            if ~isempty(iconCache)
                if isempty(resourceFilePath) || strcmp(cachePath, resourceFilePath)
                    if isfield(iconCache, foldername) && ...
                            isfield(iconCache.(foldername), name)
                        img = iconCache.(foldername).(name);
                        return;
                    end
                end
            end

            % ---------------- Resolve paths (cold or changed) ----------------
            % Resolve assetsPath once and reuse.
            if ~isempty(assetsDir)
                assetsPath = assetsDir;
            elseif isempty(assetsPath)
                assetsPath = core.MibIconCache.getDefaultAssetsDir();
            end

            % Resolve resourceFilePath, prefer explicit argument if provided.
            if isempty(resourceFilePath)
                if isempty(cachePath)
                    resourceFilePath = core.MibIconCache.getDefaultResourcePath();
                else
                    resourceFilePath = cachePath;
                end
            end

            % ---------------- Load or reload MAT resource ----------------
            % Only reload if cache is empty or the resource path changed.
            if isempty(iconCache) || ~strcmp(cachePath, resourceFilePath)
                if ~isfile(resourceFilePath)
                    % Resource file missing: build from assetsPath
                    core.MibIconCache.buildResourceFile(assetsPath, resourceFilePath);
                end

                data = load(resourceFilePath, '-mat');
                if ~isfield(data, 'resources')
                    error('MibIconCache:InvalidResource', ...
                        'Resource MAT file "%s" does not contain ''resources'' struct.', ...
                        resourceFilePath);
                end

                iconCache = data.resources;
                cachePath = resourceFilePath;
            end

            % ---------------- Lookup in freshly loaded cache ----------------
            if ~isfield(iconCache, foldername) || ...
                    ~isfield(iconCache.(foldername), name)

                % Icon not found in cache: rebuild resource and try again
                core.MibIconCache.buildResourceFile(assetsPath, resourceFilePath);
                data = load(resourceFilePath, '-mat');
                if ~isfield(data, 'resources')
                    error('MibIconCache:InvalidResource', ...
                        'Resource MAT file "%s" does not contain ''resources'' struct.', ...
                        resourceFilePath);
                end

                iconCache = data.resources;
                cachePath = resourceFilePath;
            end

            % Final lookup / error
            if isfield(iconCache, foldername) && ...
                    isfield(iconCache.(foldername), name)
                img = iconCache.(foldername).(name);
            else
                error('MibIconCache:IconNotFound', ...
                    'MibIconCache: Icon "%s.%s" not found in resource cache (%s).', ...
                    foldername, name, resourceFilePath);
            end
        end


        function img = getIconData(iconData)
            % GETICONDATA - Extract icon image array from cache data and apply transparency.
            %
            % Syntax:
            %   function img = getIconData(iconData)
            %
            % Input Arguments:
            %   - **iconData** - a structure with
            %   - .cdata - matrix ([height, width, col_channel]) with intensity values for the icon
            %   - .alpha - matrix with the alpha value, can be empty
            %

            if isstruct(iconData)
                % New format: struct with cdata and alpha
                if isfield(iconData, 'cdata')
                    if isfield(iconData, 'alpha') && ~isempty(iconData.alpha)
                        % Has alpha channel: construct RGBA
                        if size(iconData.cdata, 3) == 3
                            % RGB + Alpha -> RGBA (4-channel uint8)
                            img = cat(3, iconData.cdata, iconData.alpha);
                        elseif size(iconData.cdata, 3) == 1
                            % Grayscale + Alpha -> LA (2-channel)
                            img = cat(3, iconData.cdata, iconData.alpha);
                        else
                            % Already has alpha or unknown format
                            img = iconData.cdata;
                        end
                    else
                        % No alpha channel
                        img = iconData.cdata;
                    end
                else
                    % Malformed struct, return as-is
                    img = iconData;
                end
            else
                % Old format: plain array (backward compatibility)
                img = iconData;
            end
        end

        function buildResourceFile(assetsDir, resourceFilePath)
            % BUILDRESOURCEFILE - Scan asset folders and rebuild the resource cache file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       MibIconCache.buildResourceFile(assetsDir, resourceFilePath)
            %
            % Scans the asset directories (icons, images) for image files and builds a MAT
            % resource file containing all images. This is called automatically when the
            % resource file is missing or when a requested icon is not found.
            %
            % Input Arguments:
            %   - **assetsDir** - *(optional)* [char] path to assets directory; when empty uses default (``MIB3/mib/assets``)
            %   - **resourceFilePath** - *(optional)* [char] path for output resource file; when empty uses default (``MIB3/mib/assets/mib_icons.res``)
            %
            % **Example** - build resource file from assets directory:
            %
            %   .. code-block:: matlab
            %
            %       assetsDir = fullfile(obj.mibPath, 'assets');
            %       resourceFile = fullfile(obj.mibPath, 'assets', 'mib_icons.res');
            %       core.MibIconCache.buildResourceFile(assetsDir, resourceFile);
            %

            if nargin < 1 || isempty(assetsDir)
                assetsDir = MibIconCache.getDefaultAssetsDir();
            end
            if nargin < 2 || isempty(resourceFilePath)
                resourceFilePath = MibIconCache.getDefaultResourcePath();
            end

            wb = waitbar(0, sprintf('Generating resource file\nPlease wait...'), 'Name', 'MibIconCache');
            % define subfolders that should be scanned to generate the cache file
            % subFolders = {'icons', 'images'};
            subFolders = {'alpha_cache'};  % images from this folder are converted into doubles with NaN instead of transparency

            % Define which image extensions to include
            exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif'};

            resources = struct();

            for folderId = 1:numel(subFolders)
                subFolderName = fullfile(assetsDir, subFolders{folderId});
                if ~isfolder(subFolderName)
                    errorText = sprintf('MibIconCache:IconDirMissing\n\nIcon/image directory:\n%s\ndoes not exist.', subFolderName);
                    utils.dlgs.showErrorDialog([], errorText, 'Error in MibIconCache');
                    return;
                end

                files = dir(subFolderName);
                %files([files.isdir]) = []; % remove folders
                files(~arrayfun(@(files) contains(files.name, exts), files)) = []; % filter files
                noFiles = numel(files);
                for fileId = 1:noFiles
                    [~, baseName] = fileparts(files(fileId).name);
                    imgPath = fullfile(subFolderName, files(fileId).name);
                    try
                        if strcmp(subFolders{folderId}, 'alpha_cache')
                            [iconImg, ~, transparency] = imread(imgPath);
                            transparency = repmat(transparency, [1,1,3]);
                            iconImg = double(iconImg)/255;
                            iconImg(transparency==0) = NaN;
                        else
                            [img.cdata, ~, img.alpha] = imread(imgPath);
                            % generate an image with the alpha channel blended
                            iconImg = core.MibIconCache.getIconData(img);
                        end
                    catch err
                        fprintf('MibIconCache:ReadFailed', ...
                            'MibIconCache:ReadFailed: failed to read icon "%s"\n', imgPath);
                        continue;
                    end
                    resources.(subFolders{folderId}).(baseName) = iconImg;
                    waitbar(fileId/noFiles, wb);
                end
            end

            save(resourceFilePath, 'resources', '-v6');  % 
            delete(wb);
        end

        function assetsDir = getDefaultAssetsDir()
            % GETDEFAULTASSETSDIR - Get the default folder where assets files live.
            %
            % Syntax:
            %   function assetsDir = getDefaultAssetsDir()
            %

            persistent mibPath
            if isempty(mibPath); mibPath = utils.getInstallationPath('mib3'); end

            assetsDir = fullfile(mibPath, 'assets');
        end

        function resourceFilename = getDefaultResourcePath()
            % GETDEFAULTRESOURCEPATH - Get location of the default MAT resource path.
            %
            % Syntax:
            %   function resourceFilename = getDefaultResourcePath()
            %
            % (assets\mib_icons.res) for icons and images

            persistent mibPath

            % obtain MIB path and generate resource filename
            if isempty(mibPath); mibPath = utils.getInstallationPath('mib3'); end
            resourceFilename = fullfile(mibPath, 'assets', 'mib_icons.res');
        end


    end
end
