classdef MibLabels63 < core.MibImage 
    % classdef MibLabels63 < MibImage 
    % memory optimized label class of MIB3 capable to encode 63 materials,
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
            % function obj = MibLabels63(img, meta)
            % constructor of MibLabels class, inherits properties and
            % methods of MibImage
            %
            % Parameters:
            % img: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e []

            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end

            % init the class using core.MibImage and forcing the type to be labels63
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
            obj.maskFilename = 'Mask_none.mask';
        end
    end
end
