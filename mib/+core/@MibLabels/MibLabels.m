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
            % constructor of MibLabels class, inherits properties and
            % methods of MibImage
            %
            % Parameters:
            % img: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e []
            
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
        end
    end
end