classdef MibLabels63 < core.MibImage 
    % MIBLABELS63 - memory optimized packed label class of MIB3: material index,
    %
    % mask and selection in one container - uint8 (63 materials) or uint16
    % (16383-object instance model); see setLayout for the bit layout.
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
        % maximal number of materials available in this model type: 63 for the
        % uint8 layout, 16383 for the uint16 layout (see setLayout)
        objects3D = false
        % instance models (uint16 layout, maxMaterials 16383) only: true when one
        % index names one object through the whole volume, false when the numbering
        % restarts on every slice. Mirrors core.MibLabels.objects3D
    end

    properties (SetAccess = protected)
        % --- packed bit layout, set together by setLayout ---
        containerClass = 'uint8'
        % class of obj.data: 'uint8' (63 materials) or 'uint16' (16383 instances)
        materialMask = 63
        % bitand(data, materialMask) extracts the material index: 63 or 16383
        maskBit = 7
        % bit position of the mask flag: 7 (uint8) or 15 (uint16)
        selectionBit = 8
        % bit position of the selection flag: 8 (uint8) or 16 (uint16)
        maskValue = 64
        % value of the mask flag, 2^(maskBit-1): 64 or 16384
        selectionValue = 128
        % value of the selection flag, 2^(selectionBit-1): 128 or 32768
        flagsMask = 192
        % maskValue + selectionValue; bitand(data, flagsMask) keeps mask+selection
        %
        % These are doubles on purpose: bitand(data, doubleScalar) runs at the speed
        % of a literal, an integer scalar is ~35% slower. Multiplication is the
        % reverse - data*doubleScalar is ~70% slower than a literal on a full
        % volume - so a flag write multiplies by cast(maskValue, 'like', data).
    end

    methods
        % declaration of methods in external files
        dataset = getData63(obj, type, orient, materialIndex, options)        % get dataset
        result = setData63(obj, dataset, type, orient, materialIndex, options)        % update contents of the class
        result = countMaterials(obj)                 % calculate and update materialsCount from materialNames or packed pixel data; call after load/import
        renameMaterial(obj, index, newName)          % rename one or all materials in the model metadata
        insertMaterial(obj, index, name, wb)     % insert a material at the specified position: shifts bit-packed pixel data and updates name/colour/materialsCount
        swapMaterials(obj, index1, index2)     % swap material names and colours between two positions
        reorderMaterials(obj, newOrder)        % reorder material names and colours according to newOrder
        fnOut = save(obj, filename, options)   % save label data to file; overrides MibImage.save() to use getData63() for correct bit-unpacking

        function obj = MibLabels63(img, meta)
            % MIBLABELS63 - Constructor of MibLabels63 - memory-optimised label storage.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibLabels63()
            %       obj = MibLabels63(img)
            %       obj = MibLabels63(img, meta)
            %
            % Initializes a memory-optimised segmentation label container that packs up to
            % 63 materials, mask, and selection into a single uint8 array (uint16 input
            % selects the 16383 layout: bits 1-14 index, 15 mask, 16 selection):
            % bits 1-6 = material index, bit 7 = mask, bit 8 = selection.
            % Inherits all properties and methods from ``core.MibImage``.
            %
            % **Data layout:** ``[H, W, Z, 1, T]`` - single color channel, with depth
            % in dimension 3. MibLabels63 does NOT apply the ``[H,W,C]→[H,W,1,C]``
            % permutation that MibImage uses for colour images.
            %
            % Input Arguments:
            %   - **img** - *(optional)* [uint8 array] 2-D to 5-D packed data, or ``[]``.
            %     Dimension 3 is always treated as depth (Z), never as color:
            %
            %     - ``[]`` - empty placeholder; ``obj.exists = false``
            %     - ``[H, W]`` - single 2-D packed label map
            %     - ``[H, W, Z]`` - 3-D packed label volume (Z slices)
            %     - ``[H, W, Z, 1, T]`` - full 5-D form (preferred for clarity)
            %
            %   - **meta** - *(optional)* [dictionary] metadata from
            %     ``core.MibImage.initializeImgInfo()``. Pass ``[]`` to use defaults.
            %
            % After construction, ALL dimension properties are set from the actual array size:
            % ``obj.height``, ``obj.width``, ``obj.depth``, ``obj.colors`` (always 1),
            % ``obj.time``, ``obj.dim_yxzct``, ``obj.maxInt``, ``obj.dataClass``.
            %
            % **Example 1** - create 3-D packed label volume from data:
            %
            %   .. code-block:: matlab
            %
            %      rawModel = uint8(zeros(254, 378, 3));  % [H,W,Z]
            %      meta = core.MibImage.initializeImgInfo( ...
            %          'pixSize', obj.image.pixSize, ...
            %          'Height', 254, 'Width', 378, 'Depth', 3, 'Time', 1, 'Colors', 1);
            %      lbl = core.MibLabels63(rawModel, meta);
            %      % lbl.depth == 3, lbl.colors == 1
            %
            % **Example 2** - create fresh empty allocation matching current image:
            %
            %   .. code-block:: matlab
            %
            %      dims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];
            %      meta = core.MibImage.initializeImgInfo( ...
            %          'pixSize', obj.image.pixSize, ...
            %          'Height', dims(1), 'Width', dims(2), 'Depth', dims(3), 'Time', dims(5));
            %      lbl = core.MibLabels63(zeros(dims, 'uint8'), meta);
            %
            % **Example 3** - create empty placeholder:
            %
            %   .. code-block:: matlab
            %
            %      lbl = core.MibLabels63();
            %      % lbl.exists == false
            %

            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end

            % init the class using core.MibImage and forcing the type to be labels63
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
            obj.maskFilename = 'Mask_none.mask';
            if isa(img, 'uint16'); obj.setLayout('uint16'); end
        end

        function setLayout(obj, containerClass)
            % SETLAYOUT - Select the packed bit layout of the container.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.setLayout('uint8')    % 63 materials, mask bit 7, selection bit 8
            %       obj.setLayout('uint16')   % 16383 instances, mask bit 15, selection bit 16
            %
            % Sets ``containerClass``, ``materialMask``, ``maskBit``, ``selectionBit``,
            % ``maskValue``, ``selectionValue``, ``flagsMask`` and ``maxMaterials``
            % together, so the bit constants can never disagree. Every packed read
            % or write (``getData63``/``setData63``, the ``MibDataset.move*`` layer
            % operations, ``core.MibBigDataLabels``) takes its constants from these
            % properties instead of literals.
            %
            % The layout only describes ``obj.data``; it does not convert it. The
            % constructor calls it for ``uint16`` input, ``core.MibBigDataLabels``
            % calls it from ``createStore``/``openStore``. Converting existing data
            % between layouts is ``core.MibDataset.convertModel``'s job.
            %
            % Input Arguments:
            %   - **containerClass** - ``'uint8'`` or ``'uint16'``
            switch containerClass
                case 'uint8'
                    bits = 8;
                case 'uint16'
                    bits = 16;
                otherwise
                    error('MibLabels63:setLayout:badClass', ...
                        'Packed labels support uint8 or uint16, not %s', containerClass);
            end
            obj.containerClass = containerClass;
            obj.maskBit        = bits - 1;
            obj.selectionBit   = bits;
            obj.maskValue      = 2^(bits - 2);
            obj.selectionValue = 2^(bits - 1);
            obj.flagsMask      = obj.maskValue + obj.selectionValue;
            obj.materialMask   = obj.maskValue - 1;
            obj.maxMaterials   = obj.materialMask;
        end
    end
end
