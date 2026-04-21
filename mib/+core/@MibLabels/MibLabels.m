classdef MibLabels < core.MibImage 
    % classdef MibLabels < MibImage 
    % a base label class of MIB3
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
        % been assigned — used by MibDataset.addMaterial to determine the
        % next available index without scanning the full dataset.
        % Updated by addMaterial (+1), removeMaterial (-N or recount),
        % squeezeMaterialLabels (recount), and createModel (initial value).
        maxMaterials = 255;   % can also be 127 (with negative part), 32767 (with negative part), 65535
        % maximal number of materials available in this model type
    end

    methods
        
        fnOut = save(obj, filename, options)        % Override of MibImage.save(); adds materialNames/materialColors/labelsVariable to metadata before dispatching to io.SaverFactory

        result = countMaterials(obj)                 % calculate and update materialsCount from materialNames or pixel data; call after load/import

        squeezeMaterialLabels(obj, wb)              % renumber all label indices to contiguous 1..N; for large model types after material deletion

        renameMaterial(obj, index, newName)          % rename one or all materials in the model metadata

        insertMaterial(obj, index, name, wb)     % insert a material at the specified position: shifts pixel data and updates name/colour/materialsCount

        swapMaterials(obj, index1, index2)     % swap material names and colours between two positions

        reorderMaterials(obj, newOrder)        % reorder material names and colours according to newOrder

        function obj = MibLabels(img, meta)
            % function obj = MibLabels(img, meta)
            % Constructor of MibLabels — segmentation label storage for
            % models with up to 255 (or 65535 / 4294967295) materials.
            % Inherits all properties and methods from core.MibImage.
            %
            % Data layout: [H, W, Z, 1, T] — single color channel, depth
            % in dimension 3.  MibLabels does NOT apply the [H,W,C]→[H,W,1,C]
            % permute that MibImage uses for colour images.
            %
            % Parameters:
            % img: [@em optional] 2-D to 5-D uint8/uint16/uint32 array, or [].
            %   Dim 3 is always treated as depth (Z), never as color.
            %   @li []              — empty placeholder; obj.exists = false
            %   @li [H, W]          — single 2-D label map
            %   @li [H, W, Z]       — 3-D label volume (Z slices)
            %   @li [H, W, Z, 1, T] — full 5-D form (preferred for clarity)
            % meta: [@em optional] metadata dictionary from
            %   core.MibImage.initializeImgInfo().  Pass [] to use defaults.
            %
            % After construction ALL dimension properties are set from the
            % actual array size via MibImage.initialize():
            %   obj.height, obj.width, obj.depth, obj.colors, obj.time,
            %   obj.dim_yxzct, obj.maxInt, obj.dataClass
            %
            % @b Examples:
            % @code
            % % 1. 3-D label volume, 3 slices
            % rawLabels = uint8(zeros(254, 378, 3));
            % meta = core.MibImage.initializeImgInfo( ...
            %     'pixSize', obj.image.pixSize, ...
            %     'Height', 254, 'Width', 378, 'Depth', 3, 'Time', 1, 'Colors', 1);
            % lbl = core.MibLabels(rawLabels, meta);
            % % lbl.depth == 3, lbl.colors == 1
            %
            % % 2. Empty placeholder
            % lbl = core.MibLabels();
            % % lbl.exists == false
            %
            % % 3. After construction, set maxMaterials for large models
            % lbl = core.MibLabels(rawLabels, meta);
            % lbl.maxMaterials = 65535;
            % @endcode
            
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
        end
    end
end