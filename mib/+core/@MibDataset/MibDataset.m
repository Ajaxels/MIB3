classdef MibDataset < matlab.mixin.Copyable    
    %MIBDATASET Summary of this class goes here
    %   Detailed explanation goes here

    properties
        img
        model
        mask
        selection
    end

    methods
        function obj = MibDataset()
            %MIBDATASET Construct an instance of this class
            %   Detailed explanation goes here
            
            files = dir(fullfile(fileparts(fileparts(which('mib3'))), 'mib\assets\icons\*.png'));
            fnIndex = round(rand*numel(files));

            obj.img = imread(fullfile(fileparts(fileparts(which('mib3'))), 'mib\assets\icons\', files(fnIndex).name));
        end

        function outputArg = getData(obj)
            %METHOD1 Summary of this method goes here
            %   Detailed explanation goes here
            outputArg = obj.img;
        end
    end
end