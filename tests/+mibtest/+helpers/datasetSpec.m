function spec = datasetSpec(name)
% DATASETSPEC - Return download/cache spec for a named real-data test dataset.
%
% Specs extracted from homeExamples_Callback.m. Keep in one place so
% cachedRawDataset, hasTestData, and ExampleDataFixture all agree.
%
% Syntax:
%   spec = mibtest.helpers.datasetSpec('Trypanosoma')
%   spec = mibtest.helpers.datasetSpec('Huh7')
%
% Output fields:
%   .imageUrl      - direct download URL for raw image bytes (uint8)
%   .labelsUrl     - direct download URL for raw labels bytes (uint8)
%   .imageDims     - [H W D C] reshape target for image
%   .labelsDims    - [H W D]   reshape target for labels
%   .materialNames - cell of material name strings
%   .pixSize       - struct with x/y/z voxel size in um
%   .cacheDir      - local cache directory (from env or LOCALAPPDATA)

switch name
    case 'Trypanosoma'
        spec.imageUrl      = 'http://mib.helsinki.fi/tutorials/datasets/SBEM_Trypanosoma.raw';
        spec.labelsUrl     = 'http://mib.helsinki.fi/tutorials/datasets/Labels_SBEM_Trypanosoma.raw';
        spec.imageDims     = [887 813 171 1];
        spec.labelsDims    = [887 813 171];
        spec.materialNames = {'Nuclei'; 'Mito'; 'Vesicles'; 'LD'; 'ER'; 'Cytoplasm'};
        spec.pixSize       = struct('x', 0.0140193, 'y', 0.0140193, 'z', 0.03);
    case 'Huh7'
        spec.imageUrl      = 'http://mib.helsinki.fi/tutorials/datasets/SBEM_Huh7.raw';
        spec.labelsUrl     = 'http://mib.helsinki.fi/tutorials/datasets/Labels_SBEM_Huh7.raw';
        spec.imageDims     = [372 521 75 1];
        spec.labelsDims    = [372 521 75];
        spec.materialNames = {'LD'; 'NE'; 'ER'; 'Mito'};
        spec.pixSize       = struct('x', 0.013, 'y', 0.013, 'z', 0.030);
    otherwise
        error('mibtest:datasetSpec:unknownDataset', ...
            'Unknown dataset "%s". Valid names: Trypanosoma, Huh7', name);
end

spec.cacheDir = getenv('MIB3_TEST_DATA_DIR');
if isempty(spec.cacheDir)
    spec.cacheDir = fullfile(getenv('LOCALAPPDATA'), 'MIB3', 'testData');
end
end
