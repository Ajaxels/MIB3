classdef subClass < mainClass
    %SUBCLASS Summary of this class goes here
    %   Detailed explanation goes here

    properties
        Property2
    end

    methods
        function obj = subClass(inputArg1, inputArg2)
            %SUBCLASS Construct an instance of this class
            %   Detailed explanation goes here
            obj.Property2 = inputArg1 + inputArg2;
        end

        function outputArg = method1(obj,inputArg)
            %METHOD1 Summary of this method goes here
            %   Detailed explanation goes here
            outputArg = obj.Property2 + inputArg;
        end
    end
end