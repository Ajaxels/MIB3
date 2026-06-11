classdef PureUtilsTest < matlab.unittest.TestCase
% PUREUTILSTEST - Unit tests for pure (no-GUI) utility functions.
%
% Covers:
%   utils.updatePixSizeAndResolution  — pixSize derivation from img_info
%   utils.updateBatchOptCombineFields_Shared — batch-opt merge semantics

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % utils.updatePixSizeAndResolution
        % -----------------------------------------------------------------

        function updatePixSize_fromBoundingBoxInDescription(testCase)
            % BoundingBox string → pixSize derived from extent / (dims-1)
            % H=11 W=11 D=6 with BB [0 1 0 1 0 0.5] → pixSize = [0.1 0.1 0.1]
            imgInfo = core.MibImage.initializeImgInfo();
            imgInfo{'Width'}            = 11;
            imgInfo{'Height'}           = 11;
            imgInfo{'Depth'}            = 6;
            imgInfo{'ImageDescription'} = 'BoundingBox 0.00000 1.00000 0.00000 1.00000 0.00000 0.50000 ';
            imgInfo{'XResolution'}      = 1;
            imgInfo{'YResolution'}      = 1;
            imgInfo{'ResolutionUnit'}   = 'cm';

            pixSize.x = 1; pixSize.y = 1; pixSize.z = 1;
            pixSize.t = 1; pixSize.units = 'um'; pixSize.tunits = 's';

            [~, updatedPixSize] = utils.updatePixSizeAndResolution(imgInfo, pixSize);

            testCase.verifyEqual(updatedPixSize.x, 0.1, 'AbsTol', 1e-9);
            testCase.verifyEqual(updatedPixSize.y, 0.1, 'AbsTol', 1e-9);
            testCase.verifyEqual(updatedPixSize.z, 0.1, 'AbsTol', 1e-9);
        end

        function updatePixSize_fromProvidedPixSizeWritesBoundingBox(testCase)
            % No BoundingBox in description, no XResolution:
            % function should write BoundingBox to ImageDescription from pixSize.
            imgInfo = core.MibImage.initializeImgInfo();
            imgInfo{'Width'}            = 10;
            imgInfo{'Height'}           = 10;
            imgInfo{'Depth'}            = 5;
            imgInfo{'ImageDescription'} = '';
            imgInfo{'XResolution'}      = [];
            imgInfo{'YResolution'}      = [];

            pixSize.x = 0.05; pixSize.y = 0.05; pixSize.z = 0.20;
            pixSize.t = 1; pixSize.units = 'um'; pixSize.tunits = 's';

            [updatedInfo, ~] = utils.updatePixSizeAndResolution(imgInfo, pixSize);

            description = updatedInfo{'ImageDescription'};
            if iscell(description); description = description{1}; end
            testCase.verifySubstring(description, 'BoundingBox');
        end

        function updatePixSize_emptyImgInfoReturnsImmediately(testCase)
            % Passing [] as img_info should return unchanged without error.
            pixSize.x = 0.01; pixSize.y = 0.01; pixSize.z = 0.05;
            pixSize.t = 1; pixSize.units = 'um'; pixSize.tunits = 's';

            [outInfo, outPixSize, result] = utils.updatePixSizeAndResolution([], pixSize);

            testCase.verifyEmpty(outInfo);
            testCase.verifyEqual(outPixSize.x, pixSize.x);
            testCase.verifyEqual(result, 1);
        end

        % -----------------------------------------------------------------
        % utils.updateBatchOptCombineFields_Shared
        % -----------------------------------------------------------------

        function combineFields_dropdownPreservesOptionsList(testCase)
            % Dropdown stored as {selectedItem, {item1, item2, ...}}
            % Input supplies only the selected item as {newItem}.
            % Result: selected item updated, options list preserved.
            BatchOpt.Mode = {'Add', {'Add', 'Subtract', 'Multiply'}};
            BatchOptIn.Mode = {'Subtract'};

            merged = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);

            testCase.verifyEqual(merged.Mode{1}, 'Subtract');
            testCase.verifyEqual(merged.Mode{2}, {'Add', 'Subtract', 'Multiply'});
        end

        function combineFields_spinner3cellUpdatesValueOnly(testCase)
            % Spinner stored as {value, [min max], 'on'}.
            % Input supplies {newValue}.  Limits and rounding flag are preserved.
            BatchOpt.MyParam = {5, [1 100], 'on'};
            BatchOptIn.MyParam = {42};

            merged = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);

            testCase.verifyEqual(merged.MyParam{1}, 42);
            testCase.verifyEqual(merged.MyParam{2}, [1 100]);   % limits preserved
            testCase.verifyEqual(merged.MyParam{3}, 'on');       % rounding flag preserved
        end

        function combineFields_plainNumericUpdated(testCase)
            BatchOpt.Threshold = 0.5;
            BatchOptIn.Threshold = 0.8;

            merged = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);

            testCase.verifyEqual(merged.Threshold, 0.8);
        end

        function combineFields_logicalFieldUpdated(testCase)
            BatchOpt.showWaitbar = true;
            BatchOptIn.showWaitbar = false;

            merged = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);

            testCase.verifyFalse(merged.showWaitbar);
        end

        function combineFields_unknownFieldAddedFromInput(testCase)
            % Fields present in input but absent from BatchOpt are added.
            BatchOpt.existingField = 1;
            BatchOptIn.newField = 99;

            merged = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);

            testCase.verifyTrue(isfield(merged, 'newField'));
            testCase.verifyEqual(merged.newField, 99);
        end

    end
end
