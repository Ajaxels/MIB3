classdef PureUtilsTest < matlab.unittest.TestCase
% PUREUTILSTEST - Unit tests for pure (no-GUI) utility functions.
%
% Covers:
%   utils.updatePixSizeAndResolution  — pixSize derivation from img_info
%   utils.updateBatchOptCombineFields_Shared — batch-opt merge semantics
%   utils.calculatePixSizes           — resolution → physical pixel size
%   utils.calculateResolution         — physical pixel size → resolution
%   MibDataset.convertPixelsToUnits / convertUnitsToPixels — round-trip

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

        % -----------------------------------------------------------------
        % utils.calculatePixSizes
        % -----------------------------------------------------------------

        function calculatePixSizes_knownValue_1pixPerInch(testCase)
            % 1 pixel/inch = 25400 µm/pixel
            pixSize = utils.calculatePixSizes([1 1], 'Inch', 'um');

            testCase.verifyEqual(pixSize.x, 25400.0, 'AbsTol', 1e-6);
            testCase.verifyEqual(pixSize.y, 25400.0, 'AbsTol', 1e-6);
        end

        % -----------------------------------------------------------------
        % utils.calculateResolution
        % -----------------------------------------------------------------

        function calculateResolution_knownValue_25400umPerPix(testCase)
            % 25400 µm/pixel → 1 pixel/inch
            pixSizeIn.x     = 25400;
            pixSizeIn.y     = 25400;
            pixSizeIn.units = 'um';

            resolution = utils.calculateResolution(pixSizeIn);

            testCase.verifyEqual(resolution(1), 1.0, 'AbsTol', 1e-9);
            testCase.verifyEqual(resolution(2), 1.0, 'AbsTol', 1e-9);
        end

        % -----------------------------------------------------------------
        % utils.normalizeUnits
        % -----------------------------------------------------------------

        function normalizeUnits_longFormsMapToShort(testCase)
            % Long unit spellings (as carried by zarr/BigData pixSize) map to
            % MIB's canonical short codes.
            testCase.verifyEqual(utils.normalizeUnits('micrometers'), 'um');
            testCase.verifyEqual(utils.normalizeUnits('microns'),     'um');
            testCase.verifyEqual(utils.normalizeUnits('nanometers'),  'nm');
            testCase.verifyEqual(utils.normalizeUnits('millimeters'), 'mm');
            testCase.verifyEqual(utils.normalizeUnits('meters'),      'm');
            testCase.verifyEqual(utils.normalizeUnits('centimeters'), 'cm');
        end

        function normalizeUnits_shortFormsIdempotent(testCase)
            % Already-canonical codes are returned unchanged.
            testCase.verifyEqual(utils.normalizeUnits('um'), 'um');
            testCase.verifyEqual(utils.normalizeUnits('nm'), 'nm');
            testCase.verifyEqual(utils.normalizeUnits('mm'), 'mm');
        end

        function normalizeUnits_pixelsAndUnknownPreserved(testCase)
            % 'pixels' (no physical size) and unrecognised strings are kept as-is
            % (lower-cased) so downstream callers fall back to their defaults.
            testCase.verifyEqual(utils.normalizeUnits('pixels'),  'pixels');
            testCase.verifyEqual(utils.normalizeUnits('furlong'), 'furlong');
        end

        function calculateResolution_micrometersAliasMatchesUm(testCase)
            % A zarr dataset carries units='micrometers'; resolution must match
            % the equivalent 'um' result instead of falling back to 72 dpi.
            psLong.x  = 0.5; psLong.y  = 0.5; psLong.units = 'micrometers';
            psShort.x = 0.5; psShort.y = 0.5; psShort.units = 'um';

            resLong  = utils.calculateResolution(psLong);
            resShort = utils.calculateResolution(psShort);

            testCase.verifyEqual(resLong, resShort, 'AbsTol', 1e-9);
            testCase.verifyGreaterThan(resLong(1), 72);   % not the fallback
        end

        % -----------------------------------------------------------------
        % calculatePixSizes / calculateResolution round-trip
        % -----------------------------------------------------------------

        function calculatePixSizesAndResolution_roundTrip_um(testCase)
            % Start with an arbitrary pixSize, convert to resolution, then back.
            pixSizeIn.x     = 0.065;
            pixSizeIn.y     = 0.065;
            pixSizeIn.units = 'um';

            resolution = utils.calculateResolution(pixSizeIn);
            pixSizeOut = utils.calculatePixSizes(resolution, 'Inch', 'um');

            testCase.verifyEqual(pixSizeOut.x, pixSizeIn.x, 'AbsTol', 1e-10);
            testCase.verifyEqual(pixSizeOut.y, pixSizeIn.y, 'AbsTol', 1e-10);
        end

        % -----------------------------------------------------------------
        % MibDataset.convertPixelsToUnits / convertUnitsToPixels round-trip
        % -----------------------------------------------------------------

        function convertPixelsToUnits_roundTrip_orientation3(testCase)
            % Pixel coords → physical units → pixel coords must be identity.
            % Round-trip is algebraically exact for any pixSize/bb combination.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            ds = mibModel.I{1};

            xPx = 5; yPx = 7; zPx = 3;
            [xU, yU, zU]       = ds.convertPixelsToUnits(xPx, yPx, zPx);
            [xPx2, yPx2, zPx2] = ds.convertUnitsToPixels(xU, yU, zU);

            testCase.verifyEqual(xPx2, xPx, 'AbsTol', 1e-9);
            testCase.verifyEqual(yPx2, yPx, 'AbsTol', 1e-9);
            testCase.verifyEqual(zPx2, zPx, 'AbsTol', 1e-9);
        end

        function convertUnitsToPixels_roundTrip_orientation3(testCase)
            % Physical unit coords → pixel coords → physical units must be identity.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            ds = mibModel.I{1};

            % Use physical coords within the dataset extent
            pixSize = ds.image.pixSize;
            xU = 3.0 * pixSize.x;
            yU = 4.0 * pixSize.y;
            zU = 2.0 * pixSize.z;

            [xPx, yPx, zPx]   = ds.convertUnitsToPixels(xU, yU, zU);
            [xU2, yU2, zU2]   = ds.convertPixelsToUnits(xPx, yPx, zPx);

            testCase.verifyEqual(xU2, xU, 'AbsTol', 1e-9);
            testCase.verifyEqual(yU2, yU, 'AbsTol', 1e-9);
            testCase.verifyEqual(zU2, zU, 'AbsTol', 1e-9);
        end

    end
end
