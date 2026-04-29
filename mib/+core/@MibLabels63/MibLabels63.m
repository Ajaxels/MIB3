classdef MibLabels63 < core.MibImage 
    % MIBLABELS63 - memory optimized label class of MIB3 capable to encode 63 materials,.
    %
    % mask and selection layers within the same 8-bit container.
    % The class inherits properties and function of the parent class
    % (core.MibImage).
    % Constructor requires initialization as
    % "obj = obj@core.MibImage(img, meta);  % Call parent constructor"

    properties
        labelsVariable
        % @em labelsVariable is a variable name in the mat-file to keep the 'Labels' layer'; default: 'labelsVariable'
        materialColors
        % a matrix of colors [0-1] for materials of the 'Model', [materialIndex, R G B]
        materialNames
        % an array of strings to define names of materials of Labels
        materialsCount = 0
        % number of materials currently in the model; equals
        % numel(materialNames).  Updated by addMaterial (+1),
        % removeMaterial (-N), and createModel (initial value).
        maxMaterials = 63;
        % maximal number of materials available in this model type
    end

    methods
        % declaration of methods
        dataset = getData63(obj, type, orient, materialIndex, options)        % get dataset

        result = setData63(obj, dataset, type, orient, materialIndex, options)        % update contents of the class

        result = countMaterials(obj)                 % calculate and update materialsCount from materialNames or packed pixel data; call after load/import

        renameMaterial(obj, index, newName)          % rename one or all materials in the model metadata

        insertMaterial(obj, index, name, wb)     % insert a material at the specified position: shifts bit-packed pixel data and updates name/colour/materialsCount

        swapMaterials(obj, index1, index2)     % swap material names and colours between two positions

        reorderMaterials(obj, newOrder)        % reorder material names and colours according to newOrder

        fnOut = save(obj, filename, options)   % save label data to file; overrides MibImage.save() to use getData63() for correct bit-unpacking

        function obj = MibLabels63(img, meta)
            % MIBLABELS63 - Constructor of MibLabels63 — memory-optimised label storage.
            %
            % Syntax:
            %   function obj = MibLabels63(img, meta)
            %
            % that packs up to 63 materials, mask, and selection into a
            % single uint8 array (bits 1–6 = material index, bit 7 = mask,
            % bit 8 = selection).  Inherits from core.MibImage.
            %
            % Data layout: [H, W, Z, 1, T] — single color channel, depth
            % in dimension 3.  MibLabels63 does NOT apply the [H,W,C]→[H,W,1,C]
            % permute that MibImage uses for colour images.
            %
            % Input Arguments:
            %   - **img** — *(optional)* 2-D to 5-D uint8 array, or [].
            %     Dim 3 is always treated as depth (Z), never as color.
            %   - []              — empty placeholder; obj.exists = false
            %   - [H, W]          — single 2-D packed label map
            %   - [H, W, Z]       — 3-D packed label volume (Z slices)
            %   - [H, W, Z, 1, T] — full 5-D form (preferred for clarity)
            %   - **meta** — *(optional)* metadata dictionary from
            %     core.MibImage.initializeImgInfo().  Pass [] to use defaults.
            %
            %   After construction ALL dimension properties are set from the
            %   actual array size via MibImage.initialize():
            %   obj.height, obj.width, obj.depth, obj.colors (always 1),
            %   obj.time, obj.dim_yxzct, obj.maxInt, obj.dataClass
            %
            % Usage:
            %   **Example 1** — 1. 3-D packed label volume loaded from file
            %
            %   .. code-block:: matlab
            %
            %
            %     % 1. 3-D packed label volume loaded from file
            %     rawModel = uint8(zeros(254, 378, 3));  % [H,W,Z]
            %     meta = core.MibImage.initializeImgInfo( ...
            %         'pixSize', obj.image.pixSize, ...
            %         'Height', 254, 'Width', 378, 'Depth', 3, 'Time', 1, 'Colors', 1);
            %     lbl = core.MibLabels63(rawModel, meta);
            %     % lbl.depth == 3, lbl.colors == 1
            %
            %     % 2. Fresh empty allocation matching the current image
            %     dims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];
            %     meta = core.MibImage.initializeImgInfo( ...
            %         'pixSize', obj.image.pixSize, ...
            %         'Height', dims(1), 'Width', dims(2), 'Depth', dims(3), 'Time', dims(5));
            %     lbl = core.MibLabels63(zeros(dims, 'uint8'), meta);
            %
            %     % 3. Empty placeholder (no data yet)
            %     lbl = core.MibLabels63();
            %     % lbl.exists == false
            %

            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end

            % init the class using core.MibImage and forcing the type to be labels63
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
            obj.maskFilename = 'Mask_none.mask';
        end
    end
end
