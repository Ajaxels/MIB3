classdef AmiraMeshRleTest < matlab.unittest.TestCase
% AMIRAMESHRLETEST - HxByteRLE compression of Amira Mesh files (image, labels, mask).
%
% Covers the MEX pair io.AmiraMesh.hxByteRleEncode / hxByteRleDecode and the writers and
% readers that use them:
%   codec           - encoder output decodes (MEX and an independent MATLAB decoder) to the
%                     input bytes; packet edge cases (runs of 2, 127, 128, 255); size bound
%   image           - 'Amira Mesh binary RLE compression (*.am)' round trip, uint8/uint16,
%                     1 and 3 channels, partial loading (depth_start/step)
%   labels          - 'Amira mesh binary RLE compression (*.am)' round trip, uint8/uint16
%   word RLE        - uint16 labels with word-sized RLE packets, as MIB2 laid them out,
%                     still load
%   header          - the patched size field matches the data section and parses

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function codecMatchesReferenceDecoder(testCase)
            rng(11, 'twister');
            runLengths = [1 2 3 126 127 128 254 255 256 1 2 1 1];
            runs = repelem(uint8(mod(1:numel(runLengths), 250) + 1), runLengths);
            inputs = {uint8([]), uint8(7), uint8([1 2]), uint8([4 4]), runs, ...
                uint8(repmat([1 2 2 3 4 4 5], 1, 60)), uint8(randi(255, 1, 1000)), ...
                uint8(randi(3, 1, 5000)), uint16(randi(65535, 37, 11)), int16(randi([-2 2], 50, 50))};
            for k = 1:numel(inputs)
                block = inputs{k};
                expectedBytes = typecast(block(:), 'uint8');
                encoded = io.AmiraMesh.hxByteRleEncode(block);
                testCase.verifyClass(encoded, 'uint8');
                testCase.verifyLessThanOrEqual(numel(encoded), ...
                    numel(expectedBytes) + floor(numel(expectedBytes)/127) + 1, ...
                    sprintf('input %d exceeds the size bound', k));
                testCase.verifyEqual(AmiraMeshRleTest.referenceDecode(encoded, numel(expectedBytes)), ...
                    expectedBytes(:), sprintf('reference decode of input %d', k));
                testCase.verifyEqual(io.AmiraMesh.hxByteRleDecode(encoded, numel(expectedBytes)), ...
                    expectedBytes(:), sprintf('MEX decode of input %d', k));
            end
        end

        function codecRandomStress(testCase)
            % mixes of short and long runs - the pattern that once overran the output buffer
            rng(12, 'twister');
            for trial = 1:200
                blockSize = [randi(40) randi(40)];
                block = uint8(randi(randi(4), blockSize));
                block(rand(blockSize) < 0.3) = 7;
                expectedBytes = block(:);
                encoded = io.AmiraMesh.hxByteRleEncode(block);
                testCase.assertLessThanOrEqual(numel(encoded), ...
                    numel(expectedBytes) + floor(numel(expectedBytes)/127) + 1);
                testCase.assertEqual(io.AmiraMesh.hxByteRleDecode(encoded, numel(expectedBytes)), expectedBytes);
            end
        end

        function decoderRejectsCorruptStream(testCase)
            encoded = io.AmiraMesh.hxByteRleEncode(uint8(1:200));
            testCase.verifyError(@() io.AmiraMesh.hxByteRleDecode(encoded(1:end-5), 200), ...
                'MIB:hxByteRleDecode:corrupt');
            testCase.verifyError(@() io.AmiraMesh.hxByteRleDecode(encoded, 150), ...
                'MIB:hxByteRleDecode:corrupt');
            testCase.verifyError(@() io.AmiraMesh.hxByteRleDecode(encoded, 250), ...
                'MIB:hxByteRleDecode:corrupt');
        end

        function imageUint8GrayscaleRoundtrip(testCase)
            rng(13, 'twister');
            data = uint8(randi(4, [33 47 5 1 1]));
            data(5:20, :, 2) = 0;
            loaded = testCase.saveAndLoadImage(data);
            testCase.verifyEqual(loaded, data);
        end

        function imageUint16MultichannelRoundtrip(testCase)
            rng(14, 'twister');
            data = uint16(randi(65535, [21 30 4 3 1]));
            data(:, 1:10, :, 2) = 1000;
            loaded = testCase.saveAndLoadImage(data);
            testCase.verifyEqual(loaded, data);
        end

        function imagePartialLoading(testCase)
            rng(15, 'twister');
            data = uint8(randi(255, [16 18 9 2 1]));
            [~, outFile] = testCase.saveAndLoadImage(data);
            loadOptions = struct('depth_start', 2, 'depth_end', 8, 'depth_step', 3, ...
                'xy_step', 1, 'resizeMethod', 'nearest', 'verbose', false);
            loaded = io.AmiraMesh.amiraMesh2bitmap(outFile, loadOptions);
            testCase.verifyEqual(loaded, data(:, :, 2:3:8, :));
        end

        function imageHeaderSizeFieldIsPatched(testCase)
            rng(16, 'twister');
            data = uint8(randi(3, [40 40 3 1 1]));
            [~, outFile] = testCase.saveAndLoadImage(data);
            fid = fopen(outFile, 'r');
            fileText = char(fread(fid, inf, '*uint8')');   % one char per byte, unlike fileread
            fclose(fid);
            sizeToken = regexp(fileText, 'Lattice \{ byte Data \} @1\(HxByteRLE,(\d+)\) *\n', 'tokens', 'once');
            testCase.assertNotEmpty(sizeToken, 'Lattice line with the RLE size');
            dataStart = strfind(fileText, sprintf('\n@1\n'));
            dataBytes = dir(outFile).bytes - (dataStart(end) + 3) - 1;   % trailing newline
            testCase.verifyEqual(str2double(sizeToken{1}), dataBytes);
            [~, ~, dimensions] = io.AmiraMesh.getAmiraMeshHeader(outFile);
            testCase.verifyEqual(dimensions(1:2), [40 40]);
        end

        function labelsUint8Roundtrip(testCase)
            rng(17, 'twister');
            labels = uint8(imresize(randi(4, 6, 6, 'uint8'), [60 50], 'nearest'));
            labels = repmat(labels, 1, 1, 4);
            loaded = testCase.saveAndLoadLabels(labels, 'Amira mesh binary RLE compression (*.am)');
            testCase.verifyEqual(loaded, labels);
        end

        function labelsUint16Roundtrip(testCase)
            rng(18, 'twister');
            labels = uint16(randi(700, [25 31 3]));
            labels(1:10, :, :) = 0;
            loaded = testCase.saveAndLoadLabels(labels, 'Amira mesh binary RLE compression (*.am)');
            testCase.verifyEqual(loaded, labels);
        end

        function legacyFormatNameStillSaves(testCase)
            labels = uint8(repmat(magic(8) > 30, 1, 1, 2));
            loaded = testCase.saveAndLoadLabels(labels, 'Amira mesh binary RLE compression SLOW (*.am)');
            testCase.verifyEqual(loaded, labels);
        end

        function wordRleLabelsLoad(testCase)
            % MIB2 wrote uint16 RLE labels with packets of 16-bit words and counted words in
            % the header; the reader recognises them by the length of the data section
            tempFolder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            rng(19, 'twister');
            labels = uint16(randi(400, [20 23 3]));
            labels(1:3, :, 1) = 300;    % a run of 69 equal words at the start (x fastest)
            filename = fullfile(tempFolder.Folder, 'word_rle.am');
            AmiraMeshRleTest.writeWordRleLabels(filename, labels);
            loaded = io.AmiraMesh.amiraLabels2bitmap(filename);
            testCase.verifyEqual(loaded, labels);
        end
    end

    methods (Access = private)

        function [loaded, outFile] = saveAndLoadImage(testCase, data)
            tempFolder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'image_rle.am');
            formatName = 'Amira Mesh binary RLE compression (*.am)';
            saver = io.SaverFactory.create(formatName);
            saveOptions = struct('Format', formatName, 'layerType', 'image', ...
                'showWaitbar', false, 'silent', true, 'overwrite', true);
            metadata = struct('colorType', 'grayscale', 'lutColors', repmat([1 1 1], size(data, 4), 1), ...
                'dataClass', class(data), 'maxInt', double(intmax(class(data))), ...
                'pixSize', struct('x', 1, 'y', 1, 'z', 1, 'units', 'um', 't', 1, 'tunits', 's'));
            if size(data, 4) > 1; metadata.colorType = 'truecolor'; end
            fnOut = saver.save(data, metadata, outFile, saveOptions);
            testCase.assertEqual(fnOut, outFile);
            loaded = io.AmiraMesh.amiraMesh2bitmap(outFile, struct('verbose', false));
        end

        function loaded = saveAndLoadLabels(testCase, labels, formatName)
            tempFolder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'labels_rle.am');
            saver = io.SaverFactory.create(formatName);
            saveOptions = struct('Format', formatName, 'layerType', 'labels', ...
                'showWaitbar', false, 'silent', true, 'overwrite', true);
            numMaterials = max(1, double(max(labels(:))));
            metadata = struct('materialNames', {arrayfun(@(k) sprintf('M%d', k), 1:numMaterials, 'UniformOutput', false)}, ...
                'materialColors', rand(numMaterials, 3), ...
                'pixSize', struct('x', 1, 'y', 1, 'z', 1, 'units', 'um', 't', 1, 'tunits', 's'), ...
                'boundingBox', [0 1 0 1 0 1]);
            fnOut = saver.save(labels, metadata, outFile, saveOptions);
            testCase.assertEqual(fnOut, outFile);
            loaded = io.AmiraMesh.amiraLabels2bitmap(outFile);
        end
    end

    methods (Static, Access = private)

        function decoded = referenceDecode(stream, numBytes)
            % plain MATLAB HxByteRLE decoder, independent of the MEX file
            decoded = zeros(numBytes, 1, 'uint8');
            inIndex = 1;
            outIndex = 1;
            while inIndex <= numel(stream)
                control = double(stream(inIndex));
                count = bitand(control, 127);
                if bitand(control, 128)
                    decoded(outIndex:outIndex+count-1) = stream(inIndex+1:inIndex+count);
                    inIndex = inIndex + count + 1;
                else
                    decoded(outIndex:outIndex+count-1) = stream(inIndex+1);
                    inIndex = inIndex + 2;
                end
                outIndex = outIndex + count;
            end
        end

        function writeWordRleLabels(filename, labels)
            % uint16 labels as MIB2 laid them out: header as bitmap2amiraLabels, packets made
            % of whole words, size field counting words
            values = permute(labels, [2 1 3]);
            values = values(:);
            runEnd = find(values ~= values(1), 1) - 1;
            stream = [uint16(runEnd); values(1)];               % one repeat packet
            for chunkStart = runEnd + 1:127:numel(values)       % literal packets for the rest
                chunk = values(chunkStart:min(chunkStart + 126, numel(values)));
                stream = [stream; uint16(128 + numel(chunk)); chunk]; %#ok<AGROW>
            end
            fid = fopen(filename, 'w');
            fprintf(fid, '# AmiraMesh BINARY-LITTLE-ENDIAN 2.1\n\n\n');
            fprintf(fid, 'define Lattice %d %d %d\n\n', size(labels,2), size(labels,1), size(labels,3));
            fprintf(fid, 'Parameters {\n');
            fprintf(fid, '    Content "%dx%dx%d ushort, uniform coordinates",\n', size(labels,2), size(labels,1), size(labels,3));
            fprintf(fid, '    CoordType "uniform"\n');
            fprintf(fid, '}\n\n');
            fprintf(fid, 'Lattice { ushort Labels } @1(HxByteRLE,%d)\n\n', numel(stream));
            fprintf(fid, '# Data section follows\n');
            fprintf(fid, '@1\n');
            fwrite(fid, stream, 'uint16', 0, 'ieee-le');
            fprintf(fid, '\n');
            fclose(fid);
        end
    end
end
