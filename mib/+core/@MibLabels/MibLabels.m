classdef MibLabels < core.MibImage 
    % MIBLABELS - a base label class of MIB3.
    %
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
        % number of materials currently in the model.  For small models
        % (63/255) this equals numel(materialNames).  For large models
        % (65535/4294967295) this is the highest material index that has
        % been assigned - used by MibDataset.addMaterial to determine the
        % next available index without scanning the full dataset.
        % Updated by addMaterial (+1), removeMaterial (-N or recount),
        % squeezeMaterialLabels (recount), and createModel (initial value).
        maxMaterials = 255;   % can also be 127 (with negative part), 32767 (with negative part), 65535
        % maximal number of materials available in this model type
    end

    methods
        % declaration of methods in external files
        fnOut = save(obj, filename, options)        % Override of MibImage.save(); adds materialNames/materialColors/labelsVariable to metadata before dispatching to io.SaverFactory
        result = countMaterials(obj)                 % calculate and update materialsCount from materialNames or pixel data; call after load/import
        squeezeMaterialLabels(obj, wb)              % renumber all label indices to contiguous 1..N; for large model types after material deletion
        renameMaterial(obj, index, newName)          % rename one or all materials in the model metadata
        insertMaterial(obj, index, name, wb)     % insert a material at the specified position: shifts pixel data and updates name/colour/materialsCount
        swapMaterials(obj, index1, index2)     % swap material names and colours between two positions
        reorderMaterials(obj, newOrder)        % reorder material names and colours according to newOrder

        function obj = MibLabels(img, meta)
            % MIBLABELS - Constructor of MibLabels - segmentation label storage.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibLabels()
            %       obj = MibLabels(img)
            %       obj = MibLabels(img, meta)
            %
            % Initializes a segmentation label container with up to 255 (or 65535 / 4294967295)
            % materials. Inherits all properties and methods from ``core.MibImage``.
            %
            % **Data layout:** ``[H, W, Z, 1, T]`` - single color channel, with depth
            % in dimension 3. MibLabels does NOT apply the ``[H,W,C]→[H,W,1,C]``
            % permutation that MibImage uses for colour images.
            %
            % Input Arguments:
            %   - **img** - *(optional)* [numeric array] 2-D to 5-D uint8/uint16/uint32, or ``[]``.
            %     Dimension 3 is always treated as depth (Z), never as color:
            %
            %     - ``[]`` - empty placeholder; ``obj.exists = false``
            %     - ``[H, W]`` - single 2-D label map
            %     - ``[H, W, Z]`` - 3-D label volume (Z slices)
            %     - ``[H, W, Z, 1, T]`` - full 5-D form (preferred for clarity)
            %
            %   - **meta** - *(optional)* [dictionary] metadata from
            %     ``core.MibImage.initializeImgInfo()``. Pass ``[]`` to use defaults.
            %
            % After construction, ALL dimension properties are set from the actual array size:
            % ``obj.height``, ``obj.width``, ``obj.depth``, ``obj.colors``, ``obj.time``,
            % ``obj.dim_yxzct``, ``obj.maxInt``, ``obj.dataClass``.
            %
            % **Example 1** - create 3-D label volume:
            %
            %   .. code-block:: matlab
            %
            %      rawLabels = uint8(zeros(254, 378, 3));
            %      meta = core.MibImage.initializeImgInfo( ...
            %          'pixSize', obj.image.pixSize, ...
            %          'Height', 254, 'Width', 378, 'Depth', 3, 'Time', 1, 'Colors', 1);
            %      lbl = core.MibLabels(rawLabels, meta);
            %      % lbl.depth == 3, lbl.colors == 1
            %
            % **Example 2** - create empty placeholder:
            %
            %   .. code-block:: matlab
            %
            %      lbl = core.MibLabels();
            %      % lbl.exists == false
            %
            % **Example 3** - create and set large model type:
            %
            %   .. code-block:: matlab
            %
            %      lbl = core.MibLabels(rawLabels, meta);
            %      lbl.maxMaterials = 65535;
            %
            
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
        end
    end
end
