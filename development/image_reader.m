% ImageLoaderFactory
% ├─ createLoader(filename, options)
% │   ├─ Detect format (extension + file magic bytes)
% │   └─ Return format-specific loader instance
% │
% ├─ FormatLoaders/
% │   ├─ ImageLoaderBase (abstract)
% │   │   ├─ validateOptions()
% │   │   ├─ getMetadata() [template method]
% │   │   ├─ getImages() [template method]
% │   │   └─ Shared utilities (waitbar, error handling)
% │   │
% │   ├─ ImageLoaderTIF < ImageLoaderBase
% │   ├─ ImageLoaderHDF5 < ImageLoaderBase
% │   ├─ ImageLoaderBioFormats < ImageLoaderBase
% │   ├─ ImageLoaderNRRD < ImageLoaderBase
% │   ├─ ImageLoaderZarr < ImageLoaderBase
% │   ├─ ImageLoaderAmiraMesh < ImageLoaderBase
% │   └─ ImageLoaderMRC < ImageLoaderBase
% │
% └─ ImageMetadataSchema
%     ├─ REQUIRED_KEYS
%     ├─ validateRequired()
%     └─ getOpt()
% 


% +io/
% ├─ loadImages.m                 (existing, now orchestrator)
% ├─ getImageMetadata.m           (simplified, delegates to loaders)
% ├─ getImages.m                  (simplified, delegates to loaders)
% ├─ imageMetadata.m              (schema validation)
% │
% ├─ @ImageLoaderFactory/
% │   └─ ImageLoaderFactory.m     (NEW - routing, format detection)
% │
% ├─ @ImageLoaderBase/
% │   └─ ImageLoaderBase.m        (NEW - abstract base class)
% │
% └─ @Loaders/                    (NEW - format-specific implementations)
% ├─ @ImageLoaderTIF/
% │   └─ ImageLoaderTIF.m
% ├─ @ImageLoaderHDF5/
% │   └─ ImageLoaderHDF5.m
% ├─ @ImageLoaderBioFormats/
% │   └─ ImageLoaderBioFormats.m
% ├─ @ImageLoaderNRRD/
% │   └─ ImageLoaderNRRD.m
% ├─ @ImageLoaderZarr/
% │   └─ ImageLoaderZarr.m
% ├─ @ImageLoaderAmiraMesh/
% │   └─ ImageLoaderAmiraMesh.m
% └─ @ImageLoaderMRC/
% └─ ImageLoaderMRC.m

